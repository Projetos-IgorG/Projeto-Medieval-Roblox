-- StarterPlayer > StarterPlayerScripts > ShiftLockController

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local plr = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- ==============================================================================
-- CONFIGURAÇÕES
-- ==============================================================================
local CONFIG = {
	ToggleKey = Enum.KeyCode.LeftControl,
	SmoothFactor = 0.3, -- Suavidade do giro
	OffsetShoulder = Vector3.new(2, 0, 1), -- Câmera de lado
	OffsetFP = Vector3.new(0, 0, -0.9), -- Câmera em 1ª pessoa
	OffsetCrouch = Vector3.new(0, -0.5, 0), -- Deslocamento ao agachar (Configurável)
	TransitionTime = 0.35, -- Tempo da animação
	ZoomRangeOn = { Min = 0.5, Max = 15 },
	ZoomRangeOff = { Min = 0.5, Max = 50 },
	DefaultZoomOut = 10, -- Zoom ao sair da 1ª pessoa via Ctrl
	FP_Threshold = 1.5, -- Distância para considerar modo FPS
	HeadHideLimit = 0.6, -- Zoom mínimo onde a cabeça some
	DeadZoneSnapDelay = 0.2, -- Tempo em segundos na zona morta antes do snap (200ms)
	SnapTransitionTime = 0.25, -- Tempo da transição suave do snap
	-- Movement offsets & FOV
	WalkOffset = Vector3.new(0, -0.1, -0.3), -- Pequeno deslocamento ao andar
	RunOffset = Vector3.new(0, -0.2, -0.4), -- Deslocamento extra ao correr
	WalkFOV = 78, -- FOV ao andar (se desejar)
	RunFOV = 86, -- FOV ao correr
	DefaultFOV = 78, -- Valor base de FOV (padrão)
	FOVTransitionTime = 0.3, -- Tempo de transição do FOV
	RunSpeedThreshold = 18, -- Velocidade acima da qual é considerado corrida
}

local TWEEN_INFO = TweenInfo.new(CONFIG.TransitionTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- ==============================================================================
-- VARIÁVEIS DO SISTEMA DE SOMBRAS
-- ==============================================================================
local shadowReg = {}
local shadowProjector = Instance.new("Model")
shadowProjector.Name = "ShadowProjector"

-- ==============================================================================
-- VARIÁVEIS DE CONTROLE GERAL
-- ==============================================================================
local isActive = false
local isFirstPersonMode = false
local isSwimming = false
local isCrouching = false
local isSnappingToFP = false -- Flag para evitar snap repetitivo
local deadZoneEntryTime = nil -- Timestamp de entrada na zona morta
local currentZoomTween = nil -- Tween do zoom suave
local isMoving = false
local isRunning = false
local currentFOVTween = nil
local lastFOV = nil
local defaultFOV = nil
local lastSentState = nil
local currentOffsetTween = nil
local lastTargetOffset = Vector3.zero
local lastMaxZoom = CONFIG.ZoomRangeOff.Max
local characterComponents: { HRP: BasePart?, Humanoid: Humanoid? } = {}

local function getStatusValue()
	local char = plr.Character or plr.CharacterAdded:Wait()
	local statusFolder = char and char:WaitForChild("Status", 30)

	if not statusFolder then
		warn("ALERTA: Pasta 'Status' não encontrada no Character! O ShiftLock pode não funcionar corretamente.")
		statusFolder = Instance.new("Folder", char or plr)
		statusFolder.Name = "Status"
	end

	local val = statusFolder:FindFirstChild("ShiftLockOn") or Instance.new("BoolValue", statusFolder)
	val.Name = "ShiftLockOn"
	return val
end

local shiftLockBool = getStatusValue()

local shiftlockRemote = ReplicatedStorage:FindFirstChild("ShiftLockChanged")
if not shiftlockRemote then
	shiftlockRemote = Instance.new("RemoteEvent")
	shiftlockRemote.Name = "ShiftLockChanged"
	shiftlockRemote.Parent = ReplicatedStorage
end

-- ==============================================================================
-- FUNÇÕES: SISTEMA DE SOMBRAS (Otimizado para APENAS Cabeça/Acessórios)
-- ==============================================================================

local function onShadowChildAdded(child)
	if child:IsA("BasePart") then
		local isHead = (child.Name == "Head")
		local isRoot = (child.Name == "HumanoidRootPart")
		local isAccessory = child:FindFirstAncestorWhichIsA("Accessory")

		if not (isHead or isRoot or isAccessory) then
			return
		end

		local clone = child:Clone()
		clone.Anchored = true
		clone.CanCollide = false
		clone.CastShadow = true

		for _, v in pairs(clone:GetChildren()) do
			if v:IsA("JointInstance") or v:IsA("Script") or v:IsA("LocalScript") then
				v:Destroy()
			end
		end

		if clone.Transparency < 1 then
			clone.Transparency = 0
		end

		clone.Parent = shadowProjector
		shadowReg[child] = clone

		child.ChildAdded:Connect(function(child2)
			if child2:IsA("SpecialMesh") then
				clone:ClearAllChildren()
				child2:Clone().Parent = clone
			end
		end)
	elseif child:IsA("Accoutrement") then
		task.spawn(function()
			local handle = child:WaitForChild("Handle", 1)
			if handle then
				onShadowChildAdded(handle)
			end
		end)
	elseif child:IsA("CharacterMesh") then
		return
	end
end

local function updateShadows()
	local char = plr.Character
	if not char then
		return
	end

	for realObj, projectorObj in pairs(shadowReg) do
		if not realObj:IsDescendantOf(char) then
			projectorObj:Destroy()
			shadowReg[realObj] = nil
		end
	end

	local sunPos = Lighting:GetSunDirection() * 10000
	if sunPos.Y > 0 then
		local cf = camera.CFrame
		local focusPoint = camera.Focus.Position
		local dist = (focusPoint - cf.Position).Magnitude

		if dist < 1.5 then
			local facing = sunPos.Unit:Dot(cf.LookVector)
			if facing < 0 then
				local sunDist = (focusPoint - sunPos).Magnitude
				local rootPart = char:FindFirstChild("HumanoidRootPart")

				if rootPart and shadowReg[rootPart] then
					local projectorRoot = shadowReg[rootPart]
					local objCF = rootPart.CFrame
					local objPos = objCF.Position
					local objRot = objCF - objPos

					local realDist = (focusPoint - objPos).Magnitude
					local lerpScale = (realDist / sunDist) * 9

					local projectPos = focusPoint:Lerp(sunPos, lerpScale)
					local camOffset = objPos - focusPoint

					projectorRoot.CFrame = CFrame.new(projectPos + camOffset) * objRot

					for realObj, projectorObj in pairs(shadowReg) do
						if realObj ~= rootPart and realObj:IsA("BasePart") then
							local offset = objCF:ToObjectSpace(realObj.CFrame)
							projectorObj.CFrame = projectorRoot.CFrame * offset
						end
					end

					shadowProjector.Parent = camera
					return
				end
			end
		end
	end
	shadowProjector.Parent = nil
end

-- ==============================================================================
-- FUNÇÕES: VISIBILIDADE & CÂMERA
-- ==============================================================================

local function syncServer(state)
	if lastSentState ~= state then
		lastSentState = state
		shiftlockRemote:FireServer(state)
	end
end

local function tweenOffset(targetOffset)
	local hum = characterComponents.Humanoid
	if not hum then
		return
	end
	if currentOffsetTween then
		currentOffsetTween:Cancel()
	end
	currentOffsetTween = TweenService:Create(hum, TWEEN_INFO, { CameraOffset = targetOffset })
	currentOffsetTween:Play()
end

local function updateTransparency()
	local char = plr.Character
	if not char then
		return
	end

	local camDist = (camera.CFrame.Position - camera.Focus.Position).Magnitude
	local isMinimumZoom = camDist <= CONFIG.HeadHideLimit

	for _, obj in pairs(char:GetDescendants()) do
		if obj:IsA("BasePart") then
			local isAccessory = obj:FindFirstAncestorWhichIsA("Accessory")
			local isHead = (obj.Name == "Head")

			if obj.CastShadow == false and obj.Transparency < 1 then
				obj.CastShadow = true
			end

			if isFirstPersonMode then
				if isHead or isAccessory then
					obj.LocalTransparencyModifier = isMinimumZoom and 1 or 0
				else
					obj.LocalTransparencyModifier = 0
				end
			else
				obj.LocalTransparencyModifier = 0
			end
		end
	end
end

local function updateRotation()
	local hrp = characterComponents.HRP
	if not hrp then
		return
	end

	-- Câmera sempre trava quando shiftlock está ativo OU em primeira pessoa
	if isActive or isFirstPersonMode then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter

		-- REGRA: Se estiver nadando, NÃO rotaciona o corpo mesmo com shiftlock
		if not isSwimming then
			local camLook = camera.CFrame.LookVector
			local desiredLook = Vector3.new(camLook.X, 0, camLook.Z).Unit
			local targetRotation = CFrame.lookAt(Vector3.zero, desiredLook)
			local hrpPos = hrp.Position
			local nextRotation = hrp.CFrame.Rotation:Lerp(targetRotation, CONFIG.SmoothFactor)
			hrp.CFrame = CFrame.new(hrpPos) * nextRotation
		end
	else
		if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end
end

local function updateState()
	if not characterComponents.Humanoid then
		return
	end

	local camDist = (camera.CFrame.Position - camera.Focus.Position).Magnitude
	local nowInFirstPerson = camDist < CONFIG.FP_Threshold
	local inDeadZone = nowInFirstPerson and camDist > CONFIG.HeadHideLimit

	-- SNAP PARA PRIMEIRA PESSOA: Evita zona morta entre HeadHideLimit e FP_Threshold
	-- Funciona com ou sem ShiftLock, usando janela de tempo para evitar snaps acidentais
	if inDeadZone and not isSnappingToFP then
		local now = tick()

		if deadZoneEntryTime == nil then
			-- Primeira vez entrando na zona morta
			deadZoneEntryTime = now
		elseif (now - deadZoneEntryTime) >= CONFIG.DeadZoneSnapDelay then
			-- Ficou tempo suficiente na zona morta, executa snap suave
			isSnappingToFP = true
			deadZoneEntryTime = nil

			-- Cancela tween anterior se existir
			if currentZoomTween then
				currentZoomTween:Cancel()
			end

			-- Transição suave do zoom usando tween
			local snapTweenInfo =
				TweenInfo.new(CONFIG.SnapTransitionTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			currentZoomTween = TweenService:Create(plr, snapTweenInfo, {
				CameraMinZoomDistance = CONFIG.ZoomRangeOn.Min,
				CameraMaxZoomDistance = CONFIG.ZoomRangeOn.Min,
			})
			currentZoomTween:Play()

			-- Restaura o range após a transição completar
			currentZoomTween.Completed:Once(function()
				local maxZoom = (isActive or isFirstPersonMode) and CONFIG.ZoomRangeOn.Max or CONFIG.ZoomRangeOff.Max
				plr.CameraMaxZoomDistance = maxZoom
				isSnappingToFP = false
			end)
		end
	else
		-- Saiu da zona morta, reseta o timer
		deadZoneEntryTime = nil
	end

	if nowInFirstPerson ~= isFirstPersonMode then
		isFirstPersonMode = nowInFirstPerson
		updateTransparency()
	end

	local finalState = isActive or isFirstPersonMode

	if shiftLockBool.Value ~= finalState then
		shiftLockBool.Value = finalState
		syncServer(finalState)

		-- REGRA: AutoRotate só desativa se NÃO estiver nadando
		characterComponents.Humanoid.AutoRotate = not finalState or isSwimming
	end

	-- Calcula o offset alvo
	local targetOffset = Vector3.zero
	if isFirstPersonMode then
		targetOffset = CONFIG.OffsetFP
	elseif isActive then
		targetOffset = CONFIG.OffsetShoulder
	end

	-- Aplica offset de agachamento (Configurável)
	if isCrouching then
		targetOffset = targetOffset + CONFIG.OffsetCrouch
	end

	-- Aplica deslocamento por movimento (andar / correr)
	local movementOffset = Vector3.zero
	if isRunning then
		movementOffset = CONFIG.RunOffset
	elseif isMoving then
		movementOffset = CONFIG.WalkOffset
	end
	targetOffset = targetOffset + movementOffset

	-- Tween do offset apenas se mudou (Evita recriar tweens todo frame)
	if targetOffset ~= lastTargetOffset then
		lastTargetOffset = targetOffset
		tweenOffset(targetOffset)
	end

	-- GERA TRANSIÇÃO SUAVE DO FOV CONFORME MOVIMENTO
	local targetFOV = defaultFOV or CONFIG.DefaultFOV
	if isRunning then
		targetFOV = CONFIG.RunFOV
	elseif isMoving then
		targetFOV = CONFIG.WalkFOV
	end

	if lastFOV == nil then
		lastFOV = camera.FieldOfView or defaultFOV
	end

	if math.abs((targetFOV or 0) - (lastFOV or 0)) > 0.01 then
		-- cria tween somente se mudou
		if currentFOVTween then
			currentFOVTween:Cancel()
		end
		local fovTweenInfo = TweenInfo.new(CONFIG.FOVTransitionTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		currentFOVTween = TweenService:Create(camera, fovTweenInfo, { FieldOfView = targetFOV })
		currentFOVTween:Play()
		lastFOV = targetFOV
		currentFOVTween.Completed:Once(function()
			currentFOVTween = nil
		end)
	end

	-- Gerencia limites de zoom e suaviza a transição (Especialmente quando longe)
	local targetMaxZoom = finalState and CONFIG.ZoomRangeOn.Max or CONFIG.ZoomRangeOff.Max
	local targetMinZoom = finalState and CONFIG.ZoomRangeOn.Min or CONFIG.ZoomRangeOff.Min

	if targetMaxZoom ~= lastMaxZoom then
		lastMaxZoom = targetMaxZoom
		-- Tween do MaxZoom para suavidade ao ativar/desativar ShiftLock longe
		TweenService:Create(plr, TWEEN_INFO, { CameraMaxZoomDistance = targetMaxZoom }):Play()
		plr.CameraMinZoomDistance = targetMinZoom
	end
end

-- ==============================================================================
-- INICIALIZAÇÃO
-- ==============================================================================

local function onCharacterAdded(char)
	if next(shadowReg) ~= nil then
		shadowProjector:ClearAllChildren()
		shadowReg = {}
	end

	characterComponents = {}
	local hrp = char:WaitForChild("HumanoidRootPart", 5)
	local hum = char:WaitForChild("Humanoid", 5)

	if hrp and hum then
		characterComponents.HRP = hrp
		characterComponents.Humanoid = hum

		-- Guarda FOV padrão ao spawnar
		-- Guarda FOV padrão ao spawnar: use o valor configurado (CONFIG.DefaultFOV)
		defaultFOV = CONFIG.DefaultFOV
		lastFOV = camera.FieldOfView or defaultFOV

		-- Detecta movimento (Walking/Running) via evento Running
		hum.Running:Connect(function(speed)
			isMoving = (speed > 0.5)
			isRunning = (speed >= CONFIG.RunSpeedThreshold)
			-- não cria tweens direto aqui; updateState vai aplicar offsets/FOV suavemente
		end)

		-- Detecta mudanças de estado do Humanoid (incluindo natação)
		hum.StateChanged:Connect(function(oldState, newState)
			isSwimming = (newState == Enum.HumanoidStateType.Swimming)

			-- Atualiza AutoRotate quando muda de/para natação
			if isActive or isFirstPersonMode then
				hum.AutoRotate = isSwimming
			end
		end)

		-- Detecta agachamento via Status
		task.spawn(function()
			local status = char:WaitForChild("Status", 10)
			if status then
				local agachadoVal = status:WaitForChild("AgachadoOn", 10)
				if agachadoVal then
					isCrouching = agachadoVal.Value
					agachadoVal.Changed:Connect(function(val)
						isCrouching = val
					end)
				end
			end
		end)

		for _, v in pairs(char:GetChildren()) do
			task.spawn(onShadowChildAdded, v)
		end
		char.ChildAdded:Connect(onShadowChildAdded)

		RunService:BindToRenderStep("CameraShadowController", Enum.RenderPriority.Camera.Value + 1, function()
			updateState()
			updateRotation()
			updateTransparency()
			updateShadows()
		end)
	end
end

local function onCharacterRemoving()
	RunService:UnbindFromRenderStep("CameraShadowController")
	shadowProjector.Parent = nil
	characterComponents = {}
	isSwimming = false
	isCrouching = false
	isSnappingToFP = false
	deadZoneEntryTime = nil
	if currentZoomTween then
		currentZoomTween:Cancel()
		currentZoomTween = nil
	end
	if currentFOVTween then
		currentFOVTween:Cancel()
		currentFOVTween = nil
	end
	isMoving = false
	isRunning = false
	lastFOV = nil
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then
		return
	end
	if input.KeyCode == CONFIG.ToggleKey then
		-- Se estiver em 1ª pessoa, força a saída para ShiftLock Ativo
		if isFirstPersonMode then
			isActive = true

			-- Força o zoom para fora suavemente (usando restrição temporária)
			local oldMin = plr.CameraMinZoomDistance
			plr.CameraMinZoomDistance = CONFIG.DefaultZoomOut

			task.delay(0.1, function()
				plr.CameraMinZoomDistance = oldMin
			end)
		else
			-- Toggle normal fora da 1ª pessoa
			isActive = not isActive
		end
	end
end)

plr.CharacterAdded:Connect(onCharacterAdded)
plr.CharacterRemoving:Connect(onCharacterRemoving)

if plr.Character then
	onCharacterAdded(plr.Character)
end

Lighting.Changed:Connect(updateShadows)
