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

		if isMouseLocked or isFirstPerson then
			-- We need to use the right vector of the camera after rotation, not before
			local newLookCFrame: CFrame = self:CalculateNewLookCFrameFromArg(overrideCameraLookVector, rotateInput)

			-- Determina o offset base (shoulder para MouseLock, FP para 1ª pessoa)
			local offset: Vector3
			if isFirstPerson then
				-- Offset de 1ª pessoa do ConfigJogador
				offset = ConfigJogador.ObterConfiguracao("OffsetFP") or Vector3.zero
			else
				-- Offset de shoulder (MouseLock) do MouseLockController
				offset = self:GetMouseLockOffset()
			end

			-- Adiciona offset de movimento dinâmico baseado no estado do humanoid
			if humanoid then
				-- Offset base do humanoid
				offset = offset + humanoid.CameraOffset

				-- Calcula o offset alvo baseado no estado de movimento
				local targetMovementOffset = Vector3.zero
				local speed = humanoid.MoveDirection.Magnitude

				-- Detecta agachamento via pasta Status do personagem (mais confiável)
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
				-- Verifica a velocidade REAL do personagem para decidir entre Andar e Correr
				if speed > 0.1 then
					local hrp = self:GetHumanoidRootPart()
					local realSpeed = 0
					if hrp then
						local v = hrp.AssemblyLinearVelocity
						realSpeed = Vector3.new(v.X, 0, v.Z).Magnitude
					end

					-- Verifica se está correndo usando o limiar configurado
					local isCorrendo = ConfigJogador.EstaCorrendo(realSpeed)

					local walkOffset = ConfigJogador.ObterConfiguracao("WalkOffset") or Vector3.zero
					local runOffset = ConfigJogador.ObterConfiguracao("RunOffset") or Vector3.zero

					-- Se está correndo, alvo é RunOffset. Se está andando, alvo é WalkOffset.
					-- A transição suave (Lerp) é feita logo abaixo no update do currentMovementOffset
					if isCorrendo then
						targetMovementOffset = targetMovementOffset + runOffset
					else
						targetMovementOffset = targetMovementOffset + walkOffset
					end
				end

				-- Suaviza a transição do offset usando lerp (elimina o "flick" brusco)
				local lerpAlpha = math.clamp(self.offsetLerpSpeed * timeDelta, 0, 1)
				self.currentMovementOffset = self.currentMovementOffset:Lerp(targetMovementOffset, lerpAlpha)

				-- Offset de movimento é aplicado SEPARADAMENTE em coordenadas do personagem (não da câmera)
				-- Isso garante que ao olhar para baixo, o offset Z vai para frente do personagem, não para o chão
			end

			-- Aplica offset base (shoulder/FP + humanoid) relativo à câmera DE FORMA ESTABILIZADA (Yaw only)
			-- Isso evita que olhar para cima/baixo faça a câmera orbitar verticalmente (subir/descer)
			-- X = Right (do personagem/camera horizontal)
			-- Y = Global Up (altura fixa)
			-- Z = Forward Horizontal (profundidade fixa no plano)

			local lookVectorHorizontal = Vector3.new(newLookCFrame.LookVector.X, 0, newLookCFrame.LookVector.Z)
			if lookVectorHorizontal.Magnitude > 0.001 then
				lookVectorHorizontal = lookVectorHorizontal.Unit
			else
				lookVectorHorizontal = Vector3.new(0, 0, -1) -- Fallback se olhar perfeitamente vertical
			end

			local rightVectorHorizontal = Vector3.new(0, 1, 0):Cross(lookVectorHorizontal).Unit

			local cameraRelativeOffset: Vector3 = offset.X * rightVectorHorizontal
				+ offset.Y * Vector3.new(0, 1, 0) -- Força Y global
				+ offset.Z * lookVectorHorizontal

			-- Aplica offset de movimento relativo ao PERSONAGEM (não à câmera)
			-- Usa o CFrame do HumanoidRootPart para que o Z siga a direção do personagem, não da câmera
			local characterRelativeOffset = Vector3.zero
			if self.currentMovementOffset.Magnitude > 0.001 then
				local hrp = self:GetHumanoidRootPart()
				if hrp then
					-- X = direita do personagem, Y = global (altura), Z = frente do personagem
					characterRelativeOffset = self.currentMovementOffset.X * hrp.CFrame.RightVector
						+ Vector3.new(0, self.currentMovementOffset.Y, 0) -- Y é global (altura)
						+ self.currentMovementOffset.Z * hrp.CFrame.LookVector
				end
			end

			--offset can be NAN, NAN, NAN if newLookVector has only y component
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
