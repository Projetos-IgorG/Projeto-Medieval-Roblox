-- ServerScriptService/BuildCustomProximity.server.lua

local function buildCustomProximity(part)
	-- BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CustomProximity"
	billboard.Archivable = true
	billboard.Active = false
	billboard.AlwaysOnTop = true
	billboard.Enabled = true
	billboard.ExtentsOffset = Vector3.new(0, 0, 0)
	billboard.ExtentsOffsetWorldSpace = Vector3.new(0, 0, 0)
	billboard.LightInfluence = 0.5
	billboard.MaxDistance = 12
	billboard.PlayerToHideFrom = nil
	billboard.ResetOnSpawn = true
	billboard.Size = UDim2.new(7, 0, 1.8, 0)
	billboard.SizeOffset = Vector2.new(0, 0)
	billboard.StudsOffset = Vector3.new(0, 1.5, 0)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 0, 0)
	billboard.ZIndexBehavior = Enum.ZIndexBehavior.Global
	billboard.Adornee = nil
	billboard.Parent = part

	-- UIPadding
	local uiPadding = Instance.new("UIPadding")
	uiPadding.Name = "UIPadding"
	uiPadding.Archivable = true
	uiPadding.PaddingBottom = UDim.new(0, 0)
	uiPadding.PaddingLeft = UDim.new(0.4, 0)
	uiPadding.PaddingRight = UDim.new(0, 0)
	uiPadding.PaddingTop = UDim.new(0, 0)
	uiPadding.Parent = billboard

	-- Container (Frame)
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Archivable = true
	container.Active = false
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.AutomaticSize = Enum.AutomaticSize.None
	container.BackgroundColor3 = Color3.fromRGB(163, 162, 165)
	container.BackgroundTransparency = 1
	container.BorderColor3 = Color3.fromRGB(27, 42, 53)
	container.BorderMode = Enum.BorderMode.Outline
	container.BorderSizePixel = 1
	container.Interactable = true
	container.LayoutOrder = 0
	container.Position = UDim2.new(0.5, 0, 1, 0)
	container.Rotation = 0
	container.Size = UDim2.new(0.8, 0, 1, 0)
	container.SizeConstraint = Enum.SizeConstraint.RelativeXY
	container.Style = Enum.FrameStyle.Custom
	container.Visible = true
	container.ZIndex = 1
	container.SelectionImageObject = nil

	-- Propriedades somente leitura (do print) e/ou calculadas pelo layout:
	-- container.AbsolutePosition / AbsoluteRotation / AbsoluteSize / GuiState / UniqueId

	container.Parent = billboard

	-- Filhos do Container (estrutura; propriedades virão nos próximos prints)
	-- KeyText (Frame)
	local keyText = Instance.new("Frame")
	keyText.Name = "KeyText"
	keyText.Archivable = true
	keyText.Active = false
	keyText.AnchorPoint = Vector2.new(0, 0.5)
	keyText.AutomaticSize = Enum.AutomaticSize.None
	keyText.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	keyText.BackgroundTransparency = 0.35
	keyText.BorderColor3 = Color3.fromRGB(27, 42, 53)
	keyText.BorderMode = Enum.BorderMode.Outline
	keyText.BorderSizePixel = 0
	keyText.Interactable = true
	keyText.LayoutOrder = 0
	keyText.Position = UDim2.new(0, 5, 0.3, 0)
	keyText.Rotation = 0
	keyText.Size = UDim2.new(0, 40, 0, 40)
	keyText.SizeConstraint = Enum.SizeConstraint.RelativeXY
	keyText.Style = Enum.FrameStyle.Custom
	keyText.Visible = true
	keyText.ZIndex = 1
	keyText.SelectionImageObject = nil
	keyText.Parent = container

	-- Filhos do KeyText: UICorner
	local keyTextCorner = Instance.new("UICorner")
	keyTextCorner.Name = "UICorner"
	keyTextCorner.Archivable = true
	keyTextCorner.CornerRadius = UDim.new(1, 0)
	keyTextCorner.Parent = keyText

	-- Filhos do KeyText: UIStroke (Outer / Preto)
	local keyTextStroke1 = Instance.new("UIStroke")
	keyTextStroke1.Name = "UIStroke"
	keyTextStroke1.Archivable = true
	keyTextStroke1.Enabled = true
	keyTextStroke1.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	keyTextStroke1.BorderOffset = UDim.new(0, 0)
	keyTextStroke1.BorderStrokePosition = Enum.BorderStrokePosition.Outer
	keyTextStroke1.Color = Color3.fromRGB(0, 0, 0)
	keyTextStroke1.LineJoinMode = Enum.LineJoinMode.Round
	keyTextStroke1.StrokeSizingMode = Enum.StrokeSizingMode.FixedSize
	keyTextStroke1.Thickness = 3
	keyTextStroke1.Transparency = 0.35
	keyTextStroke1.ZIndex = 1
	keyTextStroke1.Parent = keyText

	-- Filhos do KeyText: UIStroke (Inner / Branco)
	local keyTextStroke2 = Instance.new("UIStroke")
	keyTextStroke2.Name = "UIStroke"
	keyTextStroke2.Archivable = true
	keyTextStroke2.Enabled = true
	keyTextStroke2.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	keyTextStroke2.BorderOffset = UDim.new(0.01, 0)
	keyTextStroke2.BorderStrokePosition = Enum.BorderStrokePosition.Inner
	keyTextStroke2.Color = Color3.fromRGB(255, 255, 255)
	keyTextStroke2.LineJoinMode = Enum.LineJoinMode.Round
	keyTextStroke2.StrokeSizingMode = Enum.StrokeSizingMode.FixedSize
	keyTextStroke2.Thickness = 2
	keyTextStroke2.Transparency = 0.35
	keyTextStroke2.ZIndex = 2
	keyTextStroke2.Parent = keyText

	-- Progress (Frame) - filho de KeyText
	local progress = Instance.new("Frame")
	progress.Name = "Progress"
	progress.Archivable = true
	progress.Active = false
	progress.AnchorPoint = Vector2.new(0.5, 0.5)
	progress.AutomaticSize = Enum.AutomaticSize.None
	progress.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	progress.BackgroundTransparency = 0.3
	progress.BorderColor3 = Color3.fromRGB(27, 42, 53)
	progress.BorderMode = Enum.BorderMode.Outline
	progress.BorderSizePixel = 0
	progress.Interactable = true
	progress.LayoutOrder = 0
	progress.Position = UDim2.new(0.5, 0, 0.5, 0)
	progress.Rotation = 0
	progress.Size = UDim2.new(0, 0, 0, 0)
	progress.SizeConstraint = Enum.SizeConstraint.RelativeXY
	progress.Style = Enum.FrameStyle.Custom
	progress.Visible = true
	progress.ZIndex = 2
	progress.SelectionImageObject = nil
	progress.Parent = keyText

	-- UICorner (filho de Progress)
	local progressCorner = Instance.new("UICorner")
	progressCorner.Name = "UICorner"
	progressCorner.Archivable = true
	progressCorner.CornerRadius = UDim.new(1, 0)
	progressCorner.Parent = progress

	-- KeyLabel (TextLabel) - filho de Container
	local keyLabel = Instance.new("TextLabel")
	keyLabel.Name = "KeyLabel"
	keyLabel.Archivable = true
	keyLabel.Active = false
	keyLabel.AnchorPoint = Vector2.new(0, 0)
	keyLabel.AutomaticSize = Enum.AutomaticSize.None
	keyLabel.BackgroundColor3 = Color3.fromRGB(163, 162, 165)
	keyLabel.BackgroundTransparency = 1
	keyLabel.BorderColor3 = Color3.fromRGB(27, 42, 53)
	keyLabel.BorderMode = Enum.BorderMode.Outline
	keyLabel.BorderSizePixel = 1
	keyLabel.Interactable = true
	keyLabel.LayoutOrder = 0
	keyLabel.Position = UDim2.new(0, 0, 0, 0)
	keyLabel.Rotation = 0
	keyLabel.Size = UDim2.new(1, 0, 1, 0)
	keyLabel.SizeConstraint = Enum.SizeConstraint.RelativeXY
	keyLabel.Visible = true
	keyLabel.ZIndex = 3
	keyLabel.SelectionImageObject = nil

	-- Texto (KeyLabel)
	keyLabel.Text = "E"
	keyLabel.FontFace = Font.fromName("Fondamento", Enum.FontWeight.Bold, Enum.FontStyle.Normal)
	keyLabel.LineHeight = 1
	keyLabel.MaxVisibleGraphemes = -1
	keyLabel.RichText = false
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

	keyLabel.Parent = keyText

	-- UIStroke (filho de KeyLabel)
	local keyLabelStroke = Instance.new("UIStroke")
	keyLabelStroke.Name = "UIStroke"
	keyLabelStroke.Archivable = true
	keyLabelStroke.Enabled = true
	keyLabelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	keyLabelStroke.Color = Color3.fromRGB(0, 0, 0)
	keyLabelStroke.LineJoinMode = Enum.LineJoinMode.Round
	keyLabelStroke.StrokeSizingMode = Enum.StrokeSizingMode.FixedSize
	keyLabelStroke.Thickness = 2
	keyLabelStroke.Transparency = 0.5
	keyLabelStroke.Parent = keyLabel

	-- ActionText (TextLabel) - filho de Container
	local actionText = Instance.new("TextLabel")
	actionText.Name = "ActionText"
	actionText.Archivable = true
	actionText.Active = false
	actionText.AnchorPoint = Vector2.new(0, 0)
	actionText.AutomaticSize = Enum.AutomaticSize.None
	actionText.BackgroundColor3 = Color3.fromRGB(163, 162, 165)
	actionText.BackgroundTransparency = 1
	actionText.BorderColor3 = Color3.fromRGB(27, 42, 53)
	actionText.BorderMode = Enum.BorderMode.Outline
	actionText.BorderSizePixel = 0
	actionText.Interactable = true
	actionText.LayoutOrder = 0
	actionText.Position = UDim2.new(0, 60, 0, 0)
	actionText.Rotation = 0
	actionText.Size = UDim2.new(1, 0, 0.3, 0)
	actionText.SizeConstraint = Enum.SizeConstraint.RelativeXY
	actionText.Visible = true
	actionText.ZIndex = 1
	actionText.SelectionImageObject = nil
	actionText.AutoLocalize = true
	actionText.Selectable = false

	-- Texto (ActionText)
	actionText.Text = "Talk"
	actionText.FontFace = Font.fromName("Fondamento", Enum.FontWeight.Bold, Enum.FontStyle.Normal)
	actionText.LineHeight = 1
	actionText.MaxVisibleGraphemes = -1
	actionText.RichText = false
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

	actionText.Parent = container

	-- UIStroke (filho de ActionText)
	local actionTextStroke = Instance.new("UIStroke")
	actionTextStroke.Name = "UIStroke"
	actionTextStroke.Archivable = true
	actionTextStroke.Enabled = true
	actionTextStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	actionTextStroke.Color = Color3.fromRGB(0, 0, 0)
	actionTextStroke.LineJoinMode = Enum.LineJoinMode.Round
	actionTextStroke.StrokeSizingMode = Enum.StrokeSizingMode.FixedSize
	actionTextStroke.Thickness = 1.5
	actionTextStroke.Transparency = 0.1
	actionTextStroke.Parent = actionText

	-- ObjectText (TextLabel) - filho de Container
	local objectText = Instance.new("TextLabel")
	objectText.Name = "ObjectText"
	objectText.Archivable = true
	objectText.Active = false
	objectText.AnchorPoint = Vector2.new(0, 0)
	objectText.AutomaticSize = Enum.AutomaticSize.None
	objectText.BackgroundColor3 = Color3.fromRGB(163, 162, 165)
	objectText.BackgroundTransparency = 1
	objectText.BorderColor3 = Color3.fromRGB(27, 42, 53)
	objectText.BorderMode = Enum.BorderMode.Outline
	objectText.BorderSizePixel = 1
	objectText.Interactable = true
	objectText.LayoutOrder = 0
	objectText.Position = UDim2.new(0, 60, 0.3, 0)
	objectText.Rotation = 0
	objectText.Size = UDim2.new(1, 0, 0.6, 0)
	objectText.SizeConstraint = Enum.SizeConstraint.RelativeXY
	objectText.Visible = true
	objectText.ZIndex = 1
	objectText.SelectionImageObject = nil
	objectText.AutoLocalize = true
	objectText.Selectable = false

	-- Texto (ObjectText)
	objectText.Text = "Lord Jalkior"
	objectText.FontFace = Font.fromName("Fondamento", Enum.FontWeight.Bold, Enum.FontStyle.Normal)
	objectText.LineHeight = 1
	objectText.MaxVisibleGraphemes = -1
	objectText.RichText = false
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

	objectText.Parent = container

	-- UIStroke (filho de ObjectText)
	local objectTextStroke = Instance.new("UIStroke")
	objectTextStroke.Name = "UIStroke"
	objectTextStroke.Archivable = true
	objectTextStroke.Enabled = true
	objectTextStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	objectTextStroke.Color = Color3.fromRGB(0, 0, 0)
	objectTextStroke.LineJoinMode = Enum.LineJoinMode.Round
	objectTextStroke.StrokeSizingMode = Enum.StrokeSizingMode.FixedSize
	objectTextStroke.Thickness = 1.5
	objectTextStroke.Transparency = 0.1
	objectTextStroke.Parent = objectText

	return billboard
end

local partUITeste = workspace:FindFirstChild("PartUITeste")
if partUITeste then
	buildCustomProximity(partUITeste)
end
