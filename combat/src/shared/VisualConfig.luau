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
