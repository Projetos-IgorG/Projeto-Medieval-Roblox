--!nonstrict

--[[
    Script: VRCamera.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/PlayerModule/CameraModule
    Responsabilidade: Implementa camera do jogador para modo VR.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao implementa regras de gameplay do projeto; apenas apoia camera, controle e compatibilidade do jogador.
    Funcoes principais: new, Reset, Update, GetAvatarFeetWorldYValue, UpdateFirstPersonTransform, UpdateImmersionCamera
]]
local PlayersService = game:GetService("Players")
local VRService = game:GetService("VRService")

local CAMERA_BLACKOUT_TIME = 0.1
local FP_ZOOM = 0.5
local TORSO_FORWARD_OFFSET_RATIO = 1 / 8
local NECK_OFFSET = -0.7

local VRBaseCamera = require(script.Parent:WaitForChild("VRBaseCamera"))
local VRCamera = setmetatable({}, VRBaseCamera)
VRCamera.__index = VRCamera

function VRCamera.new()
	local self = setmetatable(VRBaseCamera.new(), VRCamera)

	self.lastUpdate = os.clock()
	self.focusOffset = CFrame.new()
	self:Reset()

	self.controlModule =
		require(PlayersService.LocalPlayer:WaitForChild("PlayerScripts").PlayerModule:WaitForChild("ControlModule"))
	self.savedAutoRotate = true
	self.NoRecenter = false
	self.recentered = false
	self.VRCameraFocusFrozen = false
	self.characterOrientation = nil
	self.VRBlur = nil

	return self
end

function VRCamera:Reset()
	self.needsReset = true
	self.needsBlackout = true
	self.motionDetTime = 0.0
	self.blackOutTimer = 0
	self.lastCameraResetPosition = nil
	VRBaseCamera.Reset(self)
end

function VRCamera:Update(timeDelta)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local newCameraCFrame = camera.CFrame
	local newCameraFocus = camera.Focus

	local player = PlayersService.LocalPlayer

	if self.lastUpdate == nil or timeDelta > 1 then
		self.lastCameraTransform = nil
	end

	self:UpdateFadeFromBlack(timeDelta)
	self:UpdateEdgeBlur(player, timeDelta)

	local lastSubjPos = self.lastSubjectPosition
	local subjectPosition: Vector3 = self:GetSubjectPosition()

	if self.needsBlackout then
		self:StartFadeFromBlack()

		local dt = math.clamp(timeDelta, 0.0001, 0.1)
		self.blackOutTimer += dt
		if self.blackOutTimer > CAMERA_BLACKOUT_TIME and game:IsLoaded() then
			self.needsBlackout = false
			self.needsReset = true
		end
	end

	if subjectPosition and player and camera then
		newCameraFocus = self:GetVRFocus(subjectPosition, timeDelta)

		if self:IsInFirstPerson() then
			if VRService.AvatarGestures then

				newCameraCFrame, newCameraFocus =
					self:UpdateImmersionCamera(timeDelta, newCameraCFrame, newCameraFocus, lastSubjPos, subjectPosition)
			else
				newCameraCFrame, newCameraFocus = self:UpdateFirstPersonTransform(
					timeDelta,
					newCameraCFrame,
					newCameraFocus,
					lastSubjPos,
					subjectPosition
				)
			end
		else
			if VRService.ThirdPersonFollowCamEnabled then
				newCameraCFrame, newCameraFocus = self:UpdateThirdPersonFollowTransform(
					timeDelta,
					newCameraCFrame,
					newCameraFocus,
					lastSubjPos,
					subjectPosition
				)
			else
				newCameraCFrame, newCameraFocus = self:UpdateThirdPersonComfortTransform(
					timeDelta,
					newCameraCFrame,
					newCameraFocus,
					lastSubjPos,
					subjectPosition
				)
			end
		end

		self.lastCameraTransform = newCameraCFrame
		self.lastCameraFocus = newCameraFocus
	end

	self.lastUpdate = os.clock()
	return newCameraCFrame, newCameraFocus
end

function VRCamera:GetAvatarFeetWorldYValue(): number?
	local camera = workspace.CurrentCamera
	local cameraSubject = camera.CameraSubject
	if not cameraSubject then
		return nil
	end

	if cameraSubject:IsA("Humanoid") and cameraSubject.RootPart then
		local rootPart = cameraSubject.RootPart
		return rootPart.Position.Y - rootPart.Size.Y / 2 - cameraSubject.HipHeight
	end

	return nil
end

function VRCamera:UpdateFirstPersonTransform(timeDelta, newCameraCFrame, newCameraFocus, lastSubjPos, subjectPosition)
	local safeSubjPos = lastSubjPos or subjectPosition

	if self.needsReset then
		self:StartFadeFromBlack()
		self.needsReset = false
	end

	local player = PlayersService.LocalPlayer
	local subjectDelta = safeSubjPos - subjectPosition
	if subjectDelta.Magnitude > 0.01 then
		self:StartVREdgeBlur(player)
	end

	local cameraFocusP = newCameraFocus.Position
	local cameraLookVector = self:GetCameraLookVector()
	cameraLookVector = Vector3.new(cameraLookVector.X, 0, cameraLookVector.Z).Unit

	local yawDelta = self:getRotation(timeDelta)

	local newLookVector = self:CalculateNewLookVectorFromArg(cameraLookVector, Vector2.new(yawDelta, 0))
	newCameraCFrame = CFrame.new(cameraFocusP - (FP_ZOOM * newLookVector), cameraFocusP)

	return newCameraCFrame, newCameraFocus
end

function VRCamera:UpdateImmersionCamera(timeDelta, newCameraCFrame, _newCameraFocus, _lastSubjPos, subjectPosition)
	local subjectCFrame = self:GetSubjectCFrame()
	local curCamera = workspace.CurrentCamera :: Camera

	local character = PlayersService.LocalPlayer.Character
	local humanoid = self:GetHumanoid()
	if not humanoid then
		return curCamera.CFrame, curCamera.Focus
	end
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return curCamera.CFrame, curCamera.Focus
	end
	self.characterOrientation = humanoidRootPart:FindFirstChild("CharacterAlignOrientation")
	if not self.characterOrientation then
		local rootAttachment = humanoidRootPart:FindFirstChild("RootAttachment")
		if not rootAttachment then
			return curCamera.CFrame, curCamera.Focus
		end
		self.characterOrientation = Instance.new("AlignOrientation")
		self.characterOrientation.Name = "CharacterAlignOrientation"
		self.characterOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
		self.characterOrientation.Attachment0 = rootAttachment
		self.characterOrientation.RigidityEnabled = true
		self.characterOrientation.Parent = humanoidRootPart
	end
	if self.characterOrientation.Enabled == false then
		self.characterOrientation.Enabled = true
	end

	if self.needsReset then
		self.needsReset = false

		self.savedAutoRotate = humanoid.AutoRotate
		humanoid.AutoRotate = false

		if self.NoRecenter then
			self.NoRecenter = false
			VRService:RecenterUserHeadCFrame()
		end

		self:StartFadeFromBlack()

		newCameraCFrame = subjectCFrame
	else

		if humanoid.Sit then
			newCameraCFrame = subjectCFrame
			if (newCameraCFrame.Position - curCamera.CFrame.Position).Magnitude > 0.01 then
				self:StartVREdgeBlur(PlayersService.LocalPlayer)
			end
		else

			local torsoRotation = self.controlModule:GetEstimatedVRTorsoFrame()
			self.characterOrientation.CFrame = curCamera.CFrame * torsoRotation

			if self.controlModule.inputMoveVector.Magnitude > 0 then
				self.motionDetTime = 0.1
			end

			if self.controlModule.inputMoveVector.Magnitude > 0 or self.motionDetTime > 0 then
				self.motionDetTime -= timeDelta

				self:StartVREdgeBlur(PlayersService.LocalPlayer)

				local vrHeadOffset = VRService:GetUserCFrame(Enum.UserCFrame.Head)
				vrHeadOffset = vrHeadOffset.Rotation + vrHeadOffset.Position * curCamera.HeadScale

				local hrp = character.HumanoidRootPart
				local neck_offset = NECK_OFFSET * hrp.Size.Y / 2
				local neckWorld = curCamera.CFrame * vrHeadOffset * CFrame.new(0, neck_offset, 0)
				local hrpLook = hrp.CFrame.LookVector
				neckWorld -= Vector3.new(hrpLook.X, 0, hrpLook.Z).Unit * hrp.Size.Y * TORSO_FORWARD_OFFSET_RATIO

				local goalCameraPosition = subjectPosition - neckWorld.Position + curCamera.CFrame.Position

				goalCameraPosition = Vector3.new(goalCameraPosition.X, subjectPosition.Y, goalCameraPosition.Z)

				newCameraCFrame = curCamera.CFrame.Rotation + goalCameraPosition
			else

				newCameraCFrame = curCamera.CFrame.Rotation
					+ Vector3.new(curCamera.CFrame.Position.X, subjectPosition.Y, curCamera.CFrame.Position.Z)
			end

			local yawDelta = self:getRotation(timeDelta)
			if math.abs(yawDelta) > 0 then

				local vrHeadOffset = VRService:GetUserCFrame(Enum.UserCFrame.Head)
				vrHeadOffset = vrHeadOffset.Rotation + vrHeadOffset.Position * curCamera.HeadScale
				local VRheadWorld = newCameraCFrame * vrHeadOffset

				local desiredVRHeadCFrame = CFrame.new(VRheadWorld.Position)
					* CFrame.Angles(0, -math.rad(yawDelta * 90), 0)
					* VRheadWorld.Rotation

				newCameraCFrame = desiredVRHeadCFrame * vrHeadOffset:Inverse()
			end
		end
	end

	return newCameraCFrame, newCameraCFrame * CFrame.new(0, 0, -FP_ZOOM)
end

function VRCamera:UpdateThirdPersonComfortTransform(
	timeDelta,
	newCameraCFrame,
	newCameraFocus,
	lastSubjPos,
	subjectPosition
)
	local zoom = self:GetCameraToSubjectDistance()
	if zoom < 0.5 then
		zoom = 0.5
	end

	if lastSubjPos ~= nil and self.lastCameraFocus ~= nil then

		local subjectDelta = lastSubjPos - subjectPosition
		local moveVector = self.controlModule:GetMoveVector()

		local isMoving = (lastSubjPos and (subjectDelta.Magnitude > 0.01)) or moveVector.Magnitude > 0.01
		if isMoving then
			self.motionDetTime = 0.1
		end

		self.motionDetTime = self.motionDetTime - timeDelta
		if self.motionDetTime > 0 then
			isMoving = true
		end

		if isMoving and not self.needsReset then

			newCameraFocus = self.lastCameraFocus

			self.VRCameraFocusFrozen = true
		else
			local lastResetPos = self.lastCameraResetPosition
			local subjectMoved = lastResetPos == nil or (subjectPosition - lastResetPos).Magnitude > 1

			local yawDelta = self:getRotation(timeDelta)
			if math.abs(yawDelta) > 0 then
				local cameraOffset = newCameraFocus:ToObjectSpace(newCameraCFrame)
				newCameraCFrame = newCameraFocus * CFrame.Angles(0, -yawDelta, 0) * cameraOffset
			end

			if (self.VRCameraFocusFrozen and subjectMoved) or self.needsReset then
				VRService:RecenterUserHeadCFrame()

				self.VRCameraFocusFrozen = false
				self.needsReset = false
				self.lastCameraResetPosition = subjectPosition

				self:ResetZoom()
				self:StartFadeFromBlack()

				local humanoid = self:GetHumanoid()
				local rootPart = humanoid and humanoid.RootPart
				local forwardVector = rootPart and rootPart.CFrame.LookVector or Vector3.new(1, 0, 0)

				local vecToCameraAtHeight = Vector3.new(forwardVector.X, 0, forwardVector.Z)
				local newCameraPos = newCameraFocus.Position - vecToCameraAtHeight * zoom

				local lookAtPos = Vector3.new(newCameraFocus.Position.X, newCameraPos.Y, newCameraFocus.Position.Z)

				newCameraCFrame = CFrame.new(newCameraPos, lookAtPos)
			end
		end
	end

	return newCameraCFrame, newCameraFocus
end

function VRCamera:UpdateThirdPersonFollowTransform(
	timeDelta,
	newCameraCFrame,
	_newCameraFocus,
	lastSubjPos,
	subjectPosition
)
	local camera = workspace.CurrentCamera :: Camera
	local zoom = self:GetCameraToSubjectDistance()
	local vrFocus = self:GetVRFocus(subjectPosition, timeDelta)

	if self.needsReset then
		self.needsReset = false

		VRService:RecenterUserHeadCFrame()
		self:ResetZoom()
		self:StartFadeFromBlack()
	end

	if self.recentered then
		local subjectCFrame = self:GetSubjectCFrame()
		if not subjectCFrame then
			return camera.CFrame, camera.Focus
		end

		newCameraCFrame = vrFocus * subjectCFrame.Rotation * CFrame.new(0, 0, zoom)

		self.focusOffset = vrFocus:ToObjectSpace(newCameraCFrame)

		self.recentered = false
		return newCameraCFrame, vrFocus
	end

	local trackCameraCFrame = vrFocus:ToWorldSpace(self.focusOffset)

	local subjectDelta = (lastSubjPos or subjectPosition) - subjectPosition
	local moveVector = self.controlModule:GetMoveVector()

	if subjectDelta.Magnitude > 0.01 or moveVector.Magnitude > 0 then
		local headOffset = self.controlModule:GetEstimatedVRTorsoFrame()

		headOffset = headOffset.Rotation + headOffset.Position * camera.HeadScale
		local headCframe = camera.CFrame * headOffset
		local headLook = headCframe.LookVector

		local headVectorDirection = Vector3.new(headLook.X, 0, headLook.Z).Unit * zoom
		local goalHeadPosition = vrFocus.Position - headVectorDirection

		local moveGoalCameraCFrame = CFrame.new(camera.CFrame.Position + goalHeadPosition - headCframe.Position)
			* trackCameraCFrame.Rotation

		newCameraCFrame = trackCameraCFrame:Lerp(moveGoalCameraCFrame, 0.01)
	else
		newCameraCFrame = trackCameraCFrame
	end

	local yawDelta = self:getRotation(timeDelta)
	if math.abs(yawDelta) > 0 then
		local cameraOffset = vrFocus:ToObjectSpace(newCameraCFrame)
		newCameraCFrame = vrFocus * CFrame.Angles(0, -yawDelta, 0) * cameraOffset
	end

	self.focusOffset = vrFocus:ToObjectSpace(newCameraCFrame)

	local newCameraFocus = newCameraCFrame * CFrame.new(0, 0, -zoom)

	if (newCameraFocus.Position - camera.Focus.Position).Magnitude > 0.01 then
		self:StartVREdgeBlur(PlayersService.LocalPlayer)
	end

	return newCameraCFrame, newCameraFocus
end

function VRCamera:LeaveFirstPerson()
	VRBaseCamera.LeaveFirstPerson(self)

	self.needsReset = true
	if self.VRBlur then
		self.VRBlur.Visible = false
	end

	if self.characterOrientation then
		self.characterOrientation.Enabled = false
	end
	local humanoid = self:GetHumanoid()
	if humanoid then
		humanoid.AutoRotate = self.savedAutoRotate
	end
end

return VRCamera
