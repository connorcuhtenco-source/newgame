--!strict
-- SwingArc — procedural, arc-based swing pose generator. Given a combo index and
-- a normalized progress t in [0,1] it returns the viewmodel's CFrame offset
-- (relative to the rest pose) and a coupled camera tilt, producing three phases:
--
--   Anticipation : weapon pulls back/up away from screen center (ease-out)
--   Strike       : weapon whips ACROSS the screen fast (ease-in for snap)
--   Recovery     : weapon slows smoothly back to rest (ease-in-out)
--
-- The slash direction alternates each hit so a combo reads as left/right/left…;
-- the finisher is a heavier overhead. The camera roll is driven from the same
-- curve so the view tilts INTO the swing (e.g. roll right on a right->left cut),
-- selling momentum without desyncing from the blade.
--
-- This is intentionally pure (no Instances/state) so it is deterministic and
-- trivially testable; the ViewmodelController feeds it progress each frame.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatConfig = require(ReplicatedStorage.Combat.CombatConfig)
local VisualConfig = require(ReplicatedStorage.Combat.VisualConfig)

local SwingArc = {}

local function easeOutCubic(t: number): number
	local f = 1 - t
	return 1 - f * f * f
end

local function easeInCubic(t: number): number
	return t * t * t
end

local function easeInOutCubic(t: number): number
	if t < 0.5 then
		return 4 * t * t * t
	end
	local f = -2 * t + 2
	return 1 - (f * f * f) / 2
end

-- Total duration of a swing's pose animation (windup + active), matching the
-- combat state machine so the visual and the hitbox stay in lock-step.
function SwingArc.duration(): number
	local f = CombatConfig.Combo.Frames
	return f.Windup + f.Active
end

export type SwingResult = {
	offset: CFrame,
	cameraRoll: number, -- radians (signed)
	cameraPitch: number, -- radians
}

-- Evaluate the swing pose at progress t for the given combo hit.
function SwingArc.evaluate(combo: number, t: number): SwingResult
	local cfg = VisualConfig.Swing
	t = math.clamp(t, 0, 1)

	local isFinisher = combo >= CombatConfig.Combo.MaxHits
	-- Alternate slash handedness; finisher is a centered overhead.
	local dir = (combo % 2 == 1) and 1 or -1

	local antiPos = cfg.AnticipationPos * Vector3.new(dir, 1, 1)
	local antiRot = isFinisher and cfg.FinisherAnticipationRot or (cfg.AnticipationRot * Vector3.new(1, dir, dir))
	local strikePos = cfg.StrikeEndPos * Vector3.new(dir, 1, 1)
	local strikeRot = isFinisher and cfg.FinisherStrikeRot or (cfg.StrikeEndRot * Vector3.new(1, dir, dir))

	local aFrac = cfg.AnticipationFraction
	local sFrac = cfg.StrikeFraction

	local pos: Vector3
	local rot: Vector3
	local rollEnvelope: number -- 0..1 strength of camera coupling this frame

	if t <= aFrac then
		-- Anticipation: rest -> pulled back, ease-out (settles into the cock).
		local a = easeOutCubic(t / aFrac)
		pos = Vector3.zero:Lerp(antiPos, a)
		rot = Vector3.zero:Lerp(antiRot, a)
		rollEnvelope = a * 0.25
	elseif t <= aFrac + sFrac then
		-- Strike: pulled back -> follow-through, ease-in for an explosive whip.
		local a = easeInCubic((t - aFrac) / sFrac)
		pos = antiPos:Lerp(strikePos, a)
		rot = antiRot:Lerp(strikeRot, a)
		-- Peak the camera coupling mid-strike.
		rollEnvelope = math.sin(a * math.pi) * 1.0 + 0.25
	else
		-- Recovery: follow-through -> rest, smooth ease-in-out.
		local a = easeInOutCubic((t - aFrac - sFrac) / math.max(1 - aFrac - sFrac, 1e-3))
		pos = strikePos:Lerp(Vector3.zero, a)
		rot = strikeRot:Lerp(Vector3.zero, a)
		rollEnvelope = (1 - a) * 0.35
	end

	local rollSign = isFinisher and 0 or -dir -- tilt INTO a right->left cut
	return {
		offset = CFrame.new(pos) * CFrame.Angles(rot.X, rot.Y, rot.Z),
		cameraRoll = cfg.CameraRoll * rollEnvelope * rollSign,
		cameraPitch = (isFinisher and cfg.CameraPitchKick or 0) * rollEnvelope,
	}
end

return SwingArc
