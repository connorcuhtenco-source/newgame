--!strict
-- HuecoMundoSky — the endless white desert under a perpetual crescent moon.
-- Configures a night Sky with the moon shown, dials Lighting for stark white
-- sand + sharp black silhouettes, and can generate the flat desert terrain.

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local ToonLighting = require(script.Parent.ToonLighting)

local HuecoMundoSky = {}

local function makeSky(): Sky
	local existing = Lighting:FindFirstChildOfClass("Sky")
	local sky = existing or Instance.new("Sky")
	sky.CelestialBodiesShown = true
	-- Default Roblox night-ish faces; swap for your own white-void skybox ids.
	sky.SkyboxBk = "rbxassetid://6444884337"
	sky.SkyboxDn = "rbxassetid://6444884785"
	sky.SkyboxFt = "rbxassetid://6444884337"
	sky.SkyboxLf = "rbxassetid://6444884337"
	sky.SkyboxRt = "rbxassetid://6444884337"
	sky.SkyboxUp = "rbxassetid://6444884785"
	sky.StarCount = 1200
	-- The signature crescent moon, large and low.
	sky.MoonAngularSize = 18
	sky.MoonTextureId = "rbxasset://sky/moon.jpg"
	sky.SunAngularSize = 0 -- hide the sun; perpetual night
	sky.Parent = Lighting
	return sky
end

function HuecoMundoSky.apply()
	makeSky()
	-- Perpetual crescent: fix the clock to a moon-up hour.
	Lighting.ClockTime = 0
	Lighting.GeographicLatitude = 20

	-- Toon night base, then crank contrast for that stark-white/black look.
	ToonLighting.apply(false)
	Lighting.Ambient = Color3.fromRGB(28, 30, 40)
	Lighting.OutdoorAmbient = Color3.fromRGB(60, 64, 82)
	Lighting.Brightness = 2.2

	local cc = Lighting:FindFirstChild("ToonContrast") :: ColorCorrectionEffect?
	if cc then
		cc.Contrast = 0.45 -- very graphic, sharp silhouettes
		cc.Saturation = -0.1 -- desaturated bone-white world
		cc.TintColor = Color3.fromRGB(235, 240, 255)
	end

	local atmos = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmos.Density = 0.32
	atmos.Haze = 1.2
	atmos.Color = Color3.fromRGB(220, 225, 240)
	atmos.Decay = Color3.fromRGB(120, 130, 160)
	atmos.Glare = 0.1
	atmos.Parent = Lighting
end

-- Generate a large flat bone-white desert with the terrain system.
-- `radius` studs out from the origin; `y` is the sand top height.
function HuecoMundoSky.buildDesert(radius: number?, y: number?)
	local r = radius or 1024
	local top = y or 0
	local terrain = Workspace.Terrain
	terrain:FillBlock(CFrame.new(0, top - 25, 0), Vector3.new(r * 2, 50, r * 2), Enum.Material.Sand)
	-- Tint the sand toward stark white.
	terrain:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(244, 244, 238))
end

return HuecoMundoSky
