local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ToolBuilder = require(ReplicatedStorage:WaitForChild("Equipamentos"):WaitForChild("ConstrutorFerramentas"))

local tool = script:FindFirstAncestorOfClass("Tool")
if not tool then
	warn("[ColetaTool] Script sem Tool ancestral")
	return
end

local handle = tool:FindFirstChild("Handle")
if not handle then
	warn("[ColetaTool] Tool sem Handle: " .. tool.Name)
	return
end

local prompt = handle:FindFirstChild("ColetarTool")
if not prompt or not prompt:IsA("ProximityPrompt") then
	warn("[ColetaTool] ProximityPrompt ColetarTool nao encontrado em: " .. tool.Name)
	return
end

local pegando = false

prompt.Triggered:Connect(function(player)
	if pegando then
		return
	end

	pegando = true
	prompt.Enabled = false

	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
	if not backpack then
		pegando = false
		prompt.Enabled = true
		return
	end

	local dados = ToolBuilder.ExtrairDadosDoMundo(tool)
	if not dados then
		pegando = false
		prompt.Enabled = true
		return
	end

	local toolCriada = ToolBuilder.CriarTool(dados, backpack)
	if toolCriada then
		tool:Destroy()
	else
		pegando = false
		prompt.Enabled = true
	end
end)