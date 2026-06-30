--!strict
-- VisualConfig — tuning for the visual/presentation layer (sway, motion trail,
-- procedural swing arc, hit feedback, materials). Kept separate from
-- CombatConfig so artists can iterate on feel without touching combat balance.

local VisualConfig = {}

-- First-person viewmodel hand-sway (spring driven).
VisualConfig.Sway = {
	-- Rotational sway from looking around (radians of offset per rad/s of look).
	LookStiffness = 90,
	LookDamping = 12,
	LookAmount = 0.65, -- pitch/yaw lag strength
	RollAmount = 0.35, -- extra roll when turning (sells weight)
	MaxLook = math.rad(9), -- clamp so the weapon never leaves frame

	-- Positional sway / counter-motion.
	PosStiffness = 70,
	PosDamping = 10,
	PosAmount = 0.20,
	MaxPos = 0.35, -- studs

	-- Walk bob.
	BobFrequency = 9.0, -- steps-ish per second at full speed
	BobAmount = 0.05, -- studs
	-- Idle breathing.
	BreatheFrequency = 1.1,
	BreatheAmount = 0.012,
}

-- Procedural swing arc (anticipation / strike / recovery). Fractions of the
-- swing's total active time; must sum to 1.
VisualConfig.Swing = {
	AnticipationFraction = 0.24,
	StrikeFraction = 0.34,
	RecoveryFraction = 0.42,
	-- Pose offsets, relative to the rest CFrame, in (studs / radians).
	AnticipationPos = Vector3.new(0.18, 0.10, 0.28), -- pull back & toward face
	AnticipationRot = Vector3.new(math.rad(-30), math.rad(28), math.rad(40)),
	StrikeEndPos = Vector3.new(-0.30, -0.18, -0.45), -- slash across & forward
	StrikeEndRot = Vector3.new(math.rad(26), math.rad(-46), math.rad(-58)),
	-- The finisher (#4) is a heavier overhead.
	FinisherAnticipationRot = Vector3.new(math.rad(-78), 0, 0),
	FinisherStrikeRot = Vector3.new(math.rad(60), 0, math.rad(6)),
	-- Camera roll/tilt coupled to the swing (radians, peak during strike).
	CameraRoll = math.rad(2.0),
	CameraPitchKick = math.rad(1.2),
}

-- Cubic-Bezier swing system (the upgraded "Slash Curve"). Phase split per spec:
-- 15% anticipation / 60% active / 25% recovery, each driven by a CSS-style cubic
-- bezier timing function so every strike has its own acceleration profile, plus
-- an elastic settle on recovery and camera roll + FOV coupling during the strike.
VisualConfig.Bezier = {
	Phases = {
		Anticipation = 0.15,
		Active = 0.60,
		Recovery = 0.25,
	},
	-- Per-strike cubic-bezier handles {x1, y1, x2, y2} for each phase, giving
	-- each of the 4 combo hits a distinct feel. Index 1..4.
	Curves = {
		-- hit 1: quick diagonal
		{
			anticipation = { 0.30, 0.00, 0.40, 1.00 }, -- ease-out cock-back
			active = { 0.85, 0.00, 0.90, 0.35 }, -- slow->snap accel
			recovery = { 0.20, 0.00, 0.20, 1.00 }, -- ease-out settle
		},
		-- hit 2: reverse diagonal, snappier
		{
			anticipation = { 0.25, 0.00, 0.35, 1.00 },
			active = { 0.90, 0.00, 0.95, 0.30 },
			recovery = { 0.18, 0.00, 0.22, 1.00 },
		},
		-- hit 3: wide horizontal
		{
			anticipation = { 0.30, 0.00, 0.45, 1.00 },
			active = { 0.80, 0.00, 0.92, 0.40 },
			recovery = { 0.22, 0.00, 0.25, 1.00 },
		},
		-- hit 4: heavy overhead finisher
		{
			anticipation = { 0.35, 0.00, 0.50, 1.00 }, -- longer cock-back
			active = { 0.95, 0.00, 0.98, 0.25 }, -- explosive
			recovery = { 0.16, 0.00, 0.30, 1.00 },
		},
	},
	-- Strength of the elastic overshoot blended into the recovery phase (0 = none).
	ElasticAmplitude = 0.35,
	ElasticPeriod = 0.4,
	-- Camera-impact coupling during the Active phase.
	CameraRoll = math.rad(2.4), -- peak roll into the cut
	CameraPitchKick = math.rad(1.4), -- finisher downward kick
	FovKick = 6.0, -- degrees of FOV punch at peak of the strike
}

-- Advanced clash/parry impact VFX.
VisualConfig.Impact = {
	ScreenFlash = {
		Color = Color3.fromRGB(255, 255, 255),
		ParryDuration = 0.18,
		ClashDuration = 0.26,
		Peak = 0.55, -- max screen coverage opacity (0..1)
	},
	Shockwave = {
		-- Optional authored ring texture; "" falls back to a neon expanding disc.
		RingTexture = "",
		Color = Color3.fromRGB(190, 225, 255),
		ParryRadius = 9,
		ClashRadius = 16,
		Duration = 0.35,
	},
	Sparks = {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = Color3.fromRGB(255, 240, 200),
		ParryCount = 28,
		ClashCount = 64,
		Speed = NumberRange.new(40, 95),
		Squash = 3.0, -- stretches billboards along travel (motion-streak look)
	},
}

-- Reiatsu charging aura (hold G): screen-space vignette w/ faux chromatic
-- aberration + aura particles around the first-person weapon.
VisualConfig.Reiatsu = {
	VignetteTexture = "", -- optional radial vignette image; "" uses edge gradients
	CoreColor = Color3.fromRGB(120, 200, 255),
	AberrationColor1 = Color3.fromRGB(255, 60, 90), -- red fringe
	AberrationColor2 = Color3.fromRGB(60, 140, 255), -- blue fringe
	BorderColor = Color3.fromRGB(40, 10, 60), -- "burning" dark border tint
	MaxOpacity = 0.55,
	FadeTime = 0.25,
	PulseSpeed = 7,
	AuraRate = 60,
	AuraColor = Color3.fromRGB(150, 210, 255),
	InputKey = Enum.KeyCode.G,
}

-- Emissive motion-trail ribbon on the blade.
VisualConfig.Trail = {
	Lifetime = 0.18, -- seconds the ribbon persists
	MinLength = 0.05,
	WidthCurve = { 1.0, 0.0 }, -- start..end width scale
	Color = Color3.fromRGB(150, 210, 255), -- spiritual blue-white
	Transparency = { 0.1, 1.0 }, -- start..end
	LightEmission = 1,
	LightInfluence = 0,
	-- Optional streak texture; "" uses a solid ribbon.
	Texture = "",
}

-- "Solid white" hit flash (instant feedback when an enemy is struck).
VisualConfig.HitFlash = {
	Duration = 0.05,
	Color = Color3.fromRGB(255, 255, 255),
	Outline = Color3.fromRGB(255, 255, 255),
}

-- Hollow enemy aura / eyes.
VisualConfig.Hollow = {
	EyeColor = Color3.fromRGB(255, 35, 25),
	EyeLightRange = 8,
	EyeLightBrightness = 5,
	AuraColor = Color3.fromRGB(20, 0, 30),
	AuraRate = 26,
	AuraSize = 4.5,
	-- Played on a hit reaction. Replace with your own; "rbxassetid://0" no-ops
	-- and falls back to a brief procedural stagger lean.
	FlinchAnim = "rbxassetid://0",
}

-- Material / mesh handling guidelines surfaced to code where useful. The actual
-- high-poly meshes + PBR textures are authored in a DCC tool (see VISUALS.md);
-- these are the in-engine Instance properties to apply to them.
VisualConfig.Materials = {
	SteelBlade = {
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(214, 224, 235),
		Reflectance = 0.25,
	},
	Hilt = {
		Material = Enum.Material.Fabric,
		Color = Color3.fromRGB(40, 30, 60),
	},
	Tsuba = {
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(60, 55, 50),
		Reflectance = 0.15,
	},
	QuincyBow = {
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(120, 200, 255),
		Transparency = 0.35,
	},
}

table.freeze(VisualConfig)
return VisualConfig
