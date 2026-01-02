--[[
    InicializadorCombate.server.lua
    
    Script principal do servidor que:
    - Inicializa o GerenciadorNPC
    - Escuta BindableEvent SpawnNPC para criar NPCs via chat
    - Garante que todos os sistemas de combate estejam ativos
    
    IMPORTANTE: Este script deve rodar DEPOIS do InicializadorRemotos
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

-- Aguarda remotos serem criados
local Bindables = ReplicatedStorage:WaitForChild("Bindables", 10)
if not Bindables then
    warn("[InicializadorCombate] Pasta Bindables não encontrada! Verifique InicializadorRemotos.")
    return
end

-- ═══════════════════════════════════════════════════════════════════
-- CARREGAR MÓDULOS
-- ═══════════════════════════════════════════════════════════════════

local Combate = ServerScriptService:WaitForChild("Combate")
local GerenciadorNPC = require(Combate:WaitForChild("GerenciadorNPC"))
local ControladorCombate = require(Combate:WaitForChild("ControladorCombate"))

print("[InicializadorCombate] Módulos carregados")

-- ═══════════════════════════════════════════════════════════════════
-- CRIAR PASTA NPCS SE NÃO EXISTIR
-- ═══════════════════════════════════════════════════════════════════

local pastaNPCs = workspace:FindFirstChild("NPCs")
if not pastaNPCs then
    pastaNPCs = Instance.new("Folder")
    pastaNPCs.Name = "NPCs"
    pastaNPCs.Parent = workspace
    print("[InicializadorCombate] Pasta NPCs criada")
end

-- ═══════════════════════════════════════════════════════════════════
-- TEMPLATE DE NPC BÁSICO
-- ═══════════════════════════════════════════════════════════════════

local function CriarNPCBasico(dados: {vida: number?, nome: string?, modo: string?, cframe: CFrame?}): Model?
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
        warn("[InicializadorCombate] Nenhum template de NPC encontrado. Crie um modelo NPCTemplate na ServerStorage.")
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

-- ═══════════════════════════════════════════════════════════════════
-- LISTENER DO BINDABLE EVENT SPAWNNPC
-- ═══════════════════════════════════════════════════════════════════

local SpawnNPC = Bindables:WaitForChild("SpawnNPC", 5)
if SpawnNPC then
    SpawnNPC.Event:Connect(function(dados)
        -- dados = {vida, nome, modo, cframe}
        print(string.format("[InicializadorCombate] SpawnNPC chamado: nome=%s, vida=%s, modo=%s", 
            tostring(dados.nome), tostring(dados.vida), tostring(dados.modo)))
        
        -- Cria NPC
        local npc = CriarNPCBasico(dados)
        
        if npc then
            print(string.format("[InicializadorCombate] NPC '%s' criado com sucesso!", npc.Name))
            -- O GerenciadorNPC já escuta ChildAdded na pasta NPCs
            -- então o NPC será registrado automaticamente
        else
            warn("[InicializadorCombate] Falha ao criar NPC. Verifique se há um template.")
        end
    end)
    
    print("[InicializadorCombate] Listener SpawnNPC conectado")
else
    warn("[InicializadorCombate] BindableEvent SpawnNPC não encontrado!")
end

-- ═══════════════════════════════════════════════════════════════════
-- INICIALIZAÇÃO DE JOGADORES
-- ═══════════════════════════════════════════════════════════════════

-- Garante que jogadores tenham máquina de estados quando entrarem
Players.PlayerAdded:Connect(function(jogador)
    jogador.CharacterAdded:Connect(function(personagem)
        -- Pequeno delay para garantir que o personagem está pronto
        task.wait(0.5)
        
        if personagem:FindFirstChildOfClass("Humanoid") then
            -- O ControladorCombate já cria a máquina via Setup.lua
            print(string.format("[InicializadorCombate] Jogador %s carregado", jogador.Name))
        end
    end)
end)

-- Processa jogadores já conectados
for _, jogador in ipairs(Players:GetPlayers()) do
    if jogador.Character and jogador.Character:FindFirstChildOfClass("Humanoid") then
        print(string.format("[InicializadorCombate] Jogador existente %s detectado", jogador.Name))
    end
end

print("[InicializadorCombate] Inicializado com sucesso!")
