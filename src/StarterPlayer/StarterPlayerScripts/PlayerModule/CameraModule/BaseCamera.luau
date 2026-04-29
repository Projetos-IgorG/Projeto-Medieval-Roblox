--!nonstrict
--!nolint DeprecatedApi

--[[
    Script: BaseCamera.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/PlayerModule/CameraModule
    Responsabilidade: Define a classe base compartilhada pelos controladores de camera.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao implementa regras de gameplay do projeto; apenas apoia camera, controle e compatibilidade do jogador.
    Funcoes principais: new, GetModuleName, _setUpConfigurations, OnCharacterAdded, GetHumanoidRootPart, GetBodyPartToFollow
]]
local Players = game:GetService("Players")
local VRService = game:GetService("VRService")
local UserGameSettings = UserSettings():GetService("UserGameSettings")

local CommonUtils = script.Parent.Parent:WaitForChild("CommonUtils")
local ConnectionUtil = require(CommonUtils:WaitForChild("ConnectionUtil"))

local CameraUtils = require(script.Parent:WaitForChild("CameraUtils"))
local ZoomController = require(script.Parent:WaitForChild("ZoomController"))
local CameraToggleStateController = require(script.Parent:WaitForChild("CameraToggleStateController"))
local CameraInput = require(script.Parent:WaitForChild("CameraInput"))
local CameraUI = require(script.Parent:WaitForChild("CameraUI"))

local player = Players.LocalPlayer

local FFlagUserFixGamepadMaxZoom
do
	local success, result = pcall(function()
		return UserSettings():IsUserFeatureEnabled("UserFixGamepadMaxZoom")
	end)
	FFlagUserFixGamepadMaxZoom = success and result
end

local UNIT_Z = Vector3.new(0, 0, 1)
local X1_Y0_Z1 = Vector3.new(1, 0, 1)

local DEFAULT_DISTANCE = 12.5

local MIN_Y = math.rad(-80)
local MAX_Y = math.rad(80)

local VR_ANGLE = math.rad(15)

local ZERO_VECTOR3 = Vector3.new(0, 0, 0)

local SEAT_OFFSET = Vector3.new(0, 5, 0)
local HEAD_OFFSET = Vector3.new(0, 1.5, 0)
local R15_HEAD_OFFSET = Vector3.new(0, 1.5, 0)
local R15_HEAD_OFFSET_NO_SCALING = Vector3.new(0, 2, 0)
local HUMANOID_ROOT_PART_SIZE = Vector3.new(2, 2, 1)

local ZOOM_SENSITIVITY_CURVATURE = 0.5

local CONNECTIONS = {
	CHARACTER_ADDED = "CHARACTER_ADDED",
	CAMERA_MODE_CHANGED = "CAMERA_MODE_CHANGED",
	CAMERA_MIN_DISTANCE_CHANGED = "CAMERA_MIN_DISTANCE_CHANGED",
	CAMERA_MAX_DISTANCE_CHANGED = "CAMERA_MAX_DISTANCE_CHANGED",
}

type BaseCameraClass = {
	__index: BaseCameraClass,
	new: () -> BaseCamera,

	_setUpConfigurations: (self: BaseCamera) -> (),
}

export type BaseCamera = typeof(setmetatable(
	{} :: {
		_connections: ConnectionUtil.ConnectionUtil,
	},
	{} :: BaseCameraClass
))

local BaseCamera = {}
BaseCamera.__index = BaseCamera

function BaseCamera.new()
	local self = setmetatable({}, BaseCamera)

	self._connections = ConnectionUtil.new()

	self.gamepadZoomLevels = { 0, 10, 20 }

	self.cameraType = nil
	self.cameraMovementMode = nil

	self.lastCameraTransform = nil
	self.lastUserPanCamera = tick()

	self.humanoidRootPart = nil
	self.humanoidCache = {}

	self.lastSubject = nil
	self.lastSubjectPosition = Vector3.new(0, 5, 0)
	self.lastSubjectCFrame = CFrame.new(self.lastSubjectPosition)

	self.currentSubjectDistance =
		math.clamp(DEFAULT_DISTANCE, player.CameraMinZoomDistance, player.CameraMaxZoomDistance)

	self.inFirstPerson = false
	self.inMouseLockedMode = false

	self.resetCameraAngle = true

	self.enabled = false

	self.cameraChangedConn = nil

	self.shouldUseVRRotation = false
	self.VRRotationIntensityAvailable = false
	self.lastVRRotationIntensityCheckTime = 0
	self.lastVRRotationTime = 0
	self.vrRotateKeyCooldown = {}
	self.cameraTranslationConstraints = Vector3.new(1, 1, 1)
	self.humanoidJumpOrigin = nil
	self.trackingHumanoid = nil
	self.cameraFrozen = false
	self.subjectStateChangedConn = nil

	self.gamepadZoomPressConnection = nil

	self.mouseLockOffset = ZERO_VECTOR3

	UserGameSettings:SetCameraYInvertVisible()
	UserGameSettings:SetGamepadCameraSensitivityVisible()

	return self
end

function BaseCamera:GetModuleName()
	return "BaseCamera"
end

function BaseCamera:_setUpConfigurations()
	self._connections:trackConnection(
		CONNECTIONS.CHARACTER_ADDED,
		player.CharacterAdded:Connect(function(char)
			self:OnCharacterAdded(char)
		end)
	)
	self.humanoidRootPart = nil

	self._connections:trackConnection(
		CONNECTIONS.CAMERA_MODE_CHANGED,
		player:GetPropertyChangedSignal("CameraMode"):Connect(function()
			self:OnPlayerCameraPropertyChange()
		end)
	)
	self._connections:trackConnection(
		CONNECTIONS.CAMERA_MIN_DISTANCE_CHANGED,
		player:GetPropertyChangedSignal("CameraMinZoomDistance"):Connect(function()
			self:OnPlayerCameraPropertyChange()
		end)
	)
	self._connections:trackConnection(
		CONNECTIONS.CAMERA_MAX_DISTANCE_CHANGED,
		player:GetPropertyChangedSignal("CameraMaxZoomDistance"):Connect(function()
			self:OnPlayerCameraPropertyChange()
		end)
	)
	self:OnPlayerCameraPropertyChange()
end

function BaseCamera:OnCharacterAdded(_char)

	self.resetCameraAngle = self.resetCameraAngle or self:GetEnabled()
	self.humanoidRootPart = nil
end

function BaseCamera:GetHumanoidRootPart(): BasePart
	if not self.humanoidRootPart then
		if player.Character then
			local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				self.humanoidRootPart = humanoid.RootPart
			end
		end
	end
	return self.humanoidRootPart
end

function BaseCamera:GetBodyPartToFollow(humanoid: Humanoid, _isDead: boolean)

	if humanoid:GetState() == Enum.HumanoidStateType.Dead then
		local character = humanoid.Parent
		if character and character:IsA("Model") then
			return character:FindFirstChild("Head") or humanoid.RootPart
		end
	end

	return humanoid.RootPart
end

function BaseCamera:GetSubjectCFrame(): CFrame
	local result = self.lastSubjectCFrame
	local camera = workspace.CurrentCamera
	local cameraSubject = camera and camera.CameraSubject

	if not cameraSubject then
		return result
	end

	if cameraSubject:IsA("Humanoid") then
		local humanoid = cameraSubject
		local humanoidIsDead = humanoid:GetState() == Enum.HumanoidStateType.Dead

		local cameraOffset = humanoid.CameraOffset

		if self:GetIsMouseLocked() then
			cameraOffset = Vector3.new()
		end

		local bodyPartToFollow = humanoid.RootPart

		if humanoidIsDead then
			if humanoid.Parent and humanoid.Parent:IsA("Model") then
				bodyPartToFollow = humanoid.Parent:FindFirstChild("Head") or bodyPartToFollow
			end
		end

		if bodyPartToFollow and bodyPartToFollow:IsA("BasePart") then
			local heightOffset
			if humanoid.RigType == Enum.HumanoidRigType.R15 then
				if humanoid.AutomaticScalingEnabled then
					heightOffset = R15_HEAD_OFFSET

					local rootPart = humanoid.RootPart
					if bodyPartToFollow == rootPart then
						local rootPartSizeOffset = (rootPart.Size.Y - HUMANOID_ROOT_PART_SIZE.Y) / 2
						heightOffset = heightOffset + Vector3.new(0, rootPartSizeOffset, 0)
					end
				else
					heightOffset = R15_HEAD_OFFSET_NO_SCALING
				end
			else
				heightOffset = HEAD_OFFSET
			end

			if humanoidIsDead then
				heightOffset = ZERO_VECTOR3
			end

			result = bodyPartToFollow.CFrame * CFrame.new(heightOffset + cameraOffset)
		end
	elseif cameraSubject:IsA("BasePart") then
		result = cameraSubject.CFrame
	elseif cameraSubject:IsA("Model") then

		if cameraSubject.PrimaryPart then
			result = cameraSubject.PrimaryPart.CFrame
		else
			result = CFrame.new()
		end
	end

	if result then
		self.lastSubjectCFrame = result
	end

	return result
end

function BaseCamera:GetSubjectVelocity(): Vector3
	local camera = workspace.CurrentCamera
	local cameraSubject = camera and camera.CameraSubject

	if not cameraSubject then
		return ZERO_VECTOR3
	end

	if cameraSubject:IsA("BasePart") then
		return cameraSubject.AssemblyLinearVelocity
	elseif cameraSubject:IsA("Humanoid") then
		local rootPart = cameraSubject.RootPart

		if rootPart then
			return rootPart.AssemblyLinearVelocity
		end
	elseif cameraSubject:IsA("Model") then
		local primaryPart = cameraSubject.PrimaryPart

		if primaryPart then
			return primaryPart.AssemblyLinearVelocity
		end
	end

	return ZERO_VECTOR3
end

function BaseCamera:GetSubjectRotVelocity(): Vector3
	local camera = workspace.CurrentCamera
	local cameraSubject = camera and camera.CameraSubject

	if not cameraSubject then
		return ZERO_VECTOR3
	end

	if cameraSubject:IsA("BasePart") then
		return cameraSubject.AssemblyAngularVelocity
	elseif cameraSubject:IsA("Humanoid") then
		local rootPart = cameraSubject.RootPart

		if rootPart then
			return rootPart.AssemblyAngularVelocity
		end
	elseif cameraSubject:IsA("Model") then
		local primaryPart = cameraSubject.PrimaryPart

		if primaryPart then
			return primaryPart.AssemblyAngularVelocity
		end
	end

	return ZERO_VECTOR3
end

function BaseCamera:StepZoom()
	local zoom: number = self.currentSubjectDistance
	local zoomDelta: number = CameraInput.getZoomDelta()

	if math.abs(zoomDelta) > 0 then
		local newZoom

		if zoomDelta > 0 then
			newZoom = zoom + zoomDelta * (1 + zoom * ZOOM_SENSITIVITY_CURVATURE)
		else
			newZoom = (zoom + zoomDelta) / (1 - zoomDelta * ZOOM_SENSITIVITY_CURVATURE)
		end

		self:SetCameraToSubjectDistance(newZoom)
	end

	return ZoomController.GetZoomRadius()
end

function BaseCamera:GetSubjectPosition(): Vector3?
	local result = self.lastSubjectPosition
	local camera = workspace.CurrentCamera
	local cameraSubject = camera and camera.CameraSubject

	if cameraSubject then
		if cameraSubject:IsA("Humanoid") then
			local humanoid = cameraSubject
			local humanoidIsDead = humanoid:GetState() == Enum.HumanoidStateType.Dead

			local cameraOffset = humanoid.CameraOffset

			if self:GetIsMouseLocked() then
				cameraOffset = Vector3.new()
			end

			local bodyPartToFollow = humanoid.RootPart

			if humanoidIsDead then
				if humanoid.Parent and humanoid.Parent:IsA("Model") then
					bodyPartToFollow = humanoid.Parent:FindFirstChild("Head") or bodyPartToFollow
				end
			end

			if bodyPartToFollow and bodyPartToFollow:IsA("BasePart") then
				local heightOffset
				if humanoid.RigType == Enum.HumanoidRigType.R15 then
					if humanoid.AutomaticScalingEnabled then
						heightOffset = R15_HEAD_OFFSET
						if bodyPartToFollow == humanoid.RootPart then
							local rootPartSizeOffset = (humanoid.RootPart.Size.Y / 2) - (HUMANOID_ROOT_PART_SIZE.Y / 2)
							heightOffset = heightOffset + Vector3.new(0, rootPartSizeOffset, 0)
						end
					else
						heightOffset = R15_HEAD_OFFSET_NO_SCALING
					end
				else
					heightOffset = HEAD_OFFSET
				end

				if humanoidIsDead then
					heightOffset = ZERO_VECTOR3
				end

				result = bodyPartToFollow.CFrame.Position
					+ bodyPartToFollow.CFrame:vectorToWorldSpace(heightOffset + cameraOffset)
			end
		elseif cameraSubject:IsA("VehicleSeat") then
			local offset = SEAT_OFFSET
			result = cameraSubject.CFrame.Position + cameraSubject.CFrame:vectorToWorldSpace(offset)
		elseif cameraSubject:IsA("SkateboardPlatform") then
			result = cameraSubject.CFrame.Position + SEAT_OFFSET
		elseif cameraSubject:IsA("BasePart") then
			result = cameraSubject.CFrame.Position
		elseif cameraSubject:IsA("Model") then
			if cameraSubject.PrimaryPart then
				result = cameraSubject.PrimaryPart.CFrame.Position
			else
				result = cameraSubject:GetModelCFrame().Position
			end
		end
	else

		return nil
	end

	self.lastSubject = cameraSubject
	self.lastSubjectPosition = result

	return result
end

function BaseCamera:OnCurrentCameraChanged()

	if self.cameraSubjectChangedConn then
		self.cameraSubjectChangedConn:Disconnect()
		self.cameraSubjectChangedConn = nil
	end

	local camera = workspace.CurrentCamera
	if camera then
		self.cameraSubjectChangedConn = camera:GetPropertyChangedSignal("CameraSubject"):Connect(function()
			self:OnNewCameraSubject()
		end)
		self:OnNewCameraSubject()
	end
end

function BaseCamera:OnPlayerCameraPropertyChange()

	self:SetCameraToSubjectDistance(self.currentSubjectDistance)
end

function BaseCamera:InputTranslationToCameraAngleChange(translationVector, sensitivity)
	return translationVector * sensitivity
end

function BaseCamera:GamepadZoomPress()

	local dist = self:GetCameraToSubjectDistance()

	local max = player.CameraMaxZoomDistance

	for i = #self.gamepadZoomLevels, 1, -1 do
		local zoom = self.gamepadZoomLevels[i]

		if max < zoom then
			continue
		end

		if zoom < player.CameraMinZoomDistance then
			zoom = player.CameraMinZoomDistance
			if FFlagUserFixGamepadMaxZoom then

				if max == zoom then
					break
				end
			end
		end

		if not FFlagUserFixGamepadMaxZoom then
			if max == zoom then
				break
			end
		end

		if dist > zoom + (max - zoom) / 2 then
			self:SetCameraToSubjectDistance(zoom)
			return
		end

		max = zoom
	end

	self:SetCameraToSubjectDistance(self.gamepadZoomLevels[#self.gamepadZoomLevels])
end

function BaseCamera:Enable(enable: boolean)
	if self.enabled ~= enable then
		self.enabled = enable

		self:OnEnabledChanged()
	end
end

function BaseCamera:OnEnabledChanged()
	if self.enabled then
		self:_setUpConfigurations()

		CameraInput.setInputEnabled(true)

		self.gamepadZoomPressConnection = CameraInput.gamepadZoomPress:Connect(function()
			self:GamepadZoomPress()
		end)

		if player.CameraMode == Enum.CameraMode.LockFirstPerson then
			self.currentSubjectDistance = 0.5
			if not self.inFirstPerson then
				self:EnterFirstPerson()
			end
		end

		if self.cameraChangedConn then
			self.cameraChangedConn:Disconnect()
			self.cameraChangedConn = nil
		end
		self.cameraChangedConn = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
			self:OnCurrentCameraChanged()
		end)
		self:OnCurrentCameraChanged()
	else
		self._connections:disconnectAll()

		CameraInput.setInputEnabled(false)

		if self.gamepadZoomPressConnection then
			self.gamepadZoomPressConnection:Disconnect()
			self.gamepadZoomPressConnection = nil
		end

		self:Cleanup()
	end
end

function BaseCamera:GetEnabled(): boolean
	return self.enabled
end

function BaseCamera:Cleanup()
	if self.subjectStateChangedConn then
		self.subjectStateChangedConn:Disconnect()
		self.subjectStateChangedConn = nil
	end
	if self.cameraChangedConn then
		self.cameraChangedConn:Disconnect()
		self.cameraChangedConn = nil
	end

	self.lastCameraTransform = nil
	self.lastSubjectCFrame = nil

	CameraUtils.restoreMouseBehavior()
end

function BaseCamera:UpdateMouseBehavior()
	local blockToggleDueToClickToMove = UserGameSettings.ComputerMovementMode == Enum.ComputerMovementMode.ClickToMove

	if self.isCameraToggle and blockToggleDueToClickToMove == false then
		CameraUI.setCameraModeToastEnabled(true)
		CameraInput.enableCameraToggleInput()
		CameraToggleStateController(self.inFirstPerson)
	else
		CameraUI.setCameraModeToastEnabled(false)
		CameraInput.disableCameraToggleInput()

		if self.inFirstPerson or self.inMouseLockedMode then
			CameraUtils.setRotationTypeOverride(Enum.RotationType.CameraRelative)
			CameraUtils.setMouseBehaviorOverride(Enum.MouseBehavior.LockCenter)
		else
			CameraUtils.restoreRotationType()

			local rotationActivated = CameraInput.getRotationActivated()
			if rotationActivated then
				CameraUtils.setMouseBehaviorOverride(Enum.MouseBehavior.LockCurrentPosition)
			else
				CameraUtils.restoreMouseBehavior()
			end
		end
	end
end

function BaseCamera:UpdateForDistancePropertyChange()

	self:SetCameraToSubjectDistance(self.currentSubjectDistance)
end

function BaseCamera:SetCameraToSubjectDistance(desiredSubjectDistance: number): number
	local lastSubjectDistance = self.currentSubjectDistance

	if player.CameraMode == Enum.CameraMode.LockFirstPerson then
		self.currentSubjectDistance = 0.5
		if not self.inFirstPerson then
			self:EnterFirstPerson()
		end
	else
		local newSubjectDistance =
			math.clamp(desiredSubjectDistance, player.CameraMinZoomDistance, player.CameraMaxZoomDistance)
		self.currentSubjectDistance = newSubjectDistance
	end

	ZoomController.SetZoomParameters(
		self.currentSubjectDistance,
		math.sign(desiredSubjectDistance - lastSubjectDistance)
	)

	return self.currentSubjectDistance
end

function BaseCamera:SetCameraType(cameraType)

	self.cameraType = cameraType
end

function BaseCamera:GetCameraType()
	return self.cameraType
end

function BaseCamera:SetCameraMovementMode(cameraMovementMode)
	self.cameraMovementMode = cameraMovementMode
end

function BaseCamera:GetCameraMovementMode()
	return self.cameraMovementMode
end

function BaseCamera:SetIsMouseLocked(mouseLocked: boolean)
	self.inMouseLockedMode = mouseLocked
end

function BaseCamera:GetIsMouseLocked(): boolean
	return self.inMouseLockedMode
end

function BaseCamera:SetMouseLockOffset(offsetVector)
	self.mouseLockOffset = offsetVector
end

function BaseCamera:GetMouseLockOffset()
	return self.mouseLockOffset
end

function BaseCamera:InFirstPerson(): boolean
	return self.inFirstPerson
end

function BaseCamera:SetPrimeiraPessoa(_ativo: boolean)

end

function BaseCamera:EnterFirstPerson()
	self.inFirstPerson = true
	self:UpdateMouseBehavior()
end

function BaseCamera:LeaveFirstPerson()
	self.inFirstPerson = false
	self:UpdateMouseBehavior()
end

function BaseCamera:GetCameraToSubjectDistance(): number
	return self.currentSubjectDistance
end

function BaseCamera:GetMeasuredDistanceToFocus(): number?
	local camera = workspace.CurrentCamera
	if camera then
		return (camera.CFrame.Position - camera.Focus.Position).Magnitude
	end
	return nil
end

function BaseCamera:GetCameraLookVector(): Vector3
	return workspace.CurrentCamera and workspace.CurrentCamera.CFrame.LookVector or UNIT_Z
end

function BaseCamera:CalculateNewLookCFrameFromArg(suppliedLookVector: Vector3?, rotateInput: Vector2): CFrame
	local currLookVector: Vector3 = suppliedLookVector or self:GetCameraLookVector()
	local currPitchAngle = math.asin(currLookVector.Y)
	local yTheta = math.clamp(rotateInput.Y, -MAX_Y + currPitchAngle, -MIN_Y + currPitchAngle)
	local constrainedRotateInput = Vector2.new(rotateInput.X, yTheta)
	local startCFrame = CFrame.new(ZERO_VECTOR3, currLookVector)
	local newLookCFrame = CFrame.Angles(0, -constrainedRotateInput.X, 0)
		* startCFrame
		* CFrame.Angles(-constrainedRotateInput.Y, 0, 0)
	return newLookCFrame
end

function BaseCamera:CalculateNewLookVectorFromArg(suppliedLookVector: Vector3?, rotateInput: Vector2): Vector3
	local newLookCFrame = self:CalculateNewLookCFrameFromArg(suppliedLookVector, rotateInput)
	return newLookCFrame.LookVector
end

function BaseCamera:CalculateNewLookVectorVRFromArg(rotateInput: Vector2): Vector3
	local subjectPosition: Vector3 = self:GetSubjectPosition()
	local vecToSubject: Vector3 = (subjectPosition - (workspace.CurrentCamera :: Camera).CFrame.Position)
	local currLookVector: Vector3 = (vecToSubject * X1_Y0_Z1).unit
	local vrRotateInput: Vector2 = Vector2.new(rotateInput.X, 0)
	local startCFrame: CFrame = CFrame.new(ZERO_VECTOR3, currLookVector)
	local yawRotatedVector: Vector3 = (CFrame.Angles(0, -vrRotateInput.X, 0) * startCFrame * CFrame.Angles(
		-vrRotateInput.Y,
		0,
		0
	)).LookVector
	return (yawRotatedVector * X1_Y0_Z1).unit
end

function BaseCamera:GetHumanoid(): Humanoid?
	local character = player and player.Character
	if character then
		local resultHumanoid = self.humanoidCache[player]
		if resultHumanoid and resultHumanoid.Parent == character then
			return resultHumanoid
		else
			self.humanoidCache[player] = nil
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				self.humanoidCache[player] = humanoid
			end
			return humanoid
		end
	end
	return nil
end

function BaseCamera:GetHumanoidPartToFollow(humanoid: Humanoid, humanoidStateType: Enum.HumanoidStateType)
	if humanoidStateType == Enum.HumanoidStateType.Dead then
		local character = humanoid.Parent
		if character then
			return character:FindFirstChild("Head") or humanoid.RootPart
		else
			return humanoid.RootPart
		end
	else
		return humanoid.RootPart
	end
end

function BaseCamera:OnNewCameraSubject()
	if self.subjectStateChangedConn then
		self.subjectStateChangedConn:Disconnect()
		self.subjectStateChangedConn = nil
	end
end

function BaseCamera:IsInFirstPerson()
	return self.inFirstPerson
end

function BaseCamera:Update(_dt)
	error("BaseCamera:Update() This is a virtual function that should never be getting called.", 2)
end

function BaseCamera:GetCameraHeight()
	if VRService.VREnabled and not self.inFirstPerson then
		return math.sin(VR_ANGLE) * self.currentSubjectDistance
	end
	return 0
end

return BaseCamera
