--!strict

--[[
	Script: ControladorCombateNPC.luau
	Caminho: src/ServerScriptService/NPC/Combate
	Responsabilidade: Camada SO-LOGICA do combate de NPCs no servidor.
	    NAO carrega animacoes, NAO clona WeaponModel, NAO mantem hitbox no
	    servidor. Apenas:
	      - mantem estado canonico (atacando, indiceCombo, acaoTick, swingToken),
	      - publica atributos NPC_Acao/NPC_AcaoTick/NPC_LocomocaoNome/...
	      - recebe reportes de hit do CLIENTE do alvo (RemoteEvent NPC_HitReport),
	        valida (NPC realmente atacando, alvo proximo, dedup por swing) e
	        delega o dano canonico ao CombateServidor._ProcessarHit.
	    Cliente do alvo roda hitbox shapecast em seu WeaponModel LOCAL (que e o
	    unico que esta animado pelo Animator local), com os mesmos DmgPoints da
	    arma. Dano permanece autoritativo no servidor.
	Uso: ModuleScript; require e use a mesma API publica de antes
	    (Iniciar/EquiparArma/DesequiparArma/AtacarLeve/PararAtaque/
	     TocarLocomocao/EstaArmaPronta/EstaAtacando/EstaEquipando/
	     ObterAlcanceArmaEquipada/Destruir).
	Funcoes principais: Iniciar, EquiparArma, DesequiparArma, AtacarLeve,
	    TocarLocomocao, PararAtaque, Destruir
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Combate = ReplicatedStorage:WaitForChild("Combate")
local Modulo_Configuracoes = require(Combate:WaitForChild("Configuracoes"):WaitForChild("ConfigCombate"))
local Timings = require(Combate:WaitForChild("Configuracoes"):WaitForChild("TimingsAtaqueNPC"))

local TiposNPC = require(
	ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC"):WaitForChild("Tipos")
)

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
	local toolNoModelo = encontrarToolArmaNoModelo(s.modelo)
	if toolNoModelo then
		return registrarArmaEquipada(s, toolNoModelo)
	end
	local toolPorAtributo = encontrarToolArmaPorAtributo(s.modelo)
	if toolPorAtributo then
		return registrarArmaEquipada(s, toolPorAtributo)
	end
	if s.armaEquipada and s.armaEquipada.Parent then
		return registrarArmaEquipada(s, s.armaEquipada)
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
		verificarAlvo = nil,
		timings = Timings.Punhos,
		destruido = false,
	}
	estados[modelo] = s

	resolverArmaEquipada(s)

	setArmaPronta(s, false)
	setAcao(s, TiposNPC.Acao.Idle, 0)
	setLocomocao(s, "Idle", 1)

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

	resolverArmaEquipada(s)

	s.equipando = true
	s.equipToken += 1
	local token = s.equipToken
	local idArma = s.armaEquipada and lerStringDados(s.armaEquipada, "Id")
	if idArma then
		s.modelo:SetAttribute(TiposNPC.Chaves.ArmaEquipadaId, idArma)
	end
	setAcao(s, TiposNPC.Acao.Equipar, 0)

	local duracao = s.timings.Equipar.Duracao
	task.delay(duracao, function()
		if s.destruido or s.equipToken ~= token then
			return
		end
		s.armaPronta = true
		setArmaPronta(s, true)
		s.equipando = false
		setAcao(s, TiposNPC.Acao.Idle, 0)
	end)
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
		local cs = obterCS()
		if cs and cs.ProcessarComboTerminou then
			pcall(cs.ProcessarComboTerminou, s.modelo)
		end
	end

	s.equipando = true
	s.desequipToken += 1
	local token = s.desequipToken
	setAcao(s, TiposNPC.Acao.Desequipar, 0)

	local duracao = s.timings.Desequipar.Duracao
	task.delay(duracao, function()
		if s.destruido or s.desequipToken ~= token then
			return
		end
		s.armaPronta = false
		setArmaPronta(s, false)
		s.equipando = false
		setAcao(s, TiposNPC.Acao.Idle, 0)
	end)
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

local function finalizarSwing(s: Estado, token: number)
	if s.destruido or s.comboToken ~= token then
		return
	end
	s.atacando = false
	s.ultimoSwingFim = os.clock()
	s.swingHitFim = 0
	-- Reseta combo se nao houver continuacao dentro da janela.
	local janela = s.timings.AtaqueLeve.ContinuacaoCombo
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
			local cs = obterCS()
			if cs and cs.ProcessarComboTerminou then
				pcall(cs.ProcessarComboTerminou, s.modelo)
			end
			if not s.atacando and not s.equipando then
				setAcao(s, TiposNPC.Acao.Idle, 0)
			end
		end
	end)
end

function Mod.AtacarLeve(modelo: Model, verificarAlvo: (() -> boolean)?): boolean
	local s = estados[modelo]
	if not s then
		return false
	end
	if not s.armaPronta or s.atacando or s.equipando then
		return false
	end

	s.verificarAlvo = verificarAlvo

	local cs = obterCS()
	if not cs then
		return false
	end

	local maquina = cs.ObterMaquina(modelo)
	if not maquina then
		return false
	end

	if maquina.DefinirModo then
		maquina:DefinirModo("Punhos")
	end

	local ok, tipoAtaque = maquina:TenteAtacarLeveEmPe()
	if not ok or not tipoAtaque then
		return false
	end

	if cs._AplicarImpulsoAtacante then
		pcall(cs._AplicarImpulsoAtacante, modelo, tipoAtaque)
	end

	local velBloq = Modulo_Configuracoes.ObterConfiguracao("VelocidadeBloqueando") or 6
	s.humanoide.WalkSpeed = velBloq * 1.5

	s.indiceCombo = math.min(4, s.indiceCombo + 1)
	s.atacando = true
	s.comboToken += 1
	local token = s.comboToken

	-- Janela de aceitacao de hit reports do cliente (referenciada em ProcessarReporteHit).
	local t = s.timings.AtaqueLeve
	-- setAcao atualiza acaoTick para os.clock() agora; a janela usa esse tempo.
	setAcao(s, TiposNPC.Acao.AtaqueLeve, s.indiceCombo)
	s.swingHitInicio = s.acaoTick + t.AtrasoHit
	s.swingHitFim = s.acaoTick + t.Duracao
	table.clear(s.jaAtingidos)

	if cs.ProcessarComboHitbox then
		pcall(cs.ProcessarComboHitbox, s.modelo, { indice = s.indiceCombo })
	end

	-- Cancelamento por verificarAlvo (sai cedo se alvo ja saiu da faixa).
	task.delay(t.AtrasoHit, function()
		if s.destruido or s.comboToken ~= token then
			return
		end
		if s.verificarAlvo and not s.verificarAlvo() then
			s.swingHitFim = 0 -- fecha janela
			finalizarSwing(s, token)
		end
	end)

	task.delay(t.Duracao, function()
		finalizarSwing(s, token)
	end)

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
	local cs = obterCS()
	if cs and cs.ProcessarComboTerminou then
		pcall(cs.ProcessarComboTerminou, s.modelo)
	end
	if not s.equipando then
		setAcao(s, TiposNPC.Acao.Idle, 0)
	end
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
	s.armaPronta = false
	s.swingHitFim = 0
	table.clear(s.jaAtingidos)
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

local function processarReporteHit(jogador: Player, npcModel: Model, alvoModel: Model, acaoTickReportado: number)
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
	if not s.atacando then
		return
	end

	-- Cliente so pode reportar hit no proprio personagem (anti-cheat: outro
	-- player nao pode "pedir" dano em alguem).
	if alvoModel ~= jogador.Character then
		return
	end

	-- Tick precisa bater com o swing atual (com tolerancia).
	if math.abs((s.acaoTick or 0) - acaoTickReportado) > TOLERANCIA_TICK then
		return
	end

	-- Janela temporal do swing (do inicio efetivo da hitbox ate o fim do golpe).
	local agora = os.clock()
	if s.swingHitFim <= 0 then
		return
	end
	if agora < s.swingHitInicio - 0.05 or agora > s.swingHitFim + 0.10 then
		return
	end

	-- Dedup por swing.
	if s.jaAtingidos[alvoModel] then
		return
	end

	-- Validacao de alvo vivo + distancia plausivel.
	local hum = alvoModel:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return
	end
	local alcance = s.alcanceArma or 6
	local d = distanciaModelos(s.modelo, alvoModel)
	if d > alcance + TOLERANCIA_DISTANCIA then
		return
	end

	s.jaAtingidos[alvoModel] = true

	local cs = obterCS()
	if not cs or not cs._ProcessarHit then
		return
	end
	pcall(cs._ProcessarHit, s.modelo, alvoModel, "AtaqueLeve", s.danoLeve)
end

NPC_HitReport.OnServerEvent:Connect(processarReporteHit)

return Mod
