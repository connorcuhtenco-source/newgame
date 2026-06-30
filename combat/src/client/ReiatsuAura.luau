--!strict
-- ReiatsuAura — the G-key spiritual-pressure charging effect. A screen-space
-- overlay that, while held, tints the screen borders with a "burning" vignette
-- and a faux chromatic-aberration fringe (offset red/blue edges — Roblox has no
-- native chromatic aberration post effect), plus stylized aura particles around
-- the first-person weapon mesh.
--
-- All overlay frames live under a CanvasGroup so the whole effect can be faded
-- with a single GroupTransparency tween. Client-side; toggled via :setActive().

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VisualConfig = require(ReplicatedStorage.Combat.VisualConfig)

local ReiatsuAura = {}
ReiatsuAura.__index = ReiatsuAura

local localPlayer = Players.LocalPlayer

export type ReiatsuAura = typeof(setmetatable({} :: any, ReiatsuAura))

local function makeEdge(
	parent: Instance,
	name: string,
	anchor: Vector2,
	pos: UDim2,
	size: UDim2,
	rotation: number,
	color: Color3
)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = anchor
	frame.Position = pos
	frame.Size = size
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.Parent = parent

	local grad = Instance.new("UIGradient")
	grad.Rotation = rotation
	-- Opaque at the screen edge, fully transparent toward the center.
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	grad.Parent = frame
	return frame
end

function ReiatsuAura.new(): ReiatsuAura
	local cfg = VisualConfig.Reiatsu

	local gui = Instance.new("ScreenGui")
	gui.Name = "SoulriftReiatsu"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 40
	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	local group = Instance.new("CanvasGroup")
	group.Size = UDim2.fromScale(1, 1)
	group.BackgroundTransparency = 1
	group.GroupTransparency = 1 -- hidden until active
	group.Parent = gui

	-- Main burning vignette (four edges).
	makeEdge(group, "Top", Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.35), 90, cfg.BorderColor)
	makeEdge(group, "Bottom", Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.fromScale(1, 0.35), 270, cfg.BorderColor)
	-- Chromatic-aberration fringe: red on the left edge, blue on the right.
	makeEdge(
		group,
		"FringeL",
		Vector2.new(0, 0),
		UDim2.fromScale(0, 0),
		UDim2.fromScale(0.32, 1),
		0,
		cfg.AberrationColor1
	)
	makeEdge(
		group,
		"FringeR",
		Vector2.new(1, 0),
		UDim2.fromScale(1, 0),
		UDim2.fromScale(0.32, 1),
		180,
		cfg.AberrationColor2
	)

	local self = setmetatable({
		_gui = gui,
		_group = group,
		_active = false,
		_baseTransparency = 1 - cfg.MaxOpacity,
		_weapon = nil :: Instance?,
		_auraEmitters = {} :: { ParticleEmitter },
		_conn = nil :: RBXScriptConnection?,
		_t = 0,
	}, ReiatsuAura)
	return self :: any
end

-- Attach aura particles to the viewmodel weapon (call after the weapon exists).
function ReiatsuAura:setWeapon(weapon: Instance?)
	for _, e in self._auraEmitters do
		e:Destroy()
	end
	table.clear(self._auraEmitters)
	self._weapon = weapon
	if not weapon then
		return
	end

	local cfg = VisualConfig.Reiatsu
	-- Emit from each DmgPoint along the blade so the aura clings to the edge.
	for _, d in weapon:GetDescendants() do
		if d:IsA("Attachment") then
			local emitter = Instance.new("ParticleEmitter")
			emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			emitter.Color = ColorSequence.new(cfg.AuraColor)
			emitter.LightEmission = 1
			emitter.LightInfluence = 0
			emitter.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.25),
				NumberSequenceKeypoint.new(1, 0),
			})
			emitter.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.2),
				NumberSequenceKeypoint.new(1, 1),
			})
			emitter.Lifetime = NumberRange.new(0.25, 0.6)
			emitter.Speed = NumberRange.new(1, 4)
			emitter.Acceleration = Vector3.new(0, 8, 0)
			emitter.SpreadAngle = Vector2.new(60, 60)
			emitter.Rate = 0
			emitter.Enabled = false
			emitter.Parent = d
			table.insert(self._auraEmitters, emitter)
		end
	end
end

function ReiatsuAura:setActive(active: boolean)
	if self._active == active then
		return
	end
	self._active = active
	local cfg = VisualConfig.Reiatsu

	TweenService:Create(self._group, TweenInfo.new(cfg.FadeTime, Enum.EasingStyle.Quad), {
		GroupTransparency = active and self._baseTransparency or 1,
	}):Play()

	local rate = active and cfg.AuraRate or 0
	for _, e in self._auraEmitters do
		e.Rate = rate
		e.Enabled = active
	end

	if active and not self._conn then
		self._t = 0
		self._conn = RunService.RenderStepped:Connect(function(dt)
			self._t += dt
			-- Subtle pulse so the pressure feels alive.
			local pulse = math.sin(self._t * cfg.PulseSpeed) * 0.06
			self._group.GroupTransparency = math.clamp(self._baseTransparency - pulse, 0, 1)
		end)
	elseif not active and self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
end

function ReiatsuAura:Destroy()
	if self._conn then
		self._conn:Disconnect()
	end
	self._gui:Destroy()
end

return ReiatsuAura
