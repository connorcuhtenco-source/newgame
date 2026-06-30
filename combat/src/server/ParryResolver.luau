--!strict
-- ParryResolver — decides what a guarded victim's defense produces:
--   "parry" : F was raised within ParryWindow before the hit -> perfect parry
--   "block" : guarding, but too early -> standard 80% mitigation
--   "none"  : not guarding -> full damage

local CombatConfig = require(game:GetService("ReplicatedStorage").Combat.CombatConfig)
local PlayerCombatState = require(script.Parent.PlayerCombatState)

local ParryResolver = {}

export type Outcome = "parry" | "block" | "none"

function ParryResolver.resolve(victimState: PlayerCombatState.State?, serverNow: number): Outcome
	if not victimState or not victimState.blocking then
		return "none"
	end
	-- The parry frame: the guard was raised no longer than ParryWindow ago.
	if serverNow - victimState.blockStartTime <= CombatConfig.Block.ParryWindow then
		return "parry"
	end
	return "block"
end

return ParryResolver
