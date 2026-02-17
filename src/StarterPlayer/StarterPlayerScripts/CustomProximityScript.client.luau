-- StarterPlayerScripts > CustomProximityScript.luau

local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- ========================================
-- Funcionalidade de Cor por Tipo (ex-módulo)
-- ========================================
local COLOR_MAP = {
	Ferramentas = Color3.fromRGB(149, 149, 149), -- Cinza
	Armas = Color3.fromRGB(149, 149, 149), -- Cinza
	ArmasEquipadas = Color3.fromRGB(149, 149, 149), -- Cinza
	Armaduras = Color3.fromRGB(149, 149, 149), -- Cinza
	Materiais = Color3.fromRGB(167, 116, 96), -- Marrom
	Comidas = Color3.fromRGB(186, 174, 104), -- Amarelo
	Bebidas = Color3.fromRGB(104, 186, 159), -- Azul Claro
	Pocoes = Color3.fromRGB(162, 104, 186), -- Roxo
	Ingredientes = Color3.fromRGB(111, 186, 104), -- Verde
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

-- ═══════════════════════════════════════════════════════════════════
-- BLOQUEIO DE INTERAÇÃO (COMBATE/FERRAMENTA)
-- Oculta e bloqueia todos os prompts enquanto modoAnimacao for de Combate ou Interação.
-- Controla cada BillboardGui.Enabled individualmente (ScreenGui.Enabled não
-- afeta BillboardGuis com Adornee de forma confiável).
-- ═══════════════════════════════════════════════════════════════════

local Modulo_Configuracoes =
	require(ReplicatedStorage:WaitForChild("Modulos"):WaitForChild("Combate"):WaitForChild("Modulo_Configuracoes"))

local interacaoBloqueada = false

-- Rastreia prompts atualmente visíveis (para desabilitar ao entrar em combate)
local promptsVisiveis: { [ProximityPrompt]: boolean } = {}

-- Prompts que desabilitamos via .Enabled = false (para reabilitar ao sair de combate)
local promptsDesabilitados: { [ProximityPrompt]: boolean } = {}

local function AtualizarBloqueioProximity(modoAnimacao: string)
	local novoBloqueio = Modulo_Configuracoes.BloqueiaInteracao(modoAnimacao)
	if novoBloqueio == interacaoBloqueada then
		return
	end

	interacaoBloqueada = novoBloqueio

	if interacaoBloqueada then
		-- Entrou em combate: desabilita todos os prompts que já estão visíveis
		for prompt in pairs(promptsVisiveis) do
			if prompt and prompt.Parent then
				prompt.Enabled = false
				promptsDesabilitados[prompt] = true
			end
		end
		promptsVisiveis = {}
	else
		-- Saiu de combate: reabilita todos os prompts que desabilitamos
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

	-- Se em combate/ferramenta, desabilita o prompt e não cria UI
	if interacaoBloqueada then
		promptInstance.Enabled = false
		promptsDesabilitados[promptInstance] = true
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

		-- Preferir o StringValue `Dados/Tipo` do Tool se existir (fallback para atributo do prompt)
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

		objectText.TextColor3 = GetColorByType(tipoFinal)
	end

	-- Configura o BillboardGui para usar Adornee e ficar no PlayerGui
	CustomProximity.Active = true -- IMPORTANTE: permite detectar input
	CustomProximity.Adornee = promptInstance.Parent
	CustomProximity.Parent = screenGui

	-- Registra como visível (para desabilitar se entrar em combate)
	promptsVisiveis[promptInstance] = true

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
		-- Remove do rastreamento
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
