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

local player = Players.LocalPlayer
local Analisador = require(script:WaitForChild("Analisador"))
local Movimento = require(script:WaitForChild("Movimento"))
local Configs = require(script:WaitForChild("Configs"))
local Debug = require(script:WaitForChild("Debug"))
local CooldownManager = require(script:WaitForChild("CooldownManager"))

-- ══════════════════════════════════════
-- Estado de conexões (cleanup no respawn)
-- ══════════════════════════════════════

local connections: { RBXScriptConnection } = {}
local JUMP_COOLDOWN = 0.1 -- segundos entre cada verificação de parkour
local lastJumpTime = 0
local runtimeConfig = Configs.mergeConfig(nil)
local cooldownBlockedLogAt = {} :: { [string]: number }

-- Estado de SubirSalto pendente (quando W detecta que precisa de W+Pulo)
local subirSaltoPendente = nil -- { Result, ExpiresAt, SourceEdgePosition }

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

local function clearSubirSaltoPendente()
	subirSaltoPendente = nil
end

local function setSubirSaltoPendente(subirResult)
	subirSaltoPendente = {
		Result = subirResult,
		ExpiresAt = os.clock() + (runtimeConfig.SubirSaltoConfirmWindow or 0.35),
		SourceEdgePosition = subirResult and subirResult.SourceEdgePosition,
	}
end

local function getSubirSaltoPendenteValido()
	if not subirSaltoPendente then
		return nil
	end

	if os.clock() > (subirSaltoPendente.ExpiresAt or 0) then
		subirSaltoPendente = nil
		return nil
	end

	local grabData = Movimento.GetGrabData()
	local sourceEdge = subirSaltoPendente.SourceEdgePosition
	if grabData and sourceEdge and grabData.EdgePosition then
		local maxDrift = runtimeConfig.SubirSaltoConfirmEdgeTolerance or 2.5
		if (grabData.EdgePosition - sourceEdge).Magnitude > maxDrift then
			subirSaltoPendente = nil
			return nil
		end
	end

	return subirSaltoPendente.Result
end

-- ══════════════════════════════════════
-- Detectar intenção direcional (frente/trás)
-- Usa MoveDirection do Humanoid (funciona em todas as plataformas)
-- ══════════════════════════════════════

local function getIntencaoDirecional(humanoid, hrp): string?
	local moveDir = humanoid.MoveDirection
	if moveDir.Magnitude < 0.1 then
		return nil -- sem input direcional
	end

	local lateralThreshold = runtimeConfig.LateralInputDotThreshold or 0.35

	local lookVector = hrp.CFrame.LookVector
	local rightVector = hrp.CFrame.RightVector
	-- Projetar na horizontal (ignorar Y)
	local lookFlat = Vector3.new(lookVector.X, 0, lookVector.Z).Unit
	local rightFlat = Vector3.new(rightVector.X, 0, rightVector.Z).Unit
	local moveFlat = Vector3.new(moveDir.X, 0, moveDir.Z).Unit

	local dotForward = lookFlat:Dot(moveFlat)
	local dotRight = rightFlat:Dot(moveFlat)

	-- Prioridade para frente/trás quando input estiver diagonal (W+A/W+D)
	if dotForward > 0.3 then
		return "Frente"
	elseif dotForward < -0.3 then
		return "Tras"
	elseif dotRight >= lateralThreshold then
		return "Direita"
	elseif dotRight <= -lateralThreshold then
		return "Esquerda"
	end

	return nil -- lateral ou ambíguo
end

-- ══════════════════════════════════════
-- Lógica de Jump quando AGARRADO
-- ══════════════════════════════════════

local function onJumpAgarrado(humanoid, hrp)
	local direcao = getIntencaoDirecional(humanoid, hrp)

	if direcao == "Direita" or direcao == "Esquerda" then
		local now = os.clock()
		if not canUseActionCooldown("LateralSalto", direcao, now) then
			return
		end

		local ok = Movimento.PuloLateral(direcao)
		if ok then
			CooldownManager.RegisterSuccess("LateralSalto", direcao, now)
			clearSubirSaltoPendente()
			resetDescerState()
			return
		end
	end

	-- PuloTras: Trás + Pular (prioridade máxima quando S está sendo segurado)
	if direcao == "Tras" then
		local ok = Movimento.PuloTras()
		if ok then
			clearSubirSaltoPendente()
			resetDescerState()
			return
		end
	end

	-- SubirSalto: Frente + Pular (com pendente)
	local subirSaltoValido = getSubirSaltoPendenteValido()
	if direcao == "Frente" and subirSaltoValido then
		local now = os.clock()
		if not canUseActionCooldown("SubirSalto", nil, now) then
			return
		end

		local ok = Movimento.ExecutarSubirSalto(subirSaltoValido)
		if ok then
			CooldownManager.RegisterSuccess("SubirSalto", nil, now)
			clearSubirSaltoPendente()
			return
		end
	end

	-- Escalar: Pular (com ou sem direção frente) — tenta subir em cima da plataforma
	local escalou = Movimento.TentarEscalar()
	if escalou then
		clearSubirSaltoPendente()
		resetDescerState()
		return
	end

	-- Se pressionou frente mas não conseguiu escalar, não soltar (continuar agarrado)
	if direcao == "Frente" then
		return
	end

	-- Fallback: soltar (só quando não tem direção ou direção lateral)
	clearSubirSaltoPendente()
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
	if not Movimento.EstaAgarrado() then
		clearSubirSaltoPendente()
		resetDescerState()
		return
	end

	if Movimento.EstaEmAcao() then
		return
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local direcao = getIntencaoDirecional(humanoid, hrp)
	local now = os.clock()

	if direcao == "Frente" then
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
				clearSubirSaltoPendente()
			elseif tipo == "SubirSalto" then
				setSubirSaltoPendente(subirResult)
				CooldownManager.BlockAction("Subir", nil, now, runtimeConfig.SubirSaltoCheckCooldown or 0.25)
				print("[Parkour] SubirSalto disponível — aperte Pular para confirmar")
			end
		else
			local fallbackMin = (runtimeConfig.MinimumCooldowns and runtimeConfig.MinimumCooldowns.Subir) or 0.5
			local failCooldown = runtimeConfig.SubirFailCooldown or fallbackMin
			CooldownManager.BlockAction("Subir", nil, now, failCooldown)
		end
	elseif direcao == "Direita" or direcao == "Esquerda" then
		resetDescerState()
		clearSubirSaltoPendente()

		if not canUseActionCooldown("Lateral", direcao, now) then
			return
		end

		local ok, estadoLateral, lateralResult = Movimento.TentarMoverLateral(direcao)

		Analisador.ClearDebug()
		Debug.DrawLateralDebug(lateralResult)

		if ok then
			CooldownManager.RegisterSuccess("Lateral", direcao, now)
			if estadoLateral then
				print("[Parkour]", estadoLateral)
			end
		elseif lateralResult and (lateralResult.Reason == "NoLateralSurface" or lateralResult.Reason == "NoLateralSurfaceCached") then
			local fallbackMin = (runtimeConfig.MinimumCooldowns and runtimeConfig.MinimumCooldowns.Lateral) or 0.5
			local failCooldown = runtimeConfig.LateralNoSurfaceCooldown or fallbackMin
			CooldownManager.BlockAction("Lateral", direcao, now, failCooldown)
		end
	elseif direcao == "Tras" then
		if not descerHolding then
			descerHolding = true
			descerHoldStart = now
			clearSubirSaltoPendente()
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
			clearSubirSaltoPendente()
			resetDescerState()
		else
			clearSubirSaltoPendente()
			resetDescerState()
			Movimento.Soltar()
		end
	else
		-- Sem direção → resetar estado de descer
		resetDescerState()
		-- Não limpar subirSaltoPendente imediatamente (janela pra apertar pulo)
	end
end

-- ══════════════════════════════════════
-- Setup por Character (com cleanup)
-- ══════════════════════════════════════

local function setupCharacter(character: Model)
	limparConexoes()
	Movimento.Soltar()
	lastJumpTime = 0
	clearSubirSaltoPendente()
	resetDescerState()

	table.clear(cooldownBlockedLogAt)
	runtimeConfig = Configs.mergeConfig(nil)
	CooldownManager.Configure(runtimeConfig)
	CooldownManager.Reset()

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid

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
		Movimento.Soltar()
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
