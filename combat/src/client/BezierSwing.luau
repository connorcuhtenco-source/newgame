--!strict
-- BezierSwing — the upgraded "Slash Curve" weapon-swing system.
--
-- Instead of linear interpolation, each combo hit is driven by CSS-style cubic
-- Bezier timing functions (one per phase), so velocity is shaped, not constant:
--
--   Anticipation (15%) : rest -> cocked-back pose      (ease-out handle)
--   Active       (60%) : cocked-back -> follow-through (slow->snap accel)
--   Recovery     (25%) : follow-through -> rest        (ease + elastic settle)
--
-- Each phase uses per-strike handles from VisualConfig.Bezier.Curves so all four
-- hits feel distinct. During Active it also returns a camera Roll + FOV punch
-- (camera-impact coupling). Output is a CFrame offset relative to the rest pose.
--
-- Pure module (no state/Instances): ViewmodelController feeds it progress.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatConfig = require(ReplicatedStorage.Combat.CombatConfig)
local VisualConfig = require(ReplicatedStorage.Combat.VisualConfig)

local BezierSwing = {}

-- --- Cubic Bezier timing function -----------------------------------------
-- Solves a CSS cubic-bezier(x1,y1,x2,y2) for y given x (P0=(0,0), P3=(1,1)).
-- Newton-Raphson on the X polynomial, then evaluate Y at the found parameter.
local function bezierEase(x: number, x1: number, y1: number, x2: number, y2: number): number
	if x <= 0 then
		return 0
	elseif x >= 1 then
		return 1
	end

	local function sampleX(u: number): number
		local mu = 1 - u
		return 3 * mu * mu * u * x1 + 3 * mu * u * u * x2 + u * u * u
	end
	local function sampleXDeriv(u: number): number
		local mu = 1 - u
		return 3 * mu * mu * x1 + 6 * mu * u * (x2 - x1) + 3 * u * u * (1 - x2)
	end

	local u = x
	for _ = 1, 8 do
		local err = sampleX(u) - x
		if math.abs(err) < 1e-5 then
			break
		end
		local d = sampleXDeriv(u)
		if math.abs(d) < 1e-6 then
			break
		end
		u = math.clamp(u - err / d, 0, 1)
	end

	local mu = 1 - u
	return 3 * mu * mu * u * y1 + 3 * mu * u * u * y2 + u * u * u
end

-- Elastic overshoot used to "settle" the weapon back into idle on recovery.
local function easeOutElastic(t: number, amplitude: number, period: number): number
	if t <= 0 then
		return 0
	elseif t >= 1 then
		return 1
	end
	local s = period / (2 * math.pi) * math.asin(1 / math.max(amplitude, 1))
	return amplitude * math.pow(2, -10 * t) * math.sin((t - s) * (2 * math.pi) / period) + 1
end

export type SwingResult = {
	offset: CFrame,
	cameraRoll: number,
	cameraPitch: number,
	fovDelta: number,
}

function BezierSwing.duration(): number
	local f = CombatConfig.Combo.Frames
	return f.Windup + f.Active
end

local function poses(combo: number)
	local cfg = VisualConfig.Swing
	local isFinisher = combo >= CombatConfig.Combo.MaxHits
	local dir = (combo % 2 == 1) and 1 or -1
	local antiPos = cfg.AnticipationPos * Vector3.new(dir, 1, 1)
	local antiRot = isFinisher and cfg.FinisherAnticipationRot or (cfg.AnticipationRot * Vector3.new(1, dir, dir))
	local strikePos = cfg.StrikeEndPos * Vector3.new(dir, 1, 1)
	local strikeRot = isFinisher and cfg.FinisherStrikeRot or (cfg.StrikeEndRot * Vector3.new(1, dir, dir))
	return antiPos, antiRot, strikePos, strikeRot, dir, isFinisher
end

-- Evaluate the swing at global progress t in [0,1].
function BezierSwing.evaluate(combo: number, t: number): SwingResult
	local bz = VisualConfig.Bezier
	local curve = bz.Curves[math.clamp(combo, 1, #bz.Curves)]
	t = math.clamp(t, 0, 1)

	local antiPos, antiRot, strikePos, strikeRot, dir, isFinisher = poses(combo)

	local aEnd = bz.Phases.Anticipation
	local sEnd = aEnd + bz.Phases.Active

	local pos: Vector3
	local rot: Vector3
	local strikeEnvelope = 0 -- 0..1 camera coupling, peaks mid-Active

	if t <= aEnd then
		local lt = t / math.max(aEnd, 1e-4)
		local e =
			bezierEase(lt, curve.anticipation[1], curve.anticipation[2], curve.anticipation[3], curve.anticipation[4])
		pos = Vector3.zero:Lerp(antiPos, e)
		rot = Vector3.zero:Lerp(antiRot, e)
	elseif t <= sEnd then
		local lt = (t - aEnd) / math.max(bz.Phases.Active, 1e-4)
		local e = bezierEase(lt, curve.active[1], curve.active[2], curve.active[3], curve.active[4])
		pos = antiPos:Lerp(strikePos, e)
		rot = antiRot:Lerp(strikeRot, e)
		strikeEnvelope = math.sin(lt * math.pi)
	else
		local lt = (t - sEnd) / math.max(bz.Phases.Recovery, 1e-4)
		local e = bezierEase(lt, curve.recovery[1], curve.recovery[2], curve.recovery[3], curve.recovery[4])
		-- Blend the eased return with an elastic settle so it overshoots slightly.
		local elastic = easeOutElastic(lt, 1 + bz.ElasticAmplitude, bz.ElasticPeriod)
		local a = e * (1 - bz.ElasticAmplitude) + elastic * bz.ElasticAmplitude
		pos = strikePos:Lerp(Vector3.zero, a)
		rot = strikeRot:Lerp(Vector3.zero, a)
	end

	local rollSign = isFinisher and 0 or -dir
	return {
		offset = CFrame.new(pos) * CFrame.Angles(rot.X, rot.Y, rot.Z),
		cameraRoll = bz.CameraRoll * strikeEnvelope * rollSign,
		cameraPitch = (isFinisher and bz.CameraPitchKick or 0) * strikeEnvelope,
		fovDelta = bz.FovKick * strikeEnvelope,
	}
end

return BezierSwing
