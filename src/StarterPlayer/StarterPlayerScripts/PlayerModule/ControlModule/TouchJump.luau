--!nonstrict

--[[
    Script: TouchJump.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/PlayerModule/ControlModule
    Responsabilidade: Gerencia botao e estado de pulo em dispositivos de toque.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao implementa regras de gameplay do projeto; apenas apoia camera, controle e compatibilidade do jogador.
    Funcoes principais: new, _reset, EnableButton, UpdateEnabled, _setupConfigurations, Enable
]]
local GuiService = game:GetService("GuiService")

local CommonUtils = script.Parent.Parent:WaitForChild("CommonUtils")

local ConnectionUtil = require(CommonUtils:WaitForChild("ConnectionUtil"))
local CharacterUtil = require(CommonUtils:WaitForChild("CharacterUtil"))

local TOUCH_CONTROL_SHEET = "rbxasset://textures/ui/Input/TouchControlsSheetV2.png"
local CONNECTIONS = {
	HUMANOID_STATE_ENABLED_CHANGED = "HUMANOID_STATE_ENABLED_CHANGED",
	HUMANOID_JUMP_POWER = "HUMANOID_JUMP_POWER",
	HUMANOID_JUMP_HEIGHT = "HUMANOID_JUMP_HEIGHT",
	HUMANOID = "HUMANOID",
	JUMP_INPUT_ENDED = "JUMP_INPUT_ENDED",
	MENU_OPENED = "MENU_OPENED",
}

type TouchJumpClass = {
	new: () -> TouchJump,

	_reset: (self: TouchJump) -> (),

	_setupConfigurations: (self: TouchJump) -> (),
}

export type TouchJump = typeof(setmetatable({} :: {

	_connectionUtil: any,

	_active: boolean
}, {} :: TouchJumpClass))

local BaseCharacterController = require(script.Parent:WaitForChild("BaseCharacterController"))
local TouchJump = setmetatable({}, BaseCharacterController)
TouchJump.__index = TouchJump

function TouchJump.new()
	local self = setmetatable(BaseCharacterController.new() :: any, TouchJump)

	self.parentUIFrame = nil
	self.jumpButton = nil

	self.externallyEnabled = false
	self.isJumping = false
	self._active = false
	self._connectionUtil = ConnectionUtil.new()

	return self
end

function TouchJump:_reset()
	self.isJumping = false
	self.touchObject = nil
	if self.jumpButton then
		self.jumpButton.ImageRectOffset = Vector2.new(1, 146)
	end
end

function TouchJump:EnableButton(enable)
	if enable == self._active then
		return
	end

	if enable then
		if not self.jumpButton then
			self:Create()
		end
		self.jumpButton.Visible = true

		self._connectionUtil:trackConnection(
			CONNECTIONS.JUMP_INPUT_ENDED,
			self.jumpButton.InputEnded:Connect(function(inputObject)
				if inputObject == self.touchObject then
					self:_reset()
				end
			end)
		)

		self._connectionUtil:trackConnection(
			CONNECTIONS.MENU_OPENED,
			GuiService.MenuOpened:Connect(function()
				if self.touchObject then
					self:_reset()
				end
			end)
		)
	else
		if self.jumpButton then
			self.jumpButton.Visible = false
		end
		self._connectionUtil:disconnect(CONNECTIONS.JUMP_INPUT_ENDED)
		self._connectionUtil:disconnect(CONNECTIONS.MENU_OPENED)
	end
	self:_reset()
	self._active = enable
end

function TouchJump:UpdateEnabled()
	local humanoid = CharacterUtil.getChild("Humanoid", "Humanoid")
	if humanoid and self.externallyEnabled and ((humanoid.UseJumpPower and humanoid.JumpPower > 0) or (not humanoid.UseJumpPower and humanoid.JumpHeight > 0)) and humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping) then
		self:EnableButton(true)
	else
		self:EnableButton(false)
	end
end

function TouchJump:_setupConfigurations()
	local function update()
		self:UpdateEnabled()
	end

	local humanoidConnection = CharacterUtil.onChild("Humanoid", "Humanoid", function(humanoid)
		update()
		self:_reset()
		self._connectionUtil:trackConnection(
			CONNECTIONS.HUMANOID_JUMP_POWER,
			humanoid:GetPropertyChangedSignal("JumpPower"):Connect(update)
		)
		self._connectionUtil:trackConnection(
			CONNECTIONS.HUMANOID_JUMP_HEIGHT,
			humanoid:GetPropertyChangedSignal("JumpHeight"):Connect(update)
		)
		self._connectionUtil:trackConnection(
			CONNECTIONS.HUMANOID_STATE_ENABLED_CHANGED,
			humanoid.StateEnabledChanged:Connect(function(state, isEnabled)

				if state == Enum.HumanoidStateType.Jumping and isEnabled ~= self._active then
					update()
				end
			end)
		)
	end)
	self._connectionUtil:trackConnection(CONNECTIONS.HUMANOID, humanoidConnection)
end

function TouchJump:Enable(enable, parentFrame)
	if parentFrame then
		self.parentUIFrame = parentFrame
	end

	if self.externallyEnabled == enable then return end
	self.externallyEnabled = enable

	self:UpdateEnabled()

	if enable then
		self:_setupConfigurations()
	else
		self._connectionUtil:disconnectAll()
	end
end

function TouchJump:Create()
	if not self.parentUIFrame then
		return
	end

	if self.jumpButton then
		self.jumpButton:Destroy()
		self.jumpButton = nil
	end

	if self.absoluteSizeChangedConn then
		self.absoluteSizeChangedConn:Disconnect()
		self.absoluteSizeChangedConn = nil
	end

	self.jumpButton = Instance.new("ImageButton")
	self.jumpButton.Name = "JumpButton"
	self.jumpButton.Visible = false
	self.jumpButton.BackgroundTransparency = 1
	self.jumpButton.Image = TOUCH_CONTROL_SHEET
	self.jumpButton.ImageRectOffset = Vector2.new(1, 146)
	self.jumpButton.ImageRectSize = Vector2.new(144, 144)

	local function ResizeJumpButton()
		local minAxis = math.min(self.parentUIFrame.AbsoluteSize.x, self.parentUIFrame.AbsoluteSize.y)
		local isSmallScreen = minAxis <= 500
		local jumpButtonSize = isSmallScreen and 70 or 120

		self.jumpButton.Size = UDim2.fromOffset(jumpButtonSize, jumpButtonSize)
		self.jumpButton.Position = isSmallScreen and UDim2.new(1, -(jumpButtonSize*1.5-10), 1, -jumpButtonSize - 20) or
			UDim2.new(1, -(jumpButtonSize*1.5-10), 1, -jumpButtonSize * 1.75)
	end

	ResizeJumpButton()
	self.absoluteSizeChangedConn = self.parentUIFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(ResizeJumpButton)

	self.touchObject = nil
	self.jumpButton.InputBegan:connect(function(inputObject)

		if self.touchObject or inputObject.UserInputType ~= Enum.UserInputType.Touch
			or inputObject.UserInputState ~= Enum.UserInputState.Begin then
			return
		end

		self.touchObject = inputObject
		self.jumpButton.ImageRectOffset = Vector2.new(146, 146)
		self.isJumping = true
	end)

	self.jumpButton.Parent = self.parentUIFrame
end

return TouchJump
