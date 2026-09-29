--!strict

--[[
	Script: Combate.luau
	Caminho: src/StarterPlayer/StarterPlayerScripts/NPC/Views
	Responsabilidade: View completa do NPC de combate (cliente-fat). Toca todas
	    as animacoes localmente, clona o WeaponModel visual a partir de cache com
	    Motor6D local, orienta torso e cabeca para o alvo e roda a hitbox local
	    quando o jogador local e o alvo. O servidor nao replica visual nenhum.
	Uso: ModuleScript; auto-registra em ViewBase.
	Nao faz: Nao aplica dano, nao decide estado e nao move o Humanoid.
	Funcoes principais: iniciar, atualizar, aoLOD, destruir

	Correcoes:
	- tocarEquip sem animacao disponivel agora cria a arma e confirma ao
	  servidor (antes saia calado e deixava o NPC preso em "equipando").
	- equipArmaCriada e resetado ao trocar de acao e ao cair para LOD Distante.
	- equipExecutadoTick e limpo no LOD Distante (antes bloqueava o replay da
	  animacao de equipar ao reaproximar).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CatalogoItens =
	require(ReplicatedStorage:WaitForChild("Dados"):WaitForChild("Itens"):WaitForChild("CatalogoItens"))
local CacheArmas = require(ReplicatedStorage:WaitForChild("SistemaItens"):WaitForChild("CacheArmasVisuais"))

local PastaNPC = ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC")
local TiposNPC = require(PastaNPC:WaitForChild("Tipos"))
local RegistroNPC = require(PastaNPC:WaitForChild("RegistroNPC"))

local PastaCombate = ReplicatedStorage:WaitForChild("Combate")
local IdsCombate = require(PastaCombate:WaitForChild("Animacoes"):WaitForChild("IdsAnimacoesCombate"))
local Modulo_Hitbox = require(PastaCombate:WaitForChild("Hitbox"))
local Timings = require(PastaCombate:WaitForChild("Configuracoes"):WaitForChild("TimingsAtaqueNPC"))
local Modulo_Combo = require(PastaCombate:WaitForChild("Dominio"):WaitForChild("ComboCombate"))
local IdsGerais =
	require(ReplicatedStorage:WaitForChild("Jogador"):WaitForChild("Animacoes"):WaitForChild("IdsAnimacoesGerais"))

local ViewBase = require(script.Parent:WaitForChild("ViewBase"))

local PLAYER_LOCAL = Players.LocalPlayer
local Remotos = ReplicatedStorage:WaitForChild("Remotos")
local NPC_HitReport = Remotos:WaitForChild("NPC_HitReport") :: RemoteEvent
local EquipAnimacaoTerminou = Remotos:WaitForChild("EquipAnimacaoTerminou") :: RemoteEvent

type Ctx = ViewBase.ContextoView

-- Estado tipado. Antes era um saco de strings montadas em runtime
-- ("WeaponModelLocal" .. mao), onde um typo virava bug silencioso.
type EstadoCombate = {
	rootJoint: Motor6D?,
	rootJointC0Base: CFrame?,
	neckJoint: Motor6D?,
	yawSuavizado: number?,

	alvoRef: number?,
	alvoHrp: BasePart?,

	armaVisualId: string?,
	armaRight: Model?,
	armaLeft: Model?,

	estadoTocando: string?,
	acaoTocando: string?,
	acaoTick: number?,

	hitboxRight: any,
	hitboxLeft: any,
	swingToken: number?,
	markerDisparado: boolean?,
	limpezaMarkers: (() -> ())?,
	conexaoStopped: RBXScriptConnection?,

	equipToken: number?,
	equipStoppedConn: RBXScriptConnection?,
	equipEndedConn: RBXScriptConnection?,
	equipMarkerConn: RBXScriptConnection?,
	equipArmaCriada: boolean?,
	equipNomeAtual: string?,
	equipExecutadoTick: number?,
}

local function est(ctx: Ctx): EstadoCombate
	return (ctx.estado :: any) :: EstadoCombate
end

local Punhos = (IdsCombate :: any).Punhos and (IdsCombate :: any).Punhos.animacoes or {}
local BaseAnims = IdsGerais.Base.animacoes

local FADE_LOCOMOCAO = 0.18
local FADE_REACAO_IN = 0.14
local FADE_REACAO_OUT = 0.18
local FADE_REACAO_PARA_ATAQUE = 0.16
local FADE_ENTRADA_ATAQUE = 0.16
local FADE_SAIDA_ATAQUE = 0.22
local FADE_EQUIP = 0.10

-- Quanto maior, mais rapido o torso alcanca o alvo. 12 e um meio termo entre
-- "robotico" (infinito, que era o comportamento antigo) e "molenga".
local VELOCIDADE_SUAVIZACAO_YAW = 12
-- Folga dada aos markers da animacao antes do fallback por tempo assumir.
local BUFFER_FALLBACK_HITBOX = 0.15

local SUFIXO_PARA_BRACO = { Right = "Right Arm", Left = "Left Arm" }
local SUFIXO_PARA_SLOT = { Right = "RightArm", Left = "LeftArm" }

local LOCOMOCAO_NAMES: { [string]: boolean } = {
	Idle = true,
	Andando = true,
	AndandoDireita = true,
	AndandoEsquerda = true,
	Correndo = true,
	CorrendoDireita = true,
	CorrendoEsquerda = true,
}

local aplicarLocomocao: (ctx: Ctx) -> ()

-- =============================================================================
-- Animacoes: resolucao de id e invalidacao seletiva de tracks.
-- =============================================================================

local function obterAnimacoesModo(ctx: Ctx): { [string]: string }
	if ctx.modelo:GetAttribute(TiposNPC.Chaves.ArmaPronta) ~= true then
		return BaseAnims
	end
	local idArma = ctx.modelo:GetAttribute(TiposNPC.Chaves.ArmaEquipadaId) :: string?
	if not idArma or idArma == "" then
		return BaseAnims
	end
	local dados = CatalogoItens.Get(idArma)
	local modoData = dados and dados.ModoAnimacao and (IdsCombate :: any)[dados.ModoAnimacao]
	return (modoData and modoData.animacoes) or BaseAnims
end

local function idParaTrack(ctx: Ctx, nome: string): string?
	local armaPronta = ctx.modelo:GetAttribute(TiposNPC.Chaves.ArmaPronta) == true
	local ehTransicao = nome == "Equipar" or nome == "Desequipar"
	local idArma = ctx.modelo:GetAttribute(TiposNPC.Chaves.ArmaEquipadaId) :: string?

	if not ((armaPronta or ehTransicao) and idArma and idArma ~= "") then
		return BaseAnims[nome]
	end

	local dados = CatalogoItens.Get(idArma)
	local modo = (dados and dados.ModoAnimacao) or "Punhos"
	local modoData = (IdsCombate :: any)[modo]
	local id = modoData and modoData.animacoes and modoData.animacoes[nome]
	if id then
		return id
	end
	return Punhos[nome]
end

local function descartarTrack(ctx: Ctx, nome: string, fade: number)
	local track = ctx.tracks[nome]
	if not track then
		return
	end
	pcall(function()
		track:Stop(fade)
		track:Destroy()
	end)
	ctx.tracks[nome] = nil
end

local function carregarTrack(ctx: Ctx, nome: string): AnimationTrack?
	local id = idParaTrack(ctx, nome)
	if not id then
		return nil
	end

	local trackExistente = ctx.tracks[nome]
	if trackExistente then
		local idAtual = trackExistente.Animation and trackExistente.Animation.AnimationId
		if idAtual ~= id then
			descartarTrack(ctx, nome, 0)
		end
	end

	return ViewBase.CarregarTrack(ctx, nome, id)
end

-- Substitui o antigo limparTracks(), que apagava TUDO ao trocar de arma e ja
-- tinha quebrado o hitbox uma vez ao destruir a track de ataque recem criada.
local function reconciliarTracks(ctx: Ctx)
	for nome, track in ctx.tracks do
		local novoId = idParaTrack(ctx, nome)
		local idAtual = track.Animation and track.Animation.AnimationId
		if novoId ~= idAtual then
			descartarTrack(ctx, nome, FADE_LOCOMOCAO)
		end
	end
end

local function pararLocomocaoExceto(ctx: Ctx, manter: AnimationTrack?)
	for nome, t in ctx.tracks do
		if LOCOMOCAO_NAMES[nome] and t ~= manter and t.IsPlaying then
			t:Stop(FADE_LOCOMOCAO)
		end
	end
end

local function pararTodasLocomocao(ctx: Ctx)
	pararLocomocaoExceto(ctx, nil)
end

local function tocarLocomocao(ctx: Ctx, nome: string, velocidade: number?)
	local t = carregarTrack(ctx, nome)
	if not t then
		return
	end
	pararLocomocaoExceto(ctx, t)
	t.Looped = true
	if not t.IsPlaying then
		t:Play(FADE_LOCOMOCAO)
	end
	t:AdjustSpeed(velocidade or 1)
end

-- =============================================================================
-- Alvo em cache. Antes isso era um GetDescendants() por frame, por NPC.
-- =============================================================================

local function obterAlvoHrp(ctx: Ctx): BasePart?
	local e = est(ctx)
	local ref = ctx.modelo:GetAttribute(TiposNPC.Chaves.AlvoRef)

	if typeof(ref) ~= "number" or ref == 0 then
		e.alvoRef = nil
		e.alvoHrp = nil
		return nil
	end

	local cache = e.alvoHrp
	if e.alvoRef == ref and cache and cache.Parent then
		return cache
	end

	local modelo: Model? = nil
	if ref > 0 then
		local player = Players:GetPlayerByUserId(ref)
		modelo = player and player.Character or nil
	else
		modelo = RegistroNPC.Obter(-ref)
	end

	e.alvoRef = ref
	e.alvoHrp = modelo and modelo:FindFirstChild("HumanoidRootPart") :: BasePart? or nil
	return e.alvoHrp
end

local function ehAlvoLocal(ctx: Ctx): boolean
	local ref = ctx.modelo:GetAttribute(TiposNPC.Chaves.AlvoRef)
	return typeof(ref) == "number" and ref == PLAYER_LOCAL.UserId
end

-- =============================================================================
-- Orientacao visual. Roda no render step logo depois do Character, para
-- sobrescrever o que o Animator acabou de aplicar no mesmo frame.
-- =============================================================================

local function normAngulo(a: number): number
	return ((a + math.pi) % (2 * math.pi)) - math.pi
end

local function yawDoVetor(dir: Vector3): number
	return math.atan2(-dir.X, -dir.Z)
end

local function obterRootJoint(ctx: Ctx): Motor6D?
	local e = est(ctx)
	local existente = e.rootJoint
	if existente and existente.Parent then
		return existente
	end

	local hrp = ctx.modelo:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return nil
	end
	local torso = ctx.modelo:FindFirstChild("Torso") :: BasePart?
	for _, child in hrp:GetChildren() do
		if child:IsA("Motor6D") and child.Part0 == hrp and (not torso or child.Part1 == torso) then
			e.rootJoint = child
			if not e.rootJointC0Base then
				e.rootJointC0Base = child.C0
			end
			return child
		end
	end
	return nil
end

local function obterNeckJoint(ctx: Ctx): Motor6D?
	local e = est(ctx)
	local existente = e.neckJoint
	if existente and existente.Parent then
		return existente
	end
	local neck = ctx.modelo:FindFirstChild("Neck", true)
	if neck and neck:IsA("Motor6D") then
		e.neckJoint = neck
		return neck
	end
	return nil
end

local function atualizarOrientacaoVisual(ctx: Ctx, dt: number)
	if ctx.lod == TiposNPC.LOD.Distante then
		return
	end

	local joint = obterRootJoint(ctx)
	local hrp = ctx.modelo:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not joint or not hrp then
		return
	end

	local e = est(ctx)
	local baseC0 = e.rootJointC0Base
	if typeof(baseC0) ~= "CFrame" then
		baseC0 = joint.C0
		e.rootJointC0Base = baseC0
	end

	local alvoHrp = obterAlvoHrp(ctx)
	local desejado = 0
	if alvoHrp then
		local dx = alvoHrp.Position.X - hrp.Position.X
		local dz = alvoHrp.Position.Z - hrp.Position.Z
		if (dx * dx + dz * dz) > 0.0025 then
			desejado = normAngulo(yawDoVetor(Vector3.new(dx, 0, dz)) - yawDoVetor(hrp.CFrame.LookVector))
		end
	end

	-- Lerp exponencial, independente de framerate. O campo antigo
	-- jointYawSuavizado recebia o valor cru: suavizacao so no nome.
	local prevYaw = e.yawSuavizado
	local atual: number
	if prevYaw == nil then
		atual = desejado
	else
		atual = normAngulo(prevYaw + normAngulo(desejado - prevYaw) * (1 - math.exp(-VELOCIDADE_SUAVIZACAO_YAW * dt)))
	end
	e.yawSuavizado = atual

	joint.C0 = CFrame.Angles(0, atual, 0) * (baseC0 :: CFrame)

	-- Cabeca so no LOD Proximo: ninguem percebe a distancia media.
	if ctx.lod ~= TiposNPC.LOD.Proximo or not alvoHrp then
		return
	end

	local neck = obterNeckJoint(ctx)
	local head = ctx.modelo:FindFirstChild("Head") :: BasePart?
	local torso = ctx.modelo:FindFirstChild("Torso") :: BasePart?
	if not neck or not head or not torso then
		return
	end

	local dir = alvoHrp.Position - head.Position
	if dir.Magnitude <= 0.1 then
		return
	end

	local relativeYaw = normAngulo(yawDoVetor(dir) - yawDoVetor(torso.CFrame.LookVector))
	-- Preserva pitch e roll do animador, sobrescreve so o yaw.
	local rx, ry = neck.Transform:ToEulerAnglesXYZ()
	neck.Transform = CFrame.Angles(rx, ry, relativeYaw)
end

local function restaurarOrientacaoVisual(ctx: Ctx)
	local e = est(ctx)
	local joint = e.rootJoint
	local baseC0 = e.rootJointC0Base
	if joint and joint.Parent and typeof(baseC0) == "CFrame" then
		joint.C0 = baseC0
	end

	local neck = e.neckJoint
	if neck and neck.Parent then
		neck.Transform = CFrame.new()
	end

	e.rootJoint = nil
	e.rootJointC0Base = nil
	e.neckJoint = nil
	e.yawSuavizado = nil
end

-- =============================================================================
-- WeaponModel local. Nada disso replica: cada cliente monta o seu.
-- =============================================================================

local function campoArma(mao: string): string
	return if mao == "Right" then "armaRight" else "armaLeft"
end

local function destruirArmaMao(ctx: Ctx, mao: string)
	local e = est(ctx)
	local existente = if mao == "Right" then e.armaRight else e.armaLeft
	if existente then
		existente:Destroy()
	end
	if mao == "Right" then
		e.armaRight = nil
	else
		e.armaLeft = nil
	end

	local nomeBraco = SUFIXO_PARA_BRACO[mao]
	local arm = nomeBraco and ctx.modelo:FindFirstChild(nomeBraco) :: BasePart?
	if arm then
		local j = arm:FindFirstChild(SUFIXO_PARA_SLOT[mao] .. "_WeaponJointLocal")
		if j then
			j:Destroy()
		end
	end
end

local function destruirArmasLocais(ctx: Ctx)
	destruirArmaMao(ctx, "Right")
	destruirArmaMao(ctx, "Left")
end

local function criarArmaMao(ctx: Ctx, idArma: string?, mao: string)
	local nomeBraco = SUFIXO_PARA_BRACO[mao]
	local armPart = nomeBraco and ctx.modelo:FindFirstChild(nomeBraco) :: BasePart?
	if not armPart then
		return
	end

	destruirArmaMao(ctx, mao)

	-- Template ja vem limpo e normalizado do cache.
	local clone = CacheArmas.Clonar(idArma) or CacheArmas.Clonar("punhos")
	if not clone then
		return
	end

	local handle = clone:FindFirstChild("Handle") :: BasePart?
	if not handle then
		clone:Destroy()
		return
	end

	clone.Name = "WeaponModelLocal" .. mao
	clone.Parent = ctx.modelo

	local joint = Instance.new("Motor6D")
	joint.Name = SUFIXO_PARA_SLOT[mao] .. "_WeaponJointLocal"
	joint.Part0 = armPart
	joint.Part1 = handle
	-- CFrame estatico relativo ao braco: ler o CFrame ja animado introduziria
	-- offset errado.
	joint.C0 = CFrame.new(0, -1, 0) * CFrame.Angles(math.rad(-90), 0, 0)
	joint.C1 = CFrame.new()
	joint.Parent = armPart

	local e = est(ctx)
	if mao == "Right" then
		e.armaRight = clone
	else
		e.armaLeft = clone
	end
end

local function criarArmasLocais(ctx: Ctx)
	local idArma = ctx.modelo:GetAttribute(TiposNPC.Chaves.ArmaEquipadaId) :: string?
	local dados = idArma and idArma ~= "" and CatalogoItens.Get(idArma) or nil
	local modo = (dados and dados.ModoAnimacao) or "Punhos"

	criarArmaMao(ctx, idArma, "Right")
	if modo == "Punhos" or modo == "Dupla" or modo == "UmaMaoDupla" then
		criarArmaMao(ctx, idArma, "Left")
	else
		destruirArmaMao(ctx, "Left")
	end
end

-- =============================================================================
-- Hitbox local: so o cliente do alvo roda, e reporta ao servidor.
-- =============================================================================

local function campoHitbox(mao: string): string
	return if mao == "Right" then "hitboxRight" else "hitboxLeft"
end

local function destruirHitboxMao(ctx: Ctx, mao: string)
	local e = est(ctx) :: any
	local campo = campoHitbox(mao)
	if e[campo] then
		Modulo_Hitbox.DestruirHitbox(e[campo])
	end
	e[campo] = nil
end

local function destruirHitboxes(ctx: Ctx)
	destruirHitboxMao(ctx, "Right")
	destruirHitboxMao(ctx, "Left")
end

local function maoOposta(mao: string): string
	return if mao == "Right" then "Left" else "Right"
end

-- A animacao de punhos R6 comeca o golpe 1 com a mao esquerda.
local function maoPorIndice(indice: number?): string
	local valor = if typeof(indice) == "number" then math.max(1, math.floor(indice)) else 1
	return if valor % 2 == 0 then "Right" else "Left"
end

local function limparConexoesHitbox(ctx: Ctx)
	local e = est(ctx)
	if e.limpezaMarkers then
		pcall(e.limpezaMarkers)
	end
	e.limpezaMarkers = nil

	local conn = e.conexaoStopped
	if conn and conn.Connected then
		conn:Disconnect()
	end
	e.conexaoStopped = nil
end

local function cancelarSwing(ctx: Ctx)
	local e = est(ctx)
	e.swingToken = (e.swingToken or 0) + 1
	e.markerDisparado = false
	limparConexoesHitbox(ctx)
	destruirHitboxes(ctx)
end

local function ativarHitboxMao(ctx: Ctx, mao: string, acaoTick: number)
	destruirHitboxMao(ctx, mao)

	local arma = (est(ctx) :: any)[campoArma(mao)] :: Model?
	if not arma or not arma.Parent then
		return
	end

	local params = Modulo_Hitbox.CriarRaycastParamsAtacante(ctx.modelo)
	local handle, erro = Modulo_Hitbox.CriarHitbox(arma, mao :: any, params)
	if not handle then
		if erro then
			warn("[NPC.Combate.View] CriarHitbox falhou (" .. mao .. "): " .. tostring(erro))
		end
		return
	end
	(est(ctx) :: any)[campoHitbox(mao)] = handle

	Modulo_Hitbox.AtivarHitbox(handle, function(alvo: Model, _mao, raycastResult)
		if est(ctx).acaoTick ~= acaoTick or alvo ~= PLAYER_LOCAL.Character then
			return
		end
		-- O servidor valida atacando + janela + distancia rebobinada + dedup.
		local npcHrp = ctx.modelo:FindFirstChild("HumanoidRootPart") :: BasePart?
		local alvoHrp = alvo:FindFirstChild("HumanoidRootPart") :: BasePart?
		NPC_HitReport:FireServer(
			ctx.modelo,
			alvo,
			acaoTick,
			raycastResult and raycastResult.Instance.Name or nil,
			npcHrp and npcHrp.CFrame or nil,
			alvoHrp and alvoHrp.CFrame or nil
		)
	end, nil)
end

local function obterTimingsAtaque(ctx: Ctx)
	local idArma = ctx.modelo:GetAttribute(TiposNPC.Chaves.ArmaEquipadaId) :: string?
	local dados = idArma and CatalogoItens.Get(idArma)
	local modo = dados and dados.ModoAnimacao
	if modo and modo ~= "" then
		return Timings.ObterPorArma(modo)
	end
	return Timings.Punhos
end

local function configurarHitboxParaSwing(ctx: Ctx, track: AnimationTrack, acaoTick: number)
	local e = est(ctx)
	if not ehAlvoLocal(ctx) then
		return
	end
	if not e.armaRight and not e.armaLeft then
		return
	end

	limparConexoesHitbox(ctx)
	destruirHitboxes(ctx)

	-- Arma de uma mao so tem WeaponModel a direita: nao da pra alternar.
	local maoIndice: string
	if e.armaRight and e.armaLeft then
		maoIndice = maoPorIndice(ctx.modelo:GetAttribute(TiposNPC.Chaves.AcaoIndice) :: number?)
	else
		maoIndice = if e.armaRight then "Right" else "Left"
	end

	e.swingToken = (e.swingToken or 0) + 1
	local token = e.swingToken
	e.markerDisparado = false

	local function valido(): boolean
		return not ctx.destruido and e.swingToken == token and e.acaoTick == acaoTick and ehAlvoLocal(ctx)
	end

	local function ativarPorMarker(mao: string)
		if not valido() or e.markerDisparado then
			return
		end
		e.markerDisparado = true
		destruirHitboxMao(ctx, maoOposta(mao))
		ativarHitboxMao(ctx, mao, acaoTick)
	end

	e.limpezaMarkers = Modulo_Combo.ConfigurarListenersMarcadores(track, {
		onAtaqueDireita = function()
			ativarPorMarker("Right")
		end,
		onAtaqueEsquerda = function()
			ativarPorMarker("Left")
		end,
		onAtaqueAmbos = function()
			ativarPorMarker(maoIndice)
		end,
		onAtaqueFim = function()
			if e.swingToken == token then
				destruirHitboxes(ctx)
			end
		end,
	})

	e.conexaoStopped = track.Stopped:Connect(function()
		if e.swingToken ~= token then
			return
		end
		destruirHitboxes(ctx)
		limparConexoesHitbox(ctx)
	end)

	-- Fallback por tempo, escalado pela velocidade REAL da track. Com ataque
	-- carregado (speed 0.4) o delay fixo antigo disparava cedo demais.
	local t = obterTimingsAtaque(ctx)
	local velocidade = math.max(track.Speed, 0.05)

	task.delay(t.Ataque.AtrasoHit / velocidade + BUFFER_FALLBACK_HITBOX, function()
		if valido() and not e.markerDisparado then
			e.markerDisparado = true
			destruirHitboxMao(ctx, maoOposta(maoIndice))
			ativarHitboxMao(ctx, maoIndice, acaoTick)
		end
	end)

	task.delay(t.Ataque.Duracao / velocidade, function()
		if e.swingToken ~= token then
			return
		end
		destruirHitboxes(ctx)
		limparConexoesHitbox(ctx)
	end)
end

-- =============================================================================
-- Reacoes (NPC_Estado).
-- =============================================================================

type Entry = { nome: string, id: string, looped: boolean }

local function entradaPorEstado(ctx: Ctx, estado: string): Entry?
	local a = obterAnimacoesModo(ctx)
	if estado == TiposNPC.Estado.Aparando then
		return { nome = "Aparando", id = a.Aparar or a.Defesa or Punhos.Aparar or Punhos.Defesa or "", looped = false }
	elseif estado == TiposNPC.Estado.Aparado then
		return {
			nome = "Aparado",
			id = a.Aparado or a.Stunado or Punhos.Aparado or Punhos.Stunado or "",
			looped = false,
		}
	elseif estado == TiposNPC.Estado.DefesaQuebrada then
		return {
			nome = "DefesaQuebrada",
			id = a.DefesaQuebrada or a.Stunado or Punhos.DefesaQuebrada or Punhos.Stunado or "",
			looped = false,
		}
	elseif estado == TiposNPC.Estado.Stunado then
		return { nome = "Stunado", id = a.Stunado or Punhos.Stunado or "", looped = false }
	elseif estado == TiposNPC.Estado.Defendendo then
		return { nome = "Defendendo", id = a.Defesa or Punhos.Defesa or "", looped = true }
	end
	return nil
end

local function tocarEstado(ctx: Ctx)
	local e = est(ctx)
	local estado = (ctx.modelo:GetAttribute(TiposNPC.Chaves.Estado) or TiposNPC.Estado.Idle) :: string
	local entry = entradaPorEstado(ctx, estado)

	if not entry then
		-- Estado normal: locomocao e ataque sao tocados por outros caminhos.
		if e.estadoTocando == nil then
			return
		end
		local anterior = e.estadoTocando
		e.estadoTocando = nil

		local track = ctx.tracks[anterior]
		if track and track.IsPlaying then
			local indoAtacar = estado == TiposNPC.Estado.Atacando
			track:Stop(if indoAtacar then FADE_REACAO_PARA_ATAQUE else FADE_REACAO_OUT)
		end
		-- Sem isso o NPC volta para a pose padrao do Roblox.
		if estado ~= TiposNPC.Estado.Atacando then
			aplicarLocomocao(ctx)
		end
		return
	end

	local track = ViewBase.CarregarTrack(ctx, entry.nome, entry.id)
	if not track then
		return
	end

	if estado == TiposNPC.Estado.Aparando then
		local ataque = ctx.tracks["Ataque"]
		if ataque and ataque.IsPlaying then
			ataque:Stop(FADE_SAIDA_ATAQUE)
		end
		pararTodasLocomocao(ctx)
	end

	if e.estadoTocando == entry.nome and track.IsPlaying then
		return
	end
	e.estadoTocando = entry.nome

	-- Para outras reacoes; locomocao continua rodando por baixo.
	for outro, t in ctx.tracks do
		if outro == entry.nome or LOCOMOCAO_NAMES[outro] or not t.IsPlaying then
			continue
		end
		if outro == "Ataque" or outro == "Equipar" or outro == "Desequipar" then
			continue
		end
		t:Stop(FADE_REACAO_OUT)
	end

	track.Looped = entry.looped
	track:Play(FADE_REACAO_IN)
end

-- =============================================================================
-- Acao (NPC_Acao).
-- =============================================================================

local function limparConexoesEquip(ctx: Ctx)
	local e = est(ctx)
	for _, campo in { "equipStoppedConn", "equipEndedConn", "equipMarkerConn" } do
		local conn = (e :: any)[campo] :: RBXScriptConnection?
		if conn and conn.Connected then
			conn:Disconnect()
		end
		(e :: any)[campo] = nil
	end
end

local function tocarEquip(ctx: Ctx, nome: string, criarArmaNoMarker: boolean, acaoTick: number?)
	local track = carregarTrack(ctx, nome)
	if not track then
		-- FIX: sem track a funcao saia calada. A arma nunca era criada e o
		-- servidor nunca recebia EquipAnimacaoTerminou, deixando o NPC preso em
		-- "equipando". Agora aplica o efeito imediatamente e confirma.
		local eSemTrack = est(ctx)
		eSemTrack.equipNomeAtual = nil
		eSemTrack.equipExecutadoTick = acaoTick
		if criarArmaNoMarker and not ctx.destruido then
			eSemTrack.equipArmaCriada = true
			criarArmasLocais(ctx)
		end
		if not ctx.destruido then
			EquipAnimacaoTerminou:FireServer(ctx.modelo)
		end
		return
	end

	local e = est(ctx)

	-- Evita re-executar a mesma acao de equipar para o mesmo tick ou enquanto ja estiver ativa.
	if typeof(acaoTick) == "number" and acaoTick > 0 and e.equipExecutadoTick == acaoTick then
		return
	end
	if e.equipNomeAtual == nome and track.IsPlaying and e.equipToken then
		return
	end

	limparConexoesEquip(ctx)

	local token = (e.equipToken or 0) + 1
	e.equipToken = token
	e.equipArmaCriada = false
	e.equipNomeAtual = nome
	e.equipExecutadoTick = acaoTick

	-- Para a track caso ja esteja tocando antes de reiniciar limpa.
	if track.IsPlaying then
		pcall(function()
			track:Stop(0)
		end)
	end

	track.Looped = false
	track:Play(FADE_EQUIP)
	track.Looped = false

	local finalizado = false
	local function finalizar()
		if finalizado then
			return
		end
		finalizado = true

		limparConexoesEquip(ctx)
		if e.equipToken ~= token then
			return
		end

		if criarArmaNoMarker and not e.equipArmaCriada and not ctx.destruido then
			e.equipArmaCriada = true
			criarArmasLocais(ctx)
		end

		if track.IsPlaying then
			pcall(function()
				track:Stop(0.1)
			end)
		end

		if not ctx.destruido then
			EquipAnimacaoTerminou:FireServer(ctx.modelo)
		end
	end

	if criarArmaNoMarker then
		-- Marker "Equip": cria a arma durante a animacao.
		e.equipMarkerConn = track:GetMarkerReachedSignal("Equip"):Connect(function()
			if e.equipToken == token and not ctx.destruido then
				e.equipArmaCriada = true
				criarArmasLocais(ctx)
			end
		end)
	end

	e.equipStoppedConn = track.Stopped:Connect(finalizar)

	pcall(function()
		e.equipEndedConn = track.Ended:Connect(finalizar)
	end)

	local didLoopConn: RBXScriptConnection? = nil
	pcall(function()
		didLoopConn = track.DidLoop:Connect(function()
			if didLoopConn then
				didLoopConn:Disconnect()
				didLoopConn = nil
			end
			finalizar()
		end)
	end)

	local duracao = if track.Length > 0 then (track.Length + 0.5) else 2.0
	task.delay(duracao, function()
		if e.equipToken == token and not finalizado then
			finalizar()
		end
		if didLoopConn then
			pcall(function()
				didLoopConn:Disconnect()
			end)
			didLoopConn = nil
		end
	end)
end

local function tocarAcao(ctx: Ctx)
	local e = est(ctx)
	local acao = ctx.modelo:GetAttribute(TiposNPC.Chaves.Acao) :: string?
	local tick = ctx.modelo:GetAttribute(TiposNPC.Chaves.AcaoTick) :: number?
	if not acao then
		return
	end

	-- Mesmo Acao + mesmo tick = artefato de replicacao.
	if e.acaoTocando == acao and e.acaoTick == tick then
		return
	end
	e.acaoTocando = acao
	e.acaoTick = tick

	if acao ~= TiposNPC.Acao.Equipar and acao ~= TiposNPC.Acao.Desequipar then
		e.equipNomeAtual = nil
		e.equipExecutadoTick = nil
		-- FIX: equipArmaCriada nunca era resetado. Ficando true para sempre,
		-- sincronizarArmaVisual caia no early-return e nunca mais reconciliava
		-- a arma visual enquanto NPC_ArmaPronta fosse false.
		e.equipArmaCriada = false
	end

	if acao == TiposNPC.Acao.Idle then
		local ataque = ctx.tracks["Ataque"]
		if ataque and ataque.IsPlaying then
			ataque:Stop(FADE_SAIDA_ATAQUE)
		end
		cancelarSwing(ctx)
		aplicarLocomocao(ctx)
	elseif acao == TiposNPC.Acao.Equipar then
		tocarEquip(ctx, "Equipar", true, tick)
	elseif acao == TiposNPC.Acao.Desequipar then
		tocarEquip(ctx, "Desequipar", false, tick)
	elseif acao == TiposNPC.Acao.Ataque then
		local track = carregarTrack(ctx, "Ataque")
		if not track or e.acaoTick ~= tick or ctx.destruido then
			return
		end
		track.Looped = false

		if not track.IsPlaying then
			track:Play(FADE_ENTRADA_ATAQUE)
		end

		if typeof(tick) == "number" then
			configurarHitboxParaSwing(ctx, track, tick)
		end
	end
end

-- =============================================================================
-- Locomocao e sincronia de arma.
-- =============================================================================

function aplicarLocomocao(ctx: Ctx)
	local nomeAttr = ctx.modelo:GetAttribute(TiposNPC.Chaves.LocomocaoNome) :: string?
	local vel = ctx.modelo:GetAttribute(TiposNPC.Chaves.LocomocaoVelocidade) :: number?
	local nome = if nomeAttr ~= nil and nomeAttr ~= "" then nomeAttr else "Idle"
	if not LOCOMOCAO_NAMES[nome] then
		return
	end
	tocarLocomocao(ctx, nome, vel)
end

local function reaplicarDepois(ctx: Ctx)
	task.defer(function()
		if not ctx.destruido and ctx.lod ~= TiposNPC.LOD.Distante then
			aplicarLocomocao(ctx)
			tocarEstado(ctx)
		end
	end)
end

local function sincronizarArmaVisual(ctx: Ctx)
	local e = est(ctx)
	local pronta = ctx.modelo:GetAttribute(TiposNPC.Chaves.ArmaPronta) == true

	if not pronta then
		if e.equipArmaCriada or e.equipNomeAtual ~= nil then
			-- Preserva as armas criadas localmente enquanto aguarda sincronizacao do servidor.
			return
		end
		cancelarSwing(ctx)
		destruirArmasLocais(ctx)
		if e.armaVisualId ~= nil then
			e.armaVisualId = nil
			reconciliarTracks(ctx)
			reaplicarDepois(ctx)
		end
		return
	end

	local idAtual = (ctx.modelo:GetAttribute(TiposNPC.Chaves.ArmaEquipadaId) :: string?) or "punhos"
	local precisaRecriar = e.armaVisualId ~= idAtual or not e.armaRight or (idAtual == "punhos" and not e.armaLeft)
	if not precisaRecriar then
		return
	end

	cancelarSwing(ctx)
	destruirArmasLocais(ctx)
	reconciliarTracks(ctx)
	criarArmasLocais(ctx)
	e.armaVisualId = idAtual
	reaplicarDepois(ctx)
end

-- =============================================================================
-- Render loop unico para todas as Views de combate.
-- =============================================================================

local ctxsAtivos: { [Ctx]: true } = {}
local renderLigado = false

local function garantirRenderLoop()
	if renderLigado then
		return
	end
	renderLigado = true
	RunService:BindToRenderStep("NPCCombateOrientacao", Enum.RenderPriority.Character.Value + 1, function(dt)
		for ctx in ctxsAtivos do
			if ctx.destruido or not ctx.modelo.Parent then
				ctxsAtivos[ctx] = nil
				continue
			end
			atualizarOrientacaoVisual(ctx, dt)
		end
	end)
end

-- =============================================================================
-- View pipeline.
-- =============================================================================

local function instalarSubscricoes(ctx: Ctx)
	local m = ctx.modelo
	local chaves = {
		TiposNPC.Chaves.Estado,
		TiposNPC.Chaves.Acao,
		TiposNPC.Chaves.AcaoTick,
		TiposNPC.Chaves.LocomocaoNome,
		TiposNPC.Chaves.LocomocaoVelocidade,
		TiposNPC.Chaves.ArmaPronta,
		TiposNPC.Chaves.ArmaEquipadaId,
	}

	for _, chave in chaves do
		ViewBase.RastrearConexao(
			ctx,
			m:GetAttributeChangedSignal(chave):Connect(function()
				if ctx.lod == TiposNPC.LOD.Distante then
					return
				end
				if chave == TiposNPC.Chaves.Estado then
					tocarEstado(ctx)
				elseif chave == TiposNPC.Chaves.Acao or chave == TiposNPC.Chaves.AcaoTick then
					tocarAcao(ctx)
				elseif chave == TiposNPC.Chaves.LocomocaoNome or chave == TiposNPC.Chaves.LocomocaoVelocidade then
					aplicarLocomocao(ctx)
				else
					sincronizarArmaVisual(ctx)
				end
			end)
		)
	end
end

local function aplicarTudoAgora(ctx: Ctx)
	sincronizarArmaVisual(ctx)
	aplicarLocomocao(ctx)
	tocarAcao(ctx)
	tocarEstado(ctx)
end

local Combate: ViewBase.View = {
	id = TiposNPC.Archetype.Combate,

	iniciar = function(ctx: Ctx)
		instalarSubscricoes(ctx)
		ctxsAtivos[ctx] = true
		garantirRenderLoop()
		-- LOD comeca Distante; aplicamos quando promover via aoLOD.
	end,

	atualizar = function(_ctx: Ctx, _dt: number, _distancia: number) end,

	aoLOD = function(ctx: Ctx, novo: string, _anterior: string)
		if novo ~= TiposNPC.LOD.Distante then
			aplicarTudoAgora(ctx)
			return
		end

		local e = est(ctx)
		ViewBase.PararTodasAsTracks(ctx, FADE_REACAO_OUT)
		pararTodasLocomocao(ctx)
		e.estadoTocando = nil
		e.acaoTocando = nil
		e.acaoTick = nil
		cancelarSwing(ctx)
		destruirArmasLocais(ctx)
		e.armaVisualId = nil
		restaurarOrientacaoVisual(ctx)
		limparConexoesEquip(ctx)
		e.equipNomeAtual = nil
		-- FIX: sem limpar o tick executado, ao voltar de LOD Distante o mesmo
		-- NPC_AcaoTick era considerado "ja executado" e a animacao de equipar
		-- nunca mais tocava.
		e.equipExecutadoTick = nil
		e.equipArmaCriada = false
	end,

	destruir = function(ctx: Ctx)
		ctxsAtivos[ctx] = nil
		cancelarSwing(ctx)
		destruirArmasLocais(ctx)
		restaurarOrientacaoVisual(ctx)
		limparConexoesEquip(ctx)
		est(ctx).equipNomeAtual = nil
		ViewBase.LimparTudo(ctx)
	end,
}

ViewBase.RegistrarView(Combate)

return Combate
