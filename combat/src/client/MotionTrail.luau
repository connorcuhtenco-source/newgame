--!strict
-- MotionTrail — emissive slash ribbon for the blade. Wraps a Roblox `Trail`
-- stretched between two attachments running along the cutting edge (base -> tip).
-- As the blade sweeps during the Active frames, the Trail leaves a glowing
-- spiritual streak that fades out over Trail.Lifetime.
--
-- The trail is only emitted during a strike: :slash() enables it for the
-- duration of the swing, then auto-disables so idle movement leaves no streak.
--
-- It auto-locates "TrailTop"/"TrailBottom" attachments on the weapon; if they
-- are missing it creates a sensible pair from the blade's bounds, so it works
-- on both authored meshes and the placeholder katana.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VisualConfig = require(ReplicatedStorage.Combat.VisualConfig)

local MotionTrail = {}
MotionTrail.__index = MotionTrail

export type MotionTrail = typeof(setmetatable({} :: any, MotionTrail))

local function findBlade(weapon: Instance): BasePart?
	local named = weapon:FindFirstChild("Blade")
	if named and named:IsA("BasePart") then
		return named
	end
	-- Fall back to the longest part (a blade is long & thin).
	local best: BasePart? = nil
	local bestLen = 0
	for _, d in weapon:GetDescendants() do
		if d:IsA("BasePart") then
			local len = math.max(d.Size.X, d.Size.Y, d.Size.Z)
			if len > bestLen then
				bestLen, best = len, d
			end
		end
	end
	return best
end

local function ensureAttachments(weapon: Instance): (Attachment?, Attachment?)
	local top = weapon:FindFirstChild("TrailTop", true)
	local bottom = weapon:FindFirstChild("TrailBottom", true)
	if top and top:IsA("Attachment") and bottom and bottom:IsA("Attachment") then
		return top, bottom
	end

	local blade = findBlade(weapon)
	if not blade then
		return nil, nil
	end
	-- Blade is modeled long on its local Z; place the ribbon along that edge.
	local halfLen = math.max(blade.Size.X, blade.Size.Y, blade.Size.Z) / 2
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailBottom"
	a0.Position = Vector3.new(0, 0, halfLen) -- near the guard
	a0.Parent = blade
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailTop"
	a1.Position = Vector3.new(0, 0, -halfLen) -- near the tip
	a1.Parent = blade
	return a1, a0
end

function MotionTrail.new(weapon: Instance): MotionTrail
	local cfg = VisualConfig.Trail
	local top, bottom = ensureAttachments(weapon)

	local trail = Instance.new("Trail")
	trail.Enabled = false
	trail.Lifetime = cfg.Lifetime
	trail.MinLength = cfg.MinLength
	trail.LightEmission = cfg.LightEmission
	trail.LightInfluence = cfg.LightInfluence
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(cfg.Color)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, cfg.Transparency[1]),
		NumberSequenceKeypoint.new(1, cfg.Transparency[2]),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, cfg.WidthCurve[1]),
		NumberSequenceKeypoint.new(1, cfg.WidthCurve[2]),
	})
	if cfg.Texture ~= "" then
		trail.Texture = cfg.Texture
		trail.TextureMode = Enum.TextureMode.Stretch
	end

	if top and bottom then
		trail.Attachment0 = bottom
		trail.Attachment1 = top
		trail.Parent = top.Parent :: Instance
	else
		warn("[MotionTrail] could not place trail attachments on weapon")
	end

	local self = setmetatable({
		_trail = trail,
		_token = 0,
	}, MotionTrail)
	return self :: any
end

-- Enable the ribbon for `duration` seconds (the swing's active window), then
-- fade. Re-calling restarts the timer so chained combo hits stay streaked.
function MotionTrail:slash(duration: number)
	if not self._trail.Attachment0 then
		return
	end
	self._trail.Enabled = true
	self._token += 1
	local myToken = self._token
	task.delay(duration, function()
		if myToken == self._token then
			self._trail.Enabled = false
		end
	end)
end

function MotionTrail:setEnabled(on: boolean)
	self._token += 1
	self._trail.Enabled = on
end

function MotionTrail:Destroy()
	self._token += 1
	self._trail:Destroy()
end

return MotionTrail
