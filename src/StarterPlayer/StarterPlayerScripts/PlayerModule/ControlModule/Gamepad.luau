--!nonstrict

--[[
    Script: Gamepad.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/PlayerModule/ControlModule
    Responsabilidade: Converte entrada de gamepad em movimento do personagem.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao implementa regras de gameplay do projeto; apenas apoia camera, controle e compatibilidade do jogador.
    Funcoes principais: new, Enable, GetHighestPriorityGamepad, BindContextActions, UnbindContextActions, OnNewGamepadConnected
]]
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local ZERO_VECTOR3 = Vector3.new(0,0,0)
local NONE = Enum.UserInputType.None
local thumbstickDeadzone = 0.2

local BaseCharacterController = require(script.Parent:WaitForChild("BaseCharacterController"))
local Gamepad = setmetatable({}, BaseCharacterController)
Gamepad.__index = Gamepad

function Gamepad.new(CONTROL_ACTION_PRIORITY)
	local self = setmetatable(BaseCharacterController.new() :: any, Gamepad)

	self.CONTROL_ACTION_PRIORITY = CONTROL_ACTION_PRIORITY

	self.forwardValue  = 0
	self.backwardValue = 0
	self.leftValue = 0
	self.rightValue = 0

	self.activeGamepad = NONE
	self.gamepadConnectedConn = nil
	self.gamepadDisconnectedConn = nil
	return self
end

function Gamepad:Enable(enable: boolean): boolean
	if enable == self.enabled then

		return true
	end

	self.forwardValue  = 0
	self.backwardValue = 0
	self.leftValue = 0
	self.rightValue = 0
	self.moveVector = ZERO_VECTOR3
	self.isJumping = false

	if enable then
		self.activeGamepad = self:GetHighestPriorityGamepad()
		if self.activeGamepad ~= NONE then
			self:BindContextActions()
			self:ConnectGamepadConnectionListeners()
		else

			return false
		end
	else
		self:UnbindContextActions()
		self:DisconnectGamepadConnectionListeners()
		self.activeGamepad = NONE
	end

	self.enabled = enable
	return true
end

function Gamepad:GetHighestPriorityGamepad()
	local connectedGamepads = UserInputService:GetConnectedGamepads()
	local bestGamepad = NONE
	for _, gamepad in pairs(connectedGamepads) do
		if gamepad.Value < bestGamepad.Value then
			bestGamepad = gamepad
		end
	end
	return bestGamepad
end

function Gamepad:BindContextActions()

	if self.activeGamepad == NONE then

		return false
	end

	local handleJumpAction = function(_actionName, inputState, _inputObject)
		self.isJumping = (inputState == Enum.UserInputState.Begin)
		return Enum.ContextActionResult.Sink
	end

	local handleThumbstickInput = function(_actionName, inputState, inputObject)

		if inputState == Enum.UserInputState.Cancel then
			self.moveVector = ZERO_VECTOR3
			return Enum.ContextActionResult.Sink
		end

		if self.activeGamepad ~= inputObject.UserInputType then
			return Enum.ContextActionResult.Pass
		end
		if inputObject.KeyCode ~= Enum.KeyCode.Thumbstick1 then return end

		if inputObject.Position.magnitude > thumbstickDeadzone then
			self.moveVector  =  Vector3.new(inputObject.Position.X, 0, -inputObject.Position.Y)
		else
			self.moveVector = ZERO_VECTOR3
		end
		return Enum.ContextActionResult.Sink
	end

	ContextActionService:BindActivate(self.activeGamepad, Enum.KeyCode.ButtonR2)
	ContextActionService:BindActionAtPriority("jumpAction", handleJumpAction, false,
		self.CONTROL_ACTION_PRIORITY, Enum.KeyCode.ButtonA)
	ContextActionService:BindActionAtPriority("moveThumbstick", handleThumbstickInput, false,
		self.CONTROL_ACTION_PRIORITY, Enum.KeyCode.Thumbstick1)

	return true
end

function Gamepad:UnbindContextActions()
	if self.activeGamepad ~= NONE then
		ContextActionService:UnbindActivate(self.activeGamepad, Enum.KeyCode.ButtonR2)
	end
	ContextActionService:UnbindAction("moveThumbstick")
	ContextActionService:UnbindAction("jumpAction")
end

function Gamepad:OnNewGamepadConnected()

	local bestGamepad: Enum.UserInputType = self:GetHighestPriorityGamepad()

	if bestGamepad == self.activeGamepad then

		return
	end

	if bestGamepad == NONE then

		warn("Gamepad:OnNewGamepadConnected found no connected gamepads")
		self:UnbindContextActions()
		return
	end

	if self.activeGamepad ~= NONE then

		self:UnbindContextActions()
	end

	self.activeGamepad = bestGamepad
	self:BindContextActions()
end

function Gamepad:OnCurrentGamepadDisconnected()
	if self.activeGamepad ~= NONE then
		ContextActionService:UnbindActivate(self.activeGamepad, Enum.KeyCode.ButtonR2)
	end

	local bestGamepad = self:GetHighestPriorityGamepad()

	if self.activeGamepad ~= NONE and bestGamepad == self.activeGamepad then
		warn("Gamepad:OnCurrentGamepadDisconnected found the supposedly disconnected gamepad in connectedGamepads.")
		self:UnbindContextActions()
		self.activeGamepad = NONE
		return
	end

	if bestGamepad == NONE then

		self:UnbindContextActions()
		self.activeGamepad = NONE
	else

		self.activeGamepad = bestGamepad
		ContextActionService:BindActivate(self.activeGamepad, Enum.KeyCode.ButtonR2)
	end
end

function Gamepad:ConnectGamepadConnectionListeners()
	self.gamepadConnectedConn = UserInputService.GamepadConnected:Connect(function(_gamepadEnum)
		self:OnNewGamepadConnected()
	end)

	self.gamepadDisconnectedConn = UserInputService.GamepadDisconnected:Connect(function(gamepadEnum)
		if self.activeGamepad == gamepadEnum then
			self:OnCurrentGamepadDisconnected()
		end
	end)

end

function Gamepad:DisconnectGamepadConnectionListeners()
	if self.gamepadConnectedConn then
		self.gamepadConnectedConn:Disconnect()
		self.gamepadConnectedConn = nil
	end

	if self.gamepadDisconnectedConn then
		self.gamepadDisconnectedConn:Disconnect()
		self.gamepadDisconnectedConn = nil
	end
end

return Gamepad
