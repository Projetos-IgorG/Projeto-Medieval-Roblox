--!strict

--[[
	Script: Combate.luau
	Caminho: src/StarterPlayer/StarterPlayerScripts/NPC/Views
	Responsabilidade: View completa do NPC de combate - cliente-fat. Toca TODAS
	    as animacoes (Idle, Andando*, Correndo*, Equipar, Desequipar, Ataque,
	    Aparando, Aparado, Stunado, DefesaQuebrada, Defendendo) localmente.
	    Tambem clona o WeaponModel visual da arma equipada localmente, com
	    Motor6D, ao detectar NPC_ArmaPronta=true. Servidor NAO replica visual
	    nenhum: o controlador-servidor so seta atributos.
	Uso: ModuleScript; auto-registra em ViewBase.
	Funcoes principais: iniciar, atualizar, aoLOD, destruir
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CatalogoItens = require(ReplicatedStorage:WaitForChild("Dados"):WaitForChild("Itens"):WaitForChild("CatalogoItens"))
local ConstrutorTools = require(ReplicatedStorage:WaitForChild("SistemaItens"):WaitForChild("ConstrutorTools"))

local TiposNPC = require(ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC"):WaitForChild("Tipos"))
local IdsCombate =
	require(ReplicatedStorage:WaitForChild("Combate"):WaitForChild("Animacoes"):WaitForChild("IdsAnimacoesCombate"))
local Modulo_Hitbox = require(ReplicatedStorage:WaitForChild("Combate"):WaitForChild("Hitbox"))
local Timings =
	require(ReplicatedStorage:WaitForChild("Combate"):WaitForChild("Configuracoes"):WaitForChild("TimingsAtaqueNPC"))
local Modulo_Combo =
	require(ReplicatedStorage:WaitForChild("Combate"):WaitForChild("Dominio"):WaitForChild("ComboCombate"))
local ViewBase = require(script.Parent:WaitForChild("ViewBase"))

local PLAYER_LOCAL = Players.LocalPlayer
local NPC_HitReport: RemoteEvent =
	ReplicatedStorage:WaitForChild("Remotos"):WaitForChild("NPC_HitReport") :: RemoteEvent
local EquipAnimacaoTerminou: RemoteEvent =
	ReplicatedStorage:WaitForChild("Remotos"):WaitForChild("EquipAnimacaoTerminou") :: RemoteEvent

type Ctx = ViewBase.ContextoView

local Punhos = (IdsCombate :: any).Punhos and (IdsCombate :: any).Punhos.animacoes or {}

local FADE_LOCOMOCAO = 0.18
local FADE_REACAO_IN = 0.14
local FADE_REACAO_OUT = 0.18
local FADE_REACAO_PARA_ATAQUE = 0.16
local FADE_ENTRADA_ATAQUE = 0.16
local FADE_SAIDA_ATAQUE = 0.22
local FADE_EQUIP = 0.10

local SUFIXO_PARA_BRACO = {
	Right = "Right Arm",
	Left = "Left Arm",
}
local SUFIXO_PARA_SLOT = {
	Right = "RightArm",
	Left = "LeftArm",
}

-- Conjunto de nomes considerados locomocao (Movement priority).
local LOCOMOCAO_NAMES: { [string]: boolean } = {
	Idle = true,
	Andando = true,
	AndandoDireita = true,
	AndandoEsquerda = true,
	Correndo = true,
	CorrendoDireita = true,
	CorrendoEsquerda = true,
}

-- =============================================================================
-- Helpers de tracks.
-- =============================================================================

local function carregarTrack(ctx: Ctx, nome: string): AnimationTrack?
	local id = Punhos[nome]
	if not id then
		return nil
	end
	return ViewBase.CarregarTrack(ctx, nome, id)
end

local function pararLocomocaoExceto(ctx: Ctx, manter: AnimationTrack?)
	for nome, t in ctx.tracks do
		if LOCOMOCAO_NAMES[nome] and t ~= manter and t.IsPlaying then
			t:Stop(FADE_LOCOMOCAO)
		end
	end
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

local function pararTodasLocomocao(ctx: Ctx)
	for nome, t in ctx.tracks do
		if LOCOMOCAO_NAMES[nome] and t.IsPlaying then
			t:Stop(FADE_LOCOMOCAO)
		end
	end
end

-- =============================================================================
-- Orientacao visual cliente-local. O servidor move o Humanoid; a View gira o
-- RootJoint localmente para o NPC parecer mirar o alvo sem aplicar torque fisico.
-- =============================================================================

local function obterRootJointVisual(ctx: Ctx): Motor6D?
	local existente = ctx.estado.rootJointVisual
	if typeof(existente) == "Instance" and existente:IsA("Motor6D") and existente.Parent then
		return existente
	end

	local hrp = ctx.modelo:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return nil
	end
	local torso = ctx.modelo:FindFirstChild("Torso") :: BasePart?
	for _, child in hrp:GetChildren() do
		if child:IsA("Motor6D") and child.Part0 == hrp and (not torso or child.Part1 == torso) then
			ctx.estado.rootJointVisual = child
			ctx.estado.rootJointVisualC0Base = child.C0
			return child
		end
	end
	return nil
end

local function obterNeckJoint(ctx: Ctx): Motor6D?
	local existente = ctx.estado.neckJoint
	if typeof(existente) == "Instance" and existente:IsA("Motor6D") and existente.Parent then
		return existente
	end

	local neck = ctx.modelo:FindFirstChild("Neck", true) :: Motor6D?
	if neck and neck:IsA("Motor6D") then
		ctx.estado.neckJoint = neck
		ctx.estado.neckC0Base = neck.C0
		return neck
	end
	return nil
end

local function obterPosicaoAlvoVisual(ctx: Ctx): Vector3?
	local alvoRef = ctx.modelo:GetAttribute(TiposNPC.Chaves.AlvoRef)
	if typeof(alvoRef) ~= "number" or alvoRef == 0 then
		return nil
	end
	-- Player: AlvoRef positivo = UserId.
	if alvoRef > 0 then
		for _, player in Players:GetPlayers() do
			if player.UserId == alvoRef then
				local char = player.Character
				local hrp = char and (char:FindFirstChild("HumanoidRootPart") :: BasePart?)
				return hrp and hrp.Position or nil
			end
		end
		return nil
	end
	-- NPC: AlvoRef negativo = -id de NPC. Procura por NPC_Id no workspace.
	local procurado = -alvoRef
	local pastaNPCs = workspace:FindFirstChild("NPCs") or workspace
	for _, m in pastaNPCs:GetDescendants() do
		if m:IsA("Model") and m:GetAttribute("NPC_Id") == procurado then
			local hrp = m:FindFirstChild("HumanoidRootPart") :: BasePart?
			return hrp and hrp.Position or nil
		end
	end
	return nil
end

-- Normaliza angulo para [-pi, pi].
local function normAngulo(a: number): number
	return ((a + math.pi) % (2 * math.pi)) - math.pi
end

local function yawDoVetor(dir: Vector3): number
	return math.atan2(-dir.X, -dir.Z)
end

local function atualizarOrientacaoVisual(ctx: Ctx, _dt: number)
	if ctx.lod == TiposNPC.LOD.Distante then
		return
	end
	local joint = obterRootJointVisual(ctx)
	if not joint then
		return
	end
	local hrp = ctx.modelo:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end
	local baseC0 = ctx.estado.rootJointVisualC0Base
	if typeof(baseC0) ~= "CFrame" then
		baseC0 = joint.C0
		ctx.estado.rootJointVisualC0Base = baseC0
	end

	local alvoPos = obterPosicaoAlvoVisual(ctx)
	local atual = 0

	if alvoPos then
		local dx = alvoPos.X - hrp.Position.X
		local dz = alvoPos.Z - hrp.Position.Z
		if (dx * dx + dz * dz) > 0.0025 then
			local desiredYaw = yawDoVetor(Vector3.new(dx, 0, dz))
			local hrpYaw = yawDoVetor(hrp.CFrame.LookVector)
			atual = normAngulo(desiredYaw - hrpYaw)
		end
	end

	ctx.estado.jointYawAtual = atual
	ctx.estado.jointYawSuavizado = atual

	joint.C0 = CFrame.Angles(0, atual, 0) * (baseC0 :: CFrame)

	-- Rotacao da Cabeca (Neck) no eixo Y fixa no alvo, preservando X e Z do animador
	local neck = obterNeckJoint(ctx)
	if neck then
		if alvoPos then
			local head = ctx.modelo:FindFirstChild("Head") :: BasePart?
			local torso = ctx.modelo:FindFirstChild("Torso") :: BasePart?
			if head and torso then
				local dir = alvoPos - head.Position
				if dir.Magnitude > 0.1 then
					local desiredHeadYawWorld = yawDoVetor(dir)
					local torsoYawWorld = yawDoVetor(torso.CFrame.LookVector)
					local relativeYaw = normAngulo(desiredHeadYawWorld - torsoYawWorld)

					-- Mantem X (pitch) e Y (roll) do animador, sobrescreve Z (yaw)
					local rx, ry, _ = neck.Transform:ToEulerAnglesXYZ()
					neck.Transform = CFrame.Angles(rx, ry, relativeYaw)
				end
			end
		end
	end
end

local function restaurarOrientacaoVisual(ctx: Ctx)
	local joint = ctx.estado.rootJointVisual
	local baseC0 = ctx.estado.rootJointVisualC0Base
	if typeof(joint) == "Instance" and joint:IsA("Motor6D") and typeof(baseC0) == "CFrame" then
		joint.C0 = baseC0
	end

	local neck = ctx.estado.neckJoint
	if typeof(neck) == "Instance" and neck:IsA("Motor6D") and neck.Parent then
		neck.Transform = CFrame.new()
	end

	ctx.estado.rootJointVisual = nil
	ctx.estado.rootJointVisualC0Base = nil
	ctx.estado.jointYawAtual = nil
	ctx.estado.jointYawSuavizado = nil
	ctx.estado.neckJoint = nil
	ctx.estado.neckC0Base = nil
end

-- =============================================================================
-- WeaponModel cliente-local: cada cliente clona o WeaponModel visual da arma
-- equipada e ancora aos bracos do NPC via Motor6D LOCAL. Nada disso replica.
-- =============================================================================

local function encontrarTemplateArma(id: string?): Tool?
	if not id or id == "" then
		return nil
	end
	return ConstrutorTools.CriarTool(id)
end

local function destruirWeaponModelMao(ctx: Ctx, mao: string)
	local key = "WeaponModelLocal" .. mao
	local existente = ctx.estado[key]
	if existente and typeof(existente) == "Instance" then
		existente:Destroy()
	end
	ctx.estado[key] = nil

	local nomeBraco = SUFIXO_PARA_BRACO[mao]
	if nomeBraco then
		local arm = ctx.modelo:FindFirstChild(nomeBraco) :: BasePart?
		if arm then
			local jname = SUFIXO_PARA_SLOT[mao] .. "_WeaponJointLocal"
			local j = arm:FindFirstChild(jname)
			if j then
				j:Destroy()
			end
		end
	end
end

local function destruirWeaponModelsLocais(ctx: Ctx)
	destruirWeaponModelMao(ctx, "Right")
	destruirWeaponModelMao(ctx, "Left")
end

local function criarWeaponModelMao(ctx: Ctx, template: Model, mao: string)
	local nomeBraco = SUFIXO_PARA_BRACO[mao]
	if not nomeBraco then
		return
	end
	local armPart = ctx.modelo:FindFirstChild(nomeBraco) :: BasePart?
	if not armPart then
		return
	end
	destruirWeaponModelMao(ctx, mao)

	local clone = template:Clone()
	clone.Name = "WeaponModelLocal" .. mao

	local handle = clone:FindFirstChild("Handle") :: BasePart?
	if not handle then
		clone:Destroy()
		return
	end
	-- Mantém o nome original como "Handle" para compatibilidade com animações
	handle.Name = "Handle"

	for _, d in clone:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ProximityPrompt") then
			d:Destroy()
		end
	end
	for _, p in clone:GetDescendants() do
		if p:IsA("BasePart") then
			p.Transparency = if p.Name == "HitboxPart" then 1 else 0
			p.Anchored = false
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = false
			p.Massless = true
		end
	end

	clone.Parent = ctx.modelo

	local joint = Instance.new("Motor6D")
	joint.Name = SUFIXO_PARA_SLOT[mao] .. "_WeaponJointLocal"
	joint.Part0 = armPart
	joint.Part1 = handle
	-- Usar CFrame estático relativo ao braço para a C0 do Motor6D, evitando
	-- ler o CFrame do braço já animado (que introduziria offsets incorretos).
	joint.C0 = CFrame.new(0, -1, 0) * CFrame.Angles(math.rad(-90), 0, 0)
	joint.C1 = CFrame.new()
	joint.Parent = armPart

	ctx.estado["WeaponModelLocal" .. mao] = clone
end

local function criarWeaponModelsLocais(ctx: Ctx)
	local id = ctx.modelo:GetAttribute(TiposNPC.Chaves.ArmaEquipadaId) :: string?
	-- Fallback para punhos se nao houver id explicito.
	local template: Model? = nil
	local tool = encontrarTemplateArma(id) or encontrarTemplateArma("punhos")
	if tool then
		local wm = tool:FindFirstChild("WeaponModel")
		if wm and wm:IsA("Model") then
			template = wm
		end
	end
	if not template then
		return
	end
	criarWeaponModelMao(ctx, template, "Right")
	criarWeaponModelMao(ctx, template, "Left")
end

-- =============================================================================
-- Hitbox local: o cliente do alvo roda shapecast no WeaponModel local (que e
-- o unico que esta realmente animado pelo Animator local). Quando acertar a
-- si proprio, dispara NPC_HitReport para o servidor validar e aplicar dano.
-- Outros clientes nao rodam hitbox para este NPC (so o do alvo).
-- =============================================================================

local sincronizarArmaVisual: (ctx: Ctx) -> ()
local aplicarLocomocao: (ctx: Ctx) -> ()

local function ehAlvoLocal(ctx: Ctx): boolean
	local alvoRef = ctx.modelo:GetAttribute(TiposNPC.Chaves.AlvoRef)
	return typeof(alvoRef) == "number" and alvoRef == PLAYER_LOCAL.UserId
end

local function destruirHitboxesLocais(ctx: Ctx)
	for _, key in { "HitboxRight", "HitboxLeft" } do
		local handle = ctx.estado[key]
		if handle then
			Modulo_Hitbox.DestruirHitbox(handle)
		end
		ctx.estado[key] = nil
	end
end

local function destruirHitboxMaoLocal(ctx: Ctx, mao: string)
	local key = "Hitbox" .. mao
	local handle = ctx.estado[key]
	if handle then
		Modulo_Hitbox.DestruirHitbox(handle)
	end
	ctx.estado[key] = nil
end

local function maoOposta(mao: string): string
	return if mao == "Right" then "Left" else "Right"
end

local function maoPorIndice(indice: number?): string
	local valor = if typeof(indice) == "number" then math.max(1, math.floor(indice)) else 1
	-- A animação de punhos R6 inicia o primeiro golpe (índice 1) com a mão Esquerda (Left).
	-- Portanto, índices ímpares (1, 3) mapeiam para 'Left' e pares (2, 4) para 'Right'.
	return if valor % 2 == 0 then "Right" else "Left"
end

local function limparConexoesHitboxAnimacao(ctx: Ctx)
	local limpezaMarkers = ctx.estado.limpezaMarkersHitbox
	if type(limpezaMarkers) == "function" then
		pcall(limpezaMarkers)
	end
	ctx.estado.limpezaMarkersHitbox = nil

	local conexaoStopped = ctx.estado.conexaoHitboxStopped
	if conexaoStopped and conexaoStopped.Connected then
		conexaoStopped:Disconnect()
	end
	ctx.estado.conexaoHitboxStopped = nil
end

local function cancelarHitboxSwing(ctx: Ctx)
	ctx.estado.swingHitToken = (ctx.estado.swingHitToken or 0) + 1
	ctx.estado.hitboxMarkerDisparado = false
	limparConexoesHitboxAnimacao(ctx)
	destruirHitboxesLocais(ctx)
end

local function ativarHitboxMaoCliente(ctx: Ctx, mao: string, duracao: number?, acaoTick: number)
	local key = "Hitbox" .. mao
	local existente = ctx.estado[key]
	if existente then
		Modulo_Hitbox.DestruirHitbox(existente)
		ctx.estado[key] = nil
	end

	local weaponLocal = ctx.estado["WeaponModelLocal" .. mao]
	if not weaponLocal or typeof(weaponLocal) ~= "Instance" or not (weaponLocal :: Instance):IsA("Model") then
		return
	end
	local weaponModel = weaponLocal :: Model
	if not weaponModel.Parent then
		return
	end

	local params = Modulo_Hitbox.CriarRaycastParamsAtacante(ctx.modelo)
	-- Exclui o proprio NPC atacante; o servidor valida alvo, distancia e swing.

	local handle, erro = Modulo_Hitbox.CriarHitbox(weaponModel, mao :: any, params)
	if not handle then
		if erro then
			warn("[NPC.Combate.View] CriarHitbox falhou (" .. mao .. "): " .. tostring(erro))
		end
		return
	end
	ctx.estado[key] = handle

	Modulo_Hitbox.AtivarHitbox(handle, function(alvo: Model, _maoHit, raycastResult)
		if ctx.estado.acaoTick ~= acaoTick then
			return
		end
		if alvo ~= PLAYER_LOCAL.Character then
			return
		end
		-- Reporta para servidor: ele valida atacando + janela + distancia + dedup
		-- e chama _ProcessarHit canonico.
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
	end, duracao)
end

local function obterTimingsAtaque(ctx: Ctx): typeof(Timings.Punhos)
	local idArma = ctx.modelo:GetAttribute(TiposNPC.Chaves.ArmaEquipadaId) :: string?
	local timings = Timings.Punhos
	if idArma then
		local catalogData = CatalogoItens.Get(idArma)
		local modo = catalogData and catalogData.ModoAnimacao
		if modo and modo ~= "" then
			timings = Timings.ObterPorArma(modo)
		end
	end
	return timings
end

local function configurarHitboxParaSwing(ctx: Ctx, track: AnimationTrack, acaoTick: number)
	if not ehAlvoLocal(ctx) then
		return
	end

	-- Garantir que as armas visuais estejam sincronizadas antes de validar
	sincronizarArmaVisual(ctx)

	-- So tem sentido se a arma estiver pronta visualmente (WeaponModel local existe).
	if not ctx.estado.WeaponModelLocalRight and not ctx.estado.WeaponModelLocalLeft then
		return
	end

	limparConexoesHitboxAnimacao(ctx)
	destruirHitboxesLocais(ctx)

	local timings = obterTimingsAtaque(ctx)
	local t = timings.Ataque
	local indiceSwing = ctx.modelo:GetAttribute(TiposNPC.Chaves.AcaoIndice) :: number?
	local maoIndice = maoPorIndice(indiceSwing)

	-- Token: apenas o swing mais recente conta. Markers/delays antigos abortam.
	ctx.estado.swingHitToken = (ctx.estado.swingHitToken or 0) + 1
	local token = ctx.estado.swingHitToken
	ctx.estado.hitboxMarkerDisparado = false

	local function swingValido(): boolean
		return not ctx.destruido
			and ctx.estado.swingHitToken == token
			and ctx.estado.acaoTick == acaoTick
			and ehAlvoLocal(ctx)
	end

	local function ativarMaoPorMarker(mao: string)
		if not swingValido() then
			return
		end
		if ctx.estado.hitboxMarkerDisparado then
			return
		end
		ctx.estado.hitboxMarkerDisparado = true
		destruirHitboxMaoLocal(ctx, maoOposta(mao))
		ativarHitboxMaoCliente(ctx, mao, nil, acaoTick)
	end

	local function pararPorMarkerFim()
		if ctx.estado.swingHitToken ~= token then
			return
		end
		destruirHitboxesLocais(ctx)
	end

	ctx.estado.limpezaMarkersHitbox = Modulo_Combo.ConfigurarListenersMarcadores(track, {
		onAtaqueDireita = function(_indice)
			ativarMaoPorMarker("Right")
		end,
		onAtaqueEsquerda = function(_indice)
			ativarMaoPorMarker("Left")
		end,
		onAtaqueAmbos = function(_indice)
			ativarMaoPorMarker(maoIndice)
		end,
		onAtaqueFim = pararPorMarkerFim,
	})

	ctx.estado.conexaoHitboxStopped = track.Stopped:Connect(function()
		if ctx.estado.swingHitToken ~= token then
			return
		end
		destruirHitboxesLocais(ctx)
		limparConexoesHitboxAnimacao(ctx)
	end)

	-- O fallback de atraso do hitbox deve ser calculado a partir de quando a animação inicia localmente no cliente,
	-- e não baseado no clock desincronizado do servidor (acaoTick), evitando ativação prematura.
	-- Adicionado um buffer de 0.15s para garantir que os marcadores da animação (markers) tenham prioridade.
	local delayTempo = t.AtrasoHit + 0.15

	task.delay(delayTempo, function()
		if not ctx.destruido
			and ctx.estado.swingHitToken == token
			and ctx.estado.acaoTick == acaoTick
			and ehAlvoLocal(ctx)
		then
			if not ctx.estado.hitboxMarkerDisparado then
				ctx.estado.hitboxMarkerDisparado = true
				destruirHitboxMaoLocal(ctx, maoOposta(maoIndice))
				ativarHitboxMaoCliente(ctx, maoIndice, nil, acaoTick)
			end
		end
	end)

	task.delay(t.Duracao, function()
		if ctx.estado.swingHitToken ~= token then
			return
		end
		destruirHitboxesLocais(ctx)
		limparConexoesHitboxAnimacao(ctx)
	end)
end

-- =============================================================================
-- Reacoes (estado replicado em NPC_Estado).
-- =============================================================================

type Entry = { nome: string, id: string, looped: boolean }

local function entradaPorEstado(estado: string): Entry?
	if estado == TiposNPC.Estado.Aparando then
		return { nome = "Aparando", id = Punhos.Aparar or Punhos.Defesa or "", looped = false }
	elseif estado == TiposNPC.Estado.Aparado then
		return { nome = "Aparado", id = Punhos.Aparado or Punhos.Stunado or "", looped = false }
	elseif estado == TiposNPC.Estado.DefesaQuebrada then
		return { nome = "DefesaQuebrada", id = Punhos.DefesaQuebrada or Punhos.Stunado or "", looped = false }
	elseif estado == TiposNPC.Estado.Stunado then
		return { nome = "Stunado", id = Punhos.Stunado or "", looped = false }
	elseif estado == TiposNPC.Estado.Defendendo then
		return { nome = "Defendendo", id = Punhos.Defesa or "", looped = true }
	end
	return nil
end

local function tocarEstado(ctx: Ctx)
	local estado = ctx.modelo:GetAttribute(TiposNPC.Chaves.Estado) or TiposNPC.Estado.Idle
	local entry = entradaPorEstado(estado :: string)
	if not entry then
		-- Estado normal (Idle/Andando/Correndo/Atacando) - nao e reacao; locomocao
		-- e ataque sao tocadas separadamente via NPC_LocomocaoNome / NPC_Acao.
		if ctx.estado.estadoTocando ~= nil then
			-- Saindo de uma reacao: para apenas a track de reacao que estava tocando.
			local nomeReacao = ctx.estado.estadoTocando
			ctx.estado.estadoTocando = nil
			local trackReacao = ctx.tracks[nomeReacao]
			if trackReacao and trackReacao.IsPlaying then
				local indoAtacar = estado == TiposNPC.Estado.Atacando
				trackReacao:Stop(if indoAtacar then FADE_REACAO_PARA_ATAQUE else FADE_REACAO_OUT)
			end
			-- Reaplica locomocao ao sair de reacao para evitar que o NPC
			-- fique na pose padrao do Roblox (sem nenhuma animacao tocando).
			if estado ~= TiposNPC.Estado.Atacando then
				aplicarLocomocao(ctx)
			end
		end
		return
	end
	local track = ViewBase.CarregarTrack(ctx, entry.nome, entry.id)
	if not track then
		return
	end
	if ctx.estado.estadoTocando == entry.nome then
		if track.IsPlaying then
			return
		end
	end
	ctx.estado.estadoTocando = entry.nome

	-- Para outras tracks de reacao (NAO para locomocao - locomocao continua por baixo).
	for outro, t in ctx.tracks do
		if outro ~= entry.nome and not LOCOMOCAO_NAMES[outro] and t.IsPlaying then
			-- Nao para Ataque/Equipar/Desequipar aqui - eles tem sua propria gestao.
			if outro == "Ataque" or outro == "Equipar" or outro == "Desequipar" then
				continue
			end
			t:Stop(FADE_REACAO_OUT)
		end
	end

	track.Looped = entry.looped
	track:Play(FADE_REACAO_IN)
end

-- =============================================================================
-- Acao (NPC_Acao: Idle / Ataque / Equipar / Desequipar).
-- =============================================================================

local function tocarAcao(ctx: Ctx)
	local acao = ctx.modelo:GetAttribute(TiposNPC.Chaves.Acao) :: string?
	local tick = ctx.modelo:GetAttribute(TiposNPC.Chaves.AcaoTick) :: number?
	if not acao then
		return
	end

	-- Reentrancia: mesmo Acao + mesmo tick = nada a fazer (replication artifact).
	if ctx.estado.acaoTocando == acao and ctx.estado.acaoTick == tick then
		return
	end
	ctx.estado.acaoTocando = acao
	ctx.estado.acaoTick = tick

	if acao == TiposNPC.Acao.Idle then
		-- Para tracks de acao se ainda tocando.
		local prev = ctx.tracks["Ataque"]
		if prev and prev.IsPlaying then
			prev:Stop(FADE_SAIDA_ATAQUE)
		end
		cancelarHitboxSwing(ctx)
		-- Reaplica locomocao para evitar que o NPC fique sem animacao
		-- (pose padrao do Roblox) apos sair de um ataque ou reacao.
		aplicarLocomocao(ctx)
	elseif acao == TiposNPC.Acao.Equipar then
		local track = carregarTrack(ctx, "Equipar")
		if not track then
			return
		end
		track.Looped = false
		track:Play(FADE_EQUIP)
		-- Notifica o servidor quando a animacao terminar (igual player).
		local equipToken = (ctx.estado.equipStoppedToken or 0) + 1
		ctx.estado.equipStoppedToken = equipToken
		local conn = ctx.estado.equipStoppedConn
		if conn and conn.Connected then
			conn:Disconnect()
		end
		ctx.estado.equipStoppedConn = track.Stopped:Connect(function()
			local currentConn = ctx.estado.equipStoppedConn
			if currentConn then
				currentConn:Disconnect()
				ctx.estado.equipStoppedConn = nil
			end
			if ctx.estado.equipStoppedToken ~= equipToken then
				return
			end
			EquipAnimacaoTerminou:FireServer(ctx.modelo)
		end)
	elseif acao == TiposNPC.Acao.Desequipar then
		local track = carregarTrack(ctx, "Desequipar")
		if not track then
			return
		end
		track.Looped = false
		track:Play(FADE_EQUIP)
		-- Notifica o servidor quando a animacao terminar (igual player).
		local equipToken = (ctx.estado.equipStoppedToken or 0) + 1
		ctx.estado.equipStoppedToken = equipToken
		local conn = ctx.estado.equipStoppedConn
		if conn and conn.Connected then
			conn:Disconnect()
		end
		ctx.estado.equipStoppedConn = track.Stopped:Connect(function()
			local currentConn = ctx.estado.equipStoppedConn
			if currentConn then
				currentConn:Disconnect()
				ctx.estado.equipStoppedConn = nil
			end
			if ctx.estado.equipStoppedToken ~= equipToken then
				return
			end
			EquipAnimacaoTerminou:FireServer(ctx.modelo)
		end)
	elseif acao == TiposNPC.Acao.Ataque then
		local track = carregarTrack(ctx, "Ataque")
		if not track then
			return
		end
		track.Looped = false

		-- Se a animacao de ataque JA esta tocando, e continuacao de combo.
		-- Todos os golpes (1->4) estao na mesma animacao em sequencia de
		-- keyframes, entao a animacao deve continuar rodando sem reiniciar.
		-- Nao dependemos de NPC_AcaoIndice aqui pois existe race condition
		-- na replicacao: o AcaoTick pode disparar antes do AcaoIndice atualizar,
		-- causando um Stop->Play indevido que mistura a animacao consigo mesma.
		if track.IsPlaying then
			-- Combo em andamento: so atualiza hitbox, sem tocar na animacao.
			if ctx.estado.acaoTick == tick and not ctx.destruido then
				if typeof(tick) == "number" then
					configurarHitboxParaSwing(ctx, track, tick)
				end
			end
		else
			-- Primeiro golpe ou novo combo (animacao nao esta tocando).
			if ctx.estado.acaoTick == tick and not ctx.destruido then
				if typeof(tick) == "number" then
					configurarHitboxParaSwing(ctx, track, tick)
				end
				track:Play(FADE_ENTRADA_ATAQUE)
			end
		end
	end
end

-- =============================================================================
-- Locomocao (NPC_LocomocaoNome / NPC_LocomocaoVelocidade).
-- =============================================================================

function aplicarLocomocao(ctx: Ctx)
	local nomeAttr = ctx.modelo:GetAttribute(TiposNPC.Chaves.LocomocaoNome) :: string?
	local vel = ctx.modelo:GetAttribute(TiposNPC.Chaves.LocomocaoVelocidade) :: number?
	local nome: string = (nomeAttr ~= nil and nomeAttr ~= "") and nomeAttr or "Idle"
	if not LOCOMOCAO_NAMES[nome] then
		return
	end
	tocarLocomocao(ctx, nome, vel)
end

-- =============================================================================
-- Sincronia de WeaponModel (NPC_ArmaPronta / NPC_ArmaEquipadaId).
-- =============================================================================

function sincronizarArmaVisual(ctx: Ctx)
	local pronta = ctx.modelo:GetAttribute(TiposNPC.Chaves.ArmaPronta) == true
	if pronta then
		-- Recria se faltar qualquer mao ou se a arma equipada mudou.
		local idAtual = (ctx.modelo:GetAttribute(TiposNPC.Chaves.ArmaEquipadaId) :: string?) or "punhos"
		if
			ctx.estado.armaVisualIdLocal ~= idAtual
			or not ctx.estado.WeaponModelLocalRight
			or not ctx.estado.WeaponModelLocalLeft
		then
			cancelarHitboxSwing(ctx)
			destruirWeaponModelsLocais(ctx)
			criarWeaponModelsLocais(ctx)
			ctx.estado.armaVisualIdLocal = idAtual
		end
	else
		cancelarHitboxSwing(ctx)
		destruirWeaponModelsLocais(ctx)
		ctx.estado.armaVisualIdLocal = nil
	end
end

-- =============================================================================
-- View pipeline.
-- =============================================================================

local function instalarSubscricoes(ctx: Ctx)
	local m = ctx.modelo
	local sinais = {
		TiposNPC.Chaves.Estado,
		TiposNPC.Chaves.Acao,
		TiposNPC.Chaves.AcaoTick,
		TiposNPC.Chaves.LocomocaoNome,
		TiposNPC.Chaves.LocomocaoVelocidade,
		TiposNPC.Chaves.ArmaPronta,
		TiposNPC.Chaves.ArmaEquipadaId,
	}

	for _, chave in sinais do
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
				elseif chave == TiposNPC.Chaves.ArmaPronta or chave == TiposNPC.Chaves.ArmaEquipadaId then
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
		-- Orientacao visual roda por frame (Heartbeat) para ser suave; o
		-- atualizar do Scheduler eh throttled e causaria jitter visivel.
		ViewBase.RastrearConexao(
			ctx,
			RunService.Heartbeat:Connect(function(dt)
				atualizarOrientacaoVisual(ctx, dt)
			end)
		)
		-- LOD comeca Distante; aplicamos quando promover via aoLOD.
	end,

	atualizar = function(_ctx: Ctx, _dt: number, _distancia: number) end,

	aoLOD = function(ctx: Ctx, novo: string, _anterior: string)
		if novo == TiposNPC.LOD.Distante then
			ViewBase.PararTodasAsTracks(ctx, FADE_REACAO_OUT)
			pararTodasLocomocao(ctx)
			ctx.estado.estadoTocando = nil
			ctx.estado.acaoTocando = nil
			ctx.estado.acaoTick = nil
			cancelarHitboxSwing(ctx)
			destruirWeaponModelsLocais(ctx)
			restaurarOrientacaoVisual(ctx)

			local conn = ctx.estado.equipStoppedConn
			if conn and conn.Connected then
				conn:Disconnect()
			end
			ctx.estado.equipStoppedConn = nil
		else
			-- Recarrega tudo ao reaproximar.
			aplicarTudoAgora(ctx)
		end
	end,

	destruir = function(ctx: Ctx)
		cancelarHitboxSwing(ctx)
		destruirWeaponModelsLocais(ctx)
		restaurarOrientacaoVisual(ctx)

		local conn = ctx.estado.equipStoppedConn
		if conn and conn.Connected then
			conn:Disconnect()
		end
		ctx.estado.equipStoppedConn = nil

		ViewBase.LimparTudo(ctx)
	end,
}

ViewBase.RegistrarView(Combate)

return Combate
