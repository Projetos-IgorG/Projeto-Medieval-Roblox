--[[
    Script: InicializarServidor.server.luau
    Caminho: src/ServerScriptService/Inicializacao
    Responsabilidade: Inicializa servicos centrais do projeto quando o servidor sobe.
    Uso: Script de servidor; roda automaticamente em src/ServerScriptService/Inicializacao quando a instancia existe no jogo.
    Nao faz: Nao controla UI local nem le inputs diretamente; recebe sinais ja autorizados pelo fluxo do jogo.
	Funcoes principais: CriarRemoto, ConfigurarEquipamentoPasta, ConfigurarStatusPasta, createValue
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

local Remotos = ReplicatedStorage:FindFirstChild("Remotos")
if not Remotos then
	Remotos = Instance.new("Folder")
	Remotos.Name = "Remotos"
	Remotos.Parent = ReplicatedStorage
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
CriarRemoto(Remotos, "NPC_HitReport", "Event")
CriarRemoto(Remotos, "DanoDebugVisual", "Event")

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
	createValue("BoolValue", "RollOn", false)
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
	"[ConfigIniciar] Setup de Status configurado (server-only: estadoAcao, BloqueandoOn, ProntoAparar, StunadoOn, RollOn, DashOn)"
)

local CombateServidor = ServerScriptService:WaitForChild("Combate"):WaitForChild("Servidor")
local _ControladorCombate = require(CombateServidor:WaitForChild("CombateServidor"))

DebugPrint("[Bootstrap] Modulos de combate carregados")

local ServicoDrop = require(ServerScriptService:WaitForChild("Inventario"):WaitForChild("Servidor"):WaitForChild("ServicoSoltarItem"))
local ModuloServicoArrastar = ServerScriptService:WaitForChild("Interacao"):WaitForChild("Arrastar"):WaitForChild("ArrastarServidor") :: ModuleScript
local ServicoArrastar = require(ModuloServicoArrastar)
local ServicosAmbiente = ServerScriptService:WaitForChild("Mundo"):WaitForChild("Ambiente")
local ServicoTempoMundo = require(ServicosAmbiente:WaitForChild("ServicoTempoMundo"))
local ServicoAmbienteMundo = require(ServicosAmbiente:WaitForChild("ServicoAmbienteMundo"))

local ServicoEquipamento = require(ServerScriptService:WaitForChild("Equipamentos"):WaitForChild("Servidor"):WaitForChild("ServicoEquipamentos"))

ServicoTempoMundo:Iniciar()
ServicoAmbienteMundo:Iniciar()
ServicoDrop:Iniciar()
ServicoArrastar:Iniciar()

if ServicoEquipamento then
	ServicoEquipamento:Iniciar()
	DebugPrint("[Bootstrap] EquipmentService inicializado")
end

DebugPrint("[Bootstrap] Servicos inicializados")

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
