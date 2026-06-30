--!strict
-- WeaponHitbox — spatial raycast hitbox in the spirit of Swordphin's
-- RaycastHitboxV4. Instead of relying on .Touched (which is laggy and easy to
-- tunnel through), it samples Attachments placed along the blade and, every
-- frame the hitbox is active, raycasts from each point's PREVIOUS world
-- position to its CURRENT one. Fast swings therefore leave a continuous swept
-- segment that cannot be skipped between frames.
--
-- Usage:
--   local hb = WeaponHitbox.new(weaponModel)        -- model containing "DmgPoint" attachments
--   hb.OnHit = function(humanoid, hitPart, result) ... end
--   hb:HitStart()  -- call at the start of a swing's Active frame
--   hb:HitStop()   -- call when the Active frame ends
--   hb:Destroy()

local RunService = game:GetService("RunService")
local CombatConfig = require(script.Parent.CombatConfig)

local WeaponHitbox = {}
WeaponHitbox.__index = WeaponHitbox

export type HitCallback = (humanoid: Humanoid, hitPart: BasePart, result: RaycastResult) -> ()

export type WeaponHitbox = typeof(setmetatable(
	{} :: {
		_model: Instance,
		_points: { Attachment },
		_lastPositions: { [Attachment]: Vector3 },
		_active: boolean,
		_alreadyHit: { [Humanoid]: boolean },
		_conn: RBXScriptConnection?,
		_params: RaycastParams,
		OnHit: HitCallback?,
	},
	WeaponHitbox
))

local function collectPoints(model: Instance): { Attachment }
	local points = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Attachment") and descendant.Name == CombatConfig.Hitbox.DamagePointTag then
			table.insert(points, descendant)
		end
	end
	return points
end

function WeaponHitbox.new(model: Instance, ignore: { Instance }?): WeaponHitbox
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or { model }
	params.IgnoreWater = true

	local self = setmetatable({
		_model = model,
		_points = collectPoints(model),
		_lastPositions = {},
		_active = false,
		_alreadyHit = {},
		_conn = nil,
		_params = params,
		OnHit = nil,
	}, WeaponHitbox)

	if #self._points == 0 then
		warn(`[WeaponHitbox] no "{CombatConfig.Hitbox.DamagePointTag}" attachments found in {model:GetFullName()}`)
	end
	return self :: any
end

-- Add characters/instances the rays should pass through (e.g. the attacker).
function WeaponHitbox:Ignore(instances: { Instance })
	local current = self._params.FilterDescendantsInstances
	for _, inst in instances do
		table.insert(current, inst)
	end
	self._params.FilterDescendantsInstances = current
end

function WeaponHitbox:HitStart()
	if self._active then
		return
	end
	self._active = true
	table.clear(self._alreadyHit)
	-- Seed the previous positions so the first frame doesn't cast a huge ray.
	for _, point in self._points do
		self._lastPositions[point] = point.WorldPosition
	end
	self._conn = RunService.Heartbeat:Connect(function()
		self:_step()
	end)
end

function WeaponHitbox:HitStop()
	self._active = false
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
end

function WeaponHitbox:_step()
	for _, point in self._points do
		local current = point.WorldPosition
		local last = self._lastPositions[point] or current
		local delta = current - last
		self._lastPositions[point] = current

		if delta.Magnitude <= 1e-3 then
			continue
		end

		local result = workspace:Raycast(last, delta, self._params)
		if result then
			local hitPart = result.Instance
			local model = hitPart:FindFirstAncestorOfClass("Model")
			local humanoid = model and model:FindFirstChildOfClass("Humanoid")
			if humanoid and not self._alreadyHit[humanoid] then
				self._alreadyHit[humanoid] = true
				if self.OnHit then
					self.OnHit(humanoid, hitPart, result)
				end
			end
		end
	end
end

function WeaponHitbox:Destroy()
	self:HitStop()
	table.clear(self._lastPositions)
	table.clear(self._alreadyHit)
	self.OnHit = nil
end

return WeaponHitbox
