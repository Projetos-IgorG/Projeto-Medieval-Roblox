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
local _ContextActionService = game:GetService("ContextActionService") -- Reservado para uso futuro

local player = Players.LocalPlayer

local Modulo_Configuracoes =
	require(ReplicatedStorage:WaitForChild("Modulos"):WaitForChild("Combate"):WaitForChild("Modulo_Configuracoes"))
local ModEquip = require(ReplicatedStorage:WaitForChild("Modulos"):WaitForChild("Modulo_Equipamento"))

-- ═══════════════════════════════════════════════════════════════════
-- REMOTE EVENTS
-- ═══════════════════════════════════════════════════════════════════

-- Referência ao GUI customizado (reservado para uso futuro)
local PlayerGui = player:WaitForChild("PlayerGui")
local _CustomInventoryGUI = PlayerGui:WaitForChild("Custom Inventory", 10) -- Aguarda até 10 segundos

local Remotos = ReplicatedStorage:WaitForChild("Remotos")
local TentarAcao = Remotos:WaitForChild("TentarAcao")
local EquipAnimacaoTerminou = Remotos:WaitForChild("EquipAnimacaoTerminou")
local AcaoRejeitada = Remotos:FindFirstChild("AcaoRejeitada")

-- Listener: se o servidor rejeitar uma ação, loga (ex: Cooldown para ataque pesado)
if AcaoRejeitada then
	AcaoRejeitada.OnClientEvent:Connect(function(acao, motivo)
		if acao == "CarregarPesado" or acao == "SoltarPesado" then
			if motivo == "Cooldown" then
				DebugPrint("[EntradaJogador] Ação rejeitada:", acao, "- motivo: Cooldown (heavy attack em cooldown)")
			else
				DebugPrint("[EntradaJogador] Ação rejeitada:", acao, "- motivo:", motivo or "?")
			end
		end
	end)
end

-- ═══════════════════════════════════════════════════════════════════
-- CONFIGURAÇÃO DE INPUTS
-- ═══════════════════════════════════════════════════════════════════

local Configuracao = {
	-- Tempo para considerar ataque pesado (segurar M1)
	TempoCarregarPesado = 0.12,

	-- Cooldowns
	CooldownDefesa = 0.5, -- Cooldown de 0.5 segundos para defesa

	-- Debounce para evitar spam de requests
	DebounceAcao = 0.05, -- Tempo mínimo entre ações iguais

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
	tempoMouse2 = 0,
	agachadoAtivo = false,
	correndoAtivo = false,
	ultimaDefesa = 0,
	carregandoPesado = false,
	ataqueLevePendente = false,
}

-- Conexões de eventos de Tool para limpeza
local toolConexoes: { RBXScriptConnection } = {}

-- ═══════════════════════════════════════════════════════════════════
-- SISTEMA DE DEBOUNCE PARA EVITAR SPAM DE REQUESTS
-- ═══════════════════════════════════════════════════════════════════

local ultimasAcoes = {} -- Tabela com o tempo da última vez que cada ação foi enviada

--- Verifica se pode enviar uma ação (debounce)
--- Retorna true se passou tempo suficiente desde a última vez
local function PodeEnviarAcao(nomeAcao: string): boolean
	local agora = tick()
	local ultimaVez = ultimasAcoes[nomeAcao] or 0
	if (agora - ultimaVez) < Configuracao.DebounceAcao then
		return false
	end
	ultimasAcoes[nomeAcao] = agora
	return true
end

--- Envia ação para o servidor COM debounce
--- Evita enviar a mesma ação múltiplas vezes em sequência rápida
local function EnviarAcaoComDebounce(acao: string, dados: any?)
	if PodeEnviarAcao(acao) then
		TentarAcao:FireServer(acao, dados)
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES GLOBAIS PARA VERIFICAÇÃO DE INPUT
-- ═══════════════════════════════════════════════════════════════════

--- Verifica se M1 está sendo pressionado (usado pelo ControladorEstado para ataque pesado)
function _G.EstaSegurandoM1()
	return estadoInput.mouse1Pressionado
end

--- Verifica se está carregando ataque pesado
function _G.EstaCarregandoPesado()
	return estadoInput.carregandoPesado
end

-- ═══════════════════════════════════════════════════════════════════
-- SISTEMA DE EQUIPAMENTO
-- ═══════════════════════════════════════════════════════════════════
--[[
    Sistema de bloqueio para gerenciar troca de tools.
    
    Regras:
    - Não é possível equipar/desequipar/trocar um Tool enquanto houver
      qualquer ação em andamento (ataque, defesa, dash, stun, etc.)
    - Não é possível equipar/desequipar/trocar um Tool enquanto a
      animação de equipar/desequipar ainda estiver tocando (mesmo após early cancel)
    - Tentativas bloqueadas são silenciosamente revertidas (re-equipa o mesmo Tool)
    
    Variáveis:
    - estadoEquip: "idle", "equipando" ou "desequipando"
    - toolAtualEquipado: Tool que está efetivamente equipado (modo ativo no servidor)
    - toolPendente: Tool aguardando para ser equipado após desequip do atual
    - revertendoTool: Flag anti-loop para quando o sistema reverte uma ação do Roblox
]]

local estadoEquip = "idle" -- "idle", "equipando", "desequipando"
local toolAtualEquipado = nil -- Tool que está efetivamente equipado (modo ativo)
local toolPendente = nil -- Tool aguardando para ser equipado após desequip
local revertendoTool = false -- Flag para evitar loops ao reverter ações do Roblox

--- Verifica se há animação de equip/desequip em andamento (compatibilidade)
function _G.EstaEmAnimacaoEquip()
	return estadoEquip ~= "idle"
end

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

--- Obtém o modo resolvido de um Tool (considerando dual-wield, escudo, etc.)
local function ObterModoDoTool(tool: Tool): string?
	if not tool then
		return nil
	end

	-- Leitura do modoAnimacao base do Tool
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
	local toolEsq = _G.ObterEquipamentoBraco and _G.ObterEquipamentoBraco("LeftArm") or nil
	local estadoEsq = ModEquip.ResolverEstadoMaoEsquerda(toolEsq)
	local categoriaDir = _G.ObterCategoriaRightArm and _G.ObterCategoriaRightArm() or nil

	local modoResolvido = ModEquip.ResolverModoAtivo(modoBase, estadoEsq, categoriaDir)
	DebugPrint("[EntradaJogador] Modo base:", modoBase, "| Estado esq:", estadoEsq, "| Resolvido:", modoResolvido)

	return modoResolvido
end

--- Obtém o Humanoid do character atual
local function ObterHumanoid(): Humanoid?
	local char = player.Character
	if char then
		return char:FindFirstChildOfClass("Humanoid")
	end
	return nil
end

--- Inicia animação de equipar um tool
local function IniciarEquipar(tool: Tool, modo: string)
	estadoEquip = "equipando"
	EnviarAcao("Equipar", modo)
	DebugPrint("[EntradaJogador] Iniciando equipar:", tool.Name, "- Modo:", modo)
end

--- Inicia animação de desequipar
local function IniciarDesequipar(tool: Tool)
	estadoEquip = "desequipando"
	EnviarAcao("Desequipar")
	DebugPrint("[EntradaJogador] Iniciando desequipar:", tool and tool.Name or "?")
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
		"Tool atual:",
		toolAtualEquipado and toolAtualEquipado.Name or "nil",
		"Tool pendente:",
		toolPendente and toolPendente.Name or "nil"
	)

	if direcaoFinal == 1 then
		-- Terminou equipando - agora temos o tool equipado
		-- Busca o Tool no character (é a referência mais confiável)
		local char = player.Character
		if char then
			local toolNoCharacter = char:FindFirstChildOfClass("Tool")
			if toolNoCharacter then
				toolAtualEquipado = toolNoCharacter
			end
		end
		toolPendente = nil
	elseif direcaoFinal == -1 then
		-- Terminou desequipando - agora não temos tool
		toolAtualEquipado = nil
	end

	estadoEquip = "idle"

	-- Notifica o servidor que a animação de equip/desequip terminou
	EquipAnimacaoTerminou:FireServer()

	-- Se terminou desequipando e há um tool pendente, equipa ele agora
	if direcaoFinal == -1 and toolPendente then
		local pendente = toolPendente
		toolPendente = nil
		local modo = ObterModoDoTool(pendente)
		if modo then
			-- Verifica se o tool pendente ainda está no character
			if pendente.Parent == player.Character then
				IniciarEquipar(pendente, modo)
			else
				DebugPrint("[EntradaJogador] Tool pendente não está mais no character, ignorando")
			end
		end
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES DE AÇÃO (COMBATE/MOVIMENTO)
-- ═══════════════════════════════════════════════════════════════════

--- Processa clique do mouse 1 (ataque)
--- Sistema de ataque leve/pesado:
--- - Ao pressionar, marca tempo e aguarda
--- - Se soltar antes de 0.2s → ataque leve
--- - Se segurar mais de 0.2s → CarregarPesado (via loop)
--- - Combo é tratado imediatamente
local function ProcessarMouse1Pressionado()
	estadoInput.mouse1Pressionado = true
	estadoInput.tempoMouse1 = tick()
	estadoInput.carregandoPesado = false
	estadoInput.ataqueLevePendente = true -- Ainda não decidiu se é leve ou pesado

	-- Verifica se há combo ativo (função exposta pelo ControladorEstado)
	-- Combo tem prioridade e é processado imediatamente
	local comboAtivo = _G.EstaComboAtivo and _G.EstaComboAtivo()
	local janelaAtiva = _G.EstaJanelaComboAtiva and _G.EstaJanelaComboAtiva()

	if comboAtivo or janelaAtiva then
		-- Combo ativo - marca para continuar
		if _G.MarcarContinuarCombo then
			local marcou = _G.MarcarContinuarCombo()
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
--- Se estava carregando pesado → SoltarPesado
--- Se ainda era pendente (< 0.2s) → Ataque leve
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
		if _G.ContinuarAtaquePesado then
			_G.ContinuarAtaquePesado()
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
	if _G.TentarCancelarAtaquePorDefesa then
		local cancelou, tipoAtaque = _G.TentarCancelarAtaquePorDefesa()
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
					if _G.CancelarCancelPendente then
						_G.CancelarCancelPendente()
					end
					estadoInput.ultimaDefesa = tick()
					-- Envia ShiftLock junto com ação de bloqueio (servidor precisa para validar)
					local shiftLockAtivo = _G.LerStatusLocal and _G.LerStatusLocal("ShiftLockOn") or false
					EnviarAcao("Bloquear", { shiftLock = shiftLockAtivo })
				else
					DebugPrint("[EntradaJogador] M2 solto após cancel - apenas cancelou, sem defesa")
					-- Resolve o cancel pendente (volta ao Idle)
					if _G.ResolverCancelPendente then
						_G.ResolverCancelPendente()
					end
				end
			end)

			return -- Não inicia defesa agora, aguarda o delay
		end
	end

	-- Se não cancelou nenhum ataque, inicia defesa normalmente
	estadoInput.ultimaDefesa = agora
	-- Envia ShiftLock junto com ação de bloqueio (servidor precisa para validar)
	local shiftLockAtivo = _G.LerStatusLocal and _G.LerStatusLocal("ShiftLockOn") or false
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

	-- Ignorar Tools de Armas/Armaduras — gerenciados pelo EquipamentoController
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
	local podeAlterar = _G.PodeAlterarTool and _G.PodeAlterarTool()
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
	local podeAlterar = _G.PodeAlterarTool and _G.PodeAlterarTool()
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
	if _G.EstaEmAnimacaoEquip and _G.EstaEmAnimacaoEquip() then
		DebugPrint("[EntradaJogador] Dash bloqueado: Animação de equipamento em andamento")
		return
	end

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

UserInputService.InputEnded:Connect(function(input, gameProcessed)
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
