--!nonstrict

--[[
    Script: MouseLockController.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/PlayerModule/CameraModule
    Responsabilidade: Gerencia o modo MouseLock e suas teclas, cursor e estado visual.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao implementa regras de gameplay do projeto; apenas apoia camera, controle e compatibilidade do jogador.
    Funcoes principais: new, GetIsMouseLocked, SetIsMouseLocked, GetBindableToggleEvent, GetMouseLockOffset, UpdateMouseLockAvailability
]]
local CommonUtils = script.Parent.Parent:WaitForChild("CommonUtils")
local FlagUtil = require(CommonUtils:WaitForChild("FlagUtil"))
local DEFAULT_MOUSE_LOCK_CURSOR = "rbxasset://textures/MouseLockedCursor.png"

local CONTEXT_ACTION_NAME = "MouseLockSwitchAction"
local MOUSELOCK_ACTION_PRIORITY = Enum.ContextActionPriority.Medium.Value

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ConfigJogador = require(
	ReplicatedStorage:WaitForChild("Jogador")
		:WaitForChild("Camera")
		:WaitForChild("Configuracoes")
		:WaitForChild("ConfigCamera")
)

local CAMERA_OFFSET_FALLBACK = Vector3.new(2, 0, 1)

local PlayersService = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local Settings = UserSettings()
local GameSettings = Settings.GameSettings

local CameraUtils = require(script.Parent:WaitForChild("CameraUtils"))

local FFlagUserFixStuckShiftLock = FlagUtil.getUserFlag("UserFixStuckShiftLock")

local MouseLockController = {}
MouseLockController.__index = MouseLockController

function MouseLockController.new()
	local self = setmetatable({}, MouseLockController)

	self.isMouseLocked = false
	self.savedMouseCursor = nil

	local toggleKey = ConfigJogador.ObterConfiguracao("ToggleKey") or Enum.KeyCode.LeftControl
	self.boundKeys = { toggleKey }

	self.mouseLockToggledEvent = Instance.new("BindableEvent")

	local boundKeysObj = script:FindFirstChild("BoundKeys")
	if (not boundKeysObj) or (not boundKeysObj:IsA("StringValue")) then
		if boundKeysObj then
			boundKeysObj:Destroy()
		end

		boundKeysObj = Instance.new("StringValue")

		assert(boundKeysObj, "")
		boundKeysObj.Name = "BoundKeys"

		boundKeysObj.Value = "LeftControl"
		boundKeysObj.Parent = script
	end

	if boundKeysObj then
		boundKeysObj.Changed:Connect(function(value)
			self:OnBoundKeysObjectChanged(value)
		end)
		self:OnBoundKeysObjectChanged(boundKeysObj.Value)
	end

	GameSettings.Changed:Connect(function(property)
		if property == "ControlMode" or property == "ComputerMovementMode" then
			self:UpdateMouseLockAvailability()
		end
	end)

	PlayersService.LocalPlayer:GetPropertyChangedSignal("DevEnableMouseLock"):Connect(function()
		self:UpdateMouseLockAvailability()
	end)

	PlayersService.LocalPlayer:GetPropertyChangedSignal("DevComputerMovementMode"):Connect(function()
		self:UpdateMouseLockAvailability()
	end)

	UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
		self:UpdateMouseLockAvailability()
	end)

	self:UpdateMouseLockAvailability()

	return self
end

function MouseLockController:GetIsMouseLocked()
	return self.isMouseLocked
end

function MouseLockController:SetIsMouseLocked(mouseLocked: boolean)
	if self.isMouseLocked == mouseLocked then
		return
	end

	self.isMouseLocked = mouseLocked

	if self.isMouseLocked then
		local cursorImageValueObj: StringValue? = script:FindFirstChild("CursorImage") :: StringValue?
		if cursorImageValueObj and cursorImageValueObj:IsA("StringValue") and cursorImageValueObj.Value then
			CameraUtils.setMouseIconOverride(cursorImageValueObj.Value)
		else
			if cursorImageValueObj then
				cursorImageValueObj:Destroy()
			end
			cursorImageValueObj = Instance.new("StringValue")
			assert(cursorImageValueObj, "")
			cursorImageValueObj.Name = "CursorImage"
			cursorImageValueObj.Value = DEFAULT_MOUSE_LOCK_CURSOR
			cursorImageValueObj.Parent = script
			CameraUtils.setMouseIconOverride(DEFAULT_MOUSE_LOCK_CURSOR)
		end
	else
		CameraUtils.restoreMouseIcon()
	end

	self.mouseLockToggledEvent:Fire()
end

function MouseLockController:GetBindableToggleEvent()
	return self.mouseLockToggledEvent.Event
end

function MouseLockController:GetMouseLockOffset()
	return ConfigJogador.ObterConfiguracao("OffsetShoulder") or CAMERA_OFFSET_FALLBACK
end

function MouseLockController:UpdateMouseLockAvailability()
	local userUsingKeyboardAndMouse = UserInputService.PreferredInput == Enum.PreferredInput.KeyboardAndMouse
		or UserInputService.KeyboardEnabled

	local MouseLockAvailable = userUsingKeyboardAndMouse

	if MouseLockAvailable ~= self.enabled then
		self:EnableMouseLock(MouseLockAvailable)
	end
end

function MouseLockController:OnBoundKeysObjectChanged(newValue: string)
	self.boundKeys = {}
	for token in string.gmatch(newValue, "[^%s,]+") do
		for _, keyEnum in pairs(Enum.KeyCode:GetEnumItems()) do
			if token == keyEnum.Name then
				self.boundKeys[#self.boundKeys + 1] = keyEnum :: Enum.KeyCode
				break
			end
		end
	end
	self:UnbindContextActions()
	self:BindContextActions()
end

function MouseLockController:OnMouseLockToggled()
	self:SetIsMouseLocked(not self.isMouseLocked)
end

function MouseLockController:DoMouseLockSwitch(_name, state, _input)
	if state == Enum.UserInputState.Begin then
		self:OnMouseLockToggled()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

function MouseLockController:BindContextActions()
	ContextActionService:BindActionAtPriority(CONTEXT_ACTION_NAME, function(name, state, input)
		return self:DoMouseLockSwitch(name, state, input)
	end, false, MOUSELOCK_ACTION_PRIORITY, unpack(self.boundKeys))
end

function MouseLockController:UnbindContextActions()
	ContextActionService:UnbindAction(CONTEXT_ACTION_NAME)
end

function MouseLockController:IsMouseLocked(): boolean
	return self.enabled and self.isMouseLocked
end

function MouseLockController:EnableMouseLock(enable: boolean)
	if enable ~= self.enabled then
		self.enabled = enable

		if self.enabled then
			self:BindContextActions()
		else
			CameraUtils.restoreMouseIcon()

			self:UnbindContextActions()

			if FFlagUserFixStuckShiftLock then
				if self.isMouseLocked then
					self.isMouseLocked = false
					self.mouseLockToggledEvent:Fire()
				end
			else
				if self.isMouseLocked then
					self.mouseLockToggledEvent:Fire()
				end

				self.isMouseLocked = false
			end
		end
	end
end

return MouseLockController
