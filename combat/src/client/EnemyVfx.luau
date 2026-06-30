--!strict
-- EnemyVfx — visual upgrades for Hollow-type enemies and their hit reactions.
--
--   setupHollow(model)        : glowing red eyes (+ light & ember trail) and a
--                               dark shadowy aura radiating from the torso.
--   hitReaction(model, pos)   : instant feedback when struck — hit-spark burst,
--                               a 0.05s solid-white flash, and a flinch/stagger.
--
-- Cosmetic only; runs on the client and is normally driven by the server's
-- CombatEffect "Hit" broadcast so everyone sees the same reaction.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VisualConfig = require(ReplicatedStorage.Combat.VisualConfig)
local HitFlash = require(script.Parent.HitFlash)
local EffectsController = require(script.Parent.EffectsController)

local EnemyVfx = {}

local SETUP_TAG = "__HollowVfx"

local function findTorso(model: Model): BasePart?
	return (
		model:FindFirstChild("UpperTorso")
		or model:FindFirstChild("Torso")
		or model:FindFirstChild("HumanoidRootPart")
	) :: BasePart?
end

local function makeAura(): ParticleEmitter
	local cfg = VisualConfig.Hollow
	local p = Instance.new("ParticleEmitter")
	p.Texture = "rbxasset://textures/particles/smoke_main.dds"
	p.Color = ColorSequence.new(cfg.AuraColor)
	p.LightEmission = 0
	p.LightInfluence = 0
	p.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, cfg.AuraSize * 0.4),
		NumberSequenceKeypoint.new(1, cfg.AuraSize),
	})
	p.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.25, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	p.Rate = cfg.AuraRate
	p.Lifetime = NumberRange.new(0.8, 1.4)
	p.Speed = NumberRange.new(2, 5)
	p.SpreadAngle = Vector2.new(20, 20)
	p.Acceleration = Vector3.new(0, 6, 0)
	p.Drag = 2
	return p
end

local function dressEye(part: BasePart)
	local cfg = VisualConfig.Hollow
	part.Material = Enum.Material.Neon
	part.Color = cfg.EyeColor

	local light = Instance.new("PointLight")
	light.Color = cfg.EyeColor
	light.Range = cfg.EyeLightRange
	light.Brightness = cfg.EyeLightBrightness
	light.Parent = part

	local a = Instance.new("Attachment")
	a.Parent = part
	local ember = Instance.new("ParticleEmitter")
	ember.Texture = "rbxasset://textures/particles/fire_main.dds"
	ember.Color = ColorSequence.new(cfg.EyeColor)
	ember.LightEmission = 1
	ember.Size = NumberSequence.new(0.4, 0)
	ember.Transparency = NumberSequence.new(0.2, 1)
	ember.Rate = 12
	ember.Lifetime = NumberRange.new(0.3, 0.6)
	ember.Speed = NumberRange.new(1, 2)
	ember.Acceleration = Vector3.new(0, 3, 0)
	ember.Parent = a
end

function EnemyVfx.setupHollow(model: Model)
	if not model or model:FindFirstChild(SETUP_TAG) then
		return
	end
	local marker = Instance.new("BoolValue")
	marker.Name = SETUP_TAG
	marker.Parent = model

	-- Eyes: any part whose name contains "Eye".
	local foundEye = false
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and string.find(string.lower(d.Name), "eye") then
			dressEye(d)
			foundEye = true
		end
	end

	-- Torso aura.
	local torso = findTorso(model)
	if torso then
		local a = Instance.new("Attachment")
		a.Name = "AuraPoint"
		a.Parent = torso
		makeAura().Parent = a
	end

	if not foundEye then
		-- No eye parts: still give a faint head glow so it reads as "alive".
		local head = model:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			local light = Instance.new("PointLight")
			light.Color = VisualConfig.Hollow.EyeColor
			light.Range = VisualConfig.Hollow.EyeLightRange
			light.Brightness = VisualConfig.Hollow.EyeLightBrightness * 0.5
			light.Parent = head
		end
	end
end

-- Brief procedural stagger when no flinch animation is available: lean the rig
-- back from the hit direction and snap it upright.
local function proceduralStagger(model: Model, fromPos: Vector3?)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end
	-- A small, safe visual recoil using the Humanoid's CameraOffset-free lean:
	-- nudge the look with a temporary tilt on the root's Motor6D if present.
	local rootJoint = root:FindFirstChild("RootJoint") :: Motor6D?
	if not rootJoint then
		return
	end
	local base = rootJoint.C0
	local dir = 1
	if fromPos then
		local toHit = (fromPos - root.Position)
		dir = (root.CFrame.RightVector:Dot(toHit) >= 0) and -1 or 1
	end
	rootJoint.C0 = base * CFrame.Angles(math.rad(14) * dir, 0, 0)
	task.delay(0.12, function()
		if rootJoint and rootJoint.Parent then
			rootJoint.C0 = base
		end
	end)
end

function EnemyVfx.hitReaction(model: Model, position: Vector3?)
	if not model then
		return
	end
	local pos = position
	if not pos then
		local torso = findTorso(model)
		pos = torso and torso.Position or nil
	end

	if pos then
		EffectsController.hit(pos)
	end
	HitFlash.flash(model, VisualConfig.HitFlash.Duration)

	-- Flinch: prefer an authored animation, else a procedural stagger.
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animId = VisualConfig.Hollow.FlinchAnim
	if humanoid and animId ~= "" and animId ~= "rbxassetid://0" then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end
		local anim = Instance.new("Animation")
		anim.AnimationId = animId
		local ok, track = pcall(function()
			return (animator :: Animator):LoadAnimation(anim)
		end)
		if ok and track then
			track.Priority = Enum.AnimationPriority.Action
			track:Play(0.05)
			Debris:AddItem(anim, 2)
		else
			proceduralStagger(model, pos)
		end
	else
		proceduralStagger(model, pos)
	end
end

return EnemyVfx
