--[[
	ParkourTesting - init.client.luau
	Script principal do sistema de parkour.

	Keybind: Jump intent (Space / A no console / JumpButton no mobile)
	Lógica:
		- No chão: apenas VaultBaixo / VaultMédio
		- No ar: VaultBaixo / VaultMédio / Agarrar
		- Agarrado + Jump: solta
		- Cooldown para evitar verificações repetidas ao segurar pulo
]]

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local Analisador = require(script:WaitForChild("Analisador"))
local Movimento = require(script:WaitForChild("Movimento"))

-- ══════════════════════════════════════
-- Estado de conexões (cleanup no respawn)
-- ══════════════════════════════════════

local connections: { RBXScriptConnection } = {}
local JUMP_COOLDOWN = 0.2 -- segundos entre cada verificação de parkour
local lastJumpTime = 0

local function limparConexoes()
	for _, conn in ipairs(connections) do
		conn:Disconnect()
	end
	table.clear(connections)
end

-- ══════════════════════════════════════
-- Lógica principal de parkour no Jump
-- ══════════════════════════════════════

local function onJumpRequest(character: Model, humanoid: Humanoid)
	-- Cooldown: ignorar se apertou muito rápido (segurar pulo)
	local now = os.clock()
	if now - lastJumpTime < JUMP_COOLDOWN then
		return
	end
	lastJumpTime = now

	-- Se está agarrado, soltar ao pular
	if Movimento.EstaAgarrado() then
		Movimento.Soltar()
		return
	end

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
-- Setup por Character (com cleanup)
-- ══════════════════════════════════════

local function setupCharacter(character: Model)
	limparConexoes()
	Movimento.Soltar()
	lastJumpTime = 0

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid

	-- JumpRequest: dispara em qualquer plataforma (Space, A, JumpButton)
	local jumpConn = humanoid:GetPropertyChangedSignal("Jump"):Connect(function()
		if humanoid.Jump then
			onJumpRequest(character, humanoid)
		end
	end)
	table.insert(connections, jumpConn)

	-- Cleanup ao morrer
	local diedConn = humanoid.Died:Once(function()
		limparConexoes()
		Movimento.Soltar()
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
