--[[
    Script: ControladorProximidade.client.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/Interacao/Proximidade
    Responsabilidade: Controla deteccao, destaque e ativacao local de interacoes por proximidade.
    Uso: LocalScript; roda automaticamente para o jogador local em src/StarterPlayer/StarterPlayerScripts/Interacao/Proximidade.
    Nao faz: Nao valida autoridade do servidor, nao salva dados persistentes e nao substitui regras server-side.
    Funcoes principais: AtualizarBloqueioProximity, ConectarStatusLocalProximity
]]
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ProximityColors = require(ReplicatedStorage:WaitForChild("Interacao"):WaitForChild("Proximidade"):WaitForChild("Configuracoes"):WaitForChild("CoresProximidade"))

local player = Players.LocalPlayer
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CustomPromptsGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local Modulo_Configuracoes =
	require(ReplicatedStorage:WaitForChild("Combate"):WaitForChild("Configuracoes"):WaitForChild("ConfigCombate"))

local interacaoBloqueada = false

local promptsVisiveis: { [ProximityPrompt]: boolean } = {}

local promptsDesabilitados: { [ProximityPrompt]: boolean } = {}

local function AtualizarBloqueioProximity(modoAnimacao: string)
	local novoBloqueio = Modulo_Configuracoes.BloqueiaInteracao(modoAnimacao)
	if novoBloqueio == interacaoBloqueada then
		return
	end

	interacaoBloqueada = novoBloqueio

	if interacaoBloqueada then

		for prompt in pairs(promptsVisiveis) do
			if prompt and prompt.Parent then
				prompt.Enabled = false
				promptsDesabilitados[prompt] = true
			end
		end
		promptsVisiveis = {}
	else

		for prompt in pairs(promptsDesabilitados) do
			if prompt and prompt.Parent then
				prompt.Enabled = true
			end
		end
		promptsDesabilitados = {}
	end
end

local function ConectarStatusLocalProximity(character: Model)
	local statusLocal = character:WaitForChild("StatusLocal", 10)
	if not statusLocal then
		return
	end
	local modoVal = statusLocal:WaitForChild("modoAnimacao", 10)
	if not modoVal then
		return
	end

	modoVal.Changed:Connect(function(novoModo)
		AtualizarBloqueioProximity(novoModo)
	end)

	AtualizarBloqueioProximity(modoVal.Value)
end

if player.Character then
	task.spawn(ConectarStatusLocalProximity, player.Character)
end

player.CharacterAdded:Connect(function(character)
	interacaoBloqueada = false
	promptsVisiveis = {}
	promptsDesabilitados = {}
	task.spawn(ConectarStatusLocalProximity, character)
end)

ProximityPromptService.PromptShown:Connect(function(promptInstance: ProximityPrompt)
	if promptInstance.Style == Enum.ProximityPromptStyle.Default then
		return
	end

	if interacaoBloqueada then
		promptInstance.Enabled = false
		promptsDesabilitados[promptInstance] = true
		return
	end

	local CustomProximity = ReplicatedStorage:WaitForChild("Interacao"):WaitForChild("Proximidade"):WaitForChild("Modelos"):WaitForChild("ModeloProximidade"):Clone()

	local KeyText = CustomProximity:FindFirstChild("KeyText", true)
	local KeyLabel = KeyText and KeyText:FindFirstChild("KeyLabel")

	if KeyLabel then
		KeyLabel.Text = promptInstance.KeyboardKeyCode.Name
	end

	local actionText = CustomProximity:FindFirstChild("ActionText", true)
	if actionText then
		actionText.Text = promptInstance.ActionText
	end

	local objectText = CustomProximity:FindFirstChild("ObjectText", true)
	if objectText then
		objectText.Text = promptInstance.ObjectText

		local tipoFinal = nil
		local adornee = promptInstance.Parent
		if adornee then
			local tool = adornee:FindFirstAncestorOfClass("Tool")
			if not tool and adornee:IsA("Tool") then
				tool = adornee
			end
			if tool then
				local dadosFolder = tool:FindFirstChild("Dados")
				if dadosFolder then
					local tipoValue = dadosFolder:FindFirstChild("Tipo")
					if tipoValue and tipoValue:IsA("StringValue") then
						tipoFinal = tipoValue.Value
					end
				end
			end
		end

		if not tipoFinal then
			tipoFinal = promptInstance:GetAttribute("Tipo")
		end

		objectText.TextColor3 = ProximityColors.GetColorByType(tipoFinal)
	end

	CustomProximity.Active = true
	CustomProximity.Adornee = promptInstance.Parent
	CustomProximity.Parent = screenGui

	promptsVisiveis[promptInstance] = true

	local clickButton = CustomProximity:FindFirstChild("Frame"):FindFirstChild("ClickDetector", true)

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

	local Progress = KeyText and KeyText:FindFirstChild("Progress")
	local ProgressHoldBg = KeyText and KeyText:FindFirstChild("ProgressHoldBg")
	local currentTween
	local currentBgTween

	local holdBeganConnection = promptInstance.PromptButtonHoldBegan:Connect(function()
		if Progress then
			if currentTween then
				currentTween:Cancel()
			end

			local currentScale = Progress.Size.X.Scale
			local remaining = promptInstance.HoldDuration * (1 - currentScale / 0.94)
			currentTween = TweenService:Create(Progress, TweenInfo.new(remaining), {
				Size = UDim2.fromScale(0.94, 0.94),
			})
			currentTween:Play()
		end

		if ProgressHoldBg then
			if currentBgTween then
				currentBgTween:Cancel()
			end
			currentBgTween = TweenService:Create(ProgressHoldBg, TweenInfo.new(0.3), {
				BackgroundTransparency = 0.75,
			})
			currentBgTween:Play()
		end
	end)

	local holdEndedConnection = promptInstance.PromptButtonHoldEnded:Connect(function()
		if currentTween then
			currentTween:Cancel()
		end
		if Progress then

			local shrinkDuration = 0.25
			currentTween = TweenService:Create(Progress, TweenInfo.new(shrinkDuration), {
				Size = UDim2.fromScale(0, 0),
			})
			currentTween:Play()
		end

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

		promptsVisiveis[promptInstance] = nil

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
