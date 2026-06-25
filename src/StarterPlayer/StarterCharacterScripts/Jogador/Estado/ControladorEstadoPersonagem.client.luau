--[[
    Script: ControladorEstadoPersonagem.client.luau
    Caminho: src/StarterPlayer/StarterCharacterScripts/Jogador/Estado
    Responsabilidade: Bootstrapper que inicializa e conecta todos os modulos de estado do personagem.
    Uso: LocalScript; roda automaticamente para o jogador local.
    Nao faz: Nao implementa logica diretamente; delega tudo aos modulos em Modulos/.
    Modulos: Animacao, Combo, Equipamento, Esquiva, Sincronizacao, Movimento
]]
local DEBUG_ENABLED = true

local function DebugPrint(...)
	if DEBUG_ENABLED then
		print(...)
	end
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- ═══════════════════════════════════════════════════════════════════
-- Referências base
-- ═══════════════════════════════════════════════════════════════════

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local animator = humanoid:WaitForChild("Animator")

-- ═══════════════════════════════════════════════════════════════════
-- Módulos externos
-- ═══════════════════════════════════════════════════════════════════

local ModulosRS = ReplicatedStorage
local Modulo_Configuracoes =
	require(ModulosRS:WaitForChild("Combate"):WaitForChild("Configuracoes"):WaitForChild("ConfigCombate"))
local Modulo_Combo = require(ModulosRS:WaitForChild("Combate"):WaitForChild("Dominio"):WaitForChild("ComboCombate"))
local GerenciadorHitboxCliente =
	require(ModulosRS:WaitForChild("Combate"):WaitForChild("Hitbox"):WaitForChild("GerenciadorHitboxCliente"))
local ClientBridge =
	require(ModulosRS:WaitForChild("Jogador"):WaitForChild("ComunicacaoCliente"):WaitForChild("PonteCliente"))

-- ═══════════════════════════════════════════════════════════════════
-- Constantes
-- ═══════════════════════════════════════════════════════════════════

local TIMINGS = {
	JumpHold = 0.28,
	RunInAirSpeed = 0.4,

	MoveFadeIn = 0.18,
	MoveFadeOut = 0.18,

	ActionFadeIn = 0.20,
	ActionFadeOut = 0.20,

	SoftEnd = 0.40,
}

-- ═══════════════════════════════════════════════════════════════════
-- Desativar script Animate padrão
-- ═══════════════════════════════════════════════════════════════════

local function DesativarScriptAnimate()
	local animate = character:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
		DebugPrint("[ControladorEstado] Script Animate padrão desativado")
	end

	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		track:Stop(0)
	end
end

DesativarScriptAnimate()

-- ═══════════════════════════════════════════════════════════════════
-- Remotos
-- ═══════════════════════════════════════════════════════════════════

local Remotos = ReplicatedStorage:WaitForChild("Remotos")
local SincronizarEstado = Remotos:WaitForChild("SincronizarEstado")
local TocarAnimacao = Remotos:WaitForChild("TocarAnimacao")
local TentarAcao = Remotos:WaitForChild("TentarAcao")
local EquipamentoAcao = Remotos:WaitForChild("EquipamentoAcao")

-- ═══════════════════════════════════════════════════════════════════
-- Estado compartilhado (tabelas por referência)
-- ═══════════════════════════════════════════════════════════════════

local estadoAtual = {
	estadoMov = "Parado",
	estadoAcao = "Nenhuma",
	estadoAcaoAnterior = "Nenhuma",
	modoAnimacao = "Base",
	bloqueando = false,
	agachado = false,
	correndo = false,
}

local movementFlags = {
	isRunning = false,
	isJumping = false,
	isFalling = false,
	isClimbing = false,
	isSwimming = false,
	isRolling = false,
	isDashing = false,
}

local parkourState = {
	ativo = false,
	estadoAcaoAnterior = "Nenhuma",
}

local isShiftHeld = false

-- ═══════════════════════════════════════════════════════════════════
-- Gestão centralizada de conexões
-- ═══════════════════════════════════════════════════════════════════

local conexoesGlobais: { RBXScriptConnection } = {}

local function ConectarGlobal(signal: RBXScriptSignal, callback: (...any) -> ...any): RBXScriptConnection
	local conexao = signal:Connect(callback)
	table.insert(conexoesGlobais, conexao)
	return conexao
end

local function DesconectarTudoGlobal()
	for _, conexao in ipairs(conexoesGlobais) do
		if conexao.Connected then
			conexao:Disconnect()
		end
	end
	table.clear(conexoesGlobais)
end

script.Destroying:Connect(DesconectarTudoGlobal)
humanoid.Died:Connect(DesconectarTudoGlobal)

-- ═══════════════════════════════════════════════════════════════════
-- Contexto compartilhado
-- ═══════════════════════════════════════════════════════════════════

local Contexto = {
	-- Referências
	Player = player,
	Character = character,
	Humanoid = humanoid,
	Animator = animator,

	-- Estado compartilhado
	EstadoAtual = estadoAtual,
	MovementFlags = movementFlags,
	ParkourState = parkourState,
	IsShiftHeld = function()
		return isShiftHeld
	end,
	SetShiftHeld = function(v)
		isShiftHeld = v
	end,

	-- Constantes
	TIMINGS = TIMINGS,
	DEBUG_ENABLED = DEBUG_ENABLED,

	-- Remotos
	TentarAcao = TentarAcao,
	SincronizarEstado = SincronizarEstado,
	TocarAnimacao = TocarAnimacao,
	EquipamentoAcao = EquipamentoAcao,

	-- Módulos externos
	Modulo_Configuracoes = Modulo_Configuracoes,
	Modulo_Combo = Modulo_Combo,
	GerenciadorHitboxCliente = GerenciadorHitboxCliente,
	ClientBridge = ClientBridge,

	-- Utilidades
	ConectarGlobal = ConectarGlobal,
	DebugPrint = DebugPrint,

	-- Referências cruzadas (preenchidas abaixo)
	Modulos = {},
}

-- ═══════════════════════════════════════════════════════════════════
-- Carregar módulos
-- ═══════════════════════════════════════════════════════════════════

local modulosFolder = script.Parent:WaitForChild("Modulos")

local ModuloMovimento = require(modulosFolder:WaitForChild("Movimento"))
local ModuloAnimacao = require(modulosFolder:WaitForChild("Animacao"))
local ModuloCombo = require(modulosFolder:WaitForChild("Combo"))
local ModuloEquipamento = require(modulosFolder:WaitForChild("Equipamento"))
local ModuloEsquiva = require(modulosFolder:WaitForChild("Esquiva"))
local ModuloSincronizacao = require(modulosFolder:WaitForChild("Sincronizacao"))

-- Registrar referências cruzadas
Contexto.Modulos.Movimento = ModuloMovimento
Contexto.Modulos.Animacao = ModuloAnimacao
Contexto.Modulos.Combo = ModuloCombo
Contexto.Modulos.Equipamento = ModuloEquipamento
Contexto.Modulos.Esquiva = ModuloEsquiva
Contexto.Modulos.Sincronizacao = ModuloSincronizacao

-- ═══════════════════════════════════════════════════════════════════
-- Inicializar módulos (ordem importa: dependências primeiro)
-- ═══════════════════════════════════════════════════════════════════

-- 1. Movimento (standalone, sem deps de outros módulos na init)
ModuloMovimento.Inicializar(Contexto)

-- 2. Animação (depende de Movimento, mas também precisa de Combo/Equipamento/Esquiva)
ModuloAnimacao.Inicializar(Contexto)

-- 3. Combo (depende de Animacao)
ModuloCombo.Inicializar(Contexto)

-- 4. Equipamento (depende de Animacao)
ModuloEquipamento.Inicializar(Contexto)

-- 5. Esquiva (depende de Animacao e Movimento)
ModuloEsquiva.Inicializar(Contexto)

-- 6. Sincronização (depende de Animacao e Movimento)
ModuloSincronizacao.Inicializar(Contexto)

-- ═══════════════════════════════════════════════════════════════════
-- Input: Shift (corrida)
-- ═══════════════════════════════════════════════════════════════════

ConectarGlobal(UserInputService.InputBegan, function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.LeftShift then
		movementFlags.isRunning = true
		isShiftHeld = true
		estadoAtual.correndo = true
		ModuloMovimento.AtualizarVelocidadeLocal()
		ModuloMovimento.AtualizarEstadoMovimento()
	end
end)

ConectarGlobal(UserInputService.InputEnded, function(input, _gameProcessed)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		movementFlags.isRunning = false
		isShiftHeld = false
		estadoAtual.correndo = false
		ModuloMovimento.AtualizarVelocidadeLocal()
		ModuloMovimento.AtualizarEstadoMovimento()
	end
end)

-- ═══════════════════════════════════════════════════════════════════
-- Heartbeat: atualização de estado de movimento
-- ═══════════════════════════════════════════════════════════════════

ConectarGlobal(RunService.Heartbeat, function()
	ModuloMovimento.AtualizarEstadoMovimento()
end)

-- ═══════════════════════════════════════════════════════════════════
-- StateChanged do humanoid
-- ═══════════════════════════════════════════════════════════════════

humanoid.StateChanged:Connect(ModuloMovimento.OnStateChanged)

-- ═══════════════════════════════════════════════════════════════════
-- Hitbox callbacks
-- ═══════════════════════════════════════════════════════════════════

GerenciadorHitboxCliente.DefinirCharacter(character)

GerenciadorHitboxCliente.DefinirCallbackHit(function(alvo, mao, raycastResult)
	ModuloCombo.AplicarHitFreeze()
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local alvoHrp = alvo:FindFirstChild("HumanoidRootPart")
	TentarAcao:FireServer("HitboxAcerto", {
		mao = mao,
		alvo = alvo,
		cframe = hrp and hrp.CFrame or nil,
		alvoCFrame = alvoHrp and alvoHrp.CFrame or nil,
		multiplicadorDano = ModuloCombo.ObterMultiplicadorDano(),
		parteAtingida = raycastResult and raycastResult.Instance.Name or nil,
	})
end)

GerenciadorHitboxCliente.DefinirCallbackSolidHit(function(_raycastResult, _mao)
	ModuloCombo.AplicarRewindParteSolida()
end)

-- ═══════════════════════════════════════════════════════════════════
-- Pré-carregar animações e inicializar estado visual
-- ═══════════════════════════════════════════════════════════════════

ModuloAnimacao.PreCarregarAnimacoes()

-- ═══════════════════════════════════════════════════════════════════
-- Monitor de script Animate tardio
-- ═══════════════════════════════════════════════════════════════════

ConectarGlobal(character.ChildAdded, function(child)
	if (child:IsA("Script") or child:IsA("LocalScript")) and child.Name == "Animate" then
		task.defer(function()
			if child.Parent then
				child:Destroy()
				DebugPrint("[ControladorEstado] Script Animate tardio desativado no cliente")
				for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
					track:Stop(0)
				end
				ModuloAnimacao.AtualizarBaseIdle()
				ModuloAnimacao.AtualizarAnimacaoMovimento()
			end
		end)
	end
end)

-- ═══════════════════════════════════════════════════════════════════
-- Estado visual inicial
-- ═══════════════════════════════════════════════════════════════════

ModuloAnimacao.AtualizarBaseIdle()
ModuloAnimacao.AtualizarAnimacaoMovimento()

DebugPrint("[ControladorEstado] Inicializado - bootstrapper com 6 módulos")
