--!nonstrict
--[[
	ClassicCamera - Classic Roblox camera control module
	2018 Camera Update - AllYourBlox

	Note: This module also handles camera control types Follow and Track, the
	latter of which is currently not distinguished from Classic
--]]

-- Local private variables and constants

local tweenAcceleration = math.rad(220) -- Radians/Second^2
local tweenSpeed = math.rad(0) -- Radians/Second
local tweenMaxSpeed = math.rad(250) -- Radians/Second
local TIME_BEFORE_AUTO_ROTATE = 2 -- Seconds, used when auto-aligning camera with vehicles

local INITIAL_CAMERA_ANGLE = CFrame.fromOrientation(math.rad(-15), 0, 0)

local CommonUtils = script.Parent.Parent:WaitForChild("CommonUtils")
local FlagUtil = require(CommonUtils:WaitForChild("FlagUtil"))

local FFlagUserCameraInputDt = FlagUtil.getUserFlag("UserCameraInputDt")
local FFlagUserFixCameraFPError = FlagUtil.getUserFlag("UserFixCameraFPError")

--[[ Services ]]
--
local PlayersService = game:GetService("Players")

local CameraInput = require(script.Parent:WaitForChild("CameraInput"))
local Util = require(script.Parent:WaitForChild("CameraUtils"))

-- Importa configurações centralizadas do jogador para offsets dinâmicos
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ConfigJogador = require(
	ReplicatedStorage:WaitForChild("Modulos"):WaitForChild("Jogador"):WaitForChild("Modulo_ConfiguracoesJogador")
)

--[[ The Module ]]
--
local BaseCamera = require(script.Parent:WaitForChild("BaseCamera"))
local ClassicCamera = setmetatable({}, BaseCamera)
ClassicCamera.__index = ClassicCamera

function ClassicCamera.new()
	local self = setmetatable(BaseCamera.new(), ClassicCamera)

	self.isFollowCamera = false
	self.isCameraToggle = false
	self.lastUpdate = tick()
	self.cameraToggleSpring = Util.Spring.new(5, 0)

	-- Estado para suavização de offsets dinâmicos
	self.currentMovementOffset = Vector3.zero
	self.currentMovementOffset = Vector3.zero
	self.currentShoulderOffset = Vector3.zero
	self.offsetLerpSpeed = 8 -- Velocidade do lerp (maior = mais rápido)

	return self
end

function ClassicCamera:GetCameraToggleOffset(dt: number)
	if self.isCameraToggle then
		local zoom = self.currentSubjectDistance

		if CameraInput.getTogglePan() then
			self.cameraToggleSpring.goal =
				math.clamp(Util.map(zoom, 0.5, self.FIRST_PERSON_DISTANCE_THRESHOLD, 0, 1), 0, 1)
		else
			self.cameraToggleSpring.goal = 0
		end

		local distanceOffset: number = math.clamp(Util.map(zoom, 0.5, 64, 0, 1), 0, 1) + 1
		return Vector3.new(0, self.cameraToggleSpring:step(dt) * distanceOffset, 0)
	end

	return Vector3.new()
end

-- Movement mode standardized to Enum.ComputerCameraMovementMode values
function ClassicCamera:SetCameraMovementMode(cameraMovementMode: Enum.ComputerCameraMovementMode)
	BaseCamera.SetCameraMovementMode(self, cameraMovementMode)

	self.isFollowCamera = cameraMovementMode == Enum.ComputerCameraMovementMode.Follow
	self.isCameraToggle = cameraMovementMode == Enum.ComputerCameraMovementMode.CameraToggle
end

function ClassicCamera:Update(dt)
	local now = tick()
	local timeDelta = now - self.lastUpdate -- replace with dt if FFlagUserCameraInputDt
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

	-- Reset tween speed if user is panning
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

		-- Aplica offsets de câmera customizados baseados no modo
		local isFirstPerson = self:IsInFirstPerson()
		local isMouseLocked = self:GetIsMouseLocked()

		-- ============================================================================
		-- TRANSICAO SUAVE DE OFFSET (SHIFTLOCK / 1ª PESSOA)
		-- ============================================================================

		local targetShoulderOffset = Vector3.zero
		if isFirstPerson then
			targetShoulderOffset = ConfigJogador.ObterConfiguracao("OffsetFP") or Vector3.zero
		elseif isMouseLocked then
			targetShoulderOffset = self:GetMouseLockOffset()
		end

		-- Interpola o offset atual para o alvo (suaviza entrada e saída do ShiftLock)
		local lerpAlpha = math.clamp(self.offsetLerpSpeed * timeDelta, 0, 1)
		self.currentShoulderOffset = self.currentShoulderOffset:Lerp(targetShoulderOffset, lerpAlpha)

		-- Calcula a direção horizontal da câmera para aplicar o offset corretamente
		-- Precisamos do vetor de olhar PREVISTO (com input de rotação aplicado)
		local predictedLookVector = self:CalculateNewLookVectorFromArg(overrideCameraLookVector, rotateInput)
		local lookVectorHorizontal = Vector3.new(predictedLookVector.X, 0, predictedLookVector.Z)
		if lookVectorHorizontal.Magnitude > 0.001 then
			lookVectorHorizontal = lookVectorHorizontal.Unit
		else
			lookVectorHorizontal = Vector3.new(0, 0, -1)
		end

		local rightVectorHorizontal = Vector3.new(0, 1, 0):Cross(lookVectorHorizontal).Unit

		-- Aplica o offset globalmente (antes da lógica específica de modo)
		local globalOffsetWorld = self.currentShoulderOffset.X * rightVectorHorizontal
			+ Vector3.new(0, self.currentShoulderOffset.Y, 0) -- Y pode variar se configurado
			+ self.currentShoulderOffset.Z * lookVectorHorizontal

		if Util.IsFiniteVector3(globalOffsetWorld) then
			subjectPosition = subjectPosition + globalOffsetWorld
		end

		-- ============================================================================
		-- LÓGICA ESPECÍFICA DE MODO
		-- ============================================================================

		if isMouseLocked or isFirstPerson then
			-- We need to use the right vector of the camera after rotation, not before
			-- local newLookCFrame: CFrame = self:CalculateNewLookCFrameFromArg(overrideCameraLookVector, rotateInput)
			-- (newLookCFrame removed as it was unused and we use the outer scope vectors)

			-- Recalcula offset apenas para movimento e humanoid (Offset base já aplicado acima)
			local offset = Vector3.zero

			-- Adiciona offset de movimento dinâmico baseado no estado do humanoid
			if humanoid then
				-- Offset base do humanoid
				offset = offset + humanoid.CameraOffset

				-- Calcula o offset alvo baseado no estado de movimento
				local targetMovementOffset = Vector3.zero
				local speed = humanoid.MoveDirection.Magnitude

				-- Detecta agachamento via pasta Status do personagem
				local character = humanoid.Parent
				local statusFolder = character and character:FindFirstChild("Status")
				local isAgachado = false
				if statusFolder then
					local agachadoValue = statusFolder:FindFirstChild("Agachado")
					if agachadoValue and agachadoValue:IsA("BoolValue") then
						isAgachado = agachadoValue.Value
					end
				end

				-- Offset de agachamento
				if isAgachado then
					local crouchOffset = ConfigJogador.ObterConfiguracao("OffsetCrouch") or Vector3.zero
					targetMovementOffset = targetMovementOffset + crouchOffset
				end

				-- Offset de movimento (Walk/Run)
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

				-- Suaviza a transição do offset de movimento
				self.currentMovementOffset = self.currentMovementOffset:Lerp(targetMovementOffset, lerpAlpha)
			end

			-- Aplica offsets relativos (Camera Base já foi, agora são os offsets de movimento/humanoide)

			-- NOTA: O código original aplicava offset.X/Y/Z usando rightVectorHorizontal e lookVectorHorizontal.
			-- Aqui 'offset' contém apenas humanoid.CameraOffset.
			-- E 'characterRelativeOffset' contém currentMovementOffset.

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
					-- Logic that was unique to the old FollowCamera module
					local lastVec = -(self.lastCameraTransform.Position - subjectPosition)

					local y = Util.GetAngleBetweenXZVectors(lastVec, self:GetCameraLookVector())

					-- This cutoff is to decide if the humanoid's angle of movement,
					-- relative to the camera's look vector, is enough that
					-- we want the camera to be following them. The point is to provide
					-- a sizable dead zone to allow more precise forward movements.
					local thetaCutoff = 0.4

					-- Check for NaNs
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
		else -- is FollowCamera
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

return ClassicCamera
