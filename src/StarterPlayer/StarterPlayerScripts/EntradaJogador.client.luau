--[[
    EntradaJogador.client.lua
    
    Script local que captura inputs do jogador e envia ações para o servidor.
    Responsável apenas por:
    - Detectar inputs (mouse, teclado)
    - Enviar RemoteEvents com a ação desejada
    - Gerenciar estado de teclas pressionadas
    
    NÃO gerencia animações, estados ou lógica de combate.
]]

-- ═══════════════════════════════════════════════════════════════════
-- CONFIGURAÇÃO DE DEBUG
-- ═══════════════════════════════════════════════════════════════════
local DEBUG_ENABLED = false -- Altere para true para habilitar prints de debug

--- Função para imprimir apenas se debug estiver habilitado
local function DebugPrint(...)
	if DEBUG_ENABLED then
		print(...)
	end
end

--- Função para advertir apenas se debug estiver habilitado
local function DebugWarn(...)
	if DEBUG_ENABLED then
		warn(...)
	end
end

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local _ContextActionService = game:GetService("ContextActionService") -- Reservado para uso futuro

local player = Players.LocalPlayer

-- ═══════════════════════════════════════════════════════════════════
-- REMOTE EVENTS
-- ═══════════════════════════════════════════════════════════════════

local Remotos = ReplicatedStorage:WaitForChild("Remotos")
local TentarAcao = Remotos:WaitForChild("TentarAcao")
local EquipAnimacaoTerminou = Remotos:WaitForChild("EquipAnimacaoTerminou")

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
	TeclaDash = Enum.KeyCode.Q,
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

-- ═══════════════════════════════════════════════════════════════════
-- SISTEMA DE FILA DE EQUIPAMENTO
-- ═══════════════════════════════════════════════════════════════════
--[[
    Sistema de fila para gerenciar troca de tools com animações reversíveis.
    
    Estados possíveis:
    - estadoEquip = "idle" → Nenhuma animação de equip em andamento
    - estadoEquip = "equipando" → Animação de equipar tocando (velocidade positiva)
    - estadoEquip = "desequipando" → Animação de desequipar tocando (velocidade positiva ou negativa)
    
    Variáveis:
    - toolAtualEquipado: Tool que está atualmente equipado (modo ativo no servidor)
    - toolEmAnimacao: Tool cuja animação está tocando agora
    - toolAlvo: Tool que queremos ter equipado no final (nil = queremos ficar sem arma)
]]

local estadoEquip = "idle" -- "idle", "equipando", "desequipando"
local toolAtualEquipado = nil -- Tool que está efetivamente equipado (modo ativo)
local toolEmAnimacao = nil -- Tool cuja animação está tocando
local toolAlvo = nil -- Tool que queremos ter no final (nil = Base)

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES BASE
-- ═══════════════════════════════════════════════════════════════════

--- Envia ação para o servidor
local function EnviarAcao(acao: string, dados: any?)
	TentarAcao:FireServer(acao, dados)
end

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES AUXILIARES DE EQUIPAMENTO
-- ═══════════════════════════════════════════════════════════════════

--- Obtém o modo de um Tool
local function ObterModoDoTool(tool: Tool): string?
	if not tool then
		return nil
	end
	local modoValue = tool:FindFirstChild("modoAnimacao")
	if modoValue and modoValue:IsA("StringValue") and modoValue.Value ~= "" and modoValue.Value ~= "Base" then
		return modoValue.Value
	end
	return nil
end

-- Forward declaration para permitir referência circular
local ProcessarProximaAcao

-- Timeout para detectar se ação foi rejeitada pelo servidor
local TIMEOUT_ACAO = 0.3 -- segundos
local ultimoIdAcao = 0

--- Atualiza o estado da backpack (habilita/desabilita)
--- Bloqueia a backpack durante animações de equip/desequip
local function AtualizarBackpack()
	local bloqueado = estadoEquip ~= "idle"
	local success, result = pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, not bloqueado)
	end)
	if not success then
		DebugWarn("[EntradaJogador] Falha ao atualizar estado da mochila:", result)
	end
end

--- Verifica se há animação ativa após timeout, senão reseta
local function VerificarTimeoutAcao(idAcao: number)
	-- Se o ID mudou, uma nova ação foi iniciada - ignora este timeout
	if idAcao ~= ultimoIdAcao then
		return
	end

	-- Se ainda estamos em estado não-idle mas não há animação, reseta
	if estadoEquip ~= "idle" then
		local temAnimacao = _G.EstaEmAnimacaoEquip and _G.EstaEmAnimacaoEquip()
		if not temAnimacao then
			DebugPrint("[EntradaJogador] Timeout: ação rejeitada pelo servidor, resetando estado")
			estadoEquip = "idle"
			toolEmAnimacao = nil
			AtualizarBackpack()
			ProcessarProximaAcao()
		end
	end
end

--- Inicia animação de equipar um tool
local function IniciarEquipar(tool: Tool, modo: string)
	estadoEquip = "equipando"
	toolEmAnimacao = tool
	ultimoIdAcao = ultimoIdAcao + 1
	local idAtual = ultimoIdAcao
	AtualizarBackpack() -- Bloqueia backpack durante animação
	EnviarAcao("Equipar", modo)
	DebugPrint("[EntradaJogador] Iniciando equipar:", tool.Name, "- Modo:", modo)

	-- Configura timeout para detectar rejeição
	task.delay(TIMEOUT_ACAO, function()
		VerificarTimeoutAcao(idAtual)
	end)
end

--- Inicia animação de desequipar
local function IniciarDesequipar(tool: Tool)
	estadoEquip = "desequipando"
	toolEmAnimacao = tool
	ultimoIdAcao = ultimoIdAcao + 1
	local idAtual = ultimoIdAcao
	AtualizarBackpack() -- Bloqueia backpack durante animação
	EnviarAcao("Desequipar")
	DebugPrint("[EntradaJogador] Iniciando desequipar:", tool and tool.Name or "?")

	-- Configura timeout para detectar rejeição
	task.delay(TIMEOUT_ACAO, function()
		VerificarTimeoutAcao(idAtual)
	end)
end

--- Inverte a animação atual
--- Se não há animação para inverter, reseta estado e processa a fila
local function InverterAnimacao(novaDirecao: number, modo: string?)
	local sucesso = false
	if _G.InverterEquipAnimacao then
		sucesso = _G.InverterEquipAnimacao(novaDirecao)
	end

	if sucesso then
		-- Inversão funcionou, atualiza estado e notifica servidor
		EnviarAcao("InverterEquipAnimacao", { direcao = novaDirecao, modo = modo })

		if novaDirecao == 1 then
			estadoEquip = "equipando"
			DebugPrint("[EntradaJogador] Invertendo para equipar. Modo:", modo or "?")
		else
			estadoEquip = "desequipando"
			DebugPrint("[EntradaJogador] Invertendo para desequipar")
		end
	else
		-- Não há animação para inverter - reseta estado e processa fila
		DebugPrint("[EntradaJogador] Inversão falhou - resetando estado e processando fila")
		estadoEquip = "idle"
		toolEmAnimacao = nil
		AtualizarBackpack() -- Libera backpack quando voltar para idle
		-- Chama ProcessarProximaAcao após um pequeno delay para evitar recursão
		task.defer(function()
			ProcessarProximaAcao()
		end)
	end
end

--- Processa a fila - chamado quando uma animação termina
ProcessarProximaAcao = function()
	-- Se toolAlvo é diferente do que temos, precisamos agir
	if toolAlvo ~= toolAtualEquipado then
		if toolAlvo then
			-- Queremos equipar algo
			local modo = ObterModoDoTool(toolAlvo)
			if modo then
				if toolAtualEquipado then
					-- Primeiro precisa desequipar o atual
					IniciarDesequipar(toolAtualEquipado)
				else
					-- Pode equipar direto
					IniciarEquipar(toolAlvo, modo)
				end
			else
				-- Tool não tem modo válido, ignora
				toolAlvo = toolAtualEquipado
			end
		else
			-- Queremos ficar sem arma
			if toolAtualEquipado then
				IniciarDesequipar(toolAtualEquipado)
			end
		end
	else
		-- Já temos o que queremos, idle
		estadoEquip = "idle"
		toolEmAnimacao = nil
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- CALLBACKS GLOBAIS
-- ═══════════════════════════════════════════════════════════════════

--- Callback chamado pelo ControladorEstado quando a animação de equipar/desequipar termina
--- @param direcaoFinal number 1 se terminou equipando, -1 se terminou desequipando
_G.OnEquipAnimacaoTerminou = function(direcaoFinal: number)
	DebugPrint(
		"[EntradaJogador] Animação terminou. Direção:",
		direcaoFinal,
		"Tool em animação:",
		toolEmAnimacao and toolEmAnimacao.Name or "nil"
	)

	if direcaoFinal == 1 then
		-- Terminou equipando - agora temos o tool equipado
		toolAtualEquipado = toolEmAnimacao
	elseif direcaoFinal == -1 then
		-- Terminou desequipando - agora não temos tool
		toolAtualEquipado = nil
	end

	toolEmAnimacao = nil
	estadoEquip = "idle"
	AtualizarBackpack() -- Libera backpack quando animação termina

	-- Notifica o servidor que a animação de equip/desequip terminou
	EquipAnimacaoTerminou:FireServer()

	-- Processa próxima ação da fila
	ProcessarProximaAcao()
end

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES DE AÇÃO (COMBATE/MOVIMENTO)
-- ═══════════════════════════════════════════════════════════════════

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

--- Processa quando um Tool é equipado
--- Gerencia fila de equipamento e animações reversíveis
local function ProcessarToolEquipado(tool: Tool)
	local modoDesejado = ObterModoDoTool(tool)
	if not modoDesejado then
		DebugWarn("[EntradaJogador] Tool '", tool.Name, "' não tem modoAnimacao válido")
		return
	end

	DebugPrint("[EntradaJogador] Tool adicionado:", tool.Name, "- Estado atual:", estadoEquip)

	-- Atualiza o alvo
	toolAlvo = tool

	-- Se idle, inicia ação diretamente
	if estadoEquip == "idle" then
		if toolAtualEquipado then
			-- Precisa desequipar primeiro
			IniciarDesequipar(toolAtualEquipado)
		else
			-- Pode equipar direto
			IniciarEquipar(tool, modoDesejado)
		end
		return
	end

	-- Se estamos equipando
	if estadoEquip == "equipando" then
		if toolEmAnimacao == tool then
			-- Re-equipando o mesmo tool que já está equipando - não faz nada
			DebugPrint("[EntradaJogador] Já está equipando este tool")
			return
		else
			-- Equipando tool A, mas queremos tool B
			-- Precisa reverter animação de A para desequipar, depois equipar B
			InverterAnimacao(-1, nil)
			-- toolAlvo já está como tool B, será processado quando animação terminar
			return
		end
	end

	-- Se estamos desequipando
	if estadoEquip == "desequipando" then
		if toolEmAnimacao == tool then
			-- Estava desequipando este tool, mas agora quer equipar novamente
			-- Inverte a animação para equipar
			InverterAnimacao(1, modoDesejado)
			return
		else
			-- Estava desequipando tool A para equipar B, mas agora quer C
			-- Continua desequipando A, toolAlvo atualizado para C será processado depois
			DebugPrint("[EntradaJogador] Atualizando alvo para:", tool.Name)
			return
		end
	end
end

--- Processa quando um Tool é desequipado (removido do character)
--- Gerencia fila de equipamento e animações reversíveis
local function ProcessarToolDesequipado(tool: Tool)
	DebugPrint(
		"[EntradaJogador] Tool removido:",
		tool.Name,
		"- Estado atual:",
		estadoEquip,
		"- Tool alvo:",
		toolAlvo and toolAlvo.Name or "nil"
	)

	-- Se o tool removido é o alvo, atualiza alvo para nil
	if toolAlvo == tool then
		toolAlvo = nil
	end

	-- Se idle e este era o tool equipado, inicia desequip
	if estadoEquip == "idle" then
		if toolAtualEquipado == tool then
			IniciarDesequipar(tool)
		end
		return
	end

	-- Se estamos equipando
	if estadoEquip == "equipando" then
		if toolEmAnimacao == tool then
			-- Estava equipando este tool, mas foi removido - inverte para desequipar
			InverterAnimacao(-1, nil)
			return
		else
			-- Equipando outro tool, este foi removido - não afeta
			return
		end
	end

	-- Se estamos desequipando
	if estadoEquip == "desequipando" then
		if toolEmAnimacao == tool then
			-- Já está desequipando este tool - continua normalmente
			-- Se toolAlvo é nil, vai para idle. Se tem outro tool, vai equipar.
			return
		else
			-- Desequipando outro tool - não afeta diretamente
			return
		end
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

--- Processa dash
--- Calcula a direção baseado no MoveDirection do humanoid em relação ao LookVector
local function ProcessarDash()
	-- Usa a função global para calcular direção (definida em ControladorEstado)
	local direcao = "Frente"
	if _G.CalcularDirecaoDash then
		direcao = _G.CalcularDirecaoDash()
	end

	EnviarAcao("Dash", direcao)
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

	if input.KeyCode == Configuracao.TeclaDash then
		ProcessarDash()
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

-- ═══════════════════════════════════════════════════════════════════
-- DETECÇÃO DE TOOLS EQUIPADOS/DESEQUIPADOS
-- ═══════════════════════════════════════════════════════════════════

--- Detecta quando um filho é adicionado ao Character (pode ser Tool)
local function OnChildAdded(child)
	if child:IsA("Tool") then
		-- Verifica se o jogador está morto
		local char = player.Character
		if char then
			local humanoid = char:FindFirstChild("Humanoid")
			if humanoid and humanoid.Health <= 0 then
				-- Jogador está morto - desseleciona o tool automaticamente
				if child:FindFirstChild("modoAnimacao") then
					-- Se tem modoAnimacao, desequipa
					humanoid:UnequipTools()
					DebugPrint("[EntradaJogador] Tool desequipado automaticamente (jogador morto):", child.Name)
				end
				return
			end
		end

		ProcessarToolEquipado(child)
	end
end

--- Detecta quando um filho é removido do Character (pode ser Tool desequipado)
local function OnChildRemoved(child)
	if child:IsA("Tool") then
		ProcessarToolDesequipado(child)
	end
end

--- Configura listeners para o Character atual
local function ConfigurarCharacter(char)
	-- Resetar estados locais para garantir que após morrer/respawn tudo volte ao estado inicial
	estadoInput = {
		mouse1Pressionado = false,
		mouse2Pressionado = false,
		tempoMouse1 = 0,
		agachadoAtivo = false,
		correndoAtivo = false,
		ultimaDefesa = 0,
	}

	-- Resetar estado de fila/equipamento para evitar bloqueios após morrer
	estadoEquip = "idle"
	toolAtualEquipado = nil
	toolEmAnimacao = nil
	toolAlvo = nil
	ultimoIdAcao = 0

	-- Habilita backpack ao nascer
	AtualizarBackpack()

	-- Conecta eventos de adicionar/remover filhos
	char.ChildAdded:Connect(OnChildAdded)
	char.ChildRemoved:Connect(OnChildRemoved)

	-- Conecta ao evento de morte para habilitar backpack
	local humanoid = char:WaitForChild("Humanoid")
	humanoid.Died:Connect(function()
		-- Ao morrer, reseta estado de equipamento e habilita backpack
		estadoEquip = "idle"
		AtualizarBackpack()
		DebugPrint("[EntradaJogador] Jogador morreu - Backpack habilitada")
	end)

	-- Verifica se já tem algum Tool equipado
	for _, child in pairs(char:GetChildren()) do
		if child:IsA("Tool") then
			ProcessarToolEquipado(child)
			break -- Só pode ter um Tool equipado por vez
		end
	end
end

-- Conecta ao evento de respawn
player.CharacterAdded:Connect(ConfigurarCharacter)

-- Configura o Character inicial (caso o script rode depois do Character carregar)
if player.Character then
	ConfigurarCharacter(player.Character)
end

DebugPrint("[EntradaJogador] Inicializado - capturando inputs")
