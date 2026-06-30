--!strict
-- SoulSocietyAtmosphere — atmosphere pass for the Soul Society map: warm,
-- flickering paper-lantern point lights and the drifting Reishi flakes, on top
-- of the stylized toon day lighting.
--
-- Lanterns: tag the lantern parts by giving them the name "Lantern" (or add a
-- CollectionService tag "Lantern"); this finds them and attaches a dynamic,
-- gently flickering warm PointLight to each.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local ToonLighting = require(script.Parent.ToonLighting)
local ReishiDrift = require(script.Parent.ReishiDrift)

local SoulSocietyAtmosphere = {}

local LANTERN_COLOR = Color3.fromRGB(255, 170, 90)

type Flicker = {
	light: PointLight,
	base: number,
	phase: number,
	speed: number,
}

local flickers: { Flicker } = {}
local flickerConn: RBXScriptConnection? = nil

local function addLantern(part: BasePart)
	if part:FindFirstChild("LanternLight") then
		return
	end
	local light = Instance.new("PointLight")
	light.Name = "LanternLight"
	light.Color = LANTERN_COLOR
	light.Range = 16
	light.Brightness = 1.6
	light.Shadows = true
	light.Parent = part

	-- Make the lantern part itself glow.
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(255, 200, 140)

	table.insert(flickers, {
		light = light,
		base = light.Brightness,
		phase = math.random() * math.pi * 2,
		speed = 4 + math.random() * 3,
	})
end

local function collectLanterns(root: Instance)
	for _, tagged in CollectionService:GetTagged("Lantern") do
		if tagged:IsA("BasePart") and tagged:IsDescendantOf(root) then
			addLantern(tagged)
		end
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Lantern" then
			addLantern(d)
		end
	end
end

-- Apply the full Soul Society atmosphere. `mapRoot` defaults to Workspace.
function SoulSocietyAtmosphere.apply(mapRoot: Instance?)
	local root = mapRoot or workspace
	local Lighting = game:GetService("Lighting")

	-- Deep indigo nocturnal base.
	ToonLighting.apply(false)
	Lighting.Ambient = Color3.fromRGB(22, 14, 40)
	Lighting.OutdoorAmbient = Color3.fromRGB(38, 28, 70)
	Lighting.Brightness = 1.4
	Lighting.ClockTime = 0.1

	-- Volumetric-ish fog: Atmosphere haze + legacy distance fog tinted indigo so
	-- lantern light and Reishi flakes read against deep murk.
	local atmos = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmos.Density = 0.42
	atmos.Haze = 1.8
	atmos.Color = Color3.fromRGB(60, 45, 110)
	atmos.Decay = Color3.fromRGB(30, 20, 70)
	atmos.Glare = 0.2
	atmos.Parent = Lighting
	Lighting.FogColor = Color3.fromRGB(30, 22, 60)
	Lighting.FogStart = 30
	Lighting.FogEnd = 320

	ReishiDrift.start(45)

	collectLanterns(root)

	-- Drive the flicker. (Cheap: a few sine waves; no per-frame allocations.)
	if not flickerConn then
		flickerConn = RunService.Heartbeat:Connect(function(dt)
			for _, f in flickers do
				f.phase += dt * f.speed
				local n = (math.sin(f.phase) * 0.5 + math.sin(f.phase * 2.3) * 0.5)
				f.light.Brightness = f.base + n * 0.35
			end
		end)
	end
end

function SoulSocietyAtmosphere.stop()
	if flickerConn then
		flickerConn:Disconnect()
		flickerConn = nil
	end
	table.clear(flickers)
	ReishiDrift.stop()
end

return SoulSocietyAtmosphere
