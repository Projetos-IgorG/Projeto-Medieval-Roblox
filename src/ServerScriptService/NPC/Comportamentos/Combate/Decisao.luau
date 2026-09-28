--!strict

--[[
	Script: Decisao.luau (filho de Combate)
	Responsabilidade: IA de combate do NPC. Decide alvo, distancia e intencao
	(perseguir / atacar / bloquear / orbitar / desengajar). NAO toca animacoes
	nem aplica dano: delega acoes ao Acoes e movimento ao Movimento.

	Correcoes em relacao ao codigo antigo:
	- Raio unico de desengajamento (Config.RAIO_DESENGAJAR).
	- SEM tentativa de bloqueio durante stun (removido a pedido).
	- Bloqueio nao ignora mais o desengajamento: se o alvo sumir/ficar longe
	  enquanto o NPC bloqueia, ele solta a guarda e desengaja.
	- Um unico conjunto de hooks na maquina (via Sincronia.InstalarHooks).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TiposNPC = require(ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC"):WaitForChild("Tipos"))

local Config = require(script.Parent:WaitForChild("Config"))
local Estado = require(script.Parent:WaitForChild("Estado"))
local Arma = require(script.Parent:WaitForChild("Arma"))
local Acoes = require(script.Parent:WaitForChild("Acoes"))
local Sincronia = require(script.Parent:WaitForChild("Sincronia"))
local Movimento = require(script.Parent:WaitForChild("Movimento"))
local HitReport = require(script.Parent:WaitForChild("HitReport"))
local Comportamento = require(script.Parent.Parent:WaitForChild("Comportamento"))

type Ctx = Comportamento.ContextoNPC

local Decisao = {}

-- =============================================================================
-- Helpers gerais.
-- =============================================================================

local function lerFlag(modelo: Model, chave: string, padrao: boolean): boolean
	local v = modelo:GetAttribute(chave)
	if typeof(v) == "boolean" then
		return v
	end
	return padrao
end

local function lerNumero(modelo: Model, chave: string, padrao: number): number
	local v = modelo:GetAttribute(chave)
	if typeof(v) == "number" and v > 0 then
		return v
	end
	return padrao
end

local function setModoCombateAttr(ctx: Ctx, ativo: boolean)
	if ctx.modelo:GetAttribute(TiposNPC.Chaves.ModoCombate) ~= ativo then
		ctx.modelo:SetAttribute(TiposNPC.Chaves.ModoCombate, ativo)
	end
end

local function alvoVivoComHRP(alvo: Model?): (boolean, BasePart?)
	if not alvo or not alvo.Parent then
		return false, nil
	end
	local hum = alvo:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return false, nil
	end
	local hrp = alvo:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return false, nil
	end
	return true, hrp
end

local function alvoDentroDoRaio(ctx: Ctx, alvo: Model?, raio: number): (boolean, BasePart?)
	local vivo, hrp = alvoVivoComHRP(alvo)
	if not vivo or not hrp then
		return false, nil
	end
	local d = (hrp.Position - ctx.modelo:GetPivot().Position).Magnitude
	return d <= raio, hrp
end

local function refAlvo(alvo: Model?): number
	if not alvo then
		return 0
	end
	local player = Players:GetPlayerFromCharacter(alvo)
	if player then
		return player.UserId
	end
	local id = alvo:GetAttribute(TiposNPC.Chaves.Id)
	if typeof(id) == "number" then
		return -id
	end
	return 0
end

-- Verificador usado pelo Acoes para decidir se um combo pode CONTINUAR.
local function criarVerificadorCombo(ctx: Ctx, alvo: Model): () -> boolean
	return function(): boolean
		if ctx.estado.destruido then
			return false
		end
		local vivo, hrp = alvoVivoComHRP(alvo)
		if not vivo or not hrp then
			return false
		end
		local alcance = Acoes.ObterAlcanceArma(ctx.modelo)
		if not alcance then
			return false
		end
		local d = (hrp.Position - ctx.modelo:GetPivot().Position).Magnitude
		return d <= alcance * Config.TOLERANCIA_COMBO_ALCANCE
	end
end

-- =============================================================================
-- Alvo: selecao, subscricao e memoria de agressor.
-- =============================================================================

local atualizarSubscricaoAlvo: (Ctx, Model?) -> ()
local tentarBloqueioPreditivo: (Ctx, Model) -> ()
local iniciarBloqueio: (Ctx) -> ()
local tentarRiposte: (Ctx) -> ()

local function definirAlvoFocado(ctx: Ctx, alvo: Model?)
	if ctx.estado.alvoAtual == alvo then
		return
	end
	ctx.estado.alvoAtual = alvo
	ctx.estado.agressorCandidato = nil
	ctx.estado.hitsAgressorCandidato = 0
	ctx.estado.agressorCandidatoAte = 0
	atualizarSubscricaoAlvo(ctx, alvo)
	ctx.modelo:SetAttribute(TiposNPC.Chaves.AlvoRef, refAlvo(alvo))
end

local function encontrarAlvo(ctx: Ctx): Model?
	-- Mantem o alvo atual enquanto estiver dentro do raio de desengajamento.
	local atual = ctx.estado.alvoAtual
	if alvoDentroDoRaio(ctx, atual, Config.RAIO_DESENGAJAR) then
		return atual
	end

	local pos = ctx.modelo:GetPivot().Position
	local alvo: Model? = nil
	local melhor = math.huge
	for _, player in Players:GetPlayers() do
		local char = player.Character
		if not char then
			continue
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then
			continue
		end
		local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then
			continue
		end
		local d = (hrp.Position - pos).Magnitude
		if d < Config.RAIO_AGGRO and d < melhor then
			melhor = d
			alvo = char
		end
	end
	return alvo
end

local function obterMaquinaAlvo(alvo: Model): any?
	local cs = Estado.ObterCombateServidor()
	if not cs or not cs.ObterMaquina then
		return nil
	end
	local ok, maq = pcall(cs.ObterMaquina, alvo)
	if ok then
		return maq
	end
	return nil
end

local function dadosComboAlvo(ctx: Ctx): any?
	local alvo = ctx.estado.alvoSubscrito or ctx.estado.alvoAtual
	if not alvo then
		return nil
	end
	local maq = ctx.estado.maquinaAlvoSubscrita
	if not maq or ctx.estado.alvoSubscrito ~= alvo then
		maq = obterMaquinaAlvo(alvo)
	end
	return maq and maq.dados or nil
end

local function alvoMantemComboLeve(ctx: Ctx): boolean
	local dados = dadosComboAlvo(ctx)
	if not dados or dados.estadoAcao ~= "Atacando" then
		return false
	end
	local indice = dados.indiceCombo or 0
	return indice > 0 and indice < Config.INDICE_COMBO_MAX
end

local function registrarAtaqueAlvo(ctx: Ctx, alvo: Model, dados: any?)
	if not dados then
		return
	end
	local agora = os.clock()
	local emPreparoAposAparado = (ctx.estado.prepararParryAte or 0) > agora

	if emPreparoAposAparado then
		-- Na janela pos-aparado, reage apenas no instante em que a hitbox do
		-- atacante iniciar (parry trade preciso).
		if not dados.hitboxAtivou then
			return
		end
		local tParryStart = (ctx.estado.prepararParryAte :: number) - Config.JANELA_PREPARO_APOS_APARADO
		local ultimoAtaqueAlvo = math.max(dados.ultimoAtaque or 0, dados.ultimaContinuacaoCombo or 0)
		if ultimoAtaqueAlvo <= tParryStart then
			return
		end
	end

	local indice = dados.indiceCombo or 0
	local ultimoAtaque = math.max(dados.ultimoAtaque or 0, dados.ultimaContinuacaoCombo or 0)
	local chaveHitbox = string.format("%d_%f_%s", indice, ultimoAtaque, tostring(dados.hitboxAtivou))
	if chaveHitbox == ctx.estado.ultimoHitboxRegistrado then
		return
	end
	ctx.estado.ultimoHitboxRegistrado = chaveHitbox

	tentarBloqueioPreditivo(ctx, alvo)
end

local function instalarSincAlvo(ctx: Ctx, alvo: Model)
	local maqAlvo = obterMaquinaAlvo(alvo)
	if not maqAlvo or not maqAlvo.AoMudarEstadoAcao then
		return
	end
	ctx.estado.maquinaAlvoSubscrita = maqAlvo
	local disc = maqAlvo:AoMudarEstadoAcao(function(novo: string, _anterior: string)
		if ctx.estado.destruido or ctx.humanoide.Health <= 0 then
			return
		end
		if ctx.estado.alvoSubscrito ~= alvo then
			return
		end
		if novo ~= "Atacando" then
			return
		end
		if not lerFlag(ctx.modelo, TiposNPC.Chaves.PodeDefender, false) then
			return
		end
		registrarAtaqueAlvo(ctx, alvo, maqAlvo.dados)
	end)
	if typeof(disc) == "function" then
		ctx.estado.desconectarAlvo = disc
	end
end

atualizarSubscricaoAlvo = function(ctx: Ctx, novoAlvo: Model?)
	if ctx.estado.alvoSubscrito == novoAlvo then
		return
	end
	if ctx.estado.desconectarAlvo then
		pcall(ctx.estado.desconectarAlvo)
		ctx.estado.desconectarAlvo = nil
	end
	ctx.estado.alvoSubscrito = novoAlvo
	ctx.estado.maquinaAlvoSubscrita = nil
	ctx.estado.ultimoHitboxRegistrado = nil
	if novoAlvo then
		instalarSincAlvo(ctx, novoAlvo)
	end
end

local function registrarDanoRecebido(ctx: Ctx, atacante: Model)
	if ctx.estado.destruido or ctx.humanoide.Health <= 0 then
		return
	end
	if not ctx.hostil or atacante == ctx.modelo then
		return
	end
	if not alvoDentroDoRaio(ctx, atacante, Config.RAIO_DESENGAJAR) then
		return
	end

	local alvoAtual = ctx.estado.alvoAtual
	if atacante == alvoAtual then
		ctx.estado.agressorCandidato = nil
		ctx.estado.hitsAgressorCandidato = 0
		ctx.estado.agressorCandidatoAte = 0
		return
	end

	if not alvoDentroDoRaio(ctx, alvoAtual, Config.RAIO_DESENGAJAR) then
		definirAlvoFocado(ctx, atacante)
		return
	end

	local agora = os.clock()
	if ctx.estado.agressorCandidato ~= atacante or (ctx.estado.agressorCandidatoAte or 0) < agora then
		ctx.estado.agressorCandidato = atacante
		ctx.estado.hitsAgressorCandidato = 1
	else
		ctx.estado.hitsAgressorCandidato = (ctx.estado.hitsAgressorCandidato or 0) + 1
	end
	ctx.estado.agressorCandidatoAte = agora + Config.JANELA_MEMORIA_AGRESSOR

	if (ctx.estado.hitsAgressorCandidato or 0) >= Config.HITS_PARA_TROCAR_ALVO then
		definirAlvoFocado(ctx, atacante)
	end
end

local function instalarSincDanoRecebido(ctx: Ctx)
	local cs = Estado.ObterCombateServidor()
	if not cs or not cs.AoDanoAplicado then
		return
	end
	local conn = cs.AoDanoAplicado(function(atacante: Model, alvo: Model, _tipoAtaque: string, _dano: number)
		if alvo ~= ctx.modelo then
			return
		end
		registrarDanoRecebido(ctx, atacante)
	end)
	if typeof(conn) == "RBXScriptConnection" then
		Comportamento.Helpers.RastrearConexao(ctx, conn)
	end
end

local function instalarSincHitboxAtivada(ctx: Ctx)
	local cs = Estado.ObterCombateServidor()
	if not cs or not cs.AoHitboxAtivada then
		return
	end
	local conn = cs.AoHitboxAtivada(function(entidade: Model, dados: any)
		if ctx.estado.destruido or ctx.humanoide.Health <= 0 then
			return
		end
		if entidade ~= ctx.estado.alvoAtual then
			return
		end
		if not lerFlag(ctx.modelo, TiposNPC.Chaves.PodeDefender, false) then
			return
		end
		registrarAtaqueAlvo(ctx, entidade, dados)
	end)
	if typeof(conn) == "RBXScriptConnection" then
		Comportamento.Helpers.RastrearConexao(ctx, conn)
	end
end

-- =============================================================================
-- Bloqueio / parry / riposte.
-- =============================================================================

local function pararBloqueio(ctx: Ctx)
	if (ctx.estado.bloqueandoAte or 0) <= 0 then
		return
	end
	ctx.estado.bloqueioToken = (ctx.estado.bloqueioToken or 0) + 1
	ctx.estado.bloqueandoAte = 0
	ctx.estado.bloqueioSeguraCombo = false
	ctx.estado.cooldownBloqueio = os.clock() + Config.COOLDOWN_BLOQUEIO
	Acoes.PararBloqueio(ctx.modelo)
end

iniciarBloqueio = function(ctx: Ctx)
	if not lerFlag(ctx.modelo, TiposNPC.Chaves.PodeDefender, false) then
		return
	end
	local maq = ctx.estado.maquina
	if maq then
		-- FIX: nunca levanta guarda stunado/em acao conflitante.
		if maq.EstaStunado and maq:EstaStunado() then
			return
		end
		local estadoAcao = if maq.ObterEstadoAcao then maq:ObterEstadoAcao() else nil
		if estadoAcao == "Atacando" or estadoAcao == "Equipando" or estadoAcao == "Desequipando" or estadoAcao == "Aparando" then
			return
		end
	end
	local agora = os.clock()
	if (ctx.estado.cooldownBloqueio or 0) > agora then
		return
	end
	if Acoes.EstaAtacando(ctx.modelo) then
		return
	end

	local ok = Acoes.Bloquear(ctx.modelo)
	if not ok then
		return
	end

	local duracao = Config.DURACAO_BLOQUEIO_MIN
		+ math.random() * (Config.DURACAO_BLOQUEIO_MAX - Config.DURACAO_BLOQUEIO_MIN)
	ctx.estado.bloqueioToken = (ctx.estado.bloqueioToken or 0) + 1
	local token = ctx.estado.bloqueioToken
	ctx.estado.bloqueandoAte = agora + duracao
	ctx.estado.bloqueioSeguraCombo = false
	ctx.estado.cooldownBloqueio = agora + duracao + Config.COOLDOWN_BLOQUEIO

	task.delay(duracao, function()
		if ctx.estado.destruido or ctx.estado.bloqueioToken ~= token then
			return
		end
		if (ctx.estado.bloqueandoAte or 0) <= os.clock() + 0.001 and not ctx.estado.bloqueioSeguraCombo then
			pararBloqueio(ctx)
		end
	end)
end

tentarBloqueioPreditivo = function(ctx: Ctx, alvo: Model)
	if not lerFlag(ctx.modelo, TiposNPC.Chaves.PodeDefender, false) then
		return
	end
	local agora = os.clock()

	-- Janela pos-aparado: levanta a guarda imediatamente (parry trade).
	if (ctx.estado.prepararParryAte or 0) > agora then
		iniciarBloqueio(ctx)
		return
	end

	if (ctx.estado.cooldownPredicaoParry or 0) > agora then
		return
	end
	ctx.estado.cooldownPredicaoParry = agora + Config.COOLDOWN_PREDICAO_BLOQUEIO
	local token = (ctx.estado.predicaoToken or 0) + 1
	ctx.estado.predicaoToken = token

	task.delay(Config.ATRASO_BLOQUEIO_PREDITIVO, function()
		if ctx.estado.destruido or ctx.humanoide.Health <= 0 then
			return
		end
		if ctx.estado.predicaoToken ~= token then
			return
		end
		if ctx.estado.alvoSubscrito ~= alvo and ctx.estado.alvoAtual ~= alvo then
			return
		end
		iniciarBloqueio(ctx)
	end)
end

tentarRiposte = function(ctx: Ctx)
	local token = (ctx.estado.riposteToken or 0) + 1
	ctx.estado.riposteToken = token
	task.delay(Config.ATRASO_ATAQUE_APOS_PARRY, function()
		if ctx.estado.destruido or ctx.humanoide.Health <= 0 then
			return
		end
		if ctx.estado.riposteToken ~= token then
			return
		end
		if Acoes.EstaAtacando(ctx.modelo) or Acoes.EstaEquipando(ctx.modelo) then
			return
		end
		local alvo = ctx.estado.alvoAtual
		if not alvo then
			return
		end
		Acoes.Atacar(ctx.modelo, criarVerificadorCombo(ctx, alvo))
	end)
end

-- =============================================================================
-- Desengajar.
-- =============================================================================

local function desengajar(ctx: Ctx)
	Movimento.Parar(ctx)
	Movimento.LimparOrientacao(ctx)
	if (ctx.estado.bloqueandoAte or 0) > 0 then
		pararBloqueio(ctx) -- FIX: bloqueio nao segura mais o NPC engajado
	end
	if Acoes.EstaArmaPronta(ctx.modelo) then
		Acoes.DesequiparArma(ctx.modelo)
		setModoCombateAttr(ctx, false)
		local maq = ctx.estado.maquina
		if maq and maq.DefinirModo then
			maq:DefinirModo("Base")
		end
	else
		Acoes.TocarLocomocao(ctx.modelo, "Idle")
		Sincronia.DefinirEstadoLocomocao(
			Estado.ObterOuCriar(ctx.modelo, ctx.humanoide),
			ctx.estado.maquina,
			TiposNPC.Estado.Idle
		)
	end
end

-- =============================================================================
-- Reacao a mudancas de estado da maquina (callback registrado na Sincronia).
-- =============================================================================

local function aoMudarEstadoAcao(ctx: Ctx, novo: string, anterior: string)
	if ctx.estado.destruido or ctx.humanoide.Health <= 0 then
		return
	end
	local agora = os.clock()
	local e = ctx.estado

	-- Baiting: ao sair de um ataque proprio, espera antes do proximo.
	-- Se acertou o golpe, pressiona (espera curta).
	if anterior == "Atacando" then
		local acertou = ctx.modelo:GetAttribute("NPC_AcertouCombo") == true
		local espera
		if acertou then
			espera = Config.ESPERA_APOS_ACERTO_MIN
				+ math.random() * (Config.ESPERA_APOS_ACERTO_MAX - Config.ESPERA_APOS_ACERTO_MIN)
		else
			espera = Config.ESPERA_BAITING_MIN
				+ math.random() * (Config.ESPERA_BAITING_MAX - Config.ESPERA_BAITING_MIN)
		end
		e.cooldownAtaque = agora + espera
	end

	if novo == "Aparado" then
		e.bloqueandoAte = 0
		e.bloqueioSeguraCombo = false
		e.prepararParryAte = agora + Config.JANELA_PREPARO_APOS_APARADO
		e.cooldownBloqueio = 0
		e.cooldownPredicaoParry = 0
		e.cooldownAtaque = 0
		ctx.humanoide.WalkSpeed = Config.VELOCIDADE_APARANDO
		Acoes.PararAtaque(ctx.modelo)
		Movimento.LimparOrientacao(ctx)
	elseif novo == "Stunado" or novo == "DefesaQuebrada" then
		e.bloqueandoAte = 0
		e.stunadoAte = agora + 0.05
		ctx.humanoide:Move(Vector3.zero, false)
		ctx.humanoide.WalkSpeed = 0
		Acoes.PararAtaque(ctx.modelo)
		Movimento.LimparOrientacao(ctx)
	elseif novo == "Aparando" then
		-- Parry bem sucedido: reseta cooldowns e tenta riposte.
		e.bloqueandoAte = 0
		e.bloqueioSeguraCombo = false
		e.cooldownBloqueio = 0
		e.cooldownPredicaoParry = 0
		e.cooldownAtaque = 0
		tentarRiposte(ctx)
	end
end

-- =============================================================================
-- Ciclo de vida.
-- =============================================================================

function Decisao.Iniciar(ctx: Ctx)
	ctx.humanoide.JumpHeight = 7.2
	ctx.humanoide.WalkSpeed = 0
	ctx.humanoide.AutoRotate = true

	local e = ctx.estado
	e.destruido = false
	e.cooldownBloqueio = 0
	e.bloqueandoAte = 0
	e.stunadoAte = 0
	e.cooldownAtaque = 0
	e.cooldownPredicaoParry = 0
	e.prepararParryAte = 0
	e.velocidadeAnimacaoLocomocao = 1
	e.alvoAtual = nil
	e.alvoSubscrito = nil
	e.desconectarAlvo = nil
	e.agressorCandidato = nil
	e.hitsAgressorCandidato = 0
	e.agressorCandidatoAte = 0

	-- Estado de combate central + arma.
	local s = Estado.ObterOuCriar(ctx.modelo, ctx.humanoide)
	Arma.Aplicar(s)
	Sincronia.DefinirArmaPronta(s, false)
	Sincronia.DefinirAcao(s, TiposNPC.Acao.Idle, 0)
	Sincronia.DefinirLocomocao(s, "Idle", 1)
	Sincronia.DefinirEstado(ctx.modelo, TiposNPC.Estado.Idle)

	-- Maquina canonica: NPC participa do pipeline igual qualquer player.
	-- UM unico conjunto de hooks (Sincronia cuida dos atributos; Decisao da IA).
	local cs = Estado.ObterCombateServidor()
	if cs and cs.ObterMaquina then
		local ok, maq = pcall(cs.ObterMaquina, ctx.modelo)
		if ok and maq then
			e.maquina = maq
			Sincronia.InstalarHooks(s, maq, function(novo: string, anterior: string)
				aoMudarEstadoAcao(ctx, novo, anterior)
			end)
			if maq.DefinirModo then
				maq:DefinirModo("Base")
			end
		end
	end

	instalarSincDanoRecebido(ctx)
	instalarSincHitboxAtivada(ctx)
	HitReport.Iniciar()

	-- Comeca SEM arma equipada (modo Base).
	setModoCombateAttr(ctx, false)
end

function Decisao.Tick(ctx: Ctx, dt: number)
	-- Morte: o Gerenciamento cuida (ragdoll + despawn). Nada a decidir aqui.
	if ctx.humanoide.Health <= 0 then
		return
	end

	local agora = os.clock()
	local e = ctx.estado
	local maq = e.maquina
	local modelo = ctx.modelo

	local emAparado = (maq and maq.dados and maq.dados.estadoAcao == "Aparado") == true
	local emAparando = (maq and maq.dados and maq.dados.estadoAcao == "Aparando") == true
	local emPreparoAposAparado = (e.prepararParryAte or 0) > agora

	-- Stunado: nao age (FIX: sem tentativa de bloqueio durante stun).
	local stunadoLocal = (e.stunadoAte or 0) > agora
	local stunadoMaq = (maq and maq.EstaStunado and maq:EstaStunado()) == true
	if (stunadoLocal or stunadoMaq) and not emAparado then
		Movimento.Parar(ctx)
		return
	end

	-- Equipando/desequipando: aguarda a animacao terminar.
	if Acoes.EstaEquipando(modelo) then
		Movimento.Parar(ctx)
		return
	end

	-- NPC nao-hostil: parado em modo Base.
	if not ctx.hostil then
		desengajar(ctx)
		return
	end

	local podeAndar = lerFlag(modelo, TiposNPC.Chaves.PodeAndar, true)
	local podeAtacar = lerFlag(modelo, TiposNPC.Chaves.PodeAtacar, true)
	local podeDefender = lerFlag(modelo, TiposNPC.Chaves.PodeDefender, false)

	-- Bloqueando: mantem postura, mas NAO ignora desengajamento (FIX).
	if (e.bloqueandoAte or 0) > agora then
		local alvoB = e.alvoAtual
		local dentro, hrpB = alvoDentroDoRaio(ctx, alvoB, Config.RAIO_DESENGAJAR)
		if not dentro then
			desengajar(ctx)
			return
		end
		if hrpB then
			Movimento.OrientarParaAlvo(ctx, hrpB.Position)
		end
		if alvoMantemComboLeve(ctx) then
			e.bloqueioSeguraCombo = true
			e.bloqueandoAte = math.max(e.bloqueandoAte or 0, agora + 0.25)
		elseif e.bloqueioSeguraCombo then
			pararBloqueio(ctx)
			return
		end
		ctx.humanoide:Move(Vector3.zero, false)
		ctx.humanoide.WalkSpeed = Config.VELOCIDADE_BLOQUEANDO
		return
	end

	local alvo = encontrarAlvo(ctx)
	definirAlvoFocado(ctx, alvo)
	if not alvo then
		desengajar(ctx)
		return
	end

	local _, alvoHRP = alvoVivoComHRP(alvo)
	if not alvoHRP then
		return
	end

	local pos = modelo:GetPivot().Position
	local distancia = (alvoHRP.Position - pos).Magnitude

	-- Fallback de deteccao de ataque do alvo (caso o hook tenha perdido o evento).
	local maqAlvo = e.maquinaAlvoSubscrita
	if maqAlvo and maqAlvo.dados and maqAlvo.dados.estadoAcao == "Atacando" then
		registrarAtaqueAlvo(ctx, alvo, maqAlvo.dados)
	end

	-- Muito longe: desengaja (raio unico).
	if distancia > Config.RAIO_DESENGAJAR then
		desengajar(ctx)
		return
	end

	-- Dentro do raio de combate: garante arma equipada.
	if not Acoes.EstaArmaPronta(modelo) then
		Acoes.EquiparArma(modelo)
		setModoCombateAttr(ctx, true)
		if maq and maq.DefinirModo then
			maq:DefinirModo(Acoes.ObterModoAnimacao(modelo))
		end
		Movimento.Parar(ctx)
		Movimento.OrientarParaAlvo(ctx, alvoHRP.Position)
		return
	end

	Movimento.OrientarParaAlvo(ctx, alvoHRP.Position)

	local alcance = Acoes.ObterAlcanceArma(modelo)
	if not alcance then
		Movimento.Parar(ctx)
		Acoes.TocarLocomocao(modelo, "Idle")
		return
	end
	local dentroDoAlcance = distancia <= (alcance + Config.TOLERANCIA_ALCANCE)
	local distanciaCorrer = lerNumero(modelo, TiposNPC.Chaves.DistanciaCorrer, Config.DISTANCIA_CORRER_PADRAO)

	-- Controle de "chegou/parou" para liberar o primeiro ataque rapido.
	if dentroDoAlcance then
		if e.chasingAlvo then
			e.chasingAlvo = nil
			e.cooldownAtaque = 0
		end
		local npcParado = Movimento.VelocidadePlanaModelo(modelo) < 0.8
			and ctx.humanoide.MoveDirection.Magnitude < 0.1
		if npcParado then
			if not e.tempoParadoInicio then
				e.tempoParadoInicio = agora
			elseif agora - e.tempoParadoInicio >= 0.35 then
				e.cooldownAtaque = 0
			end
		else
			e.tempoParadoInicio = nil
		end
	else
		e.chasingAlvo = true
		e.tempoParadoInicio = nil
	end

	-- Aparado: continua andando em direcao ao alvo enquanto a reacao toca.
	if emAparado then
		if podeAndar then
			local dirParaAlvo = alvoHRP.Position - pos
			if dirParaAlvo.Magnitude > 0.001 then
				Movimento.MoverDirecaoMantendoOlhar(
					ctx,
					alvoHRP.Position,
					dirParaAlvo.Unit,
					Config.VELOCIDADE_APARANDO,
					false
				)
			end
		else
			Movimento.Parar(ctx)
		end
		return
	end

	if emAparando then
		Movimento.Parar(ctx)
		return
	end

	-- Atacando: ajusta posicao e pede continuacao de combo.
	if Acoes.EstaAtacando(modelo) then
		if podeAndar then
			local moveu, animLoco = Movimento.MoverParaFaixaDeAlcance(
				ctx, pos, alvoHRP.Position, distancia, alcance, distanciaCorrer, dt
			)
			if moveu and animLoco then
				Acoes.TocarLocomocao(modelo, animLoco, e.velocidadeAnimacaoLocomocao or 1)
			else
				Acoes.TocarLocomocao(modelo, "Idle")
			end
		else
			Movimento.Parar(ctx)
		end

		if podeAtacar and distancia <= alcance * Config.TOLERANCIA_COMBO_ALCANCE then
			Acoes.Atacar(modelo, criarVerificadorCombo(ctx, alvo))
		end
		return
	end

	-- No alcance: decide entre bloquear e atacar.
	if dentroDoAlcance then
		local cooldownBloqueioOK = (e.cooldownBloqueio or 0) <= agora
		local cooldownAtaqueOK = (e.cooldownAtaque or 0) <= agora

		if podeDefender and cooldownBloqueioOK and not emPreparoAposAparado
			and math.random() < Config.CHANCE_BLOQUEIO_POR_TICK
		then
			iniciarBloqueio(ctx)
			return
		end
		if podeAtacar and cooldownAtaqueOK and not emPreparoAposAparado then
			if Acoes.Atacar(modelo, criarVerificadorCombo(ctx, alvo)) then
				return
			end
		end
	end

	-- Orbita / faixa de alcance.
	local s = Estado.Obter(modelo)
	if podeAndar then
		local orbitando, animOrbita =
			Movimento.TentarOrbitar(ctx, alvo, pos, alvoHRP.Position, distancia, alcance, agora)
		if orbitando and animOrbita then
			Acoes.TocarLocomocao(modelo, animOrbita, e.velocidadeAnimacaoLocomocao or 1)
			if s then
				Sincronia.DefinirEstadoLocomocao(s, maq, Movimento.EstadoPorAnimacaoLocomocao(animOrbita))
			end
			return
		end

		local moveu, animLoco = Movimento.MoverParaFaixaDeAlcance(
			ctx, pos, alvoHRP.Position, distancia, alcance, distanciaCorrer, dt
		)
		if moveu and animLoco then
			Acoes.TocarLocomocao(modelo, animLoco, e.velocidadeAnimacaoLocomocao or 1)
			if s then
				Sincronia.DefinirEstadoLocomocao(s, maq, Movimento.EstadoPorAnimacaoLocomocao(animLoco))
			end
		else
			Acoes.TocarLocomocao(modelo, "Idle")
			if s then
				Sincronia.DefinirEstadoLocomocao(s, maq, TiposNPC.Estado.Idle)
			end
		end
	else
		Movimento.Parar(ctx)
		Acoes.TocarLocomocao(modelo, "Idle")
		if s then
			Sincronia.DefinirEstadoLocomocao(s, maq, TiposNPC.Estado.Idle)
		end
	end
end

function Decisao.Destruir(ctx: Ctx)
	ctx.estado.destruido = true
	atualizarSubscricaoAlvo(ctx, nil)
	Movimento.LimparOrientacao(ctx)
	Acoes.PararBloqueio(ctx.modelo)
	Estado.Destruir(ctx.modelo) -- desconecta hooks, limpa historico, remove maquina
	ctx.estado.maquina = nil
	ctx.estado.maquinaAlvoSubscrita = nil
	Comportamento.Helpers.LimparConexoes(ctx)
end

return Decisao
