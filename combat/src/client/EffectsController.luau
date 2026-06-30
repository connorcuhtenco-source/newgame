--!strict
-- EffectsController — fire-and-forget cosmetic feedback: spark bursts and SFX at
-- a world point. Driven by the server's CombatEffect broadcasts so every nearby
-- client sees the same clash/parry, and by local prediction for the attacker's
-- own swing whoosh. All emitters self-destruct.

local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Combat.CombatConfig)

local EffectsController = {}

local function sparkAttachment(): Attachment
	local a = Instance.new("Attachment")

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 245, 200), Color3.fromRGB(255, 170, 60))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Speed = NumberRange.new(14, 30)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Lifetime = NumberRange.new(0.15, 0.35)
	emitter.Rate = 0
	emitter.Drag = 4
	emitter.Acceleration = Vector3.new(0, -40, 0)
	emitter.Parent = a

	return a
end

-- Spawn a burst of `count` sparks at a world position.
local function burst(position: Vector3, count: number, light: boolean)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.CFrame = CFrame.new(position)
	holder.Parent = Workspace

	local a = sparkAttachment()
	a.Parent = holder
	a:FindFirstChildOfClass("ParticleEmitter"):Emit(count)

	if light then
		local pl = Instance.new("PointLight")
		pl.Color = Color3.fromRGB(255, 210, 130)
		pl.Range = 14
		pl.Brightness = 6
		pl.Parent = holder
		task.delay(0.08, function()
			pl.Enabled = false
		end)
	end

	Debris:AddItem(holder, 1)
end

local function playSound(id: string, position: Vector3, volume: number, pitch: number?)
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
	sound.PlaybackSpeed = pitch or 1
	sound.RollOffMaxDistance = 120
	sound.Parent = holder
	sound:Play()
	Debris:AddItem(holder, 3)
end

function EffectsController.hit(position: Vector3)
	burst(position, 8, false)
	playSound(CombatConfig.Sounds.Hit, position, 0.6)
end

function EffectsController.blockHit(position: Vector3)
	burst(position, 12, false)
	playSound(CombatConfig.Sounds.BlockHit, position, 0.7, 0.9)
end

-- Perfect parry: bright spark + loud metallic clash.
function EffectsController.parry(position: Vector3)
	burst(position, 26, true)
	playSound(CombatConfig.Sounds.Parry, position, 1, 1.1)
end

-- Sword-on-sword clash: a massive emitter between the two fighters.
function EffectsController.clash(position: Vector3)
	burst(position, 60, true)
	playSound(CombatConfig.Sounds.Clash, position, 1, 1)
end

function EffectsController.swing(position: Vector3, combo: number)
	playSound(CombatConfig.Sounds.Swing, position, 0.4, 0.95 + combo * 0.03)
end

return EffectsController
