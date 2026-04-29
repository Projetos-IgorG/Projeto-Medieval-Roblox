--!nonstrict

--[[
    Script: VehicleController.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/PlayerModule/ControlModule
    Responsabilidade: Controla movimento do jogador quando esta sentado em veiculos.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao implementa regras de gameplay do projeto; apenas apoia camera, controle e compatibilidade do jogador.
    Funcoes principais: new, BindContextActions, Enable, OnThrottleAccel, OnThrottleDeccel, OnSteerRight
]]
local ContextActionService = game:GetService("ContextActionService")

local useTriggersForThrottle = true

local onlyTriggersForThrottle = false
local ZERO_VECTOR3 = Vector3.new(0,0,0)

local AUTO_PILOT_DEFAULT_MAX_STEERING_ANGLE = 35

local VehicleController = {}
VehicleController.__index = VehicleController

function VehicleController.new(CONTROL_ACTION_PRIORITY)
	local self = setmetatable({}, VehicleController)

	self.CONTROL_ACTION_PRIORITY = CONTROL_ACTION_PRIORITY

	self.enabled = false
	self.vehicleSeat = nil
	self.throttle = 0
	self.steer = 0

	self.acceleration = 0
	self.decceleration = 0
	self.turningRight = 0
	self.turningLeft = 0

	self.vehicleMoveVector = ZERO_VECTOR3

	self.autoPilot = {}
	self.autoPilot.MaxSpeed = 0
	self.autoPilot.MaxSteeringAngle = 0

	return self
end

function VehicleController:BindContextActions()
	if useTriggersForThrottle then
		ContextActionService:BindActionAtPriority("throttleAccel", (function(actionName, inputState, inputObject)
			self:OnThrottleAccel(actionName, inputState, inputObject)
			return Enum.ContextActionResult.Pass
		end), false, self.CONTROL_ACTION_PRIORITY, Enum.KeyCode.ButtonR2)
		ContextActionService:BindActionAtPriority("throttleDeccel", (function(actionName, inputState, inputObject)
			self:OnThrottleDeccel(actionName, inputState, inputObject)
			return Enum.ContextActionResult.Pass
		end), false, self.CONTROL_ACTION_PRIORITY, Enum.KeyCode.ButtonL2)
	end
	ContextActionService:BindActionAtPriority("arrowSteerRight", (function(actionName, inputState, inputObject)
		self:OnSteerRight(actionName, inputState, inputObject)
		return Enum.ContextActionResult.Pass
	end), false, self.CONTROL_ACTION_PRIORITY, Enum.KeyCode.Right)
	ContextActionService:BindActionAtPriority("arrowSteerLeft", (function(actionName, inputState, inputObject)
		self:OnSteerLeft(actionName, inputState, inputObject)
		return Enum.ContextActionResult.Pass
	end), false, self.CONTROL_ACTION_PRIORITY, Enum.KeyCode.Left)
end

function VehicleController:Enable(enable: boolean, vehicleSeat: VehicleSeat)
	if enable == self.enabled and vehicleSeat == self.vehicleSeat then
		return
	end

	self.enabled = enable
	self.vehicleMoveVector = ZERO_VECTOR3

	if enable then
		if vehicleSeat then
			self.vehicleSeat = vehicleSeat

			self:SetupAutoPilot()
			self:BindContextActions()
		end
	else
		if useTriggersForThrottle then
			ContextActionService:UnbindAction("throttleAccel")
			ContextActionService:UnbindAction("throttleDeccel")
		end
		ContextActionService:UnbindAction("arrowSteerRight")
		ContextActionService:UnbindAction("arrowSteerLeft")
		self.vehicleSeat = nil
	end
end

function VehicleController:OnThrottleAccel(_actionName, inputState, _inputObject)
	if inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		self.acceleration = 0
	else
		self.acceleration = -1
	end
	self.throttle = self.acceleration + self.decceleration
end

function VehicleController:OnThrottleDeccel(_actionName, inputState, _inputObject)
	if inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		self.decceleration = 0
	else
		self.decceleration = 1
	end
	self.throttle = self.acceleration + self.decceleration
end

function VehicleController:OnSteerRight(_actionName, inputState, _inputObject)
	if inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		self.turningRight = 0
	else
		self.turningRight = 1
	end
	self.steer = self.turningRight + self.turningLeft
end

function VehicleController:OnSteerLeft(_actionName, inputState, _inputObject)
	if inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		self.turningLeft = 0
	else
		self.turningLeft = -1
	end
	self.steer = self.turningRight + self.turningLeft
end

function VehicleController:Update(moveVector: Vector3, cameraRelative: boolean, usingGamepad: boolean)
	if self.vehicleSeat then
		if cameraRelative then

			moveVector = moveVector + Vector3.new(self.steer, 0, self.throttle)
			if usingGamepad and onlyTriggersForThrottle and useTriggersForThrottle then
				self.vehicleSeat.ThrottleFloat = -self.throttle
			else
				self.vehicleSeat.ThrottleFloat = -moveVector.Z
			end
			self.vehicleSeat.SteerFloat = moveVector.X

			return moveVector, true
		else

			local localMoveVector = self.vehicleSeat.Occupant.RootPart.CFrame:VectorToObjectSpace(moveVector)

			self.vehicleSeat.ThrottleFloat = self:ComputeThrottle(localMoveVector)
			self.vehicleSeat.SteerFloat = self:ComputeSteer(localMoveVector)

			return ZERO_VECTOR3, true
		end
	end
	return moveVector, false
end

function VehicleController:ComputeThrottle(localMoveVector)
	if localMoveVector ~= ZERO_VECTOR3 then
		local throttle = -localMoveVector.Z
		return throttle
	else
		return 0.0
	end
end

function VehicleController:ComputeSteer(localMoveVector)
	if localMoveVector ~= ZERO_VECTOR3 then
		local steerAngle = -math.atan2(-localMoveVector.x, -localMoveVector.z) * (180 / math.pi)
		return steerAngle / self.autoPilot.MaxSteeringAngle
	else
		return 0.0
	end
end

function VehicleController:SetupAutoPilot()

	self.autoPilot.MaxSpeed = self.vehicleSeat.MaxSpeed
	self.autoPilot.MaxSteeringAngle = AUTO_PILOT_DEFAULT_MAX_STEERING_ANGLE

end

return VehicleController
