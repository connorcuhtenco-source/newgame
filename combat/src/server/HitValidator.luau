--!strict
-- HitValidator — the gatekeeper for "server-side hit validation". A client
-- detects candidate hits with its raycast hitbox, but the server independently
-- confirms each claim is physically plausible before any damage is dealt. This
-- rejects teleport-hits, out-of-range hits, hits with no corresponding swing,
-- hits while stunned, and rapid-fire swing spam.

local Players = game:GetService("Players")
local CombatConfig = require(game:GetService("ReplicatedStorage").Combat.CombatConfig)
local PlayerCombatState = require(script.Parent.PlayerCombatState)

local HitValidator = {}

local function getRoot(character: Model?): BasePart?
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function getHumanoid(character: Model?): Humanoid?
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

-- Should the server accept this swing intent? (rate-limit + lock check)
function HitValidator.canSwing(state: PlayerCombatState.State, serverNow: number): boolean
	if PlayerCombatState.isLocked(state, serverNow) then
		return false
	end
	if serverNow - state.lastSwingAt < CombatConfig.Server.MinSwingInterval then
		return false
	end
	return true
end

export type HitContext = {
	attacker: Player,
	attackerChar: Model,
	victim: Player?,
	victimChar: Model,
	victimHumanoid: Humanoid,
	hitPosition: Vector3,
}

-- Validate a claimed hit. Returns a HitContext on success, or nil + reason.
function HitValidator.validateHit(
	state: PlayerCombatState.State,
	serverNow: number,
	targetCharacter: any,
	claimedHitPos: any
): (HitContext?, string?)
	local attacker = state.player
	local attackerChar = attacker.Character
	if not attackerChar then
		return nil, "attacker has no character"
	end
	if PlayerCombatState.isLocked(state, serverNow) then
		return nil, "attacker is locked (stun/recoil)"
	end

	-- There must be a live swing this hit belongs to.
	local swing = state.activeSwing
	if not swing or serverNow > swing.validUntil then
		return nil, "no active swing for hit"
	end

	-- Validate the target.
	if typeof(targetCharacter) ~= "Instance" or not targetCharacter:IsA("Model") then
		return nil, "invalid target"
	end
	local victimChar = targetCharacter :: Model
	if victimChar == attackerChar then
		return nil, "cannot hit self"
	end
	if swing.hitVictims[victimChar] then
		return nil, "victim already hit this swing"
	end

	local victimHumanoid = getHumanoid(victimChar)
	if not victimHumanoid or victimHumanoid.Health <= 0 then
		return nil, "target not a living humanoid"
	end

	local attackerRoot = getRoot(attackerChar)
	local victimRoot = getRoot(victimChar)
	if not attackerRoot or not victimRoot then
		return nil, "missing root parts"
	end

	-- Range check (with latency fudge).
	local toVictim = victimRoot.Position - attackerRoot.Position
	local distance = toVictim.Magnitude
	if distance > CombatConfig.Hitbox.Reach + CombatConfig.Hitbox.ReachFudge then
		return nil, "out of range"
	end

	-- Facing check: the attacker must be roughly looking at the victim.
	if distance > 1e-3 then
		local look = attackerRoot.CFrame.LookVector
		local dot = look:Dot(toVictim.Unit)
		if dot < CombatConfig.Hitbox.FacingDot then
			return nil, "victim not in front of attacker"
		end
	end

	-- Prefer a server-trusted contact point; fall back to the claim, then to the
	-- midpoint between the two characters.
	local hitPos: Vector3
	if typeof(claimedHitPos) == "Vector3" then
		hitPos = claimedHitPos
	else
		hitPos = attackerRoot.Position:Lerp(victimRoot.Position, 0.5)
	end

	swing.hitVictims[victimChar] = true

	return {
		attacker = attacker,
		attackerChar = attackerChar,
		victim = Players:GetPlayerFromCharacter(victimChar),
		victimChar = victimChar,
		victimHumanoid = victimHumanoid,
		hitPosition = hitPos,
	},
		nil
end

return HitValidator
