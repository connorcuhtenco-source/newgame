--!strict
-- CombatClient (bootstrap) — wires the local controller together:
--
--   InputController ──► CombatStateMachine ──► ViewmodelController (pose/anim)
--                                          ├─► WeaponHitbox (raycast detection)
--                                          └─► Remotes.CombatAction (intents)
--
--   Remotes.CombatState  ──► authoritative stun / knockback / clash recoil
--   Remotes.CombatEffect ──► sparks, sfx, camera shake (cosmetic, for everyone)
--
-- The client is responsible for FEEL and for *detecting* candidate hits; the
-- server has the final say on whether anything actually lands (see CombatServer).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Combat.Remotes)
local WeaponHitbox = require(ReplicatedStorage.Combat.WeaponHitbox)
local CombatConfig = require(ReplicatedStorage.Combat.CombatConfig)

local CombatStateMachine = require(script.CombatStateMachine)
local InputController = require(script.InputController)
local ViewmodelController = require(script.ViewmodelController)
local CameraShaker = require(script.CameraShaker)
local EffectsController = require(script.EffectsController)
local EnemyVfx = require(script.EnemyVfx)

local localPlayer = Players.LocalPlayer

local function now(): number
	return Workspace:GetServerTimeNow()
end

-- == Per-character context ===============================================

local character: Model? = nil
local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil
local baseWalkSpeed = 16

-- == Subsystems ==========================================================

local viewmodel = ViewmodelController.new()
local cameraShaker = CameraShaker.new()
local stateMachine
local input
local hitbox: WeaponHitbox.WeaponHitbox? = nil

local function buildHitbox()
	if hitbox then
		hitbox:Destroy()
		hitbox = nil
	end
	local weapon = viewmodel:getWeapon()
	if not weapon then
		return
	end
	local hb = WeaponHitbox.new(weapon)
	-- Never hit ourselves or our own viewmodel.
	local ignore: { Instance } = { weapon }
	if character then
		table.insert(ignore, character)
	end
	hb:Ignore(ignore)

	hb.OnHit = function(hitHumanoid, _hitPart, result)
		local victimModel = hitHumanoid.Parent
		if not victimModel or victimModel == character then
			return
		end
		-- Report the candidate hit; the server decides damage / parry / clash.
		Remotes.CombatAction:FireServer("Hit", {
			combo = stateMachine.combo,
			clientTime = now(),
			targetCharacter = victimModel,
			hitPosition = result.Position,
		})
		-- Light local prediction so the attacker gets instant feedback.
		EffectsController.hit(result.Position)
		cameraShaker:shake(CombatConfig.Camera.HitImpulse)
	end
	hitbox = hb
end

-- == State machine callbacks =============================================

local function makeStateMachine()
	return CombatStateMachine.new({
		onSwingStart = function(combo)
			viewmodel:playSwing(combo)
			if rootPart then
				EffectsController.swing(rootPart.Position, combo)
			end
			Remotes.CombatAction:FireServer("Swing", {
				combo = combo,
				clientTime = now(),
			})
		end,
		onActiveStart = function()
			if hitbox then
				hitbox:HitStart()
			end
		end,
		onActiveEnd = function()
			if hitbox then
				hitbox:HitStop()
			end
		end,
		onBlockChanged = function(isBlocking)
			viewmodel:setBlocking(isBlocking)
			if humanoid then
				humanoid.WalkSpeed = isBlocking and (baseWalkSpeed * CombatConfig.Block.WalkSpeedMultiplier)
					or baseWalkSpeed
			end
			Remotes.CombatAction:FireServer(isBlocking and "BlockStart" or "BlockEnd", {
				clientTime = now(),
			})
		end,
		onLockChanged = function(locked)
			if input then
				input:setEnabled(not locked)
			end
			if humanoid then
				humanoid.WalkSpeed = locked and 0 or baseWalkSpeed
				humanoid.AutoRotate = not locked
			end
		end,
	})
end

stateMachine = makeStateMachine()
input = InputController.new({
	onAttack = function()
		stateMachine:requestAttack()
	end,
	onBlockChanged = function(held)
		stateMachine:setBlockHeld(held)
	end,
})

-- == Authoritative server -> client messages =============================

Remotes.CombatState.OnClientEvent:Connect(function(kind: string, payload)
	payload = payload or {}
	if kind == "Stun" then
		stateMachine:applyStun(payload.duration or CombatConfig.Parry.AttackerStun)
		viewmodel:playStun(payload.duration or CombatConfig.Parry.AttackerStun)
		cameraShaker:shake(CombatConfig.Camera.ParryImpulse)
	elseif kind == "Recoil" then
		stateMachine:applyRecoil(payload.duration or CombatConfig.Clash.RecoilTime)
	elseif kind == "Cancel" then
		stateMachine:applyRecoil(0.15)
	elseif kind == "Knockback" then
		if rootPart and payload.direction then
			local power = payload.power or 0
			rootPart.AssemblyLinearVelocity = payload.direction * power + Vector3.new(0, payload.lift or 0, 0)
		end
	elseif kind == "ParrySuccess" then
		-- We successfully parried someone; reward feel.
		cameraShaker:shake(CombatConfig.Camera.HitImpulse)
	end
end)

-- == Cosmetic broadcasts (seen by everyone nearby) =======================

Remotes.CombatEffect.OnClientEvent:Connect(function(effectKind: string, payload)
	payload = payload or {}
	local pos = payload.position
	if effectKind == "Hit" then
		-- Full enemy reaction (spark + 0.05s white flash + flinch) on the struck
		-- character; fall back to a bare spark if we only got a position.
		if payload.victimChar then
			EnemyVfx.hitReaction(payload.victimChar, pos)
		elseif pos and payload.attacker ~= localPlayer then
			EffectsController.hit(pos)
		end
	elseif effectKind == "Block" then
		if pos then
			EffectsController.blockHit(pos)
		end
		if payload.victim == localPlayer then
			viewmodel:playBlockImpact()
			cameraShaker:shake(CombatConfig.Camera.HitImpulse)
		end
	elseif effectKind == "Parry" then
		if pos then
			EffectsController.parry(pos)
		end
		if payload.victim == localPlayer then
			-- We are the parrier.
			cameraShaker:shake(CombatConfig.Camera.ParryImpulse)
		end
	elseif effectKind == "Clash" then
		if pos then
			EffectsController.clash(pos)
		end
		if payload.attacker == localPlayer or payload.other == localPlayer then
			cameraShaker:shake(CombatConfig.Camera.ClashImpulse)
		end
	end
end)

-- == Character lifecycle =================================================

local function onCharacter(char: Model)
	character = char
	humanoid = char:WaitForChild("Humanoid") :: Humanoid
	rootPart = char:WaitForChild("HumanoidRootPart") :: BasePart
	baseWalkSpeed = (humanoid :: Humanoid).WalkSpeed
	-- Fresh state machine + hitbox each life so nothing leaks across deaths.
	-- The input handlers close over the `stateMachine` upvalue, so reassigning
	-- it here is automatically picked up by them.
	stateMachine = makeStateMachine()
	if input then
		input:setEnabled(true)
	end
	buildHitbox()
end

if localPlayer.Character then
	onCharacter(localPlayer.Character)
end
localPlayer.CharacterAdded:Connect(onCharacter)

-- == Enemy VFX: auto-dress any model tagged "Hollow" =====================

local function setupHollow(inst: Instance)
	if inst:IsA("Model") then
		EnemyVfx.setupHollow(inst)
	end
end
for _, tagged in CollectionService:GetTagged("Hollow") do
	setupHollow(tagged)
end
CollectionService:GetInstanceAddedSignal("Hollow"):Connect(setupHollow)

-- == Boot ================================================================

viewmodel:start()
cameraShaker:start()

RunService.RenderStepped:Connect(function(dt)
	stateMachine:update(dt)

	-- Feed the viewmodel the player's planar speed (0..1) for bob/sway.
	if rootPart then
		local v = rootPart.AssemblyLinearVelocity
		local planar = Vector3.new(v.X, 0, v.Z).Magnitude
		viewmodel:setSpeed01(planar / math.max(baseWalkSpeed, 1))
	end
end)
