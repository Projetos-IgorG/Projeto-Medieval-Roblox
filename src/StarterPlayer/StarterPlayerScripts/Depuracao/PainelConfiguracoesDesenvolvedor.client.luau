--[[
    Script: PainelConfiguracoesDesenvolvedor.client.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/Depuracao
    Responsabilidade: Renderiza painel local de configuracoes e comandos de desenvolvimento.
    Uso: LocalScript; roda automaticamente para o jogador local em src/StarterPlayer/StarterPlayerScripts/Depuracao.
    Nao faz: Nao valida autoridade do servidor, nao salva dados persistentes e nao substitui regras server-side.
	Funcoes principais: renderInicio, renderConfiguracoes, renderToolbuilder, renderClimas, renderJogadorMundo, renderStatusJogador
]]
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Modulos = ReplicatedStorage

local ParkourConfigs = require(
	script.Parent.Parent
		:WaitForChild("Jogador")
		:WaitForChild("Parkour")
		:WaitForChild("Configuracoes")
		:WaitForChild("ConfigParkour")
)
local ModConfCombate =
	require(Modulos:WaitForChild("Combate"):WaitForChild("Configuracoes"):WaitForChild("ConfigCombate"))
local ModConfJogador = require(
	Modulos:WaitForChild("Jogador"):WaitForChild("Camera"):WaitForChild("Configuracoes"):WaitForChild("ConfigCamera")
)
local HitboxConfig = require(
	Modulos:WaitForChild("Combate"):WaitForChild("Hitbox"):WaitForChild("Shapecast"):WaitForChild("HitboxConfig")
)
local AmbienteReplicado = Modulos:WaitForChild("Mundo"):WaitForChild("Ambiente")
local CatalogoAmbiente = require(AmbienteReplicado:WaitForChild("CatalogoAmbiente"))
local CompositorAmbiente = require(AmbienteReplicado:WaitForChild("CompositorAmbiente"))
local AplicadorAmbiente = require(AmbienteReplicado:WaitForChild("AplicadorAmbiente"))
local ExtratorAmbiente = require(AmbienteReplicado:WaitForChild("ExtratorAmbiente"))
local ConfiguracaoTempo = require(AmbienteReplicado:WaitForChild("ConfiguracaoTempo"))
local EquipamentosModelos = Modulos:WaitForChild("Equipamentos"):WaitForChild("Modelos")

local EntidadesPasta = Modulos:WaitForChild("Entidades")
local LeitorEntidade = require(EntidadesPasta:WaitForChild("LeitorEntidade"))

local AdminDevRemote = nil

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

type SectionRule = { prefix: string, section: string }

local SECTION_RULES: { [string]: { SectionRule } } = {
	["Parkour Config"] = {
		{ prefix = "Debug", section = "Debug" },
		{ prefix = "Idle", section = "Idle (Agarrado)" },
		{ prefix = "ForwardRayGrid", section = "Detecção Frontal (RayGrid)" },
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
		{ prefix = "CooldownRoll", section = "Roll" },
		{ prefix = "ForcaRoll", section = "Roll" },
		{ prefix = "VelocidadeAnimacaoRoll", section = "Roll" },
		{ prefix = "JanelaCancelamentoRoll", section = "Roll" },
		{ prefix = "RollCamera", section = "Roll" },
		{ prefix = "CooldownDash", section = "Dash" },
		{ prefix = "ForcaDash", section = "Dash" },
		{ prefix = "DuracaoDash", section = "Dash" },
		{ prefix = "VelocidadeAnimacaoDash", section = "Dash" },
		{ prefix = "JanelaCancelamentoDash", section = "Dash" },
		{ prefix = "DashCamera", section = "Dash" },
		{ prefix = "Janela", section = "Janelas de Tempo" },
		{ prefix = "Cooldown", section = "Cooldowns" },
		{ prefix = "Magnitude", section = "Impulso / Knockback" },
		{ prefix = "Duracao", section = "Impulso / Knockback" },
		{ prefix = "Forca", section = "Dash" },
		{ prefix = "Tempo", section = "Tempos" },
	},
	["Movement"] = {
		{ prefix = "Tempo", section = "Tempos" },
		{ prefix = "Velocidade", section = "Velocidades" },
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

export type CategoryEntry = {
	nome: string,
	tipo: string?,
	config: { [string]: any },
	onChange: ((key: string, value: any) -> ())?,
	setter: ((key: string, value: any) -> ())?,
}

local categories: { CategoryEntry } = {}

local fireAdminAction: (acao: string, overrides: { [string]: any }?) -> ()

local adminState = {
	alvo = player.Name,
	tipoTool = "Armas",
	tool = "espada_ferro",
	quantidade = "1",
	distancia = "8",
	ambiente = CatalogoAmbiente.AmbientePadrao,
	clima = CatalogoAmbiente.ClimaPadrao,
	periodo = "Dia",
	condicao = CatalogoAmbiente.ClimaPadrao,
	horario = ConfiguracaoTempo.FormatarHora(ConfiguracaoTempo.HorarioInicialMinutos),
	transicao = "20",
	bloquearSyncClimasAte = 0,
	pausado = false,
}

local AMBIENTES_PAINEL = {
	{ id = "Planice", nome = "Planice", emoji = "🌾", subtitulo = "campos" },
	{ id = "Pantano", nome = "Pantano", emoji = "🌿", subtitulo = "umido" },
	{ id = "Neve", nome = "Neve", emoji = "❄️", subtitulo = "frio" },
	{ id = "Areia", nome = "Areia", emoji = "🏜️", subtitulo = "seco" },
	{ id = "Floresta", nome = "Floresta", emoji = "🌲", subtitulo = "denso" },
}

local PERIODOS_PAINEL = {
	{ id = "Dia", nome = "Dia", emoji = "☀️", horario = "12:00" },
	{ id = "Noite", nome = "Noite", emoji = "🌙", horario = "00:00" },
	{ id = "Amanhecer", nome = "Amanhecer", emoji = "🌅", horario = "06:00" },
	{ id = "Anoitecer", nome = "Anoitecer", emoji = "🌇", horario = "18:30" },
}

local CONDICOES_PAINEL = {
	{ id = "DiaLimpo", nome = "Limpo", emoji = "☀️", subtitulo = "default" },
	{ id = "ChuvaCalma", nome = "Chuva Calma", emoji = "🌦️", subtitulo = "leve" },
	{ id = "ChuvaNormal", nome = "Chuva Normal", emoji = "🌧️", subtitulo = "media" },
	{ id = "Tempestade", nome = "Tempestade", emoji = "⛈️", subtitulo = "forte" },
}

local function sortStringsCaseInsensitive(values: { string })
	table.sort(values, function(left, right)
		return string.lower(left) < string.lower(right)
	end)
end

local function containsString(values: { string }, target: string): boolean
	for _, value in ipairs(values) do
		if value == target then
			return true
		end
	end

	return false
end

local function listarTiposTool(): { string }
	local tipos = {}
	for _, child in ipairs(EquipamentosModelos:GetChildren()) do
		if child:IsA("Folder") then
			table.insert(tipos, child.Name)
		end
	end

	sortStringsCaseInsensitive(tipos)
	return tipos
end

local function listarToolsPorTipo(tipoTool: string): { string }
	local pastaTipo = EquipamentosModelos:FindFirstChild(tipoTool)
	if not pastaTipo or not pastaTipo:IsA("Folder") then
		return {}
	end

	local tools = {}
	for _, child in ipairs(pastaTipo:GetChildren()) do
		if child:IsA("Tool") or child:IsA("Folder") or child:IsA("Model") then
			table.insert(tools, child.Name)
		end
	end

	sortStringsCaseInsensitive(tools)
	return tools
end

local function garantirSelecaoToolbuilder(): ({ string }, { string })
	local tipos = listarTiposTool()
	if #tipos == 0 then
		adminState.tipoTool = ""
		adminState.tool = ""
		return tipos, {}
	end

	if adminState.tipoTool == "" or not containsString(tipos, adminState.tipoTool) then
		adminState.tipoTool = tipos[1]
	end

	local tools = listarToolsPorTipo(adminState.tipoTool)
	if #tools == 0 then
		adminState.tool = ""
		return tipos, tools
	end

	if adminState.tool == "" or not containsString(tools, adminState.tool) then
		adminState.tool = tools[1]
	end

	return tipos, tools
end

local function listarNomesJogadores(filtro: string?): { string }
	local nomes = {}
	local consulta = string.lower(filtro or "")

	for _, candidate in ipairs(Players:GetPlayers()) do
		local nome = candidate.Name
		if consulta == "" or string.find(string.lower(nome), consulta, 1, true) then
			table.insert(nomes, nome)
		end
	end

	sortStringsCaseInsensitive(nomes)
	return nomes
end

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
	if ParkourConfigs[key] ~= nil then
		ParkourConfigs[key] = value
	end
	if ParkourConfigs.DefaultConfig[key] ~= nil then
		ParkourConfigs.DefaultConfig[key] = value
	end
end)

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
	if estadoAcao == "Atacando" then
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

local cameraConfig = ModConfJogador.ObterTodasConfiguracoes()
local cameraDefaults = table.clone(cameraConfig)
registrar("Camera / Jogador", cameraConfig, cameraDefaults, nil, function(key, value)
	ModConfJogador.DefinirConfiguracao(key, value)
end)

registrar("Hitbox Debug", HitboxConfig, nil, function(key, value)
	if key == "ParryDebugBlock" then
		fireAdminAction("MudarDebugParry", { ativo = value })
	end
end)

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

local connections: { RBXScriptConnection } = {}
local controlConnections: { RBXScriptConnection } = {}
local leftConnections: { RBXScriptConnection } = {}
local activeCategory: CategoryEntry? = nil
local categoryButtons: { [string]: TextButton } = {}
local isOpen = false
local telaAtual = "Inicio"

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
	return s
end

local function clearControlConnections()
	for _, conn in controlConnections do
		conn:Disconnect()
	end
	table.clear(controlConnections)
end

local function clearLeftConnections()
	for _, conn in leftConnections do
		conn:Disconnect()
	end
	table.clear(leftConnections)
end

local function trackConn(conn: RBXScriptConnection)
	table.insert(controlConnections, conn)
end

local function trackLeftConn(conn: RBXScriptConnection)
	table.insert(leftConnections, conn)
end

local adminStatusLabel: TextLabel? = nil
local adminStatusTexto = "Pronto"
local adminRemoteConnection: RBXScriptConnection? = nil

local function setAdminStatus(texto: string, sucesso: boolean?)
	adminStatusTexto = texto
	if not adminStatusLabel then
		return
	end

	adminStatusLabel.Text = texto
	if sucesso == true then
		adminStatusLabel.TextColor3 = Color3.fromRGB(90, 220, 120)
	elseif sucesso == false then
		adminStatusLabel.TextColor3 = Color3.fromRGB(240, 110, 90)
	else
		adminStatusLabel.TextColor3 = COLORS.textDim
	end
end

local function resolveAdminRemote(): RemoteEvent?
	if AdminDevRemote and AdminDevRemote.Parent then
		return AdminDevRemote
	end

	local remotos = ReplicatedStorage:FindFirstChild("Remotos")
	local remote = remotos and remotos:FindFirstChild("AcaoAdminDev")
	if remote and remote:IsA("RemoteEvent") then
		AdminDevRemote = remote
		return remote
	end

	return nil
end

local function ensureAdminRemoteConnection(): RemoteEvent?
	local remote = resolveAdminRemote()
	if remote and not adminRemoteConnection then
		local connection = remote.OnClientEvent:Connect(function(tipoMensagem, mensagem, sucesso)
			if tipoMensagem == "Resultado" then
				setAdminStatus(tostring(mensagem), sucesso == true)
			end
		end)
		adminRemoteConnection = connection
		table.insert(connections, connection)
	end

	return remote
end

local function criarAdminPayload(overrides: { [string]: any }?)
	local payload = {
		alvo = adminState.alvo,
		tipoTool = adminState.tipoTool,
		tool = adminState.tool,
		quantidade = tonumber(adminState.quantidade) or 1,
		distancia = tonumber(adminState.distancia) or 8,
		ambiente = adminState.ambiente,
		clima = adminState.clima,
		horario = adminState.horario,
		transicao = tonumber(adminState.transicao) or 6,
	}

	if overrides then
		for key, value in overrides do
			payload[key] = value
		end
	end

	return payload
end

fireAdminAction = function(acao: string, overrides: { [string]: any }?)
	local remote = ensureAdminRemoteConnection()
	if not remote then
		setAdminStatus("Remote admin indisponivel", false)
		return
	end

	remote:FireServer(acao, criarAdminPayload(overrides))
	setAdminStatus("Enviado: " .. acao, nil)
end

local function obterMinutosPainel(): number
	local minutos = ConfiguracaoTempo.ConverterHorario(adminState.horario)
	if minutos then
		return minutos
	end

	local estadoMundo = ReplicatedStorage:FindFirstChild("EstadoMundo")
	local valorMinutos = estadoMundo and estadoMundo:FindFirstChild("MinutosDoDia")
	if valorMinutos and valorMinutos:IsA("NumberValue") then
		return valorMinutos.Value
	end

	return ConfiguracaoTempo.HorarioInicialMinutos
end

local function selecionarAmbiente(ambienteId: string)
	local ambiente, chaveAmbiente = CatalogoAmbiente.ObterAmbiente(ambienteId)
	adminState.ambiente = chaveAmbiente
	if not ambiente.climas[adminState.clima] then
		local primeiroClima = CatalogoAmbiente.ListarClimas(chaveAmbiente)[1]
		adminState.clima = if primeiroClima then primeiroClima.id else CatalogoAmbiente.ClimaPadrao
	end
	adminState.condicao = adminState.clima
end

local function selecionarClima(climaId: string)
	local _, chaveClima = CatalogoAmbiente.ObterClima(adminState.ambiente, climaId)
	adminState.clima = chaveClima
	adminState.condicao = chaveClima
end

local function aplicarPreviewAmbiente()
	local duracao = tonumber(adminState.transicao) or 4
	local resolvido = CompositorAmbiente.Compor(adminState.ambiente, adminState.clima, obterMinutosPainel(), {
		duracao = duracao,
	})
	AplicadorAmbiente.Aplicar(resolvido, { duracao = duracao })
	setAdminStatus("Preview local: " .. resolvido.ambienteNome .. " / " .. resolvido.climaNome, true)
end

local function aplicarAmbienteNoMundo()
	adminState.bloquearSyncClimasAte = os.clock() + 0.8
	fireAdminAction("AplicarAmbienteClima", {
		ambiente = adminState.ambiente,
		clima = adminState.clima,
		transicao = tonumber(adminState.transicao) or 6,
	})
end

local function definirHorarioMundo()
	adminState.bloquearSyncClimasAte = os.clock() + 0.8
	fireAdminAction("DefinirHorarioMundo", {
		horario = adminState.horario,
	})
end

local function avancarTempoMundo(minutos: number)
	adminState.bloquearSyncClimasAte = os.clock() + 0.8
	fireAdminAction("AvancarTempoMundo", {
		minutos = minutos,
	})
end

local function extrairClimaAtual()
	ExtratorAmbiente.ImprimirClima(tostring(adminState.clima) .. "Extraido", tostring(adminState.clima) .. " Extraido")
	setAdminStatus("Clima atual impresso no console", true)
end

local function extrairAmbienteAtual()
	ExtratorAmbiente.ImprimirAmbiente(
		tostring(adminState.ambiente) .. "Extraido",
		tostring(adminState.ambiente) .. " Extraido"
	)
	setAdminStatus("Ambiente atual impresso no console", true)
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DevSettingsPanel"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 100
screenGui.Enabled = false
screenGui.Parent = playerGui

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

local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, 38)
titleBar.BackgroundColor3 = COLORS.titleBar
titleBar.BorderSizePixel = 0
titleBar.Parent = mainFrame
addCorner(titleBar, UDim.new(0, 10))

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

local body = Instance.new("Frame")
body.Name = "Body"
body.Size = UDim2.new(1, 0, 1, -38)
body.Position = UDim2.fromOffset(0, 38)
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.Parent = mainFrame

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

local rightPanel = Instance.new("Frame")
rightPanel.Name = "RightPanel"
rightPanel.Size = UDim2.fromScale(0.78, 1)
rightPanel.Position = UDim2.fromScale(0.22, 0)
rightPanel.BackgroundTransparency = 1
rightPanel.BorderSizePixel = 0
rightPanel.Parent = body

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
		if abs == 0 then
			return 1
		end
		if abs < 0.1 then
			return 0.01
		end
		if abs < 1 then
			return 0.05
		end
		if abs < 10 then
			return 0.1
		end
		if abs < 100 then
			return 1
		end
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

local function createStringControl(parent: ScrollingFrame, key: string, value: string, layoutOrder: number)
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

local function createSectionHeader(parent: ScrollingFrame, title: string, layoutOrder: number)
	local header = Instance.new("Frame")
	header.Name = "Section_" .. title
	header.Size = UDim2.new(1, 0, 0, SECTION_HEADER_HEIGHT)
	header.BackgroundTransparency = 1
	header.BorderSizePixel = 0
	header.LayoutOrder = layoutOrder
	header.Parent = parent

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

local function createAdminInput(parent: ScrollingFrame, labelText: string, stateKey: string, layoutOrder: number)
	local row = createRow(labelText, layoutOrder)
	row.Size = UDim2.new(1, 0, 0, 38)
	row.Parent = parent

	local label = row:FindFirstChild("Key") :: TextLabel?
	if label then
		label.Size = UDim2.new(0.34, -10, 1, 0)
	end

	local input = Instance.new("TextBox")
	input.Name = "Input"
	input.Size = UDim2.new(0.62, 0, 0, 24)
	input.AnchorPoint = Vector2.new(1, 0.5)
	input.Position = UDim2.new(1, -10, 0.5, 0)
	input.BackgroundColor3 = COLORS.input
	input.BorderSizePixel = 0
	input.ClearTextOnFocus = false
	input.Text = tostring(adminState[stateKey] or "")
	input.PlaceholderText = labelText
	input.TextColor3 = COLORS.text
	input.PlaceholderColor3 = COLORS.textDim
	input.Font = FONT_VALUE
	input.TextSize = 13
	input.TextXAlignment = Enum.TextXAlignment.Left
	input.Parent = row
	addCorner(input, UDim.new(0, 4))
	addPadding(input, 6, 6, 0, 0)

	trackConn(input.FocusLost:Connect(function()
		adminState[stateKey] = input.Text
	end))
end

local function createAdminDropdown(
	parent: ScrollingFrame,
	labelText: string,
	layoutOrder: number,
	options: { string },
	selectedValue: string,
	onSelect: (string) -> (),
	placeholderText: string?
)
	local row = createRow(labelText, layoutOrder)
	local collapsedHeight = 38
	local optionHeight = 24
	local maxVisibleOptions = 6
	local visibleOptions = math.min(#options, maxVisibleOptions)
	local listHeight = if visibleOptions > 0 then visibleOptions * optionHeight + 8 else 0
	local expanded = false

	row.Size = UDim2.new(1, 0, 0, collapsedHeight)
	row.ClipsDescendants = true
	row.Parent = parent

	local label = row:FindFirstChild("Key") :: TextLabel?
	if label then
		label.Size = UDim2.new(0.34, -10, 1, 0)
	end

	local button = Instance.new("TextButton")
	button.Name = "Dropdown"
	button.Size = UDim2.new(0.62, 0, 0, 24)
	button.AnchorPoint = Vector2.new(1, 0)
	button.Position = UDim2.new(1, -10, 0, 7)
	button.BackgroundColor3 = COLORS.input
	button.BorderSizePixel = 0
	button.TextColor3 = COLORS.text
	button.Font = FONT_VALUE
	button.TextSize = 13
	button.TextXAlignment = Enum.TextXAlignment.Left
	button.AutoButtonColor = true
	button.Parent = row
	addCorner(button, UDim.new(0, 4))
	addPadding(button, 8, 24, 0, 0)

	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.Size = UDim2.fromOffset(18, 24)
	arrow.AnchorPoint = Vector2.new(1, 0)
	arrow.Position = UDim2.new(1, -4, 0, 0)
	arrow.BackgroundTransparency = 1
	arrow.Text = "▼"
	arrow.TextColor3 = COLORS.textDim
	arrow.Font = FONT_LABEL
	arrow.TextSize = 11
	arrow.Parent = button

	local listFrame = Instance.new("ScrollingFrame")
	listFrame.Name = "DropdownList"
	listFrame.Size = UDim2.new(0.62, 0, 0, listHeight)
	listFrame.AnchorPoint = Vector2.new(1, 0)
	listFrame.Position = UDim2.new(1, -10, 0, 35)
	listFrame.BackgroundColor3 = COLORS.searchBg
	listFrame.BorderSizePixel = 0
	listFrame.Visible = false
	listFrame.ScrollBarThickness = if #options > maxVisibleOptions then 4 else 0
	listFrame.CanvasSize = UDim2.fromOffset(0, #options * optionHeight)
	listFrame.Parent = row
	addCorner(listFrame, UDim.new(0, 4))
	addStroke(listFrame, COLORS.separator, 1)

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 2)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = listFrame

	addPadding(listFrame, 4, 4, 4, 4)

	local function updateButtonText()
		local texto = selectedValue
		if texto == "" then
			texto = placeholderText or "Selecionar"
		end
		button.Text = texto
		button.TextColor3 = if selectedValue == "" then COLORS.textDim else COLORS.text
		arrow.Text = if expanded then "▲" else "▼"
	end

	local function setExpanded(nextExpanded: boolean)
		expanded = nextExpanded and #options > 0
		listFrame.Visible = expanded
		row.Size = UDim2.new(1, 0, 0, if expanded then collapsedHeight + listHeight else collapsedHeight)
		updateButtonText()
	end

	for index, option in ipairs(options) do
		local optionButton = Instance.new("TextButton")
		optionButton.Name = "Option_" .. option
		optionButton.Size = UDim2.new(1, 0, 0, optionHeight)
		optionButton.BackgroundColor3 = if option == selectedValue then COLORS.categoryActive else COLORS.categoryBtn
		optionButton.BorderSizePixel = 0
		optionButton.Text = option
		optionButton.TextColor3 = COLORS.text
		optionButton.Font = FONT_VALUE
		optionButton.TextSize = 12
		optionButton.TextXAlignment = Enum.TextXAlignment.Left
		optionButton.AutoButtonColor = true
		optionButton.LayoutOrder = index
		optionButton.Parent = listFrame
		addCorner(optionButton, UDim.new(0, 4))
		addPadding(optionButton, 8, 8, 0, 0)

		trackConn(optionButton.MouseButton1Click:Connect(function()
			selectedValue = option
			onSelect(option)
			setExpanded(false)
		end))
	end

	trackConn(button.MouseButton1Click:Connect(function()
		setExpanded(not expanded)
	end))

	updateButtonText()
	return row
end

local function createAdminAutocompleteInput(
	parent: ScrollingFrame,
	labelText: string,
	stateKey: string,
	layoutOrder: number,
	optionsProvider: (string) -> { string },
	placeholderText: string?
)
	local row = createRow(labelText, layoutOrder)
	local collapsedHeight = 38
	local optionHeight = 24
	local maxVisibleOptions = 5
	local suggestionConnections = {}
	local focused = false

	row.Size = UDim2.new(1, 0, 0, collapsedHeight)
	row.ClipsDescendants = true
	row.Parent = parent

	local label = row:FindFirstChild("Key") :: TextLabel?
	if label then
		label.Size = UDim2.new(0.34, -10, 1, 0)
	end

	local shell = Instance.new("Frame")
	shell.Name = "InputShell"
	shell.Size = UDim2.new(0.62, 0, 0, 24)
	shell.AnchorPoint = Vector2.new(1, 0)
	shell.Position = UDim2.new(1, -10, 0, 7)
	shell.BackgroundColor3 = COLORS.input
	shell.BorderSizePixel = 0
	shell.Parent = row
	addCorner(shell, UDim.new(0, 4))

	local ghostLabel = Instance.new("TextLabel")
	ghostLabel.Name = "GhostText"
	ghostLabel.Size = UDim2.new(1, -16, 1, 0)
	ghostLabel.Position = UDim2.fromOffset(8, 0)
	ghostLabel.BackgroundTransparency = 1
	ghostLabel.Text = ""
	ghostLabel.TextColor3 = COLORS.textDim
	ghostLabel.TextTransparency = 0.45
	ghostLabel.Font = FONT_VALUE
	ghostLabel.TextSize = 13
	ghostLabel.TextXAlignment = Enum.TextXAlignment.Left
	ghostLabel.ZIndex = 1
	ghostLabel.Parent = shell

	local input = Instance.new("TextBox")
	input.Name = "Input"
	input.Size = UDim2.new(1, -16, 1, 0)
	input.Position = UDim2.fromOffset(8, 0)
	input.BackgroundTransparency = 1
	input.BorderSizePixel = 0
	input.ClearTextOnFocus = false
	input.Text = tostring(adminState[stateKey] or "")
	input.PlaceholderText = placeholderText or labelText
	input.PlaceholderColor3 = COLORS.textDim
	input.TextColor3 = COLORS.text
	input.Font = FONT_VALUE
	input.TextSize = 13
	input.TextXAlignment = Enum.TextXAlignment.Left
	input.ZIndex = 2
	input.Parent = shell

	local suggestions = Instance.new("ScrollingFrame")
	suggestions.Name = "Suggestions"
	suggestions.Size = UDim2.fromScale(0.62, 0)
	suggestions.AnchorPoint = Vector2.new(1, 0)
	suggestions.Position = UDim2.new(1, -10, 0, 35)
	suggestions.BackgroundColor3 = COLORS.searchBg
	suggestions.BorderSizePixel = 0
	suggestions.Visible = false
	suggestions.ScrollBarThickness = 0
	suggestions.CanvasSize = UDim2.fromOffset(0, 0)
	suggestions.Parent = row
	addCorner(suggestions, UDim.new(0, 4))
	addStroke(suggestions, COLORS.separator, 1)

	local suggestionsLayout = Instance.new("UIListLayout")
	suggestionsLayout.Padding = UDim.new(0, 2)
	suggestionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	suggestionsLayout.Parent = suggestions

	addPadding(suggestions, 4, 4, 4, 4)

	local function clearSuggestionButtons()
		for _, connection in ipairs(suggestionConnections) do
			connection:Disconnect()
		end
		table.clear(suggestionConnections)

		for _, child in ipairs(suggestions:GetChildren()) do
			if child:IsA("GuiButton") then
				child:Destroy()
			end
		end
	end

	local function syncSuggestions()
		local query = input.Text
		adminState[stateKey] = query
		clearSuggestionButtons()

		local matches = optionsProvider(query)
		local visibleCount = math.min(#matches, maxVisibleOptions)
		local showList = focused and query ~= "" and visibleCount > 0
		local bestMatch = matches[1]
		local lowerQuery = string.lower(query)

		if
			bestMatch
			and query ~= ""
			and string.sub(string.lower(bestMatch), 1, #lowerQuery) == lowerQuery
			and string.lower(bestMatch) ~= lowerQuery
		then
			ghostLabel.Text = bestMatch
		else
			ghostLabel.Text = ""
		end

		if showList then
			for index = 1, visibleCount do
				local option = matches[index]
				local suggestionButton = Instance.new("TextButton")
				suggestionButton.Name = "Suggestion_" .. option
				suggestionButton.Size = UDim2.new(1, 0, 0, optionHeight)
				suggestionButton.BackgroundColor3 = COLORS.categoryBtn
				suggestionButton.BorderSizePixel = 0
				suggestionButton.Text = option
				suggestionButton.TextColor3 = COLORS.text
				suggestionButton.Font = FONT_VALUE
				suggestionButton.TextSize = 12
				suggestionButton.TextXAlignment = Enum.TextXAlignment.Left
				suggestionButton.AutoButtonColor = true
				suggestionButton.LayoutOrder = index
				suggestionButton.Parent = suggestions
				addCorner(suggestionButton, UDim.new(0, 4))
				addPadding(suggestionButton, 8, 8, 0, 0)

				local suggestionConn = suggestionButton.MouseButton1Click:Connect(function()
					input.Text = option
					adminState[stateKey] = option
					focused = false
					syncSuggestions()
				end)
				table.insert(suggestionConnections, suggestionConn)
			end
		end

		local listHeight = if showList then visibleCount * optionHeight + 8 else 0
		suggestions.Visible = showList
		suggestions.Size = UDim2.new(0.62, 0, 0, listHeight)
		suggestions.CanvasSize = UDim2.fromOffset(0, visibleCount * optionHeight)
		row.Size = UDim2.new(1, 0, 0, collapsedHeight + listHeight)
	end

	trackConn(input:GetPropertyChangedSignal("Text"):Connect(syncSuggestions))
	trackConn(input.Focused:Connect(function()
		focused = true
		syncSuggestions()
	end))
	trackConn(input.FocusLost:Connect(function(enterPressed)
		focused = false
		local matches = optionsProvider(input.Text)
		if enterPressed and #matches > 0 then
			input.Text = matches[1]
			adminState[stateKey] = matches[1]
		else
			adminState[stateKey] = input.Text
		end
		syncSuggestions()
	end))

	syncSuggestions()
	return row
end

local function createScreenButton(
	parent: ScrollingFrame,
	text: string,
	layoutOrder: number,
	onClick: () -> (),
	height: number?
)
	local row = Instance.new("Frame")
	row.Name = "AcaoTela_" .. tostring(layoutOrder)
	row.Size = UDim2.new(1, 0, 0, height or 34)
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.LayoutOrder = layoutOrder
	row.Parent = parent

	local button = Instance.new("TextButton")
	button.Name = "Executar"
	button.Size = UDim2.new(1, -8, 1, -4)
	button.Position = UDim2.fromOffset(4, 2)
	button.BackgroundColor3 = COLORS.categoryBtn
	button.BorderSizePixel = 0
	button.Text = text
	button.TextColor3 = COLORS.text
	button.Font = FONT_LABEL
	button.TextSize = 13
	button.AutoButtonColor = true
	button.Parent = row
	addCorner(button, UDim.new(0, 4))

	trackConn(button.MouseButton1Click:Connect(function()
		onClick()
	end))

	return row
end

local function createAdminButton(
	parent: ScrollingFrame,
	text: string,
	acao: string,
	layoutOrder: number,
	overrides: { [string]: any }?
)
	return createScreenButton(parent, text, layoutOrder, function()
		fireAdminAction(acao, overrides)
	end)
end

local function createHomeTileGrid(
	parent: ScrollingFrame,
	layoutOrder: number,
	itens: { { texto: string, emoji: string, onClick: () -> () } }
)
	local linhas = math.ceil(#itens / 3)
	local gridFrame = Instance.new("Frame")
	gridFrame.Name = "HomeTiles"
	gridFrame.Size = UDim2.new(1, 0, 0, linhas * 118)
	gridFrame.BackgroundTransparency = 1
	gridFrame.BorderSizePixel = 0
	gridFrame.LayoutOrder = layoutOrder
	gridFrame.Parent = parent

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(108, 108)
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.FillDirection = Enum.FillDirection.Horizontal
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = gridFrame

	for indice, item in ipairs(itens) do
		local button = Instance.new("TextButton")
		button.Name = "Tile_" .. item.texto
		button.Size = UDim2.fromOffset(108, 108)
		button.BackgroundColor3 = COLORS.categoryBtn
		button.BorderSizePixel = 0
		button.Text = item.emoji .. "\n" .. item.texto
		button.TextColor3 = COLORS.text
		button.Font = FONT_LABEL
		button.TextSize = 14
		button.TextWrapped = true
		button.AutoButtonColor = true
		button.LayoutOrder = indice
		button.Parent = gridFrame
		addCorner(button, UDim.new(0, 6))
		addStroke(button, COLORS.separator, 1)

		trackConn(button.MouseButton1Click:Connect(item.onClick))
	end
end

local function createTileGrid(
	parent: ScrollingFrame,
	layoutOrder: number,
	itens: {
		{
			titulo: string,
			subtitulo: string?,
			emoji: string,
			ativo: boolean?,
			onClick: () -> (),
		}
	},
	colunas: number?,
	tamanho: number?
)
	local totalColunas = math.max(colunas or 4, 1)
	local lado = tamanho or 104
	local linhas = math.ceil(#itens / totalColunas)
	local gridFrame = Instance.new("Frame")
	gridFrame.Name = "TileGrid_" .. tostring(layoutOrder)
	gridFrame.Size = UDim2.new(1, 0, 0, linhas * (lado + 10))
	gridFrame.BackgroundTransparency = 1
	gridFrame.BorderSizePixel = 0
	gridFrame.LayoutOrder = layoutOrder
	gridFrame.Parent = parent

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(lado, lado)
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.FillDirection = Enum.FillDirection.Horizontal
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = gridFrame

	for indice, item in ipairs(itens) do
		local ativo = item.ativo == true
		local button = Instance.new("TextButton")
		button.Name = "Tile_" .. item.titulo
		button.Size = UDim2.fromOffset(lado, lado)
		button.BackgroundColor3 = if ativo then COLORS.categoryActive else COLORS.categoryBtn
		button.BorderSizePixel = 0
		local subtituloTexto = if item.subtitulo and item.subtitulo ~= "" then "\n" .. item.subtitulo else ""
		button.Text = item.emoji .. "\n" .. item.titulo .. subtituloTexto
		button.TextColor3 = Color3.fromRGB(245, 245, 250)
		button.Font = FONT_LABEL
		button.TextSize = 13
		button.TextWrapped = true
		button.AutoButtonColor = true
		button.LayoutOrder = indice
		button.Parent = gridFrame
		addCorner(button, UDim.new(0, 6))
		addStroke(button, if ativo then Color3.fromRGB(120, 180, 255) else COLORS.separator, if ativo then 2 else 1)

		trackConn(button.MouseEnter:Connect(function()
			if not ativo then
				button.BackgroundColor3 = COLORS.categoryHover
			end
		end))
		trackConn(button.MouseLeave:Connect(function()
			if not ativo then
				button.BackgroundColor3 = COLORS.categoryBtn
			end
		end))
		trackConn(button.MouseButton1Click:Connect(item.onClick))
	end
end

local function createStatusRow(parent: ScrollingFrame, layoutOrder: number)
	local statusRow = Instance.new("Frame")
	statusRow.Name = "StatusTela"
	statusRow.Size = UDim2.new(1, 0, 0, 42)
	statusRow.BackgroundColor3 = COLORS.row
	statusRow.BackgroundTransparency = 0.15
	statusRow.BorderSizePixel = 0
	statusRow.LayoutOrder = layoutOrder
	statusRow.Parent = parent
	addCorner(statusRow, UDim.new(0, 4))

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.Size = UDim2.new(1, -16, 1, 0)
	statusLabel.Position = UDim2.fromOffset(8, 0)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = FONT_VALUE
	statusLabel.TextSize = 12
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextWrapped = true
	statusLabel.Text = adminStatusTexto
	statusLabel.TextColor3 = COLORS.textDim
	statusLabel.Parent = statusRow
	adminStatusLabel = statusLabel
end

local function renderAdminActions()
	ensureAdminRemoteConnection()
	counterLabel.Text = "Ferramentas admin"
	resetBtn.Visible = false
	searchFrame.Visible = false
	settingsScroll.Position = UDim2.fromOffset(8, 6)
	settingsScroll.Size = UDim2.new(1, -16, 1, -42)

	local layoutOrder = 0
	local function nextOrder()
		layoutOrder += 1
		return layoutOrder
	end

	createSectionHeader(settingsScroll, "Contexto", nextOrder())
	createAdminInput(settingsScroll, "Jogador alvo", "alvo", nextOrder())
	createAdminInput(settingsScroll, "Tipo tool", "tipoTool", nextOrder())
	createAdminInput(settingsScroll, "Tool", "tool", nextOrder())
	createAdminInput(settingsScroll, "Quantidade", "quantidade", nextOrder())
	createAdminInput(settingsScroll, "Distancia", "distancia", nextOrder())

	createSectionHeader(settingsScroll, "Criacao", nextOrder())
	createAdminButton(settingsScroll, "Criar tool no mundo", "CriarToolMundo", nextOrder())
	createAdminButton(settingsScroll, "Dar tool ao alvo", "DarTool", nextOrder())

	createSectionHeader(settingsScroll, "Jogador", nextOrder())
	createAdminButton(settingsScroll, "Curar alvo", "CurarAlvo", nextOrder())
	createAdminButton(settingsScroll, "Respawn alvo", "RespawnAlvo", nextOrder())
	createAdminButton(settingsScroll, "Ir ate alvo", "IrAteAlvo", nextOrder())
	createAdminButton(settingsScroll, "Trazer alvo", "TrazerAlvo", nextOrder())
	createAdminButton(settingsScroll, "Congelar alvo", "CongelarAlvo", nextOrder())
	createAdminButton(settingsScroll, "Descongelar alvo", "DescongelarAlvo", nextOrder())

	createSectionHeader(settingsScroll, "Mundo", nextOrder())
	createAdminButton(settingsScroll, "Limpar tools soltas", "LimparToolsSoltas", nextOrder())

	local statusRow = Instance.new("Frame")
	statusRow.Name = "AdminStatus"
	statusRow.Size = UDim2.new(1, 0, 0, 42)
	statusRow.BackgroundColor3 = COLORS.row
	statusRow.BackgroundTransparency = 0.15
	statusRow.BorderSizePixel = 0
	statusRow.LayoutOrder = nextOrder()
	statusRow.Parent = settingsScroll
	addCorner(statusRow, UDim.new(0, 4))

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.Size = UDim2.new(1, -16, 1, 0)
	statusLabel.Position = UDim2.fromOffset(8, 0)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = FONT_VALUE
	statusLabel.TextSize = 12
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextWrapped = true
	statusLabel.Text = adminStatusTexto
	statusLabel.TextColor3 = COLORS.textDim
	statusLabel.Parent = statusRow
	adminStatusLabel = statusLabel

	settingsScroll.CanvasPosition = Vector2.zero
end

local function clearSettings()
	clearControlConnections()
	adminStatusLabel = nil
	for _, child in settingsScroll:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

local function renderCategory(category: CategoryEntry, filter: string?)
	clearSettings()
	activeCategory = category

	if category.nome == "Runtime" then
		syncRuntimeFromEngine()
	end

	for nome, btn in categoryButtons do
		if nome == category.nome then
			btn.BackgroundColor3 = COLORS.categoryActive
			btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		else
			btn.BackgroundColor3 = COLORS.categoryBtn
			btn.TextColor3 = COLORS.text
		end
	end

	if category.tipo == "AcoesAdmin" then
		renderAdminActions()
		return
	end

	resetBtn.Visible = true
	searchFrame.Visible = true
	settingsScroll.Position = UDim2.fromOffset(8, 42)
	settingsScroll.Size = UDim2.new(1, -16, 1, -78)

	local keys: { string } = {}
	for k, v in category.config do
		local t = typeof(v)

		if
			k ~= "__ParkourMergedConfig"
			and t ~= "function"
			and (t == "boolean" or t == "number" or t == "string" or t == "Vector3" or t == "Color3")
		then
			if category.nome == "Parkour Config" and PARKOUR_DEBUG_KEYS[k] then
				continue
			end

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
		sectionOrder = { "" }
		sectionKeys[""] = keys
	end

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

	settingsScroll.CanvasPosition = Vector2.zero
end

local renderInicio
local renderConfiguracoes
local renderToolbuilder
local renderClimas
local renderJogadorMundo
local renderStatusJogador
local renderNPCs

local function clearLeftButtons()
	clearLeftConnections()
	table.clear(categoryButtons)
	for _, child in leftScroll:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
end

local function createLeftButton(text: string, layoutOrder: number, active: boolean, onClick: () -> ())
	local btn = Instance.new("TextButton")
	btn.Name = "Nav_" .. text
	btn.Size = UDim2.new(1, 0, 0, CATEGORY_BTN_HEIGHT)
	btn.BackgroundColor3 = if active then COLORS.categoryActive else COLORS.categoryBtn
	btn.BorderSizePixel = 0
	btn.Text = text
	btn.TextColor3 = if active then Color3.fromRGB(255, 255, 255) else COLORS.text
	btn.Font = FONT_LABEL
	btn.TextSize = 13
	btn.TextTruncate = Enum.TextTruncate.AtEnd
	btn.AutoButtonColor = false
	btn.LayoutOrder = layoutOrder
	btn.Parent = leftScroll
	addCorner(btn, UDim.new(0, 4))

	trackLeftConn(btn.MouseEnter:Connect(function()
		if not active then
			btn.BackgroundColor3 = COLORS.categoryHover
		end
	end))
	trackLeftConn(btn.MouseLeave:Connect(function()
		if not active then
			btn.BackgroundColor3 = COLORS.categoryBtn
		end
	end))
	trackLeftConn(btn.MouseButton1Click:Connect(onClick))

	return btn
end

local function configurarAreaConteudo(titulo: string, contador: string)
	titleLabel.Text = titulo
	resetBtn.Visible = false
	searchFrame.Visible = false
	counterLabel.Text = contador
	settingsScroll.Position = UDim2.fromOffset(8, 6)
	settingsScroll.Size = UDim2.new(1, -16, 1, -42)
	settingsScroll.CanvasPosition = Vector2.zero
end

local function criarNavegacaoPrincipal(ativo: string)
	clearLeftButtons()
	createLeftButton("Inicio", 1, ativo == "Inicio", function()
		renderInicio()
	end)
	createLeftButton("Configuracoes", 2, ativo == "Configuracoes", function()
		renderConfiguracoes()
	end)
	createLeftButton("Toolbuilder", 3, ativo == "Toolbuilder", function()
		renderToolbuilder()
	end)
	createLeftButton("Climas", 4, ativo == "Climas", function()
		renderClimas()
	end)
	createLeftButton("Jogador / Mundo", 5, ativo == "Jogador / Mundo", function()
		renderJogadorMundo()
	end)
	createLeftButton("Status", 6, ativo == "Status", function()
		renderStatusJogador()
	end)
	createLeftButton("NPCs", 7, ativo == "NPCs", function()
		renderNPCs()
	end)
end

function renderInicio()
	telaAtual = "Inicio"
	activeCategory = nil
	clearSettings()
	criarNavegacaoPrincipal("Inicio")
	configurarAreaConteudo("Dev Panel", "Selecione uma ferramenta")

	local ordem = 0
	local function nextOrder()
		ordem += 1
		return ordem
	end

	createSectionHeader(settingsScroll, "Ferramentas", nextOrder())
	createHomeTileGrid(settingsScroll, nextOrder(), {
		{ emoji = "⚙️", texto = "Configs", onClick = renderConfiguracoes },
		{ emoji = "🛠️", texto = "Tools", onClick = renderToolbuilder },
		{ emoji = "🌦️", texto = "Climas", onClick = renderClimas },
		{ emoji = "🌍", texto = "Mundo", onClick = renderJogadorMundo },
		{
			emoji = "📊",
			texto = "Status",
			onClick = function()
				renderStatusJogador()
			end,
		},
		{
			emoji = "🧝",
			texto = "NPCs",
			onClick = function()
				renderNPCs()
			end,
		},
	})
end

function renderConfiguracoes()
	telaAtual = "Configuracoes"
	clearSettings()
	clearLeftButtons()
	titleLabel.Text = "Dev Panel / Configuracoes"
	searchFrame.Visible = true
	resetBtn.Visible = true
	settingsScroll.Position = UDim2.fromOffset(8, 42)
	settingsScroll.Size = UDim2.new(1, -16, 1, -78)

	createLeftButton("Inicio", 1, false, function()
		renderInicio()
	end)
	for i, cat in categories do
		local btn = createLeftButton(
			cat.nome,
			i + 1,
			activeCategory ~= nil and activeCategory.nome == cat.nome,
			function()
				searchBox.Text = ""
				renderCategory(cat)
			end
		)
		categoryButtons[cat.nome] = btn
	end

	local categoriaInicial = activeCategory
	if not categoriaInicial or categoriaInicial.tipo == "AcoesAdmin" then
		categoriaInicial = categories[1]
	end
	if categoriaInicial then
		renderCategory(categoriaInicial, searchBox.Text)
	end
end

function renderToolbuilder()
	telaAtual = "Toolbuilder"
	activeCategory = nil
	clearSettings()
	criarNavegacaoPrincipal("Toolbuilder")
	configurarAreaConteudo("Dev Panel / Toolbuilder", "Criar e entregar tools")
	ensureAdminRemoteConnection()
	local tiposTool, toolsDisponiveis = garantirSelecaoToolbuilder()

	local ordem = 0
	local function nextOrder()
		ordem += 1
		return ordem
	end

	createSectionHeader(settingsScroll, "Contexto", nextOrder())
	createAdminAutocompleteInput(
		settingsScroll,
		"Jogador alvo",
		"alvo",
		nextOrder(),
		listarNomesJogadores,
		"Digite para buscar jogador"
	)
	createAdminDropdown(
		settingsScroll,
		"Tipo tool",
		nextOrder(),
		tiposTool,
		adminState.tipoTool,
		function(tipoSelecionado)
			adminState.tipoTool = tipoSelecionado
			local toolsAtualizados = listarToolsPorTipo(tipoSelecionado)
			adminState.tool = toolsAtualizados[1] or ""
			renderToolbuilder()
		end,
		"Selecione um tipo"
	)
	createAdminDropdown(
		settingsScroll,
		"Tool",
		nextOrder(),
		toolsDisponiveis,
		adminState.tool,
		function(toolSelecionada)
			adminState.tool = toolSelecionada
		end,
		"Selecione uma tool"
	)
	createAdminInput(settingsScroll, "Quantidade", "quantidade", nextOrder())
	createAdminInput(settingsScroll, "Distancia", "distancia", nextOrder())

	createSectionHeader(settingsScroll, "Acoes", nextOrder())
	createAdminButton(settingsScroll, "Criar tool na frente do alvo", "CriarToolMundo", nextOrder())
	createAdminButton(settingsScroll, "Dar tool ao alvo", "DarTool", nextOrder())
	createAdminButton(settingsScroll, "Dar tool para mim", "DarTool", nextOrder(), { alvo = player.Name })

	createSectionHeader(settingsScroll, "Status", nextOrder())
	createStatusRow(settingsScroll, nextOrder())
end

function renderClimas()
	telaAtual = "Climas"
	activeCategory = nil
	clearSettings()
	criarNavegacaoPrincipal("Climas")
	configurarAreaConteudo("Dev Panel / Climas", "Ambiente > periodo > clima")
	ensureAdminRemoteConnection()

	local ordem = 0
	local function nextOrder()
		ordem += 1
		return ordem
	end

	local function condicaoPainelExiste(climaId: string): boolean
		for _, condicao in ipairs(CONDICOES_PAINEL) do
			if condicao.id == climaId then
				return true
			end
		end
		return false
	end

	local function sincronizarEstadoPainel()
		if os.clock() < (adminState.bloquearSyncClimasAte or 0) then
			return
		end

		local estadoMundo = ReplicatedStorage:FindFirstChild("EstadoMundo")
		if not estadoMundo then
			return
		end

		local ambienteValor = estadoMundo:FindFirstChild("AmbienteAtual")
		local climaValor = estadoMundo:FindFirstChild("ClimaAtual")
		local horaValor = estadoMundo:FindFirstChild("HoraTexto")
		local faseValor = estadoMundo:FindFirstChild("FaseDia")

		if ambienteValor and ambienteValor:IsA("StringValue") then
			adminState.ambiente = ambienteValor.Value
		end
		if climaValor and climaValor:IsA("StringValue") then
			adminState.clima = climaValor.Value
			adminState.condicao = if condicaoPainelExiste(climaValor.Value)
				then climaValor.Value
				else CatalogoAmbiente.ClimaPadrao
		end
		if horaValor and horaValor:IsA("StringValue") then
			adminState.horario = horaValor.Value
		end
		if faseValor and faseValor:IsA("StringValue") then
			adminState.periodo = faseValor.Value
		end

		local pausadoValor = estadoMundo:FindFirstChild("TempoPausado")
		if pausadoValor and pausadoValor:IsA("BoolValue") then
			adminState.pausado = pausadoValor.Value
		end
	end

	sincronizarEstadoPainel()

	local ambienteSelecionado, climaSelecionado = CatalogoAmbiente.Resolver(adminState.ambiente, adminState.clima)
	local minutosPainel = obterMinutosPainel()
	local fase = ConfiguracaoTempo.ObterFase(minutosPainel)
	adminState.periodo = fase.id

	local function lerEstadoTexto(): string
		local estadoMundo = ReplicatedStorage:FindFirstChild("EstadoMundo")
		if not estadoMundo then
			return "EstadoMundo ainda nao replicado"
		end

		local ambienteValor = estadoMundo:FindFirstChild("AmbienteAtual")
		local climaValor = estadoMundo:FindFirstChild("ClimaAtual")
		local horaValor = estadoMundo:FindFirstChild("HoraTexto")
		local faseValor = estadoMundo:FindFirstChild("FaseDia")
		local ambienteTexto = if ambienteValor and ambienteValor:IsA("StringValue") then ambienteValor.Value else "?"
		local climaTexto = if climaValor and climaValor:IsA("StringValue") then climaValor.Value else "?"
		local horaTexto = if horaValor and horaValor:IsA("StringValue") then horaValor.Value else "?"
		local faseTexto = if faseValor and faseValor:IsA("StringValue") then faseValor.Value else "?"
		local pausadoValor = estadoMundo:FindFirstChild("TempoPausado")
		local pausadoTexto = if pausadoValor
				and pausadoValor:IsA("BoolValue")
				and pausadoValor.Value
			then " [PAUSADO]"
			else ""
		return ambienteTexto .. " / " .. climaTexto .. " - " .. horaTexto .. " (" .. faseTexto .. ")" .. pausadoTexto
	end

	createSectionHeader(settingsScroll, "Estado", nextOrder())
	createStringControl(settingsScroll, "Mundo", lerEstadoTexto(), nextOrder())
	createStringControl(
		settingsScroll,
		"Selecao",
		ambienteSelecionado.nome
			.. " / "
			.. climaSelecionado.nome
			.. " - "
			.. ConfiguracaoTempo.FormatarHora(minutosPainel)
			.. " ("
			.. fase.nome
			.. ")",
		nextOrder()
	)

	createSectionHeader(settingsScroll, "Ajustes", nextOrder())
	createAdminInput(settingsScroll, "Transicao", "transicao", nextOrder())

	createSectionHeader(settingsScroll, "Ambientes", nextOrder())
	local tilesAmbientes = {}
	for _, item in ipairs(AMBIENTES_PAINEL) do
		local _, chaveAmbiente = CatalogoAmbiente.ObterAmbiente(item.id)
		table.insert(tilesAmbientes, {
			titulo = item.nome,
			subtitulo = item.subtitulo,
			emoji = item.emoji,
			ativo = chaveAmbiente == adminState.ambiente,
			onClick = function()
				selecionarAmbiente(item.id)
				aplicarAmbienteNoMundo()
				renderClimas()
			end,
		})
	end
	createTileGrid(settingsScroll, nextOrder(), tilesAmbientes, 5, 98)

	createSectionHeader(settingsScroll, "Periodo", nextOrder())
	local tilesPeriodos = {}
	for _, item in ipairs(PERIODOS_PAINEL) do
		table.insert(tilesPeriodos, {
			titulo = item.nome,
			subtitulo = item.horario,
			emoji = item.emoji,
			ativo = item.id == adminState.periodo,
			onClick = function()
				adminState.periodo = item.id
				adminState.horario = item.horario
				definirHorarioMundo()
				renderClimas()
			end,
		})
	end
	createTileGrid(settingsScroll, nextOrder(), tilesPeriodos, 4, 104)

	createSectionHeader(settingsScroll, "Clima", nextOrder())
	local tilesCondicoes = {}
	for _, item in ipairs(CONDICOES_PAINEL) do
		local clima, chaveClima = CatalogoAmbiente.ObterClima(adminState.ambiente, item.id)
		table.insert(tilesCondicoes, {
			titulo = item.nome,
			subtitulo = clima.nome,
			emoji = item.emoji,
			ativo = chaveClima == adminState.clima,
			onClick = function()
				selecionarClima(item.id)
				aplicarAmbienteNoMundo()
				renderClimas()
			end,
		})
	end
	createTileGrid(settingsScroll, nextOrder(), tilesCondicoes, 4, 104)

	createSectionHeader(settingsScroll, "Acoes", nextOrder())
	local estaPausado = adminState.pausado == true
	createTileGrid(settingsScroll, nextOrder(), {
		{
			titulo = if estaPausado then "Retomar" else "Pausar",
			subtitulo = if estaPausado then "tempo/clima" else "para editar",
			emoji = if estaPausado then "▶️" else "⏸️",
			ativo = estaPausado,
			onClick = function()
				local novoPausado = not estaPausado
				adminState.pausado = novoPausado
				adminState.bloquearSyncClimasAte = os.clock() + 0.8
				fireAdminAction("PausarMundo", { pausado = novoPausado })
				renderClimas()
			end,
		},
		{
			titulo = "Aplicar",
			subtitulo = "mundo",
			emoji = "✅",
			onClick = aplicarAmbienteNoMundo,
		},
		{
			titulo = "Preview",
			subtitulo = "local",
			emoji = "👁️",
			onClick = aplicarPreviewAmbiente,
		},
		{
			titulo = "+1 Hora",
			subtitulo = "tempo",
			emoji = "⏩",
			onClick = function()
				avancarTempoMundo(60)
				renderClimas()
			end,
		},
		{
			titulo = "Padrao",
			subtitulo = "DiaLimpo",
			emoji = "🌅",
			onClick = function()
				selecionarAmbiente(CatalogoAmbiente.AmbientePadrao)
				selecionarClima(CatalogoAmbiente.ClimaPadrao)
				adminState.horario = ConfiguracaoTempo.FormatarHora(ConfiguracaoTempo.HorarioInicialMinutos)
				adminState.periodo = ConfiguracaoTempo.ObterFase(ConfiguracaoTempo.HorarioInicialMinutos).id
				definirHorarioMundo()
				aplicarAmbienteNoMundo()
				renderClimas()
			end,
		},
	}, 4, 104)

	createSectionHeader(settingsScroll, "Extrair Templates", nextOrder())
	createTileGrid(settingsScroll, nextOrder(), {
		{
			titulo = "Extrair Clima",
			subtitulo = "console",
			emoji = "📋",
			onClick = extrairClimaAtual,
		},
		{
			titulo = "Extrair Ambiente",
			subtitulo = "console",
			emoji = "📋",
			onClick = extrairAmbienteAtual,
		},
	}, 4, 104)

	createSectionHeader(settingsScroll, "Status", nextOrder())
	createStatusRow(settingsScroll, nextOrder())
end

function renderJogadorMundo()
	telaAtual = "Jogador / Mundo"
	activeCategory = nil
	clearSettings()
	criarNavegacaoPrincipal("Jogador / Mundo")
	configurarAreaConteudo("Dev Panel / Jogador e Mundo", "Acoes rapidas")
	ensureAdminRemoteConnection()

	local ordem = 0
	local function nextOrder()
		ordem += 1
		return ordem
	end

	createSectionHeader(settingsScroll, "Contexto", nextOrder())
	createAdminInput(settingsScroll, "Jogador alvo", "alvo", nextOrder())

	createSectionHeader(settingsScroll, "Jogador", nextOrder())
	createAdminButton(settingsScroll, "Curar alvo", "CurarAlvo", nextOrder())
	createAdminButton(settingsScroll, "Respawn alvo", "RespawnAlvo", nextOrder())
	createAdminButton(settingsScroll, "Ir ate alvo", "IrAteAlvo", nextOrder())
	createAdminButton(settingsScroll, "Trazer alvo", "TrazerAlvo", nextOrder())
	createAdminButton(settingsScroll, "Congelar alvo", "CongelarAlvo", nextOrder())
	createAdminButton(settingsScroll, "Descongelar alvo", "DescongelarAlvo", nextOrder())

	createSectionHeader(settingsScroll, "Mundo", nextOrder())
	createAdminButton(settingsScroll, "Limpar tools soltas", "LimparToolsSoltas", nextOrder())
end

-- =============================================================================
-- Tela: NPCs (spawn rapido pelo Dev). Usa o RemoteEvent dedicado
-- ReplicatedStorage/NPC/Remotos/SpawnNPCDev. O painel apenas envia opcoes;
-- o servidor decide posicao (a frente do jogador) e cria o NPC.
-- =============================================================================

-- Capacidades aplicadas ao proximo Combate Hostil que for spawnado.
-- Persistem enquanto o painel estiver vivo (sao recriadas em cada renderNPCs).
local capacidadesNPC = {
	podeAndar = true,
	podeAtacar = true,
	podeDefender = false,
	podeParry = false,
}

local DEBUG = false
local function dbg(...)
	if DEBUG then
		print(...)
	end
end

local function obterRemoteNPC(nome: string): RemoteEvent?
	local raiz = ReplicatedStorage:WaitForChild("NPC", 2)
	local pasta = raiz and raiz:WaitForChild("Remotos", 2)
	local remoto = pasta and pasta:WaitForChild(nome, 2)
	if remoto and remoto:IsA("RemoteEvent") then
		return remoto :: RemoteEvent
	end
	return nil
end

local function dispararSpawnNPC(payload: { [string]: any })
	local remoto = obterRemoteNPC("SpawnNPCDev")
	if not remoto then
		warn("[DevPanel] RemoteEvent SpawnNPCDev nao encontrado em ReplicatedStorage.NPC.Remotos")
		return
	end
	remoto:FireServer(payload)
end

local function dispararSpawnCombate(hostil: boolean)
	local payload: { [string]: any } = {
		archetype = "Combate",
		hostil = hostil,
		podeAndar = capacidadesNPC.podeAndar,
		podeAtacar = capacidadesNPC.podeAtacar,
		podeDefender = capacidadesNPC.podeDefender,
		podeParry = capacidadesNPC.podeParry,
	}
	dispararSpawnNPC(payload)
end

-- Aplica as capacidades atuais em todos os NPCs hostis ja spawnados (real-time).
local function dispararAtualizarFlags()
	local remoto = obterRemoteNPC("AtualizarFlagsNPCDev")
	if not remoto then
		warn("[DevPanel] RemoteEvent AtualizarFlagsNPCDev nao encontrado")
		return
	end
	dbg("[DevPanel] Disparando atualizacao de flags em tempo real para os NPCs")
	remoto:FireServer({
		podeAndar = capacidadesNPC.podeAndar,
		podeAtacar = capacidadesNPC.podeAtacar,
		podeDefender = capacidadesNPC.podeDefender,
		podeParry = capacidadesNPC.podeParry,
	})
end

local function dispararDespawnTodos()
	dbg("[DevPanel] Botao Despawn clicado, buscando remote...")
	local remoto = obterRemoteNPC("DespawnNPCDev")
	if not remoto then
		warn("[DevPanel] RemoteEvent DespawnNPCDev nao encontrado")
		return
	end
	dbg("[DevPanel] Remote DespawnNPCDev encontrado, enviando pedido FireServer({ todos = true })")
	remoto:FireServer({ todos = true })
end

function renderNPCs()
	telaAtual = "NPCs"
	activeCategory = nil
	clearSettings()
	criarNavegacaoPrincipal("NPCs")
	configurarAreaConteudo("Dev Panel / NPCs", "Spawn a frente do jogador")

	local ordem = 0
	local function nextOrder()
		ordem += 1
		return ordem
	end

	createSectionHeader(settingsScroll, "Capacidades (aplicadas em tempo real aos NPCs hostis)", nextOrder())
	createBooleanControl(settingsScroll, "Pode andar", capacidadesNPC.podeAndar, nextOrder(), function(v)
		capacidadesNPC.podeAndar = v
		dispararAtualizarFlags()
	end)
	createBooleanControl(settingsScroll, "Pode atacar", capacidadesNPC.podeAtacar, nextOrder(), function(v)
		capacidadesNPC.podeAtacar = v
		dispararAtualizarFlags()
	end)
	createBooleanControl(settingsScroll, "Pode defender", capacidadesNPC.podeDefender, nextOrder(), function(v)
		capacidadesNPC.podeDefender = v
		-- Parry exige defender ativo.
		if not v then
			capacidadesNPC.podeParry = false
		end
		dispararAtualizarFlags()
	end)
	createBooleanControl(settingsScroll, "Pode dar parry", capacidadesNPC.podeParry, nextOrder(), function(v)
		capacidadesNPC.podeParry = v and capacidadesNPC.podeDefender
		dispararAtualizarFlags()
	end)

	createSectionHeader(settingsScroll, "Humanoides", nextOrder())
	createTileGrid(settingsScroll, nextOrder(), {
		{
			titulo = "Dialogo",
			subtitulo = "idle + head track",
			emoji = "💬",
			onClick = function()
				dispararSpawnNPC({ archetype = "Dialogo" })
			end,
		},
		{
			titulo = "Combate",
			subtitulo = "hostil",
			emoji = "⚔️",
			onClick = function()
				dispararSpawnCombate(true)
			end,
		},
	}, 3, 110)

	createSectionHeader(settingsScroll, "Animais", nextOrder())
	createTileGrid(settingsScroll, nextOrder(), {
		{
			titulo = "Galinha",
			subtitulo = "vagar/fugir",
			emoji = "🐔",
			onClick = function()
				dispararSpawnNPC({ archetype = "Animal", especie = "Galinha" })
			end,
		},
		{
			titulo = "Ovelha",
			subtitulo = "vagar/fugir",
			emoji = "🐑",
			onClick = function()
				dispararSpawnNPC({ archetype = "Animal", especie = "Ovelha" })
			end,
		},
		{
			titulo = "Vaca",
			subtitulo = "vagar/fugir",
			emoji = "🐄",
			onClick = function()
				dispararSpawnNPC({ archetype = "Animal", especie = "Vaca" })
			end,
		},
	}, 3, 110)

	createSectionHeader(settingsScroll, "Limpeza", nextOrder())
	createTileGrid(settingsScroll, nextOrder(), {
		{
			titulo = "Despawn",
			subtitulo = "todos",
			emoji = "🗑️",
			onClick = dispararDespawnTodos,
		},
	}, 3, 110)
end

-- =============================================================================
-- Tela: Status do Jogador (Entidade)
-- Mostra atributos vitais (Vida, Fome, Sede, Energia, ...), estado de movimento,
-- estado de combate e configuracoes derivadas. Atualiza ~10x/s via Heartbeat.
-- Todas as conexoes usam trackConn() para serem limpas em clearSettings().
-- =============================================================================

local STATUS_INTERVALO_ATUALIZACAO = 0.1 -- segundos

local function criarLinhaInfo(parent: Instance, layoutOrder: number, rotulo: string): TextLabel
	local row = Instance.new("Frame")
	row.Name = "Info_" .. rotulo
	row.Size = UDim2.new(1, 0, 0, 26)
	row.BackgroundColor3 = COLORS.row
	row.BackgroundTransparency = 0.4
	row.BorderSizePixel = 0
	row.LayoutOrder = layoutOrder
	row.Parent = parent
	addCorner(row, UDim.new(0, 4))

	local lbl = Instance.new("TextLabel")
	lbl.Name = "Rotulo"
	lbl.Size = UDim2.new(0.45, -8, 1, 0)
	lbl.Position = UDim2.fromOffset(8, 0)
	lbl.BackgroundTransparency = 1
	lbl.Font = FONT_LABEL
	lbl.TextSize = 12
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextColor3 = COLORS.textDim
	lbl.Text = rotulo
	lbl.Parent = row

	local val = Instance.new("TextLabel")
	val.Name = "Valor"
	val.Size = UDim2.new(0.55, -8, 1, 0)
	val.Position = UDim2.fromScale(0.45, 0)
	val.BackgroundTransparency = 1
	val.Font = FONT_VALUE
	val.TextSize = 12
	val.TextXAlignment = Enum.TextXAlignment.Right
	val.TextColor3 = COLORS.text
	val.Text = "-"
	val.Parent = row

	return val
end

type LinhaAtributoUI = {
	frame: Frame,
	valor: TextLabel,
	preenchimento: Frame,
}

local function criarLinhaAtributo(parent: Instance, layoutOrder: number, atributo): LinhaAtributoUI
	local row = Instance.new("Frame")
	row.Name = "Atrib_" .. atributo.id
	row.Size = UDim2.new(1, 0, 0, 38)
	row.BackgroundColor3 = COLORS.row
	row.BackgroundTransparency = 0.3
	row.BorderSizePixel = 0
	row.LayoutOrder = layoutOrder
	row.Parent = parent
	addCorner(row, UDim.new(0, 4))

	local rotulo = Instance.new("TextLabel")
	rotulo.Name = "Nome"
	rotulo.Size = UDim2.new(0.5, -8, 0, 16)
	rotulo.Position = UDim2.fromOffset(8, 2)
	rotulo.BackgroundTransparency = 1
	rotulo.Font = FONT_LABEL
	rotulo.TextSize = 12
	rotulo.TextXAlignment = Enum.TextXAlignment.Left
	rotulo.TextColor3 = COLORS.text
	rotulo.Text = atributo.nome
	rotulo.Parent = row

	local valor = Instance.new("TextLabel")
	valor.Name = "Valor"
	valor.Size = UDim2.new(0.5, -8, 0, 16)
	valor.Position = UDim2.new(0.5, 0, 0, 2)
	valor.BackgroundTransparency = 1
	valor.Font = FONT_VALUE
	valor.TextSize = 12
	valor.TextXAlignment = Enum.TextXAlignment.Right
	valor.TextColor3 = COLORS.textDim
	valor.Text = "-"
	valor.Parent = row

	local barraFundo = Instance.new("Frame")
	barraFundo.Name = "BarraFundo"
	barraFundo.Size = UDim2.new(1, -16, 0, 8)
	barraFundo.Position = UDim2.fromOffset(8, 22)
	barraFundo.BackgroundColor3 = COLORS.input
	barraFundo.BorderSizePixel = 0
	barraFundo.Parent = row
	addCorner(barraFundo, UDim.new(0, 3))

	local preenchimento = Instance.new("Frame")
	preenchimento.Name = "Preenchimento"
	preenchimento.Size = UDim2.fromScale(0, 1)
	preenchimento.BackgroundColor3 = atributo.cor
	preenchimento.BorderSizePixel = 0
	preenchimento.Parent = barraFundo
	addCorner(preenchimento, UDim.new(0, 3))

	return { frame = row, valor = valor, preenchimento = preenchimento }
end

local function formatarValorAtributo(atributo, valor: number): string
	if atributo.formato == "porcentagem" then
		return string.format("%.0f / %.0f", valor, atributo.max)
	end
	-- numero (idade, temperatura, ...)
	if math.abs(valor - math.floor(valor)) < 0.01 then
		return string.format("%.0f", valor)
	end
	return string.format("%.1f", valor)
end

function renderStatusJogador()
	telaAtual = "Status"
	activeCategory = nil
	clearSettings()
	criarNavegacaoPrincipal("Status")
	configurarAreaConteudo("Dev Panel / Status do Jogador", "Tempo real")

	local ordem = 0
	local function nextOrder()
		ordem += 1
		return ordem
	end

	-- ========== Cabecalho: Especie ==========
	createSectionHeader(settingsScroll, "Entidade", nextOrder())
	local lblEspecie = criarLinhaInfo(settingsScroll, nextOrder(), "Especie")
	local lblViva = criarLinhaInfo(settingsScroll, nextOrder(), "Viva?")

	-- ========== Atributos da entidade (dinamico) ==========
	createSectionHeader(settingsScroll, "Atributos", nextOrder())
	local atributosCabecalho = nextOrder()
	local atributosContainer = Instance.new("Frame")
	atributosContainer.Name = "AtributosContainer"
	atributosContainer.Size = UDim2.fromScale(1, 0)
	atributosContainer.AutomaticSize = Enum.AutomaticSize.Y
	atributosContainer.BackgroundTransparency = 1
	atributosContainer.BorderSizePixel = 0
	atributosContainer.LayoutOrder = atributosCabecalho
	atributosContainer.Parent = settingsScroll

	local atributosLayout = Instance.new("UIListLayout")
	atributosLayout.Padding = UDim.new(0, 4)
	atributosLayout.SortOrder = Enum.SortOrder.LayoutOrder
	atributosLayout.Parent = atributosContainer

	local linhasAtributos: { [string]: LinhaAtributoUI } = {}
	local atributosRenderizadosPara: Model? = nil

	local function reconstruirAtributos(charModel: Model?)
		atributosRenderizadosPara = charModel
		for _, ui in linhasAtributos do
			ui.frame:Destroy()
		end
		table.clear(linhasAtributos)
		if not charModel then
			return
		end
		local lista = LeitorEntidade.ListarAtributos(charModel)
		for i, attr in lista do
			linhasAtributos[attr.id] = criarLinhaAtributo(atributosContainer, i, attr)
		end
	end

	-- ========== Movimento ==========
	createSectionHeader(settingsScroll, "Movimento", nextOrder())
	local lblWalkSpeed = criarLinhaInfo(settingsScroll, nextOrder(), "WalkSpeed (atual)")
	local lblWalkSpeedConfig = criarLinhaInfo(settingsScroll, nextOrder(), "Andar / Correr (config)")
	local lblAceleracao = criarLinhaInfo(settingsScroll, nextOrder(), "Aceleracao (and/cor)")
	local lblJumpHeight = criarLinhaInfo(settingsScroll, nextOrder(), "JumpHeight")
	local lblVelocidadeAtual = criarLinhaInfo(settingsScroll, nextOrder(), "Velocidade XZ")
	local lblFloorMaterial = criarLinhaInfo(settingsScroll, nextOrder(), "Solo / No ar")

	-- ========== Estado ==========
	createSectionHeader(settingsScroll, "Estado", nextOrder())
	local lblEstadoMov = criarLinhaInfo(settingsScroll, nextOrder(), "Estado movimento")
	local lblModoAnim = criarLinhaInfo(settingsScroll, nextOrder(), "Modo animacao")
	local lblShiftLock = criarLinhaInfo(settingsScroll, nextOrder(), "ShiftLock")
	local lblAgachado = criarLinhaInfo(settingsScroll, nextOrder(), "Agachado")
	local lblCorrendo = criarLinhaInfo(settingsScroll, nextOrder(), "Correndo")

	-- Helpers de leitura.
	local function lerStatusLocal(char: Model?, nome: string)
		if not char then
			return nil
		end
		local pasta = char:FindFirstChild("StatusLocal")
		if not pasta then
			return nil
		end
		local valor = pasta:FindFirstChild(nome)
		if valor and (valor:IsA("StringValue") or valor:IsA("BoolValue") or valor:IsA("NumberValue")) then
			return (valor :: any).Value
		end
		return nil
	end

	local function texto(valor: any): string
		if valor == nil then
			return "-"
		end
		if typeof(valor) == "boolean" then
			return if valor then "Sim" else "Nao"
		end
		return tostring(valor)
	end

	-- Re-renderiza a lista de atributos quando o personagem trocar (respawn).
	trackConn(player.CharacterAdded:Connect(function(_)
		if telaAtual == "Status" then
			task.defer(function()
				if telaAtual == "Status" then
					renderStatusJogador()
				end
			end)
		end
	end))

	-- Atualizacao periodica.
	local acumulador = 0
	trackConn(RunService.Heartbeat:Connect(function(dt)
		acumulador += dt
		if acumulador < STATUS_INTERVALO_ATUALIZACAO then
			return
		end
		acumulador = 0

		local char = player.Character
		local humanoid = if char then char:FindFirstChildOfClass("Humanoid") :: Humanoid? else nil
		local hrp = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil

		-- Entidade.
		local especie = LeitorEntidade.ObterEspecie(char)
		lblEspecie.Text = if especie then especie.nome else "-"
		local vida = LeitorEntidade.ObterAtributo(char, "Vida")
		if vida ~= nil then
			lblViva.Text = if vida > 0 then "Viva" else "Morta"
			lblViva.TextColor3 = if vida > 0 then Color3.fromRGB(120, 220, 140) else Color3.fromRGB(220, 100, 100)
		else
			lblViva.Text = "-"
			lblViva.TextColor3 = COLORS.text
		end

		-- Atributos: reconstruir se mudou de char.
		if char ~= atributosRenderizadosPara then
			reconstruirAtributos(char)
		end
		if char then
			local lista = LeitorEntidade.ListarAtributos(char)
			for _, attr in lista do
				local ui = linhasAtributos[attr.id]
				if not ui then
					continue
				end
				ui.valor.Text = formatarValorAtributo(attr, attr.valor)
				local fracao = 0
				if attr.max > attr.min then
					fracao = math.clamp((attr.valor - attr.min) / (attr.max - attr.min), 0, 1)
				end
				ui.preenchimento.Size = UDim2.fromScale(fracao, 1)
			end
		end

		-- Movimento.
		if humanoid then
			lblWalkSpeed.Text = string.format("%.1f", humanoid.WalkSpeed)
			lblJumpHeight.Text = string.format("%.1f", humanoid.JumpHeight)
			lblFloorMaterial.Text = if humanoid.FloorMaterial == Enum.Material.Air
				then "No ar"
				else "Solo (" .. tostring(humanoid.FloorMaterial.Name) .. ")"
		else
			lblWalkSpeed.Text = "-"
			lblJumpHeight.Text = "-"
			lblFloorMaterial.Text = "-"
		end

		local velAndar = ModConfCombate.ObterConfiguracao("VelocidadeAndando") or 0
		local velCorrer = ModConfCombate.ObterConfiguracao("VelocidadeCorrendo") or 0
		lblWalkSpeedConfig.Text = string.format("%.1f / %.1f", velAndar, velCorrer)

		local acelAndar = ModConfCombate.ObterConfiguracao("AceleracaoAndando") or 0
		local acelCorrer = ModConfCombate.ObterConfiguracao("AceleracaoCorrendo") or 0
		lblAceleracao.Text = string.format("%.1f / %.1f", acelAndar, acelCorrer)

		if hrp then
			local v = hrp.AssemblyLinearVelocity
			local vXZ = math.sqrt(v.X * v.X + v.Z * v.Z)
			lblVelocidadeAtual.Text = string.format("%.2f studs/s", vXZ)
		else
			lblVelocidadeAtual.Text = "-"
		end

		-- Estado (lido do StatusLocal replicado).
		lblEstadoMov.Text = texto(lerStatusLocal(char, "estadoMov"))
		lblModoAnim.Text = texto(lerStatusLocal(char, "modoAnimacao"))
		lblShiftLock.Text = texto(lerStatusLocal(char, "ShiftLockOn"))
		lblAgachado.Text = texto(lerStatusLocal(char, "AgachadoOn"))
		lblCorrendo.Text = texto(lerStatusLocal(char, "CorrendoOn"))
	end))

	-- Render inicial.
	reconstruirAtributos(player.Character)

	settingsScroll.CanvasPosition = Vector2.zero
end

table.insert(
	connections,
	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		if telaAtual == "Configuracoes" and activeCategory then
			renderCategory(activeCategory, searchBox.Text)
		end
	end)
)

table.insert(
	connections,
	resetBtn.MouseButton1Click:Connect(function()
		if telaAtual ~= "Configuracoes" then
			return
		end
		if not activeCategory then
			return
		end
		if activeCategory.tipo == "AcoesAdmin" then
			return
		end
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
	end)
)

table.insert(
	connections,
	closeBtn.MouseButton1Click:Connect(function()
		isOpen = false
		screenGui.Enabled = false
	end)
)

table.insert(
	connections,
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode ~= TOGGLE_KEY then
			return
		end

		if UserInputService:GetFocusedTextBox() then
			return
		end

		isOpen = not isOpen
		screenGui.Enabled = isOpen

		if isOpen then
			renderInicio()
		end
	end)
)

table.insert(
	connections,
	screenGui.Destroying:Connect(function()
		clearControlConnections()
		clearLeftConnections()
		for _, conn in connections do
			conn:Disconnect()
		end
		table.clear(connections)
	end)
)
