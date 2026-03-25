--[[
	ParkourTesting - init.client.luau
	Script principal do sistema de parkour.

	Keybinds (baseado em intenção direcional, não teclas específicas):
	- No chão/ar + Jump: VaultBaixo / VaultMédio / Agarrar
	- Agarrado + Frente (W): Subir (ou Escalar se couber em cima)
	- Agarrado + Frente + Jump: SubirSalto
	- Agarrado + Jump: Escalar (se couber) ou Soltar
	- Agarrado + Trás (S) + Jump: PuloTras
	- Agarrado + Trás (S) segurar: confirma intenção, tenta Descer; se falhar, Soltar
	- Cooldown para evitar verificações repetidas
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local Analisador = require(script:WaitForChild("Analisador"))
local Movimento = require(script:WaitForChild("Movimento"))
local Configs = require(script:WaitForChild("Configs"))
local Debug = require(script:WaitForChild("Debug"))
local CooldownManager = require(script:WaitForChild("CooldownManager"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnimacaoParkour = require(
	ReplicatedStorage:WaitForChild("Modulos"):WaitForChild("Cliente"):WaitForChild("Visual"):WaitForChild("AnimacaoParkour")
)

-- ══════════════════════════════════════
-- Estado de conexões (cleanup no respawn)
-- ══════════════════════════════════════

local connections: { RBXScriptConnection } = {}
local JUMP_COOLDOWN = 0.1 -- segundos entre cada verificação de parkour
local lastJumpTime = 0
local runtimeConfig = Configs.mergeConfig(nil)
local cooldownBlockedLogAt = {} :: { [string]: number }
local lastIdleRecheckAt = 0

-- Estado de SubirSalto pendente (quando W detecta que precisa de W+Pulo)
local subirSaltoPendente = nil -- { Result, ExpiresAt, SourceEdgePosition }
local lateralSaltoPendente = nil -- { Direcao, Target }

-- Estado de intenção para descer (hold em S antes de tentar descer)
local descerHoldStart = 0 -- timestamp de quando começou a segurar S
local descerHolding = false -- está segurando S?

local function canUseActionCooldown(actionKey, direction, now)
	if CooldownManager.CanPerformAction(actionKey, direction, now) then
		return true
	end

	if Configs.DebugVerbose then
		local directionLabel = direction or "-"
		local logKey = actionKey .. "/" .. directionLabel
		local interval = runtimeConfig.CooldownBlockedLogInterval or 0.25
		local lastLogAt = cooldownBlockedLogAt[logKey] or 0

		if now - lastLogAt >= interval then
			local remaining = CooldownManager.GetRemaining(actionKey, now)
			print(string.format("[Parkour] Cooldown bloqueado: %s | restante %.2fs", logKey, remaining))
			cooldownBlockedLogAt[logKey] = now
		end
	end

	return false
end

local function limparConexoes()
	for _, conn in ipairs(connections) do
		conn:Disconnect()
	end
	table.clear(connections)
end

local function resetDescerState()
	descerHoldStart = 0
	descerHolding = false
end

local function clearSubirSaltoPendente(cancelarPreview)
	if cancelarPreview and subirSaltoPendente then
		Movimento.CancelarPreviewAcao(runtimeConfig)
	end
	subirSaltoPendente = nil
end

local function setSubirSaltoPendente(subirResult)
	if subirSaltoPendente then
		return false
	end

	if not Movimento.IniciarPreviewSubirSalto(subirResult) then
		return false
	end

	subirSaltoPendente = {
		Result = subirResult,
		ExpiresAt = os.clock() + (runtimeConfig.SubirSaltoConfirmWindow or 0.9),
		SourceEdgePosition = subirResult and subirResult.SourceEdgePosition,
	}

	return true
end

local function clearLateralSaltoPendente(cancelarPreview)
	if cancelarPreview and lateralSaltoPendente then
		Movimento.CancelarPreviewAcao(runtimeConfig)
	end
	lateralSaltoPendente = nil
end

local function setLateralSaltoPendente(direcao, target)
	if not target then
		return false
	end

	if lateralSaltoPendente and lateralSaltoPendente.Direcao == direcao then
		lateralSaltoPendente.Target = target
		return false
	end

	if lateralSaltoPendente then
		clearLateralSaltoPendente(true)
	end

	if not Movimento.IniciarPreviewLateralSalto(direcao) then
		return false
	end

	lateralSaltoPendente = {
		Direcao = direcao,
		Target = target,
	}

	return true
end

local function getSubirSaltoPendenteValido()
	if not subirSaltoPendente then
		return nil
	end

	local now = os.clock()
	if now > (subirSaltoPendente.ExpiresAt or 0) then
		if AnimacaoParkour.EstaAcaoPausadaCongelada() then
			-- Enquanto a pre-acao estiver congelada no marker, manter janela de confirmacao aberta.
			subirSaltoPendente.ExpiresAt = now + (runtimeConfig.SubirSaltoConfirmWindow or 0.9)
		else
		clearSubirSaltoPendente(true)
		return nil
		end
	end

	local grabData = Movimento.GetGrabData()
	local sourceEdge = subirSaltoPendente.SourceEdgePosition
	if grabData and sourceEdge and grabData.EdgePosition then
		local maxDrift = runtimeConfig.SubirSaltoConfirmEdgeTolerance or 2.5
		if (grabData.EdgePosition - sourceEdge).Magnitude > maxDrift then
			clearSubirSaltoPendente(true)
			return nil
		end
	end

	return subirSaltoPendente.Result
end

-- ══════════════════════════════════════
-- Detectar intenção direcional (frente/trás)
-- Usa MoveDirection com base da camera no parkour agarrado
-- ══════════════════════════════════════

local function getIntencaoDirecional(humanoid, hrp): string?
	local moveDir = humanoid.MoveDirection
	local moveFlat = Vector3.new(moveDir.X, 0, moveDir.Z)
	local deadzone = runtimeConfig.DirectionInputDeadzone or 0.2
	if moveFlat.Magnitude < deadzone then
		return nil -- sem input direcional
	end

	local useCameraBasis = runtimeConfig.DirectionUseCameraBasis ~= false
	local basisCFrame = hrp.CFrame
	if useCameraBasis then
		local currentCamera = Workspace.CurrentCamera
		if currentCamera then
			local camLookFlat = Vector3.new(currentCamera.CFrame.LookVector.X, 0, currentCamera.CFrame.LookVector.Z)
			if camLookFlat.Magnitude > 0.001 then
				basisCFrame = CFrame.lookAt(Vector3.zero, camLookFlat.Unit)
			end
		end
	end

	local lookFlat = Vector3.new(basisCFrame.LookVector.X, 0, basisCFrame.LookVector.Z)
	if lookFlat.Magnitude <= 0.001 then
		lookFlat = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
		if lookFlat.Magnitude <= 0.001 then
			return nil
		end
	end
	lookFlat = lookFlat.Unit

	local rightFlat = Vector3.new(basisCFrame.RightVector.X, 0, basisCFrame.RightVector.Z)
	if rightFlat.Magnitude <= 0.001 then
		rightFlat = Vector3.new(hrp.CFrame.RightVector.X, 0, hrp.CFrame.RightVector.Z)
		if rightFlat.Magnitude <= 0.001 then
			return nil
		end
	end
	rightFlat = rightFlat.Unit

	moveFlat = moveFlat.Unit

	local dotForward = lookFlat:Dot(moveFlat)
	local dotRight = rightFlat:Dot(moveFlat)
	local absForward = math.abs(dotForward)
	local absRight = math.abs(dotRight)
	local dominanceMargin = runtimeConfig.DirectionDominanceMargin or 0.12
	local forwardThreshold = runtimeConfig.DirectionForwardDotThreshold or 0.6
	local lateralThreshold = runtimeConfig.DirectionLateralDotThreshold or runtimeConfig.LateralInputDotThreshold or 0.6

	if absForward >= forwardThreshold and absForward >= (absRight + dominanceMargin) then
		if dotForward > 0 then
			return "Frente"
		end
		return "Tras"
	end

	if absRight >= lateralThreshold and absRight >= (absForward + dominanceMargin) then
		if dotRight >= 0 then
			return "Direita"
		end
		return "Esquerda"
	elseif dotRight >= lateralThreshold then
		return "Direita"
	elseif dotRight <= -lateralThreshold then
		return "Esquerda"
	end

	return nil -- ambíguo
end

-- ══════════════════════════════════════
-- Lógica de Jump quando AGARRADO
-- ══════════════════════════════════════

local function onJumpAgarrado(humanoid, hrp)
	local now = os.clock()
	local subirSaltoValido = getSubirSaltoPendenteValido()
	if subirSaltoValido then
		if not canUseActionCooldown("SubirSalto", nil, now) then
			return
		end

		local ok = Movimento.ConfirmarPreviewSubirSalto(subirSaltoValido)
		if ok then
			CooldownManager.RegisterSuccess("SubirSalto", nil, now)
			clearSubirSaltoPendente(false)
			clearLateralSaltoPendente(true)
			resetDescerState()
			return
		end
	end

	local direcao = getIntencaoDirecional(humanoid, hrp)

	if direcao == "Direita" or direcao == "Esquerda" then
		if not canUseActionCooldown("LateralSalto", direcao, now) then
			return
		end

		if lateralSaltoPendente and lateralSaltoPendente.Direcao == direcao then
			local confirmou = Movimento.ConfirmarPreviewLateralSalto(direcao, lateralSaltoPendente.Target)
			if confirmou then
				CooldownManager.RegisterSuccess("LateralSalto", direcao, now)
				clearLateralSaltoPendente(false)
				clearSubirSaltoPendente(false)
				resetDescerState()
				return
			end
		end

		local ok = Movimento.PuloLateral(direcao)
		if ok then
			CooldownManager.RegisterSuccess("LateralSalto", direcao, now)
			clearSubirSaltoPendente(false)
			clearLateralSaltoPendente(false)
			resetDescerState()
			return
		end
	end

	-- PuloTras: Trás + Pular (prioridade máxima quando S está sendo segurado)
	if direcao == "Tras" then
		local grabData = Movimento.GetGrabData()
		if grabData and grabData.IdleMode == "IdleSuspenso" then
			clearSubirSaltoPendente(true)
			clearLateralSaltoPendente(true)
			resetDescerState()
			Movimento.Soltar()
			return
		end

		local ok = Movimento.PuloTras()
		if ok then
			clearSubirSaltoPendente(true)
			clearLateralSaltoPendente(true)
			resetDescerState()
			return
		end
	end

	-- Escalar: Pular (com ou sem direção frente) — tenta subir em cima da plataforma
	local escalou = Movimento.TentarEscalar()
	if escalou then
		clearSubirSaltoPendente(true)
		clearLateralSaltoPendente(true)
		resetDescerState()
		return
	end

	-- Se pressionou frente mas não conseguiu escalar, não soltar (continuar agarrado)
	if direcao == "Frente" then
		return
	end

	-- Fallback: soltar (só quando não tem direção ou direção lateral)
	clearSubirSaltoPendente(true)
	clearLateralSaltoPendente(true)
	resetDescerState()
	Movimento.Soltar()
end

-- ══════════════════════════════════════
-- Lógica de Jump quando NÃO está agarrado
-- (comportamento original: VaultBaixo/VaultMédio/Agarrar)
-- ══════════════════════════════════════

local function onJumpNormal(character, humanoid)
	-- Não executar se já está em transição
	if Movimento.EstaEmAcao() then
		return
	end

	local noChao = humanoid.FloorMaterial ~= Enum.Material.Air

	Analisador.ClearDebug()

	local result = Analisador.CheckParkour(character, {})

	if not result or not result.Aprovado then
		if result then
			Analisador.DrawDebug(result)
		end
		return
	end

	-- Filtro condicional: no chão é só Vault
	if noChao and result.Acao == "Agarrar" then
		Analisador.DrawDebug(result)
		return
	end

	-- Debug visual
	Analisador.DrawDebug(result)

	-- Executar a ação de parkour
	local sucesso = Movimento.Executar(result)

	if sucesso then
		print("[Parkour] Executando:", result.Acao, result.IdleMode and ("| Idle: " .. result.IdleMode) or "")
	end
end

-- ══════════════════════════════════════
-- Handler unificado de Jump
-- ══════════════════════════════════════

local function onJumpRequest(character: Model, humanoid: Humanoid)
	-- Cooldown
	local now = os.clock()
	if now - lastJumpTime < JUMP_COOLDOWN then
		return
	end
	lastJumpTime = now

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	if Movimento.EstaAgarrado() then
		onJumpAgarrado(humanoid, hrp)
	else
		onJumpNormal(character, humanoid)
	end
end

-- ══════════════════════════════════════
-- Polling: Verificar MoveDirection enquanto agarrado
-- W = Subir | S (segurar) = confirma intenção e tenta Descer
-- ══════════════════════════════════════

local function onHeartbeat(character, humanoid)
	local now = os.clock()

	if not Movimento.EstaAgarrado() then
		clearSubirSaltoPendente(false)
		clearLateralSaltoPendente(false)
		resetDescerState()
		return
	end

	if Movimento.EstaEmAcao() then
		return
	end

	local recheckInterval = runtimeConfig.GrabIdleRecheckInterval or 0.15
	if now - lastIdleRecheckAt >= recheckInterval then
		lastIdleRecheckAt = now
		Movimento.ReavaliarIdleAgarrado()
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local direcao = getIntencaoDirecional(humanoid, hrp)

	if direcao == "Frente" then
		if lateralSaltoPendente then
			clearLateralSaltoPendente(true)
		end

		-- Resetar estado de descer quando muda pra frente
		resetDescerState()

		if not canUseActionCooldown("Subir", nil, now) then
			return
		end

		local ok, tipo, subirResult, escalarResult = Movimento.TentarSubir()

		-- Debug visual: SEMPRE desenhar os rays de verificação (mesmo se falhar)
		Analisador.ClearDebug()
		Debug.DrawClimbDebug(escalarResult, subirResult)

		if ok then
			if tipo == "Escalar" or tipo == "Subir" then
				if tipo == "Subir" then
					CooldownManager.RegisterSuccess("Subir", nil, now)
				end
				clearSubirSaltoPendente(true)
			elseif tipo == "SubirSalto" then
				local iniciouPreview = setSubirSaltoPendente(subirResult)
				if iniciouPreview then
					CooldownManager.BlockAction("Subir", nil, now, runtimeConfig.SubirSaltoCheckCooldown or 0.25)
					print("[Parkour] SubirSalto disponível — aperte Pular para confirmar")
				end
			end
		else
			local fallbackMin = (runtimeConfig.MinimumCooldowns and runtimeConfig.MinimumCooldowns.Subir) or 0.5
			local failCooldown = runtimeConfig.SubirFailCooldown or fallbackMin
			CooldownManager.BlockAction("Subir", nil, now, failCooldown)
		end
	elseif direcao == "Direita" or direcao == "Esquerda" then
		resetDescerState()
		clearSubirSaltoPendente(true)

		if not canUseActionCooldown("Lateral", direcao, now) then
			return
		end

		local ok, estadoLateral, lateralResult = Movimento.TentarMoverLateral(direcao)

		Analisador.ClearDebug()
		Debug.DrawLateralDebug(lateralResult)

		if ok then
			CooldownManager.RegisterSuccess("Lateral", direcao, now)
			if lateralSaltoPendente then
				clearLateralSaltoPendente(true)
			end
			if estadoLateral then
				print("[Parkour]", estadoLateral)
			end
		elseif lateralResult and (lateralResult.Reason == "NoLateralSurface" or lateralResult.Reason == "NoLateralSurfaceCached") then
			local target = lateralResult and lateralResult.LateralSaltoTarget or nil
			if target then
				local iniciouPreview = setLateralSaltoPendente(direcao, target)
				if iniciouPreview then
					print("[Parkour] LateralSalto disponível — aperte Pular para confirmar")
				end
			elseif lateralSaltoPendente then
				clearLateralSaltoPendente(true)
			end
			local fallbackMin = (runtimeConfig.MinimumCooldowns and runtimeConfig.MinimumCooldowns.Lateral) or 0.5
			local failCooldown = runtimeConfig.LateralNoSurfaceCooldown or fallbackMin
			CooldownManager.BlockAction("Lateral", direcao, now, failCooldown)
		else
			if lateralSaltoPendente then
				clearLateralSaltoPendente(true)
			end
		end
	elseif direcao == "Tras" then
		if lateralSaltoPendente then
			clearLateralSaltoPendente(true)
		end
		local grabData = Movimento.GetGrabData()
		if grabData and grabData.IdleMode == "IdleSuspenso" then
			clearSubirSaltoPendente(true)
			resetDescerState()
			Movimento.Soltar()
			return
		end

		if not descerHolding then
			descerHolding = true
			descerHoldStart = now
			clearSubirSaltoPendente(true)
			return
		end

		local holdTime = runtimeConfig.DescerHoldTime or 0.2
		if now - descerHoldStart < holdTime then
			return
		end

		local ok, tipo, descerResult = Movimento.TentarDescer()

		Analisador.ClearDebug()
		Debug.DrawDescerDebug(descerResult)

		if ok and tipo == "Descer" then
			clearSubirSaltoPendente(true)
			resetDescerState()
		else
			clearSubirSaltoPendente(true)
			resetDescerState()
			Movimento.Soltar()
		end
	else
		if lateralSaltoPendente then
			Movimento.CancelarPreviewLateralAoSoltar(runtimeConfig)
			clearLateralSaltoPendente(false)
		end
		-- Sem direção → resetar estado de descer
		resetDescerState()
		clearSubirSaltoPendente(true)
	end
end

-- ══════════════════════════════════════
-- Setup por Character (com cleanup)
-- ══════════════════════════════════════

local function setupCharacter(character: Model)
	limparConexoes()
	AnimacaoParkour.Destruir()
	Movimento.Soltar()
	lastJumpTime = 0
	lastIdleRecheckAt = 0
	clearSubirSaltoPendente(false)
	clearLateralSaltoPendente(false)
	resetDescerState()

	table.clear(cooldownBlockedLogAt)
	runtimeConfig = Configs.mergeConfig(nil)
	CooldownManager.Configure(runtimeConfig)
	CooldownManager.Reset()

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	AnimacaoParkour.Inicializar(character)

	-- JumpRequest: dispara em qualquer plataforma (Space, A, JumpButton)
	local jumpConn = humanoid:GetPropertyChangedSignal("Jump"):Connect(function()
		if humanoid.Jump then
			onJumpRequest(character, humanoid)
		end
	end)
	table.insert(connections, jumpConn)

	-- Heartbeat: polling de MoveDirection enquanto agarrado
	local heartbeatConn = RunService.Heartbeat:Connect(function()
		onHeartbeat(character, humanoid)
	end)
	table.insert(connections, heartbeatConn)

	-- Cleanup ao morrer
	local diedConn = humanoid.Died:Once(function()
		limparConexoes()
		AnimacaoParkour.Destruir()
		Movimento.Soltar()
		clearLateralSaltoPendente(false)
		clearSubirSaltoPendente(false)
		resetDescerState()
		table.clear(cooldownBlockedLogAt)
		CooldownManager.Reset()
	end)
	table.insert(connections, diedConn)
end

-- ══════════════════════════════════════
-- Inicialização
-- ══════════════════════════════════════

local function init()
	player.CharacterAdded:Connect(setupCharacter)

	if player.Character then
		setupCharacter(player.Character)
	end
end

init()
