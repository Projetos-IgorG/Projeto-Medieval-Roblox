--[[
	ParkourTesting - init.client.luau
	Script principal do sistema de parkour.

	Keybinds (baseado em intenção direcional, não teclas específicas):
	- No chão/ar + Jump: VaultBaixo / VaultMédio / Agarrar
	- Agarrado + Frente (W): Subir (ou Escalar se couber em cima)
	- Agarrado + Frente + Jump: SubirSalto
	- Agarrado + Jump: Escalar (se couber) ou Soltar
	- Agarrado + Trás (S) + Jump: PuloTras
	- Agarrado + Trás (S) segurar: Descer (soltar após DescerHoldTime)
	- Cooldown para evitar verificações repetidas
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Analisador = require(script:WaitForChild("Analisador"))
local Movimento = require(script:WaitForChild("Movimento"))
local Configs = require(script:WaitForChild("Configs"))
local Debug = require(script:WaitForChild("Debug"))

-- ══════════════════════════════════════
-- Estado de conexões (cleanup no respawn)
-- ══════════════════════════════════════

local connections: { RBXScriptConnection } = {}
local JUMP_COOLDOWN = 0.15 -- segundos entre cada verificação de parkour
local MOVE_COOLDOWN = 0.35 -- cooldown entre ações de Subir (W contínuo)
local lastJumpTime = 0
local lastMoveTime = 0

-- Estado de SubirSalto pendente (quando W detecta que precisa de W+Pulo)
local subirSaltoPendente = nil

-- Estado de Descer (segurar S): controla o hold time para não conflitar com PuloTras
local descerHoldStart = 0 -- timestamp de quando começou a segurar S
local descerHolding = false -- está segurando S?

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

-- ══════════════════════════════════════
-- Detectar intenção direcional (frente/trás)
-- Usa MoveDirection do Humanoid (funciona em todas as plataformas)
-- ══════════════════════════════════════

local function getIntencaoDirecional(humanoid, hrp): string?
	local moveDir = humanoid.MoveDirection
	if moveDir.Magnitude < 0.1 then
		return nil -- sem input direcional
	end

	local lookVector = hrp.CFrame.LookVector
	-- Projetar na horizontal (ignorar Y)
	local lookFlat = Vector3.new(lookVector.X, 0, lookVector.Z).Unit
	local moveFlat = Vector3.new(moveDir.X, 0, moveDir.Z).Unit

	local dot = lookFlat:Dot(moveFlat)

	if dot > 0.3 then
		return "Frente"
	elseif dot < -0.3 then
		return "Tras"
	end

	return nil -- lateral ou ambíguo
end

-- ══════════════════════════════════════
-- Lógica de Jump quando AGARRADO
-- ══════════════════════════════════════

local function onJumpAgarrado(humanoid, hrp)
	local direcao = getIntencaoDirecional(humanoid, hrp)

	-- PuloTras: Trás + Pular (prioridade máxima quando S está sendo segurado)
	if direcao == "Tras" then
		local ok = Movimento.PuloTras()
		if ok then
			subirSaltoPendente = nil
			resetDescerState()
			return
		end
	end

	-- SubirSalto: Frente + Pular (com pendente)
	if direcao == "Frente" and subirSaltoPendente then
		local ok = Movimento.ExecutarSubirSalto(subirSaltoPendente)
		if ok then
			subirSaltoPendente = nil
			return
		end
	end

	-- Escalar: Pular (com ou sem direção frente) — tenta subir em cima da plataforma
	local escalou = Movimento.TentarEscalar()
	if escalou then
		subirSaltoPendente = nil
		resetDescerState()
		return
	end

	-- Se pressionou frente mas não conseguiu escalar, não soltar (continuar agarrado)
	if direcao == "Frente" then
		return
	end

	-- Fallback: soltar (só quando não tem direção ou direção lateral)
	subirSaltoPendente = nil
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
-- W = Subir | S (segurar) = Descer (com hold time para PuloTras)
-- ══════════════════════════════════════

local function onHeartbeat(character, humanoid)
	if not Movimento.EstaAgarrado() then
		subirSaltoPendente = nil
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

		-- Cooldown entre ações de subir
		if now - lastMoveTime < MOVE_COOLDOWN then
			return
		end

		local ok, tipo, subirResult, escalarResult = Movimento.TentarSubir()

		-- Debug visual: SEMPRE desenhar os rays de verificação (mesmo se falhar)
		Analisador.ClearDebug()
		Debug.DrawClimbDebug(escalarResult, subirResult)

		if ok then
			lastMoveTime = now

			if tipo == "Escalar" or tipo == "Subir" then
				subirSaltoPendente = nil
			elseif tipo == "SubirSalto" then
				subirSaltoPendente = subirResult
				print("[Parkour] SubirSalto disponível — aperte Pular para confirmar")
			end
		end
	elseif direcao == "Tras" then
		-- Descer: precisa SEGURAR S por DescerHoldTime antes de soltar
		-- Isso permite que S+Jump (PuloTras) funcione sem conflito
		if not descerHolding then
			-- Começou a segurar S
			descerHolding = true
			descerHoldStart = now
		else
			-- Já está segurando S — verificar se passou o hold time
			local finalConfig = Configs.mergeConfig(nil)
			local holdTime = finalConfig.DescerHoldTime

			if now - descerHoldStart >= holdTime then
				-- Segurou S por tempo suficiente → soltar
				subirSaltoPendente = nil
				resetDescerState()
				Movimento.Soltar()
			end
			-- Se não passou o holdTime, NÃO FAZ NADA (dá janela pra PuloTras)
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
	lastMoveTime = 0
	subirSaltoPendente = nil
	resetDescerState()

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
