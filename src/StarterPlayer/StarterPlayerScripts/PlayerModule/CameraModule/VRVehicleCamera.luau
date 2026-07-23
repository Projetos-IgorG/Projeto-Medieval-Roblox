--!nonstrict

--[[
    Script: VRVehicleCamera.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/PlayerModule/CameraModule
    Responsabilidade: Implementa camera VR quando o jogador esta em veiculos.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao implementa regras de gameplay do projeto; apenas apoia camera, controle e compatibilidade do jogador.
    Funcoes principais: new, Reset, _StepRotation, _GetThirdPersonLocalOffset, _GetFirstPersonLocalOffset, Update
]]
local FFlagUserVRVehicleCamera
do
	local success, result = pcall(function()
		return UserSettings():IsUserFeatureEnabled("UserVRVehicleCamera2")
	end)
	FFlagUserVRVehicleCamera = success and result
end

local EPSILON = 1e-3
local MIN_ASSEMBLY_RADIUS = 5
local PITCH_LIMIT = math.rad(80)
local YAW_DEFAULT = math.rad(0)
local ZOOM_MINIMUM = 0.5
local TP_FOLLOW_DIST = 200
local TP_FOLLOW_ANGLE_DOT = 0.56

local DEFAULT_GAMEPAD_ZOOM_LEVELS = { 0, 30 }

local UserGameSettings = UserSettings():GetService("UserGameSettings")

local VRBaseCamera = require(script.Parent:WaitForChild("VRBaseCamera"))
local CameraInput = require(script.Parent:WaitForChild("CameraInput"))
local CameraUtils = require(script.Parent:WaitForChild("CameraUtils"))
local VehicleCameraCore = require(script.Parent.VehicleCamera:FindFirstChild("VehicleCameraCore")) :: any
local VehicleCameraConfig = require(script.Parent.VehicleCamera:FindFirstChild("VehicleCameraConfig")) :: any
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VRService = game:GetService("VRService")

local localPlayer = Players.LocalPlayer
local Spring = CameraUtils.Spring
local mapClamp = CameraUtils.mapClamp
local sanitizeAngle = CameraUtils.sanitizeAngle

local function pitchVelocity(rotVel, cf)
	return math.abs(cf.XVector:Dot(rotVel))
end

local function yawVelocity(rotVel, cf)
	return math.abs(cf.YVector:Dot(rotVel))
end

local worldDt = 1 / 60
local VRVehicleCamera = setmetatable({}, VRBaseCamera)
VRVehicleCamera.__index = VRVehicleCamera

function VRVehicleCamera.new()
	local self = setmetatable(VRBaseCamera.new(), VRVehicleCamera)
	self:Reset()

	RunService.Stepped:Connect(function(_, _worldDt)
		worldDt = _worldDt
	end)

	return self
end

function VRVehicleCamera:Reset()
	self.vehicleCameraCore = VehicleCameraCore.new(self:GetSubjectCFrame())
	if FFlagUserVRVehicleCamera then
		self.pitchSpring = Spring.new(0, 0)
	else
		self.pitchSpring = Spring.new(0, -math.rad(VehicleCameraConfig.pitchBaseAngle))
	end
	self.yawSpring = Spring.new(0, YAW_DEFAULT)

	if FFlagUserVRVehicleCamera then
		self.lastPanTick = 0
		self.currentDriftAngle = 0
		self.needsReset = true
	end

	local camera = workspace.CurrentCamera
	local cameraSubject = camera and camera.CameraSubject

	assert(camera, "VRVehicleCamera initialization error")
	assert(cameraSubject, "VRVehicleCamera requires a camera subject")
	assert(cameraSubject:IsA("VehicleSeat"), "VRVehicleCamera subject must be a VehicleSeat")

	local assemblyParts = cameraSubject:GetConnectedParts(true)
	local assemblyPosition, assemblyRadius = CameraUtils.getLooseBoundingSphere(assemblyParts)

	assemblyRadius = math.max(assemblyRadius, MIN_ASSEMBLY_RADIUS)

	self.assemblyRadius = assemblyRadius
	self.assemblyOffset = cameraSubject.CFrame:Inverse() * assemblyPosition

	self.gamepadZoomLevels = {}
	for _, zoom in DEFAULT_GAMEPAD_ZOOM_LEVELS do
		table.insert(self.gamepadZoomLevels, zoom * self.headScale * self.assemblyRadius / 10)
	end
	self.lastCameraFocus = nil
	self:SetCameraToSubjectDistance(self.gamepadZoomLevels[#self.gamepadZoomLevels])
end

function VRVehicleCamera:_StepRotation(dt, vdotz): CFrame
	local yawSpring = self.yawSpring
	local pitchSpring = self.pitchSpring

	local rotationInput = self:getRotation(dt)
	local dYaw = -rotationInput

	yawSpring.pos = sanitizeAngle(yawSpring.pos + dYaw)
	pitchSpring.pos = sanitizeAngle(math.clamp(pitchSpring.pos, -PITCH_LIMIT, PITCH_LIMIT))

	if CameraInput.getRotationActivated() then
		self.lastPanTick = os.clock()
	end

	local pitchBaseAngle = 0
	local pitchDeadzoneAngle = math.rad(VehicleCameraConfig.pitchDeadzoneAngle)

	if os.clock() - self.lastPanTick > VehicleCameraConfig.autocorrectDelay then
		local autocorrectResponse = mapClamp(
			vdotz,
			VehicleCameraConfig.autocorrectMinCarSpeed,
			VehicleCameraConfig.autocorrectMaxCarSpeed,
			0,
			VehicleCameraConfig.autocorrectResponse
		)

		yawSpring.freq = autocorrectResponse
		pitchSpring.freq = autocorrectResponse

		if yawSpring.freq < EPSILON then
			yawSpring.vel = 0
		end

		if pitchSpring.freq < EPSILON then
			pitchSpring.vel = 0
		end

		if math.abs(sanitizeAngle(pitchBaseAngle - pitchSpring.pos)) <= pitchDeadzoneAngle then
			pitchSpring.goal = pitchSpring.pos
		else
			pitchSpring.goal = pitchBaseAngle
		end
	else
		yawSpring.freq = 0
		yawSpring.vel = 0

		pitchSpring.freq = 0
		pitchSpring.vel = 0

		pitchSpring.goal = pitchBaseAngle
	end

	return CFrame.fromEulerAnglesYXZ(pitchSpring:step(dt), yawSpring:step(dt), 0)
end

function VRVehicleCamera:_GetThirdPersonLocalOffset()
	return self.assemblyOffset + Vector3.new(0, self.assemblyRadius * VehicleCameraConfig.verticalCenterOffset, 0)
end

function VRVehicleCamera:_GetFirstPersonLocalOffset(subjectCFrame: CFrame)
	local character = localPlayer.Character

	if character and character.Parent then
		local head = character:FindFirstChild("Head")

		if head and head:IsA("BasePart") then
			return subjectCFrame:Inverse() * head.Position
		end
	end

	return self:_GetThirdPersonLocalOffset()
end

function VRVehicleCamera:Update()
	if FFlagUserVRVehicleCamera then
		local dt = worldDt
		worldDt = 0

		self:UpdateFadeFromBlack(dt)
		self:UpdateEdgeBlur(localPlayer, dt)

		local camera, focus
		if VRService.ThirdPersonFollowCamEnabled then
			camera, focus = self:UpdateStepRotation(dt)
		else
			camera, focus = self:UpdateComfortCamera(dt)
		end

		return camera, focus
	else
		return self:UpdateComfortCamera()
	end
end

function VRVehicleCamera:addDrift(currentCamera, focus)
	local function NormalizeAngle(angle): number
		angle = (angle + math.pi * 4) % (math.pi * 2)
		if angle > math.pi then
			angle = angle - math.pi * 2
		end
		return angle
	end

	local camera = workspace.CurrentCamera

	local zoom = self:GetCameraToSubjectDistance()
	local subjectVel: Vector3 = self:GetSubjectVelocity()
	local subjectCFrame: CFrame = self:GetSubjectCFrame()

	if subjectVel.Magnitude > 0.1 then
		local headOffset = VRService:GetUserCFrame(Enum.UserCFrame.Head)

		headOffset = headOffset.Rotation + headOffset.Position * camera.HeadScale
		local headCframe = camera.CFrame * headOffset

		local _, headAngle, _ = headCframe:ToEulerAnglesYXZ()
		local _, carAngle, _ = subjectCFrame:ToEulerAnglesYXZ()
		local headAngleRelativeToCurrentAngle = NormalizeAngle(headAngle - self.currentDriftAngle)
		local carAngleRelativeToCurrentAngle = NormalizeAngle(carAngle - self.currentDriftAngle)

		local minimumValidAngle = math.min(carAngleRelativeToCurrentAngle, headAngleRelativeToCurrentAngle)
		local maximumValidAngle = math.max(carAngleRelativeToCurrentAngle, headAngleRelativeToCurrentAngle)

		local relativeAngleToUse = 0
		if minimumValidAngle > 0 then
			relativeAngleToUse = minimumValidAngle
		elseif maximumValidAngle < 0 then
			relativeAngleToUse = maximumValidAngle
		end

		self.currentDriftAngle = relativeAngleToUse + self.currentDriftAngle
		local angleCFrame = CFrame.fromEulerAnglesYXZ(0, self.currentDriftAngle, 0)
		local angleLook = angleCFrame.LookVector

		local headVectorDirection = Vector3.new(angleLook.X, 0, angleLook.Z).Unit * zoom
		local goalHeadPosition = focus.Position - headVectorDirection

		local moveGoalCameraCFrame = CFrame.new(camera.CFrame.Position + goalHeadPosition - headCframe.Position)
			* camera.CFrame.Rotation

		currentCamera = currentCamera:Lerp(moveGoalCameraCFrame, 0.01)
	end

	return currentCamera, focus
end

function VRVehicleCamera:UpdateRotationCamera(dt)
	local camera = workspace.CurrentCamera
	local cameraSubject = camera and camera.CameraSubject
	local vehicleCameraCore = self.vehicleCameraCore

	assert(camera, "VRVehicleCamera requires a valid camera")
	assert(cameraSubject, "VRVehicleCamera requires a camera subject")
	assert(cameraSubject:IsA("VehicleSeat"), "VRVehicleCamera subject must be a VehicleSeat")

	local subjectCFrame: CFrame = self:GetSubjectCFrame()
	local subjectVel: Vector3 = self:GetSubjectVelocity()
	local subjectRotVel = self:GetSubjectRotVelocity()

	local vDotZ = math.abs(subjectVel:Dot(subjectCFrame.ZVector))
	local yawVel = yawVelocity(subjectRotVel, subjectCFrame)
	local pitchVel = pitchVelocity(subjectRotVel, subjectCFrame)

	local zoom = self:GetCameraToSubjectDistance()

	local firstPerson = mapClamp(zoom, ZOOM_MINIMUM, self.assemblyRadius, 1, 0)

	local tpOffset = self:_GetThirdPersonLocalOffset()
	local fpOffset = self:_GetFirstPersonLocalOffset(subjectCFrame)
	local localOffset = tpOffset:Lerp(fpOffset, firstPerson)

	vehicleCameraCore:setTransform(subjectCFrame)
	local processedRotation = vehicleCameraCore:step(dt, pitchVel, yawVel, firstPerson)

	local objectRotation = self:_StepRotation(dt, vDotZ)

	local focus = self:GetVRFocus(subjectCFrame * localOffset, dt) * processedRotation * objectRotation
	local cf = focus * CFrame.new(0, 0, zoom)

	if subjectVel.Magnitude > 0.1 then
		self:StartVREdgeBlur(localPlayer)
	end

	return cf, focus
end

function VRVehicleCamera:UpdateStepRotation(dt)
	local cf, focus

	local camera = workspace.CurrentCamera

	local lastSubjectCFrame = self.lastSubjectCFrame
	local subjectCFrame: CFrame = self:GetSubjectCFrame()
	local subjectVel: Vector3 = self:GetSubjectVelocity()

	local zoom = self:GetCameraToSubjectDistance()

	local firstPerson = mapClamp(zoom, ZOOM_MINIMUM, self.assemblyRadius, 1, 0)

	local tpOffset = self:_GetThirdPersonLocalOffset()
	local fpOffset = self:_GetFirstPersonLocalOffset(subjectCFrame)
	local localOffset = tpOffset:Lerp(fpOffset, firstPerson)
	local offsetSubject = subjectCFrame * localOffset

	focus = self:GetVRFocus(offsetSubject, dt)

	cf = focus:ToWorldSpace(self:GetVRFocus(lastSubjectCFrame * localOffset, dt):ToObjectSpace(camera.CFrame))

	cf, focus = self:addDrift(cf, focus)

	local yawDelta = self:getRotation(dt)
	if math.abs(yawDelta) > 0 then
		local cameraOffset = focus:ToObjectSpace(cf)
		local rotatedCamera = focus * CFrame.Angles(0, -yawDelta, 0) * cameraOffset

		if not UserGameSettings.VRSmoothRotationEnabled then
			local headOffset = VRService:GetUserCFrame(Enum.UserCFrame.Head)

			headOffset = headOffset.Rotation + headOffset.Position * camera.HeadScale
			local focusWithRotation = focus * subjectCFrame.Rotation

			local headOffsetCurrent = focusWithRotation:ToObjectSpace(cf * headOffset)
			local currentVector = Vector3.new(headOffsetCurrent.X, 0, headOffsetCurrent.Z).Unit
			local currentAngleFromBack = math.acos(currentVector:Dot(Vector3.new(0, 0, 1)))

			local headOffsetRotated = focusWithRotation:ToObjectSpace(rotatedCamera * headOffset)
			local rotatedVector = Vector3.new(headOffsetRotated.X, 0, headOffsetRotated.Z).Unit
			local rotatedAngleFromBack = math.acos(rotatedVector:Dot(Vector3.new(0, 0, 1)))

			if rotatedAngleFromBack < currentAngleFromBack then
				if yawDelta < 0 then
					currentAngleFromBack *= -1
				end
				rotatedCamera = focus * CFrame.Angles(0, -currentAngleFromBack, 0) * cameraOffset
			end
		end

		cf = rotatedCamera
	end

	if subjectVel.Magnitude > 0.1 then
		self:StartVREdgeBlur(localPlayer)
	end

	if self.needsReset then
		self.needsReset = false
		VRService:RecenterUserHeadCFrame()
		self:StartFadeFromBlack()
		self:ResetZoom()
	end

	if self.recentered then
		focus *= subjectCFrame.Rotation
		cf = focus * CFrame.new(0, 0, zoom)

		self.recentered = false
	end

	return cf, cf * CFrame.new(0, 0, -zoom)
end

function VRVehicleCamera:UpdateComfortCamera(dt)
	local camera = workspace.CurrentCamera
	local cameraSubject = camera and camera.CameraSubject
	local vehicleCameraCore = self.vehicleCameraCore

	assert(camera, "VRVehicleCamera requires a valid camera")
	assert(cameraSubject, "VRVehicleCamera requires a camera subject")
	assert(cameraSubject:IsA("VehicleSeat"), "VRVehicleCamera subject must be a VehicleSeat")

	if not FFlagUserVRVehicleCamera then
		dt = worldDt
		worldDt = 0
	end

	local subjectCFrame: CFrame = self:GetSubjectCFrame()
	local subjectVel: Vector3 = self:GetSubjectVelocity()
	local subjectRotVel = self:GetSubjectRotVelocity()

	local yawVel = yawVelocity(subjectRotVel, subjectCFrame)
	local pitchVel = pitchVelocity(subjectRotVel, subjectCFrame)

	local zoom = self:StepZoom()

	local firstPerson = mapClamp(zoom, ZOOM_MINIMUM, self.assemblyRadius, 1, 0)

	local tpOffset = self:_GetThirdPersonLocalOffset()
	local fpOffset = self:_GetFirstPersonLocalOffset(subjectCFrame)
	local localOffset = tpOffset:Lerp(fpOffset, firstPerson)

	vehicleCameraCore:setTransform(subjectCFrame)
	local processedRotation = vehicleCameraCore:step(dt, pitchVel, yawVel, firstPerson)

	local focus = nil
	local cf = nil

	if not FFlagUserVRVehicleCamera then
		self:UpdateFadeFromBlack(dt)
	end

	if not self:IsInFirstPerson() then
		focus = CFrame.new(subjectCFrame * localOffset) * processedRotation
		cf = focus * CFrame.new(0, 0, zoom)

		if not self.lastCameraFocus then
			self.lastCameraFocus = focus
			self.needsReset = true
		end

		local curCameraDir = focus.Position - camera.CFrame.Position
		local curCameraDist = curCameraDir.magnitude
		curCameraDir = curCameraDir.Unit
		local cameraDot = curCameraDir:Dot(camera.CFrame.LookVector)
		if cameraDot > TP_FOLLOW_ANGLE_DOT and curCameraDist < TP_FOLLOW_DIST and not self.needsReset then
			focus = self.lastCameraFocus

			local cameraFocusP = focus.p
			local cameraLookVector = self:GetCameraLookVector()
			cameraLookVector = Vector3.new(cameraLookVector.X, 0, cameraLookVector.Z).Unit
			local newLookVector = self:CalculateNewLookVectorFromArg(cameraLookVector, Vector2.new(0, 0))
			cf = CFrame.new(cameraFocusP - (zoom * newLookVector), cameraFocusP)
		else
			self.lastCameraFocus = self:GetVRFocus(subjectCFrame.Position, dt)
			self.needsReset = false
			self:StartFadeFromBlack()
			self:ResetZoom()
		end

		if not FFlagUserVRVehicleCamera then
			self:UpdateEdgeBlur(localPlayer, dt)
		end
	else
		local dir = Vector3.new(processedRotation.LookVector.X, 0, processedRotation.LookVector.Z).Unit
		local planarRotation = CFrame.new(processedRotation.Position, dir)

		focus = CFrame.new(subjectCFrame * localOffset) * planarRotation
		cf = focus * CFrame.new(0, 0, zoom)

		if FFlagUserVRVehicleCamera then
			if subjectVel.Magnitude > 0.1 then
				self:StartVREdgeBlur(localPlayer)
			end
		else
			self:StartVREdgeBlur(localPlayer)
		end
	end

	return cf, focus
end

return VRVehicleCamera
