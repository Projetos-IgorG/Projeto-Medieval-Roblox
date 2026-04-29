--[[
    PlayerInput.client.luau

	Local script that captures player input and sends actions to the server.
	Responsible only for:
    - Detectar inputs (mouse, teclado)
	- Enviar RemoteEvents com a acao desejada
    - Gerenciar estado de teclas pressionadas

	Does not manage animations, states, or combat logic.
]]

-- ============================================================================
-- DEBUG CONFIGURATION
-- ============================================================================
local DEBUG_ENABLED = false -- Altere para true para habilitar prints de debug

--- Prints only when debug is enabled
local function DebugPrint(...)
	if DEBUG_ENABLED then
		print(...)
	end
end

--- Warns only when debug is enabled
local function DebugWarn(...)
	if DEBUG_ENABLED then
		warn(...)
	end
end

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Client-side communication bridge (replaces _G)
local ClientBridge =
	require(ReplicatedStorage:WaitForChild("Jogador"):WaitForChild("ComunicacaoCliente"):WaitForChild("PonteCliente"))

local player = Players.LocalPlayer

local Modulo_Configuracoes =
	require(ReplicatedStorage:WaitForChild("Combate"):WaitForChild("Configuracoes"):WaitForChild("ConfigCombate"))
local ModEquip =
	require(ReplicatedStorage:WaitForChild("Equipamentos"):WaitForChild("ValidacaoEquipamentos"))

-- ============================================================================
-- REMOTE EVENTS
-- ============================================================================

local Remotos = ReplicatedStorage:WaitForChild("Remotos")
local TentarAcao = Remotos:WaitForChild("TentarAcao")
local EquipAnimacaoTerminou = Remotos:WaitForChild("EquipAnimacaoTerminou")
local AcaoRejeitada = Remotos:FindFirstChild("AcaoRejeitada")

-- Listener: logs rejected actions from the server (for example, heavy attack cooldown)
if AcaoRejeitada then
	AcaoRejeitada.OnClientEvent:Connect(function(acao, motivo)
		if acao == "CarregarPesado" or acao == "SoltarPesado" then
			if motivo == "Cooldown" then
				DebugPrint("[EntradaJogador] Acao rejeitada:", acao, "- motivo: Cooldown (heavy attack em cooldown)")
			else
				DebugPrint("[EntradaJogador] Acao rejeitada:", acao, "- motivo:", motivo or "?")
			end
		end
	end)
end

-- ============================================================================
-- CONFIGURACAO DE INPUTS
-- ============================================================================

local Configuracao = {
	-- Tempo para considerar ataque pesado (segurar M1)
	TempoCarregarPesado = 0.12,

	-- Cooldowns
	CooldownDefesa = 0.5, -- Cooldown de 0.5 segundos para defesa

	-- Debounce para evitar spam de requests
	DebounceAcao = 0.05, -- Tempo minimo entre acoes iguais

	-- Teclas
	TeclaAgachar = Enum.KeyCode.C,
	TeclaCorrer = Enum.KeyCode.LeftShift,
	TeclaQuebrarDefesa = Enum.KeyCode.G,
	TeclaDash = Enum.KeyCode.Q,
}

-- ============================================================================
-- ESTADO LOCAL DE INPUTS
-- ============================================================================

local estadoInput = {
	mouse1Pressionado = false,
	mouse2Pressionado = false,
	tempoMouse1 = 0,
	tempoMouse2 = 0,
	agachadoAtivo = false,
	correndoAtivo = false,
	ultimaDefesa = 0,
	carregandoPesado = false,
	ataqueLevePendente = false,
}

-- Conexoes de eventos de Tool para limpeza
local toolConexoes: { RBXScriptConnection } = {}

-- ============================================================================
-- SISTEMA DE DEBOUNCE PARA EVITAR SPAM DE REQUESTS
-- ============================================================================

local InputDebounce = require(ReplicatedStorage:WaitForChild("Jogador"):WaitForChild("Entrada"):WaitForChild("DebounceEntrada"))

--- Sends an action to the server with debounce protection
local function EnviarAcaoComDebounce(acao: string, dados: any?)
	InputDebounce.EnviarAcaoComDebounce(TentarAcao, acao, dados)
end

-- ============================================================================
-- FUNCOES GLOBAIS PARA VERIFICACAO DE INPUT
-- ============================================================================

--- Returns whether M1 is currently held
function ClientBridge.EstaSegurandoM1()
	return estadoInput.mouse1Pressionado
end

--- Returns whether a heavy attack is charging
function ClientBridge.EstaCarregandoPesado()
	return estadoInput.carregandoPesado
end

-- ============================================================================
-- SISTEMA DE EQUIPAMENTO
-- ============================================================================
--[[
    Sistema de bloqueio para gerenciar troca de tools.

    Regras:
		- Nao e possivel equipar, desequipar ou trocar uma Tool enquanto houver
			qualquer acao em andamento (ataque, defesa, dash, stun, etc.)
		- Nao e possivel equipar, desequipar ou trocar uma Tool enquanto a
			animacao de equipar ou desequipar ainda estiver tocando (mesmo apos early cancel)
		- Tentativas bloqueadas sao silenciosamente revertidas (re-equipa a mesma Tool)

		Variaveis:
		- estadoEquip: "idle", "equipando" ou "desequipando"
		- toolAtualEquipado: Tool efetivamente equipada (modo ativo no servidor)
		- toolPendente: Tool aguardando para ser equipada apos o desequip atual
		- revertendoTool: Flag anti-loop para quando o sistema reverte uma acao do Roblox
]]

local estadoEquip = "idle" -- "idle", "equipando", "desequipando"
local toolAtualEquipado = nil -- Tool efetivamente equipada (modo ativo)
local toolPendente = nil -- Tool aguardando para ser equipada apos o desequip
local revertendoTool = false -- Flag para evitar loops ao reverter acoes do Roblox

--- Returns whether an equip or unequip animation is in progress
function ClientBridge.EstaEmAnimacaoEquip()
	return estadoEquip ~= "idle"
end

-- ============================================================================
-- FUNCOES BASE
-- ============================================================================

--- Sends an action to the server
local function EnviarAcao(acao: string, dados: any?)
	TentarAcao:FireServer(acao, dados)
end

-- ============================================================================
-- FUNCOES AUXILIARES DE EQUIPAMENTO
-- ============================================================================

--- Returns the resolved tool mode (dual wield, shield, etc.)
local function ObterModoDoTool(tool: Tool): string?
	if not tool then
		return nil
	end

	-- Read the base animation mode from the tool
	local modoBase = nil
	local dados = tool:FindFirstChild("Dados")
	if dados and dados:IsA("Folder") then
		local modoValue = dados:FindFirstChild("modoAnimacao")
		if modoValue and modoValue:IsA("StringValue") and modoValue.Value ~= "" and modoValue.Value ~= "Base" then
			modoBase = modoValue.Value
		end
	else
		-- Fallback: procura diretamente na Tool por compatibilidade
		local modoValue = tool:FindFirstChild("modoAnimacao")
		if modoValue and modoValue:IsA("StringValue") and modoValue.Value ~= "" and modoValue.Value ~= "Base" then
			modoBase = modoValue.Value
		end
	end

	if not modoBase then
		return nil
	end

	-- Resolver modo ativo via Modulo_Equipamento (dual-wield, escudo, arco, etc.)
	local toolEsq = ClientBridge.ObterEquipamentoBraco and ClientBridge.ObterEquipamentoBraco("LeftArm") or nil
	local estadoEsq = ModEquip.ResolverEstadoMaoEsquerda(toolEsq)
	local categoriaDir = ClientBridge.ObterCategoriaRightArm and ClientBridge.ObterCategoriaRightArm() or nil

	local modoResolvido = ModEquip.ResolverModoAtivo(modoBase, estadoEsq, categoriaDir)
	DebugPrint("[EntradaJogador] Modo base:", modoBase, "| Estado esq:", estadoEsq, "| Resolvido:", modoResolvido)

	return modoResolvido
end

--- Returns the Humanoid from the current character
local function ObterHumanoid(): Humanoid?
	local char = player.Character
	if char then
		return char:FindFirstChildOfClass("Humanoid")
	end
	return nil
end

--- Starts the equip animation for a tool
local function IniciarEquipar(tool: Tool, modo: string)
	estadoEquip = "equipando"
	EnviarAcao("Equipar", modo)
	DebugPrint("[EntradaJogador] Iniciando equipar:", tool.Name, "- Modo:", modo)
end

--- Starts the unequip animation
local function IniciarDesequipar(tool: Tool)
	estadoEquip = "desequipando"
	EnviarAcao("Desequipar")
	DebugPrint("[EntradaJogador] Iniciando desequipar:", tool and tool.Name or "?")
end

-- ============================================================================
-- CALLBACKS GLOBAIS
-- ============================================================================

--- Callback fired when the equip or unequip animation finishes
--- @param direcaoFinal number 1 if equip finished, -1 if unequip finished
ClientBridge.OnEquipAnimacaoTerminou = function(direcaoFinal: number)
	DebugPrint(
		"[EntradaJogador] Animacao terminou. Direcao:",
		direcaoFinal,
		"Tool atual:",
		toolAtualEquipado and toolAtualEquipado.Name or "nil",
		"Tool pendente:",
		toolPendente and toolPendente.Name or "nil"
	)

	if direcaoFinal == 1 then
		-- Terminou equipando - agora temos o tool equipado
		-- Busca a Tool no character, que e a referencia mais confiavel
		local char = player.Character
		if char then
			local toolNoCharacter = char:FindFirstChildOfClass("Tool")
			if toolNoCharacter then
				toolAtualEquipado = toolNoCharacter
			end
		end
		toolPendente = nil
	elseif direcaoFinal == -1 then
		-- Terminou desequipando - agora nao temos tool
		toolAtualEquipado = nil
	end

	estadoEquip = "idle"

	-- Notifica o servidor que a animacao de equip ou desequip terminou
	EquipAnimacaoTerminou:FireServer()

	-- Se terminou desequipando e ha uma tool pendente, equipa agora
	if direcaoFinal == -1 and toolPendente then
		local pendente = toolPendente
		toolPendente = nil
		local modo = ObterModoDoTool(pendente)
		if modo then
			-- Verifica se a tool pendente ainda esta no character
			if pendente.Parent == player.Character then
				IniciarEquipar(pendente, modo)
			else
				DebugPrint("[EntradaJogador] Tool pendente nao esta mais no character, ignorando")
			end
		end
	end
end

-- ============================================================================
-- FUNCOES DE ACAO (COMBATE/MOVIMENTO)
-- ============================================================================

--- Processa clique do mouse 1 (ataque)
--- Sistema de ataque leve/pesado:
--- - Ao pressionar, marca tempo e aguarda
--- - Se soltar antes de 0.2s -> ataque leve
--- - Se segurar mais de 0.2s -> CarregarPesado (via loop)
--- - Combo e tratado imediatamente
local function ProcessarMouse1Pressionado()
	estadoInput.mouse1Pressionado = true
	estadoInput.tempoMouse1 = tick()
	estadoInput.carregandoPesado = false
	estadoInput.ataqueLevePendente = true -- Ainda nao decidiu se e leve ou pesado

	-- Verifica se há combo ativo (função exposta pelo ControladorEstado)
	-- Combo tem prioridade e é processado imediatamente
	local comboAtivo = ClientBridge.EstaComboAtivo and ClientBridge.EstaComboAtivo()
	local janelaAtiva = ClientBridge.EstaJanelaComboAtiva and ClientBridge.EstaJanelaComboAtiva()

	if comboAtivo or janelaAtiva then
		-- Combo ativo - marca para continuar
		if ClientBridge.MarcarContinuarCombo then
			local marcou = ClientBridge.MarcarContinuarCombo()
			if marcou then
				-- Também notifica servidor que input foi recebido
				EnviarAcao("AtacarLeveEmPe")
				estadoInput.ataqueLevePendente = false -- Combo iniciado, não enviar ataque leve depois
				return
			end
		end
	end

	-- Se está em combo, envia ataque leve imediatamente
	-- Caso contrário, aguarda para decidir se é leve ou pesado
	-- O loop ProcessarMouse1Segurar ou ProcessarMouse1Solto vai decidir
	DebugPrint("[EntradaJogador] M1 pressionado - aguardando decisão leve/pesado")
end

--- Processa soltar mouse 1
--- Se estava carregando pesado â†’ SoltarPesado
--- Se ainda era pendente (< 0.2s) â†’ Ataque leve
local function ProcessarMouse1Solto()
	if not estadoInput.mouse1Pressionado then
		return
	end

	local tempoSegurando = tick() - estadoInput.tempoMouse1
	estadoInput.mouse1Pressionado = false

	-- Se estava carregando ataque pesado, solta o pesado
	if estadoInput.carregandoPesado then
		DebugPrint("[EntradaJogador] M1 solto - SoltarPesado (carregou por", tempoSegurando, "s)")

		-- Primeiro, notifica o ControladorEstado para continuar a animação (se estava pausada)
		if ClientBridge.ContinuarAtaquePesado then
			ClientBridge.ContinuarAtaquePesado()
		end

		-- Depois envia a ação para o servidor
		EnviarAcao("SoltarPesado")
		estadoInput.carregandoPesado = false
		estadoInput.ataqueLevePendente = false
	elseif estadoInput.ataqueLevePendente then
		-- Soltou antes de 0.2s, é ataque leve
		DebugPrint("[EntradaJogador] M1 solto - AtaqueLeve (segurou", tempoSegurando, "s)")
		if estadoInput.agachadoAtivo then
			EnviarAcao("AtacarLeveAgachado")
		else
			EnviarAcao("AtacarLeveEmPe")
		end
		estadoInput.ataqueLevePendente = false
	end
end

--- Processa segurar mouse 1 (chamado em loop)
--- Após 0.2s de segurar, inicia carregamento de ataque pesado
local function ProcessarMouse1Segurar()
	if not estadoInput.mouse1Pressionado then
		return
	end

	-- Se já está carregando pesado, não precisa fazer nada
	if estadoInput.carregandoPesado then
		return
	end

	local tempoSegurando = tick() - estadoInput.tempoMouse1

	-- Após tempo mínimo, inicia carregamento pesado
	if tempoSegurando >= Configuracao.TempoCarregarPesado and estadoInput.ataqueLevePendente then
		DebugPrint("[EntradaJogador] M1 segurado por", tempoSegurando, "s - iniciando CarregarPesado")
		EnviarAcao("CarregarPesado")
		estadoInput.carregandoPesado = true
		estadoInput.ataqueLevePendente = false -- Não é mais ataque leve
	end
end

--- Processa mouse 2 (bloqueio)
local function ProcessarMouse2Pressionado()
	-- Verifica cooldown de defesa
	local agora = tick()
	if (agora - estadoInput.ultimaDefesa) < Configuracao.CooldownDefesa then
		return -- Ainda em cooldown
	end

	-- Marca que M2 está pressionado e registra o tempo
	estadoInput.mouse2Pressionado = true
	estadoInput.tempoMouse2 = agora

	-- Tenta cancelar ataque por defesa (se estiver na janela de cancelamento)
	if ClientBridge.TentarCancelarAtaquePorDefesa then
		local cancelou, tipoAtaque = ClientBridge.TentarCancelarAtaquePorDefesa()
		if cancelou then
			DebugPrint("[EntradaJogador] Ataque cancelado por defesa:", tipoAtaque)
			-- Notifica servidor sobre o cancelamento
			EnviarAcao("CancelarAtaquePorDefesa", tipoAtaque)

			-- Reseta estado de carregamento pesado se estava carregando
			if tipoAtaque == "CarregandoPesado" then
				estadoInput.carregandoPesado = false
				estadoInput.ataqueLevePendente = false
			end

			-- NÃO inicia defesa imediatamente após cancelar
			-- Aguarda um tempo para ver se o jogador continua segurando M2
			local tempoParaDefesa = Modulo_Configuracoes.ObterConfiguracao("TempoSegurandoM2ParaDefesa") or 0.15

			task.delay(tempoParaDefesa, function()
				-- Verifica se M2 ainda está pressionado após o delay
				if estadoInput.mouse2Pressionado then
					DebugPrint("[EntradaJogador] M2 ainda pressionado após cancel - iniciando defesa")
					-- Cancela o cancel pendente (não volta ao Idle, vai direto pra defesa)
					if ClientBridge.CancelarCancelPendente then
						ClientBridge.CancelarCancelPendente()
					end
					estadoInput.ultimaDefesa = tick()
					-- Envia ShiftLock junto com ação de bloqueio (servidor precisa para validar)
					local shiftLockAtivo = ClientBridge.LerStatusLocal and ClientBridge.LerStatusLocal("ShiftLockOn")
						or false
					EnviarAcao("Bloquear", { shiftLock = shiftLockAtivo })
				else
					DebugPrint("[EntradaJogador] M2 solto após cancel - apenas cancelou, sem defesa")
					-- Resolve o cancel pendente (volta ao Idle)
					if ClientBridge.ResolverCancelPendente then
						ClientBridge.ResolverCancelPendente()
					end
				end
			end)

			return -- Não inicia defesa agora, aguarda o delay
		end
	end

	-- Se não cancelou nenhum ataque, inicia defesa normalmente
	estadoInput.ultimaDefesa = agora
	-- Envia ShiftLock junto com ação de bloqueio (servidor precisa para validar)
	local shiftLockAtivo = ClientBridge.LerStatusLocal and ClientBridge.LerStatusLocal("ShiftLockOn") or false
	EnviarAcao("Bloquear", { shiftLock = shiftLockAtivo })
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
	EnviarAcaoComDebounce("Agachar")
end

--- Processa levantar
local function ProcessarAgacharSolto()
	estadoInput.agachadoAtivo = false
	EnviarAcaoComDebounce("Levantar")
end

--- Processa quebrar defesa
local function ProcessarQuebrarDefesa()
	EnviarAcaoComDebounce("QuebrarDefesa")
end

--- Processa quando um Tool é equipado (adicionado ao character)
--- Bloqueia a ação se o jogador está em qualquer estado que impeça troca
local function ProcessarToolEquipado(tool: Tool)
	-- Ignora se é o sistema revertendo (anti-loop)
	if revertendoTool then
		return
	end

	-- Ignorar Tools de Armas/Armaduras - gerenciadas pelo EquipamentoController
	local dadosFolder = tool:FindFirstChild("Dados")
	if dadosFolder then
		local tipoValue = dadosFolder:FindFirstChild("Tipo")
		if tipoValue and tipoValue:IsA("StringValue") then
			local tipo = tipoValue.Value
			if tipo == "Armas" or tipo == "Armaduras" then
				DebugPrint("[EntradaJogador] Tool de equipamento ignorado (EquipamentoController cuida):", tool.Name)
				return
			end
		end
	end

	local modoDesejado = ObterModoDoTool(tool)
	if not modoDesejado then
		DebugWarn("[EntradaJogador] Tool '", tool.Name, "' não tem modoAnimacao válido")
		return
	end

	DebugPrint("[EntradaJogador] Tool adicionado:", tool.Name, "- Estado atual:", estadoEquip)

	-- Verifica se pode alterar o Tool (sem ação em andamento e sem animação de equip)
	local podeAlterar = ClientBridge.PodeAlterarTool and ClientBridge.PodeAlterarTool()
	if not podeAlterar then
		-- BLOQUEIO: Reverte silenciosamente a ação do Roblox
		DebugPrint("[EntradaJogador] Troca bloqueada - revertendo. Tool:", tool.Name)
		local humanoid = ObterHumanoid()
		if humanoid then
			revertendoTool = true

			if toolAtualEquipado and toolAtualEquipado ~= tool then
				-- Tentou equipar outro tool enquanto estava bloqueado
				-- Remove o novo e re-equipa o antigo
				humanoid:UnequipTools()
				task.defer(function()
					if toolAtualEquipado and toolAtualEquipado.Parent then
						humanoid:EquipTool(toolAtualEquipado)
					end
					revertendoTool = false
				end)
			elseif toolAtualEquipado == tool then
				-- Re-equipou o mesmo tool (vindo de um revert de desequip)
				revertendoTool = false
			else
				-- Tentou equipar sem ter nenhum, mas está bloqueado
				humanoid:UnequipTools()
				revertendoTool = false
			end
		end
		return
	end

	-- Configura detecção nativa de Tool (substitui MouseButton1)
	-- Limpa conexões anteriores primeiro
	for _, conexao in ipairs(toolConexoes) do
		pcall(function()
			conexao:Disconnect()
		end)
	end
	table.clear(toolConexoes)

	-- Conecta tool.Activated (clique/toque)
	local conexaoActivated = tool.Activated:Connect(function()
		ProcessarMouse1Pressionado()
	end)
	table.insert(toolConexoes, conexaoActivated)

	-- Conecta tool.Deactivated (soltou clique/toque)
	local conexaoDeactivated = tool.Deactivated:Connect(function()
		ProcessarMouse1Solto()
	end)
	table.insert(toolConexoes, conexaoDeactivated)

	DebugPrint("[EntradaJogador] Configurado tool.Activated/Deactivated para:", tool.Name)

	-- Se idle, inicia ação
	if estadoEquip == "idle" then
		if toolAtualEquipado then
			-- Precisa desequipar o atual primeiro, depois equipar o novo
			toolPendente = tool
			IniciarDesequipar(toolAtualEquipado)
		else
			-- Pode equipar direto
			IniciarEquipar(tool, modoDesejado)
		end
		return
	end

	-- Se estamos desequipando, registra este tool como pendente para equipar após término
	if estadoEquip == "desequipando" then
		toolPendente = tool
		DebugPrint("[EntradaJogador] Desequipando - tool pendente atualizado para:", tool.Name)
		return
	end

	-- Se estamos equipando (não deveria chegar aqui pelo bloqueio, mas por segurança)
	DebugPrint("[EntradaJogador] Tool adicionado durante animação de equipar - ignorando")
end

--- Processa quando um Tool é desequipado (removido do character)
--- Bloqueia a ação se o jogador está em qualquer estado que impeça troca
local function ProcessarToolDesequipado(tool: Tool)
	-- Ignora se é o sistema revertendo (anti-loop)
	if revertendoTool then
		return
	end

	DebugPrint("[EntradaJogador] Tool removido:", tool.Name, "- Estado atual:", estadoEquip)

	-- Limpa conexões de tool.Activated/Deactivated
	for _, conexao in ipairs(toolConexoes) do
		pcall(function()
			conexao:Disconnect()
		end)
	end
	table.clear(toolConexoes)
	DebugPrint("[EntradaJogador] Limpas conexões tool.Activated/Deactivated para:", tool.Name)

	-- Verifica se pode alterar o Tool
	local podeAlterar = ClientBridge.PodeAlterarTool and ClientBridge.PodeAlterarTool()
	if not podeAlterar then
		-- BLOQUEIO: Reverte silenciosamente - re-equipa o tool que tentou tirar
		DebugPrint("[EntradaJogador] Desequip bloqueado - revertendo. Tool:", tool.Name)
		local humanoid = ObterHumanoid()
		if humanoid and tool.Parent then
			revertendoTool = true
			humanoid:EquipTool(tool)
			revertendoTool = false
		end
		return
	end

	-- Se idle e este era o tool equipado, inicia desequip
	if estadoEquip == "idle" then
		if toolAtualEquipado == tool then
			IniciarDesequipar(tool)
		end
		return
	end

	-- Se estamos em animação (não deveria chegar aqui pelo bloqueio, mas por segurança)
	DebugPrint("[EntradaJogador] Tool removido durante animação - ignorando (não deveria ocorrer)")
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
	-- Bloqueia dash se não pode alterar tool (animação de equip em andamento)
	if ClientBridge.EstaEmAnimacaoEquip and ClientBridge.EstaEmAnimacaoEquip() then
		DebugPrint("[EntradaJogador] Dash bloqueado: Animação de equipamento em andamento")
		return
	end

	-- Usa a função global para calcular direção (definida em ControladorEstado)
	local direcao = "Frente"
	if ClientBridge.CalcularDirecaoDash then
		direcao = ClientBridge.CalcularDirecaoDash()
	end

	EnviarAcao("Dash", direcao)
end

-- ----------------------------------------------------------------------------
-- LISTENERS DE INPUT
-- ----------------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	-- MouseButton1 agora é detectado via tool.Activated (compatibilidade cross-platform)
	-- Mantém MouseButton2 para bloqueio (sem equivalente nativo)
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
			-- Corrida é tratada localmente pelo ControladorEstado via isShiftHeld
		end
		-- NÃO envia para servidor - corrida é 100% client-side
		-- O ControladorEstado detecta isShiftHeld e ajusta animação/velocidade localmente
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

UserInputService.InputEnded:Connect(function(input, _gameProcessed)
	-- MouseButton1 agora é detectado via tool.Deactivated (compatibilidade cross-platform)
	-- Mantém MouseButton2 para bloqueio (sem equivalente nativo)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		ProcessarMouse2Solto()
		return
	end

	-- Teclado
	if input.KeyCode == Configuracao.TeclaCorrer then
		estadoInput.correndoAtivo = false
		-- NÃO envia para servidor - corrida é 100% client-side
		-- O ControladorEstado detecta isShiftHeld e ajusta animação/velocidade localmente
		return
	end

	if input.KeyCode == Configuracao.TeclaAgachar then
		ProcessarAgacharSolto()
		return
	end
end)

-- ----------------------------------------------------------------------------
-- LOOP PARA VERIFICAR SEGURAR MOUSE
-- ----------------------------------------------------------------------------

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

-- ----------------------------------------------------------------------------
-- INICIALIZAÇÃO
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- DETECÇÃO DE TOOLS EQUIPADOS/DESEQUIPADOS
-- ----------------------------------------------------------------------------

--- Detecta quando um filho é adicionado ao Character (pode ser Tool)
local function OnChildAdded(child)
	if child:IsA("Tool") then
		-- Verifica se o jogador está morto
		local char = player.Character
		if char then
			local humanoid = char:FindFirstChild("Humanoid")
			if humanoid and humanoid.Health <= 0 then
				-- Jogador está morto - desseleciona o tool automaticamente
				-- Verifica novo padrão: Dados/modoAnimacao
				local dados = child:FindFirstChild("Dados")
				local temModo = false
				if dados and dados:IsA("Folder") then
					temModo = dados:FindFirstChild("modoAnimacao") ~= nil
				else
					temModo = child:FindFirstChild("modoAnimacao") ~= nil
				end
				if temModo then
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
		-- Sistema de ataque pesado
		carregandoPesado = false,
		ataqueLevePendente = false,
	}

	-- Resetar estado de equipamento para evitar bloqueios após morrer
	estadoEquip = "idle"
	toolAtualEquipado = nil
	toolPendente = nil
	revertendoTool = false

	-- Conecta eventos de adicionar/remover filhos
	char.ChildAdded:Connect(OnChildAdded)
	char.ChildRemoved:Connect(OnChildRemoved)

	-- Conecta ao evento de morte para resetar estado
	local humanoid = char:WaitForChild("Humanoid")
	humanoid.Died:Connect(function()
		-- Ao morrer, reseta estado de equipamento
		estadoEquip = "idle"
		toolPendente = nil
		revertendoTool = false
		DebugPrint("[EntradaJogador] Jogador morreu - Estado resetado")
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
