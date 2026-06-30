--!strict
-- ToonLighting — pushes Lighting toward a high-contrast, stylized "anime/cel"
-- look: low ambient, hard sharp shadows, punchy contrast and saturation. Real
-- per-object cel-shading needs a custom renderer (not available in Roblox), so
-- this approximates it with engine lighting + a contrast ColorCorrection and an
-- optional black outline helper for characters.
--
-- NOTE: set Lighting.Technology = Future in Studio (it is not reliably settable
-- from a script) for the crispest shadows; everything else is configured here.

local Lighting = game:GetService("Lighting")

local ToonLighting = {}

local function getOrMake(className: string, name: string): Instance
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = Lighting
	return inst
end

-- Apply the toon base. `daytime` true = bright stylized day, false = moody night.
function ToonLighting.apply(daytime: boolean?)
	local day = daytime ~= false

	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0 -- hard, sharp shadow edges
	Lighting.Brightness = day and 3 or 1.5
	Lighting.EnvironmentDiffuseScale = day and 0.4 or 0.15
	Lighting.EnvironmentSpecularScale = 0.3
	Lighting.Ambient = day and Color3.fromRGB(70, 72, 80) or Color3.fromRGB(18, 20, 30)
	Lighting.OutdoorAmbient = day and Color3.fromRGB(120, 125, 140) or Color3.fromRGB(35, 40, 60)
	Lighting.ClockTime = day and 14.5 or 0.2

	local cc = getOrMake("ColorCorrectionEffect", "ToonContrast") :: ColorCorrectionEffect
	cc.Enabled = true
	cc.Contrast = 0.25 -- crunch midtones for a flat, graphic look
	cc.Saturation = 0.20
	cc.Brightness = 0
	cc.TintColor = day and Color3.fromRGB(255, 252, 245) or Color3.fromRGB(225, 230, 255)

	local sun = getOrMake("SunRaysEffect", "ToonSunRays") :: SunRaysEffect
	sun.Enabled = day
	sun.Intensity = 0.12
	sun.Spread = 0.6
end

-- Add a clean black toon outline to a character/model (FillTransparency = 1 so
-- only the silhouette outline shows). Cheap stand-in for shader outlines.
function ToonLighting.addOutline(model: Model, thickness: number?)
	if model:FindFirstChild("__ToonOutline") then
		return
	end
	local hl = Instance.new("Highlight")
	hl.Name = "__ToonOutline"
	hl.FillTransparency = 1
	hl.OutlineColor = Color3.fromRGB(8, 8, 12)
	hl.OutlineTransparency = 0
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Adornee = model
	hl.Parent = model
end

return ToonLighting
