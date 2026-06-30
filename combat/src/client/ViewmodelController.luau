--!strict
-- ViewmodelController — owns the first-person arms + katana that live in the
-- camera. It is purely cosmetic/local: the real, authoritative weapon used for
-- server validation is the one welded to the player's actual character.
--
-- Two responsibilities:
--   1. Keep the viewmodel glued to the camera every render frame.
--   2. Drive the swing/block POSES. Crucially, the swing physically sweeps the
--      blade through an arc so the DmgPoint attachments move through space — that
--      motion is what the WeaponHitbox raycasts along.
--
-- If you provide ReplicatedStorage.Combat.Assets.Viewmodel (a rigged Model with
-- a weapon containing "DmgPoint" attachments) it is used and its animations are
-- played; otherwise a minimal procedural katana is generated so the system is
-- fully runnable out of the box.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Combat.CombatConfig)

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

		-- Procedural swing state (fallback + extra blade sweep on top of anims).
		_swinging = false,
		_swingT = 0,
		_swingDur = 0.001,
		_swingArc = CFrame.identity,
		_blocking = false,
	}, ViewmodelController)

	self:_buildModel()
	self:_loadAnimations()
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

-- Plays hit `combo`'s swing. Alternates the arc direction for a real combo feel.
function ViewmodelController:playSwing(combo: number)
	local track = self._tracks["Swing" .. combo]
	if track then
		track:Play(0.05)
	end

	-- Procedural arc: alternate diagonal slashes; the finisher is a big overhead.
	local dir = (combo % 2 == 1) and 1 or -1
	local startArc, endArc
	if combo >= CombatConfig.Combo.MaxHits then
		startArc = CFrame.Angles(math.rad(-70), 0, 0)
		endArc = CFrame.Angles(math.rad(55), 0, 0)
	else
		startArc = CFrame.Angles(math.rad(-25), math.rad(35 * dir), math.rad(60 * dir))
		endArc = CFrame.Angles(math.rad(20), math.rad(-40 * dir), math.rad(-50 * dir))
	end

	self._swinging = true
	self._swingT = 0
	self._swingDur = CombatConfig.Combo.Frames.Windup + CombatConfig.Combo.Frames.Active
	self._swingStartArc = startArc
	self._swingEndArc = endArc
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

local function easeOutCubic(t: number): number
	local f = 1 - t
	return 1 - f * f * f
end

function ViewmodelController:_render(dt: number)
	local model = self._model
	local root = self._root
	local camera = Workspace.CurrentCamera
	if not model or not root or not camera then
		return
	end

	local baseOffset = self._blocking and BLOCK_OFFSET or REST_OFFSET
	local swingArc = CFrame.identity

	if self._swinging then
		self._swingT += dt
		local alpha = math.clamp(self._swingT / self._swingDur, 0, 1)
		swingArc = (self._swingStartArc :: CFrame):Lerp(self._swingEndArc :: CFrame, easeOutCubic(alpha))
		if alpha >= 1 then
			self._swinging = false
		end
	end

	local target = camera.CFrame * baseOffset * swingArc
	model:PivotTo(target)
end

function ViewmodelController:Destroy()
	self:stop()
	if self._model then
		self._model:Destroy()
	end
end

return ViewmodelController
