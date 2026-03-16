--[[
    StatusLocal.client.luau
    
    Script local que cria e gerencia a pasta StatusLocal no character.
    Esta pasta contém atributos de estado que são gerenciados 100% pelo cliente
    para evitar latência e sincronização desnecessária com o servidor.
    
    Atributos client-side:
    - modoAnimacao: String, modo de animação atual (Base, Espada, etc.)
    - estadoMov: String, estado de movimento (Parado, Andando, Correndo, etc.)
    - ShiftLockOn: Bool, câmera travada (ShiftLock/1ª pessoa)
    - AgachadoOn: Bool, jogador agachado
    - CorrendoOn: Bool, jogador correndo
    
    Atributos que permanecem no servidor (pasta Status):
    - estadoAcao, BloqueandoOn, ProntoAparar, StunadoOn, DashOn
]]

local debug = false

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Ponte de comunicação entre scripts client-side (substitui _G)
local ClientBridge =
	require(ReplicatedStorage:WaitForChild("Modulos"):WaitForChild("Core"):WaitForChild("ClientBridge"))

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local StatusLocalManager = require(ReplicatedStorage:WaitForChild("Modulos"):WaitForChild("Cliente"):WaitForChild("Estado"):WaitForChild("StatusLocalManager"))

-- ═══════════════════════════════════════════════════════════════════
-- CRIAR PASTA STATUSLOCAL
-- ═══════════════════════════════════════════════════════════════════

-- Cria para character atual
local _statusLocal = StatusLocalManager.CriarStatusLocal(character)

-- Recria quando respawnar
player.CharacterAdded:Connect(function(newCharacter)
	character = newCharacter
	_statusLocal = StatusLocalManager.CriarStatusLocal(newCharacter)
end)

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES PARA ATUALIZAR STATUSLOCAL (via ClientBridge)
-- ═══════════════════════════════════════════════════════════════════

--- Obtém a pasta StatusLocal do character atual
local function ObterStatusLocal(): Folder?
	return StatusLocalManager.ObterStatusLocal(character)
end

--- Atualiza um valor na pasta StatusLocal
local function AtualizarStatusLocal(nome: string, valor: any)
	StatusLocalManager.AtualizarStatusLocal(character, nome, valor)
end

--- Lê um valor da pasta StatusLocal
local function LerStatusLocal(nome: string): any
	return StatusLocalManager.LerStatusLocal(character, nome)
end

-- Registra funções no ClientBridge para acesso por outros scripts
ClientBridge.ObterStatusLocal = ObterStatusLocal
ClientBridge.AtualizarStatusLocal = AtualizarStatusLocal
ClientBridge.LerStatusLocal = LerStatusLocal

if debug then
	print("[StatusLocal] Pasta StatusLocal criada para", player.Name)
end
