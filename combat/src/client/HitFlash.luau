--!strict
-- HitFlash — the instant "solid white" feedback flash when something is struck.
-- Uses a Highlight overlay (non-destructive: no need to cache/restore the
-- model's real colors) held for a very short duration, then removed. This is
-- the cleanest way to flash a whole rig white for ~0.05s.

local Debris = game:GetService("Debris")
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

return HitFlash
