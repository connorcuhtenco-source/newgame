--!strict
-- InputController — thin translation layer from raw user input to combat verbs.
-- It deliberately knows nothing about state; it just reports "attack pressed"
-- and "block held" so the state machine remains the single decision-maker.
-- Supports mouse + touch + gamepad so the same controller works everywhere.

local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local InputController = {}
InputController.__index = InputController

export type Handlers = {
	onAttack: () -> (),
	onBlockChanged: (held: boolean) -> (),
}

export type InputController = typeof(setmetatable({} :: any, InputController))

local ATTACK_ACTION = "SoulriftAttack"
local BLOCK_ACTION = "SoulriftBlock"

function InputController.new(handlers: Handlers): InputController
	local self = setmetatable({
		_handlers = handlers,
		_enabled = true,
	}, InputController)
	self:_bind()
	return self :: any
end

function InputController:_bind()
	ContextActionService:BindAction(ATTACK_ACTION, function(_, inputState: Enum.UserInputState)
		if not self._enabled then
			return Enum.ContextActionResult.Pass
		end
		if inputState == Enum.UserInputState.Begin then
			self._handlers.onAttack()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)

	ContextActionService:BindAction(BLOCK_ACTION, function(_, inputState: Enum.UserInputState)
		if not self._enabled then
			return Enum.ContextActionResult.Pass
		end
		if inputState == Enum.UserInputState.Begin then
			self._handlers.onBlockChanged(true)
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			self._handlers.onBlockChanged(false)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.F, Enum.KeyCode.ButtonL2)
end

-- When disabled (e.g. while stunned) we also force-release the block so the
-- guard cannot get "stuck" on across a lock-out.
function InputController:setEnabled(enabled: boolean)
	if self._enabled == enabled then
		return
	end
	self._enabled = enabled
	if not enabled then
		self._handlers.onBlockChanged(false)
	end
end

function InputController:Destroy()
	ContextActionService:UnbindAction(ATTACK_ACTION)
	ContextActionService:UnbindAction(BLOCK_ACTION)
end

return InputController
