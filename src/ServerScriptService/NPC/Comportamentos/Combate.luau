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

local TiposNPC = require(
	ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC"):WaitForChild("Tipos")
)
local Comportamento = require(script.Parent:WaitForChild("Comportamento"))
local ConfigCombate = require(
	ReplicatedStorage:WaitForChild("Combate"):WaitForChild("Configuracoes"):WaitForChild("ConfigCombate")
)
local ControladorCombateNPC = require(
	ServerScriptService:WaitForChild("NPC"):WaitForChild("Combate"):WaitForChild("ControladorCombateNPC")
)

type Ctx = Comportamento.ContextoNPC

-- =============================================================================
-- Constantes
-- =============================================================================

local RAIO_AGGRO = 35
local RAIO_DESAGGRO = 60
local RAIO_DESEQUIPAR = 50
local DISTANCIA_ANDAR = 20

local VELOCIDADE_ANDANDO = ConfigCombate.ConfiguracaoGlobal.VelocidadeAndando or 12
local VELOCIDADE_CORRENDO = ConfigCombate.ConfiguracaoGlobal.VelocidadeCorrendo or 16
local VELOCIDADE_BLOQUEANDO = ConfigCombate.ConfiguracaoGlobal.VelocidadeBloqueando or 6
local VELOCIDADE_APARANDO = ConfigCombate.ConfiguracaoGlobal.VelocidadeAparando or 3

local DURACAO_BLOQUEIO_MIN = 1.1
local DURACAO_BLOQUEIO_MAX = 2.0
local CHANCE_BLOQUEIO_POR_TICK = 0.18
local COOLDOWN_BLOQUEIO_NPC = (ConfigCombate.ConfiguracaoGlobal.CooldownBloqueio or 0.5) + 1.5
local JANELA_PARRY_NPC = ConfigCombate.ConfiguracaoGlobal.JanelaParry or 0.2

-- Distancia unica que o NPC tenta manter do alvo. Sem "zona de conforto"
-- ampla: se esta mais longe, aproxima; se esta mais perto, recua.
local DISTANCIA_ALVO_PADRAO = 4.4
local TOLERANCIA_DISTANCIA_ALVO = 0.35
local MARGEM_ATAQUE_EXTRA = 0.75
local LIMITE_CANCELA_COMBO = 2.0

-- REQ 7: predicao de ataque do alvo. Cooldown curto entre tentativas de
-- bloqueio preditivo para nao spammar quando alvo encadeia varios ataques.
-- ATRASO_PARRY: aguarda 0.2s apos o alvo iniciar o ataque para sincronizar
-- o bloqueio com a janela de parry (a hitbox do alvo ainda nao chegou).
local CHANCE_PARRY_PREDITIVO = 0.7
local COOLDOWN_PREDICAO_PARRY = 0.4
local ATRASO_PARRY_PREDITIVO = 0.2

-- Baiting: apos cada ataque proprio, NPC fica 1.0-2.5s sem iniciar novo ataque,
-- esperando o alvo abrir guarda/atacar para conseguir parry. NPC continua
-- podendo bloquear/recuar/orbitar nesse intervalo.
local ESPERA_BAITING_MIN = 1.0
local ESPERA_BAITING_MAX = 2.5

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

local function encontrarAlvo(ctx: Ctx): Model?
	local pos = ctx.modelo:GetPivot().Position
	local alvo: Model? = nil
	local melhor = math.huge
	local raioBase = ctx.estado.alvoAtual and RAIO_DESAGGRO or RAIO_AGGRO
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
		if d < raioBase and d < melhor then
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
	elseif estadoAcao == "AtacandoLeve"
		or estadoAcao == "CarregandoPesado"
		or estadoAcao == "SoltandoPesado"
		or estadoAcao == "AtaquePesado" then
		return TiposNPC.Estado.Atacando
	elseif estadoAcao == "Defendendo" then
		return TiposNPC.Estado.Defendendo
	end
	return nil
end

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
		-- Baiting: apos sair de um ataque proprio, fica em cooldown sem iniciar
		-- novo ataque - espera o alvo atacar para tentar parry.
		if anterior == "AtacandoLeve" or anterior == "AtaquePesado" then
			local espera = ESPERA_BAITING_MIN
				+ math.random() * (ESPERA_BAITING_MAX - ESPERA_BAITING_MIN)
			ctx.estado.cooldownAtaquePersonagem = os.clock() + espera
		end
		local mapped = mapearEstadoMaquina(novo)
		if mapped then
			setEstado(ctx, mapped)
			-- Quando o NPC e interrompido, server para o ataque para nao competir
			-- com a animacao de reacao tocada pela View no cliente.
			if mapped == TiposNPC.Estado.Aparado then
				ctx.estado.bloqueandoAte = 0
				ctx.humanoide.WalkSpeed = VELOCIDADE_APARANDO
				ControladorCombateNPC.PararAtaque(ctx.modelo)
			elseif mapped == TiposNPC.Estado.Stunado
				or mapped == TiposNPC.Estado.DefesaQuebrada then
				ctx.estado.bloqueandoAte = 0
				ctx.estado.stunadoAte = os.clock() + 0.05
				ctx.humanoide:Move(Vector3.zero, false)
				ctx.humanoide.WalkSpeed = 0
				ControladorCombateNPC.PararAtaque(ctx.modelo)
			end
			-- REQ 8: parry bem sucedido (estado Aparando) reseta o cooldown de
			-- bloqueio para que NPC possa aparar o proximo ataque imediatamente.
			if mapped == TiposNPC.Estado.Aparando then
				ctx.estado.cooldownBloqueio = 0
				ctx.estado.cooldownPredicaoParry = 0
			end
		elseif novo == "Nenhuma" then
			local atual = ctx.modelo:GetAttribute(TiposNPC.Chaves.Estado)
			if atual == TiposNPC.Estado.Aparado
				or atual == TiposNPC.Estado.Aparando
				or atual == TiposNPC.Estado.Stunado
				or atual == TiposNPC.Estado.DefesaQuebrada
				or atual == TiposNPC.Estado.Defendendo then
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
	return estadoAcao == "AtacandoLeve"
		or estadoAcao == "CarregandoPesado"
		or estadoAcao == "SoltandoPesado"
		or estadoAcao == "AtaquePesado"
end

local iniciarBloqueio: (Ctx) -> ()

local function instalarSincAlvo(ctx: Ctx, alvo: Model)
	local cs = obterCombateServidor()
	if not cs or not cs.ObterMaquina then
		return
	end
	local ok, maqAlvo = pcall(cs.ObterMaquina, alvo)
	if not ok or not maqAlvo or not maqAlvo.AoMudarEstadoAcao then
		return
	end
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
		local agora = os.clock()
		if (ctx.estado.cooldownPredicaoParry or 0) > agora then
			return
		end
		ctx.estado.cooldownPredicaoParry = agora + COOLDOWN_PREDICAO_PARRY
		if math.random() > CHANCE_PARRY_PREDITIVO then
			return
		end
		-- Atrasa o bloqueio em 0.15s para alinhar com a janela de parry: o alvo
		-- ainda esta no windup quando bloqueamos, e a hitbox dele chega exatamente
		-- enquanto prontoParaAparar=true.
		task.delay(ATRASO_PARRY_PREDITIVO, function()
			if ctx.estado.destruido or ctx.humanoide.Health <= 0 then
				return
			end
			if ctx.estado.alvoSubscrito ~= alvo then
				return
			end
			iniciarBloqueio(ctx)
		end)
	end)
	if typeof(disc) == "function" then
		ctx.estado.desconectarAlvo = disc
	end
end

local function atualizarSubscricaoAlvo(ctx: Ctx, novoAlvo: Model?)
	if ctx.estado.alvoSubscrito == novoAlvo then
		return
	end
	if ctx.estado.desconectarAlvo then
		pcall(ctx.estado.desconectarAlvo)
		ctx.estado.desconectarAlvo = nil
	end
	ctx.estado.alvoSubscrito = novoAlvo
	if novoAlvo then
		instalarSincAlvo(ctx, novoAlvo)
	end
end

local function obterDistanciaAlvo(ctx: Ctx): number
	local v = ctx.modelo:GetAttribute("NPC_AlcanceArma")
	if typeof(v) == "number" and v > 0 then
		return v
	end
	return DISTANCIA_ALVO_PADRAO
end

-- =============================================================================
-- Orientacao e movimento direcional. O movimento real fica 100% no Humanoid
-- (igual jogador); a orientacao usa AlignOrientation para nao escrever CFrame no
-- HRP durante locomocao, evitando travadas/teleporte/interpolacao picada.
-- =============================================================================

local function obterHRP(ctx: Ctx): BasePart?
	return ctx.modelo:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function obterAttachmentOrientacao(hrp: BasePart): Attachment
	local rootAttachment = hrp:FindFirstChild("RootAttachment")
	if rootAttachment and rootAttachment:IsA("Attachment") then
		return rootAttachment
	end
	local existente = hrp:FindFirstChild("NPC_OrientacaoAttachment")
	if existente and existente:IsA("Attachment") then
		return existente
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "NPC_OrientacaoAttachment"
	attachment.Parent = hrp
	return attachment
end

local function obterAlignOrientacao(ctx: Ctx, hrp: BasePart): AlignOrientation
	local existente = ctx.estado.alignOrientacaoAlvo
	if typeof(existente) == "Instance" and existente:IsA("AlignOrientation") and existente.Parent == hrp then
		return existente
	end
	if typeof(existente) == "Instance" then
		existente:Destroy()
	end

	local align = Instance.new("AlignOrientation")
	align.Name = "NPC_OrientacaoAlvo"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = obterAttachmentOrientacao(hrp)
	align.RigidityEnabled = false
	align.Responsiveness = 22
	align.MaxAngularVelocity = math.rad(720)
	align.MaxTorque = 80000
	align.Parent = hrp
	ctx.estado.alignOrientacaoAlvo = align
	return align
end

local function orientarParaAlvo(ctx: Ctx, alvoPos: Vector3)
	local hrp = obterHRP(ctx)
	if not hrp then
		return
	end
	local pos = hrp.Position
	local olhar = Vector3.new(alvoPos.X, pos.Y, alvoPos.Z)
	local dir = olhar - pos
	if dir.Magnitude < 0.01 then
		return
	end
	local align = obterAlignOrientacao(ctx, hrp)
	align.CFrame = CFrame.lookAt(pos, olhar)
	align.Enabled = true
end

local function limparOrientacao(ctx: Ctx)
	local existente = ctx.estado.alignOrientacaoAlvo
	if typeof(existente) == "Instance" then
		existente:Destroy()
	end
	ctx.estado.alignOrientacaoAlvo = nil
end

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
				return if indoParaFrente then prefixo .. "Direita" else prefixo .. "Esquerda", if indoParaFrente then velocidadeAnim else -velocidadeAnim
			else
				return if indoParaFrente then prefixo .. "Esquerda" else prefixo .. "Direita", if indoParaFrente then velocidadeAnim else -velocidadeAnim
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

-- =============================================================================
-- Bloqueio / Parry do NPC (espelhado na MaquinaDeEstados canonica).
-- =============================================================================

local function definirEstadoBloqueioMaquina(ctx: Ctx, bloqueando: boolean, prontoParry: boolean)
	local maq = ctx.estado.maquina
	if not maq or not maq.dados then
		return
	end
	maq.dados.bloqueando = bloqueando
	maq.dados.prontoParaAparar = prontoParry
end

function iniciarBloqueio(ctx: Ctx)
	if not lerFlag(ctx.modelo, TiposNPC.Chaves.PodeDefender, false) then
		return
	end
	if estaAparado(ctx) then
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
	-- Nao gateamos por stunadoAte: REQ 1 permite bloquear durante o stun.

	local duracao = DURACAO_BLOQUEIO_MIN + math.random() * (DURACAO_BLOQUEIO_MAX - DURACAO_BLOQUEIO_MIN)
	local podeParry = lerFlag(ctx.modelo, TiposNPC.Chaves.PodeParry, false)

	ctx.estado.bloqueandoAte = agora + duracao
	ctx.estado.cooldownBloqueio = agora + duracao + COOLDOWN_BLOQUEIO_NPC
	ctx.humanoide.WalkSpeed = VELOCIDADE_BLOQUEANDO
	setEstado(ctx, TiposNPC.Estado.Defendendo)
	definirEstadoBloqueioMaquina(ctx, true, podeParry)

	if podeParry then
		local fimJanela = agora + JANELA_PARRY_NPC
		task.delay(JANELA_PARRY_NPC, function()
			if ctx.estado.destruido then
				return
			end
			if (ctx.estado.bloqueandoAte or 0) >= fimJanela then
				definirEstadoBloqueioMaquina(ctx, true, false)
			end
		end)
	end

	task.delay(duracao, function()
		if ctx.estado.destruido then
			return
		end
		if (ctx.estado.bloqueandoAte or 0) <= os.clock() + 0.001 then
			ctx.estado.bloqueandoAte = 0
			definirEstadoBloqueioMaquina(ctx, false, false)
			if ctx.humanoide.Health > 0 then
				setEstado(ctx, TiposNPC.Estado.Idle)
			end
		end
	end)
end

local function desengajar(ctx: Ctx, maq: any?)
	pararMovimento(ctx)
	limparOrientacao(ctx)
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
		-- NPC sempre olha para o alvo - rotacao gerenciada manualmente.
		ctx.humanoide.AutoRotate = false
		ctx.estado.cooldownBloqueio = 0
		ctx.estado.bloqueandoAte = 0
		ctx.estado.stunadoAte = 0
		ctx.estado.cooldownAtaquePersonagem = 0
		ctx.estado.alvoAtual = nil
		ctx.estado.alvoSubscrito = nil
		ctx.estado.desconectarAlvo = nil
		ctx.estado.cooldownPredicaoParry = 0
		ctx.estado.orbitarAte = 0
		ctx.estado.proximoOrbit = 0
		ctx.estado.orbitSinal = 1
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

		-- Comeca SEM arma equipada (modo Base, anim Idle base sem postura combate).
		setModoCombateAttr(ctx, false)
	end,

	atualizar = function(ctx: Ctx, _dt: number)
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

		-- Bloqueando: mantem postura, nao persegue (mas continua olhando alvo).
		if (ctx.estado.bloqueandoAte or 0) > agora then
			local alvoB = ctx.estado.alvoAtual
			local _, hrpB = alvoVivoComHRP(alvoB)
			if hrpB then
				orientarParaAlvo(ctx, hrpB.Position)
			end
			ctx.humanoide:Move(Vector3.zero, false)
			ctx.humanoide.WalkSpeed = VELOCIDADE_BLOQUEANDO
			return
		end

		local alvo = encontrarAlvo(ctx)
		ctx.estado.alvoAtual = alvo
		atualizarSubscricaoAlvo(ctx, alvo)
		if not alvo then
			desengajar(ctx, maq)
			ctx.modelo:SetAttribute(TiposNPC.Chaves.AlvoRef, 0)
			return
		end

		local _, alvoHRP = alvoVivoComHRP(alvo)
		if not alvoHRP then
			return
		end

		local player = Players:GetPlayerFromCharacter(alvo)
		ctx.modelo:SetAttribute(TiposNPC.Chaves.AlvoRef, player and player.UserId or 0)

		local pos = ctx.modelo:GetPivot().Position
		local distancia = (alvoHRP.Position - pos).Magnitude

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

		-- Distancia unica alvo: manter X studs entre NPC e alvo.
		local distanciaAlvo = obterDistanciaAlvo(ctx)
		local distMin = math.max(0.5, distanciaAlvo - TOLERANCIA_DISTANCIA_ALVO)
		local distMax = distanciaAlvo + TOLERANCIA_DISTANCIA_ALVO
		local distAtaque = distanciaAlvo + MARGEM_ATAQUE_EXTRA

		if emAparado then
			if podeAndar then
				local dirParaAlvo = alvoHRP.Position - pos
				if dirParaAlvo.Magnitude > 0.001 then
					moverDirecaoMantendoOlhar(
						ctx,
						alvoHRP.Position,
						dirParaAlvo.Unit,
						VELOCIDADE_APARANDO,
						false
					)
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

		-- Atacando: NPC pode CONTINUAR atacando enquanto recua se estiver muito perto;
		-- so para o ataque se sair claramente da zona de conforto (verificarAlvo no
		-- AtacarLeve ja faz esse cancelamento via callback).
		if ControladorCombateNPC.EstaAtacando(ctx.modelo) then
			if podeAndar then
				local dirMovimento: Vector3? = nil
				if distancia < distMin then
					dirMovimento = pos - alvoHRP.Position
				elseif distancia > distMax then
					dirMovimento = alvoHRP.Position - pos
				end
				if dirMovimento and dirMovimento.Magnitude > 0.001 then
					local animLoco = moverDirecaoMantendoOlhar(
						ctx,
						alvoHRP.Position,
						dirMovimento.Unit,
						VELOCIDADE_BLOQUEANDO,
						false
					)
					ControladorCombateNPC.TocarLocomocao(
						ctx.modelo,
						animLoco,
						ctx.estado.velocidadeAnimacaoLocomocao or 1
					)
				else
					pararMovimento(ctx)
				end
			else
				pararMovimento(ctx)
			end
			return
		end

		-- Mantem exatamente a distancia alvo: aproxima ou recua.
		if distancia > distMax then
			if podeAndar then
				local correndo = distancia > DISTANCIA_ANDAR
				local velocidade = if correndo then VELOCIDADE_CORRENDO else VELOCIDADE_ANDANDO
				local estadoLoco = if correndo then TiposNPC.Estado.Correndo else TiposNPC.Estado.Andando
				local dirParaAlvo = (alvoHRP.Position - pos)
				if dirParaAlvo.Magnitude > 0.001 then
					local animLoco = moverDirecaoMantendoOlhar(
						ctx,
						alvoHRP.Position,
						dirParaAlvo.Unit,
						velocidade,
						correndo
					)
					ControladorCombateNPC.TocarLocomocao(
						ctx.modelo,
						animLoco,
						ctx.estado.velocidadeAnimacaoLocomocao or 1
					)
					setEstado(ctx, estadoLoco)
				end
			else
				pararMovimento(ctx)
				ControladorCombateNPC.TocarLocomocao(ctx.modelo, "Idle")
				setEstado(ctx, TiposNPC.Estado.Idle)
			end
		elseif distancia < distMin then
			if podeAndar then
				local dirParaTras = pos - alvoHRP.Position
				if dirParaTras.Magnitude > 0.001 then
					local animLoco = moverDirecaoMantendoOlhar(
						ctx,
						alvoHRP.Position,
						dirParaTras.Unit,
						VELOCIDADE_ANDANDO,
						false
					)
					ControladorCombateNPC.TocarLocomocao(
						ctx.modelo,
						animLoco,
						ctx.estado.velocidadeAnimacaoLocomocao or 1
					)
					setEstado(ctx, TiposNPC.Estado.Andando)
				end
			else
				pararMovimento(ctx)
				ControladorCombateNPC.TocarLocomocao(ctx.modelo, "Idle")
				setEstado(ctx, TiposNPC.Estado.Idle)
			end
		else
			-- Na distancia alvo: parado, pronto para atacar/bloquear.
			pararMovimento(ctx)
			ControladorCombateNPC.TocarLocomocao(ctx.modelo, "Idle")
			setEstado(ctx, TiposNPC.Estado.Idle)

			local podeAtacar = lerFlag(ctx.modelo, TiposNPC.Chaves.PodeAtacar, true)
			local podeDefender = lerFlag(ctx.modelo, TiposNPC.Chaves.PodeDefender, false)
			local cooldownBloqueioOK = (ctx.estado.cooldownBloqueio or 0) <= agora
			local cooldownAtaqueOK = (ctx.estado.cooldownAtaquePersonagem or 0) <= agora

			if podeDefender and cooldownBloqueioOK and math.random() < CHANCE_BLOQUEIO_POR_TICK then
				iniciarBloqueio(ctx)
				return
			end
			if podeAtacar and cooldownAtaqueOK then
				local alvoRef: Model = alvo
				local limiteAtaque = distAtaque + LIMITE_CANCELA_COMBO
				ControladorCombateNPC.AtacarLeve(ctx.modelo, function(): boolean
					-- REQ 4: combo segue ate o final, mas aborta se alvo morreu/saiu de alcance.
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
					return d <= limiteAtaque
				end)
			end
		end
	end,

	destruir = function(ctx: Ctx)
		ctx.estado.destruido = true
		atualizarSubscricaoAlvo(ctx, nil)
		limparOrientacao(ctx)
		definirEstadoBloqueioMaquina(ctx, false, false)
		ControladorCombateNPC.Destruir(ctx.modelo)
		ctx.estado.maquina = nil
		Comportamento.Helpers.LimparConexoes(ctx)
	end,
}

Comportamento.Registrar(Combate)

return Combate
