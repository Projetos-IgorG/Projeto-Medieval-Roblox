--[[
    Script: InicializarStatusLocal.client.luau
    Caminho: src/StarterPlayer/StarterCharacterScripts/Jogador/Estado
    Responsabilidade: Inicializa status locais do personagem assim que o Character aparece.
    Uso: LocalScript; roda automaticamente para o jogador local em src/StarterPlayer/StarterCharacterScripts/Jogador/Estado.
    Nao faz: Nao valida autoridade do servidor, nao salva dados persistentes e nao substitui regras server-side.
    Funcoes principais: ObterStatusLocal, AtualizarStatusLocal, LerStatusLocal
]]
local debug = false

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientBridge =
	require(ReplicatedStorage:WaitForChild("Jogador"):WaitForChild("ComunicacaoCliente"):WaitForChild("PonteCliente"))

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local StatusLocalManager = require(ReplicatedStorage:WaitForChild("Jogador"):WaitForChild("Estado"):WaitForChild("StatusLocalPersonagem"))

local _statusLocal = StatusLocalManager.CriarStatusLocal(character)

player.CharacterAdded:Connect(function(newCharacter)
	character = newCharacter
	_statusLocal = StatusLocalManager.CriarStatusLocal(newCharacter)
end)

local function ObterStatusLocal(): Folder?
	return StatusLocalManager.ObterStatusLocal(character)
end

local function AtualizarStatusLocal(nome: string, valor: any)
	StatusLocalManager.AtualizarStatusLocal(character, nome, valor)
end

local function LerStatusLocal(nome: string): any
	return StatusLocalManager.LerStatusLocal(character, nome)
end

ClientBridge.ObterStatusLocal = ObterStatusLocal
ClientBridge.AtualizarStatusLocal = AtualizarStatusLocal
ClientBridge.LerStatusLocal = LerStatusLocal

if debug then
	print("[StatusLocal] Pasta StatusLocal criada para", player.Name)
end
