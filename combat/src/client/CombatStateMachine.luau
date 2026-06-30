--!strict
-- CombatStateMachine — the heart of the client controller. It is a small,
-- explicit finite-state machine that drives the local feel of combat: combo
-- counting, the wind-up / active / recovery phases of each swing, blocking, and
-- the locked-out states (stun from a parry, recoil from a clash).
--
-- It owns NO Roblox instances and performs NO networking or animation itself.
-- Instead it exposes a set of callbacks the controller assigns; this keeps the
-- timing logic pure and trivially testable, and lets the ViewmodelController,
-- EffectsController and remotes plumbing stay decoupled.
--
-- States:
--   Idle      - neutral; may attack or raise a block
--   Windup    - swing anticipation; committed (cannot block-cancel)
--   Active    - blade is live; hitbox should be casting
--   Recovery  - end lag; the next attack may be buffered here
--   Blocking  - guard raised (holding F)
--   Stunned   - locked out after being perfect-parried
--   Recoil    - brief mutual lock-out after a clash

local CombatConfig = require(game:GetService("ReplicatedStorage").Combat.CombatConfig)

local State = {
	Idle = "Idle",
	Windup = "Windup",
	Active = "Active",
	Recovery = "Recovery",
	Blocking = "Blocking",
	Stunned = "Stunned",
	Recoil = "Recoil",
}

local CombatStateMachine = {}
CombatStateMachine.__index = CombatStateMachine
CombatStateMachine.State = State

export type Callbacks = {
	onStateChanged: ((new: string, old: string) -> ())?,
	onSwingStart: ((combo: number) -> ())?, -- enter Windup: play anim + send Swing intent
	onActiveStart: ((combo: number) -> ())?, -- enter Active: start the raycast hitbox
	onActiveEnd: ((combo: number) -> ())?, -- leave Active: stop the raycast hitbox
	onSwingEnd: ((combo: number) -> ())?, -- swing fully finished
	onBlockChanged: ((isBlocking: boolean) -> ())?,
	onLockChanged: ((locked: boolean) -> ())?, -- true while Stunned/Recoil
}

export type CombatStateMachine = typeof(setmetatable({} :: any, CombatStateMachine))

function CombatStateMachine.new(callbacks: Callbacks?): CombatStateMachine
	local self = setmetatable({
		state = State.Idle,
		combo = 0,
		_phaseTime = 0, -- time remaining in the current timed phase
		_sinceSwing = math.huge, -- time since the last swing ended (for combo reset)
		_blockHeld = false, -- raw F input state
		_bufferedAttack = false, -- attack pressed during Recovery
		_cb = (callbacks or {}) :: Callbacks,
	}, CombatStateMachine)
	return self :: any
end

function CombatStateMachine:_setState(newState: string)
	if newState == self.state then
		return
	end
	local old = self.state
	self.state = newState

	local wasLocked = (old == State.Stunned or old == State.Recoil)
	local isLocked = (newState == State.Stunned or newState == State.Recoil)
	if wasLocked ~= isLocked and self._cb.onLockChanged then
		self._cb.onLockChanged(isLocked)
	end
	if self._cb.onStateChanged then
		self._cb.onStateChanged(newState, old)
	end
end

function CombatStateMachine:isLocked(): boolean
	return self.state == State.Stunned or self.state == State.Recoil
end

-- Begin a fresh swing of the combo (or chain to the next hit).
function CombatStateMachine:_beginSwing()
	-- Reset the combo if we idled too long since the last hit, or finished it.
	if self._sinceSwing > CombatConfig.Combo.ResetWindow or self.combo >= CombatConfig.Combo.MaxHits then
		self.combo = 0
	end
	self.combo += 1
	self._sinceSwing = 0
	self._phaseTime = CombatConfig.Combo.Frames.Windup
	self:_setState(State.Windup)
	if self._cb.onSwingStart then
		self._cb.onSwingStart(self.combo)
	end
end

-- == Public input API =====================================================

-- Left click. Returns true if the attack was accepted (or buffered).
function CombatStateMachine:requestAttack(): boolean
	if self:isLocked() then
		return false
	end

	if self.state == State.Idle or self.state == State.Blocking then
		if self.state == State.Blocking then
			self:_dropBlock() -- attacking cancels the guard
		end
		self:_beginSwing()
		return true
	elseif self.state == State.Recovery then
		-- Buffer so the combo chains the instant recovery ends.
		self._bufferedAttack = true
		return true
	end
	-- Windup / Active are committed; ignore.
	return false
end

-- F key down/up.
function CombatStateMachine:setBlockHeld(held: boolean)
	self._blockHeld = held
	if held then
		-- You can only raise a guard from neutral or recovery.
		if self.state == State.Idle or self.state == State.Recovery then
			self:_raiseBlock()
		end
	else
		if self.state == State.Blocking then
			self:_dropBlock()
		end
	end
end

function CombatStateMachine:_raiseBlock()
	self:_setState(State.Blocking)
	if self._cb.onBlockChanged then
		self._cb.onBlockChanged(true)
	end
end

function CombatStateMachine:_dropBlock()
	if self._cb.onBlockChanged then
		self._cb.onBlockChanged(false)
	end
	if self.state == State.Blocking then
		self:_setState(State.Idle)
	end
end

function CombatStateMachine:isBlocking(): boolean
	return self.state == State.Blocking
end

-- Authoritative lock-outs pushed down from the server.
function CombatStateMachine:applyStun(duration: number)
	self:_cancelActiveSwing()
	self._bufferedAttack = false
	self._phaseTime = duration
	self:_setState(State.Stunned)
end

function CombatStateMachine:applyRecoil(duration: number)
	self:_cancelActiveSwing()
	self._bufferedAttack = false
	self._phaseTime = duration
	self:_setState(State.Recoil)
end

-- If a swing is interrupted mid-Active make sure the hitbox is closed.
function CombatStateMachine:_cancelActiveSwing()
	if self.state == State.Active and self._cb.onActiveEnd then
		self._cb.onActiveEnd(self.combo)
	end
end

-- == Per-frame tick =======================================================

function CombatStateMachine:update(dt: number)
	self._sinceSwing += dt

	local s = self.state
	if s == State.Idle then
		if self._sinceSwing > CombatConfig.Combo.ResetWindow then
			self.combo = 0
		end
		return
	end

	-- Blocking has no timer; it ends on input.
	if s == State.Blocking then
		return
	end

	self._phaseTime -= dt
	if self._phaseTime > 0 then
		return
	end

	-- Phase elapsed: advance the machine.
	if s == State.Windup then
		self._phaseTime = CombatConfig.Combo.Frames.Active
		self:_setState(State.Active)
		if self._cb.onActiveStart then
			self._cb.onActiveStart(self.combo)
		end
	elseif s == State.Active then
		if self._cb.onActiveEnd then
			self._cb.onActiveEnd(self.combo)
		end
		local recovery = CombatConfig.Combo.Frames.Recovery
		if self.combo >= CombatConfig.Combo.MaxHits then
			recovery += CombatConfig.Combo.Finisher.ExtraRecovery
		end
		self._phaseTime = recovery
		self:_setState(State.Recovery)
	elseif s == State.Recovery then
		if self._cb.onSwingEnd then
			self._cb.onSwingEnd(self.combo)
		end
		-- Consume a buffered attack to chain the combo.
		if self._bufferedAttack and self.combo < CombatConfig.Combo.MaxHits then
			self._bufferedAttack = false
			self:_beginSwing()
		else
			self._bufferedAttack = false
			self:_setState(State.Idle)
			-- Honour a still-held block coming out of recovery.
			if self._blockHeld then
				self:_raiseBlock()
			end
		end
	elseif s == State.Stunned or s == State.Recoil then
		self:_setState(State.Idle)
		if self._blockHeld then
			self:_raiseBlock()
		end
	end
end

return CombatStateMachine
