--!strict
-- ClashResolver — detects the sword-on-sword clash: two players whose M1 swings
-- go live at (almost) the same instant while facing each other. Because both
-- clients send their "Swing" intent at wind-up, the server compares the two
-- accepted swing start-times; if they fall within Clash.TimeMargin it's a clash.

local CombatConfig = require(game:GetService("ReplicatedStorage").Combat.CombatConfig)
local PlayerCombatState = require(script.Parent.PlayerCombatState)

local ClashResolver = {}

-- Returns true if the attacker's hit on the victim should resolve as a clash
-- rather than as damage/parry.
function ClashResolver.isClash(
	attackerState: PlayerCombatState.State,
	victimState: PlayerCombatState.State?,
	serverNow: number
): boolean
	if not victimState then
		return false
	end
	-- The victim must also be mid-swing (not blocking, not locked).
	if victimState.blocking then
		return false
	end
	if PlayerCombatState.isLocked(victimState, serverNow) then
		return false
	end

	local a = attackerState.activeSwing
	local b = victimState.activeSwing
	if not a or not b then
		return false
	end

	-- Both swings must still be live and have started within the margin.
	if serverNow > a.validUntil or serverNow > b.validUntil then
		return false
	end
	return math.abs(a.startTime - b.startTime) <= CombatConfig.Clash.TimeMargin
end

return ClashResolver
