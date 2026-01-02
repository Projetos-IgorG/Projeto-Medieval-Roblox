--[[
    EntradaJogador.client.lua
    
    Script local que captura inputs do jogador e envia ações para o servidor.
    Responsável apenas por:
    - Detectar inputs (mouse, teclado)
    - Enviar RemoteEvents com a ação desejada
    - Gerenciar estado de teclas pressionadas
    
    NÃO gerencia animações, estados ou lógica de combate.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local _ContextActionService = game:GetService("ContextActionService") -- Reservado para uso futuro

local player = Players.LocalPlayer

-- ═══════════════════════════════════════════════════════════════════
-- REMOTE EVENTS
-- ═══════════════════════════════════════════════════════════════════

local Remotos = ReplicatedStorage:WaitForChild("Remotos")
local TentarAcao = Remotos:WaitForChild("TentarAcao")

-- ═══════════════════════════════════════════════════════════════════
-- CONFIGURAÇÃO DE INPUTS
-- ═══════════════════════════════════════════════════════════════════

local Configuracao = {
	-- Tempo para considerar ataque pesado (segurar M1)
	TempoCarregarPesado = 0.2,

	-- Cooldowns
	CooldownDefesa = 0.5, -- Cooldown de 0.5 segundos para defesa

	-- Teclas
	TeclaAgachar = Enum.KeyCode.C,
	TeclaCorrer = Enum.KeyCode.LeftShift,
	TeclaQuebrarDefesa = Enum.KeyCode.G,
	TeclaEquipar1 = Enum.KeyCode.One,
	TeclaEquipar2 = Enum.KeyCode.Two,
}

-- ═══════════════════════════════════════════════════════════════════
-- ESTADO LOCAL DE INPUTS
-- ═══════════════════════════════════════════════════════════════════

local estadoInput = {
	mouse1Pressionado = false,
	mouse2Pressionado = false,
	tempoMouse1 = 0,
	agachadoAtivo = false,
	correndoAtivo = false,
	ultimaDefesa = 0,
}

-- Estado de equipamento
local _modoAtual = "Base" -- Modo de combate atual (lido do Status) - reservado para uso futuro
local equipBusy = false -- Evita spam de equipar/desequipar

-- Mapa de tecla para modo
local MapaTeclaModo = {
	[Enum.KeyCode.One] = "Punhos",
	[Enum.KeyCode.Two] = "UmaMaoEscudo",
}

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES DE AÇÃO
-- ═══════════════════════════════════════════════════════════════════

--- Envia ação para o servidor
local function EnviarAcao(acao: string, dados: any?)
	TentarAcao:FireServer(acao, dados)
end

--- Processa clique do mouse 1 (ataque)
--- No sistema de combo por marcadores:
--- - Se há combo ativo (janela ou animação), tenta marcar continuação
--- - Caso contrário, envia novo ataque
local function ProcessarMouse1Pressionado()
	estadoInput.mouse1Pressionado = true
	estadoInput.tempoMouse1 = tick()

	-- Verifica se há combo ativo (função exposta pelo ControladorEstado)
	local comboAtivo = _G.EstaComboAtivo and _G.EstaComboAtivo()
	local janelaAtiva = _G.EstaJanelaComboAtiva and _G.EstaJanelaComboAtiva()

	if comboAtivo or janelaAtiva then
		-- Combo ativo - marca para continuar
		if _G.MarcarContinuarCombo then
			local marcou = _G.MarcarContinuarCombo()
			if marcou then
				-- Também notifica servidor que input foi recebido
				EnviarAcao("AtacarLeveEmPe")
				return
			end
		end
	end

	-- Não está em combo - inicia novo ataque
	if estadoInput.agachadoAtivo then
		EnviarAcao("AtacarLeveAgachado")
	else
		EnviarAcao("AtacarLeveEmPe")
	end
end

--- Processa soltar mouse 1
local function ProcessarMouse1Solto()
	if not estadoInput.mouse1Pressionado then
		return
	end

	local tempoSegurando = tick() - estadoInput.tempoMouse1
	estadoInput.mouse1Pressionado = false

	-- Se segurou tempo suficiente, pode ser ataque pesado
	if tempoSegurando >= Configuracao.TempoCarregarPesado then
		EnviarAcao("SoltarPesado")
	end
end

--- Processa segurar mouse 1 (chamado em loop)
local function ProcessarMouse1Segurar()
	if not estadoInput.mouse1Pressionado then
		return
	end

	local tempoSegurando = tick() - estadoInput.tempoMouse1

	-- Após tempo mínimo, inicia carregamento pesado
	if tempoSegurando >= Configuracao.TempoCarregarPesado then
		EnviarAcao("CarregarPesado")
	end
end

--- Processa mouse 2 (bloqueio)
local function ProcessarMouse2Pressionado()
	-- Verifica cooldown de defesa
	local agora = tick()
	if (agora - estadoInput.ultimaDefesa) < Configuracao.CooldownDefesa then
		return -- Ainda em cooldown
	end

	estadoInput.mouse2Pressionado = true
	estadoInput.ultimaDefesa = agora
	EnviarAcao("Bloquear")
end

--- Processa soltar mouse 2
local function ProcessarMouse2Solto()
	if not estadoInput.mouse2Pressionado then
		return
	end

	estadoInput.mouse2Pressionado = false
	EnviarAcao("PararBloqueio")
end

--- Processa agachar
local function ProcessarAgacharPressionado()
	estadoInput.agachadoAtivo = true
	EnviarAcao("Agachar")
end

--- Processa levantar
local function ProcessarAgacharSolto()
	estadoInput.agachadoAtivo = false
	EnviarAcao("Levantar")
end

--- Processa quebrar defesa
local function ProcessarQuebrarDefesa()
	EnviarAcao("QuebrarDefesa")
end

--- Obtém o modo atual do Status
local function ObterModoAtual(): string
	local character = player.Character
	if not character then
		return "Base"
	end

	local status = character:FindFirstChild("Status")
	if not status then
		return "Base"
	end

	local modoAnimacao = status:FindFirstChild("modoAnimacao")
	if modoAnimacao and modoAnimacao:IsA("StringValue") then
		return modoAnimacao.Value
	end

	return "Base"
end

--- Processa toggle de equipar/desequipar modo
local function ProcessarToggleEquipar(modoDesejado: string)
	if equipBusy then
		return
	end

	local modoAtualValue = ObterModoAtual()

	-- Se já está nesse modo, desequipa (volta para Base)
	if modoDesejado ~= "Base" and modoAtualValue == modoDesejado then
		equipBusy = true
		EnviarAcao("Desequipar")

		-- Libera após tempo da animação
		task.delay(0.6, function()
			equipBusy = false
		end)
	else
		-- Equipa o novo modo
		equipBusy = true
		EnviarAcao("Equipar", modoDesejado)

		-- Libera após tempo da animação
		task.delay(0.6, function()
			equipBusy = false
		end)
	end
end

--- Processa pular
local function ProcessarPular()
	-- Se estiver agachado, levanta primeiro para então pular
	if estadoInput.agachadoAtivo then
		estadoInput.agachadoAtivo = false
		EnviarAcao("Levantar")
		task.delay(0.05, function()
			EnviarAcao("Pular")
		end)
		return
	end

	EnviarAcao("Pular")
end

-- ═══════════════════════════════════════════════════════════════════
-- LISTENERS DE INPUT
-- ═══════════════════════════════════════════════════════════════════

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	-- Mouse
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		ProcessarMouse1Pressionado()
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		ProcessarMouse2Pressionado()
		return
	end

	-- Teclado
	if input.KeyCode == Configuracao.TeclaCorrer then
		estadoInput.correndoAtivo = true
		-- Se estiver agachado, levanta antes de iniciar corrida
		if estadoInput.agachadoAtivo then
			estadoInput.agachadoAtivo = false
			EnviarAcao("Levantar")
			task.delay(0.05, function()
				EnviarAcao("Correr")
			end)
		else
			EnviarAcao("Correr")
		end
		return
	end

	if input.KeyCode == Configuracao.TeclaAgachar then
		ProcessarAgacharPressionado()
		return
	end

	if input.KeyCode == Configuracao.TeclaQuebrarDefesa then
		ProcessarQuebrarDefesa()
		return
	end

	-- Teclas de equipar com toggle
	local modoParaTecla = MapaTeclaModo[input.KeyCode]
	if modoParaTecla then
		ProcessarToggleEquipar(modoParaTecla)
		return
	end

	if input.KeyCode == Enum.KeyCode.Space then
		ProcessarPular()
		return
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	-- Mouse
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		ProcessarMouse1Solto()
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		ProcessarMouse2Solto()
		return
	end

	-- Teclado
	if input.KeyCode == Configuracao.TeclaCorrer then
		estadoInput.correndoAtivo = false
		-- Evita enviar PararCorrer se ainda estivermos agachados (isso pode resetar animação de agachar)
		if not estadoInput.agachadoAtivo then
			EnviarAcao("PararCorrer")
		end
		return
	end

	if input.KeyCode == Configuracao.TeclaAgachar then
		ProcessarAgacharSolto()
		return
	end
end)

-- ═══════════════════════════════════════════════════════════════════
-- LOOP PARA VERIFICAR SEGURAR MOUSE
-- ═══════════════════════════════════════════════════════════════════

local RunService = game:GetService("RunService")
local ultimaVerificacao = 0

RunService.Heartbeat:Connect(function()
	local agora = tick()

	-- Verifica a cada 0.1 segundos
	if agora - ultimaVerificacao < 0.1 then
		return
	end
	ultimaVerificacao = agora

	ProcessarMouse1Segurar()
end)

-- ═══════════════════════════════════════════════════════════════════
-- INICIALIZAÇÃO
-- ═══════════════════════════════════════════════════════════════════

print("[EntradaJogador] Inicializado - capturando inputs")
