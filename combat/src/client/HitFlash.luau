--!strict
-- HitFlash — the instant "solid white" feedback flash when something is struck.
-- Uses a Highlight overlay (non-destructive: no need to cache/restore the
-- model's real colors) held for a very short duration, then removed. This is
-- the cleanest way to flash a whole rig white for ~0.05s.

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VisualConfig = require(ReplicatedStorage.Combat.VisualConfig)

local HitFlash = {}

function HitFlash.flash(model: Model, duration: number?)
	if not model or not model:IsDescendantOf(workspace) then
		return
	end
	local cfg = VisualConfig.HitFlash
	local dur = duration or cfg.Duration

	-- Reuse an existing flash if one is already up (avoids stacking).
	local existing = model:FindFirstChild("__HitFlash")
	if existing then
		existing:Destroy()
	end

	local hl = Instance.new("Highlight")
	hl.Name = "__HitFlash"
	hl.FillColor = cfg.Color
	hl.OutlineColor = cfg.Outline
	hl.FillTransparency = 0
	hl.OutlineTransparency = 0
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Adornee = model
	hl.Parent = model

	Debris:AddItem(hl, dur)
end

-- Material-swap variant (per spec): instantly set every part to a 100% self-illum
-- white emissive look for `hold` seconds, then SMOOTHLY transition the color back
-- over `fade` seconds (Material is restored at the end of the fade). Caches and
-- restores each part's original Color/Material so it is fully non-destructive.
function HitFlash.materialFlash(model: Model, hold: number?, fade: number?)
	if not model then
		return
	end
	-- Don't stack: if a flash is mid-flight, let it finish.
	if model:GetAttribute("__Flashing") then
		return
	end
	local cfg = VisualConfig.HitFlash
	local holdT = hold or cfg.Duration
	local fadeT = fade or 0.12

	local cache: { { part: BasePart, color: Color3, material: Enum.Material } } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			table.insert(cache, { part = d, color = d.Color, material = d.Material })
			d.Material = Enum.Material.Neon
			d.Color = cfg.Color
		end
	end
	if #cache == 0 then
		return
	end
	model:SetAttribute("__Flashing", true)

	task.delay(holdT, function()
		local info = TweenInfo.new(fadeT, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		for _, entry in cache do
			if entry.part and entry.part.Parent then
				-- Tween color back; Material can't tween, so swap it back first so
				-- the fade reads against the real surface.
				entry.part.Material = entry.material
				TweenService:Create(entry.part, info, { Color = entry.color }):Play()
			end
		end
		task.delay(fadeT, function()
			if model and model.Parent then
				model:SetAttribute("__Flashing", false)
			end
		end)
	end)
end

return HitFlash
