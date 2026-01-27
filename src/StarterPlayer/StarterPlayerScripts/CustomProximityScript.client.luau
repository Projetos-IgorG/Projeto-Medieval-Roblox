-- StarterPlayerScripts > CustomProximityScript.luau

local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

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

-- Criar ScreenGui para hospedar prompts (permite TextButton funcionar)
local player = Players.LocalPlayer
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CustomPromptsGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

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

	-- Configura o BillboardGui para usar Adornee e ficar no PlayerGui
	CustomProximity.Active = true -- IMPORTANTE: permite detectar input
	CustomProximity.Adornee = promptInstance.Parent
	CustomProximity.Parent = screenGui

	-- ========================================
	-- TextButton para detectar clique/touch (usa o existente no template)
	-- ========================================
	local clickButton = CustomProximity:FindFirstChild("ClickDetector", true)

	if clickButton then
		local buttonDown = false

		clickButton.InputBegan:Connect(function(input)
			if
				(
					input.UserInputType == Enum.UserInputType.Touch
					or input.UserInputType == Enum.UserInputType.MouseButton1
				) and input.UserInputState ~= Enum.UserInputState.Change
			then
				promptInstance:InputHoldBegin()
				buttonDown = true
			end
		end)

		clickButton.InputEnded:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1
			then
				if buttonDown then
					buttonDown = false
					promptInstance:InputHoldEnd()
				end
			end
		end)
	end
	-- ========================================

	local Progress = KeyText and KeyText:FindFirstChild("Progress")
	local ProgressHoldBg = KeyText and KeyText:FindFirstChild("ProgressHoldBg")
	local currentTween
	local currentBgTween

	local holdBeganConnection = promptInstance.PromptButtonHoldBegan:Connect(function()
		if Progress then
			Progress.Size = UDim2.new(0, 0, 0, 0)
			currentTween = TweenService:Create(Progress, TweenInfo.new(promptInstance.HoldDuration), {
				Size = UDim2.new(0.94, 0, 0.94, 0),
			})
			currentTween:Play()
		end
		-- Mostrar o background de hold com animação suave
		if ProgressHoldBg then
			if currentBgTween then
				currentBgTween:Cancel()
			end
			currentBgTween = TweenService:Create(ProgressHoldBg, TweenInfo.new(0.2), {
				BackgroundTransparency = 0.8,
			})
			currentBgTween:Play()
		end
	end)

	local holdEndedConnection = promptInstance.PromptButtonHoldEnded:Connect(function()
		if currentTween then
			currentTween:Cancel()
		end
		if Progress then
			Progress.Size = UDim2.new(0, 0, 0, 0)
		end
		-- Esconder o background de hold com animação suave
		if ProgressHoldBg then
			if currentBgTween then
				currentBgTween:Cancel()
			end
			currentBgTween = TweenService:Create(ProgressHoldBg, TweenInfo.new(0.15), {
				BackgroundTransparency = 1,
			})
			currentBgTween:Play()
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
