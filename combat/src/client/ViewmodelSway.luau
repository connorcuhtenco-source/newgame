--!strict
-- ViewmodelSway — the First-Person Viewmodel Spring System (hand-sway).
--
-- Produces a small CFrame offset, applied on top of the viewmodel's rest pose
-- every render frame, so the weapon/hands feel attached to a real body:
--   * looking around makes the weapon LAG behind the camera, then spring back
--     (with a touch of roll into the turn to sell weight),
--   * walking adds a subtle figure-8 bob,
--   * standing still adds a faint breathing drift.
--
-- It is built from two damped springs (one for rotation, one for position) from
-- the shared Spring module, kicked by the camera's angular velocity. Because the
-- springs are critically damped, motion is smooth and never robotic.
--
-- Usage (per RenderStep, BEFORE positioning the viewmodel):
--   local offset = sway:update(dt, camera, speed01)   -- returns a CFrame
--   model:PivotTo(camera.CFrame * REST * offset * swingArc)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Spring = require(ReplicatedStorage.Combat.Spring)
local VisualConfig = require(ReplicatedStorage.Combat.VisualConfig)

local ViewmodelSway = {}
ViewmodelSway.__index = ViewmodelSway

export type ViewmodelSway = typeof(setmetatable({} :: any, ViewmodelSway))

local function wrapAngle(a: number): number
	-- Map any angle delta into [-pi, pi] so a yaw wrap doesn't spike the spring.
	return (a + math.pi) % (2 * math.pi) - math.pi
end

function ViewmodelSway.new(): ViewmodelSway
	local cfg = VisualConfig.Sway
	local self = setmetatable({
		_rot = Spring.new(Vector3.zero, cfg.LookStiffness, cfg.LookDamping),
		_pos = Spring.new(Vector3.zero, cfg.PosStiffness, cfg.PosDamping),
		_lastPitch = nil :: number?,
		_lastYaw = nil :: number?,
		_bobPhase = 0,
		_time = 0,
	}, ViewmodelSway)
	return self :: any
end

-- speed01 is the player's planar speed normalized 0..1 (0 = still, 1 = sprint).
function ViewmodelSway:update(dt: number, camera: Camera, speed01: number): CFrame
	local cfg = VisualConfig.Sway
	dt = math.min(dt, 1 / 30)
	self._time += dt

	-- --- Look sway: kick the springs by how fast the camera turned. ---
	local pitch, yaw = camera.CFrame:ToOrientation()
	if self._lastPitch == nil then
		self._lastPitch, self._lastYaw = pitch, yaw
	end
	local dPitch = wrapAngle(pitch - (self._lastPitch :: number))
	local dYaw = wrapAngle(yaw - (self._lastYaw :: number))
	self._lastPitch, self._lastYaw = pitch, yaw

	local dtSafe = math.max(dt, 1e-4)
	local pitchVel = dPitch / dtSafe
	local yawVel = dYaw / dtSafe

	-- Rotation: weapon lags opposite to the turn, plus roll into a yaw turn.
	self._rot:impulse(
		Vector3.new(-pitchVel * cfg.LookAmount * dt, -yawVel * cfg.LookAmount * dt, yawVel * cfg.RollAmount * dt)
	)
	-- Position: counter-translate so it reads as inertia.
	self._pos:impulse(Vector3.new(yawVel * cfg.PosAmount * dt, pitchVel * cfg.PosAmount * dt, 0))

	local rot = self._rot:update(dt) :: Vector3
	local pos = self._pos:update(dt) :: Vector3

	-- Clamp so the viewmodel can never swing out of frame.
	rot = Vector3.new(
		math.clamp(rot.X, -cfg.MaxLook, cfg.MaxLook),
		math.clamp(rot.Y, -cfg.MaxLook, cfg.MaxLook),
		math.clamp(rot.Z, -cfg.MaxLook, cfg.MaxLook)
	)
	pos = Vector3.new(
		math.clamp(pos.X, -cfg.MaxPos, cfg.MaxPos),
		math.clamp(pos.Y, -cfg.MaxPos, cfg.MaxPos),
		math.clamp(pos.Z, -cfg.MaxPos, cfg.MaxPos)
	)

	-- --- Walk bob (figure-8) blended with idle breathing. ---
	self._bobPhase += dt * cfg.BobFrequency * math.max(speed01, 0)
	local bobX = math.cos(self._bobPhase) * cfg.BobAmount * speed01
	local bobY = math.abs(math.sin(self._bobPhase)) * cfg.BobAmount * speed01
	local breathe = math.sin(self._time * cfg.BreatheFrequency) * cfg.BreatheAmount * (1 - speed01)

	local bob = Vector3.new(bobX, bobY + breathe, 0)

	return CFrame.new(pos + bob) * CFrame.Angles(rot.X, rot.Y, rot.Z)
end

function ViewmodelSway:reset()
	self._rot = Spring.new(Vector3.zero, VisualConfig.Sway.LookStiffness, VisualConfig.Sway.LookDamping)
	self._pos = Spring.new(Vector3.zero, VisualConfig.Sway.PosStiffness, VisualConfig.Sway.PosDamping)
	self._lastPitch = nil
	self._lastYaw = nil
end

return ViewmodelSway
