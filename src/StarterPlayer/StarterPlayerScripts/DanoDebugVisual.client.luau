--!strict
--[[
	DAMAGE DISPLAY LOCAL (DanoDebugVisual)
	Caminho: src/StarterPlayer/StarterPlayerScripts/DanoDebugVisual.client.luau
	Responsabilidade: Cria textos visuais (damage popups) acima de quem foi acertado, defendido ou aparado.
	Uso: LocalScript; auto-inicia ao escutar o RemoteEvent DanoDebugVisual.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local rng = Random.new()

local Config = {
	MaxDistance = 120,
	DefaultDuration = 1.0,

	DamageColor = Color3.fromRGB(255, 75, 75),       -- Vermelho vibrante para acerto
	BypassedColor = Color3.fromRGB(220, 220, 220),    -- Cinza para bypass (hit pelas costas/lado)
	BlockColor = Color3.fromRGB(50, 150, 255),       -- Azul para bloqueio normal
	ParryColor = Color3.fromRGB(255, 200, 50),       -- Amarelo/Dourado para parry
	BlockBrokenColor = Color3.fromRGB(180, 80, 255),  -- Roxo para quebra de guarda
	ChargedColor = Color3.fromRGB(255, 130, 0),      -- Laranja para ataque segurado
	WhiteColor = Color3.fromRGB(255, 255, 255),        -- Branco para texto geral
	TagColor = Color3.fromRGB(240, 240, 240),

	MainStrokeTransparency = 0.15,
	TagStrokeTransparency = 0.25,
}

local function obterOuCriarContainer(): ScreenGui
	local existente = PlayerGui:FindFirstChild("DamageDisplayContainer")
	if existente and existente:IsA("ScreenGui") then
		return existente :: ScreenGui
	end
	-- Remove versao antiga (Folder) se existir
	if existente then
		existente:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "DamageDisplayContainer"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 100
	gui.Parent = PlayerGui
	return gui
end

local container: Instance = obterOuCriarContainer()

local function roundNumber(value: number): string
	if math.abs(value % 1) < 0.01 then
		return tostring(math.round(value))
	end
	return string.format("%.1f", value)
end

local function getAdorneePart(character: Instance?): BasePart?
	if not character or not character:IsA("Model") then
		return nil
	end
	return character:FindFirstChild("Head") :: BasePart?
		or character:FindFirstChild("HumanoidRootPart") :: BasePart?
		or character:FindFirstChildWhichIsA("BasePart") :: BasePart?
end

local function makeBillboard(adornee: BasePart): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "DamageIndicator"
	gui.Adornee = adornee
	gui.AlwaysOnTop = true
	gui.MaxDistance = Config.MaxDistance
	gui.Size = UDim2.fromOffset(240, 120)
	-- Offset aleatório sutil no eixo X e Y para evitar sobreposição perfeita de múltiplos hits rápidos
	gui.StudsOffset = Vector3.new(rng:NextNumber(-0.8, 0.8), 2.5 + rng:NextNumber(0, 0.8), 0)
	gui.Parent = container
	return gui
end

local function makeText(parent: Instance, text: string, color: Color3, font: Enum.Font, size: UDim2, position: UDim2, strokeTransparency: number): (TextLabel, UIScale)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = position
	label.Size = size
	label.Text = text
	label.TextColor3 = color
	label.TextTransparency = 0
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = strokeTransparency
	label.TextScaled = true
	label.RichText = true
	label.Font = font
	label.ZIndex = 10
	label.Parent = parent

	local scale = Instance.new("UIScale")
	scale.Scale = 0.5
	scale.Parent = label

	return label, scale
end

local function animateText(label: TextLabel, scaleObject: UIScale, endPosition: UDim2, duration: number, growScale: number)
	local popTween = TweenService:Create(
		scaleObject,
		TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = growScale }
	)

	local moveFadeTween = TweenService:Create(
		label,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Position = endPosition,
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}
	)

	popTween:Play()
	moveFadeTween:Play()
end

local function addTag(parent: Instance, text: string, color: Color3, index: number, total: number, duration: number)
	local baseX = 0.5
	local spread = 0.16
	local offsetX = 0

	if total > 1 then
		offsetX = ((index - 1) / math.max(total - 1, 1) - 0.5) * (spread * 2)
	end

	offsetX += rng:NextNumber(-0.04, 0.04)

	local startPos = UDim2.fromScale(baseX + offsetX, 0.65 + rng:NextNumber(-0.04, 0.04))
	local endPos = UDim2.fromScale(baseX + offsetX, 0.20 + rng:NextNumber(-0.04, 0.04))

	local label, scale = makeText(
		parent,
		text,
		color,
		Enum.Font.GothamBold,
		UDim2.fromOffset(100, 22),
		startPos,
		Config.TagStrokeTransparency
	)

	animateText(label, scale, endPos, duration, 1.0)
end

local function Show(targetCharacter: Model, damage: number, info: any)
	-- Garante que o container sempre existe (sobrevive morte/respawn)
	if not container or not container.Parent then
		container = obterOuCriarContainer()
	end

	local adornee = getAdorneePart(targetCharacter)
	if not adornee then
		return
	end

	local duration = Config.DefaultDuration
	local gui = makeBillboard(adornee)

	local tipo = info.tipo
	local multiplicador = info.multiplicador or 1.0
	local bypassed = info.bypassed == true
	
	local mainColor = Config.DamageColor
	local mainText = ""
	local tags = {}

	if tipo == "Parry" then
		mainColor = Config.ParryColor
		mainText = "PARRY"
	elseif tipo == "BlockBroken" then
		mainColor = Config.BlockBrokenColor
		mainText = "QUEBROU DEFESA"
	elseif tipo == "Block" then
		mainColor = Config.BlockColor
		mainText = "DEFENDEU"
		-- Mostra o dano mitigado em uma tag
		if damage > 0 then
			table.insert(tags, {
				text = "-" .. roundNumber(damage),
				color = Config.DamageColor,
			})
		end
	else -- "Hit"
		mainText = "-" .. roundNumber(damage)
		if bypassed then
			mainColor = Config.DamageColor
			table.insert(tags, {
				text = "COSTAS",
				color = Config.BypassedColor,
			})
		else
			mainColor = Config.DamageColor
		end

		if typeof(multiplicador) == "number" and multiplicador > 1.0 then
			mainText = mainText .. string.format(" (x%.2f)", multiplicador)
		end
	end

	local mainStart = UDim2.fromScale(0.5 + rng:NextNumber(-0.04, 0.04), 0.55)
	local mainEnd = UDim2.fromScale(0.5 + rng:NextNumber(-0.04, 0.04), 0.10)

	local mainLabel, mainScale = makeText(
		gui,
		mainText,
		mainColor,
		Enum.Font.GothamBlack,
		UDim2.fromOffset(180, 42),
		mainStart,
		Config.MainStrokeTransparency
	)

	animateText(mainLabel, mainScale, mainEnd, duration, 1.15)

	for i, tag in ipairs(tags) do
		addTag(gui, tag.text, tag.color, i, #tags, duration)
	end

	Debris:AddItem(gui, duration + 0.1)
end

-- =============================================================================
-- ESCUTA EVENTO SERVIDOR
-- =============================================================================
local Remotos = ReplicatedStorage:WaitForChild("Remotos", 5)
if Remotos then
	local DanoDebugVisualRemote = Remotos:WaitForChild("DanoDebugVisual", 5) :: RemoteEvent?
	if DanoDebugVisualRemote then
		DanoDebugVisualRemote.OnClientEvent:Connect(function(targetCharacter: Model, damage: number, info: any)
			if typeof(targetCharacter) == "Instance" and targetCharacter:IsA("Model") then
				Show(targetCharacter, damage, info)
			end
		end)
	end
end
