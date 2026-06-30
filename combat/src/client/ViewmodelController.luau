--!strict
-- ViewmodelController — owns the first-person arms + katana that live in the
-- camera. It is purely cosmetic/local: the real, authoritative weapon used for
-- server validation is the one welded to the player's actual character.
--
-- Presentation is composed every render frame as:
--
--   camera.CFrame * REST * sway * swingArc
--
--   * REST     — the resting hold pose (or BLOCK pose while guarding)
--   * sway     — ViewmodelSway spring offset (look-lag, bob, breathing)
--   * swingArc — SwingArc procedural anticipation/strike/recovery pose
--
-- During a strike a MotionTrail ribbon streaks off the blade, and a small camera
-- roll/tilt (from SwingArc) is applied to sell the momentum of the cut.
--
-- If you provide ReplicatedStorage.Combat.Assets.Viewmodel (a rigged Model with
-- a weapon containing "DmgPoint" attachments) it is used and its animations are
-- played; otherwise a minimal procedural katana is generated so the system is
-- fully runnable out of the box.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Combat.CombatConfig)
local ViewmodelSway = require(script.ViewmodelSway)
local SwingArc = require(script.SwingArc)
local MotionTrail = require(script.MotionTrail)

local ViewmodelController = {}
ViewmodelController.__index = ViewmodelController

local RENDER_NAME = "SoulriftViewmodel"

-- Resting offset of the weapon relative to the camera (right hand, low ready).
local REST_OFFSET = CFrame.new(0.9, -1.0, -1.6) * CFrame.Angles(math.rad(-8), math.rad(-10), 0)
-- Pose while guarding: weapon raised across the view.
local BLOCK_OFFSET = CFrame.new(0.35, -0.55, -1.4) * CFrame.Angles(math.rad(10), math.rad(35), math.rad(-75))

export type ViewmodelController = typeof(setmetatable({} :: any, ViewmodelController))

local function buildPlaceholder(): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "Viewmodel"

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.2, 0.2, 0.9)
	handle.Color = Color3.fromRGB(35, 35, 40)
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = model

	local blade = Instance.new("Part")
	blade.Name = "Blade"
	blade.Size = Vector3.new(0.08, 0.08, 4.2)
	blade.Color = Color3.fromRGB(220, 230, 255)
	blade.Material = Enum.Material.Neon
	blade.CanCollide = false
	blade.Massless = true
	blade.CFrame = handle.CFrame * CFrame.new(0, 0, -2.3)
	blade.Parent = model

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = blade
	weld.Parent = handle

	-- DmgPoint attachments spaced along the blade for the raycast hitbox.
	for i = 0, 8 do
		local a = Instance.new("Attachment")
		a.Name = CombatConfig.Hitbox.DamagePointTag
		a.Position = Vector3.new(0, 0, -i * (4.2 / 8))
		a.Parent = blade
	end

	model.PrimaryPart = handle
	return model, handle
end

function ViewmodelController.new(): ViewmodelController
	local self = setmetatable({
		_model = nil :: Model?,
		_root = nil :: BasePart?,
		_weapon = nil :: Instance?,
		_animator = nil :: Animator?,
		_tracks = {} :: { [string]: AnimationTrack },
		_running = false,

		_sway = ViewmodelSway.new(),
		_trail = nil :: MotionTrail.MotionTrail?,
		_speed01 = 0,

		-- Procedural swing state.
		_swinging = false,
		_swingT = 0,
		_swingDur = SwingArc.duration(),
		_swingCombo = 1,
		_blocking = false,
	}, ViewmodelController)

	self:_buildModel()
	self:_loadAnimations()
	if self._weapon then
		self._trail = MotionTrail.new(self._weapon)
	end
	return self :: any
end

function ViewmodelController:_buildModel()
	local assets = ReplicatedStorage.Combat:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild("Viewmodel")
	local model: Model
	if template and template:IsA("Model") then
		model = template:Clone()
	else
		model = (buildPlaceholder())
	end

	model.Name = "SoulriftViewmodel"
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false -- never block the player's own camera rays
			d.Massless = true
			d.CastShadow = false
		end
	end

	self._model = model
	self._root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	-- The "weapon" is whatever subtree holds the DmgPoint attachments.
	self._weapon = model
	model.Parent = Workspace.CurrentCamera
end

function ViewmodelController:_loadAnimations()
	local model = self._model
	if not model then
		return
	end
	local animator = model:FindFirstChildWhichIsA("Animator", true)
	if not animator then
		local controller = model:FindFirstChildWhichIsA("AnimationController")
			or model:FindFirstChildWhichIsA("Humanoid")
		if not controller then
			controller = Instance.new("AnimationController")
			controller.Parent = model
		end
		animator = Instance.new("Animator")
		animator.Parent = controller
	end
	self._animator = animator

	local function tryLoad(key: string, id: string)
		if id == "" or id == "rbxassetid://0" then
			return
		end
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local ok, track = pcall(function()
			return (animator :: Animator):LoadAnimation(anim)
		end)
		if ok and track then
			self._tracks[key] = track
		end
	end

	for i, id in CombatConfig.Animations.Swings do
		tryLoad("Swing" .. i, id)
	end
	tryLoad("BlockIdle", CombatConfig.Animations.BlockIdle)
	tryLoad("BlockImpact", CombatConfig.Animations.BlockImpact)
	tryLoad("Stunned", CombatConfig.Animations.Stunned)
end

function ViewmodelController:start()
	if self._running then
		return
	end
	self._running = true
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 2, function(dt)
		self:_render(dt)
	end)
end

function ViewmodelController:stop()
	self._running = false
	RunService:UnbindFromRenderStep(RENDER_NAME)
end

-- The weapon model whose DmgPoint attachments the hitbox samples.
function ViewmodelController:getWeapon(): Instance?
	return self._weapon
end

-- Fed by the bootstrap each frame: planar move speed normalized 0..1.
function ViewmodelController:setSpeed01(value: number)
	self._speed01 = math.clamp(value, 0, 1)
end

-- Plays hit `combo`'s swing: optional authored anim + procedural arc + trail.
function ViewmodelController:playSwing(combo: number)
	local track = self._tracks["Swing" .. combo]
	if track then
		track:Play(0.05)
	end

	self._swinging = true
	self._swingT = 0
	self._swingCombo = combo
	if self._trail then
		self._trail:slash(self._swingDur + 0.05)
	end
end

function ViewmodelController:setBlocking(isBlocking: boolean)
	self._blocking = isBlocking
	local idle = self._tracks.BlockIdle
	if idle then
		if isBlocking then
			idle:Play(0.1)
		else
			idle:Stop(0.1)
		end
	end
end

function ViewmodelController:playBlockImpact()
	local t = self._tracks.BlockImpact
	if t then
		t:Play(0)
	end
end

function ViewmodelController:playStun(duration: number)
	local t = self._tracks.Stunned
	if t then
		t:Play(0.08)
		task.delay(duration, function()
			if t.IsPlaying then
				t:Stop(0.1)
			end
		end)
	end
end

function ViewmodelController:_render(dt: number)
	local model = self._model
	local root = self._root
	local camera = Workspace.CurrentCamera
	if not model or not root or not camera then
		return
	end

	local baseOffset = self._blocking and BLOCK_OFFSET or REST_OFFSET

	-- Spring hand-sway (look-lag, bob, breathing).
	local swayOffset = self._sway:update(dt, camera, self._speed01)

	-- Procedural swing arc + coupled camera tilt.
	local swingOffset = CFrame.identity
	if self._swinging then
		self._swingT += dt
		local alpha = math.clamp(self._swingT / self._swingDur, 0, 1)
		local result = SwingArc.evaluate(self._swingCombo, alpha)
		swingOffset = result.offset
		-- Tilt the view INTO the swing (applied after the camera is positioned).
		if result.cameraRoll ~= 0 or result.cameraPitch ~= 0 then
			camera.CFrame = camera.CFrame * CFrame.Angles(result.cameraPitch, 0, result.cameraRoll)
		end
		if alpha >= 1 then
			self._swinging = false
		end
	end

	model:PivotTo(camera.CFrame * baseOffset * swayOffset * swingOffset)
end

function ViewmodelController:Destroy()
	self:stop()
	if self._trail then
		self._trail:Destroy()
	end
	if self._model then
		self._model:Destroy()
	end
end

return ViewmodelController
