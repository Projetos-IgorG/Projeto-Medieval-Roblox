-- ServerScriptService/BuildCustomProximity.server.luau
-- Script que reconstrói o CustomProximity EXATAMENTE como o original

local function buildCustomProximity(parent)
	-- ============================================
	-- CustomProximity (BillboardGui)
	-- Pai: ReplicatedStorage ou Part
	-- ============================================
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CustomProximity"
	billboard.Active = false
	billboard.AlwaysOnTop = true
	billboard.Archivable = true
	billboard.AutoLocalize = true
	billboard.Brightness = 1
	billboard.ClipsDescendants = false
	billboard.DistanceLowerLimit = 0
	billboard.DistanceStep = 0
	billboard.DistanceUpperLimit = -1
	billboard.Enabled = true
	billboard.ExtentsOffset = Vector3.new(0, 0, 0)
	billboard.ExtentsOffsetWorldSpace = Vector3.new(0, 0, 0)
	billboard.LightInfluence = 0.5
	billboard.MaxDistance = 12
	billboard.ResetOnSpawn = true
	billboard.SelectionBehaviorDown = Enum.SelectionBehavior.Escape
	billboard.SelectionBehaviorLeft = Enum.SelectionBehavior.Escape
	billboard.SelectionBehaviorRight = Enum.SelectionBehavior.Escape
	billboard.SelectionBehaviorUp = Enum.SelectionBehavior.Escape
	billboard.SelectionGroup = false
	billboard.Size = UDim2.new(7, 0, 1.7999999523162842, 0)
	billboard.SizeOffset = Vector2.new(0, 0)
	billboard.StudsOffset = Vector3.new(0, 1.5, 0)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 0, 0)
	billboard.ZIndexBehavior = Enum.ZIndexBehavior.Global
	billboard.Parent = parent

	-- ============================================
	-- UIPadding (filho de CustomProximity)
	-- ============================================
	local uiPadding = Instance.new("UIPadding")
	uiPadding.Name = "UIPadding"
	uiPadding.Archivable = true
	uiPadding.PaddingBottom = UDim.new(0, 0)
	uiPadding.PaddingLeft = UDim.new(0.4000000059604645, 0)
	uiPadding.PaddingRight = UDim.new(0, 0)
	uiPadding.PaddingTop = UDim.new(0, 0)
	uiPadding.Parent = billboard

	-- ============================================
	-- Container (Frame) - filho de CustomProximity
	-- ============================================
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Active = false
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.Archivable = true
	container.AutoLocalize = true
	container.AutomaticSize = Enum.AutomaticSize.None
	container.BackgroundColor3 = Color3.fromRGB(163, 162, 165)
	container.BackgroundTransparency = 1
	container.BorderColor3 = Color3.fromRGB(27, 42, 53)
	container.BorderMode = Enum.BorderMode.Outline
	container.BorderSizePixel = 1
	container.ClipsDescendants = false
	container.Draggable = false
	container.Interactable = true
	container.LayoutOrder = 0
	container.Position = UDim2.new(0.5, 0, 1, 0)
	container.Rotation = 0
	container.Selectable = false
	container.SelectionBehaviorDown = Enum.SelectionBehavior.Escape
	container.SelectionBehaviorLeft = Enum.SelectionBehavior.Escape
	container.SelectionBehaviorRight = Enum.SelectionBehavior.Escape
	container.SelectionBehaviorUp = Enum.SelectionBehavior.Escape
	container.SelectionGroup = false
	container.SelectionOrder = 0
	container.Size = UDim2.new(0.800000011920929, 0, 1, 0)
	container.SizeConstraint = Enum.SizeConstraint.RelativeXY
	container.Style = Enum.FrameStyle.Custom
	container.Visible = true
	container.ZIndex = 1
	container.Parent = billboard

	-- ============================================
	-- KeyText (Frame) - filho de Container
	-- ============================================
	local keyText = Instance.new("Frame")
	keyText.Name = "KeyText"
	keyText.Active = false
	keyText.AnchorPoint = Vector2.new(0, 0.5)
	keyText.Archivable = true
	keyText.AutoLocalize = true
	keyText.AutomaticSize = Enum.AutomaticSize.None
	keyText.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	keyText.BackgroundTransparency = 0.3499999940395355
	keyText.BorderColor3 = Color3.fromRGB(27, 42, 53)
	keyText.BorderMode = Enum.BorderMode.Outline
	keyText.BorderSizePixel = 0
	keyText.ClipsDescendants = false
	keyText.Draggable = false
	keyText.Interactable = true
	keyText.LayoutOrder = 0
	keyText.Position = UDim2.new(0, 5, 0.30000001192092896, 0)
	keyText.Rotation = 0
	keyText.Selectable = false
	keyText.SelectionBehaviorDown = Enum.SelectionBehavior.Escape
	keyText.SelectionBehaviorLeft = Enum.SelectionBehavior.Escape
	keyText.SelectionBehaviorRight = Enum.SelectionBehavior.Escape
	keyText.SelectionBehaviorUp = Enum.SelectionBehavior.Escape
	keyText.SelectionGroup = false
	keyText.SelectionOrder = 0
	keyText.Size = UDim2.new(0, 40, 0, 40)
	keyText.SizeConstraint = Enum.SizeConstraint.RelativeXY
	keyText.Style = Enum.FrameStyle.Custom
	keyText.Visible = true
	keyText.ZIndex = 1
	keyText.Parent = container

	-- ============================================
	-- UICorner (filho de KeyText)
	-- ============================================
	local keyTextCorner = Instance.new("UICorner")
	keyTextCorner.Name = "UICorner"
	keyTextCorner.Archivable = true
	keyTextCorner.CornerRadius = UDim.new(1, 0)
	keyTextCorner.Parent = keyText

	-- ============================================
	-- UIStroke [1] Outer/Preto (filho de KeyText)
	-- ============================================
	local keyTextStroke1 = Instance.new("UIStroke")
	keyTextStroke1.Name = "UIStroke"
	keyTextStroke1.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	keyTextStroke1.Archivable = true
	keyTextStroke1.BorderOffset = UDim.new(0, 0)
	keyTextStroke1.BorderStrokePosition = Enum.BorderStrokePosition.Outer
	keyTextStroke1.Color = Color3.fromRGB(0, 0, 0)
	keyTextStroke1.Enabled = true
	keyTextStroke1.LineJoinMode = Enum.LineJoinMode.Round
	keyTextStroke1.StrokeSizingMode = Enum.StrokeSizingMode.FixedSize
	keyTextStroke1.Thickness = 3
	keyTextStroke1.Transparency = 0.3499999940395355
	keyTextStroke1.ZIndex = 1
	keyTextStroke1.Parent = keyText

	-- ============================================
	-- UIStroke [2] Inner/Branco (filho de KeyText)
	-- ============================================
	local keyTextStroke2 = Instance.new("UIStroke")
	keyTextStroke2.Name = "UIStroke"
	keyTextStroke2.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	keyTextStroke2.Archivable = true
	keyTextStroke2.BorderOffset = UDim.new(0.009999999776482582, 0)
	keyTextStroke2.BorderStrokePosition = Enum.BorderStrokePosition.Inner
	keyTextStroke2.Color = Color3.fromRGB(255, 255, 255)
	keyTextStroke2.Enabled = true
	keyTextStroke2.LineJoinMode = Enum.LineJoinMode.Round
	keyTextStroke2.StrokeSizingMode = Enum.StrokeSizingMode.FixedSize
	keyTextStroke2.Thickness = 2
	keyTextStroke2.Transparency = 0.3499999940395355
	keyTextStroke2.ZIndex = 2
	keyTextStroke2.Parent = keyText

	-- ============================================
	-- Progress (Frame) - filho de KeyText
	-- ============================================
	local progress = Instance.new("Frame")
	progress.Name = "Progress"
	progress.Active = false
	progress.AnchorPoint = Vector2.new(0.5, 0.5)
	progress.Archivable = true
	progress.AutoLocalize = true
	progress.AutomaticSize = Enum.AutomaticSize.None
	progress.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	progress.BackgroundTransparency = 0.20000000298023224
	progress.BorderColor3 = Color3.fromRGB(27, 42, 53)
	progress.BorderMode = Enum.BorderMode.Outline
	progress.BorderSizePixel = 0
	progress.ClipsDescendants = false
	progress.Draggable = false
	progress.Interactable = true
	progress.LayoutOrder = 0
	progress.Position = UDim2.new(0.5, 0, 0.5, 0)
	progress.Rotation = 0
	progress.Selectable = false
	progress.SelectionBehaviorDown = Enum.SelectionBehavior.Escape
	progress.SelectionBehaviorLeft = Enum.SelectionBehavior.Escape
	progress.SelectionBehaviorRight = Enum.SelectionBehavior.Escape
	progress.SelectionBehaviorUp = Enum.SelectionBehavior.Escape
	progress.SelectionGroup = false
	progress.SelectionOrder = 0
	progress.Size = UDim2.new(0, 0, 0, 0)
	progress.SizeConstraint = Enum.SizeConstraint.RelativeXY
	progress.Style = Enum.FrameStyle.Custom
	progress.Visible = true
	progress.ZIndex = 2
	progress.Parent = keyText

	-- ============================================
	-- UICorner (filho de Progress)
	-- ============================================
	local progressCorner = Instance.new("UICorner")
	progressCorner.Name = "UICorner"
	progressCorner.Archivable = true
	progressCorner.CornerRadius = UDim.new(1, 0)
	progressCorner.Parent = progress

	-- ============================================
	-- KeyLabel (TextLabel) - filho de KeyText
	-- ============================================
	local keyLabel = Instance.new("TextLabel")
	keyLabel.Name = "KeyLabel"
	keyLabel.Active = false
	keyLabel.AnchorPoint = Vector2.new(0, 0)
	keyLabel.Archivable = true
	keyLabel.AutoLocalize = true
	keyLabel.AutomaticSize = Enum.AutomaticSize.None
	keyLabel.BackgroundColor3 = Color3.fromRGB(163, 162, 165)
	keyLabel.BackgroundTransparency = 1
	keyLabel.BorderColor3 = Color3.fromRGB(27, 42, 53)
	keyLabel.BorderMode = Enum.BorderMode.Outline
	keyLabel.BorderSizePixel = 1
	keyLabel.ClipsDescendants = false
	keyLabel.Draggable = false
	keyLabel.FontFace = Font.fromName("Fondamento", Enum.FontWeight.Bold, Enum.FontStyle.Normal)
	keyLabel.Interactable = true
	keyLabel.LayoutOrder = 0
	keyLabel.LineHeight = 1
	keyLabel.MaxVisibleGraphemes = -1
	keyLabel.OpenTypeFeatures = ""
	keyLabel.Position = UDim2.new(0, 0, 0, 0)
	keyLabel.RichText = false
	keyLabel.Rotation = 0
	keyLabel.Selectable = false
	keyLabel.SelectionBehaviorDown = Enum.SelectionBehavior.Escape
	keyLabel.SelectionBehaviorLeft = Enum.SelectionBehavior.Escape
	keyLabel.SelectionBehaviorRight = Enum.SelectionBehavior.Escape
	keyLabel.SelectionBehaviorUp = Enum.SelectionBehavior.Escape
	keyLabel.SelectionGroup = false
	keyLabel.SelectionOrder = 0
	keyLabel.Size = UDim2.new(1, 0, 1, 0)
	keyLabel.SizeConstraint = Enum.SizeConstraint.RelativeXY
	keyLabel.Text = "E"
	keyLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	keyLabel.TextDirection = Enum.TextDirection.Auto
	keyLabel.TextScaled = false
	keyLabel.TextSize = 30
	keyLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	keyLabel.TextStrokeTransparency = 1
	keyLabel.TextTransparency = 0
	keyLabel.TextTruncate = Enum.TextTruncate.None
	keyLabel.TextWrapped = true
	keyLabel.TextXAlignment = Enum.TextXAlignment.Center
	keyLabel.TextYAlignment = Enum.TextYAlignment.Center
	keyLabel.Visible = true
	keyLabel.ZIndex = 3
	keyLabel.Parent = keyText

	-- ============================================
	-- UIStroke (filho de KeyLabel)
	-- ============================================
	local keyLabelStroke = Instance.new("UIStroke")
	keyLabelStroke.Name = "UIStroke"
	keyLabelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	keyLabelStroke.Archivable = true
	keyLabelStroke.BorderOffset = UDim.new(0, 0)
	keyLabelStroke.BorderStrokePosition = Enum.BorderStrokePosition.Outer
	keyLabelStroke.Color = Color3.fromRGB(0, 0, 0)
	keyLabelStroke.Enabled = true
	keyLabelStroke.LineJoinMode = Enum.LineJoinMode.Round
	keyLabelStroke.StrokeSizingMode = Enum.StrokeSizingMode.FixedSize
	keyLabelStroke.Thickness = 2
	keyLabelStroke.Transparency = 0.5
	keyLabelStroke.ZIndex = 1
	keyLabelStroke.Parent = keyLabel

	-- ============================================
	-- ProgressHoldBg (Frame) - filho de KeyText
	-- ============================================
	local progressHoldBg = Instance.new("Frame")
	progressHoldBg.Name = "ProgressHoldBg"
	progressHoldBg.Active = false
	progressHoldBg.AnchorPoint = Vector2.new(0.5, 0.5)
	progressHoldBg.Archivable = true
	progressHoldBg.AutoLocalize = true
	progressHoldBg.AutomaticSize = Enum.AutomaticSize.None
	progressHoldBg.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	progressHoldBg.BackgroundTransparency = 1
	progressHoldBg.BorderColor3 = Color3.fromRGB(27, 42, 53)
	progressHoldBg.BorderMode = Enum.BorderMode.Outline
	progressHoldBg.BorderSizePixel = 0
	progressHoldBg.ClipsDescendants = false
	progressHoldBg.Draggable = false
	progressHoldBg.Interactable = true
	progressHoldBg.LayoutOrder = 0
	progressHoldBg.Position = UDim2.new(0.5, 0, 0.5, 0)
	progressHoldBg.Rotation = 0
	progressHoldBg.Selectable = false
	progressHoldBg.SelectionBehaviorDown = Enum.SelectionBehavior.Escape
	progressHoldBg.SelectionBehaviorLeft = Enum.SelectionBehavior.Escape
	progressHoldBg.SelectionBehaviorRight = Enum.SelectionBehavior.Escape
	progressHoldBg.SelectionBehaviorUp = Enum.SelectionBehavior.Escape
	progressHoldBg.SelectionGroup = false
	progressHoldBg.SelectionOrder = 0
	progressHoldBg.Size = UDim2.new(0.9399999976158142, 0, 0.9399999976158142, 0)
	progressHoldBg.SizeConstraint = Enum.SizeConstraint.RelativeXY
	progressHoldBg.Style = Enum.FrameStyle.Custom
	progressHoldBg.Visible = true
	progressHoldBg.ZIndex = 2
	progressHoldBg.Parent = keyText

	-- ============================================
	-- UICorner (filho de ProgressHoldBg)
	-- ============================================
	local progressHoldBgCorner = Instance.new("UICorner")
	progressHoldBgCorner.Name = "UICorner"
	progressHoldBgCorner.Archivable = true
	progressHoldBgCorner.CornerRadius = UDim.new(1, 0)
	progressHoldBgCorner.Parent = progressHoldBg

	-- ============================================
	-- ActionText (TextLabel) - filho de Container
	-- ============================================
	local actionText = Instance.new("TextLabel")
	actionText.Name = "ActionText"
	actionText.Active = false
	actionText.AnchorPoint = Vector2.new(0, 0)
	actionText.Archivable = true
	actionText.AutoLocalize = true
	actionText.AutomaticSize = Enum.AutomaticSize.None
	actionText.BackgroundColor3 = Color3.fromRGB(163, 162, 165)
	actionText.BackgroundTransparency = 1
	actionText.BorderColor3 = Color3.fromRGB(27, 42, 53)
	actionText.BorderMode = Enum.BorderMode.Outline
	actionText.BorderSizePixel = 0
	actionText.ClipsDescendants = false
	actionText.Draggable = false
	actionText.FontFace = Font.fromName("Fondamento", Enum.FontWeight.Bold, Enum.FontStyle.Normal)
	actionText.Interactable = true
	actionText.LayoutOrder = 0
	actionText.LineHeight = 1
	actionText.MaxVisibleGraphemes = -1
	actionText.OpenTypeFeatures = ""
	actionText.Position = UDim2.new(0, 60, 0, 0)
	actionText.RichText = false
	actionText.Rotation = 0
	actionText.Selectable = false
	actionText.SelectionBehaviorDown = Enum.SelectionBehavior.Escape
	actionText.SelectionBehaviorLeft = Enum.SelectionBehavior.Escape
	actionText.SelectionBehaviorRight = Enum.SelectionBehavior.Escape
	actionText.SelectionBehaviorUp = Enum.SelectionBehavior.Escape
	actionText.SelectionGroup = false
	actionText.SelectionOrder = 0
	actionText.Size = UDim2.new(1, 0, 0.30000001192092896, 0)
	actionText.SizeConstraint = Enum.SizeConstraint.RelativeXY
	actionText.Text = "Talk"
	actionText.TextColor3 = Color3.fromRGB(255, 255, 255)
	actionText.TextDirection = Enum.TextDirection.Auto
	actionText.TextScaled = false
	actionText.TextSize = 25
	actionText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	actionText.TextStrokeTransparency = 1
	actionText.TextTransparency = 0
	actionText.TextTruncate = Enum.TextTruncate.None
	actionText.TextWrapped = false
	actionText.TextXAlignment = Enum.TextXAlignment.Left
	actionText.TextYAlignment = Enum.TextYAlignment.Bottom
	actionText.Visible = true
	actionText.ZIndex = 1
	actionText.Parent = container

	-- ============================================
	-- UIStroke (filho de ActionText)
	-- ============================================
	local actionTextStroke = Instance.new("UIStroke")
	actionTextStroke.Name = "UIStroke"
	actionTextStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	actionTextStroke.Archivable = true
	actionTextStroke.BorderOffset = UDim.new(0, 0)
	actionTextStroke.BorderStrokePosition = Enum.BorderStrokePosition.Outer
	actionTextStroke.Color = Color3.fromRGB(0, 0, 0)
	actionTextStroke.Enabled = true
	actionTextStroke.LineJoinMode = Enum.LineJoinMode.Round
	actionTextStroke.StrokeSizingMode = Enum.StrokeSizingMode.FixedSize
	actionTextStroke.Thickness = 1.5
	actionTextStroke.Transparency = 0.10000000149011612
	actionTextStroke.ZIndex = 1
	actionTextStroke.Parent = actionText

	-- ============================================
	-- ObjectText (TextLabel) - filho de Container
	-- ============================================
	local objectText = Instance.new("TextLabel")
	objectText.Name = "ObjectText"
	objectText.Active = false
	objectText.AnchorPoint = Vector2.new(0, 0)
	objectText.Archivable = true
	objectText.AutoLocalize = true
	objectText.AutomaticSize = Enum.AutomaticSize.None
	objectText.BackgroundColor3 = Color3.fromRGB(163, 162, 165)
	objectText.BackgroundTransparency = 1
	objectText.BorderColor3 = Color3.fromRGB(27, 42, 53)
	objectText.BorderMode = Enum.BorderMode.Outline
	objectText.BorderSizePixel = 1
	objectText.ClipsDescendants = false
	objectText.Draggable = false
	objectText.FontFace = Font.fromName("Fondamento", Enum.FontWeight.Bold, Enum.FontStyle.Normal)
	objectText.Interactable = true
	objectText.LayoutOrder = 0
	objectText.LineHeight = 1
	objectText.MaxVisibleGraphemes = -1
	objectText.OpenTypeFeatures = ""
	objectText.Position = UDim2.new(0, 60, 0.30000001192092896, 0)
	objectText.RichText = false
	objectText.Rotation = 0
	objectText.Selectable = false
	objectText.SelectionBehaviorDown = Enum.SelectionBehavior.Escape
	objectText.SelectionBehaviorLeft = Enum.SelectionBehavior.Escape
	objectText.SelectionBehaviorRight = Enum.SelectionBehavior.Escape
	objectText.SelectionBehaviorUp = Enum.SelectionBehavior.Escape
	objectText.SelectionGroup = false
	objectText.SelectionOrder = 0
	objectText.Size = UDim2.new(1, 0, 0.6000000238418579, 0)
	objectText.SizeConstraint = Enum.SizeConstraint.RelativeXY
	objectText.Text = "Lord Jalkior"
	objectText.TextColor3 = Color3.fromRGB(218, 218, 218)
	objectText.TextDirection = Enum.TextDirection.Auto
	objectText.TextScaled = false
	objectText.TextSize = 20
	objectText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	objectText.TextStrokeTransparency = 1
	objectText.TextTransparency = 0
	objectText.TextTruncate = Enum.TextTruncate.None
	objectText.TextWrapped = false
	objectText.TextXAlignment = Enum.TextXAlignment.Left
	objectText.TextYAlignment = Enum.TextYAlignment.Top
	objectText.Visible = true
	objectText.ZIndex = 1
	objectText.Parent = container

	-- ============================================
	-- UIStroke (filho de ObjectText)
	-- ============================================
	local objectTextStroke = Instance.new("UIStroke")
	objectTextStroke.Name = "UIStroke"
	objectTextStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	objectTextStroke.Archivable = true
	objectTextStroke.BorderOffset = UDim.new(0, 0)
	objectTextStroke.BorderStrokePosition = Enum.BorderStrokePosition.Outer
	objectTextStroke.Color = Color3.fromRGB(0, 0, 0)
	objectTextStroke.Enabled = true
	objectTextStroke.LineJoinMode = Enum.LineJoinMode.Round
	objectTextStroke.StrokeSizingMode = Enum.StrokeSizingMode.FixedSize
	objectTextStroke.Thickness = 1.5
	objectTextStroke.Transparency = 0.10000000149011612
	objectTextStroke.ZIndex = 1
	objectTextStroke.Parent = objectText

	-- ============================================
	-- ClickDetector (TextButton) - filho de CustomProximity (BillboardGui)
	-- IMPORTANTE: Está diretamente no BillboardGui, não no Container!
	-- ============================================
	local clickDetector = Instance.new("TextButton")
	clickDetector.Name = "ClickDetector"
	clickDetector.Active = true
	clickDetector.AnchorPoint = Vector2.new(0, 0.5)
	clickDetector.Archivable = true
	clickDetector.AutoButtonColor = true
	clickDetector.AutoLocalize = true
	clickDetector.AutomaticSize = Enum.AutomaticSize.None
	clickDetector.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	clickDetector.BackgroundTransparency = 1
	clickDetector.BorderColor3 = Color3.fromRGB(0, 0, 0)
	clickDetector.BorderMode = Enum.BorderMode.Outline
	clickDetector.BorderSizePixel = 0
	clickDetector.ClipsDescendants = false
	clickDetector.Draggable = false
	clickDetector.FontFace = Font.fromName("SourceSansPro", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
	clickDetector.Interactable = true
	clickDetector.LayoutOrder = 0
	clickDetector.LineHeight = 1
	clickDetector.MaxVisibleGraphemes = -1
	clickDetector.Modal = false
	clickDetector.OpenTypeFeatures = ""
	clickDetector.Position = UDim2.new(0.10000000149011612, 0, 0.800000011920929, 0)
	clickDetector.RichText = false
	clickDetector.Rotation = 0
	clickDetector.Selectable = true
	clickDetector.Selected = false
	clickDetector.SelectionBehaviorDown = Enum.SelectionBehavior.Escape
	clickDetector.SelectionBehaviorLeft = Enum.SelectionBehavior.Escape
	clickDetector.SelectionBehaviorRight = Enum.SelectionBehavior.Escape
	clickDetector.SelectionBehaviorUp = Enum.SelectionBehavior.Escape
	clickDetector.SelectionGroup = false
	clickDetector.SelectionOrder = 0
	clickDetector.Size = UDim2.new(0, 43, 0, 43)
	clickDetector.SizeConstraint = Enum.SizeConstraint.RelativeXY
	clickDetector.Style = Enum.ButtonStyle.Custom
	clickDetector.Text = ""
	clickDetector.TextColor3 = Color3.fromRGB(0, 0, 0)
	clickDetector.TextDirection = Enum.TextDirection.Auto
	clickDetector.TextScaled = false
	clickDetector.TextSize = 14
	clickDetector.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	clickDetector.TextStrokeTransparency = 1
	clickDetector.TextTransparency = 0
	clickDetector.TextTruncate = Enum.TextTruncate.None
	clickDetector.TextWrapped = false
	clickDetector.TextXAlignment = Enum.TextXAlignment.Center
	clickDetector.TextYAlignment = Enum.TextYAlignment.Center
	clickDetector.Visible = true
	clickDetector.ZIndex = 10
	clickDetector.Parent = billboard

	return billboard
end

--[[
============================================
ESTRUTURA COMPLETA DO CustomProximity:
============================================

CustomProximity (BillboardGui)
├── UIPadding
├── Container (Frame)
│   ├── KeyText (Frame)
│   │   ├── UICorner
│   │   ├── UIStroke (Outer/Preto)
│   │   ├── UIStroke (Inner/Branco)
│   │   ├── Progress (Frame)
│   │   │   └── UICorner
│   │   ├── KeyLabel (TextLabel)
│   │   │   └── UIStroke
│   │   └── ProgressHoldBg (Frame)
│   │       └── UICorner
│   ├── ActionText (TextLabel)
│   │   └── UIStroke
│   └── ObjectText (TextLabel)
│       └── UIStroke
└── ClickDetector (TextButton)
]]

-- Teste: criar em uma part chamada "PartUITeste" no workspace
local partUITeste = workspace:FindFirstChild("PartUITeste")
if partUITeste then
	buildCustomProximity(partUITeste)
end
