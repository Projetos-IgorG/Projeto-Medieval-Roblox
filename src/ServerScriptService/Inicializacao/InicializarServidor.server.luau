--[[
    Script: InicializarServidor.server.luau
    Caminho: src/ServerScriptService/Inicializacao
    Responsabilidade: Inicializa servicos centrais do projeto quando o servidor sobe.
    Uso: Script de servidor; roda automaticamente em src/ServerScriptService/Inicializacao quando a instancia existe no jogo.
    Nao faz: Nao controla UI local nem le inputs diretamente; recebe sinais ja autorizados pelo fluxo do jogo.
    Funcoes principais: CriarRemoto, CriarBindable, ConfigurarEquipamentoPasta, ConfigurarStatusPasta, createValue
]]
local DEBUG_ENABLED = false

local function DebugPrint(...)
	if DEBUG_ENABLED then
		print(...)
	end
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

DebugPrint("[ConfigIniciar] Iniciando...")

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

local Remotos = ReplicatedStorage:FindFirstChild("Remotos")
if not Remotos then
	Remotos = Instance.new("Folder")
	Remotos.Name = "Remotos"
	Remotos.Parent = ReplicatedStorage
end

local Bindables = ReplicatedStorage:FindFirstChild("Bindables")
if not Bindables then
	Bindables = Instance.new("Folder")
	Bindables.Name = "Bindables"
	Bindables.Parent = ReplicatedStorage
end

CriarRemoto(Remotos, "TentarAcao", "Event")
CriarRemoto(Remotos, "MudarShiftLock", "Event")
CriarRemoto(Remotos, "SincronizarEstado", "Event")
CriarRemoto(Remotos, "TocarAnimacao", "Event")
CriarRemoto(Remotos, "EquipAnimacaoTerminou", "Event")
CriarRemoto(Remotos, "AcaoAnimacaoTerminou", "Event")
CriarRemoto(Remotos, "AcaoRejeitada", "Event")
CriarRemoto(Remotos, "ArrastarItem", "Event")
CriarRemoto(Remotos, "EquipamentoAcao", "Event")
CriarRemoto(Remotos, "DroparTool", "Event")

local SistemaDialogo = ReplicatedStorage:FindFirstChild("Dialogo")
if SistemaDialogo then
	local DialogoRemotes = SistemaDialogo:FindFirstChild("DialogoRemotes")
	if not DialogoRemotes then
		DialogoRemotes = Instance.new("Folder")
		DialogoRemotes.Name = "DialogoRemotes"
		DialogoRemotes.Parent = SistemaDialogo
	end
	CriarRemoto(DialogoRemotes, "AcaoDialogo", "Event")
	CriarRemoto(DialogoRemotes, "SolicitarChatIA", "Event")
	CriarRemoto(DialogoRemotes, "RespostaChatIA", "Event")
end

CriarBindable(Bindables, "SpawnNPC", "Event")

DebugPrint("[ConfigIniciar] Remotos criados")

local function ConfigurarEquipamentoPasta(Character)
	local equipFolder = Instance.new("Folder")
	equipFolder.Name = "Equipamento"

	local bracosFolder = Instance.new("Folder")
	bracosFolder.Name = "Bracos"
	bracosFolder.Parent = equipFolder

	local rightArm = Instance.new("ObjectValue")
	rightArm.Name = "RightArm"
	rightArm.Parent = bracosFolder

	local leftArm = Instance.new("ObjectValue")
	leftArm.Name = "LeftArm"
	leftArm.Parent = bracosFolder

	local corpoFolder = Instance.new("Folder")
	corpoFolder.Name = "Corpo"
	corpoFolder.Parent = equipFolder

	for _, slotName in ipairs({ "Head", "Torso", "Legs", "Foot" }) do
		local slotOV = Instance.new("ObjectValue")
		slotOV.Name = slotName
		slotOV.Parent = corpoFolder
	end

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

	createValue("StringValue", "estadoAcao", "Nenhuma")

	createValue("BoolValue", "BloqueandoOn", false)
	createValue("BoolValue", "ProntoAparar", false)
	createValue("BoolValue", "StunadoOn", false)
	createValue("BoolValue", "DashOn", false)

	createValue("NumberValue", "Forca", 0)
	createValue("NumberValue", "CritChance", 0)
	createValue("NumberValue", "CritMult", 1.5)
end

local function AplicarRoupaPadrao(Character)

	for _, child in ipairs(Character:GetChildren()) do
		if child:IsA("Clothing") then
			child:Destroy()
		end
	end

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
		AplicarRoupaPadrao(Character)
	end)
end)

DebugPrint(
	"[ConfigIniciar] Setup de Status configurado (server-only: estadoAcao, BloqueandoOn, ProntoAparar, StunadoOn, DashOn)"
)

local CombateServidor = ServerScriptService:WaitForChild("Combate"):WaitForChild("Servidor")
local _GerenciadorNPC = require(CombateServidor:WaitForChild("GerenciadorNPCCombate"))
local _ControladorCombate = require(CombateServidor:WaitForChild("CombateServidor"))

DebugPrint("[Bootstrap] Modulos de combate carregados")

local ServicoDrop = require(ServerScriptService:WaitForChild("Inventario"):WaitForChild("Servidor"):WaitForChild("ServicoSoltarItem"))
local ModuloServicoArrastar = ServerScriptService:WaitForChild("Interacao"):WaitForChild("Arrastar"):WaitForChild("ArrastarServidor") :: ModuleScript
local ServicoArrastar = require(ModuloServicoArrastar)
local ServicoIAChat = require(ServerScriptService:WaitForChild("Dialogo"):WaitForChild("ChatIA"):WaitForChild("ChatIAServidor"))
local ServicosAmbiente = ServerScriptService:WaitForChild("Mundo"):WaitForChild("Ambiente")
local ServicoTempoMundo = require(ServicosAmbiente:WaitForChild("ServicoTempoMundo"))
local ServicoAmbienteMundo = require(ServicosAmbiente:WaitForChild("ServicoAmbienteMundo"))

local ServicoEquipamento = require(ServerScriptService:WaitForChild("Equipamentos"):WaitForChild("Servidor"):WaitForChild("ServicoEquipamentos"))

ServicoTempoMundo:Iniciar()
ServicoAmbienteMundo:Iniciar()
ServicoDrop:Iniciar()
ServicoArrastar:Iniciar()
ServicoIAChat:Iniciar()

if ServicoEquipamento then
	ServicoEquipamento:Iniciar()
	DebugPrint("[Bootstrap] EquipmentService inicializado")
end

DebugPrint("[Bootstrap] Servicos inicializados")

local pastaNPCs = workspace:FindFirstChild("NPCs")
if not pastaNPCs then
	pastaNPCs = Instance.new("Folder")
	pastaNPCs.Name = "NPCs"
	pastaNPCs.Parent = workspace
	DebugPrint("[ConfigIniciar] Pasta NPCs criada")
end

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

	local dadosFolder = npc:FindFirstChild("Dados")
	if not dadosFolder then
		dadosFolder = Instance.new("Folder")
		dadosFolder.Name = "Dados"
		dadosFolder.Parent = npc
	end

	local function GarantirValor(classe, nomeValor, valorPadrao)
		local valorExistente = dadosFolder:FindFirstChild(nomeValor)
		if not valorExistente then
			valorExistente = Instance.new(classe)
			valorExistente.Name = nomeValor
			valorExistente.Parent = dadosFolder
		end

		if valorExistente:IsA(classe) then
			valorExistente.Value = valorPadrao
		end
	end

	GarantirValor("StringValue", "Nome", nome)
	GarantirValor("StringValue", "Profissao", dados.profissao or "Generico")
	GarantirValor("StringValue", "Estado", dados.estado or "Livre")
	GarantirValor("StringValue", "TipoVoz", dados.tipoVoz or "Homem")
	GarantirValor("BoolValue", "CanChatAI", dados.canChatAI == true)
	GarantirValor("StringValue", "Contexto", dados.contexto or "")

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

local folderDeletar = workspace:FindFirstChild("Deletar")
if folderDeletar then
	folderDeletar:Destroy()
	DebugPrint("[ConfigIniciar] Pasta 'Deletar' removida do Workspace")
end

DebugPrint("[ConfigIniciar] Inicializado com sucesso!")
