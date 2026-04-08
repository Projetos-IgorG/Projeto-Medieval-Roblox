-- StarterPlayer > StarterPlayerScripts > Core > DevSettingsPanel (LocalScript)
--[[
	DevSettingsPanel
	────────────────
	Painel de desenvolvedor escalável para inspecionar e modificar configurações
	em tempo real. Gera controles automaticamente baseado no typeof() de cada
	valor: boolean → toggle, number → input ±, Vector3 → 3 inputs, Color3 → RGB,
	string → label.

	Toggle: X  (ignorado quando um TextBox está focado)
	Nenhum módulo de configuração é modificado — todo registro acontece aqui.
	Zero memory leak: conexões rastreadas e limpas; instâncias destruídas ao trocar categoria.
]]

--==============================================================================
-- Serviços
--==============================================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--==============================================================================
-- Módulos de configuração (require cacheado = write-through)
--==============================================================================

local Modulos = ReplicatedStorage:WaitForChild("Modulos")

local ParkourConfigs = require(script.Parent.Parent:WaitForChild("Parkour"):WaitForChild("Configs"))
local ModConfCombate = require(Modulos:WaitForChild("Combate"):WaitForChild("Modulo_Configuracoes"))
local ModConfJogador = require(Modulos:WaitForChild("Jogador"):WaitForChild("Modulo_ConfiguracoesJogador"))
local VozConfig = require(Modulos:WaitForChild("SistemaDialogo"):WaitForChild("Voz"):WaitForChild("VozConfig"))
local HitboxConfig = require(
	Modulos:WaitForChild("Combate")
		:WaitForChild("Modulo_Hitbox")
		:WaitForChild("Modulo_Shapecast")
		:WaitForChild("Modulo_ConfiguracoesHitbox")
)

--==============================================================================
-- Constantes de estilo
--==============================================================================

local TOGGLE_KEY = Enum.KeyCode.X

local COLORS = {
	bg = Color3.fromRGB(20, 20, 25),
	titleBar = Color3.fromRGB(28, 28, 35),
	categoryBtn = Color3.fromRGB(35, 35, 40),
	categoryHover = Color3.fromRGB(50, 50, 60),
	categoryActive = Color3.fromRGB(70, 130, 230),
	row = Color3.fromRGB(30, 30, 38),
	rowAlt = Color3.fromRGB(26, 26, 32),
	input = Color3.fromRGB(45, 45, 55),
	inputFocus = Color3.fromRGB(55, 55, 70),
	toggleOn = Color3.fromRGB(50, 180, 80),
	toggleOff = Color3.fromRGB(180, 50, 50),
	text = Color3.fromRGB(220, 220, 225),
	textDim = Color3.fromRGB(140, 140, 150),
	accent = Color3.fromRGB(70, 130, 230),
	resetBtn = Color3.fromRGB(200, 80, 60),
	searchBg = Color3.fromRGB(38, 38, 48),
	separator = Color3.fromRGB(55, 55, 65),
}

local FONT_LABEL = Enum.Font.GothamMedium
local FONT_VALUE = Enum.Font.Code
local FONT_TITLE = Enum.Font.GothamBold
local CORNER_RADIUS = UDim.new(0, 6)
local ROW_HEIGHT = 34
local CATEGORY_BTN_HEIGHT = 32
local SECTION_HEADER_HEIGHT = 26

--==============================================================================
-- Agrupamento por seções (prefixo → nome da seção)
-- Ordem importa: primeiro match ganha. Chaves sem match vão para "Outros".
--==============================================================================

type SectionRule = { prefix: string, section: string }

local SECTION_RULES: { [string]: { SectionRule } } = {
	["Parkour Config"] = {
		{ prefix = "Debug", section = "Debug" },
		{ prefix = "Idle", section = "Idle (Agarrado)" },
		{ prefix = "ForwardObstacle", section = "Detecção Frontal" },
		{ prefix = "TopClearance", section = "Clearance Topo" },
		{ prefix = "FrontClearance", section = "Clearance Frontal" },
		{ prefix = "LegProbe", section = "Probe Pernas" },
		{ prefix = "LegSupport", section = "Suporte Pernas" },
		{ prefix = "VaultClearance", section = "Vault Clearance" },
		{ prefix = "VaultBaixo", section = "Vault Baixo" },
		{ prefix = "VaultMedio", section = "Vault Médio" },
		{ prefix = "Vault", section = "Vault (Geral)" },
		{ prefix = "Grab", section = "Agarrar" },
		{ prefix = "Subir", section = "Subir" },
		{ prefix = "Descer", section = "Descer" },
		{ prefix = "LateralSalto", section = "Lateral Salto" },
		{ prefix = "LateralExternal", section = "Lateral Externa" },
		{ prefix = "LateralPath", section = "Lateral Caminho" },
		{ prefix = "LateralCorner", section = "Lateral Quina" },
		{ prefix = "Lateral", section = "Lateral" },
		{ prefix = "Escalar", section = "Escalar" },
		{ prefix = "PuloTras", section = "Pulo Trás" },
		{ prefix = "Momentum", section = "Momentum" },
		{ prefix = "Direction", section = "Direção Input" },
		{ prefix = "Classification", section = "Classificação" },
		{ prefix = "Ray", section = "Raycasts" },
		{ prefix = "Max", section = "Limites" },
		{ prefix = "Min", section = "Limites" },
	},
	["Combate"] = {
		{ prefix = "TempoStun", section = "Stun" },
		{ prefix = "Janela", section = "Janelas de Tempo" },
		{ prefix = "Cooldown", section = "Cooldowns" },
		{ prefix = "Velocidade", section = "Velocidades" },
		{ prefix = "Magnitude", section = "Impulso / Knockback" },
		{ prefix = "Duracao", section = "Impulso / Knockback" },
		{ prefix = "Forca", section = "Dash" },
		{ prefix = "Tempo", section = "Tempos" },
	},
	["Camera / Jogador"] = {
		{ prefix = "Offset", section = "Offsets de Câmera" },
		{ prefix = "ZoomRange", section = "Zoom" },
		{ prefix = "FOVPrimeiraPessoa", section = "Primeira Pessoa" },
		{ prefix = "FOVCorrendo", section = "Primeira Pessoa" },
		{ prefix = "Transicao", section = "Primeira Pessoa" },
		{ prefix = "FOV", section = "FOV" },
		{ prefix = "Default", section = "FOV" },
		{ prefix = "Walk", section = "Movimento Câmera" },
		{ prefix = "Run", section = "Movimento Câmera" },
		{ prefix = "Smooth", section = "Transição" },
		{ prefix = "Transition", section = "Transição" },
	},
	["Hitbox Debug"] = {
		{ prefix = "Debug_Instance_Raycast", section = "Raycast" },
		{ prefix = "Debug_Instance_Spherecast", section = "Spherecast" },
		{ prefix = "Debug_Instance_Blockcast", section = "Blockcast" },
		{ prefix = "Debug_Instance", section = "Aparência" },
		{ prefix = "Debug", section = "Debug Geral" },
	},
}

--- Determina a seção de uma chave com base nas regras da categoria
local function getSectionForKey(categoryName: string, key: string): string
	local rules = SECTION_RULES[categoryName]
	if not rules then
		return ""
	end
	for _, rule in rules do
		if string.sub(key, 1, #rule.prefix) == rule.prefix then
			return rule.section
		end
	end
	return "Outros"
end

--==============================================================================
-- Registry: categorias de configuração
--==============================================================================

export type CategoryEntry = {
	nome: string,
	config: { [string]: any },
	defaults: { [string]: any },
	onChange: ((key: string, value: any) -> ())?,
	setter: ((key: string, value: any) -> ())?, -- setter customizado (ex: Modulo_ConfiguracoesJogador)
}

local categories: { CategoryEntry } = {}

local function registrar(
	nome: string,
	config: { [string]: any },
	defaults: { [string]: any }?,
	onChange: ((key: string, value: any) -> ())?,
	setter: ((key: string, value: any) -> ())?
)
	local defs = if defaults then table.clone(defaults) else table.clone(config)
	table.insert(categories, {
		nome = nome,
		config = config,
		defaults = defs,
		onChange = onChange,
		setter = setter,
	})
end

--==============================================================================
-- Registro de categorias
--==============================================================================

-- 1) Parkour Debug (top-level flags)
local parkourDebug = {
	DebugEnabled = ParkourConfigs.DebugEnabled,
	DebugVerbose = ParkourConfigs.DebugVerbose,
	DebugLifetime = ParkourConfigs.DebugLifetime,
	IdleDebugVerbose = ParkourConfigs.DefaultConfig.IdleDebugVerbose,
	IdleDebugVisualEnabled = ParkourConfigs.DefaultConfig.IdleDebugVisualEnabled,
	IdleDebugStableLogInterval = ParkourConfigs.DefaultConfig.IdleDebugStableLogInterval,
	IdleDebugFlipWindow = ParkourConfigs.DefaultConfig.IdleDebugFlipWindow,
	IdleDebugFlipWarnThreshold = ParkourConfigs.DefaultConfig.IdleDebugFlipWarnThreshold,
}
local parkourDebugDefaults = table.clone(parkourDebug)

registrar("Parkour Debug", parkourDebug, parkourDebugDefaults, function(key, value)
	-- Sync top-level fields back to module
	if ParkourConfigs[key] ~= nil then
		ParkourConfigs[key] = value
	end
	if ParkourConfigs.DefaultConfig[key] ~= nil then
		ParkourConfigs.DefaultConfig[key] = value
	end
end)

-- 2) Parkour Config (DefaultConfig table, excluding debug keys already shown)
local PARKOUR_DEBUG_KEYS = {
	IdleDebugVerbose = true,
	IdleDebugVisualEnabled = true,
	IdleDebugStableLogInterval = true,
	IdleDebugFlipWindow = true,
	IdleDebugFlipWarnThreshold = true,
}
registrar("Parkour Config", ParkourConfigs.DefaultConfig, nil, nil, function(key, value)
	ParkourConfigs.DefaultConfig[key] = value
	ParkourConfigs.invalidateCache()
end)

-- 3) Combate
local MOVEMENT_CONFIG_KEYS = {
	VelocidadeAndando = true,
	VelocidadeCorrendo = true,
	VelocidadeBloqueando = true,
	VelocidadeAgachando = true,
	VelocidadeAparando = true,
	VelocidadeDefesaQuebrada = true,
	VelocidadeEscalando = true,
}

local function refreshLocalCombatMovementSpeed(changedKey: string)
	if not MOVEMENT_CONFIG_KEYS[changedKey] then
		return
	end

	local char = player.Character
	local hum = char and char:FindFirstChildWhichIsA("Humanoid")
	if not hum then
		return
	end

	local statusLocal = char:FindFirstChild("StatusLocal")
	if not statusLocal then
		return
	end

	local function readBool(name: string): boolean
		local valueObj = statusLocal:FindFirstChild(name)
		return valueObj ~= nil and valueObj:IsA("BoolValue") and valueObj.Value == true
	end

	local function readString(name: string): string
		local valueObj = statusLocal:FindFirstChild(name)
		return if valueObj and valueObj:IsA("StringValue") then valueObj.Value else ""
	end

	local estadoAcao = readString("estadoAcao")
	if estadoAcao == "AtacandoLeve" or estadoAcao == "CarregandoPesado" or estadoAcao == "SoltandoPesado" or estadoAcao == "AtaquePesado" then
		hum.WalkSpeed = (ModConfCombate.ObterConfiguracao("VelocidadeBloqueando") or 8) * 1.5
		return
	end

	if estadoAcao == "Defendendo" or readBool("BloqueandoOn") then
		hum.WalkSpeed = ModConfCombate.ObterConfiguracao("VelocidadeBloqueando") or 8
		return
	end

	if readBool("AgachadoOn") then
		hum.WalkSpeed = ModConfCombate.ObterConfiguracao("VelocidadeAgachando") or 12
		return
	end

	if readBool("CorrendoOn") then
		hum.WalkSpeed = ModConfCombate.ObterConfiguracao("VelocidadeCorrendo") or 25
		return
	end

	hum.WalkSpeed = ModConfCombate.ObterConfiguracao("VelocidadeAndando") or 16
end

registrar("Combate", ModConfCombate.ConfiguracaoGlobal, nil, function(key, _value)
	refreshLocalCombatMovementSpeed(key)
end)

-- 4) Camera / Jogador (usa setter existente)
local cameraConfig = ModConfJogador.ObterTodasConfiguracoes()
local cameraDefaults = table.clone(cameraConfig)
registrar("Camera / Jogador", cameraConfig, cameraDefaults, nil, function(key, value)
	ModConfJogador.DefinirConfiguracao(key, value)
end)

-- 5) Voz
local vozFlatConfig = {
	SimpleVoice = VozConfig.SimpleVoice,
	CustomVoice = VozConfig.CustomVoice,
	CustomVoiceFadeDuration = VozConfig.CustomVoiceFadeDuration,
}
local vozDefaults = table.clone(vozFlatConfig)
registrar("Voz", vozFlatConfig, vozDefaults, function(key, value)
	VozConfig[key] = value
end)

-- 6) Hitbox Debug
registrar("Hitbox Debug", HitboxConfig)

-- 7) Runtime (valores especiais lidos/escritos direto no engine)
local runtimeConfig = {
	WalkSpeed = 16,
	JumpPower = 50,
	FOV = 100,
	Gravity = 196.2,
}
local runtimeDefaults = table.clone(runtimeConfig)

local function syncRuntimeFromEngine()
	local char = player.Character
	local hum = char and char:FindFirstChildWhichIsA("Humanoid")
	if hum then
		runtimeConfig.WalkSpeed = hum.WalkSpeed
		runtimeConfig.JumpPower = hum.JumpPower
	end
	runtimeConfig.FOV = workspace.CurrentCamera and workspace.CurrentCamera.FieldOfView or 70
	runtimeConfig.Gravity = workspace.Gravity
end

registrar("Runtime", runtimeConfig, runtimeDefaults, nil, function(key, value)
	runtimeConfig[key] = value
	local char = player.Character
	local hum = char and char:FindFirstChildWhichIsA("Humanoid")
	if key == "WalkSpeed" and hum then
		hum.WalkSpeed = value
	elseif key == "JumpPower" and hum then
		hum.JumpPower = value
	elseif key == "FOV" and workspace.CurrentCamera then
		workspace.CurrentCamera.FieldOfView = value
	elseif key == "Gravity" then
		workspace.Gravity = value
	end
end)

--==============================================================================
-- Estado interno
--==============================================================================

local connections: { RBXScriptConnection } = {}
local controlConnections: { RBXScriptConnection } = {}
local activeCategory: CategoryEntry? = nil
local categoryButtons: { [string]: TextButton } = {}
local isOpen = false

--==============================================================================
-- Helpers de UI
--==============================================================================

local function addCorner(parent: GuiObject, radius: UDim?)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or CORNER_RADIUS
	c.Parent = parent
end

local function addPadding(parent: GuiObject, l: number?, r: number?, t: number?, b: number?)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, l or 0)
	p.PaddingRight = UDim.new(0, r or 0)
	p.PaddingTop = UDim.new(0, t or 0)
	p.PaddingBottom = UDim.new(0, b or 0)
	p.Parent = parent
end

local function addStroke(parent: GuiObject, color: Color3?, thickness: number?)
	local s = Instance.new("UIStroke")
	s.Color = color or COLORS.separator
	s.Thickness = thickness or 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

local function clearControlConnections()
	for _, conn in controlConnections do
		conn:Disconnect()
	end
	table.clear(controlConnections)
end

local function trackConn(conn: RBXScriptConnection)
	table.insert(controlConnections, conn)
end

--==============================================================================
-- Criar GUI
--==============================================================================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DevSettingsPanel"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 100
screenGui.Enabled = false
screenGui.Parent = playerGui

-- Main frame
local mainFrame = Instance.new("Frame")
mainFrame.Name = "Main"
mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
mainFrame.Position = UDim2.fromScale(0.5, 0.5)
mainFrame.Size = UDim2.fromScale(0.7, 0.75)
mainFrame.BackgroundColor3 = COLORS.bg
mainFrame.BackgroundTransparency = 0.02
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui
addCorner(mainFrame, UDim.new(0, 10))
addStroke(mainFrame, COLORS.separator, 1)

-- Title bar
local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, 38)
titleBar.BackgroundColor3 = COLORS.titleBar
titleBar.BorderSizePixel = 0
titleBar.Parent = mainFrame
addCorner(titleBar, UDim.new(0, 10))

-- Fix bottom corners of title bar (overlap with a small rect)
local titleBarFix = Instance.new("Frame")
titleBarFix.Name = "BottomFix"
titleBarFix.Size = UDim2.new(1, 0, 0, 12)
titleBarFix.Position = UDim2.new(0, 0, 1, -12)
titleBarFix.BackgroundColor3 = COLORS.titleBar
titleBarFix.BorderSizePixel = 0
titleBarFix.Parent = titleBar

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.Size = UDim2.new(1, -50, 1, 0)
titleLabel.Position = UDim2.fromOffset(14, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Dev Settings"
titleLabel.TextColor3 = COLORS.text
titleLabel.Font = FONT_TITLE
titleLabel.TextSize = 16
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "Close"
closeBtn.Size = UDim2.fromOffset(38, 38)
closeBtn.Position = UDim2.new(1, -38, 0, 0)
closeBtn.BackgroundTransparency = 1
closeBtn.Text = "X"
closeBtn.TextColor3 = COLORS.textDim
closeBtn.Font = FONT_LABEL
closeBtn.TextSize = 18
closeBtn.Parent = titleBar

-- Body container (below title bar)
local body = Instance.new("Frame")
body.Name = "Body"
body.Size = UDim2.new(1, 0, 1, -38)
body.Position = UDim2.fromOffset(0, 38)
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.Parent = mainFrame

--==============================================================================
-- Left panel (categories)
--==============================================================================

local leftPanel = Instance.new("Frame")
leftPanel.Name = "LeftPanel"
leftPanel.Size = UDim2.fromScale(0.22, 1)
leftPanel.BackgroundColor3 = COLORS.titleBar
leftPanel.BackgroundTransparency = 0.3
leftPanel.BorderSizePixel = 0
leftPanel.Parent = body

local leftScroll = Instance.new("ScrollingFrame")
leftScroll.Name = "Scroll"
leftScroll.Size = UDim2.new(1, 0, 1, -8)
leftScroll.Position = UDim2.fromOffset(0, 4)
leftScroll.BackgroundTransparency = 1
leftScroll.BorderSizePixel = 0
leftScroll.ScrollBarThickness = 3
leftScroll.ScrollBarImageColor3 = COLORS.accent
leftScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
leftScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
leftScroll.Parent = leftPanel

local leftLayout = Instance.new("UIListLayout")
leftLayout.Padding = UDim.new(0, 2)
leftLayout.SortOrder = Enum.SortOrder.LayoutOrder
leftLayout.Parent = leftScroll

addPadding(leftScroll, 6, 6, 4, 4)

--==============================================================================
-- Right panel (settings)
--==============================================================================

local rightPanel = Instance.new("Frame")
rightPanel.Name = "RightPanel"
rightPanel.Size = UDim2.fromScale(0.78, 1)
rightPanel.Position = UDim2.fromScale(0.22, 0)
rightPanel.BackgroundTransparency = 1
rightPanel.BorderSizePixel = 0
rightPanel.Parent = body

-- Search bar
local searchFrame = Instance.new("Frame")
searchFrame.Name = "SearchFrame"
searchFrame.Size = UDim2.new(1, -16, 0, 30)
searchFrame.Position = UDim2.fromOffset(8, 6)
searchFrame.BackgroundColor3 = COLORS.searchBg
searchFrame.BorderSizePixel = 0
searchFrame.Parent = rightPanel
addCorner(searchFrame)

local searchIcon = Instance.new("TextLabel")
searchIcon.Name = "Icon"
searchIcon.Size = UDim2.new(0, 28, 1, 0)
searchIcon.BackgroundTransparency = 1
searchIcon.Text = "🔍"
searchIcon.TextSize = 14
searchIcon.Font = FONT_LABEL
searchIcon.TextColor3 = COLORS.textDim
searchIcon.Parent = searchFrame

local searchBox = Instance.new("TextBox")
searchBox.Name = "SearchBox"
searchBox.Size = UDim2.new(1, -32, 1, 0)
searchBox.Position = UDim2.fromOffset(28, 0)
searchBox.BackgroundTransparency = 1
searchBox.PlaceholderText = "Filtrar configurações..."
searchBox.PlaceholderColor3 = COLORS.textDim
searchBox.TextColor3 = COLORS.text
searchBox.Font = FONT_VALUE
searchBox.TextSize = 13
searchBox.TextXAlignment = Enum.TextXAlignment.Left
searchBox.ClearTextOnFocus = false
searchBox.Text = ""
searchBox.Parent = searchFrame

-- Reset button area
local resetBar = Instance.new("Frame")
resetBar.Name = "ResetBar"
resetBar.Size = UDim2.new(1, -16, 0, 30)
resetBar.Position = UDim2.new(0, 8, 1, -36)
resetBar.BackgroundTransparency = 1
resetBar.BorderSizePixel = 0
resetBar.Parent = rightPanel

local resetBtn = Instance.new("TextButton")
resetBtn.Name = "Reset"
resetBtn.Size = UDim2.fromOffset(140, 28)
resetBtn.Position = UDim2.new(1, -140, 0, 0)
resetBtn.BackgroundColor3 = COLORS.resetBtn
resetBtn.BorderSizePixel = 0
resetBtn.Text = "Resetar Categoria"
resetBtn.TextColor3 = COLORS.text
resetBtn.Font = FONT_LABEL
resetBtn.TextSize = 13
resetBtn.AutoButtonColor = true
resetBtn.Parent = resetBar
addCorner(resetBtn)

-- Counter label
local counterLabel = Instance.new("TextLabel")
counterLabel.Name = "Counter"
counterLabel.Size = UDim2.fromOffset(200, 28)
counterLabel.Position = UDim2.fromOffset(0, 0)
counterLabel.BackgroundTransparency = 1
counterLabel.TextColor3 = COLORS.textDim
counterLabel.Font = FONT_VALUE
counterLabel.TextSize = 12
counterLabel.TextXAlignment = Enum.TextXAlignment.Left
counterLabel.Text = ""
counterLabel.Parent = resetBar

-- Settings scroll area
local settingsScroll = Instance.new("ScrollingFrame")
settingsScroll.Name = "SettingsScroll"
settingsScroll.Size = UDim2.new(1, -16, 1, -78)
settingsScroll.Position = UDim2.fromOffset(8, 42)
settingsScroll.BackgroundTransparency = 1
settingsScroll.BorderSizePixel = 0
settingsScroll.ScrollBarThickness = 4
settingsScroll.ScrollBarImageColor3 = COLORS.accent
settingsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
settingsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
settingsScroll.Parent = rightPanel

local settingsLayout = Instance.new("UIListLayout")
settingsLayout.Padding = UDim.new(0, 2)
settingsLayout.SortOrder = Enum.SortOrder.LayoutOrder
settingsLayout.Parent = settingsScroll

addPadding(settingsScroll, 4, 4, 2, 2)

--==============================================================================
-- Fábricas de controle
--==============================================================================

local function createRow(key: string, layoutOrder: number)
	local row = Instance.new("Frame")
	row.Name = "Row_" .. key
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.BackgroundColor3 = if layoutOrder % 2 == 0 then COLORS.row else COLORS.rowAlt
	row.BackgroundTransparency = 0.15
	row.BorderSizePixel = 0
	row.LayoutOrder = layoutOrder
	addCorner(row, UDim.new(0, 4))

	local label = Instance.new("TextLabel")
	label.Name = "Key"
	label.Size = UDim2.fromScale(0.48, 1)
	label.Position = UDim2.fromOffset(10, 0)
	label.BackgroundTransparency = 1
	label.Text = key
	label.TextColor3 = COLORS.text
	label.Font = FONT_LABEL
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = row

	return row
end

-- Boolean toggle
local function createBooleanControl(
	parent: ScrollingFrame,
	key: string,
	value: boolean,
	layoutOrder: number,
	onChanged: (boolean) -> ()
)
	local row = createRow(key, layoutOrder)
	row.Parent = parent

	local toggle = Instance.new("TextButton")
	toggle.Name = "Toggle"
	toggle.Size = UDim2.fromOffset(60, 22)
	toggle.AnchorPoint = Vector2.new(1, 0.5)
	toggle.Position = UDim2.new(1, -10, 0.5, 0)
	toggle.BackgroundColor3 = if value then COLORS.toggleOn else COLORS.toggleOff
	toggle.BorderSizePixel = 0
	toggle.Text = if value then "ON" else "OFF"
	toggle.TextColor3 = COLORS.text
	toggle.Font = FONT_VALUE
	toggle.TextSize = 13
	toggle.AutoButtonColor = false
	toggle.Parent = row
	addCorner(toggle, UDim.new(0, 4))

	local current = value
	trackConn(toggle.MouseButton1Click:Connect(function()
		current = not current
		toggle.BackgroundColor3 = if current then COLORS.toggleOn else COLORS.toggleOff
		toggle.Text = if current then "ON" else "OFF"
		onChanged(current)
	end))

	return row
end

-- Number input
local function createNumberControl(
	parent: ScrollingFrame,
	key: string,
	value: number,
	layoutOrder: number,
	onChanged: (number) -> ()
)
	local row = createRow(key, layoutOrder)
	row.Parent = parent

	local container = Instance.new("Frame")
	container.Name = "NumCtrl"
	container.Size = UDim2.fromOffset(160, 22)
	container.AnchorPoint = Vector2.new(1, 0.5)
	container.Position = UDim2.new(1, -10, 0.5, 0)
	container.BackgroundTransparency = 1
	container.Parent = row

	local btnMinus = Instance.new("TextButton")
	btnMinus.Name = "Minus"
	btnMinus.Size = UDim2.fromOffset(22, 22)
	btnMinus.Position = UDim2.fromOffset(0, 0)
	btnMinus.BackgroundColor3 = COLORS.input
	btnMinus.BorderSizePixel = 0
	btnMinus.Text = "-"
	btnMinus.TextColor3 = COLORS.text
	btnMinus.Font = FONT_VALUE
	btnMinus.TextSize = 15
	btnMinus.AutoButtonColor = true
	btnMinus.Parent = container
	addCorner(btnMinus, UDim.new(0, 4))

	local inputBox = Instance.new("TextBox")
	inputBox.Name = "Input"
	inputBox.Size = UDim2.new(1, -50, 0, 22)
	inputBox.Position = UDim2.fromOffset(24, 0)
	inputBox.BackgroundColor3 = COLORS.input
	inputBox.BorderSizePixel = 0
	inputBox.Text = tostring(value)
	inputBox.TextColor3 = COLORS.text
	inputBox.Font = FONT_VALUE
	inputBox.TextSize = 13
	inputBox.ClearTextOnFocus = false
	inputBox.Parent = container
	addCorner(inputBox, UDim.new(0, 4))

	local btnPlus = Instance.new("TextButton")
	btnPlus.Name = "Plus"
	btnPlus.Size = UDim2.fromOffset(22, 22)
	btnPlus.Position = UDim2.new(1, -22, 0, 0)
	btnPlus.BackgroundColor3 = COLORS.input
	btnPlus.BorderSizePixel = 0
	btnPlus.Text = "+"
	btnPlus.TextColor3 = COLORS.text
	btnPlus.Font = FONT_VALUE
	btnPlus.TextSize = 15
	btnPlus.AutoButtonColor = true
	btnPlus.Parent = container
	addCorner(btnPlus, UDim.new(0, 4))

	local function getStep(v: number): number
		local abs = math.abs(v)
		if abs == 0 then return 1 end
		if abs < 0.1 then return 0.01 end
		if abs < 1 then return 0.05 end
		if abs < 10 then return 0.1 end
		if abs < 100 then return 1 end
		return 10
	end

	local current = value

	trackConn(inputBox.FocusLost:Connect(function(_enterPressed)
		local n = tonumber(inputBox.Text)
		if n then
			current = n
			inputBox.Text = tostring(n)
			onChanged(n)
		else
			inputBox.Text = tostring(current)
		end
	end))

	trackConn(btnMinus.MouseButton1Click:Connect(function()
		current = current - getStep(current)
		-- Round to avoid floating-point drift
		current = math.round(current * 1000) / 1000
		inputBox.Text = tostring(current)
		onChanged(current)
	end))

	trackConn(btnPlus.MouseButton1Click:Connect(function()
		current = current + getStep(current)
		current = math.round(current * 1000) / 1000
		inputBox.Text = tostring(current)
		onChanged(current)
	end))

	return row
end

-- Vector3 input
local function createVector3Control(
	parent: ScrollingFrame,
	key: string,
	value: Vector3,
	layoutOrder: number,
	onChanged: (Vector3) -> ()
)
	local row = createRow(key, layoutOrder)
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT + 4)
	row.Parent = parent

	local container = Instance.new("Frame")
	container.Name = "V3Ctrl"
	container.Size = UDim2.fromOffset(210, 22)
	container.AnchorPoint = Vector2.new(1, 0.5)
	container.Position = UDim2.new(1, -10, 0.5, 0)
	container.BackgroundTransparency = 1
	container.Parent = row

	local components = { "X", "Y", "Z" }
	local values = { value.X, value.Y, value.Z }
	local boxes = {}

	for i, comp in components do
		local lbl = Instance.new("TextLabel")
		lbl.Name = comp .. "Lbl"
		lbl.Size = UDim2.fromOffset(12, 22)
		lbl.Position = UDim2.fromOffset((i - 1) * 70, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text = comp
		lbl.TextColor3 = COLORS.textDim
		lbl.Font = FONT_VALUE
		lbl.TextSize = 11
		lbl.Parent = container

		local box = Instance.new("TextBox")
		box.Name = comp
		box.Size = UDim2.fromOffset(54, 22)
		box.Position = UDim2.fromOffset((i - 1) * 70 + 13, 0)
		box.BackgroundColor3 = COLORS.input
		box.BorderSizePixel = 0
		box.Text = tostring(math.round(values[i] * 1000) / 1000)
		box.TextColor3 = COLORS.text
		box.Font = FONT_VALUE
		box.TextSize = 12
		box.ClearTextOnFocus = false
		box.Parent = container
		addCorner(box, UDim.new(0, 4))

		boxes[i] = box

		trackConn(box.FocusLost:Connect(function()
			local n = tonumber(box.Text)
			if n then
				values[i] = n
				box.Text = tostring(math.round(n * 1000) / 1000)
				onChanged(Vector3.new(values[1], values[2], values[3]))
			else
				box.Text = tostring(math.round(values[i] * 1000) / 1000)
			end
		end))
	end

	return row
end

-- Color3 display
local function createColor3Control(
	parent: ScrollingFrame,
	key: string,
	value: Color3,
	layoutOrder: number,
	onChanged: (Color3) -> ()
)
	local row = createRow(key, layoutOrder)
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT + 4)
	row.Parent = parent

	local container = Instance.new("Frame")
	container.Name = "C3Ctrl"
	container.Size = UDim2.fromOffset(230, 22)
	container.AnchorPoint = Vector2.new(1, 0.5)
	container.Position = UDim2.new(1, -10, 0.5, 0)
	container.BackgroundTransparency = 1
	container.Parent = row

	-- Preview swatch
	local swatch = Instance.new("Frame")
	swatch.Name = "Swatch"
	swatch.Size = UDim2.fromOffset(22, 22)
	swatch.Position = UDim2.fromOffset(0, 0)
	swatch.BackgroundColor3 = value
	swatch.BorderSizePixel = 0
	swatch.Parent = container
	addCorner(swatch, UDim.new(0, 4))
	addStroke(swatch, COLORS.separator, 1)

	local components = { "R", "G", "B" }
	local values = {
		math.round(value.R * 255),
		math.round(value.G * 255),
		math.round(value.B * 255),
	}
	local boxes = {}

	for i, comp in components do
		local lbl = Instance.new("TextLabel")
		lbl.Name = comp .. "Lbl"
		lbl.Size = UDim2.fromOffset(12, 22)
		lbl.Position = UDim2.fromOffset(28 + (i - 1) * 66, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text = comp
		lbl.TextColor3 = COLORS.textDim
		lbl.Font = FONT_VALUE
		lbl.TextSize = 11
		lbl.Parent = container

		local box = Instance.new("TextBox")
		box.Name = comp
		box.Size = UDim2.fromOffset(46, 22)
		box.Position = UDim2.fromOffset(28 + (i - 1) * 66 + 13, 0)
		box.BackgroundColor3 = COLORS.input
		box.BorderSizePixel = 0
		box.Text = tostring(values[i])
		box.TextColor3 = COLORS.text
		box.Font = FONT_VALUE
		box.TextSize = 12
		box.ClearTextOnFocus = false
		box.Parent = container
		addCorner(box, UDim.new(0, 4))

		boxes[i] = box

		trackConn(box.FocusLost:Connect(function()
			local n = tonumber(box.Text)
			if n then
				n = math.clamp(math.round(n), 0, 255)
				values[i] = n
				box.Text = tostring(n)
				local c3 = Color3.fromRGB(values[1], values[2], values[3])
				swatch.BackgroundColor3 = c3
				onChanged(c3)
			else
				box.Text = tostring(values[i])
			end
		end))
	end

	return row
end

-- String (read-only display)
local function createStringControl(
	parent: ScrollingFrame,
	key: string,
	value: string,
	layoutOrder: number
)
	local row = createRow(key, layoutOrder)
	row.Parent = parent

	local lbl = Instance.new("TextLabel")
	lbl.Name = "Value"
	lbl.Size = UDim2.new(0.45, -10, 1, 0)
	lbl.AnchorPoint = Vector2.new(1, 0)
	lbl.Position = UDim2.new(1, -10, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = value
	lbl.TextColor3 = COLORS.textDim
	lbl.Font = FONT_VALUE
	lbl.TextSize = 12
	lbl.TextXAlignment = Enum.TextXAlignment.Right
	lbl.TextTruncate = Enum.TextTruncate.AtEnd
	lbl.Parent = row

	return row
end

-- Section header (visual separator between groups)
local function createSectionHeader(parent: ScrollingFrame, title: string, layoutOrder: number)
	local header = Instance.new("Frame")
	header.Name = "Section_" .. title
	header.Size = UDim2.new(1, 0, 0, SECTION_HEADER_HEIGHT)
	header.BackgroundTransparency = 1
	header.BorderSizePixel = 0
	header.LayoutOrder = layoutOrder
	header.Parent = parent

	-- Left line
	local lineLeft = Instance.new("Frame")
	lineLeft.Name = "LineL"
	lineLeft.Size = UDim2.fromOffset(12, 1)
	lineLeft.Position = UDim2.new(0, 6, 0.5, 0)
	lineLeft.BackgroundColor3 = COLORS.accent
	lineLeft.BackgroundTransparency = 0.4
	lineLeft.BorderSizePixel = 0
	lineLeft.Parent = header

	local lbl = Instance.new("TextLabel")
	lbl.Name = "Title"
	lbl.Size = UDim2.new(1, -24, 1, 0)
	lbl.Position = UDim2.fromOffset(22, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = title
	lbl.TextColor3 = COLORS.accent
	lbl.Font = FONT_TITLE
	lbl.TextSize = 12
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = header

	return header
end

--==============================================================================
-- Renderizar categoria
--==============================================================================

local function clearSettings()
	clearControlConnections()
	for _, child in settingsScroll:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

local function renderCategory(category: CategoryEntry, filter: string?)
	clearSettings()
	activeCategory = category

	-- Sync runtime values
	if category.nome == "Runtime" then
		syncRuntimeFromEngine()
	end

	-- Highlight active button
	for nome, btn in categoryButtons do
		if nome == category.nome then
			btn.BackgroundColor3 = COLORS.categoryActive
			btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		else
			btn.BackgroundColor3 = COLORS.categoryBtn
			btn.TextColor3 = COLORS.text
		end
	end

	-- Collect and sort keys
	local keys: { string } = {}
	for k, v in category.config do
		local t = typeof(v)
		-- Skip internal sentinels, functions, and unsupported tables
		if
			k ~= "__ParkourMergedConfig"
			and t ~= "function"
			and (t == "boolean" or t == "number" or t == "string" or t == "Vector3" or t == "Color3")
		then
			-- Skip parkour debug keys already registered in debug category
			if category.nome == "Parkour Config" and PARKOUR_DEBUG_KEYS[k] then
				continue
			end
			-- Apply filter
			if filter and filter ~= "" then
				if not string.find(string.lower(k), string.lower(filter), 1, true) then
					continue
				end
			end
			table.insert(keys, k)
		end
	end
	table.sort(keys)

	counterLabel.Text = tostring(#keys) .. " configurações"

	-- Group keys by section (preserves section order by first appearance)
	local hasRules = SECTION_RULES[category.nome] ~= nil
	local sectionOrder: { string } = {}
	local sectionKeys: { [string]: { string } } = {}

	if hasRules then
		for _, key in keys do
			local section = getSectionForKey(category.nome, key)
			if not sectionKeys[section] then
				sectionKeys[section] = {}
				table.insert(sectionOrder, section)
			end
			table.insert(sectionKeys[section], key)
		end
	else
		-- No rules: single unnamed group
		sectionOrder = { "" }
		sectionKeys[""] = keys
	end

	-- Build controls with section headers
	local layoutOrder = 0

	local function buildControl(key: string, value: any)
		layoutOrder += 1
		local t = typeof(value)

		local function onChanged(newValue: any)
			if category.setter then
				category.setter(key, newValue)
			else
				category.config[key] = newValue
			end
			if category.onChange then
				category.onChange(key, newValue)
			end
		end

		if t == "boolean" then
			createBooleanControl(settingsScroll, key, value, layoutOrder, onChanged)
		elseif t == "number" then
			createNumberControl(settingsScroll, key, value, layoutOrder, onChanged)
		elseif t == "Vector3" then
			createVector3Control(settingsScroll, key, value, layoutOrder, onChanged)
		elseif t == "Color3" then
			createColor3Control(settingsScroll, key, value, layoutOrder, onChanged)
		elseif t == "string" then
			createStringControl(settingsScroll, key, value, layoutOrder)
		end
	end

	for _, section in sectionOrder do
		if section ~= "" then
			layoutOrder += 1
			createSectionHeader(settingsScroll, section, layoutOrder)
		end
		for _, key in sectionKeys[section] do
			buildControl(key, category.config[key])
		end
	end

	-- Reset scroll position
	settingsScroll.CanvasPosition = Vector2.zero
end

--==============================================================================
-- Construir botões de categoria
--==============================================================================

for i, cat in categories do
	local btn = Instance.new("TextButton")
	btn.Name = "Cat_" .. cat.nome
	btn.Size = UDim2.new(1, 0, 0, CATEGORY_BTN_HEIGHT)
	btn.BackgroundColor3 = COLORS.categoryBtn
	btn.BorderSizePixel = 0
	btn.Text = cat.nome
	btn.TextColor3 = COLORS.text
	btn.Font = FONT_LABEL
	btn.TextSize = 13
	btn.TextTruncate = Enum.TextTruncate.AtEnd
	btn.AutoButtonColor = false
	btn.LayoutOrder = i
	btn.Parent = leftScroll
	addCorner(btn, UDim.new(0, 4))

	categoryButtons[cat.nome] = btn

	-- Hover effect
	local function onHover()
		if activeCategory and activeCategory.nome == cat.nome then return end
		btn.BackgroundColor3 = COLORS.categoryHover
	end
	local function onLeave()
		if activeCategory and activeCategory.nome == cat.nome then return end
		btn.BackgroundColor3 = COLORS.categoryBtn
	end

	table.insert(connections, btn.MouseEnter:Connect(onHover))
	table.insert(connections, btn.MouseLeave:Connect(onLeave))
	table.insert(connections, btn.MouseButton1Click:Connect(function()
		searchBox.Text = ""
		renderCategory(cat)
	end))
end

--==============================================================================
-- Search filtering
--==============================================================================

table.insert(connections, searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	if activeCategory then
		renderCategory(activeCategory, searchBox.Text)
	end
end))

--==============================================================================
-- Reset button
--==============================================================================

table.insert(connections, resetBtn.MouseButton1Click:Connect(function()
	if not activeCategory then return end
	local cat = activeCategory
	for key, defVal in cat.defaults do
		if cat.setter then
			cat.setter(key, defVal)
		else
			cat.config[key] = defVal
		end
		if cat.onChange then
			cat.onChange(key, defVal)
		end
	end
	renderCategory(cat, searchBox.Text)
end))

--==============================================================================
-- Close button
--==============================================================================

table.insert(connections, closeBtn.MouseButton1Click:Connect(function()
	isOpen = false
	screenGui.Enabled = false
end))

--==============================================================================
-- Toggle keybind (X)
--==============================================================================

table.insert(connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode ~= TOGGLE_KEY then return end
	-- Don't toggle if typing in a TextBox
	if UserInputService:GetFocusedTextBox() then return end

	isOpen = not isOpen
	screenGui.Enabled = isOpen

	if isOpen and not activeCategory and #categories > 0 then
		renderCategory(categories[1])
	end
end))

--==============================================================================
-- Cleanup seguro
--==============================================================================

table.insert(connections, screenGui.Destroying:Connect(function()
	clearControlConnections()
	for _, conn in connections do
		conn:Disconnect()
	end
	table.clear(connections)
end))

-- Categories are rendered on first open via the toggle keybind
