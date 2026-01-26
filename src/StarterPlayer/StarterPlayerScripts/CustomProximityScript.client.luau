-- StarterPlayerScripts > CustomProximityScript.luau

local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ========================================
-- Funcionalidade de Cor por Tipo (ex-módulo)
-- ========================================
local COLOR_MAP = {
	Ferramenta = Color3.fromRGB(149, 149, 149), -- Cinza
	Recurso = Color3.fromRGB(186, 134, 104), -- Marrom
	Interagir = Color3.fromRGB(218, 218, 218), -- Cinza claro
	NPC = Color3.fromRGB(218, 218, 218), -- Cinza claro
}

local DEFAULT_COLOR = Color3.fromRGB(218, 218, 218)

local function GetColorByType(tipo)
	if typeof(tipo) ~= "string" then
		return DEFAULT_COLOR
	end
	return COLOR_MAP[tipo] or DEFAULT_COLOR
end
-- ========================================

ProximityPromptService.PromptShown:Connect(function(promptInstance: ProximityPrompt)
	if promptInstance.Style == Enum.ProximityPromptStyle.Default then
		return
	end

	local CustomProximity = ReplicatedStorage:WaitForChild("CustomProximity"):Clone()

	-- Acessa o KeyText (Frame circular) e o KeyLabel (texto da tecla)
	local KeyText = CustomProximity:FindFirstChild("KeyText", true)
	local KeyLabel = KeyText and KeyText:FindFirstChild("KeyLabel")

	if KeyLabel then
		KeyLabel.Text = promptInstance.KeyboardKeyCode.Name
	end

	-- Atualiza os textos de ação e objeto
	local actionText = CustomProximity:FindFirstChild("ActionText", true)
	if actionText then
		actionText.Text = promptInstance.ActionText
	end

	local objectText = CustomProximity:FindFirstChild("ObjectText", true)
	if objectText then
		objectText.Text = promptInstance.ObjectText
		local tipo = promptInstance:GetAttribute("Tipo")
		objectText.TextColor3 = GetColorByType(tipo)
	end

	CustomProximity.Parent = promptInstance.Parent

	local Progress = KeyText and KeyText:FindFirstChild("Progress")
	local currentTween

	local holdBeganConnection = promptInstance.PromptButtonHoldBegan:Connect(function()
		if Progress then
			Progress.Size = UDim2.new(0, 0, 0, 0)
			currentTween = TweenService:Create(Progress, TweenInfo.new(promptInstance.HoldDuration), {
				Size = UDim2.new(1, 0, 1, 0),
			})
			currentTween:Play()
		end
	end)

	local holdEndedConnection = promptInstance.PromptButtonHoldEnded:Connect(function()
		if currentTween then
			currentTween:Cancel()
		end
		if Progress then
			Progress.Size = UDim2.new(0, 0, 0, 0)
		end
	end)

	promptInstance.PromptHidden:Once(function()
		if CustomProximity then
			CustomProximity:Destroy()
		end
		if holdBeganConnection then
			holdBeganConnection:Disconnect()
		end
		if holdEndedConnection then
			holdEndedConnection:Disconnect()
		end
	end)
end)
