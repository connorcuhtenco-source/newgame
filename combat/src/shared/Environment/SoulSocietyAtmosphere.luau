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

	ToonLighting.apply(true)
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
