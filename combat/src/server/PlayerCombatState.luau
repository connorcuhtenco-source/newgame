--!strict
-- PlayerCombatState — authoritative per-player combat bookkeeping kept on the
-- server. This is the trusted mirror of what each client *claims* to be doing.
-- All times are server times (Workspace:GetServerTimeNow()).

local CombatConfig = require(game:GetService("ReplicatedStorage").Combat.CombatConfig)

export type Swing = {
	combo: number,
	startTime: number, -- when the server accepted the swing
	validUntil: number, -- latest server time a hit from this swing is accepted
	hitVictims: { [Model]: boolean }, -- dedup: one hit per victim per swing
}

export type State = {
	player: Player,
	lastSwingAt: number,
	comboCount: number, -- server-authoritative combo index (1..MaxHits)
	activeSwing: Swing?,
	blocking: boolean,
	blockStartTime: number,
	stunnedUntil: number,
	recoilUntil: number,
}

local PlayerCombatState = {}

local registry: { [Player]: State } = {}

function PlayerCombatState.get(player: Player): State
	local existing = registry[player]
	if existing then
		return existing
	end
	local state: State = {
		player = player,
		lastSwingAt = -math.huge,
		comboCount = 0,
		activeSwing = nil,
		blocking = false,
		blockStartTime = -math.huge,
		stunnedUntil = -math.huge,
		recoilUntil = -math.huge,
	}
	registry[player] = state
	return state
end

function PlayerCombatState.remove(player: Player)
	registry[player] = nil
end

-- Wipe transient combat state on respawn so nothing leaks across a death.
function PlayerCombatState.reset(player: Player)
	local state = registry[player]
	if not state then
		return
	end
	state.activeSwing = nil
	state.comboCount = 0
	state.blocking = false
	state.blockStartTime = -math.huge
	state.stunnedUntil = -math.huge
	state.recoilUntil = -math.huge
end

function PlayerCombatState.isLocked(state: State, serverNow: number): boolean
	return serverNow < state.stunnedUntil or serverNow < state.recoilUntil
end

-- Server-authoritative combo index: advances 1..MaxHits, resetting after the
-- finisher or after too long since the last swing. The client's claimed combo
-- is never trusted for damage/knockback.
function PlayerCombatState.nextCombo(state: State, serverNow: number): number
	if
		serverNow - state.lastSwingAt > CombatConfig.Combo.ResetWindow
		or state.comboCount >= CombatConfig.Combo.MaxHits
	then
		state.comboCount = 0
	end
	state.comboCount += 1
	return state.comboCount
end

-- Register a freshly-accepted swing, opening its hit-acceptance window.
function PlayerCombatState.beginSwing(state: State, combo: number, serverNow: number)
	local f = CombatConfig.Combo.Frames
	state.lastSwingAt = serverNow
	state.activeSwing = {
		combo = combo,
		startTime = serverNow,
		validUntil = serverNow + f.Windup + f.Active + 0.25, -- + latency grace
		hitVictims = {},
	}
end

function PlayerCombatState.clearSwing(state: State)
	state.activeSwing = nil
end

return PlayerCombatState
