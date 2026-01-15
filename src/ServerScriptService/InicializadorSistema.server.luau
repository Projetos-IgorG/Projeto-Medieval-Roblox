--[[
    InicializadorSistema.server.luau
    
    Script unificado que prepara o sistema de combate e jogadores:
    1. Cria RemoteEvents/RemoteFunctions (antes era InicializadorRemotos)
    2. Configura pasta Status de cada jogador (antes era Setup)
    3. Inicializa máquina de estados e NPC (antes era InicializadorCombate)
    
    Execução: Este script deve rodar PRIMEIRO na ServerScriptService
]]

-- ═══════════════════════════════════════════════════════════════════
-- CONFIGURAÇÃO DE DEBUG
-- ═══════════════════════════════════════════════════════════════════
local DEBUG_ENABLED = false -- Altere para true para habilitar prints de debug

local function DebugPrint(...)
	if DEBUG_ENABLED then
		print(...)
	end
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

DebugPrint("[InicializadorSistema] Iniciando...")

-- ═══════════════════════════════════════════════════════════════════
-- PARTE 1: CRIAR REMOTOS E BINDABLES
-- ═══════════════════════════════════════════════════════════════════

local function CriarRemoto(pasta, nome, tipo)
	local existente = pasta:FindFirstChild(nome)
	if existente then
		return existente
	end

	local remoto
	if tipo == "Event" then
		remoto = Instance.new("RemoteEvent")
	elseif tipo == "Function" then
		remoto = Instance.new("RemoteFunction")
	end

	remoto.Name = nome
	remoto.Parent = pasta

	return remoto
end

local function CriarBindable(pasta, nome, tipo)
	local existente = pasta:FindFirstChild(nome)
	if existente then
		return existente
	end

	local bindable
	if tipo == "Event" then
		bindable = Instance.new("BindableEvent")
	elseif tipo == "Function" then
		bindable = Instance.new("BindableFunction")
	end

	bindable.Name = nome
	bindable.Parent = pasta
	return bindable
end

-- Cria pasta principal de Remotos
local Remotos = ReplicatedStorage:FindFirstChild("Remotos")
if not Remotos then
	Remotos = Instance.new("Folder")
	Remotos.Name = "Remotos"
	Remotos.Parent = ReplicatedStorage
end

-- Cria pasta de Bindables (server-side)
local Bindables = ReplicatedStorage:FindFirstChild("Bindables")
if not Bindables then
	Bindables = Instance.new("Folder")
	Bindables.Name = "Bindables"
	Bindables.Parent = ReplicatedStorage
end

-- Remote Events: Cliente ↔ Servidor
CriarRemoto(Remotos, "TentarAcao", "Event")
CriarRemoto(Remotos, "MudarShiftLock", "Event")
CriarRemoto(Remotos, "SincronizarEstado", "Event")
CriarRemoto(Remotos, "TocarAnimacao", "Event")
CriarRemoto(Remotos, "EquipAnimacaoTerminou", "Event")
CriarRemoto(Remotos, "AcaoAnimacaoTerminou", "Event") -- Notifica quando animação de AÇÃO (ataque, etc) termina
CriarRemoto(Remotos, "AcaoRejeitada", "Event") -- Notifica cliente quando uma ação foi rejeitada (motivo)

-- BindableEvents: server-side apenas
CriarBindable(Bindables, "SpawnNPC", "Event")

DebugPrint("[InicializadorSistema] Remotos criados")

-- ═══════════════════════════════════════════════════════════════════
-- PARTE 2: SETUP DO STATUS FOLDER PARA JOGADORES
-- ═══════════════════════════════════════════════════════════════════

local function ConfigurarStatusPasta(Character)
	-- Cria pasta Status dentro do Character
	local statusFolder = Instance.new("Folder")
	statusFolder.Name = "Status"
	statusFolder.Parent = Character

	-- Função para criar valor se não existir
	local function createValue(className, name, default)
		local v = Instance.new(className)
		v.Name = name
		if typeof(default) ~= "nil" then
			v.Value = default
		end
		v.Parent = statusFolder
		return v
	end

	-- Cria os valores esperados pelo sistema de combate
	-- Estados
	createValue("StringValue", "modoAnimacao", "Base")
	createValue("StringValue", "estadoMov", "Parado")
	createValue("StringValue", "estadoAcao", "Nenhuma")

	-- Flags
	createValue("BoolValue", "ShiftLockOn", false)
	createValue("BoolValue", "AgachadoOn", false)
	createValue("BoolValue", "BloqueandoOn", false)
	createValue("BoolValue", "ProntoAparar", false)
	createValue("BoolValue", "StunadoOn", false)
	createValue("BoolValue", "CorrendoOn", false)
	createValue("BoolValue", "DashOn", false)

	-- Atributos de combate
	createValue("NumberValue", "Forca", 0)
	createValue("NumberValue", "CritChance", 0)
	createValue("NumberValue", "CritMult", 1.5)
end

local function RemoverAcessoriosNaoHair(Character)
	-- Remove acessórios que não sejam cabelo
	local parts = Character:GetChildren()
	for i = 1, #parts do
		local instanceA = parts[i]
		if instanceA.ClassName == "Accessory" then
			if not instanceA.Handle:FindFirstChild("HairAttachment") then
				parts[i]:Destroy()
			end
		end
	end
end

-- Listener para quando novo jogador entra
Players.PlayerAdded:Connect(function(Player)
	Player.CharacterAdded:Connect(function(Character)
		-- Cria Status folder
		ConfigurarStatusPasta(Character)
	end)

	Player.CharacterAppearanceLoaded:Connect(function(Character)
		-- Remove acessórios
		RemoverAcessoriosNaoHair(Character)
	end)
end)

DebugPrint("[InicializadorSistema] Setup de Status configurado")

-- ═══════════════════════════════════════════════════════════════════
-- PARTE 3: LISTENER DO SHIFTLOCKCHANGED
-- ═══════════════════════════════════════════════════════════════════

local ShiftLockChanged = ReplicatedStorage:FindFirstChild("ShiftLockChanged")
if not ShiftLockChanged then
	ShiftLockChanged = Instance.new("RemoteEvent")
	ShiftLockChanged.Name = "ShiftLockChanged"
	ShiftLockChanged.Parent = ReplicatedStorage
end

ShiftLockChanged.OnServerEvent:Connect(function(player, estado)
	local character = player.Character
	if not character then
		return
	end

	local status = character:FindFirstChild("Status")
	if status then
		local shiftLockValue = status:FindFirstChild("ShiftLockOn")
		if shiftLockValue then
			shiftLockValue.Value = estado
			DebugPrint(string.format("[ShiftLock] %s: ShiftLockOn atualizado para %s", player.Name, tostring(estado)))
		end
	end
end)

DebugPrint("[InicializadorSistema] Listener ShiftLock conectado")

-- ═══════════════════════════════════════════════════════════════════
-- PARTE 4: CARREGAMENTO DE MÓDULOS E INICIALIZAÇÃO NPC/COMBATE
-- ═══════════════════════════════════════════════════════════════════

-- Aguarda que o InicializadorSistema tenha criado os Remotos
local Combate = ServerScriptService:WaitForChild("Combate")
local _GerenciadorNPC = require(Combate:WaitForChild("GerenciadorNPC"))
local _ControladorCombate = require(Combate:WaitForChild("ControladorCombate"))

DebugPrint("[InicializadorSistema] Módulos de combate carregados")

-- ═══════════════════════════════════════════════════════════════════
-- PARTE 5: CRIAR PASTA NPCS
-- ═══════════════════════════════════════════════════════════════════

local pastaNPCs = workspace:FindFirstChild("NPCs")
if not pastaNPCs then
	pastaNPCs = Instance.new("Folder")
	pastaNPCs.Name = "NPCs"
	pastaNPCs.Parent = workspace
	DebugPrint("[InicializadorSistema] Pasta NPCs criada")
end

-- ═══════════════════════════════════════════════════════════════════
-- PARTE 6: TEMPLATE NPC BÁSICO E LISTENER SPAWNNPC
-- ═══════════════════════════════════════════════════════════════════

local function CriarNPCBasico(dados: { vida: number?, nome: string?, modo: string?, cframe: CFrame? }): Model?
	local posicao = dados.cframe or CFrame.new(0, 5, 0)
	local nome = dados.nome or "NPC_" .. math.random(1000, 9999)
	local vida = dados.vida or 100
	local modoCombate = dados.modo or "Punhos"

	-- Procura um template de NPC na ServerStorage
	local template = game.ServerStorage:FindFirstChild("NPCTemplate")
	local npc: Model? = nil

	if template then
		npc = template:Clone()
	else
		-- Tenta clonar o StarterCharacter se existir
		local starterCharacter = game.StarterPlayer:FindFirstChild("StarterCharacter")
		if starterCharacter then
			npc = starterCharacter:Clone()
		end
	end

	if not npc then
		warn("[InicializadorSistema] Nenhum template de NPC encontrado. Crie um modelo NPCTemplate na ServerStorage.")
		return nil
	end

	npc.Name = nome

	-- Configura posição
	local humanoidRoot = npc:FindFirstChild("HumanoidRootPart")
	if humanoidRoot then
		humanoidRoot.CFrame = posicao
	end

	-- Configura vida
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.MaxHealth = vida
		humanoid.Health = vida
	end

	-- Define modo de combate como atributo
	npc:SetAttribute("ModoCombate", modoCombate)

	npc.Parent = pastaNPCs
	return npc
end

-- Listener do BindableEvent SpawnNPC
local SpawnNPC = Bindables:WaitForChild("SpawnNPC", 5)
if SpawnNPC then
	SpawnNPC.Event:Connect(function(dados)
		DebugPrint(
			string.format(
				"[InicializadorSistema] SpawnNPC chamado: nome=%s, vida=%s, modo=%s",
				tostring(dados.nome),
				tostring(dados.vida),
				tostring(dados.modo)
			)
		)

		local npc = CriarNPCBasico(dados)

		if npc then
			DebugPrint(string.format("[InicializadorSistema] NPC '%s' criado com sucesso!", npc.Name))
		else
			warn("[InicializadorSistema] Falha ao criar NPC. Verifique se há um template.")
		end
	end)

	DebugPrint("[InicializadorSistema] Listener SpawnNPC conectado")
else
	warn("[InicializadorSistema] BindableEvent SpawnNPC não encontrado!")
end

-- ═══════════════════════════════════════════════════════════════════
-- PARTE 7: INICIALIZAÇÃO DE JOGADORES (MÁQUINA DE ESTADOS)
-- ═══════════════════════════════════════════════════════════════════

Players.PlayerAdded:Connect(function(jogador)
	jogador.CharacterAdded:Connect(function(personagem)
		-- Pequeno delay para garantir que o personagem está pronto
		task.wait(0.5)

		if personagem:FindFirstChildOfClass("Humanoid") then
			DebugPrint(string.format("[InicializadorSistema] Jogador %s carregado", jogador.Name))
		end
	end)
end)

-- Processa jogadores já conectados
for _, jogador in ipairs(Players:GetPlayers()) do
	if jogador.Character and jogador.Character:FindFirstChildOfClass("Humanoid") then
		DebugPrint(string.format("[InicializadorSistema] Jogador existente %s detectado", jogador.Name))
	end
end

DebugPrint("[InicializadorSistema] Inicializado com sucesso!")
