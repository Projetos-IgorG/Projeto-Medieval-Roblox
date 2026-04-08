--[[
	Parkour - init.client.luau
	Script principal do sistema de parkour.
	Responsável APENAS por captura de input e gerenciamento de estado.
	Toda lógica de verificação, análise e utilidades está nos módulos dedicados.

	MUDAR A CADA VERSÃO:
	VERSÃO: "Parkour 3.0v — Momentum System (sem cooldowns, velocidade progressiva"

	Keybinds (baseado em intenção direcional, não teclas específicas):
	- No chão/ar + Jump: VaultBaixo / VaultMédio / Agarrar
	- Agarrado + Frente (W): Subir; entre SubirSalto e Escalar, prioriza SubirSalto
	- Agarrado + Frente + Jump: SubirSalto
	- Agarrado + Frente (W) segurando após timeout: Escalar automático (quando disponível)
	- Agarrado + Jump: Escalar (se couber) ou Soltar
	- Agarrado + Trás (S) + Jump: PuloTras
	- Agarrado + Trás (S) segurar: confirma intenção, tenta Descer; se falhar, Soltar
	- Momentum: ações consecutivas aumentam velocidade de animação e transição (1.0 → 1.3x)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Analisador = require(script:WaitForChild("Analisador"))
local Movimento = require(script:WaitForChild("Movimento"))
local Configs = require(script:WaitForChild("Configs"))
local Debug = require(script:WaitForChild("Debug"))
local MomentumManager = require(script:WaitForChild("MomentumManager"))
local Utilidades = require(script:WaitForChild("Utilidades"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modulos = ReplicatedStorage:WaitForChild("Modulos")
local ClientBridge = require(Modulos:WaitForChild("Core"):WaitForChild("ClientBridge"))
local AnimacaoParkour = require(Modulos:WaitForChild("Cliente"):WaitForChild("Visual"):WaitForChild("AnimacaoParkour"))

-- ══════════════════════════════════════
-- Estado local (conexões, cache, timers)
-- ══════════════════════════════════════

local connections: { RBXScriptConnection } = {}
local JUMP_COOLDOWN = 0.1
local lastJumpTime = 0
local runtimeConfig = Configs.mergeConfig(nil)
local failThrottles = {} :: { [string]: number }
local lastIdleRecheckAt = 0
local currentHrp: BasePart? = nil

-- Pendentes de confirmação (SubirSalto / LateralSalto)
local subirSaltoPendente = nil -- { Result, ExpiresAt, SourceEdgePosition, EscalarFallbackResult?, SwitchToEscalarAt? }
local lateralSaltoPendente = nil -- { Direcao, Target, CurveFallbackTarget, CreatedAt, SwitchToCurveAt }

-- Intenção de descer (hold em S)
local descerHoldStart = 0
local descerHolding = false
local descerSemOpcaoStart = 0

-- ══════════════════════════════════════
-- Helpers locais (apenas state management)
-- ══════════════════════════════════════

local function dbgPrint(...)
	Debug.Verbose(...)
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
	descerSemOpcaoStart = 0
end

local function isFailThrottled(actionKey: string, throttleDelay: number, now: number): boolean
	local lastFail = failThrottles[actionKey]
	if lastFail and (now - lastFail) < throttleDelay then
		return true
	end
	return false
end

local function setFailThrottle(actionKey: string, now: number)
	failThrottles[actionKey] = now
end

local function registerMomentum(now: number)
	MomentumManager.RegisterSuccess(now)
	AnimacaoParkour.SetSpeedMultiplier(MomentumManager.GetSpeedMultiplier(now))
end

local function syncMomentumSpeed(now: number)
	AnimacaoParkour.SetSpeedMultiplier(MomentumManager.GetSpeedMultiplier(now))
end

local function clearSubirSaltoPendente(cancelarPreview)
	if cancelarPreview and subirSaltoPendente then
		Movimento.CancelarPreviewAcao(runtimeConfig)
	end
	subirSaltoPendente = nil
end

local function clearLateralSaltoPendente(cancelarPreview)
	if cancelarPreview and lateralSaltoPendente then
		Movimento.CancelarPreviewAcao(runtimeConfig)
	end
	lateralSaltoPendente = nil
end

local function resolveCurrentHrp(character: Model): BasePart?
	if currentHrp and currentHrp.Parent == character then
		return currentHrp
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		currentHrp = hrp
		return hrp
	end

	currentHrp = nil
	return nil
end

-- ══════════════════════════════════════
-- Pendentes: SubirSalto / LateralSalto
-- ══════════════════════════════════════

local function setSubirSaltoPendente(subirResult, escalarFallbackResult)
	if subirSaltoPendente then
		return false
	end

	if not Movimento.IniciarPreviewSubirSalto(subirResult) then
		return false
	end

	local now = os.clock()
	local switchToEscalarAt = nil
	if escalarFallbackResult and escalarFallbackResult.CanEscalar then
		switchToEscalarAt = now + (runtimeConfig.SubirSaltoPreferTimeout or 0.77)
	end

	subirSaltoPendente = {
		Result = subirResult,
		ExpiresAt = now + (runtimeConfig.SubirSaltoConfirmWindow or 0.9),
		SourceEdgePosition = subirResult and subirResult.SourceEdgePosition,
		EscalarFallbackResult = escalarFallbackResult,
		SwitchToEscalarAt = switchToEscalarAt,
	}

	return true
end

local function setLateralSaltoPendente(direcao, target, curveFallbackTarget)
	if not target then
		return false
	end

	if lateralSaltoPendente and lateralSaltoPendente.Direcao == direcao then
		lateralSaltoPendente.Target = target
		lateralSaltoPendente.CurveFallbackTarget = curveFallbackTarget
		return false
	end

	if lateralSaltoPendente then
		clearLateralSaltoPendente(true)
	end

	if not Movimento.IniciarPreviewLateralSalto(direcao) then
		return false
	end

	local now = os.clock()
	local switchTimeout = runtimeConfig.LateralSaltoPreferTimeout or 0.67
	lateralSaltoPendente = {
		Direcao = direcao,
		Target = target,
		CurveFallbackTarget = curveFallbackTarget,
		CreatedAt = now,
		SwitchToCurveAt = now + switchTimeout,
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
-- Debug draw helpers (delegates puros)
-- ══════════════════════════════════════

local function drawClimbDebug(escalarResult, subirResult)
	if not Configs.DebugEnabled then
		return
	end
	Analisador.ClearDebug()
	Debug.DrawClimbDebug(escalarResult, subirResult)
end

local function drawLateralDebug(lateralResult)
	if not Configs.DebugEnabled then
		return
	end
	Analisador.ClearDebug()
	Debug.DrawLateralDebug(lateralResult)
end

local function drawDescerDebug(descerResult)
	if not Configs.DebugEnabled then
		return
	end
	Analisador.ClearDebug()
	Debug.DrawDescerDebug(descerResult)
end

-- ══════════════════════════════════════
-- Handler: Jump quando AGARRADO
-- ══════════════════════════════════════

local function onJumpAgarrado(humanoid, hrp)
	local now = os.clock()
	local subirSaltoValido = getSubirSaltoPendenteValido()
	if subirSaltoValido then
		syncMomentumSpeed(now)
		local ok = Movimento.ConfirmarPreviewSubirSalto(subirSaltoValido)
		if ok then
			registerMomentum(now)
			clearSubirSaltoPendente(false)
			clearLateralSaltoPendente(true)
			resetDescerState()
			return
		end
	end

	local direcao = Utilidades.GetIntencaoDirecional(humanoid, hrp, runtimeConfig)

	if direcao == "Direita" or direcao == "Esquerda" then
		if lateralSaltoPendente and lateralSaltoPendente.Direcao == direcao then
			syncMomentumSpeed(now)
			local confirmou = Movimento.ConfirmarPreviewLateralSalto(direcao, lateralSaltoPendente.Target)
			if confirmou then
				registerMomentum(now)
				clearLateralSaltoPendente(false)
				clearSubirSaltoPendente(false)
				resetDescerState()
				return
			end
		end

		syncMomentumSpeed(now)
		local ok = Movimento.PuloLateral(direcao)
		if ok then
			registerMomentum(now)
			clearSubirSaltoPendente(false)
			clearLateralSaltoPendente(false)
			resetDescerState()
			return
		end
	end

	-- PuloTras: Trás + Pular
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

	-- Escalar: tenta subir em cima da plataforma
	local escalou = Movimento.TentarEscalar()
	if escalou then
		clearSubirSaltoPendente(true)
		clearLateralSaltoPendente(true)
		resetDescerState()
		return
	end

	-- Se pressionou frente mas não conseguiu escalar, continuar agarrado
	if direcao == "Frente" then
		return
	end

	-- Fallback: soltar
	clearSubirSaltoPendente(true)
	clearLateralSaltoPendente(true)
	resetDescerState()
	Movimento.Soltar()
end

-- ══════════════════════════════════════
-- Handler: Jump quando NÃO está agarrado
-- ══════════════════════════════════════

local function onJumpNormal(character, humanoid)
	if Movimento.EstaEmAcao() then
		dbgPrint("[Parkour] JumpNormal ignorado: personagem em ação")
		return
	end

	local noChao = humanoid.FloorMaterial ~= Enum.Material.Air
	dbgPrint("[Parkour] JumpNormal iniciado | noChao:", noChao)

	Analisador.ClearDebug()

	local result = Analisador.CheckParkour(character, {})

	if not result or not result.Aprovado then
		dbgPrint("[Parkour] CheckParkour reprovado | reason:", result and result.Reason or "nil")
		if result and Configs.DebugEnabled then
			Analisador.DrawDebug(result)
		end
		return
	end

	-- Filtro: no chão é só Vault
	if noChao and result.Acao == "Agarrar" then
		dbgPrint("[Parkour] Ação bloqueada no chão | Acao:", result.Acao)
		if Configs.DebugEnabled then
			Analisador.DrawDebug(result)
		end
		return
	end

	-- Vault só quando correndo
	if
		(result.Acao == "VaultBaixo" or result.Acao == "VaultMedio")
		and not Analisador.IsRunningForVault(humanoid, ClientBridge)
	then
		if noChao then
			dbgPrint("[Parkour] Vault sem corrida no chão: não pode fallback para Agarrar | Acao:", result.Acao)
			if Configs.DebugEnabled then
				Analisador.DrawDebug(result)
			end
			return
		end

		local fallbackGrab = Analisador.TentarFallbackAgarrar(character, result, runtimeConfig)
		if fallbackGrab and fallbackGrab.Aprovado then
			dbgPrint("[Parkour] Vault sem corrida -> fallback para Agarrar | Acao original:", result.Acao)
			result = fallbackGrab
		else
			dbgPrint(
				"[Parkour] Vault sem corrida e fallback falhou | Acao original:",
				result.Acao,
				"| reason:",
				fallbackGrab and fallbackGrab.Reason or "nil"
			)
			if Configs.DebugEnabled then
				Analisador.DrawDebug(fallbackGrab or result)
			end
			return
		end
	end

	-- Guarda final: nunca Agarrar quando pulo iniciou no chão
	if noChao and result.Acao == "Agarrar" then
		dbgPrint("[Parkour] Agarrar bloqueado: pulo iniciado no chão")
		if Configs.DebugEnabled then
			Analisador.DrawDebug(result)
		end
		return
	end

	-- Debug visual
	if Configs.DebugEnabled then
		Analisador.DrawDebug(result)
	end

	-- Executar ação
	local sucesso = Movimento.Executar(result)

	if sucesso then
		dbgPrint("[Parkour] Executando:", result.Acao, result.IdleMode and ("| Idle: " .. result.IdleMode) or "")
	else
		dbgPrint("[Parkour] Movimento.Executar falhou | Acao:", result.Acao)
	end
end

-- ══════════════════════════════════════
-- Handler unificado de Jump
-- ══════════════════════════════════════

local function onJumpRequest(character: Model, humanoid: Humanoid)
	local now = os.clock()
	if now - lastJumpTime < JUMP_COOLDOWN then
		return
	end
	lastJumpTime = now

	local hrp = resolveCurrentHrp(character)
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
-- Heartbeat: polling enquanto agarrado
-- ══════════════════════════════════════

local function onHeartbeat(character, humanoid)
	local now = os.clock()

	if not Movimento.EstaAgarrado() then
		clearSubirSaltoPendente(false)
		clearLateralSaltoPendente(false)
		resetDescerState()
		return
	end

	if ClientBridge.EntrarParkour then
		local emParkour = ClientBridge.EstaEmParkour and ClientBridge.EstaEmParkour() or false
		if not emParkour then
			ClientBridge.EntrarParkour()
		end
	end

	if Movimento.EstaEmAcao() then
		return
	end

	local recheckInterval = runtimeConfig.GrabIdleRecheckInterval or 0.15
	if now - lastIdleRecheckAt >= recheckInterval then
		lastIdleRecheckAt = now
		Movimento.ReavaliarIdleAgarrado()
	end

	local hrp = resolveCurrentHrp(character)
	if not hrp then
		return
	end

	local direcao = Utilidades.GetIntencaoDirecional(humanoid, hrp, runtimeConfig)

	if direcao == "Frente" then
		if lateralSaltoPendente then
			clearLateralSaltoPendente(true)
		end
		resetDescerState()

		local subirSaltoValido = getSubirSaltoPendenteValido()
		if subirSaltoValido and subirSaltoPendente then
			local switchToEscalarAt = subirSaltoPendente.SwitchToEscalarAt
			if switchToEscalarAt and now >= switchToEscalarAt then
				clearSubirSaltoPendente(true)
				syncMomentumSpeed(now)
				local escalou = Movimento.TentarEscalar()
				if escalou then
					registerMomentum(now)
					dbgPrint("[Parkour] Hold em frente: escalando automaticamente")
					clearLateralSaltoPendente(true)
					resetDescerState()
					return
				end
			end
		end

		if isFailThrottled("Subir", runtimeConfig.SubirFailThrottle or 0.35, now) then
			return
		end

		syncMomentumSpeed(now)
		local ok, tipo, subirResult, escalarResult = Movimento.TentarSubir()

		drawClimbDebug(escalarResult, subirResult)

		if ok then
			if tipo == "Escalar" or tipo == "Subir" then
				registerMomentum(now)
				clearSubirSaltoPendente(true)
			elseif tipo == "SubirSalto" then
				local escalarFallback = if escalarResult and escalarResult.CanEscalar then escalarResult else nil
				local iniciouPreview = setSubirSaltoPendente(subirResult, escalarFallback)
				if iniciouPreview then
					setFailThrottle("Subir", now)
					if escalarFallback then
						dbgPrint(
							"[Parkour] SubirSalto disponível — aperte Pular para confirmar ou segure frente para escalar"
						)
					else
						dbgPrint("[Parkour] SubirSalto disponível — aperte Pular para confirmar")
					end
				end
			end
		else
			setFailThrottle("Subir", now)
		end
	elseif direcao == "Direita" or direcao == "Esquerda" then
		resetDescerState()
		clearSubirSaltoPendente(true)

		if lateralSaltoPendente and lateralSaltoPendente.Direcao == direcao then
			local curveFallbackTarget = lateralSaltoPendente.CurveFallbackTarget
			local switchToCurveAt = lateralSaltoPendente.SwitchToCurveAt or math.huge
			if curveFallbackTarget and now >= switchToCurveAt then
				syncMomentumSpeed(now)
				local executouCurva = Movimento.ExecutarLateralForcado(curveFallbackTarget)
				if executouCurva then
					registerMomentum(now)
					clearLateralSaltoPendente(false)
					clearSubirSaltoPendente(false)
					return
				end
			end
		end

		if isFailThrottled("Lateral", runtimeConfig.LateralNoSurfaceThrottle or 0.5, now) then
			return
		end

		syncMomentumSpeed(now)
		local ok, estadoLateral, lateralResult = Movimento.TentarMoverLateral(direcao)

		drawLateralDebug(lateralResult)

		if ok then
			registerMomentum(now)
			if lateralSaltoPendente then
				clearLateralSaltoPendente(true)
			end
			if estadoLateral then
				dbgPrint("[Parkour]", estadoLateral)
			end
		elseif
			lateralResult
			and (
				lateralResult.Reason == "NoLateralSurface"
				or lateralResult.Reason == "NoLateralSurfaceCached"
				or lateralResult.Reason == "PreferLateralSaltoOverInternalCorner"
			)
		then
			local target = lateralResult and lateralResult.LateralSaltoTarget or nil
			local curveFallbackTarget = lateralResult and lateralResult.CurvaInternaFallbackTarget or nil
			if target then
				local iniciouPreview = setLateralSaltoPendente(direcao, target, curveFallbackTarget)
				if iniciouPreview then
					dbgPrint("[Parkour] LateralSalto disponível — aperte Pular para confirmar")
				end
			elseif lateralSaltoPendente then
				clearLateralSaltoPendente(true)
			end
			if lateralResult.Reason ~= "PreferLateralSaltoOverInternalCorner" then
				setFailThrottle("Lateral", now)
			end
		else
			if lateralSaltoPendente then
				clearLateralSaltoPendente(true)
			end
		end
	elseif direcao == "Tras" then
		if lateralSaltoPendente then
			clearLateralSaltoPendente(true)
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

		if isFailThrottled("Descer", runtimeConfig.DescerFailThrottle or 0.2, now) then
			return
		end

		syncMomentumSpeed(now)
		local ok, tipo, descerResult = Movimento.TentarDescer()

		drawDescerDebug(descerResult)

		if ok and tipo == "Descer" then
			registerMomentum(now)
			clearSubirSaltoPendente(true)
			resetDescerState()
		else
			setFailThrottle("Descer", now)
			clearSubirSaltoPendente(true)

			local reason = descerResult and descerResult.Reason or "Unknown"
			local semOpcao = reason == "NoSurfaceBelow"
				or reason == "NoClearanceBelow"
				or reason == "TooFarBelow"
				or reason == "InvalidCurrentNormalForDescer"

			if semOpcao then
				if descerSemOpcaoStart <= 0 then
					descerSemOpcaoStart = now
					return
				end

				local releaseDelay = runtimeConfig.DescerNoOptionReleaseDelay or 0.2
				if now - descerSemOpcaoStart >= releaseDelay then
					resetDescerState()
					Movimento.Soltar()
				end
			else
				descerSemOpcaoStart = 0
			end
		end
	else
		if lateralSaltoPendente then
			Movimento.CancelarPreviewLateralAoSoltar(runtimeConfig)
			clearLateralSaltoPendente(false)
		end
		-- Sem direção → resetar
		resetDescerState()
		clearSubirSaltoPendente(true)
	end
end

-- ══════════════════════════════════════
-- Setup por Character (com cleanup)
-- ══════════════════════════════════════

local function setupCharacter(character: Model)
	limparConexoes()
	currentHrp = nil
	AnimacaoParkour.Destruir()
	Movimento.Soltar()
	lastJumpTime = 0
	lastIdleRecheckAt = 0
	clearSubirSaltoPendente(false)
	clearLateralSaltoPendente(false)
	resetDescerState()

	table.clear(failThrottles)
	runtimeConfig = Configs.mergeConfig(nil)
	MomentumManager.Configure(runtimeConfig)
	MomentumManager.Reset()

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	currentHrp = character:WaitForChild("HumanoidRootPart") :: BasePart

	-- Desabilita climbing padrão do Roblox (sistema de parkour substitui)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)

	AnimacaoParkour.Inicializar(character)

	-- JumpRequest
	local jumpConn = humanoid:GetPropertyChangedSignal("Jump"):Connect(function()
		if humanoid.Jump then
			onJumpRequest(character, humanoid)
		end
	end)
	table.insert(connections, jumpConn)

	-- Heartbeat: polling enquanto agarrado
	local heartbeatConn = RunService.Heartbeat:Connect(function()
		onHeartbeat(character, humanoid)
	end)
	table.insert(connections, heartbeatConn)

	-- Cleanup ao morrer
	local diedConn = humanoid.Died:Once(function()
		limparConexoes()
		AnimacaoParkour.Destruir()
		Movimento.Soltar()
		currentHrp = nil
		clearLateralSaltoPendente(false)
		clearSubirSaltoPendente(false)
		resetDescerState()
		table.clear(failThrottles)
		MomentumManager.Reset()
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
