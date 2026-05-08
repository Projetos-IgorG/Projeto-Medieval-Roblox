--!strict

--[[
	Script: ControladorCombateNPC.luau
	Caminho: src/ServerScriptService/NPC/Combate
	Responsabilidade: Replica server-side o pipeline canonico de combate do player
	    para NPCs - carrega/toca animacoes via Animator do servidor, escuta markers
	    da animacao para ativar hitbox shapecast em WeaponModelRight/Left reais
	    (clonados da arma equipada), e delega a resolucao de hit ao
	    CombateServidor (mesma maquina de estados, mesmo cooldown de combo,
	    mesmo parry/bloqueio/dano/knockback que o player).
	Uso: ModuleScript; require(ControladorCombateNPC) e use Iniciar/EquiparArma/
	    DesequiparArma/AtacarLeve/TocarLocomocao/PararAtaque/Destruir.
	Nao faz: Nao decide IA (alvo/distancia); apenas executa o que o comportamento
	    pedir. Nao toca animacoes de reacao (Aparado/Stunado/...) - estas continuam
	    sendo tocadas pela View no cliente, reagindo a NPC_Estado.
	Funcoes principais: Iniciar, EquiparArma, DesequiparArma, AtacarLeve,
	    TocarLocomocao, EstaArmaPronta, EstaAtacando, PararAtaque, Destruir
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Combate = ReplicatedStorage:WaitForChild("Combate")
local IdsCombate = require(Combate:WaitForChild("Animacoes"):WaitForChild("IdsAnimacoesCombate"))
local Modulo_Hitbox = require(Combate:WaitForChild("Hitbox"))
local Modulo_Combo = require(Combate:WaitForChild("Dominio"):WaitForChild("ComboCombate"))
local Modulo_Configuracoes = require(Combate:WaitForChild("Configuracoes"):WaitForChild("ConfigCombate"))

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

-- =============================================================================
-- Estado por NPC.
-- =============================================================================

type Estado = {
	modelo: Model,
	humanoide: Humanoid,
	animator: Animator,
	tracksAnim: { [string]: AnimationTrack },
	weaponModels: { [string]: Model },
	hitboxHandles: { [string]: any },
	raycastParams: RaycastParams,
	desconectarMarkers: (() -> ())?,
	conexoesAux: { RBXScriptConnection },
	indiceCombo: number,
	janelaAtiva: boolean,
	trackAtaqueAtual: AnimationTrack?,
	trackEquipAtual: AnimationTrack?,
	armaPronta: boolean,
	armaEquipada: Tool?,
	alcanceArma: number?,
	danoLeve: number,
	verificarAlvo: (() -> boolean)?,
	destruido: boolean,
}

local estados: { [Model]: Estado } = {}

local Mod = {}

local FADE_LOCOMOCAO = 0.18
local FADE_ENTRADA_ATAQUE = 0.16
local FADE_SAIDA_ATAQUE = 0.22
local FADE_CANCELAR_ATAQUE = 0.12

-- =============================================================================
-- Helpers internos.
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

local function obterTemplateWeaponModel(s: Estado): Model?
	local tool = resolverArmaEquipada(s)
	local weaponModel = tool and tool:FindFirstChild("WeaponModel")
	if weaponModel and weaponModel:IsA("Model") then
		return weaponModel
	end
	return nil
end

local function carregarTrack(animator: Animator, id: string?): AnimationTrack?
	if not id or id == "" then
		return nil
	end
	if string.find(id, "0000000000", 1, true) then
		return nil
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	local ok, tr = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	anim:Destroy()
	if not ok or not tr then
		return nil
	end
	return tr
end

local function pararAnimsExceto(s: Estado, manter: AnimationTrack?, tempoFade: number?)
	for _, t in s.tracksAnim do
		if t ~= manter and t.IsPlaying then
			t:Stop(tempoFade or FADE_LOCOMOCAO)
		end
	end
end

-- Nomes considerados de locomocao (Movement priority). Sao tratados em grupo:
-- so uma toca por vez, e nao sao paradas quando um ataque (Action priority)
-- comeca - assim o NPC pode recuar/andar de lado enquanto ataca.
local LOCOMOCAO_NAMES: { [string]: boolean } = {
	Idle = true,
	Andando = true,
	AndandoDireita = true,
	AndandoEsquerda = true,
	Correndo = true,
	CorrendoDireita = true,
	CorrendoEsquerda = true,
}

local function pararLocomocaoExceto(s: Estado, manter: AnimationTrack?)
	for nome, t in s.tracksAnim do
		if LOCOMOCAO_NAMES[nome] and t ~= manter and t.IsPlaying then
			t:Stop(FADE_LOCOMOCAO)
		end
	end
end

local function tocarLoop(s: Estado, nome: string, velocidadeAnimacao: number?)
	local t = s.tracksAnim[nome]
	if not t then
		return
	end
	pararLocomocaoExceto(s, t)
	t.Looped = true
	if not t.IsPlaying then
		t:Play(FADE_LOCOMOCAO)
	end
	t:AdjustSpeed(velocidadeAnimacao or 1)
end

local function pararHitboxes(s: Estado)
	for _, h in s.hitboxHandles do
		Modulo_Hitbox.PararHitbox(h)
	end
end

local function destruirHitboxes(s: Estado)
	for _, h in s.hitboxHandles do
		Modulo_Hitbox.DestruirHitbox(h)
	end
	table.clear(s.hitboxHandles)
end

local function ativarHitboxMao(s: Estado, mao: string, duracao: number?)
	if mao ~= "Right" and mao ~= "Left" then
		return
	end
	local wm = s.weaponModels[mao]
	if not wm or not wm.Parent then
		return
	end

	-- Reseta hitbox dessa mao para um novo golpe (limpa jaAtingidos).
	local existente = s.hitboxHandles[mao]
	if existente then
		Modulo_Hitbox.DestruirHitbox(existente)
		s.hitboxHandles[mao] = nil
	end

	local handle = Modulo_Hitbox.CriarHitbox(wm, mao :: any, s.raycastParams)
	if not handle then
		return
	end
	s.hitboxHandles[mao] = handle

	Modulo_Hitbox.AtivarHitbox(handle, function(alvo: Model, _maoHit)
		if s.destruido then
			return
		end
		if not alvo or alvo == s.modelo then
			return
		end
		local cs = obterCS()
		if not cs or not cs._ProcessarHit then
			return
		end
		pcall(cs._ProcessarHit, s.modelo, alvo, "AtaqueLeve", s.danoLeve)
	end, duracao or 0.4)
end

local function limparMarkersAtaque(s: Estado)
	if s.desconectarMarkers then
		s.desconectarMarkers()
		s.desconectarMarkers = nil
	end
	for _, c in s.conexoesAux do
		if c.Connected then
			c:Disconnect()
		end
	end
	table.clear(s.conexoesAux)
end

local function finalizarCombo(s: Estado, restauraIdle: boolean, atrasoIdle: number?)
	destruirHitboxes(s)
	limparMarkersAtaque(s)
	s.indiceCombo = 0
	s.janelaAtiva = false
	s.trackAtaqueAtual = nil

	-- Notifica a maquina canonica que o combo terminou (libera estado e cooldown).
	local cs = obterCS()
	if cs and cs.ProcessarComboTerminou then
		pcall(cs.ProcessarComboTerminou, s.modelo)
	end

	if restauraIdle and not s.destruido and s.armaPronta then
		local atraso = atrasoIdle or 0
		if atraso > 0 then
			task.delay(atraso, function()
				if not s.destruido and s.armaPronta and not s.trackAtaqueAtual then
					tocarLoop(s, "Idle")
				end
			end)
		else
			tocarLoop(s, "Idle")
		end
	end
end

local function instalarMarkersAtaque(s: Estado, track: AnimationTrack)
	limparMarkersAtaque(s)
	s.indiceCombo = 0
	s.janelaAtiva = false

	s.desconectarMarkers = Modulo_Combo.ConfigurarListenersMarcadores(track, {
		onAtaqueDireita = function(_indice)
			ativarHitboxMao(s, "Right", 0.35)
		end,
		onAtaqueEsquerda = function(_indice)
			ativarHitboxMao(s, "Left", 0.35)
		end,
		onAtaqueAmbos = function(_indice)
			ativarHitboxMao(s, "Right", 0.35)
			ativarHitboxMao(s, "Left", 0.35)
		end,
		onAtaqueFim = function()
			pararHitboxes(s)
		end,
		onJanelaCombo = function(_ehFinal)
			s.indiceCombo = s.indiceCombo + 1
			s.janelaAtiva = true
			if s.verificarAlvo and not s.verificarAlvo() then
				local t = s.trackAtaqueAtual
				if t then
					s.trackAtaqueAtual = nil
					pcall(function()
						t:Stop(FADE_SAIDA_ATAQUE)
					end)
				end
				finalizarCombo(s, true, FADE_SAIDA_ATAQUE * 0.75)
				return
			end
			local cs = obterCS()
			if cs and cs.ProcessarComboHitbox then
				pcall(cs.ProcessarComboHitbox, s.modelo, { indice = s.indiceCombo })
			end
		end,
	})

	local conn = track.Stopped:Connect(function()
		if s.trackAtaqueAtual == track then
			finalizarCombo(s, true)
		end
	end)
	table.insert(s.conexoesAux, conn)
end

-- =============================================================================
-- WeaponModel: clona o template da arma equipada para os bracos do NPC com Motor6D.
-- =============================================================================

local SUFIXO_PARA_BRACO = {
	Right = "Right Arm",
	Left = "Left Arm",
}
local SUFIXO_PARA_SLOT = {
	Right = "RightArm",
	Left = "LeftArm",
}

local function criarWeaponModelMao(s: Estado, mao: string): Model?
	local nomeBraco = SUFIXO_PARA_BRACO[mao]
	if not nomeBraco then
		return nil
	end
	local template = obterTemplateWeaponModel(s)
	if not template then
		return nil
	end
	local armPart = s.modelo:FindFirstChild(nomeBraco) :: BasePart?
	if not armPart then
		return nil
	end

	-- Limpa anteriores (defensivo se algo ficou pendurado).
	local existente = s.modelo:FindFirstChild("WeaponModel" .. mao)
	if existente then
		existente:Destroy()
	end
	local jointName = SUFIXO_PARA_SLOT[mao] .. "_WeaponJoint"
	local jointAnt = armPart:FindFirstChild(jointName)
	if jointAnt then
		jointAnt:Destroy()
	end

	local clone = template:Clone()
	clone.Name = "WeaponModel" .. mao

	local handle = clone:FindFirstChild("Handle") :: BasePart?
	if not handle then
		clone:Destroy()
		return nil
	end
	handle.Name = "Handle" .. mao

	-- Replica o preparo do player para nao deixar a arma ancorada no NPC.
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

	clone.Parent = s.modelo
	handle.CFrame = armPart.CFrame * CFrame.new(0, -1, 0) * CFrame.Angles(math.rad(-90), 0, 0)

	local joint = Instance.new("Motor6D")
	joint.Name = jointName
	joint.Part0 = armPart
	joint.Part1 = handle
	joint.C0 = armPart.CFrame:Inverse() * handle.CFrame
	joint.C1 = CFrame.new()
	joint.Parent = armPart

	s.weaponModels[mao] = clone
	return clone
end

local function criarAmbosWeaponModels(s: Estado)
	criarWeaponModelMao(s, "Right")
	criarWeaponModelMao(s, "Left")
	s.armaPronta = next(s.weaponModels) ~= nil
end

local function destruirWeaponModels(s: Estado)
	destruirHitboxes(s)
	for mao, wm in s.weaponModels do
		local nomeBraco = SUFIXO_PARA_BRACO[mao]
		local arm = nomeBraco and s.modelo:FindFirstChild(nomeBraco) :: BasePart?
		if arm then
			local jname = SUFIXO_PARA_SLOT[mao] .. "_WeaponJoint"
			local j = arm:FindFirstChild(jname)
			if j then
				j:Destroy()
			end
		end
		if wm and wm.Parent then
			wm:Destroy()
		end
	end
	table.clear(s.weaponModels)
	s.armaPronta = false
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
	local an: Animator? = hum:FindFirstChildOfClass("Animator") :: Animator?
	if not an then
		local novoAnimator = Instance.new("Animator")
		novoAnimator.Parent = hum
		an = novoAnimator
	end

	local s: Estado = {
		modelo = modelo,
		humanoide = hum,
		animator = an :: Animator,
		tracksAnim = {},
		weaponModels = {},
		hitboxHandles = {},
		raycastParams = Modulo_Hitbox.CriarRaycastParamsAtacante(modelo),
		desconectarMarkers = nil,
		conexoesAux = {},
		indiceCombo = 0,
		janelaAtiva = false,
		trackAtaqueAtual = nil,
		trackEquipAtual = nil,
		armaPronta = false,
		armaEquipada = nil,
		alcanceArma = nil,
		danoLeve = (modelo:GetAttribute("DanoLeve") :: number?) or 8,
		verificarAlvo = nil,
		destruido = false,
	}
	estados[modelo] = s

	-- Pre-carrega tracks de Punhos (server-side, replica para clientes).
	local pun = (IdsCombate :: any).Punhos and (IdsCombate :: any).Punhos.animacoes or {}
	local nomes = {
		"Idle",
		"Andando",
		"AndandoDireita",
		"AndandoEsquerda",
		"Correndo",
		"CorrendoDireita",
		"CorrendoEsquerda",
		"Equipar",
		"Desequipar",
		"AtaqueLeve",
	}
	for _, nome in nomes do
		local tr = carregarTrack(s.animator, pun[nome])
		if tr then
			s.tracksAnim[nome] = tr
		end
	end

	-- Comeca em Idle (com a animacao base do modo Punhos, sem WeaponModel).
	tocarLoop(s, "Idle")
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
	if not s then
		return false
	end
	return s.trackAtaqueAtual ~= nil and s.trackAtaqueAtual.IsPlaying
end

function Mod.EstaEquipando(modelo: Model): boolean
	local s = estados[modelo]
	if not s then
		return false
	end
	return s.trackEquipAtual ~= nil and s.trackEquipAtual.IsPlaying
end

function Mod.EquiparArma(modelo: Model)
	local s = estados[modelo] or Mod.Iniciar(modelo)
	if not s then
		return
	end
	if s.armaPronta then
		return
	end
	if s.trackEquipAtual and s.trackEquipAtual.IsPlaying then
		return
	end

	local track = s.tracksAnim["Equipar"]
	if not track then
		criarAmbosWeaponModels(s)
		return
	end

	pararAnimsExceto(s, track)
	track.Looped = false
	track:Play(0.1)
	s.trackEquipAtual = track

	local equipConn: RBXScriptConnection? = nil
	local stoppedConn: RBXScriptConnection? = nil

	equipConn = track:GetMarkerReachedSignal("Equip"):Connect(function()
		if s.destruido then
			return
		end
		criarAmbosWeaponModels(s)
		if equipConn then
			equipConn:Disconnect()
			equipConn = nil
		end
	end)

	stoppedConn = track.Stopped:Connect(function()
		if not s.armaPronta and not s.destruido then
			criarAmbosWeaponModels(s)
		end
		if equipConn then
			equipConn:Disconnect()
			equipConn = nil
		end
		if stoppedConn then
			stoppedConn:Disconnect()
			stoppedConn = nil
		end
		if s.trackEquipAtual == track then
			s.trackEquipAtual = nil
		end
		if not s.destruido then
			tocarLoop(s, "Idle")
		end
	end)
end

function Mod.DesequiparArma(modelo: Model)
	local s = estados[modelo]
	if not s then
		return
	end
	if not s.armaPronta then
		return
	end
	if s.trackEquipAtual and s.trackEquipAtual.IsPlaying then
		return
	end

	-- Cancela ataque em curso antes de desequipar.
	if s.trackAtaqueAtual then
		local t = s.trackAtaqueAtual
		s.trackAtaqueAtual = nil
		pcall(function()
			t:Stop(0.15)
		end)
		finalizarCombo(s, false)
	end

	local track = s.tracksAnim["Desequipar"]
	if not track then
		destruirWeaponModels(s)
		return
	end

	pararAnimsExceto(s, track)
	track.Looped = false
	track:Play(0.1)
	s.trackEquipAtual = track

	local desConn: RBXScriptConnection? = nil
	local stoppedConn: RBXScriptConnection? = nil

	desConn = track:GetMarkerReachedSignal("Desequip"):Connect(function()
		if s.destruido then
			return
		end
		destruirWeaponModels(s)
		if desConn then
			desConn:Disconnect()
			desConn = nil
		end
	end)

	stoppedConn = track.Stopped:Connect(function()
		if s.armaPronta and not s.destruido then
			destruirWeaponModels(s)
		end
		if desConn then
			desConn:Disconnect()
			desConn = nil
		end
		if stoppedConn then
			stoppedConn:Disconnect()
			stoppedConn = nil
		end
		if s.trackEquipAtual == track then
			s.trackEquipAtual = nil
		end
		if not s.destruido then
			tocarLoop(s, "Idle")
		end
	end)
end

function Mod.TocarLocomocao(modelo: Model, nome: string, velocidadeAnimacao: number?)
	local s = estados[modelo]
	if not s then
		return
	end
	if s.trackEquipAtual and s.trackEquipAtual.IsPlaying then
		return
	end
	if not LOCOMOCAO_NAMES[nome] then
		return
	end
	-- Locomocao toca em paralelo com ataque (Action priority sobrepoe Movement).
	tocarLoop(s, nome, velocidadeAnimacao)
end

function Mod.AtacarLeve(modelo: Model, verificarAlvo: (() -> boolean)?): boolean
	local s = estados[modelo]
	if not s then
		return false
	end
	if not s.armaPronta then
		return false
	end
	if s.trackAtaqueAtual and s.trackAtaqueAtual.IsPlaying then
		return false
	end
	if s.trackEquipAtual and s.trackEquipAtual.IsPlaying then
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

	-- Garante modo Punhos na maquina canonica para resolver impulso/knockback.
	if maquina.DefinirModo then
		maquina:DefinirModo("Punhos")
	end

	local ok, tipoAtaque = maquina:TenteAtacarLeveEmPe()
	if not ok or not tipoAtaque then
		return false
	end

	-- Impulso a frente (mesmo do player).
	if cs._AplicarImpulsoAtacante then
		pcall(cs._AplicarImpulsoAtacante, modelo, tipoAtaque)
	end

	-- Reduz velocidade durante o ataque (mesmo padrao do ProcessarAtacarLeveEmPe).
	local velBloq = Modulo_Configuracoes.ObterConfiguracao("VelocidadeBloqueando") or 6
	s.humanoide.WalkSpeed = velBloq * 1.5

	-- Toca anim no Animator do servidor (replica para clientes + markers no server).
	-- IMPORTANTE: NAO paramos as tracks de locomocao - elas continuam por baixo
	-- (Action priority do AtaqueLeve sobrepoe Movement nos joints comuns), o que
	-- permite o NPC recuar/orbitar enquanto ataca.
	local track = s.tracksAnim["AtaqueLeve"]
	if not track then
		if cs.ProcessarComboTerminou then
			pcall(cs.ProcessarComboTerminou, modelo)
		end
		return false
	end

	if s.trackEquipAtual then
		local e = s.trackEquipAtual
		s.trackEquipAtual = nil
		pcall(function()
			e:Stop(FADE_CANCELAR_ATAQUE)
		end)
	end
	if s.trackAtaqueAtual and s.trackAtaqueAtual ~= track then
		local anterior = s.trackAtaqueAtual
		pcall(function()
			anterior:Stop(FADE_CANCELAR_ATAQUE)
		end)
	end
	track.Looped = false
	track:Play(FADE_ENTRADA_ATAQUE)
	s.trackAtaqueAtual = track

	instalarMarkersAtaque(s, track)
	return true
end

-- Para hitboxes, limpa markers e cancela qualquer ataque em curso. NAO mexe em
-- weaponModels nem em equip. Usado quando a maquina canonica entra em estados
-- de reacao (Aparado/Stunado/DefesaQuebrada) - a View no cliente toma a
-- animacao a partir de NPC_Estado.
function Mod.PararAtaque(modelo: Model)
	local s = estados[modelo]
	if not s then
		return
	end
	if s.trackAtaqueAtual then
		local t = s.trackAtaqueAtual
		s.trackAtaqueAtual = nil
		pcall(function()
			t:Stop(FADE_CANCELAR_ATAQUE)
		end)
	end
	s.verificarAlvo = nil
	finalizarCombo(s, false)
end

function Mod.Destruir(modelo: Model)
	local s = estados[modelo]
	if not s then
		return
	end
	s.destruido = true
	limparMarkersAtaque(s)
	destruirWeaponModels(s)
	for _, t in s.tracksAnim do
		pcall(function()
			t:Stop(0)
		end)
	end
	table.clear(s.tracksAnim)
	estados[modelo] = nil
end

return Mod
