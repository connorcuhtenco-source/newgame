--!strict
-- ReishiDrift — ambient spiritual-energy flakes. Subtle blue Reishi particles
-- constantly drift through the air around the player. Implemented as an emitter
-- volume parented to a part that tracks the camera each render frame, so the
-- effect is always present wherever the player walks without flooding the whole
-- map with emitters.
--
-- Client-side module: ReishiDrift.start() / .stop().

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ReishiDrift = {}

local holder: Part? = nil
local conn: RBXScriptConnection? = nil

local function makeEmitter(): ParticleEmitter
	local p = Instance.new("ParticleEmitter")
	p.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	p.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(140, 200, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(90, 150, 235)),
	})
	p.LightEmission = 0.8
	p.LightInfluence = 0
	p.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.18),
		NumberSequenceKeypoint.new(1, 0),
	})
	p.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	p.Lifetime = NumberRange.new(3, 6)
	p.Rate = 40
	p.Speed = NumberRange.new(0.5, 1.5)
	p.Drag = 1.5
	p.SpreadAngle = Vector2.new(180, 180)
	-- Gentle upward + sideways drift.
	p.Acceleration = Vector3.new(0.6, 1.2, 0.3)
	p.Rotation = NumberRange.new(0, 360)
	p.RotSpeed = NumberRange.new(-30, 30)
	return p
end

-- `boxSize` controls how large the drift volume around the player is.
function ReishiDrift.start(boxSize: number?)
	if holder then
		return
	end
	local size = boxSize or 40

	local part = Instance.new("Part")
	part.Name = "ReishiDriftVolume"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.new(size, size, size)
	part.Parent = Workspace

	-- Spread emission across the volume via several attachments.
	for x = -1, 1 do
		for z = -1, 1 do
			local a = Instance.new("Attachment")
			a.Position = Vector3.new(x * size * 0.4, 0, z * size * 0.4)
			a.Parent = part
			makeEmitter().Parent = a
		end
	end

	holder = part
	conn = RunService.RenderStepped:Connect(function()
		local cam = Workspace.CurrentCamera
		if cam and holder then
			-- Track the camera but stay axis-aligned so flakes don't whip around.
			holder.CFrame = CFrame.new(cam.CFrame.Position)
		end
	end)
end

function ReishiDrift.stop()
	if conn then
		conn:Disconnect()
		conn = nil
	end
	if holder then
		holder:Destroy()
		holder = nil
	end
end

return ReishiDrift
