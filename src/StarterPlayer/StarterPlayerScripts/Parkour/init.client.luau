--[[
	Parkour - init.client.luau
	Script principal do sistema de parkour.
	Responsável APENAS por captura de input e gerenciamento de estado.
	Toda lógica de verificação, análise e utilidades está nos módulos dedicados.

	VERSÃO: 2.0v

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

local player = Players.LocalPlayer
local Analisador = require(script:WaitForChild("Analisador"))
local Movimento = require(script:WaitForChild("Movimento"))
local Configs = require(script:WaitForChild("Configs"))
local Debug = require(script:WaitForChild("Debug"))
local CooldownManager = require(script:WaitForChild("CooldownManager"))
local Utilidades = require(script:WaitForChild("Utilidades"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modulos = ReplicatedStorage:WaitForChild("Modulos")
local ClientBridge = require(Modulos:WaitForChild("Core"):WaitForChild("ClientBridge"))
local AnimacaoParkour = require(Modulos:WaitForChild("Cliente"):WaitForChild("Visual"):WaitForChild("AnimacaoParkour"))

-- ══════════════════════════════════════
-- Estado local (conexões, cache, timers)
-- ══════════════════════════════════════

local connections: { RBXScriptConnection } = {}
local JUMP_COOLDOWN = 0.15
local lastJumpTime = 0
local runtimeConfig = Configs.mergeConfig(nil)
local cooldownBlockedLogAt = {} :: { [string]: number }
local lastIdleRecheckAt = 0
local currentHrp: BasePart? = nil

-- Pendentes de confirmação (SubirSalto / LateralSalto)
local subirSaltoPendente = nil -- { Result, ExpiresAt, SourceEdgePosition }
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
		if not CooldownManager.CanUseWithLog("SubirSalto", nil, now, cooldownBlockedLogAt) then
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

	local direcao = Utilidades.GetIntencaoDirecional(humanoid, hrp, runtimeConfig)

	if direcao == "Direita" or direcao == "Esquerda" then
		if not CooldownManager.CanUseWithLog("LateralSalto", direcao, now, cooldownBlockedLogAt) then
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
		if result.Acao == "VaultMedio" then
			if noChao then
				dbgPrint("[Parkour] VaultMedio sem corrida no chão: não pode fallback para Agarrar")
				if Configs.DebugEnabled then
					Analisador.DrawDebug(result)
				end
				return
			end

			local fallbackGrab = Analisador.TentarFallbackAgarrar(character, result, runtimeConfig)
			if fallbackGrab and fallbackGrab.Aprovado then
				dbgPrint("[Parkour] VaultMedio sem corrida -> fallback para Agarrar")
				result = fallbackGrab
			else
				dbgPrint(
					"[Parkour] VaultMedio sem corrida e fallback falhou | reason:",
					fallbackGrab and fallbackGrab.Reason or "nil"
				)
				if Configs.DebugEnabled then
					Analisador.DrawDebug(fallbackGrab or result)
				end
				return
			end
		else
			dbgPrint("[Parkour] Vault bloqueado: jogador não está correndo | Acao:", result.Acao)
			if Configs.DebugEnabled then
				Analisador.DrawDebug(result)
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

		if not CooldownManager.CanUseWithLog("Subir", nil, now, cooldownBlockedLogAt) then
			return
		end

		local ok, tipo, subirResult, escalarResult = Movimento.TentarSubir()

		drawClimbDebug(escalarResult, subirResult)

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
					dbgPrint("[Parkour] SubirSalto disponível — aperte Pular para confirmar")
				end
			end
		else
			CooldownManager.BlockAction(
				"Subir",
				nil,
				now,
				CooldownManager.GetFailCooldown("Subir", runtimeConfig.SubirFailCooldown, 0.5, runtimeConfig)
			)
		end
	elseif direcao == "Direita" or direcao == "Esquerda" then
		resetDescerState()
		clearSubirSaltoPendente(true)

		if lateralSaltoPendente and lateralSaltoPendente.Direcao == direcao then
			local curveFallbackTarget = lateralSaltoPendente.CurveFallbackTarget
			local switchToCurveAt = lateralSaltoPendente.SwitchToCurveAt or math.huge
			if curveFallbackTarget and now >= switchToCurveAt then
				local executouCurva = Movimento.ExecutarLateralForcado(curveFallbackTarget)
				if executouCurva then
					CooldownManager.RegisterSuccess("Lateral", direcao, now)
					clearLateralSaltoPendente(false)
					clearSubirSaltoPendente(false)
					return
				end
			end
		end

		if not CooldownManager.CanUseWithLog("Lateral", direcao, now, cooldownBlockedLogAt) then
			return
		end

		local ok, estadoLateral, lateralResult = Movimento.TentarMoverLateral(direcao)

		drawLateralDebug(lateralResult)

		if ok then
			CooldownManager.RegisterSuccess("Lateral", direcao, now)
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
				CooldownManager.BlockAction(
					"Lateral",
					direcao,
					now,
					CooldownManager.GetFailCooldown(
						"Lateral",
						runtimeConfig.LateralNoSurfaceCooldown,
						0.5,
						runtimeConfig
					)
				)
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

		if not CooldownManager.CanUseWithLog("Descer", nil, now, cooldownBlockedLogAt) then
			return
		end

		local ok, tipo, descerResult = Movimento.TentarDescer()

		drawDescerDebug(descerResult)

		if ok and tipo == "Descer" then
			CooldownManager.RegisterSuccess("Descer", nil, now)
			clearSubirSaltoPendente(true)
			resetDescerState()
		else
			CooldownManager.BlockAction(
				"Descer",
				nil,
				now,
				CooldownManager.GetFailCooldown("Descer", runtimeConfig.DescerFailCooldown, 0.25, runtimeConfig)
			)
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

	table.clear(cooldownBlockedLogAt)
	runtimeConfig = Configs.mergeConfig(nil)
	CooldownManager.Configure(runtimeConfig)
	CooldownManager.Reset()

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
