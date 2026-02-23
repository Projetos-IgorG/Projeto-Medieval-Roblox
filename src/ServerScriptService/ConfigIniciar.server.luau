--[[
    ConfigIniciar.server.luau
    
    Script unificado que prepara o sistema de combate e jogadores:
    1. Cria RemoteEvents/RemoteFunctions
    2. Configura pasta Status de cada jogador
    3. Inicializa máquina de estados e NPC
    4. Carrega e inicializa todos os Serviços
    
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

DebugPrint("[ConfigIniciar] Iniciando...")

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
CriarRemoto(Remotos, "AcaoAnimacaoTerminou", "Event")
CriarRemoto(Remotos, "AcaoRejeitada", "Event")
CriarRemoto(Remotos, "ArrastarItem", "Event") -- Sistema de arrastar itens
CriarRemoto(Remotos, "DroparTool", "Event") -- Sistema de drop customizado
CriarRemoto(Remotos, "AplicarKnockback", "Event") -- Sistema de knockback físico
CriarRemoto(Remotos, "EquipamentoAcao", "Event") -- Sistema de equipamento

-- Sistema de Diálogo
local Modulos = ReplicatedStorage:FindFirstChild("Modulos")
if Modulos then
	local SistemaDialogo = Modulos:FindFirstChild("SistemaDialogo")
	if SistemaDialogo then
		local DialogoRemotes = SistemaDialogo:FindFirstChild("DialogoRemotes")
		if not DialogoRemotes then
			DialogoRemotes = Instance.new("Folder")
			DialogoRemotes.Name = "DialogoRemotes"
			DialogoRemotes.Parent = SistemaDialogo
		end
		CriarRemoto(DialogoRemotes, "AcaoDialogo", "Event")
	end
end

-- BindableEvents: server-side apenas
CriarBindable(Bindables, "SpawnNPC", "Event")

DebugPrint("[ConfigIniciar] Remotos criados")

-- ═══════════════════════════════════════════════════════════════════
-- PARTE 2: SETUP DO STATUS FOLDER PARA JOGADORES
-- ═══════════════════════════════════════════════════════════════════

local function ConfigurarEquipamentoPasta(Character)
	local equipFolder = Instance.new("Folder")
	equipFolder.Name = "Equipamento"

	-- Bracos (ObjectValues para RightArm e LeftArm)
	local bracosFolder = Instance.new("Folder")
	bracosFolder.Name = "Bracos"
	bracosFolder.Parent = equipFolder

	local rightArm = Instance.new("ObjectValue")
	rightArm.Name = "RightArm"
	rightArm.Parent = bracosFolder

	local leftArm = Instance.new("ObjectValue")
	leftArm.Name = "LeftArm"
	leftArm.Parent = bracosFolder

	-- Corpo (ObjectValues para slots de armadura)
	local corpoFolder = Instance.new("Folder")
	corpoFolder.Name = "Corpo"
	corpoFolder.Parent = equipFolder

	for _, slotName in ipairs({ "Head", "Torso", "Legs", "Foot" }) do
		local slotOV = Instance.new("ObjectValue")
		slotOV.Name = slotName
		slotOV.Parent = corpoFolder
	end

	-- EquipamentosAtivos (armazena Tools não-selecionáveis: escudos, flechas, armaduras)
	local equipAtivos = Instance.new("Folder")
	equipAtivos.Name = "EquipamentosAtivos"
	equipAtivos.Parent = equipFolder

	equipFolder.Parent = Character
end

local function ConfigurarStatusPasta(Character)
	local statusFolder = Instance.new("Folder")
	statusFolder.Name = "Status"
	statusFolder.Parent = Character

	local function createValue(className, name, default)
		local v = Instance.new(className)
		v.Name = name
		if typeof(default) ~= "nil" then
			v.Value = default
		end
		v.Parent = statusFolder
		return v
	end

	-- Estados de ação (server-authoritative)
	-- NOTA: modoAnimacao, estadoMov, ShiftLockOn, AgachadoOn, CorrendoOn agora são gerenciados
	-- pelo client na pasta StatusLocal (ver StatusLocal.client.luau)
	createValue("StringValue", "estadoAcao", "Nenhuma")

	-- Flags de combate (server-authoritative)
	createValue("BoolValue", "BloqueandoOn", false)
	createValue("BoolValue", "ProntoAparar", false)
	createValue("BoolValue", "StunadoOn", false)
	createValue("BoolValue", "DashOn", false)

	-- Atributos de combate
	createValue("NumberValue", "Forca", 0)
	createValue("NumberValue", "CritChance", 0)
	createValue("NumberValue", "CritMult", 1.5)
end

local function RemoverAcessoriosNaoHair(Character)
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

--- Aplica roupa padrão medieval ao personagem
--- Remove qualquer Clothing genérico e garante Shirt/Pants corretos
local function AplicarRoupaPadrao(Character)
	-- Remover TODAS as instâncias de Clothing (base class), Shirt e Pants existentes
	for _, child in ipairs(Character:GetChildren()) do
		if child:IsA("Clothing") then
			child:Destroy()
		end
	end

	-- Criar Shirt e Pants do zero com os templates medievais
	local shirt = Instance.new("Shirt")
	shirt.ShirtTemplate = "rbxassetid://79449264778033"
	shirt.Parent = Character

	local pants = Instance.new("Pants")
	pants.PantsTemplate = "rbxassetid://73726278525951"
	pants.Parent = Character
end

Players.PlayerAdded:Connect(function(Player)
	Player.CharacterAdded:Connect(function(Character)
		ConfigurarStatusPasta(Character)
		ConfigurarEquipamentoPasta(Character)
	end)

	Player.CharacterAppearanceLoaded:Connect(function(Character)
		RemoverAcessoriosNaoHair(Character)
		AplicarRoupaPadrao(Character)
	end)
end)

DebugPrint(
	"[ConfigIniciar] Setup de Status configurado (server-only: estadoAcao, BloqueandoOn, ProntoAparar, StunadoOn, DashOn)"
)

-- NOTA: ShiftLockChanged listener removido - client gerencia ShiftLockOn localmente
-- e envia o estado junto com a ação de bloqueio quando necessário

-- ═══════════════════════════════════════════════════════════════════
-- PARTE 4: CARREGAMENTO DE MÓDULOS DE COMBATE
-- ═══════════════════════════════════════════════════════════════════

local Servicos = ServerScriptService:WaitForChild("Servicos")
local Combate = Servicos:WaitForChild("Combate")
local _GerenciadorNPC = require(Combate:WaitForChild("GerenciadorNPC"))
local _ControladorCombate = require(Combate:WaitForChild("ControladorCombate"))

DebugPrint("[ConfigIniciar] Módulos de combate carregados")

-- ═══════════════════════════════════════════════════════════════════
-- PARTE 5: CARREGAR E INICIAR SERVIÇOS
-- ═══════════════════════════════════════════════════════════════════

local ServicoDrop = require(Servicos.Inventario:WaitForChild("ServicoDrop"))
local ServicoArrastar = require(Servicos.Interacoes:WaitForChild("ServicoArrastar"))
local ServicoPortal = require(Servicos:WaitForChild("ServicoPortal"))

-- Sistema de Equipamento
local InventarioFolder = Servicos:FindFirstChild("Inventario")
local ServicoEquipamento = nil
if InventarioFolder then
	local equipModule = InventarioFolder:FindFirstChild("ServicoEquipamento")
	if equipModule then
		ServicoEquipamento = require(equipModule)
	end
end

ServicoDrop:Iniciar()
ServicoArrastar:Iniciar()
ServicoPortal:Iniciar()

if ServicoEquipamento then
	ServicoEquipamento:Iniciar()
	DebugPrint("[ConfigIniciar] ServicoEquipamento inicializado")
end

DebugPrint("[ConfigIniciar] Serviços inicializados")

-- ═══════════════════════════════════════════════════════════════════
-- PARTE 6: CRIAR PASTA NPCS
-- ═══════════════════════════════════════════════════════════════════

local pastaNPCs = workspace:FindFirstChild("NPCs")
if not pastaNPCs then
	pastaNPCs = Instance.new("Folder")
	pastaNPCs.Name = "NPCs"
	pastaNPCs.Parent = workspace
	DebugPrint("[ConfigIniciar] Pasta NPCs criada")
end

-- ═══════════════════════════════════════════════════════════════════
-- PARTE 7: TEMPLATE NPC BÁSICO E LISTENER SPAWNNPC
-- ═══════════════════════════════════════════════════════════════════

local function CriarNPCBasico(dados)
	local posicao = dados.cframe or CFrame.new(0, 5, 0)
	local nome = dados.nome or "NPC_" .. math.random(1000, 9999)
	local vida = dados.vida or 100
	local modoCombate = dados.modo or "Punhos"

	local template = game.ServerStorage:FindFirstChild("NPCTemplate")
	local npc = nil

	if template then
		npc = template:Clone()
	else
		local starterCharacter = game.StarterPlayer:FindFirstChild("StarterCharacter")
		if starterCharacter then
			npc = starterCharacter:Clone()
		end
	end

	if not npc then
		warn("[ConfigIniciar] Nenhum template de NPC encontrado. Crie um modelo NPCTemplate na ServerStorage.")
		return nil
	end

	npc.Name = nome

	local humanoidRoot = npc:FindFirstChild("HumanoidRootPart")
	if humanoidRoot then
		humanoidRoot.CFrame = posicao
	end

	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.MaxHealth = vida
		humanoid.Health = vida
	end

	npc:SetAttribute("ModoCombate", modoCombate)
	npc.Parent = pastaNPCs
	return npc
end

local SpawnNPC = Bindables:WaitForChild("SpawnNPC", 5)
if SpawnNPC then
	SpawnNPC.Event:Connect(function(dados)
		DebugPrint(
			string.format(
				"[ConfigIniciar] SpawnNPC chamado: nome=%s, vida=%s, modo=%s",
				tostring(dados.nome),
				tostring(dados.vida),
				tostring(dados.modo)
			)
		)

		local npc = CriarNPCBasico(dados)

		if npc then
			DebugPrint(string.format("[ConfigIniciar] NPC '%s' criado com sucesso!", npc.Name))
		else
			warn("[ConfigIniciar] Falha ao criar NPC. Verifique se há um template.")
		end
	end)

	DebugPrint("[ConfigIniciar] Listener SpawnNPC conectado")
else
	warn("[ConfigIniciar] BindableEvent SpawnNPC não encontrado!")
end

-- ═══════════════════════════════════════════════════════════════════
-- PARTE 8: INICIALIZAÇÃO DE JOGADORES (MÁQUINA DE ESTADOS)
-- ═══════════════════════════════════════════════════════════════════

Players.PlayerAdded:Connect(function(jogador)
	jogador.CharacterAdded:Connect(function(personagem)
		task.wait(0.5)
		if personagem:FindFirstChildOfClass("Humanoid") then
			DebugPrint(string.format("[ConfigIniciar] Jogador %s carregado", jogador.Name))
		end
	end)
end)

for _, jogador in ipairs(Players:GetPlayers()) do
	if jogador.Character and jogador.Character:FindFirstChildOfClass("Humanoid") then
		DebugPrint(string.format("[ConfigIniciar] Jogador existente %s detectado", jogador.Name))
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- PARTE 9: LIMPEZA DE WORKSPACE
-- ═══════════════════════════════════════════════════════════════════

local folderDeletar = workspace:FindFirstChild("Deletar")
if folderDeletar then
	folderDeletar:Destroy()
	DebugPrint("[ConfigIniciar] Pasta 'Deletar' removida do Workspace")
end

DebugPrint("[ConfigIniciar] Inicializado com sucesso!")
