--!strict

--[[
    Script: ServicoColetaItem.luau
    Caminho: src/ServerScriptService/Inventario/Servidor
    Responsabilidade: Escuta e processa a coleta de itens dropados no mundo de forma centralizada e otimizada.
    Uso: Script de servidor (iniciado automaticamente pelo Rojo/Roblox).
]]
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConstrutorTools = require(ReplicatedStorage:WaitForChild("SistemaItens"):WaitForChild("ConstrutorTools"))

local function OnPromptTriggered(prompt: ProximityPrompt, player: Player)
	if prompt.Name ~= "ColetarTool" then
		return
	end

	local handle = prompt.Parent
	if not handle or not handle:IsA("BasePart") then
		return
	end

	local tool = handle.Parent
	if not tool or not tool:IsA("Tool") then
		-- Pode ser que o prompt esteja dentro de um Model (caso o dropado seja Model)
		tool = handle:FindFirstAncestorOfClass("Tool")
	end

	if not tool then
		return
	end

	-- Debounce no prompt
	prompt.Enabled = false

	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
	if not backpack then
		prompt.Enabled = true
		return
	end

	local id = tool:GetAttribute("Id")
	local dados = ConstrutorTools.ExtrairDadosDoMundo(tool)
	if not id or not dados then
		prompt.Enabled = true
		return
	end

	-- Tenta empilhar ou criar o item na Backpack do jogador
	local sucesso = ConstrutorTools.EmpilharNoContainer(backpack, id, dados)
	if sucesso then
		tool:Destroy()
	else
		prompt.Enabled = true
	end
end

ProximityPromptService.PromptTriggered:Connect(OnPromptTriggered)
