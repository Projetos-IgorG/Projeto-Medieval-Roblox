--!nonstrict

--[[
    Script: ClassicCamera.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/PlayerModule/CameraModule
    Responsabilidade: Implementa o comportamento classico de camera em terceira pessoa.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao implementa regras de gameplay do projeto; apenas apoia camera, controle e compatibilidade do jogador.
    Funcoes principais: new, GetCameraToggleOffset, SetCameraMovementMode, Update, SetPrimeiraPessoa, IsInFirstPerson
]]
local tweenAcceleration = math.rad(220)
local tweenSpeed = math.rad(0)
local tweenMaxSpeed = math.rad(250)
local TIME_BEFORE_AUTO_ROTATE = 2

local INITIAL_CAMERA_ANGLE = CFrame.fromOrientation(math.rad(-15), 0, 0)

local CommonUtils = script.Parent.Parent:WaitForChild("CommonUtils")
local FlagUtil = require(CommonUtils:WaitForChild("FlagUtil"))

local FFlagUserCameraInputDt = FlagUtil.getUserFlag("UserCameraInputDt")
local FFlagUserFixCameraFPError = FlagUtil.getUserFlag("UserFixCameraFPError")

local PlayersService = game:GetService("Players")

local CameraInput = require(script.Parent:WaitForChild("CameraInput"))
local Util = require(script.Parent:WaitForChild("CameraUtils"))

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ConfigJogador = require(
	ReplicatedStorage:WaitForChild("Jogador")
		:WaitForChild("Camera")
		:WaitForChild("Configuracoes")
		:WaitForChild("ConfigCamera")
)

local BaseCamera = require(script.Parent:WaitForChild("BaseCamera"))
local ClassicCamera = setmetatable({}, BaseCamera)
ClassicCamera.__index = ClassicCamera

function ClassicCamera.new()
	local self = setmetatable(BaseCamera.new(), ClassicCamera)

	self.isFollowCamera = false
	self.isCameraToggle = false
	self.lastUpdate = tick()
	self.cameraToggleSpring = Util.Spring.new(5, 0)

	self.currentMovementOffset = Vector3.zero
	self.currentShoulderOffset = Vector3.zero
	self.offsetLerpSpeed = ConfigJogador.ObterConfiguracao("OffsetLerpSpeed") or 8

	self.emPrimeiraPessoa = false
	self.transicaoPrimeiraPessoaAlpha = 0

	return self
end

function ClassicCamera:GetCameraToggleOffset(dt: number)
	if self.isCameraToggle then
		local zoom = self.currentSubjectDistance

		if CameraInput.getTogglePan() then
			self.cameraToggleSpring.goal = math.clamp(Util.map(zoom, 0.5, 4, 0, 1), 0, 1)
		else
			self.cameraToggleSpring.goal = 0
		end

		local distanceOffset: number = math.clamp(Util.map(zoom, 0.5, 64, 0, 1), 0, 1) + 1
		return Vector3.new(0, self.cameraToggleSpring:step(dt) * distanceOffset, 0)
	end

	return Vector3.new()
end

function ClassicCamera:SetCameraMovementMode(cameraMovementMode: Enum.ComputerCameraMovementMode)
	BaseCamera.SetCameraMovementMode(self, cameraMovementMode)

	self.isFollowCamera = cameraMovementMode == Enum.ComputerCameraMovementMode.Follow
	self.isCameraToggle = cameraMovementMode == Enum.ComputerCameraMovementMode.CameraToggle
end

function ClassicCamera:Update(dt)
	local now = tick()
	local timeDelta = now - self.lastUpdate
	if FFlagUserCameraInputDt then
		timeDelta = dt
	end

	local camera = workspace.CurrentCamera
	local newCameraCFrame = camera.CFrame
	local newCameraFocus = camera.Focus

	local overrideCameraLookVector = nil
	if self.resetCameraAngle then
		local rootPart: BasePart = self:GetHumanoidRootPart()
		if rootPart then
			overrideCameraLookVector = (rootPart.CFrame * INITIAL_CAMERA_ANGLE).LookVector
		else
			overrideCameraLookVector = INITIAL_CAMERA_ANGLE.LookVector
		end
		self.resetCameraAngle = false
	end

	local player = PlayersService.LocalPlayer
	local humanoid = self:GetHumanoid()
	local cameraSubject = camera.CameraSubject
	local isInVehicle = cameraSubject and cameraSubject:IsA("VehicleSeat")
	local isOnASkateboard = cameraSubject and cameraSubject:IsA("SkateboardPlatform")
	local isClimbing = humanoid and humanoid:GetState() == Enum.HumanoidStateType.Climbing

	if self.lastUpdate == nil or timeDelta > 1 then
		self.lastCameraTransform = nil
	end

	local rotateInput = CameraInput.getRotation(timeDelta)

	self:StepZoom()

	local cameraHeight = self:GetCameraHeight()

	if rotateInput ~= Vector2.new() then
		tweenSpeed = 0
		self.lastUserPanCamera = tick()
	end

	local userRecentlyPannedCamera = now - self.lastUserPanCamera < TIME_BEFORE_AUTO_ROTATE
	local subjectPosition: Vector3 = self:GetSubjectPosition()

	if subjectPosition and player and camera then
		local zoom = self:GetCameraToSubjectDistance()
		if zoom < 0.5 then
			zoom = 0.5
		end

		local isFirstPerson = self.emPrimeiraPessoa
		local isMouseLocked = self:GetIsMouseLocked()

		local targetShoulderOffset = Vector3.zero
		if isFirstPerson then
			targetShoulderOffset = Vector3.zero
		elseif isMouseLocked then
			targetShoulderOffset = self:GetMouseLockOffset()
		end

		local lerpAlpha = math.clamp(self.offsetLerpSpeed * timeDelta, 0, 1)
		self.currentShoulderOffset = self.currentShoulderOffset:Lerp(targetShoulderOffset, lerpAlpha)

		local predictedLookVector = self:CalculateNewLookVectorFromArg(overrideCameraLookVector, rotateInput)
		local lookVectorHorizontal = Vector3.new(predictedLookVector.X, 0, predictedLookVector.Z)
		if lookVectorHorizontal.Magnitude > 0.001 then
			lookVectorHorizontal = lookVectorHorizontal.Unit
		else
			lookVectorHorizontal = Vector3.new(0, 0, -1)
		end

		local rightVectorHorizontal = Vector3.new(0, 1, 0):Cross(lookVectorHorizontal).Unit

		local globalOffsetWorld = self.currentShoulderOffset.X * rightVectorHorizontal
			+ Vector3.new(0, self.currentShoulderOffset.Y, 0)
			+ self.currentShoulderOffset.Z * lookVectorHorizontal

		if Util.IsFiniteVector3(globalOffsetWorld) then
			subjectPosition = subjectPosition + globalOffsetWorld
		end

		if isMouseLocked or isFirstPerson then
			local offset = Vector3.zero

			if humanoid then
				offset = offset + humanoid.CameraOffset

				local targetMovementOffset = Vector3.zero
				local speed = humanoid.MoveDirection.Magnitude

				local character = humanoid.Parent
				local statusFolder = character and character:FindFirstChild("Status")
				local isAgachado = false
				if statusFolder then
					local agachadoValue = statusFolder:FindFirstChild("Agachado")
					if agachadoValue and agachadoValue:IsA("BoolValue") then
						isAgachado = agachadoValue.Value
					end
				end

				if isAgachado then
					local crouchOffset = ConfigJogador.ObterConfiguracao("OffsetCrouch") or Vector3.zero
					targetMovementOffset = targetMovementOffset + crouchOffset
				end

				if speed > 0.1 then
					local hrp = self:GetHumanoidRootPart()
					local realSpeed = 0
					if hrp then
						local v = hrp.AssemblyLinearVelocity
						realSpeed = Vector3.new(v.X, 0, v.Z).Magnitude
					end

					local isCorrendo = ConfigJogador.EstaCorrendo(realSpeed)
					local walkOffset = ConfigJogador.ObterConfiguracao("WalkOffset") or Vector3.zero
					local runOffset = ConfigJogador.ObterConfiguracao("RunOffset") or Vector3.zero

					if isCorrendo then
						targetMovementOffset = targetMovementOffset + runOffset
					else
						targetMovementOffset = targetMovementOffset + walkOffset
					end
				end

				self.currentMovementOffset = self.currentMovementOffset:Lerp(targetMovementOffset, lerpAlpha)
			end

			local cameraRelativeOffset: Vector3 = offset.X * rightVectorHorizontal
				+ offset.Y * Vector3.new(0, 1, 0)
				+ offset.Z * lookVectorHorizontal

			local characterRelativeOffset = Vector3.zero
			if self.currentMovementOffset.Magnitude > 0.001 then
				local hrp = self:GetHumanoidRootPart()
				if hrp then
					characterRelativeOffset = self.currentMovementOffset.X * hrp.CFrame.RightVector
						+ Vector3.new(0, self.currentMovementOffset.Y, 0)
						+ self.currentMovementOffset.Z * hrp.CFrame.LookVector
				end
			end

			if Util.IsFiniteVector3(cameraRelativeOffset) then
				subjectPosition = subjectPosition + cameraRelativeOffset
			end
			if Util.IsFiniteVector3(characterRelativeOffset) then
				subjectPosition = subjectPosition + characterRelativeOffset
			end
		else
			local userPanningTheCamera = rotateInput ~= Vector2.new()

			if not userPanningTheCamera and self.lastCameraTransform then
				local isInFirstPerson = self:IsInFirstPerson()

				if
					(isInVehicle or isOnASkateboard or (self.isFollowCamera and isClimbing))
					and self.lastUpdate
					and humanoid
					and humanoid.Torso
				then
					if isInFirstPerson then
						if
							self.lastSubjectCFrame
							and (isInVehicle or isOnASkateboard)
							and cameraSubject:IsA("BasePart")
						then
							local y = -Util.GetAngleBetweenXZVectors(
								self.lastSubjectCFrame.LookVector,
								cameraSubject.CFrame.LookVector
							)
							if Util.IsFinite(y) then
								rotateInput = rotateInput + Vector2.new(y, 0)
							end
							tweenSpeed = 0
						end
					elseif not userRecentlyPannedCamera then
						local forwardVector = humanoid.Torso.CFrame.LookVector
						tweenSpeed = math.clamp(tweenSpeed + tweenAcceleration * timeDelta, 0, tweenMaxSpeed)

						local percent = math.clamp(tweenSpeed * timeDelta, 0, 1)
						if self:IsInFirstPerson() and not (self.isFollowCamera and isClimbing) then
							percent = 1
						end

						local y = Util.GetAngleBetweenXZVectors(forwardVector, self:GetCameraLookVector())
						if Util.IsFinite(y) and math.abs(y) > 0.0001 then
							rotateInput = rotateInput + Vector2.new(y * percent, 0)
						end
					end
				elseif self.isFollowCamera and not (isInFirstPerson or userRecentlyPannedCamera) then
					local lastVec = -(self.lastCameraTransform.Position - subjectPosition)

					local y = Util.GetAngleBetweenXZVectors(lastVec, self:GetCameraLookVector())

					local thetaCutoff = 0.4

					if Util.IsFinite(y) and math.abs(y) > 0.0001 and math.abs(y) > thetaCutoff * timeDelta then
						rotateInput = rotateInput + Vector2.new(y, 0)
					end
				end
			end
		end

		if not self.isFollowCamera then
			newCameraFocus = CFrame.new(subjectPosition)

			local cameraFocusP = newCameraFocus.Position
			local newLookVector = self:CalculateNewLookVectorFromArg(overrideCameraLookVector, rotateInput)

			if FFlagUserFixCameraFPError then
				newCameraCFrame = CFrame.lookAlong(cameraFocusP - (zoom * newLookVector), newLookVector)
			else
				newCameraCFrame = CFrame.new(cameraFocusP - (zoom * newLookVector), cameraFocusP)
			end
		else
			local newLookVector = self:CalculateNewLookVectorFromArg(overrideCameraLookVector, rotateInput)

			newCameraFocus = CFrame.new(subjectPosition)

			if FFlagUserFixCameraFPError then
				newCameraCFrame = CFrame.lookAlong(newCameraFocus.Position - (zoom * newLookVector), newLookVector)
			else
				newCameraCFrame = CFrame.new(newCameraFocus.Position - (zoom * newLookVector), newCameraFocus.Position)
					+ Vector3.new(0, cameraHeight, 0)
			end
		end

		local toggleOffset = self:GetCameraToggleOffset(timeDelta)
		newCameraFocus = newCameraFocus + toggleOffset
		newCameraCFrame = newCameraCFrame + toggleOffset

		local transicaoTempo = ConfigJogador.ObterConfiguracao("TransicaoPrimeiraPessoaTempo") or 0.4
		local alphaSpeed = 1 / math.max(transicaoTempo, 0.01)
		if self.emPrimeiraPessoa then
			self.transicaoPrimeiraPessoaAlpha = math.min(self.transicaoPrimeiraPessoaAlpha + timeDelta * alphaSpeed, 1)
		else
			self.transicaoPrimeiraPessoaAlpha = math.max(self.transicaoPrimeiraPessoaAlpha - timeDelta * alphaSpeed, 0)
		end

		if self.transicaoPrimeiraPessoaAlpha > 0 then
			local character = player.Character
			local headPart = character and character:FindFirstChild("Head")
			if headPart and headPart:IsA("BasePart") then
				local offsetFP = ConfigJogador.ObterConfiguracao("OffsetFPCabeca") or Vector3.zero
				local headPos = (headPart.CFrame * CFrame.new(offsetFP)).Position

				local lookVector = newCameraCFrame.LookVector
				local fpCFrame = CFrame.lookAlong(headPos, lookVector)

				local fpFocus = CFrame.new(headPos + lookVector * 0.5)

				local alpha = self.transicaoPrimeiraPessoaAlpha
				-- Smoothstep easing: 3t^2 - 2t^3
				local easedAlpha = alpha * alpha * (3 - 2 * alpha)
				newCameraCFrame = newCameraCFrame:Lerp(fpCFrame, easedAlpha)
				newCameraFocus = newCameraFocus:Lerp(fpFocus, easedAlpha)
			end
		end

		self.lastCameraTransform = newCameraCFrame
		self.lastCameraFocus = newCameraFocus
		if (isInVehicle or isOnASkateboard) and cameraSubject:IsA("BasePart") then
			self.lastSubjectCFrame = cameraSubject.CFrame
		else
			self.lastSubjectCFrame = nil
		end
	end

	self.lastUpdate = now
	return newCameraCFrame, newCameraFocus
end

function ClassicCamera:SetPrimeiraPessoa(ativo: boolean)
	self.emPrimeiraPessoa = ativo
end

function ClassicCamera:IsInFirstPerson(): boolean
	return self.emPrimeiraPessoa
end

return ClassicCamera
