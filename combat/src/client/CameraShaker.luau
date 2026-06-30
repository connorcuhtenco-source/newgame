--!strict
-- CameraShaker — sells the weight of impacts with a quick, springy camera kick.
-- A single Vector3 spring stores an angular offset (pitch, yaw, roll in radians).
-- Each :shake() kicks the spring's velocity with a randomized impulse; the
-- spring then settles back to zero, producing a snappy recoil rather than a
-- lingering wobble. Applied AFTER the default camera update each render frame.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Spring = require(ReplicatedStorage.Combat.Spring)
local CombatConfig = require(ReplicatedStorage.Combat.CombatConfig)

local CameraShaker = {}
CameraShaker.__index = CameraShaker

local RENDER_NAME = "SoulriftCameraShake"

export type CameraShaker = typeof(setmetatable({} :: any, CameraShaker))

function CameraShaker.new(): CameraShaker
	local cfg = CombatConfig.Camera.Spring
	local self = setmetatable({
		_spring = Spring.new(Vector3.zero, cfg.Stiffness, cfg.Damping),
		_running = false,
	}, CameraShaker)
	return self :: any
end

function CameraShaker:start()
	if self._running then
		return
	end
	self._running = true
	-- Camera priority + 1 runs just after Roblox positions the camera, so our
	-- offset is layered on top of the normal first-person camera.
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt)
		self:_render(dt)
	end)
end

function CameraShaker:stop()
	if not self._running then
		return
	end
	self._running = false
	RunService:UnbindFromRenderStep(RENDER_NAME)
end

-- intensity is roughly the peak angle in radians (see CombatConfig.Camera.*).
function CameraShaker:shake(intensity: number)
	local function rnd()
		return (math.random() * 2 - 1)
	end
	-- Bias pitch/roll over yaw so it reads as an impact, not a head-turn.
	self._spring:impulse(Vector3.new(rnd() * intensity * 22, rnd() * intensity * 10, rnd() * intensity * 26))
end

-- Directional kick (used for clashes: shove the view away from the opponent).
function CameraShaker:shakeDirectional(intensity: number, sign: number)
	self._spring:impulse(Vector3.new(-math.abs(intensity) * 24, 0, sign * intensity * 16))
end

function CameraShaker:_render(dt: number)
	local offset = self._spring:update(dt) :: Vector3
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	if offset.Magnitude < 1e-4 then
		return
	end
	camera.CFrame = camera.CFrame * CFrame.Angles(offset.X, offset.Y, offset.Z)
end

function CameraShaker:Destroy()
	self:stop()
end

return CameraShaker
