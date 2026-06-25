--!strict

--[[
	Script: Combate.luau
	Caminho: src/ServerScriptService/NPC/Comportamentos
	Responsabilidade: IA de NPC humanoide hostil. Decide alvo, distancia e
	    intencao (perseguir / atacar / bloquear / desengajar). NAO toca animacoes
	    nem aplica dano diretamente: delega TUDO ao ControladorCombateNPC, que
	    replica o pipeline canonico do player (anim+markers+hitbox real em
	    WeaponModelRight/Left, maquina de estados com cooldown de combo, parry e
	    knockback).
	Uso: ModuleScript; auto-registra ao ser required.
	Nao faz: Nao implementa renderizacao, nao toca animacoes de combate, nao
	    chama _ProcessarHit diretamente. Apenas decide intencao.
	Funcoes principais: iniciar, atualizar, destruir
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TiposNPC = require(ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC"):WaitForChild("Tipos"))
local Comportamento = require(script.Parent:WaitForChild("Comportamento"))
local ConfigCombate =
	require(ReplicatedStorage:WaitForChild("Combate"):WaitForChild("Configuracoes"):WaitForChild("ConfigCombate"))
local ControladorCombateNPC =
	require(ServerScriptService:WaitForChild("NPC"):WaitForChild("Combate"):WaitForChild("ControladorCombateNPC"))

type Ctx = Comportamento.ContextoNPC

-- =============================================================================
-- Constantes
-- =============================================================================

local RAIO_AGGRO = 35
local RAIO_DESAGGRO = 60
local RAIO_DESEQUIPAR = 50

local VELOCIDADE_ANDANDO = ConfigCombate.ConfiguracaoGlobal.VelocidadeAndando or 12
local VELOCIDADE_CORRENDO = ConfigCombate.ConfiguracaoGlobal.VelocidadeCorrendo or 16
local VELOCIDADE_BLOQUEANDO = ConfigCombate.ConfiguracaoGlobal.VelocidadeBloqueando or 6
local VELOCIDADE_APARANDO = ConfigCombate.ConfiguracaoGlobal.VelocidadeAparando or 3

local DURACAO_BLOQUEIO_MIN = 1.1
local DURACAO_BLOQUEIO_MAX = 2.0
local CHANCE_BLOQUEIO_POR_TICK = 0.18
local COOLDOWN_BLOQUEIO_NPC = (ConfigCombate.ConfiguracaoGlobal.CooldownBloqueio or 0.5) + 1.5
local DISTANCIA_CORRER_PADRAO = 20
local CHAVE_DISTANCIA_CORRER = "NPC_DistanciaCorrer"
local HITS_PARA_TROCAR_ALVO = 2
local JANELA_MEMORIA_AGRESSOR = 6

-- Faixa unica de movimento: alcance da arma equipada, com tolerancia fixa.
local TOLERANCIA_ALCANCE = 0.7

-- =============================================================================
-- Helpers de Orientação e Bloco de Defesa (Definidos no topo para evitar warnings de lint)
-- =============================================================================

local function obterOuCriarAlignOrientation(ctx: Ctx): AlignOrientation?
	local existente = ctx.estado.alignOrientacaoAlvo
	if typeof(existente) == "Instance" and existente:IsA("AlignOrientation") and existente.Parent then
		return existente :: AlignOrientation
	end

	local hrp = ctx.modelo.PrimaryPart
	if not hrp then
		return nil
	end

	local att = hrp:FindFirstChild("OrientacaoAlvoAttachment") :: Attachment
	if not att then
		local newAtt = Instance.new("Attachment") :: Attachment
		newAtt.Name = "OrientacaoAlvoAttachment"
		newAtt.Parent = hrp
		att = newAtt
	end

	local ao = Instance.new("AlignOrientation") :: AlignOrientation
	ao.Name = "AlignOrientacaoAlvo"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	-- Torque e responsividade baixos: a orientacao visual eh feita no client.
	-- Aqui so garantimos que o HRP nao fique de costas pro alvo.
	ao.MaxTorque = 50000
	ao.Responsiveness = 12
	ao.Parent = hrp

	ctx.estado.alignOrientacaoAlvo = ao
	return ao
end

local function orientarParaAlvo(ctx: Ctx, alvoPos: Vector3)
	ctx.humanoide.AutoRotate = false
	local ao = obterOuCriarAlignOrientation(ctx)
	local hrp = ctx.modelo.PrimaryPart
	if ao and hrp then
		local pos = hrp.Position
		local lookPlano = Vector3.new(alvoPos.X, pos.Y, alvoPos.Z)
		if (lookPlano - pos).Magnitude > 0.8 then -- Threshold aumentado para evitar rotação NaN/infinita em proximidade
			ao.CFrame = CFrame.lookAt(pos, lookPlano)
		end
	end
end

local function limparOrientacao(ctx: Ctx)
	local existente = ctx.estado.alignOrientacaoAlvo
	if typeof(existente) == "Instance" then
		existente:Destroy()
	end
	ctx.estado.alignOrientacaoAlvo = nil

	local hrp = ctx.modelo.PrimaryPart
	if hrp then
		local att = hrp:FindFirstChild("OrientacaoAlvoAttachment")
		if att then
			att:Destroy()
		end
	end
end


-- Cooldown entre tentativas de bloqueio preditivo para nao spammar.
local COOLDOWN_PREDICAO_BLOQUEIO = 0.4
-- Atraso apos detectar ataque do alvo antes de levantar guarda.
local ATRASO_BLOQUEIO_PREDITIVO = 0.28

-- Baiting: apos cada ataque proprio, NPC fica 1.0-2.5s sem iniciar novo ataque,
-- esperando o alvo abrir guarda/atacar para conseguir parry. NPC continua
-- podendo bloquear/recuar nesse intervalo.
local ESPERA_BAITING_MIN = 1.0
local ESPERA_BAITING_MAX = 2.5

local ATRASO_ATAQUE_APOS_PARRY = 0.2
local JANELA_PREPARO_APOS_APARADO = 1.4

local INTERVALO_ROLAGEM_ORBITA = 7
local CHANCE_ORBITA_VERDADEIRO = 0.45
local DURACAO_ORBITA = 1.2
local VELOCIDADE_ORBITA = VELOCIDADE_ANDANDO

-- =============================================================================
-- Acesso lazy ao CombateServidor (para obter a maquina canonica).
-- =============================================================================

local CombateServidor: any = nil
local function obterCombateServidor(): any?
	if CombateServidor then
		return CombateServidor
	end
	local mod = ServerScriptService:FindFirstChild("Combate")
	mod = mod and mod:FindFirstChild("Servidor")
	mod = mod and mod:FindFirstChild("CombateServidor")
	if mod and mod:IsA("ModuleScript") then
		local ok, m = pcall(require, mod)
		if ok then
			CombateServidor = m
			return m
		end
	end
	return nil
end

-- =============================================================================
-- Helpers
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

local function setEstado(ctx: Ctx, estado: string)
	if ctx.modelo:GetAttribute(TiposNPC.Chaves.Estado) ~= estado then
		ctx.modelo:SetAttribute(TiposNPC.Chaves.Estado, estado)
	end
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

local atualizarSubscricaoAlvo: (Ctx, Model?) -> ()

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
	local atual = ctx.estado.alvoAtual
	local manterAtual = alvoDentroDoRaio(ctx, atual, RAIO_DESEQUIPAR)
	if manterAtual then
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
		if d < RAIO_AGGRO and d < melhor then
			melhor = d
			alvo = char
		end
	end
	return alvo
end

local function estadoAcaoMaquina(ctx: Ctx): string?
	local maq = ctx.estado.maquina
	if not maq or not maq.dados then
		return nil
	end
	return maq.dados.estadoAcao
end

local function estaAparado(ctx: Ctx): boolean
	return estadoAcaoMaquina(ctx) == "Aparado"
		or ctx.modelo:GetAttribute(TiposNPC.Chaves.Estado) == TiposNPC.Estado.Aparado
end

local function estaAparando(ctx: Ctx): boolean
	return estadoAcaoMaquina(ctx) == "Aparando"
		or ctx.modelo:GetAttribute(TiposNPC.Chaves.Estado) == TiposNPC.Estado.Aparando
end

-- =============================================================================
-- Sincronizacao Maquina canonica -> atributo NPC_Estado (para a View animar
-- as reacoes Aparado/Stunado/DefesaQuebrada/Defendendo).
-- =============================================================================

local function mapearEstadoMaquina(estadoAcao: string): string?
	if estadoAcao == "Stunado" then
		return TiposNPC.Estado.Stunado
	elseif estadoAcao == "Aparado" then
		return TiposNPC.Estado.Aparado
	elseif estadoAcao == "Aparando" then
		return TiposNPC.Estado.Aparando
	elseif estadoAcao == "DefesaQuebrada" then
		return TiposNPC.Estado.DefesaQuebrada
	elseif estadoAcao == "Atacando" then
		return TiposNPC.Estado.Atacando
	elseif estadoAcao == "Defendendo" then
		return TiposNPC.Estado.Defendendo
	end
	return nil
end

local iniciarBloqueio: (Ctx) -> ()
local tentarBloqueioPreditivo: (Ctx, Model, boolean?) -> ()
local tentarAtaqueRiposte: (Ctx) -> ()

local function instalarSincMaquina(ctx: Ctx, maq: any)
	if not maq or not maq.AoMudarEstadoAcao then
		return
	end
	-- IMPORTANTE: o callback recebe (novo, anterior) - a maquina chama
	-- callback(novoEstado, estadoAnterior).
	local disc = maq:AoMudarEstadoAcao(function(novo: string, anterior: string)
		if ctx.estado.destruido then
			return
		end
		if ctx.humanoide.Health <= 0 then
			setEstado(ctx, TiposNPC.Estado.Morto)
			return
		end



		-- Baiting/Perseguicao: apos sair de um ataque proprio, define o cooldown.
		-- Se o NPC acertou o golpe, reduz drasticamente o cooldown para continuar pressionando.
		if anterior == "Atacando" then
			local acertou = ctx.modelo:GetAttribute("NPC_AcertouCombo") == true
			local espera
			if acertou then
				espera = 0.2 + math.random() * 0.3
			else
				espera = ESPERA_BAITING_MIN + math.random() * (ESPERA_BAITING_MAX - ESPERA_BAITING_MIN)
			end
			ctx.estado.cooldownAtaquePersonagem = os.clock() + espera
		end
		local mapped = mapearEstadoMaquina(novo)
		if mapped then
			setEstado(ctx, mapped)
			-- Quando o NPC e interrompido, server para o ataque para nao competir
			-- com a animacao de reacao tocada pela View no cliente.
			if mapped == TiposNPC.Estado.Aparado then
				ctx.estado.bloqueandoAte = 0
				ctx.estado.bloqueioSeguraCombo = false
				ctx.estado.prepararParryAte = os.clock() + JANELA_PREPARO_APOS_APARADO
				ctx.estado.cooldownBloqueio = 0
				ctx.estado.cooldownPredicaoParry = 0
				ctx.humanoide.WalkSpeed = VELOCIDADE_APARANDO
				ControladorCombateNPC.PararAtaque(ctx.modelo)
				limparOrientacao(ctx)
			elseif mapped == TiposNPC.Estado.Stunado or mapped == TiposNPC.Estado.DefesaQuebrada then
				ctx.estado.bloqueandoAte = 0
				ctx.estado.stunadoAte = os.clock() + 0.05
				ctx.humanoide:Move(Vector3.zero, false)
				ctx.humanoide.WalkSpeed = 0
				ControladorCombateNPC.PararAtaque(ctx.modelo)
				limparOrientacao(ctx)
			end
			-- REQ 8: parry bem sucedido (estado Aparando) reseta o cooldown de
			-- bloqueio para que NPC possa aparar o proximo ataque imediatamente.
			if mapped == TiposNPC.Estado.Aparando then
				ctx.estado.bloqueandoAte = 0
				ctx.estado.bloqueioSeguraCombo = false
				ctx.estado.cooldownBloqueio = 0
				ctx.estado.cooldownPredicaoParry = 0
				tentarAtaqueRiposte(ctx)
			end
		elseif novo == "Nenhuma" then
			local atual = ctx.modelo:GetAttribute(TiposNPC.Chaves.Estado)
			if
				atual == TiposNPC.Estado.Aparado
				or atual == TiposNPC.Estado.Aparando
				or atual == TiposNPC.Estado.Stunado
				or atual == TiposNPC.Estado.DefesaQuebrada
				or atual == TiposNPC.Estado.Defendendo
			then
				local aindaBloqueando = maq.dados and maq.dados.bloqueando == true
				if aindaBloqueando and (atual == TiposNPC.Estado.Defendendo or atual == TiposNPC.Estado.Aparando) then
					return
				end

				setEstado(ctx, TiposNPC.Estado.Idle)
			end
		end
	end)
	if typeof(disc) == "function" then
		table.insert(ctx.conexoes :: any, disc)
	end
end

-- =============================================================================
-- REQ 7: subscricao a maquina do ALVO para detectar inicio de ataque e tentar
-- bloquear preemptivamente para dar parry.
-- =============================================================================

local function ehEstadoAtaque(estadoAcao: string): boolean
	return estadoAcao == "Atacando"
end

local function obterMaquinaAlvo(alvo: Model): any?
	local cs = obterCombateServidor()
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
	if not dados then
		return false
	end
	if dados.estadoAcao ~= "Atacando" then
		return false
	end
	local indice = dados.indiceCombo or 0
	return indice > 0 and indice < 4
end

local function registrarAtaqueAlvo(ctx: Ctx, alvo: Model, dados: any?)
	if not dados then
		return
	end
	local indice = dados.indiceCombo or 0
	local ultimoAtaque = math.max(dados.ultimoAtaque or 0, dados.ultimaContinuacaoCombo or 0)
	if indice == ctx.estado.ultimoIndiceComboAlvo and ultimoAtaque == ctx.estado.ultimoTempoAtaqueAlvo then
		return
	end
	ctx.estado.ultimoIndiceComboAlvo = indice
	ctx.estado.ultimoTempoAtaqueAlvo = ultimoAtaque
	tentarBloqueioPreditivo(ctx, alvo, false)
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
		if not ehEstadoAtaque(novo) then
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

function atualizarSubscricaoAlvo(ctx: Ctx, novoAlvo: Model?)
	if ctx.estado.alvoSubscrito == novoAlvo then
		return
	end
	if ctx.estado.desconectarAlvo then
		pcall(ctx.estado.desconectarAlvo)
		ctx.estado.desconectarAlvo = nil
	end
	ctx.estado.alvoSubscrito = novoAlvo
	ctx.estado.maquinaAlvoSubscrita = nil
	ctx.estado.ultimoIndiceComboAlvo = 0
	ctx.estado.ultimoTempoAtaqueAlvo = 0
	if novoAlvo then
		instalarSincAlvo(ctx, novoAlvo)
	end
end

local function registrarDanoRecebido(ctx: Ctx, atacante: Model)
	if ctx.estado.destruido or ctx.humanoide.Health <= 0 then
		return
	end
	if not ctx.hostil then
		return
	end
	if atacante == ctx.modelo then
		return
	end
	local atacanteValido = alvoDentroDoRaio(ctx, atacante, RAIO_DESAGGRO)
	if not atacanteValido then
		return
	end

	local alvoAtual = ctx.estado.alvoAtual
	if atacante == alvoAtual then
		ctx.estado.agressorCandidato = nil
		ctx.estado.hitsAgressorCandidato = 0
		ctx.estado.agressorCandidatoAte = 0
		return
	end

	local alvoAtualValido = alvoDentroDoRaio(ctx, alvoAtual, RAIO_DESEQUIPAR)
	if not alvoAtualValido then
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
	ctx.estado.agressorCandidatoAte = agora + JANELA_MEMORIA_AGRESSOR

	if (ctx.estado.hitsAgressorCandidato or 0) >= HITS_PARA_TROCAR_ALVO then
		definirAlvoFocado(ctx, atacante)
	end
end

local function instalarSincDanoRecebido(ctx: Ctx)
	local cs = obterCombateServidor()
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

local function obterAlcanceArma(ctx: Ctx): number?
	return ControladorCombateNPC.ObterAlcanceArmaEquipada(ctx.modelo)
end

-- =============================================================================
-- Movimento direcional. A orientacao visual para o alvo e renderizada no client
-- pela View do NPC para evitar torque fisico/replicacao causando pulinhos.
-- =============================================================================

-- Funções de orientação movidas para o topo do arquivo

local function multiplicadorAnimacaoPorWalkSpeed(velocidade: number, correndo: boolean): number
	local baseAnim
	if velocidade <= VELOCIDADE_BLOQUEANDO + 0.05 then
		baseAnim = ConfigCombate.ConfiguracaoGlobal.VelocidadeBaseAnimBloqueando or 6
	elseif correndo then
		baseAnim = ConfigCombate.ConfiguracaoGlobal.VelocidadeBaseAnimCorrendo or 21
	else
		baseAnim = ConfigCombate.ConfiguracaoGlobal.VelocidadeBaseAnimAndando or 15
	end
	if baseAnim <= 0 then
		return 1
	end
	local ratio = velocidade / baseAnim
	local delta = ratio - 1
	return math.max(0.3, 1 + delta * 1.05)
end

local function escolherAnimDirecional(
	worldDir: Vector3,
	lookDir: Vector3,
	correndo: boolean,
	velocidade: number
): (string, number)
	if worldDir.Magnitude < 0.05 then
		return "Idle", 1
	end
	local forward = Vector3.new(lookDir.X, 0, lookDir.Z)
	if forward.Magnitude < 0.05 then
		forward = Vector3.new(0, 0, -1)
	else
		forward = forward.Unit
	end
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local moveXZ = Vector3.new(worldDir.X, 0, worldDir.Z).Unit
	local dotForward = forward:Dot(moveXZ)
	local dotRight = right:Dot(moveXZ)
	local prefixo = if correndo then "Correndo" else "Andando"
	local velocidadeAnim = multiplicadorAnimacaoPorWalkSpeed(velocidade, correndo)

	local temLateral = math.abs(dotRight) > 0.3
	local temFrontal = math.abs(dotForward) > 0.3
	if temLateral then
		local indoParaDireita = dotRight > 0
		local indoParaFrente = dotForward > 0
		if temFrontal then
			if indoParaDireita then
				return if indoParaFrente then prefixo .. "Direita" else prefixo .. "Esquerda",
					if indoParaFrente then velocidadeAnim else -velocidadeAnim
			else
				return if indoParaFrente then prefixo .. "Esquerda" else prefixo .. "Direita",
					if indoParaFrente then velocidadeAnim else -velocidadeAnim
			end
		end
		return if indoParaDireita then prefixo .. "Direita" else prefixo .. "Esquerda", velocidadeAnim
	elseif dotForward < -0.1 then
		return prefixo, -velocidadeAnim
	else
		return prefixo, velocidadeAnim
	end
end

local function moverDirecaoMantendoOlhar(
	ctx: Ctx,
	alvoPos: Vector3,
	direcaoMundo: Vector3,
	velocidade: number,
	correndo: boolean
): string
	orientarParaAlvo(ctx, alvoPos)
	local dirPlana = Vector3.new(direcaoMundo.X, 0, direcaoMundo.Z)
	if dirPlana.Magnitude < 0.05 then
		ctx.humanoide:Move(Vector3.zero, false)
		ctx.humanoide.WalkSpeed = 0
		return "Idle"
	end
	local dirNorm = dirPlana.Unit
	ctx.humanoide.WalkSpeed = velocidade
	ctx.humanoide:Move(dirNorm, false)
	local pos = ctx.modelo:GetPivot().Position
	local lookPlano = Vector3.new(alvoPos.X - pos.X, 0, alvoPos.Z - pos.Z)
	local lookDir = if lookPlano.Magnitude > 0.01 then lookPlano.Unit else Vector3.new(0, 0, -1)
	local nomeAnim, velocidadeAnim = escolherAnimDirecional(dirNorm, lookDir, correndo, velocidade)
	ctx.estado.velocidadeAnimacaoLocomocao = velocidadeAnim
	return nomeAnim
end

local function pararMovimento(ctx: Ctx)
	ctx.humanoide:Move(Vector3.zero, false)
	ctx.humanoide.WalkSpeed = 0
end

local function moverParaFaixaDeAlcance(
	ctx: Ctx,
	pos: Vector3,
	alvoPos: Vector3,
	distanciaAtual: number,
	alcance: number,
	distanciaCorrer: number,
	dt: number
): (boolean, string?)
	local distanciaMinima = math.max(0.5, alcance - TOLERANCIA_ALCANCE)
	local distanciaMaxima = alcance + TOLERANCIA_ALCANCE
	local erro = 0
	local sentido = 0

	if distanciaAtual > distanciaMaxima then
		erro = distanciaAtual - distanciaMaxima
		sentido = 1
	elseif distanciaAtual < distanciaMinima then
		erro = distanciaMinima - distanciaAtual
		sentido = -1
	else
		pararMovimento(ctx)
		return false, nil
	end

	local dirRadial = alvoPos - pos
	dirRadial = Vector3.new(dirRadial.X, 0, dirRadial.Z)
	if dirRadial.Magnitude < 0.001 then
		pararMovimento(ctx)
		return false, nil
	end

	local direcaoMundo = if sentido > 0 then dirRadial.Unit else -dirRadial.Unit
	local correndo = sentido > 0 and distanciaAtual >= distanciaCorrer
	local velocidadeMaxima = if correndo then VELOCIDADE_CORRENDO else VELOCIDADE_ANDANDO
	local velocidade = math.min(velocidadeMaxima, (erro / math.max(dt, 0.05)) * 0.8)
	if velocidade < 0.05 then
		pararMovimento(ctx)
		return false, nil
	end
	local animLoco = moverDirecaoMantendoOlhar(ctx, alvoPos, direcaoMundo, velocidade, correndo)
	return true, animLoco
end

local function velocidadePlanaModelo(modelo: Model): number
	local hrp = modelo:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return 0
	end
	local vel = hrp.AssemblyLinearVelocity
	return Vector3.new(vel.X, 0, vel.Z).Magnitude
end

local function ambosParados(ctx: Ctx, alvo: Model): boolean
	local humAlvo = alvo:FindFirstChildOfClass("Humanoid")
	local alvoParado = velocidadePlanaModelo(alvo) < 0.8 and (not humAlvo or humAlvo.MoveDirection.Magnitude < 0.1)
	local npcParado = velocidadePlanaModelo(ctx.modelo) < 0.8 and ctx.humanoide.MoveDirection.Magnitude < 0.1
	return npcParado and alvoParado
end

local function tentarOrbitar(
	ctx: Ctx,
	alvo: Model,
	pos: Vector3,
	alvoPos: Vector3,
	distanciaAtual: number,
	alcance: number,
	agora: number
): (boolean, string?)
	if (ctx.estado.orbitandoAte or 0) > agora then
		local radial = pos - alvoPos
		radial = Vector3.new(radial.X, 0, radial.Z)
		if radial.Magnitude < 0.001 then
			return false, nil
		end

		local dirRadial = radial.Unit
		local sinal = ctx.estado.orbitaSinal or 1
		local tangente = Vector3.new(-dirRadial.Z, 0, dirRadial.X) * sinal
		local erroRadial = distanciaAtual - alcance
		local correcaoRadial = -dirRadial * math.clamp(erroRadial / TOLERANCIA_ALCANCE, -0.65, 0.65)
		local direcao = tangente + correcaoRadial
		local animLoco = moverDirecaoMantendoOlhar(ctx, alvoPos, direcao, VELOCIDADE_ORBITA, false)
		return true, animLoco
	end

	if (ctx.estado.proximaRolagemOrbita or 0) > agora then
		return false, nil
	end
	ctx.estado.proximaRolagemOrbita = agora + INTERVALO_ROLAGEM_ORBITA

	if not ambosParados(ctx, alvo) then
		return false, nil
	end
	if math.abs(distanciaAtual - alcance) > TOLERANCIA_ALCANCE then
		return false, nil
	end
	if math.random() > CHANCE_ORBITA_VERDADEIRO then
		return false, nil
	end

	ctx.estado.orbitandoAte = agora + DURACAO_ORBITA
	ctx.estado.orbitaSinal = if math.random() < 0.5 then -1 else 1
	return tentarOrbitar(ctx, alvo, pos, alvoPos, distanciaAtual, alcance, agora)
end

local function estadoPorAnimacaoLocomocao(nomeAnimacao: string): string
	if string.sub(nomeAnimacao, 1, 8) == "Correndo" then
		return TiposNPC.Estado.Correndo
	end
	return TiposNPC.Estado.Andando
end

-- =============================================================================
-- Bloqueio / Parry do NPC (delegado ao pipeline do player via
-- ControladorCombateNPC.Bloquear/PararBloqueio).
-- =============================================================================

local function pararBloqueio(ctx: Ctx)
	if (ctx.estado.bloqueandoAte or 0) <= 0 then
		return
	end
	ctx.estado.bloqueioToken = (ctx.estado.bloqueioToken or 0) + 1
	ctx.estado.bloqueandoAte = 0
	ctx.estado.bloqueioSeguraCombo = false
	ctx.estado.cooldownBloqueio = os.clock() + COOLDOWN_BLOQUEIO_NPC

	-- Delega ao pipeline do player para parar bloqueio naturalmente.
	ControladorCombateNPC.PararBloqueio(ctx.modelo)
end

function iniciarBloqueio(ctx: Ctx)
	if not lerFlag(ctx.modelo, TiposNPC.Chaves.PodeDefender, false) then
		return
	end
	if estaAparando(ctx) then
		return
	end
	local agora = os.clock()
	if (ctx.estado.cooldownBloqueio or 0) > agora then
		return
	end
	if ControladorCombateNPC.EstaAtacando(ctx.modelo) then
		return
	end

	-- Delega ao pipeline do player. O parry acontece naturalmente se o
	-- cooldown interno da MaquinaDeEstados permitir.
	local ok = ControladorCombateNPC.Bloquear(ctx.modelo)
	if not ok then
		return
	end

	local duracao = DURACAO_BLOQUEIO_MIN + math.random() * (DURACAO_BLOQUEIO_MAX - DURACAO_BLOQUEIO_MIN)
	ctx.estado.bloqueioToken = (ctx.estado.bloqueioToken or 0) + 1
	local token = ctx.estado.bloqueioToken
	ctx.estado.bloqueandoAte = agora + duracao
	ctx.estado.bloqueioSeguraCombo = false
	ctx.estado.cooldownBloqueio = agora + duracao + COOLDOWN_BLOQUEIO_NPC

	task.delay(duracao, function()
		if ctx.estado.destruido then
			return
		end
		if ctx.estado.bloqueioToken ~= token then
			return
		end
		if (ctx.estado.bloqueandoAte or 0) <= os.clock() + 0.001 and not ctx.estado.bloqueioSeguraCombo then
			pararBloqueio(ctx)
		end
	end)
end

function tentarBloqueioPreditivo(ctx: Ctx, alvo: Model, forcar: boolean?)
	if not lerFlag(ctx.modelo, TiposNPC.Chaves.PodeDefender, false) then
		return
	end
	local agora = os.clock()
	local emPreparoAposAparado = (ctx.estado.prepararParryAte or 0) > agora
	if not forcar and not emPreparoAposAparado and (ctx.estado.cooldownPredicaoParry or 0) > agora then
		return
	end
	ctx.estado.cooldownPredicaoParry = agora + COOLDOWN_PREDICAO_BLOQUEIO
	local token = (ctx.estado.predicaoToken or 0) + 1
	ctx.estado.predicaoToken = token
	task.delay(ATRASO_BLOQUEIO_PREDITIVO, function()
		if ctx.estado.destruido or ctx.humanoide.Health <= 0 then
			return
		end
		if ctx.estado.predicaoToken ~= token then
			return
		end
		if ctx.estado.alvoSubscrito ~= alvo and ctx.estado.alvoAtual ~= alvo then
			return
		end
		-- Levanta a guarda naturalmente. O parry acontece automaticamente
		-- pelo pipeline do player se o cooldown permitir.
		iniciarBloqueio(ctx)
	end)
end

function tentarAtaqueRiposte(ctx: Ctx)
	local token = (ctx.estado.riposteToken or 0) + 1
	ctx.estado.riposteToken = token
	task.delay(ATRASO_ATAQUE_APOS_PARRY, function()
		if ctx.estado.destruido or ctx.humanoide.Health <= 0 then
			return
		end
		if ctx.estado.riposteToken ~= token then
			return
		end
		if ControladorCombateNPC.EstaAtacando(ctx.modelo) or ControladorCombateNPC.EstaEquipando(ctx.modelo) then
			return
		end
		local alvoRef = ctx.estado.alvoAtual
		ControladorCombateNPC.Atacar(ctx.modelo, function(): boolean
			local vivo, hrp = alvoVivoComHRP(alvoRef)
			if not vivo or not hrp then
				return false
			end
			local alcance = obterAlcanceArma(ctx)
			if not alcance then
				return false
			end
			local d = (hrp.Position - ctx.modelo:GetPivot().Position).Magnitude
			return d <= alcance * 1.5
		end)
	end)
end

local function desengajar(ctx: Ctx, maq: any?)
	pararMovimento(ctx)
	limparOrientacao(ctx)
	ctx.humanoide.AutoRotate = true
	if ControladorCombateNPC.EstaArmaPronta(ctx.modelo) then
		ControladorCombateNPC.DesequiparArma(ctx.modelo)
		setModoCombateAttr(ctx, false)
		if maq and maq.DefinirModo then
			maq:DefinirModo("Base")
		end
	else
		ControladorCombateNPC.TocarLocomocao(ctx.modelo, "Idle")
		setEstado(ctx, TiposNPC.Estado.Idle)
	end
end

-- =============================================================================
-- Comportamento
-- =============================================================================

local Combate: Comportamento.Comportamento = {
	id = TiposNPC.Archetype.Combate,

	iniciar = function(ctx: Ctx)
		ctx.humanoide.JumpHeight = 7.2
		ctx.humanoide.WalkSpeed = 0
		-- A orientacao visual para o alvo e feita no client; o servidor so move.
		ctx.humanoide.AutoRotate = true
		ctx.estado.cooldownBloqueio = 0
		ctx.estado.bloqueandoAte = 0
		ctx.estado.stunadoAte = 0
		ctx.estado.cooldownAtaquePersonagem = 0
		ctx.estado.alvoAtual = nil
		ctx.estado.alvoSubscrito = nil
		ctx.estado.desconectarAlvo = nil
		ctx.estado.agressorCandidato = nil
		ctx.estado.hitsAgressorCandidato = 0
		ctx.estado.agressorCandidatoAte = 0
		ctx.estado.cooldownPredicaoParry = 0
		ctx.estado.velocidadeAnimacaoLocomocao = 1
		ctx.estado.destruido = false
		setEstado(ctx, TiposNPC.Estado.Idle)

		-- Inicializa controlador de combate (carrega anims + idle).
		ControladorCombateNPC.Iniciar(ctx.modelo)

		-- Maquina canonica: NPC participa do pipeline igual qualquer player.
		local cs = obterCombateServidor()
		if cs and cs.ObterMaquina then
			local ok, maq = pcall(cs.ObterMaquina, ctx.modelo)
			if ok and maq then
				ctx.estado.maquina = maq
				instalarSincMaquina(ctx, maq)
				if maq.DefinirModo then
					maq:DefinirModo("Base")
				end
			end
		end
		instalarSincDanoRecebido(ctx)

		-- Comeca SEM arma equipada (modo Base, anim Idle base sem postura combate).
		setModoCombateAttr(ctx, false)
	end,

	atualizar = function(ctx: Ctx, dt: number)
		if ctx.humanoide.Health <= 0 then
			setEstado(ctx, TiposNPC.Estado.Morto)
			return
		end

		local agora = os.clock()
		local maq = ctx.estado.maquina

		-- Stun: nao age agressivamente. Aparado e excecao: o NPC continua
		-- andando para frente enquanto a animacao de reacao toca.
		local emAparado = estaAparado(ctx)
		local stunadoLocal = (ctx.estado.stunadoAte or 0) > agora
		local stunadoMaq = (maq and maq.EstaStunado and maq:EstaStunado()) or false
		if (stunadoLocal or stunadoMaq) and not emAparado then
			pararMovimento(ctx)
			local podeDefender = lerFlag(ctx.modelo, TiposNPC.Chaves.PodeDefender, false)
			local cooldownBloqueioOK = (ctx.estado.cooldownBloqueio or 0) <= agora
			if podeDefender and cooldownBloqueioOK and math.random() < CHANCE_BLOQUEIO_POR_TICK then
				iniciarBloqueio(ctx)
			end
			return
		end

		-- Em curso de animacao de equipar/desequipar: aguarda terminar.
		if ControladorCombateNPC.EstaEquipando(ctx.modelo) then
			pararMovimento(ctx)
			return
		end

		-- NPC nao-hostil: parado em modo Base.
		if not ctx.hostil then
			desengajar(ctx, maq)
			return
		end

		local podeAndar = lerFlag(ctx.modelo, TiposNPC.Chaves.PodeAndar, true)
		local podeAtacar = lerFlag(ctx.modelo, TiposNPC.Chaves.PodeAtacar, true)

		-- Bloqueando: mantem postura, nao persegue (mas continua olhando alvo).
		-- Bloqueando: DefesaBlock agora usa weld ao HRP (igual player),
		-- segue a orientacao fisica do NPC automaticamente.
		if (ctx.estado.bloqueandoAte or 0) > agora then
			local alvoB = ctx.estado.alvoAtual
			local _, hrpB = alvoVivoComHRP(alvoB)
			if hrpB then
				orientarParaAlvo(ctx, hrpB.Position)
			end
			if alvoMantemComboLeve(ctx) then
				ctx.estado.bloqueioSeguraCombo = true
				ctx.estado.bloqueandoAte = math.max(ctx.estado.bloqueandoAte or 0, agora + 0.25)
			elseif ctx.estado.bloqueioSeguraCombo then
				pararBloqueio(ctx)
				return
			end
			ctx.humanoide:Move(Vector3.zero, false)
			ctx.humanoide.WalkSpeed = VELOCIDADE_BLOQUEANDO
			return
		end

		local alvo = encontrarAlvo(ctx)
		definirAlvoFocado(ctx, alvo)
		if not alvo then
			desengajar(ctx, maq)
			return
		end

		local _, alvoHRP = alvoVivoComHRP(alvo)
		if not alvoHRP then
			return
		end

		local pos = ctx.modelo:GetPivot().Position
		local distancia = (alvoHRP.Position - pos).Magnitude
		local maqAlvo = ctx.estado.maquinaAlvoSubscrita
		if maqAlvo and maqAlvo.dados and ehEstadoAtaque(maqAlvo.dados.estadoAcao) then
			registrarAtaqueAlvo(ctx, alvo, maqAlvo.dados)
		end

		-- Muito longe: desengaja.
		if distancia > RAIO_DESEQUIPAR then
			desengajar(ctx, maq)
			return
		end

		-- Dentro do raio de combate: garante arma equipada (toca anim Equipar uma vez).
		if not ControladorCombateNPC.EstaArmaPronta(ctx.modelo) then
			ControladorCombateNPC.EquiparArma(ctx.modelo)
			setModoCombateAttr(ctx, true)
			if maq and maq.DefinirModo then
				maq:DefinirModo("Punhos")
			end
			pararMovimento(ctx)
			orientarParaAlvo(ctx, alvoHRP.Position)
			return
		end

		-- Sempre olha o alvo a partir daqui.
		orientarParaAlvo(ctx, alvoHRP.Position)

		local alcance = obterAlcanceArma(ctx)
		if not alcance then
			pararMovimento(ctx)
			ControladorCombateNPC.TocarLocomocao(ctx.modelo, "Idle")
			setEstado(ctx, TiposNPC.Estado.Idle)
			return
		end
		local dentroDoAlcance = distancia <= (alcance + TOLERANCIA_ALCANCE)
		local distanciaCorrer = lerNumero(ctx.modelo, CHAVE_DISTANCIA_CORRER, DISTANCIA_CORRER_PADRAO)

		if dentroDoAlcance then
			if ctx.estado.chasingAlvo then
				ctx.estado.chasingAlvo = nil
				ctx.estado.cooldownAtaquePersonagem = 0
			end

			local npcParado = velocidadePlanaModelo(ctx.modelo) < 0.8 and ctx.humanoide.MoveDirection.Magnitude < 0.1
			if npcParado then
				if not ctx.estado.tempoParadoInicio then
					ctx.estado.tempoParadoInicio = agora
				elseif agora - ctx.estado.tempoParadoInicio >= 1.0 then
					ctx.estado.cooldownAtaquePersonagem = 0
				end
			else
				ctx.estado.tempoParadoInicio = nil
			end
		else
			ctx.estado.chasingAlvo = true
			ctx.estado.tempoParadoInicio = nil
		end

		if emAparado then
			if podeAndar then
				local dirParaAlvo = alvoHRP.Position - pos
				if dirParaAlvo.Magnitude > 0.001 then
					moverDirecaoMantendoOlhar(ctx, alvoHRP.Position, dirParaAlvo.Unit, VELOCIDADE_APARANDO, false)
				end
			else
				pararMovimento(ctx)
			end
			return
		end

		if estaAparando(ctx) then
			pararMovimento(ctx)
			return
		end

		-- Atacando: continua ajustando somente ate a faixa do alcance da arma.
		if ControladorCombateNPC.EstaAtacando(ctx.modelo) then
			if podeAndar then
				local moveu, animLoco =
					moverParaFaixaDeAlcance(ctx, pos, alvoHRP.Position, distancia, alcance, distanciaCorrer, dt)
				if moveu and animLoco then
					ControladorCombateNPC.TocarLocomocao(
						ctx.modelo,
						animLoco,
						ctx.estado.velocidadeAnimacaoLocomocao or 1
					)
				else
					ControladorCombateNPC.TocarLocomocao(ctx.modelo, "Idle")
				end
			else
				pararMovimento(ctx)
			end

			-- Tolerancia ampla para continuar combo durante ataque (o impulso pode deslocar levemente).
			local dentroCombo = distancia <= alcance * 1.5
			if dentroCombo and podeAtacar then
				local alvoRef: Model = alvo
				ControladorCombateNPC.Atacar(ctx.modelo, function(): boolean
					if not alvoRef or not alvoRef.Parent then
						return false
					end
					local h = alvoRef:FindFirstChildOfClass("Humanoid")
					if not h or h.Health <= 0 then
						return false
					end
					local p = alvoRef:FindFirstChild("HumanoidRootPart") :: BasePart?
					if not p then
						return false
					end
					local d = (p.Position - ctx.modelo:GetPivot().Position).Magnitude
					return d <= alcance * 1.5
				end)
			end

			return
		end

		if dentroDoAlcance then
			local podeDefender = lerFlag(ctx.modelo, TiposNPC.Chaves.PodeDefender, false)
			local cooldownBloqueioOK = (ctx.estado.cooldownBloqueio or 0) <= agora
			local cooldownAtaqueOK = (ctx.estado.cooldownAtaquePersonagem or 0) <= agora

			if podeDefender and cooldownBloqueioOK and math.random() < CHANCE_BLOQUEIO_POR_TICK then
				iniciarBloqueio(ctx)
				return
			end
			if podeAtacar and cooldownAtaqueOK then
				local alvoRef: Model = alvo
				local atacou = ControladorCombateNPC.Atacar(ctx.modelo, function(): boolean
					-- Combo segue enquanto o alvo permanece proximo (tolerancia ampla).
					if not alvoRef or not alvoRef.Parent then
						return false
					end
					local h = alvoRef:FindFirstChildOfClass("Humanoid")
					if not h or h.Health <= 0 then
						return false
					end
					local p = alvoRef:FindFirstChild("HumanoidRootPart") :: BasePart?
					if not p then
						return false
					end
					local d = (p.Position - ctx.modelo:GetPivot().Position).Magnitude
					return d <= alcance * 1.5
				end)
				if atacou then
					return
				end
			end
		end

		if podeAndar then
			local orbitando, animOrbita = tentarOrbitar(ctx, alvo, pos, alvoHRP.Position, distancia, alcance, agora)
			if orbitando and animOrbita then
				ControladorCombateNPC.TocarLocomocao(
					ctx.modelo,
					animOrbita,
					ctx.estado.velocidadeAnimacaoLocomocao or 1
				)
				setEstado(ctx, estadoPorAnimacaoLocomocao(animOrbita))
				return
			end
		end

		if podeAndar then
			local moveu, animLoco =
				moverParaFaixaDeAlcance(ctx, pos, alvoHRP.Position, distancia, alcance, distanciaCorrer, dt)
			if moveu and animLoco then
				ControladorCombateNPC.TocarLocomocao(ctx.modelo, animLoco, ctx.estado.velocidadeAnimacaoLocomocao or 1)
				setEstado(ctx, estadoPorAnimacaoLocomocao(animLoco))
			else
				ControladorCombateNPC.TocarLocomocao(ctx.modelo, "Idle")
				setEstado(ctx, TiposNPC.Estado.Idle)
			end
		else
			pararMovimento(ctx)
			ControladorCombateNPC.TocarLocomocao(ctx.modelo, "Idle")
			setEstado(ctx, TiposNPC.Estado.Idle)
		end
	end,

	destruir = function(ctx: Ctx)
		ctx.estado.destruido = true
		atualizarSubscricaoAlvo(ctx, nil)
		limparOrientacao(ctx)
		ControladorCombateNPC.PararBloqueio(ctx.modelo)
		ControladorCombateNPC.Destruir(ctx.modelo)
		ctx.estado.maquina = nil
		Comportamento.Helpers.LimparConexoes(ctx)
	end,
}

Comportamento.Registrar(Combate)

return Combate
