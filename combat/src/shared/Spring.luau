--!strict
-- Spring — a tiny critically-stable damped spring used for camera shake.
-- Works for both `number` and `Vector3` targets because every operation used
-- (+, -, * scalar) is overloaded for both. Integrated with a semi-implicit
-- Euler step which stays stable at the dt values RenderStepped produces.

export type Springable = number | Vector3

local Spring = {}
Spring.__index = Spring

export type Spring = typeof(setmetatable(
	{} :: {
		position: any,
		velocity: any,
		target: any,
		stiffness: number,
		damping: number,
		_zero: any,
	},
	Spring
))

function Spring.new(initial: Springable, stiffness: number?, damping: number?): Spring
	local zero = (typeof(initial) == "Vector3") and Vector3.zero or 0
	return setmetatable({
		position = initial,
		velocity = zero,
		target = initial,
		stiffness = stiffness or 100,
		damping = damping or 10,
		_zero = zero,
	}, Spring) :: any
end

-- Kick the spring with an instantaneous change in velocity.
function Spring:impulse(force: Springable)
	self.velocity = self.velocity + force
end

function Spring:setTarget(target: Springable)
	self.target = target
end

-- Advance the simulation and return the new position.
function Spring:update(dt: number): Springable
	-- Clamp dt so a hitched frame can never blow the spring up.
	dt = math.min(dt, 1 / 30)

	local displacement = self.position - self.target
	local accel = (-self.stiffness * displacement) - (self.damping * self.velocity)
	self.velocity = self.velocity + accel * dt
	self.position = self.position + self.velocity * dt
	return self.position
end

return Spring
