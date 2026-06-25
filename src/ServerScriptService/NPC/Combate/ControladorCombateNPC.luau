--!strict

--[[
	Script: ControladorCombateNPC.luau
	Caminho: src/ServerScriptService/NPC/Combate
	Responsabilidade: Camada de combate de NPCs no servidor.
	    Delega TODAS as acoes ao CombateServidor usando o MESMO pipeline do
	    player: ProcessarAtacarEmPe, ProcessarBloquear, ProcessarPararBloqueio,
	    ProcessarEquipar, ProcessarDesequipar. Sincroniza atributos NPC_Acao/
	    NPC_Estado/NPC_AcaoTick via hooks nos eventos da MaquinaDeEstados.
	    Recebe reportes de hit do CLIENTE do alvo (RemoteEvent NPC_HitReport),
	    valida (NPC realmente atacando, alvo proximo, dedup por swing) e
	    delega o dano canonico ao CombateServidor._ProcessarHit.
	Uso: ModuleScript; require e use a mesma API publica:
	    (Iniciar/EquiparArma/DesequiparArma/Atacar/PararAtaque/
	     Bloquear/PararBloqueio/TocarLocomocao/EstaArmaPronta/EstaAtacando/
	     EstaEquipando/EstaBloqueando/ObterAlcanceArmaEquipada/Destruir).
	Funcoes principais: Iniciar, EquiparArma, DesequiparArma, Atacar,
	    Bloquear, PararBloqueio, TocarLocomocao, PararAtaque, Destruir
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Combate = ReplicatedStorage:WaitForChild("Combate")
local Timings = require(Combate:WaitForChild("Configuracoes"):WaitForChild("TimingsAtaqueNPC"))

local TiposNPC = require(ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC"):WaitForChild("Tipos"))

local Remotos = ReplicatedStorage:WaitForChild("Remotos")
local NPC_HitReport: RemoteEvent = Remotos:WaitForChild("NPC_HitReport") :: RemoteEvent

-- =============================================================================
-- Acesso lazy ao CombateServidor (evita ciclo de require na inicializacao).
-- =============================================================================

local CombateServidor: any = nil
local function obterCS(): any?
	if CombateServidor then
		return CombateServidor
	end
	local pasta = ServerScriptService:FindFirstChild("Combate")
	pasta = pasta and pasta:FindFirstChild("Servidor")
	local mod = pasta and pasta:FindFirstChild("CombateServidor")
	if mod and mod:IsA("ModuleScript") then
		local ok, m = pcall(require, mod)
		if ok then
			CombateServidor = m
			return m
		end
	end
	return nil
end

local ATRIBUTOS_ARMA_NPC = {
	"NPC_ArmaEquipadaId",
	"NPC_ArmaVisualId",
	"NPC_ArmaDanoId",
	"NPC_ArmaId",
}

local TEMPLATE_ARMA_PADRAO: Tool? = nil

-- Tolerancia (segundos) entre acaoTick reportado e armazenado (clock skew).
local TOLERANCIA_TICK = 0.4
-- Tolerancia (studs) na validacao de distancia do alvo no momento do hit.
local TOLERANCIA_DISTANCIA = 4

-- =============================================================================
-- Estado por NPC.
-- =============================================================================

type Estado = {
	modelo: Model,
	humanoide: Humanoid,
	armaEquipada: Tool?,
	alcanceArma: number?,
	danoLeve: number,
	armaPronta: boolean,
	atacando: boolean,
	equipando: boolean,
	desequipando: boolean?,
	indiceCombo: number,
	ultimoSwingFim: number,
	comboToken: number,
	equipToken: number,
	desequipToken: number,
	-- Tick (os.clock) do swing atual; cliente reporta o mesmo valor para validacao.
	acaoTick: number,
	-- Janela em que hits sao aceitos para o swing atual: [acaoTick + AtrasoHit, acaoTick + Duracao].
	swingHitInicio: number,
	swingHitFim: number,
	-- Dedup por swing: alvo => true se ja recebeu dano neste swing.
	jaAtingidos: { [Model]: boolean },
	verificarAlvo: (() -> boolean)?,
	timings: typeof(Timings.Punhos),
	destruido: boolean,
	tipoAtaqueAtual: string?,
	disconnectHooks: { () -> () }?,
	historicoAcoes: {
		[number]: {
			tipoAtaque: string,
			indiceCombo: number,
			swingHitFim: number,
			jaAtingidos: { [Model]: boolean },
		},
	},
}

local estados: { [Model]: Estado } = {}

local Mod = {}

-- =============================================================================
-- Helpers de leitura da arma equipada.
-- =============================================================================

local function obterPastaArmasEquipadas(): Instance?
	local equipamentos = ReplicatedStorage:FindFirstChild("Equipamentos")
	local modelos = equipamentos and equipamentos:FindFirstChild("Modelos")
	return modelos and modelos:FindFirstChild("ArmasEquipadas")
end

local function obterDadosTool(tool: Tool?): Folder?
	local dados = tool and tool:FindFirstChild("Dados")
	if dados and dados:IsA("Folder") then
		return dados
	end
	return nil
end

local function lerStringDados(tool: Tool?, nome: string): string?
	local dados = obterDadosTool(tool)
	local value = dados and dados:FindFirstChild(nome)
	if value and value:IsA("StringValue") and value.Value ~= "" then
		return value.Value
	end
	return nil
end

local function lerNumberDados(tool: Tool?, nome: string): number?
	local dados = obterDadosTool(tool)
	local value = dados and dados:FindFirstChild(nome)
	if value and value:IsA("NumberValue") and value.Value > 0 then
		return value.Value
	end
	return nil
end

local function ehArmaEquipada(tool: Tool?): boolean
	return lerStringDados(tool, "Tipo") == "ArmasEquipadas"
end

local function obterTemplateArmaPadrao(): Tool?
	if TEMPLATE_ARMA_PADRAO and TEMPLATE_ARMA_PADRAO.Parent then
		return TEMPLATE_ARMA_PADRAO
	end
	local pasta = obterPastaArmasEquipadas()
	local tool = pasta and pasta:FindFirstChild("punhos")
	if tool and tool:IsA("Tool") then
		TEMPLATE_ARMA_PADRAO = tool
		return tool
	end
	return nil
end

local function encontrarTemplateArmaPorId(id: string?): Tool?
	if not id or id == "" then
		return nil
	end
	local pasta = obterPastaArmasEquipadas()
	if not pasta then
		return nil
	end
	local direto = pasta:FindFirstChild(id)
	if direto and direto:IsA("Tool") then
		return direto
	end
	local equipada = pasta:FindFirstChild(id .. "-equipada")
	if equipada and equipada:IsA("Tool") then
		return equipada
	end
	for _, child in pasta:GetChildren() do
		if child:IsA("Tool") then
			local dadosId = lerStringDados(child, "Id")
			if dadosId == id then
				return child
			end
		end
	end
	return nil
end

local function encontrarToolArmaNoModelo(modelo: Model): Tool?
	for _, child in modelo:GetChildren() do
		if child:IsA("Tool") and ehArmaEquipada(child) then
			return child
		end
	end
	return nil
end

local function encontrarToolArmaPorAtributo(modelo: Model): Tool?
	for _, nomeAtributo in ATRIBUTOS_ARMA_NPC do
		local valor = modelo:GetAttribute(nomeAtributo)
		if typeof(valor) == "string" then
			local tool = encontrarTemplateArmaPorId(valor)
			if tool then
				return tool
			end
		end
	end
	return nil
end

local function registrarArmaEquipada(s: Estado, tool: Tool?): Tool?
	if not tool then
		return nil
	end
	s.armaEquipada = tool
	s.alcanceArma = lerNumberDados(tool, "Alcance")
	s.danoLeve = lerNumberDados(tool, "Dano") or s.danoLeve
	local modo = lerStringDados(tool, "modoAnimacao")
	s.timings = Timings.ObterPorArma(modo)
	return tool
end

local function resolverArmaEquipada(s: Estado): Tool?
	if s.armaEquipada then
		return s.armaEquipada
	end
	local toolNoModelo = encontrarToolArmaNoModelo(s.modelo)
	if toolNoModelo then
		return registrarArmaEquipada(s, toolNoModelo)
	end
	local toolPorAtributo = encontrarToolArmaPorAtributo(s.modelo)
	if toolPorAtributo then
		return registrarArmaEquipada(s, toolPorAtributo)
	end
	return registrarArmaEquipada(s, obterTemplateArmaPadrao())
end

-- =============================================================================
-- Atributos replicados (canal cliente <- servidor).
-- =============================================================================

local function setAcao(s: Estado, acao: string, indice: number?)
	if s.destruido then
		return
	end
	s.acaoTick = os.clock()
	s.modelo:SetAttribute(TiposNPC.Chaves.Acao, acao)
	if indice ~= nil then
		s.modelo:SetAttribute(TiposNPC.Chaves.AcaoIndice, indice)
	end
	s.modelo:SetAttribute(TiposNPC.Chaves.AcaoTick, s.acaoTick)
end

local function setLocomocao(s: Estado, nome: string, velocidade: number?)
	if s.destruido then
		return
	end
	s.modelo:SetAttribute(TiposNPC.Chaves.LocomocaoNome, nome)
	s.modelo:SetAttribute(TiposNPC.Chaves.LocomocaoVelocidade, velocidade or 1)
end

local function setArmaPronta(s: Estado, pronta: boolean)
	if s.destruido then
		return
	end
	s.modelo:SetAttribute(TiposNPC.Chaves.ArmaPronta, pronta)
end

-- =============================================================================
-- API publica.
-- =============================================================================

-- =============================================================================
-- Sincronizacao de atributos NPC via eventos da MaquinaDeEstados.
-- Sempre que a maquina muda estadoAcao, estadoMov ou modo, atualiza os
-- atributos do modelo para que a View do NPC no cliente reaja.
-- =============================================================================

local function mapearEstadoAcaoParaNPCEstado(estadoAcao: string, dados: any): string?
	if estadoAcao == "Aparado" then
		return TiposNPC.Estado.Aparado
	elseif estadoAcao == "Aparando" then
		return TiposNPC.Estado.Aparando
	elseif estadoAcao == "Stunado" then
		return TiposNPC.Estado.Stunado
	elseif estadoAcao == "DefesaQuebrada" then
		return TiposNPC.Estado.DefesaQuebrada
	elseif estadoAcao == "Defendendo" then
		return TiposNPC.Estado.Defendendo
	elseif estadoAcao == "Atacando" then
		return TiposNPC.Estado.Atacando
	end
	-- Para "Nenhuma", verificar se esta bloqueando (transicao parcial).
	if dados and dados.bloqueando then
		return TiposNPC.Estado.Defendendo
	end
	return nil -- usa estadoMov
end

local function mapearEstadoAcaoParaNPCAcao(estadoAcao: string): string
	if estadoAcao == "Equipando" then
		return TiposNPC.Acao.Equipar
	elseif estadoAcao == "Desequipando" then
		return TiposNPC.Acao.Desequipar
	elseif estadoAcao == "Atacando" then
		return TiposNPC.Acao.Ataque
	end
	return TiposNPC.Acao.Idle
end

local function sincronizarAtributosDaMaquina(s: Estado, maquina: any)
	if s.destruido then
		return
	end
	local dados = maquina:ObterDados()
	if not dados then
		return
	end

	-- NPC_Acao e NPC_AcaoTick
	local novaAcao = mapearEstadoAcaoParaNPCAcao(dados.estadoAcao)
	local indiceCombo = maquina:ObterIndiceCombo()
	setAcao(s, novaAcao, indiceCombo)

	-- NPC_Estado (prioridade: estadoAcao > bloqueando > estadoMov)
	local npcEstado = mapearEstadoAcaoParaNPCEstado(dados.estadoAcao, dados)
	if not npcEstado then
		-- Fallback para estadoMov
		local mov = dados.estadoMov
		if mov == "Correndo" then
			npcEstado = TiposNPC.Estado.Correndo
		elseif mov == "Andando" then
			npcEstado = TiposNPC.Estado.Andando
		else
			npcEstado = TiposNPC.Estado.Idle
		end
	end
	if s.modelo:GetAttribute(TiposNPC.Chaves.Estado) ~= npcEstado then
		s.modelo:SetAttribute(TiposNPC.Chaves.Estado, npcEstado)
	end

	-- NPC_ArmaPronta: atualiza quando transicao de equip/desequip termina
	local acaoAtual = dados.estadoAcao
	if acaoAtual ~= "Equipando" and acaoAtual ~= "Desequipando" then
		if s.equipando and acaoAtual == "Nenhuma" then
			if s.desequipando then
				s.armaPronta = false
				s.desequipando = nil
				s.armaEquipada = nil -- Limpa cache
				setArmaPronta(s, false)
			else
				s.armaPronta = true
				setArmaPronta(s, true)
			end
			s.equipando = false
		end
	end
end

local function instalarHooksMaquina(s: Estado, maquina: any)
	local function onMudar()
		sincronizarAtributosDaMaquina(s, maquina)
	end

	local disconnects: { () -> () } = {}
	if maquina.AoMudarEstadoAcao then
		local disc = maquina:AoMudarEstadoAcao(function(_novo: string, _anterior: string)
			onMudar()
		end)
		if typeof(disc) == "function" then
			table.insert(disconnects, disc)
		end
	end
	if maquina.AoMudarEstadoMov then
		local disc = maquina:AoMudarEstadoMov(function(_novo: string, _anterior: string)
			onMudar()
		end)
		if typeof(disc) == "function" then
			table.insert(disconnects, disc)
		end
	end
	if maquina.AoMudarModo then
		local disc = maquina:AoMudarModo(function(_novo: string, _anterior: string)
			onMudar()
		end)
		if typeof(disc) == "function" then
			table.insert(disconnects, disc)
		end
	end
	s.disconnectHooks = disconnects
end

function Mod.Iniciar(modelo: Model): Estado?
	if estados[modelo] then
		return estados[modelo]
	end
	local hum = modelo:FindFirstChildOfClass("Humanoid")
	if not hum then
		return nil
	end

	local s: Estado = {
		modelo = modelo,
		humanoide = hum,
		armaEquipada = nil,
		alcanceArma = nil,
		danoLeve = (modelo:GetAttribute("DanoLeve") :: number?) or 8,
		armaPronta = false,
		atacando = false,
		equipando = false,
		indiceCombo = 0,
		ultimoSwingFim = 0,
		comboToken = 0,
		equipToken = 0,
		desequipToken = 0,
		acaoTick = 0,
		swingHitInicio = 0,
		swingHitFim = 0,
		jaAtingidos = {},
		historicoAcoes = {},
		verificarAlvo = nil,
		timings = Timings.Punhos,
		destruido = false,
		tipoAtaqueAtual = nil,
	}
	estados[modelo] = s

	resolverArmaEquipada(s)

	setArmaPronta(s, false)
	setAcao(s, TiposNPC.Acao.Idle, 0)
	setLocomocao(s, "Idle", 1)

	-- Instalar hooks na maquina de estados para sincronizar atributos NPC.
	local cs = obterCS()
	if cs and cs.ObterMaquina then
		local ok, maquina = pcall(cs.ObterMaquina, modelo)
		if ok and maquina then
			instalarHooksMaquina(s, maquina)
		end
	end

	return s
end

function Mod.EstaArmaPronta(modelo: Model): boolean
	local s = estados[modelo]
	return (s ~= nil and s.armaPronta) == true
end

function Mod.ObterAlcanceArmaEquipada(modelo: Model): number?
	local s = estados[modelo]
	if not s then
		return nil
	end
	resolverArmaEquipada(s)
	return s.alcanceArma
end

function Mod.EstaAtacando(modelo: Model): boolean
	local s = estados[modelo]
	return s ~= nil and s.atacando
end

function Mod.EstaEquipando(modelo: Model): boolean
	local s = estados[modelo]
	return s ~= nil and s.equipando
end

function Mod.EquiparArma(modelo: Model)
	local s = estados[modelo] or Mod.Iniciar(modelo)
	if not s then
		return
	end
	if s.armaPronta or s.equipando then
		return
	end

	s.armaEquipada = nil -- Força nova resolução
	resolverArmaEquipada(s)

	local idArma = s.armaEquipada and lerStringDados(s.armaEquipada, "Id")
	if idArma then
		s.modelo:SetAttribute(TiposNPC.Chaves.ArmaEquipadaId, idArma)
	end

	local modo = lerStringDados(s.armaEquipada, "modoAnimacao") or "Punhos"
	local cs = obterCS()
	if not cs then
		return
	end

	s.equipando = true
	s.equipToken += 1

	-- Delega ao pipeline do player. A conclusao (CompletarAcao) sera chamada
	-- quando o cliente enviar EquipAnimacaoTerminou via RemoteEvent.
	local ok = pcall(cs.ProcessarEquipar, modelo, modo)
	if not ok then
		s.equipando = false
	end
end

function Mod.DesequiparArma(modelo: Model)
	local s = estados[modelo]
	if not s then
		return
	end
	if not s.armaPronta or s.equipando then
		return
	end

	if s.atacando then
		s.comboToken += 1
		s.atacando = false
		s.indiceCombo = 0
		s.swingHitFim = 0
		table.clear(s.jaAtingidos)
		s.modelo:SetAttribute("NPC_AcertouCombo", false)
		local cs = obterCS()
		if cs and cs.ProcessarComboTerminou then
			pcall(cs.ProcessarComboTerminou, s.modelo)
		end
	end

	s.equipando = true
	s.desequipando = true
	s.desequipToken += 1

	local cs = obterCS()
	if not cs then
		s.equipando = false
		return
	end

	-- Delega ao pipeline do player. A conclusao sera chamada quando o
	-- cliente enviar EquipAnimacaoTerminou via RemoteEvent.
	local ok = pcall(cs.ProcessarDesequipar, modelo)
	if not ok then
		s.equipando = false
		s.armaPronta = false
		setArmaPronta(s, false)
	end
end

function Mod.TocarLocomocao(modelo: Model, nome: string, velocidadeAnimacao: number?)
	local s = estados[modelo]
	if not s then
		return
	end
	if s.equipando then
		return
	end
	setLocomocao(s, nome, velocidadeAnimacao)
end

local iniciarSwing: (s: Estado, cs: any, _maquina: any, token: number) -> ()
local finalizarSwing: (s: Estado, token: number) -> ()

function finalizarSwing(s: Estado, token: number)
	if s.destruido or s.comboToken ~= token then
		return
	end

	local cs = obterCS()
	local maquina = cs and cs.ObterMaquina(s.modelo)
	local continuar = false
	if maquina and maquina.dados and maquina.dados.continuarCombo then
		continuar = true
		maquina.dados.continuarCombo = false
	end

	if continuar and s.indiceCombo < 4 then
		s.indiceCombo = s.indiceCombo + 1
		s.comboToken += 1
		local novoToken = s.comboToken

		if maquina.AvancarGolpeCombo then
			pcall(maquina.AvancarGolpeCombo, maquina, s.indiceCombo)
		end

		task.defer(function()
			if s.destruido or s.comboToken ~= novoToken then
				return
			end
			iniciarSwing(s, cs, maquina, novoToken)
		end)
		return
	end

	s.atacando = false
	s.ultimoSwingFim = os.clock()
	-- Reseta combo se nao houver continuacao dentro da janela.
	local janela = s.timings.Ataque.ContinuacaoCombo
	local indiceNoFim = s.indiceCombo
	task.delay(janela, function()
		if s.destruido or s.comboToken ~= token then
			return
		end
		if s.atacando then
			return
		end
		if s.indiceCombo == indiceNoFim then
			s.indiceCombo = 0
			s.modelo:SetAttribute("NPC_AcertouCombo", false)
			if cs and cs.ProcessarComboTerminou then
				pcall(cs.ProcessarComboTerminou, s.modelo)
			end
			if not s.atacando and not s.equipando then
				setAcao(s, TiposNPC.Acao.Idle, 0)
			end
		end
	end)
end

function iniciarSwing(s: Estado, cs: any, _maquina: any, token: number)
	if s.destruido or s.comboToken ~= token then
		return
	end

	local t = s.timings.Ataque
	setAcao(s, TiposNPC.Acao.Ataque, s.indiceCombo)
	s.swingHitInicio = s.acaoTick + t.AtrasoHit
	s.swingHitFim = s.acaoTick + t.Duracao
	table.clear(s.jaAtingidos)

	local tipoAtaque = "Ataque"
	if s.indiceCombo >= 4 then
		tipoAtaque = "AtaqueFinal"
	end
	s.tipoAtaqueAtual = tipoAtaque

	-- Registrar no histórico de ações para validação de hits tardios de jogadores lagados
	s.historicoAcoes[s.acaoTick] = {
		tipoAtaque = tipoAtaque,
		indiceCombo = s.indiceCombo,
		swingHitFim = s.swingHitFim,
		jaAtingidos = {},
	}

	-- Limpar registros de histórico com mais de 5 segundos
	local agora = os.clock()
	for tKey, _ in s.historicoAcoes do
		if agora - tKey > 5 then
			s.historicoAcoes[tKey] = nil
		end
	end

	-- ProcessarComboHitbox ja chama _AplicarImpulsoAtacante internamente.
	-- Nao chamar aqui para evitar impulso duplicado.
	if cs.ProcessarComboHitbox then
		pcall(cs.ProcessarComboHitbox, s.modelo, { indice = s.indiceCombo })
	end

	-- O swing completa naturalmente; a hitbox do cliente do alvo eh quem
	-- determina se o golpe acertou. Nao cancelamos antecipadamente.

	task.delay(t.Duracao, function()
		finalizarSwing(s, token)
	end)
end

function Mod.Atacar(modelo: Model, verificarAlvo: (() -> boolean)?): boolean
	local s = estados[modelo]
	if not s then
		return false
	end

	local agora = os.clock()
	local cs = obterCS()
	if not cs then
		return false
	end

	local maquina = cs.ObterMaquina(modelo)
	if not maquina then
		return false
	end

	if maquina.dados then
		maquina.dados.ultimoComboTerminou = 0
	end

	if s.atacando then
		s.verificarAlvo = verificarAlvo
		local duracao = s.timings.Ataque.Duracao
		if agora >= s.swingHitInicio - 0.05 and agora <= s.acaoTick + duracao then
			maquina.dados.continuarCombo = true
			return true
		end
		return false
	end

	if not s.armaPronta or s.equipando then
		return false
	end

	s.verificarAlvo = verificarAlvo

	if maquina.DefinirModo then
		maquina:DefinirModo("Punhos")
	end

	-- Delega ao pipeline do player: valida estado, toca animacao, aplica
	-- impulso e seta WalkSpeed automaticamente.
	local ok, tipoAtaque = cs.ProcessarAtacarEmPe(modelo)
	if not ok then
		return false
	end

	s.indiceCombo = 1
	s.tipoAtaqueAtual = tipoAtaque
	s.atacando = true
	s.comboToken += 1
	local token = s.comboToken

	iniciarSwing(s, cs, maquina, token)

	return true
end

function Mod.PararAtaque(modelo: Model)
	local s = estados[modelo]
	if not s then
		return
	end
	s.comboToken += 1
	s.atacando = false
	s.indiceCombo = 0
	s.swingHitFim = 0
	s.verificarAlvo = nil
	table.clear(s.jaAtingidos)
	s.modelo:SetAttribute("NPC_AcertouCombo", false)
	local cs = obterCS()
	if cs and cs.ProcessarComboTerminou then
		pcall(cs.ProcessarComboTerminou, s.modelo)
	end
	if not s.equipando then
		setAcao(s, TiposNPC.Acao.Idle, 0)
	end
end

function Mod.Bloquear(modelo: Model): boolean
	local s = estados[modelo]
	if not s then
		return false
	end
	if s.atacando or s.equipando or not s.armaPronta then
		return false
	end

	local cs = obterCS()
	if not cs then
		return false
	end

	-- Delega ao pipeline do player. O `true` simula ShiftLock ativo
	-- (obrigatorio para a MaquinaDeEstados permitir bloqueio).
	local ok, _motivo = cs.ProcessarBloquear(modelo, true)
	return ok == true
end

function Mod.PararBloqueio(modelo: Model): boolean
	local s = estados[modelo]
	if not s then
		return false
	end

	local cs = obterCS()
	if not cs then
		return false
	end

	local ok, _motivo = cs.ProcessarPararBloqueio(modelo)
	return ok == true
end

function Mod.EstaBloqueando(modelo: Model): boolean
	local cs = obterCS()
	if not cs then
		return false
	end
	local maquina = cs.ObterMaquina(modelo)
	if not maquina then
		return false
	end
	return maquina:EstaBloqueando()
end

function Mod.Destruir(modelo: Model)
	local s = estados[modelo]
	if not s then
		return
	end
	s.destruido = true
	s.comboToken += 1
	s.equipToken += 1
	s.desequipToken += 1
	s.atacando = false
	s.equipando = false
	s.desequipando = nil
	s.armaPronta = false
	s.swingHitFim = 0
	table.clear(s.jaAtingidos)

	-- Limpa hooks de eventos para evitar leaks de memória (closures pendentes)
	if s.disconnectHooks then
		for _, disc in s.disconnectHooks do
			disc()
		end
		s.disconnectHooks = nil
	end

	-- Remove a máquina de estados cacheada no servidor
	local cs = obterCS()
	if cs and cs.RemoverMaquina then
		pcall(cs.RemoverMaquina, modelo)
	end

	estados[modelo] = nil
end

-- =============================================================================
-- Recepcao do reporte de hit do cliente do alvo.
-- Cliente envia (npcModel, alvoModel, acaoTickReportado).
-- Servidor valida tudo e chama _ProcessarHit canonico.
-- =============================================================================

local function distanciaModelos(a: Model, b: Model): number
	local pa = a.PrimaryPart or a:FindFirstChild("HumanoidRootPart") :: BasePart?
	local pb = b.PrimaryPart or b:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not pa or not pb then
		return math.huge
	end
	return (pa.Position - pb.Position).Magnitude
end

local function processarReporteHit(
	jogador: Player,
	npcModel: Model,
	alvoModel: Model,
	acaoTickReportado: number,
	parteAtingida: string?,
	npcCFrame: CFrame?,
	alvoCFrame: CFrame?
)
	-- Tipos basicos.
	if typeof(npcModel) ~= "Instance" or not npcModel:IsA("Model") then
		return
	end
	if typeof(alvoModel) ~= "Instance" or not alvoModel:IsA("Model") then
		return
	end
	if typeof(acaoTickReportado) ~= "number" then
		return
	end

	local s = estados[npcModel]
	if not s or s.destruido then
		return
	end

	-- Cliente so pode reportar hit no proprio personagem (anti-cheat: outro
	-- player nao pode "pedir" dano em alguem).
	if alvoModel ~= jogador.Character then
		return
	end

	-- Verificar se o ataque do NPC foi interrompido por um stun/parry/hit
	local cs = obterCS()
	if cs and cs.ObterMaquina then
		local ok, maquina = pcall(cs.ObterMaquina, npcModel)
		if ok and maquina and maquina.dados then
			local ultimoAtaque = maquina.dados.ultimoAtaque or 0
			local ultimoStun = maquina.dados.ultimoStunTimestamp or 0
			if ultimoStun > ultimoAtaque then
				warn(
					string.format(
						"[NPC Combate Server] Rejecting hit on player: NPC attack was interrupted by stun (stun=%.3f, ataque=%.3f)",
						ultimoStun,
						ultimoAtaque
					)
				)
				return
			end
		end
	end

	-- Buscar dados da ação correspondente ao tick reportado no histórico
	local acaoDados = s.historicoAcoes[acaoTickReportado]
	if not acaoDados then
		-- Fallback para o swing atual se estiver muito próximo (tolerância tick)
		if math.abs((s.acaoTick or 0) - acaoTickReportado) <= TOLERANCIA_TICK then
			acaoDados = {
				tipoAtaque = s.tipoAtaqueAtual or "Ataque",
				indiceCombo = s.indiceCombo,
				swingHitFim = s.swingHitFim,
				jaAtingidos = s.jaAtingidos,
			}
		else
			warn(
				"[NPC Combate Server] Rejecting hit: tick mismatch (no history and too far from current swing). diff =",
				math.abs((s.acaoTick or 0) - acaoTickReportado)
			)
			return
		end
	end

	-- Janela temporal do swing (do inicio efetivo da hitbox ate o fim do golpe), compensando RTT.
	local agora = os.clock()
	if acaoDados.swingHitFim <= 0 then
		warn("[NPC Combate Server] Rejecting hit: swingHitFim <= 0")
		return
	end

	local rttVal = jogador:GetAttribute("RTT")
	local rtt = math.clamp(if typeof(rttVal) == "number" then rttVal else 0.0, 0, 1.5)
	local limiteMaximo = acaoDados.swingHitFim + 0.80 + rtt
	local limiteMinimo = acaoTickReportado - 0.05
	if agora < limiteMinimo or agora > limiteMaximo then
		warn(
			string.format(
				"[NPC Combate Server] Rejecting hit: timing invalid. agora=%.4f, min=%.4f, max=%.4f",
				agora,
				limiteMinimo,
				limiteMaximo
			)
		)
		return
	end

	-- Debug por swing.
	if acaoDados.jaAtingidos[alvoModel] then
		warn("[NPC Combate Server] Rejecting hit: already hit in this swing")
		return
	end

	-- Validacao de alvo vivo + distancia plausivel, compensando RTT.
	local hum = alvoModel:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		warn("[NPC Combate Server] Rejecting hit: target dead or missing humanoid")
		return
	end
	local alcance = s.alcanceArma or 6
	local d = distanciaModelos(s.modelo, alvoModel)
	local compensacaoDistancia = math.clamp(rtt * 16, 0, 12)
	local limiteDistancia = alcance + TOLERANCIA_DISTANCIA + compensacaoDistancia
	if d > limiteDistancia then
		warn(
			string.format(
				"[NPC Combate Server] Rejecting hit: distance invalid. d=%.2f, limit=%.2f",
				d,
				limiteDistancia
			)
		)
		return
	end

	acaoDados.jaAtingidos[alvoModel] = true
	s.modelo:SetAttribute("NPC_AcertouCombo", true)

	if cs and cs._ProcessarHit then
		pcall(
			cs._ProcessarHit,
			s.modelo,
			alvoModel,
			acaoDados.tipoAtaque or "Ataque",
			s.danoLeve,
			parteAtingida,
			nil,
			npcCFrame,
			alvoCFrame
		)
	end
end

NPC_HitReport.OnServerEvent:Connect(processarReporteHit)

return Mod
