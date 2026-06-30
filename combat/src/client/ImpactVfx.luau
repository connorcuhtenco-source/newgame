--!strict
-- ImpactVfx — stylized anime impact visuals for clashes and perfect parries:
--   * a bright circular white SCREEN-FLASH vignette (UI, fades fast),
--   * high-velocity STRETCHED billboard sparks (ParticleEmitter Squash),
--   * a radial SHOCKWAVE ring that expands and alpha-fades at the impact point.
--
-- Client-side, fire-and-forget; all instances self-clean. Driven by the
-- server's CombatEffect "Clash"/"Parry" broadcasts.

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Combat.CombatConfig)
local VisualConfig = require(ReplicatedStorage.Combat.VisualConfig)

local ImpactVfx = {}

local localPlayer = Players.LocalPlayer

-- --- Screen flash --------------------------------------------------------
local screenGui: ScreenGui? = nil
local flashFrame: Frame? = nil

local function ensureScreen(): Frame
	if flashFrame then
		return flashFrame
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "SoulriftImpactFx"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	-- A radial-ish flash: a white frame with brightness concentrated centrally
	-- using a soft circular gradient image overlay would be ideal; the solid
	-- frame fades so fast it reads as a flash regardless.
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = VisualConfig.Impact.ScreenFlash.Color
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = gui

	screenGui = gui
	flashFrame = frame
	return frame
end

local function screenFlash(peak: number, duration: number)
	local frame = ensureScreen()
	frame.BackgroundTransparency = 1 - peak
	TweenService:Create(frame, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
end

-- --- Stretched sparks ----------------------------------------------------
local function sparks(position: Vector3, count: number)
	local cfg = VisualConfig.Impact.Sparks
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.CFrame = CFrame.new(position)
	holder.Parent = Workspace

	local a = Instance.new("Attachment")
	a.Parent = holder

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = cfg.Texture
	emitter.Color = ColorSequence.new(cfg.Color)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	-- Squash stretches the billboard along its travel -> motion-streak sparks.
	emitter.Squash = NumberSequence.new(cfg.Squash)
	emitter.Speed = cfg.Speed
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Lifetime = NumberRange.new(0.12, 0.28)
	emitter.Rate = 0
	emitter.Drag = 6
	emitter.Acceleration = Vector3.new(0, -50, 0)
	emitter.Parent = a
	emitter:Emit(count)

	Debris:AddItem(holder, 1)
end

-- --- Shockwave ring ------------------------------------------------------
local function shockwave(position: Vector3, radius: number, duration: number)
	local cfg = VisualConfig.Shockwave
	local camera = Workspace.CurrentCamera
	local camPos = camera and camera.CFrame.Position or (position + Vector3.new(0, 0, 10))

	if cfg.RingTexture ~= "" then
		-- Authored ring texture on a camera-facing billboard.
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.Transparency = 1
		part.Size = Vector3.one
		part.CFrame = CFrame.new(position)
		part.Parent = Workspace

		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromScale(1, 1)
		bb.AlwaysOnTop = false
		bb.Adornee = part
		bb.Parent = part

		local img = Instance.new("ImageLabel")
		img.Size = UDim2.fromScale(1, 1)
		img.BackgroundTransparency = 1
		img.Image = cfg.RingTexture
		img.ImageColor3 = cfg.Color
		img.Parent = bb

		bb.Size = UDim2.fromScale(0, 0)
		TweenService:Create(bb, TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(radius, radius),
		}):Play()
		TweenService:Create(img, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			ImageTransparency = 1,
		}):Play()
		Debris:AddItem(part, duration + 0.1)
		return
	end

	-- Fallback: an emissive neon disc expanding toward the camera.
	local disc = Instance.new("Part")
	disc.Shape = Enum.PartType.Cylinder
	disc.Anchored = true
	disc.CanCollide = false
	disc.CanQuery = false
	disc.Material = Enum.Material.Neon
	disc.Color = cfg.Color
	disc.Size = Vector3.new(0.1, 1, 1)
	-- Face the disc toward the camera (cylinder's circular faces are on local X).
	disc.CFrame = CFrame.lookAt(position, camPos) * CFrame.Angles(0, math.rad(90), 0)
	disc.Parent = Workspace

	local tween = TweenService:Create(disc, TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.1, radius * 2, radius * 2),
		Transparency = 1,
	})
	tween:Play()
	Debris:AddItem(disc, duration + 0.1)
end

-- --- Sound ---------------------------------------------------------------
local function playSound(id: string, position: Vector3, volume: number)
	if id == "" or id == "rbxassetid://0" then
		return
	end
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.CFrame = CFrame.new(position)
	holder.Parent = Workspace
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.RollOffMaxDistance = 150
	sound.Parent = holder
	sound:Play()
	Debris:AddItem(holder, 3)
end

-- --- Public --------------------------------------------------------------
function ImpactVfx.parry(position: Vector3)
	local sf = VisualConfig.Impact.ScreenFlash
	screenFlash(sf.Peak * 0.8, sf.ParryDuration)
	sparks(position, VisualConfig.Impact.Sparks.ParryCount)
	shockwave(position, VisualConfig.Shockwave.ParryRadius, VisualConfig.Shockwave.Duration)
	playSound(CombatConfig.Sounds.Parry, position, 1)
end

function ImpactVfx.clash(position: Vector3)
	local sf = VisualConfig.Impact.ScreenFlash
	screenFlash(sf.Peak, sf.ClashDuration)
	sparks(position, VisualConfig.Impact.Sparks.ClashCount)
	shockwave(position, VisualConfig.Shockwave.ClashRadius, VisualConfig.Shockwave.Duration)
	playSound(CombatConfig.Sounds.Clash, position, 1)
end

return ImpactVfx
