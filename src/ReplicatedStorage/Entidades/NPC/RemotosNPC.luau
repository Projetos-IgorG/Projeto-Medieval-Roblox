--!strict

--[[
    Script: RemotosNPC.luau
    Caminho: src/ReplicatedStorage/Entidades/NPC
    Responsabilidade: Garante a existencia de RemoteEvents do sistema de NPC e expoe um helper de obtencao.
    Uso: ModuleScript; require em servidor (cria) e cliente (espera).
    Nao faz: Nao processa eventos; apenas devolve as instancias.
    Funcoes principais: ObterPasta, ObterRemote
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RemotosNPC = {}

local function obterOuCriarPasta(pai: Instance, nome: string): Folder
	local existente = pai:FindFirstChild(nome)
	if existente and existente:IsA("Folder") then
		return existente
	end
	if RunService:IsServer() then
		local nova = Instance.new("Folder")
		nova.Name = nome
		nova.Parent = pai
		return nova
	end
	return pai:WaitForChild(nome) :: Folder
end

function RemotosNPC.ObterPasta(): Folder
	local raiz = obterOuCriarPasta(ReplicatedStorage, "NPC")
	return obterOuCriarPasta(raiz, "Remotos")
end

function RemotosNPC.ObterRemote(nome: string, classe: string?): RemoteEvent | RemoteFunction
	local pasta = RemotosNPC.ObterPasta()
	local existente = pasta:FindFirstChild(nome)
	if existente and (existente:IsA("RemoteEvent") or existente:IsA("RemoteFunction")) then
		return existente :: any
	end
	if RunService:IsServer() then
		local novo = Instance.new(classe or "RemoteEvent")
		novo.Name = nome
		novo.Parent = pasta
		return novo :: any
	end
	return pasta:WaitForChild(nome) :: any
end

-- Pasta no Workspace onde os Models de NPC ativos vivem.
function RemotosNPC.ObterPastaMundo(): Folder
	local Workspace = game:GetService("Workspace")
	return obterOuCriarPasta(Workspace, "NPCs")
end

return RemotosNPC
