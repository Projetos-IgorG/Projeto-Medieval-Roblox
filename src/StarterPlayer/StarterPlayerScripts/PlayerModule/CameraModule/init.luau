--!strict
--[[
	CameraModule - This ModuleScript implements a singleton class to manage the
	selection, activation, and deactivation of the current camera controller,
	character occlusion controller, and transparency controller. This script binds to
	RenderStepped at Camera priority and calls the Update() methods on the active
	controller instances.

	The camera controller ModuleScripts implement classes which are instantiated and
	activated as-needed, they are no longer all instantiated up front as they were in
	the previous generation of PlayerScripts.

	2018 PlayerScripts Update - AllYourBlox
--]]

local CameraModule = {}
CameraModule.__index = CameraModule

-- NOTICE: Player property names do not all match their StarterPlayer equivalents,
-- with the differences noted in the comments on the right
local PLAYER_CAMERA_PROPERTIES = {
	"CameraMinZoomDistance",
	"CameraMaxZoomDistance",
	"CameraMode",
	"DevCameraOcclusionMode",
	"DevComputerCameraMode", -- Corresponds to StarterPlayer.DevComputerCameraMovementMode
	"DevTouchCameraMode", -- Corresponds to StarterPlayer.DevTouchCameraMovementMode

	-- Character movement mode
	"DevComputerMovementMode",
	"DevTouchMovementMode",
	"DevEnableMouseLock", -- Corresponds to StarterPlayer.EnableMouseLockOption
}

local USER_GAME_SETTINGS_PROPERTIES = {
	"ComputerCameraMovementMode",
	"ComputerMovementMode",
	"ControlMode",
	"GamepadCameraSensitivity",
	"MouseSensitivity",
	"RotationType",
	"TouchCameraMovementMode",
	"TouchMovementMode",
}

--[[ Roblox Services ]]
--
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VRService = game:GetService("VRService")
local UserGameSettings = UserSettings():GetService("UserGameSettings")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CommonUtils = script.Parent:WaitForChild("CommonUtils")
local ConnectionUtil = require(CommonUtils:WaitForChild("ConnectionUtil"))
local FlagUtil = require(CommonUtils:WaitForChild("FlagUtil"))

-- Static camera utils
local CameraUtils = require(script:WaitForChild("CameraUtils"))
local CameraInput = require(script:WaitForChild("CameraInput"))

-- Load Roblox Camera Controller Modules
local ClassicCamera = require(script:WaitForChild("ClassicCamera"))
local OrbitalCamera = require(script:WaitForChild("OrbitalCamera"))
local LegacyCamera = require(script:WaitForChild("LegacyCamera"))
local VehicleCamera = require(script:WaitForChild("VehicleCamera"))
-- New VR System Modules
local VRCamera = require(script:WaitForChild("VRCamera"))
local VRVehicleCamera = require(script:WaitForChild("VRVehicleCamera"))

-- Load Roblox Occlusion Modules
local Invisicam = require(script:WaitForChild("Invisicam"))
local Poppercam = require(script:WaitForChild("Poppercam"))

-- Load the near-field character transparency controller and the mouse lock "shift lock" controller
local TransparencyController = require(script:WaitForChild("TransparencyController"))
local MouseLockController = require(script:WaitForChild("MouseLockController"))
local DynamicCamFX = require(script:WaitForChild("DynamicCamFX"))
local ZoomController = require(script:WaitForChild("ZoomController"))

-- Carrega configurações centralizadas do jogador
local ConfigJogador = require(
	ReplicatedStorage:WaitForChild("Jogador"):WaitForChild("Camera"):WaitForChild("Configuracoes"):WaitForChild("ConfigCamera")
)

-- ClientBridge para acessar estados client-side (dash, etc.)
local ClientBridge =
	require(ReplicatedStorage:WaitForChild("Jogador"):WaitForChild("ComunicacaoCliente"):WaitForChild("PonteCliente"))

-- Configurações de combate (para DashCameraFixarY)
local Modulo_Configuracoes = require(
	ReplicatedStorage:WaitForChild("Combate"):WaitForChild("Configuracoes"):WaitForChild("ConfigCombate")
)

-- Estado de Y fixo durante dash (offset relativo ao HRP)
local dashCamState = {
	ativo = false,
	offsetY = nil :: number?,
}

-- Table of camera controllers that have been instantiated. They are instantiated as they are used.
local instantiatedCameraControllers = {}
local instantiatedOcclusionModules = {}

-- ============================================================================
-- SISTEMA DE FOV DINÂMICO
-- ============================================================================

local fovState = {
	runRampProgress = 0, -- 0..1, quanto tempo correndo (para ramp gradual do FOV)
}

-- Define o FOV padrão na câmera assim que o módulo carrega
do
	local cam = workspace.CurrentCamera
	if cam then
		cam.FieldOfView = ConfigJogador.ObterConfiguracao("DefaultFOV") or 78
	end
end

-- Cache de referências de StatusLocal (evita FindFirstChild a cada frame)
local cachedEstadoMov: StringValue? = nil
local cachedShiftLockBool: BoolValue? = nil
local lastShiftLockSet: boolean? = nil

local function getCachedEstadoMov(): string
	local val = cachedEstadoMov
	if val and val.Parent then
		return val.Value
	end
	local character = Players.LocalPlayer.Character
	if not character then return "Parado" end
	local statusLocal = character:FindFirstChild("StatusLocal")
	if not statusLocal then return "Parado" end
	local estadoVal = statusLocal:FindFirstChild("estadoMov")
	if estadoVal and estadoVal:IsA("StringValue") then
		cachedEstadoMov = estadoVal :: StringValue
		return estadoVal.Value
	end
	return "Parado"
end

-- Atualiza o FOV suavemente a cada frame (sem tweens, lerp contínuo)
local function updateFOV(camera: Camera, dt: number, emPrimeiraPessoa: boolean)
	local estadoMov = getCachedEstadoMov()

	local isRunning = (estadoMov == "Correndo")
	local isMoving = (estadoMov == "Andando") or isRunning

	-- Ramp gradual de corrida: incrementa/decrementa progresso
	local rampTime = ConfigJogador.ObterConfiguracao("RunFOVRampTime") or 0.8
	if isRunning then
		fovState.runRampProgress = math.min(fovState.runRampProgress + dt / rampTime, 1)
	else
		fovState.runRampProgress = math.max(fovState.runRampProgress - dt / rampTime, 0)
	end

	-- Calcula FOV alvo baseado se está em 1ª ou 3ª pessoa
	local targetFOV: number
	if emPrimeiraPessoa then
		local baseFOV = ConfigJogador.ObterConfiguracao("FOVPrimeiraPessoa") or 90
		local runFOV = ConfigJogador.ObterConfiguracao("FOVCorrendoPrimeiraPessoa") or 110
		if not isMoving and fovState.runRampProgress <= 0 then
			targetFOV = baseFOV
		else
			targetFOV = baseFOV + (runFOV - baseFOV) * fovState.runRampProgress
		end
	else
		local defaultFOV = ConfigJogador.ObterConfiguracao("DefaultFOV") or 78
		local walkFOV = ConfigJogador.ObterConfiguracao("WalkFOV") or 78
		local runFOV = ConfigJogador.ObterConfiguracao("RunFOV") or 86
		if not isMoving and fovState.runRampProgress <= 0 then
			targetFOV = defaultFOV
		else
			targetFOV = walkFOV + (runFOV - walkFOV) * fovState.runRampProgress
		end
	end

	-- Lerp suave contínuo (sem tweens)
	local transitionSpeed = ConfigJogador.ObterConfiguracao("FOVTransitionTime") or 0.3
	local lerpRate = math.clamp(dt / transitionSpeed, 0, 1)
	camera.FieldOfView = camera.FieldOfView + (targetFOV - camera.FieldOfView) * lerpRate
end

local zoomState = {
	currentTween = nil :: Tween?,
}

-- ============================================================================
-- SISTEMA DE PRIMEIRA PESSOA (TOGGLE V)
-- ============================================================================

local primeiraPessoaState = {
	ativo = false,
	transicaoAtiva = false,
	zoomAnterior = 10, -- zoom para restaurar ao sair (será o min zoom)
	shiftLockAntesDePrimeiraPessoa = false, -- estado do ShiftLock antes de entrar em 1ª pessoa
	cursorDesbloqueado = false, -- cursor livre (B toggle) em 1ª pessoa
}

-- ============================================================================
-- SISTEMA DE SINCRONIZAÇÃO DO STATUS SHIFTLOCKON
-- ============================================================================

local function updateShiftLockStatus(isLocked: boolean)
	-- Skip se o valor não mudou (evita write + FindFirstChild desnecessários)
	if isLocked == lastShiftLockSet then return end

	local boolVal = cachedShiftLockBool
	if not boolVal or not boolVal.Parent then
		local character = Players.LocalPlayer.Character
		if not character then return end
		local statusLocal = character:FindFirstChild("StatusLocal")
		if not statusLocal then return end
		local found = statusLocal:FindFirstChild("ShiftLockOn")
		if not found or not found:IsA("BoolValue") then return end
		boolVal = found :: BoolValue
		cachedShiftLockBool = boolVal
	end

	local resolvedBoolVal = boolVal :: BoolValue
	resolvedBoolVal.Value = isLocked
	lastShiftLockSet = isLocked
end

local function checkFirstPersonAndUpdateStatus(activeCameraController: any, activeMouseLockController: any)
	if not activeCameraController then
		return
	end

	local isInFirstPerson = primeiraPessoaState.ativo
	local isMouseLocked = activeMouseLockController
		and activeMouseLockController.GetIsMouseLocked
		and activeMouseLockController:GetIsMouseLocked()

	local shouldBeShiftLocked = isInFirstPerson or (isMouseLocked == true)
	updateShiftLockStatus(shouldBeShiftLocked)
end

local function updateZoomLimits(player: Player, isMouseLocked: boolean)
	local zoomRange = if isMouseLocked
		then ConfigJogador.ObterConfiguracao("ZoomRangeOn")
		else ConfigJogador.ObterConfiguracao("ZoomRangeOff")

	if zoomRange then
		if zoomState.currentTween then
			zoomState.currentTween:Cancel()
		end

		local tweenInfo = ConfigJogador.ObterTweenInfo()
		local tween = TweenService:Create(player, tweenInfo, {
			CameraMinZoomDistance = zoomRange.Min,
			CameraMaxZoomDistance = zoomRange.Max,
		})

		zoomState.currentTween = tween
		tween:Play()
	end
end

-- ============================================================================
-- FUNÇÕES DE ENTRADA/SAÍDA DE PRIMEIRA PESSOA
-- ============================================================================

local function entrarPrimeiraPessoa(cameraModule: any)
	if primeiraPessoaState.ativo or primeiraPessoaState.transicaoAtiva then
		return
	end

	local controller = cameraModule.activeCameraController
	local mouseController = cameraModule.activeMouseLockController
	if not controller then
		return
	end

	-- Salva estado anterior do ShiftLock
	primeiraPessoaState.shiftLockAntesDePrimeiraPessoa = mouseController
		and mouseController.GetIsMouseLocked
		and mouseController:GetIsMouseLocked() or false

	-- Salva zoom anterior
	if controller.GetCameraToSubjectDistance then
		primeiraPessoaState.zoomAnterior = controller:GetCameraToSubjectDistance()
	end

	primeiraPessoaState.ativo = true
	primeiraPessoaState.transicaoAtiva = true

	-- Ativa ShiftLock (necessário para combate e outros sistemas)
	if mouseController and mouseController.SetIsMouseLocked then
		mouseController:SetIsMouseLocked(true)
	elseif controller.SetIsMouseLocked then
		controller:SetIsMouseLocked(true)
	end
	if controller.EnterFirstPerson then
		controller:EnterFirstPerson()
	end

	-- Seta a primeira pessoa no controller para ele saber posicionar na cabeça
	if controller.SetPrimeiraPessoa then
		controller:SetPrimeiraPessoa(true)
	end

	-- Transição suave
	local tempo = ConfigJogador.ObterConfiguracao("TransicaoPrimeiraPessoaTempo") or 0.4
	task.delay(tempo, function()
		primeiraPessoaState.transicaoAtiva = false
	end)
end

local function sairPrimeiraPessoa(cameraModule: any)
	if not primeiraPessoaState.ativo then
		return
	end

	local controller = cameraModule.activeCameraController
	local mouseController = cameraModule.activeMouseLockController
	if not controller then
		return
	end

	local restaurarShiftLock = primeiraPessoaState.shiftLockAntesDePrimeiraPessoa

	primeiraPessoaState.ativo = false
	primeiraPessoaState.cursorDesbloqueado = false
	primeiraPessoaState.transicaoAtiva = true

	-- Desativa primeira pessoa no controller
	if controller.SetPrimeiraPessoa then
		controller:SetPrimeiraPessoa(false)
	end
	if controller.LeaveFirstPerson then
		controller:LeaveFirstPerson()
	end

	-- Restaura estado do ShiftLock
	if mouseController and mouseController.SetIsMouseLocked then
		mouseController:SetIsMouseLocked(restaurarShiftLock)
	elseif controller.SetIsMouseLocked then
		controller:SetIsMouseLocked(restaurarShiftLock)
	end

	-- Se ShiftLock vai ser restaurado, snap do shoulder offset e pula transição alpha
	-- para que a câmera vá direto para a posição do ShiftLock sem passar por "atrás da cabeça"
	if restaurarShiftLock and controller then
		if controller.GetMouseLockOffset and controller.currentShoulderOffset ~= nil then
			controller.currentShoulderOffset = controller:GetMouseLockOffset()
		end
		if controller.transicaoPrimeiraPessoaAlpha then
			controller.transicaoPrimeiraPessoaAlpha = 0
		end
	end

	-- Volta para o zoom mínimo
	local isMouseLocked = restaurarShiftLock
	local zoomRange = if isMouseLocked
		then ConfigJogador.ObterConfiguracao("ZoomRangeOn")
		else ConfigJogador.ObterConfiguracao("ZoomRangeOff")
	local zoomMinimo = zoomRange and zoomRange.Min or 4

	if controller.SetCameraToSubjectDistance then
		controller:SetCameraToSubjectDistance(zoomMinimo)
	end

	-- Snap da spring de zoom para a posição final imediatamente.
	-- Sem isso, a spring começa perto de 0 (FP) e rampeia até zoomMinimo,
	-- causando um flick da câmera atrás do jogador antes de chegar na órbita correta.
	ZoomController.ReleaseSpring()

	local tempo = ConfigJogador.ObterConfiguracao("TransicaoPrimeiraPessoaTempo") or 0.4
	task.delay(tempo, function()
		primeiraPessoaState.transicaoAtiva = false
	end)
end

-- Função acessível globalmente para outros módulos
local function obterEstadoPrimeiraPessoa(): boolean
	return primeiraPessoaState.ativo
end



if not Players.LocalPlayer then
	return {}
end
assert(Players.LocalPlayer, "Strict typing check")

-- Management of which options appear on the Roblox User Settings screen
do
	local PlayerScripts: PlayerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts") :: PlayerScripts

	PlayerScripts:RegisterTouchCameraMovementMode(Enum.TouchCameraMovementMode.Default)
	PlayerScripts:RegisterTouchCameraMovementMode(Enum.TouchCameraMovementMode.Follow)
	PlayerScripts:RegisterTouchCameraMovementMode(Enum.TouchCameraMovementMode.Classic)

	PlayerScripts:RegisterComputerCameraMovementMode(Enum.ComputerCameraMovementMode.Default)
	PlayerScripts:RegisterComputerCameraMovementMode(Enum.ComputerCameraMovementMode.Follow)
	PlayerScripts:RegisterComputerCameraMovementMode(Enum.ComputerCameraMovementMode.Classic)
	PlayerScripts:RegisterComputerCameraMovementMode(Enum.ComputerCameraMovementMode.CameraToggle)
end

local FFlagUserPlayerConnectionMemoryLeak = FlagUtil.getUserFlag("UserPlayerConnectionMemoryLeak")
local FFlagUserPSFixCameraControllerReset = FlagUtil.getUserFlag("UserPSFixCameraControllerReset")

-- Change this later as types are added for more classes
type Generic = any
type GenericOptional = any?

type CameraModuleClass = {
	__index: CameraModuleClass,
	new: () -> CameraModule,

	ActivateCameraController: (self: CameraModule) -> (),
	ActivateOcclusionModule: (self: CameraModule, occlusionMode: Enum.DevCameraOcclusionMode) -> (),
	GetCameraMovementModeFromSettings: (
		self: CameraModule
	) -> Enum.ComputerCameraMovementMode | Enum.DevComputerCameraMovementMode,
	OnPreferredInputChanged: (self: CameraModule) -> (),
	OnCameraSubjectChanged: (self: CameraModule) -> (),
	OnCameraTypeChanged: (self: CameraModule, newCameraType: Enum.CameraType) -> (),
	OnCharacterAdded: (self: CameraModule, character: Model, player: Player) -> (),
	OnCharacterRemoving: (self: CameraModule, character: Model, player: Player) -> (),
	OnCurrentCameraChanged: (self: CameraModule) -> (),
	OnLocalPlayerCameraPropertyChanged: (self: CameraModule, propertyName: string) -> (),
	OnPlayerAdded: (self: CameraModule, player: Player) -> (),
	OnPlayerRemoving: (self: CameraModule, player: Player) -> (),
	OnMouseLockToggled: (self: CameraModule) -> (),
	OnUserGameSettingsPropertyChanged: (self: CameraModule, propertyName: string) -> (),
	ShouldUseVehicleCamera: (self: CameraModule) -> boolean,
	Update: (self: CameraModule, dt: number) -> (),
}

export type CameraModule = typeof(setmetatable(
	{} :: {
		activeCameraController: GenericOptional,
		activeMouseLockController: GenericOptional,
		activeOcclusionModule: GenericOptional,
		activeTransparencyController: Generic,
		cameraSubjectChangedConn: RBXScriptConnection?,
		cameraTypeChangedConn: RBXScriptConnection?,
		connectionUtil: ConnectionUtil.ConnectionUtil?,
		currentComputerCameraMovementMode: Enum.ComputerCameraMovementMode? | Enum.DevComputerCameraMovementMode?,
		occlusionMode: Enum.DevCameraOcclusionMode?,
	},
	{} :: CameraModuleClass
))

function CameraModule.new()
	local self: CameraModule = setmetatable({
		activeTransparencyController = TransparencyController.new(),
		connectionUtil = if FFlagUserPlayerConnectionMemoryLeak then ConnectionUtil.new() else nil,
	}, CameraModule)

	-- Current active controller instances
	self.activeCameraController = nil
	self.activeOcclusionModule = nil
	self.activeMouseLockController = nil

	self.currentComputerCameraMovementMode = nil

	-- Connections to events
	self.cameraSubjectChangedConn = nil
	self.cameraTypeChangedConn = nil

	-- Adds CharacterAdded and CharacterRemoving event handlers for all current players
	for _, player in Players:GetPlayers() do
		self:OnPlayerAdded(player)
	end

	-- Adds CharacterAdded and CharacterRemoving event handlers for all players who join in the future
	Players.PlayerAdded:Connect(function(player)
		self:OnPlayerAdded(player)
	end)

	if FFlagUserPlayerConnectionMemoryLeak then
		Players.PlayerRemoving:Connect(function(player)
			self:OnPlayerRemoving(player)
		end)
	end

	self.activeTransparencyController:Enable(true)

	self.activeMouseLockController = MouseLockController.new()
	assert(self.activeMouseLockController, "Strict typing check")

	local toggleEvent = self.activeMouseLockController:GetBindableToggleEvent()
	if toggleEvent then
		toggleEvent:Connect(function()
			self:OnMouseLockToggled()
		end)
	end

	-- Inicializa limites de zoom
	if self.activeMouseLockController then
		updateZoomLimits(Players.LocalPlayer, self.activeMouseLockController:GetIsMouseLocked())
	end

	self:ActivateCameraController()
	self:ActivateOcclusionModule(Players.LocalPlayer.DevCameraOcclusionMode)
	self:OnCurrentCameraChanged() -- Does initializations and makes first camera controller
	RunService:BindToRenderStep("cameraRenderUpdate", Enum.RenderPriority.Camera.Value, function(dt)
		self:Update(dt)
	end)

	-- Bind tecla V para toggle de primeira pessoa
	local ContextActionService = game:GetService("ContextActionService")
	local teclaPP = ConfigJogador.ObterConfiguracao("TeclaPrimeiraPessoa") or Enum.KeyCode.V
	ContextActionService:BindActionAtPriority("PrimeiraPessoaToggle", function(_name, state, _input)
		if state == Enum.UserInputState.Begin then
			if primeiraPessoaState.ativo then
				sairPrimeiraPessoa(self)
			else
				entrarPrimeiraPessoa(self)
			end
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.ContextActionPriority.Medium.Value, teclaPP)

	-- Bind tecla B para destravar/travar cursor em primeira pessoa
	local teclaCursor = Enum.KeyCode.B
	ContextActionService:BindActionAtPriority("CursorTogglePrimeiraPessoa", function(_name, state, _input)
		if state == Enum.UserInputState.Begin then
			if not primeiraPessoaState.ativo then
				return Enum.ContextActionResult.Pass
			end
			primeiraPessoaState.cursorDesbloqueado = not primeiraPessoaState.cursorDesbloqueado
			if primeiraPessoaState.cursorDesbloqueado then
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
				UserInputService.MouseIconEnabled = true
			end
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.ContextActionPriority.Medium.Value, teclaCursor)

	-- Registra função de estado de primeira pessoa no ClientBridge
	ClientBridge.EstaEmPrimeiraPessoa = obterEstadoPrimeiraPessoa

	-- Connect listeners to camera-related properties
	for _, propertyName in PLAYER_CAMERA_PROPERTIES do
		Players.LocalPlayer:GetPropertyChangedSignal(propertyName):Connect(function()
			self:OnLocalPlayerCameraPropertyChanged(propertyName)
		end)
	end

	for _, propertyName in USER_GAME_SETTINGS_PROPERTIES do
		UserGameSettings:GetPropertyChangedSignal(propertyName):Connect(function()
			self:OnUserGameSettingsPropertyChanged(propertyName)
		end)
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		self:OnCurrentCameraChanged()
	end)
	UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
		self:OnPreferredInputChanged()
	end)

	return self
end

function CameraModule:GetCameraMovementModeFromSettings(): Enum.ComputerCameraMovementMode | Enum.DevComputerCameraMovementMode
	local cameraMode = Players.LocalPlayer.CameraMode

	-- Lock First Person trumps all other settings and forces ClassicCamera
	if cameraMode == Enum.CameraMode.LockFirstPerson then
		return CameraUtils.ConvertCameraModeEnumToStandard(Enum.ComputerCameraMovementMode.Classic)
	end

	local devMode, userMode
	if UserInputService.PreferredInput == Enum.PreferredInput.Touch then
		devMode = CameraUtils.ConvertCameraModeEnumToStandard(Players.LocalPlayer.DevTouchCameraMode)
		userMode = CameraUtils.ConvertCameraModeEnumToStandard(UserGameSettings.TouchCameraMovementMode)
	else
		devMode = CameraUtils.ConvertCameraModeEnumToStandard(Players.LocalPlayer.DevComputerCameraMode)
		userMode = CameraUtils.ConvertCameraModeEnumToStandard(UserGameSettings.ComputerCameraMovementMode)
	end

	if devMode == Enum.DevComputerCameraMovementMode.UserChoice then
		-- Developer is allowing user choice, so user setting is respected
		return userMode
	end

	return devMode
end

function CameraModule:ActivateOcclusionModule(occlusionMode: Enum.DevCameraOcclusionMode)
	local newModuleCreator
	if occlusionMode == Enum.DevCameraOcclusionMode.Zoom then
		newModuleCreator = Poppercam
	elseif occlusionMode == Enum.DevCameraOcclusionMode.Invisicam then
		newModuleCreator = Invisicam
	else
		warn("CameraScript ActivateOcclusionModule called with unsupported mode")
		return
	end

	self.occlusionMode = occlusionMode

	-- First check to see if there is actually a change. If the module being requested is already
	-- the currently-active solution then just make sure it's enabled and exit early
	if self.activeOcclusionModule and self.activeOcclusionModule:GetOcclusionMode() == occlusionMode then
		if not self.activeOcclusionModule:GetEnabled() then
			self.activeOcclusionModule:Enable(true)
		end
		return
	end

	-- Save a reference to the current active module (may be nil) so that we can disable it if
	-- we are successful in activating its replacement
	local prevOcclusionModule = self.activeOcclusionModule

	-- If there is no active module, see if the one we need has already been instantiated
	self.activeOcclusionModule = instantiatedOcclusionModules[newModuleCreator]

	-- If the module was not already instantiated and selected above, instantiate it
	if not self.activeOcclusionModule then
		self.activeOcclusionModule = newModuleCreator.new()
		if self.activeOcclusionModule then
			instantiatedOcclusionModules[newModuleCreator] = self.activeOcclusionModule
		end
	end

	-- If we were successful in either selecting or instantiating the module,
	-- enable it if it's not already the currently-active enabled module
	if self.activeOcclusionModule then
		local newModuleOcclusionMode = self.activeOcclusionModule:GetOcclusionMode()
		-- Sanity check that the module we selected or instantiated actually supports the desired occlusionMode
		if newModuleOcclusionMode ~= occlusionMode then
			warn(
				"CameraScript ActivateOcclusionModule mismatch: ",
				self.activeOcclusionModule:GetOcclusionMode(),
				"~=",
				occlusionMode
			)
		end

		-- Deactivate current module if there is one
		if prevOcclusionModule then
			-- Sanity check that current module is not being replaced by itself (that should have been handled above)
			if prevOcclusionModule ~= self.activeOcclusionModule then
				prevOcclusionModule:Enable(false)
			else
				warn("CameraScript ActivateOcclusionModule failure to detect already running correct module")
			end
		end

		-- Occlusion modules need to be initialized with information about characters and cameraSubject
		-- Invisicam needs the LocalPlayer's character
		-- Poppercam needs all player characters and the camera subject
		if occlusionMode == Enum.DevCameraOcclusionMode.Invisicam then
			-- Optimization to only send Invisicam what we know it needs
			if Players.LocalPlayer.Character then
				self.activeOcclusionModule:CharacterAdded(Players.LocalPlayer.Character, Players.LocalPlayer)
			end
		else
			-- When Poppercam is enabled, we send it all existing player characters for its raycast ignore list
			for _, player in Players:GetPlayers() do
				if player and player.Character then
					self.activeOcclusionModule:CharacterAdded(player.Character, player)
				end
			end
			self.activeOcclusionModule:OnCameraSubjectChanged((workspace.CurrentCamera :: Camera).CameraSubject)
		end

		-- Activate new choice
		self.activeOcclusionModule:Enable(true)
	end
end

function CameraModule:ShouldUseVehicleCamera(): boolean
	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end

	local cameraType = camera.CameraType
	local cameraSubject = camera.CameraSubject

	local isEligibleType = cameraType == Enum.CameraType.Custom or cameraType == Enum.CameraType.Follow
	local isEligibleSubject = cameraSubject and cameraSubject:IsA("VehicleSeat") or false
	local isEligibleOcclusionMode = self.occlusionMode ~= Enum.DevCameraOcclusionMode.Invisicam

	return isEligibleSubject and isEligibleType and isEligibleOcclusionMode
end

function CameraModule:ActivateCameraController()
	-- legacyCameraType should always be respected
	local legacyCameraType = (workspace.CurrentCamera :: Camera).CameraType
	local cameraMovementMode = self:GetCameraMovementModeFromSettings()
	local newCameraCreator = nil

	-- Some legacy CameraTypes map to the use of
	-- the LegacyCamera module, the value "Custom" will be translated to a movementMode enum
	-- value based on Dev and User settings, and "Scriptable" will disable the camera controller.
	if legacyCameraType == Enum.CameraType.Scriptable then
		if self.activeCameraController then
			self.activeCameraController:Enable(false)
			self.activeCameraController = nil
		end
		return
	elseif legacyCameraType == Enum.CameraType.Custom then
		cameraMovementMode = self:GetCameraMovementModeFromSettings()
	elseif legacyCameraType == Enum.CameraType.Track then
		-- Note: The TrackCamera module was basically an older, less fully-featured
		-- version of ClassicCamera, no longer actively maintained, but it is re-implemented in
		-- case a game was dependent on its lack of ClassicCamera's extra functionality.
		cameraMovementMode = Enum.ComputerCameraMovementMode.Classic
	elseif legacyCameraType == Enum.CameraType.Follow then
		cameraMovementMode = Enum.ComputerCameraMovementMode.Follow
	elseif legacyCameraType == Enum.CameraType.Orbital then
		cameraMovementMode = Enum.ComputerCameraMovementMode.Orbital
	elseif
		legacyCameraType == Enum.CameraType.Attach
		or legacyCameraType == Enum.CameraType.Watch
		or legacyCameraType == Enum.CameraType.Fixed
	then
		newCameraCreator = LegacyCamera
	else
		warn("CameraScript encountered an unhandled Camera.CameraType value: ", legacyCameraType)
	end

	if not newCameraCreator then
		if VRService.VREnabled then
			newCameraCreator = VRCamera
		elseif
			cameraMovementMode == Enum.ComputerCameraMovementMode.Classic
			or cameraMovementMode == Enum.ComputerCameraMovementMode.Follow
			or cameraMovementMode == Enum.ComputerCameraMovementMode.Default
			or cameraMovementMode == Enum.ComputerCameraMovementMode.CameraToggle
		then
			newCameraCreator = ClassicCamera
		elseif cameraMovementMode == Enum.ComputerCameraMovementMode.Orbital then
			newCameraCreator = OrbitalCamera
		else
			warn("ActivateCameraController did not select a module.")
			return
		end
	end

	local isVehicleCamera = self:ShouldUseVehicleCamera()
	if isVehicleCamera then
		if VRService.VREnabled then
			newCameraCreator = VRVehicleCamera
		else
			newCameraCreator = VehicleCamera
		end
	end

	-- Create the camera control module we need if it does not already exist in instantiatedCameraControllers
	local newCameraController
	if not instantiatedCameraControllers[newCameraCreator] then
		newCameraController = newCameraCreator.new()
		instantiatedCameraControllers[newCameraCreator] = newCameraController
	else
		newCameraController = instantiatedCameraControllers[newCameraCreator]
		if FFlagUserPSFixCameraControllerReset then
			if newCameraController.Reset and self.activeCameraController ~= newCameraController then
				newCameraController:Reset()
			end
		else
			if newCameraController.Reset then
				newCameraController:Reset()
			end
		end
	end

	if self.activeCameraController then
		-- deactivate the old controller and activate the new one
		if self.activeCameraController ~= newCameraController then
			self.activeCameraController:Enable(false)
			self.activeCameraController = newCameraController
			self.activeCameraController:Enable(true)
		elseif not self.activeCameraController:GetEnabled() then
			self.activeCameraController:Enable(true)
		end
	elseif newCameraController ~= nil then
		-- only activate the new controller
		self.activeCameraController = newCameraController
		assert(self.activeCameraController, "Strict typing check")

		self.activeCameraController:Enable(true)
	end

	if self.activeCameraController then
		-- These functions can be removed in the future and the logic of managing cameraType/cameraMovementMode should be moved
		-- into a higher level class so that activeCameraControllers can be single function.
		self.activeCameraController:SetCameraMovementMode(cameraMovementMode)
		-- was convertible to a ComputerCameraMovementMode value, i.e. really only applies to LegacyCamera
		self.activeCameraController:SetCameraType(legacyCameraType)
	end
end

-- Note: The active transparency controller could be made to listen for this event itself.
function CameraModule:OnCameraSubjectChanged()
	local camera = workspace.CurrentCamera
	local cameraSubject = if camera then camera.CameraSubject else nil

	if self.activeTransparencyController then
		self.activeTransparencyController:SetSubject(cameraSubject)
	end

	if self.activeOcclusionModule then
		self.activeOcclusionModule:OnCameraSubjectChanged(cameraSubject)
	end

	self:ActivateCameraController()
end

function CameraModule:OnCameraTypeChanged(newCameraType: Enum.CameraType)
	if newCameraType == Enum.CameraType.Scriptable then
		if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
			CameraUtils.restoreMouseBehavior()
		end
	end

	-- Forward the change to ActivateCameraController to handle
	self:ActivateCameraController()
end

-- Note: Called whenever workspace.CurrentCamera changes, but also on initialization of this script
function CameraModule:OnCurrentCameraChanged()
	local currentCamera = workspace.CurrentCamera
	if not currentCamera then
		return
	end

	if self.cameraSubjectChangedConn then
		self.cameraSubjectChangedConn:Disconnect()
	end

	if self.cameraTypeChangedConn then
		self.cameraTypeChangedConn:Disconnect()
	end

	self.cameraSubjectChangedConn = currentCamera:GetPropertyChangedSignal("CameraSubject"):Connect(function()
		self:OnCameraSubjectChanged()
	end)

	self.cameraTypeChangedConn = currentCamera:GetPropertyChangedSignal("CameraType"):Connect(function()
		self:OnCameraTypeChanged(currentCamera.CameraType)
	end)

	self:OnCameraSubjectChanged()
	self:OnCameraTypeChanged(currentCamera.CameraType)
end

function CameraModule:OnLocalPlayerCameraPropertyChanged(propertyName: string)
	if propertyName == "CameraMode" then
		-- CameraMode is only used to turn on/off forcing the player into first person view. The
		-- Note: The case "Classic" is used for all other views and does not correspond only to the ClassicCamera module
		if Players.LocalPlayer.CameraMode == Enum.CameraMode.LockFirstPerson then
			-- Locked in first person, use ClassicCamera which supports this
			if not self.activeCameraController or self.activeCameraController:GetModuleName() ~= "ClassicCamera" then
				self:ActivateCameraController()
			end

			if self.activeCameraController then
				self.activeCameraController:UpdateForDistancePropertyChange()
			end
		elseif Players.LocalPlayer.CameraMode == Enum.CameraMode.Classic then
			-- Not locked in first person view
			self:ActivateCameraController()
		else
			warn("Unhandled value for property player.CameraMode: ", Players.LocalPlayer.CameraMode)
		end
	elseif propertyName == "DevComputerCameraMode" or propertyName == "DevTouchCameraMode" then
		self:ActivateCameraController()
	elseif propertyName == "DevCameraOcclusionMode" then
		self:ActivateOcclusionModule(Players.LocalPlayer.DevCameraOcclusionMode)
	elseif propertyName == "CameraMinZoomDistance" or propertyName == "CameraMaxZoomDistance" then
		if self.activeCameraController then
			self.activeCameraController:UpdateForDistancePropertyChange()
		end
	end
end

function CameraModule:OnUserGameSettingsPropertyChanged(propertyName: string)
	if propertyName == "ComputerCameraMovementMode" or propertyName == "TouchCameraMovementMode" then
		self:ActivateCameraController()
	end
end

function CameraModule:OnPreferredInputChanged()
	self:ActivateCameraController()
end

--[[
	Main RenderStep Update. The camera controller and occlusion module both have opportunities
	to set and modify (respectively) the CFrame and Focus before it is set once on CurrentCamera.
	The camera and occlusion modules should only return CFrames, not set the CFrame property of
	CurrentCamera directly.
--]]
function CameraModule:Update(dt)
	if self.activeCameraController then
		-- Em 1ª pessoa: interceptar scroll para trás (zoom out) para sair
		if primeiraPessoaState.ativo then
			local zoomDelta = CameraInput.getZoomDelta()
			if zoomDelta > 0 then
				-- Scroll para trás: sair de 1ª pessoa
				sairPrimeiraPessoa(self)
				-- Consome o delta de zoom para não afetar o zoom normal
				CameraInput.resetInputForFrameEnd()
			end
			-- Scroll para frente: ignorar (não faz nada em 1ª pessoa)
		end

		-- Cursor desbloqueado em 1ª pessoa: congela rotação e libera mouse
		if primeiraPessoaState.cursorDesbloqueado then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
			CameraInput.resetInputForFrameEnd()
		else
			self.activeCameraController:UpdateMouseBehavior()
		end

		local newCameraCFrame, newCameraFocus = self.activeCameraController:Update(dt)

		if self.activeOcclusionModule and not primeiraPessoaState.ativo then
			newCameraCFrame, newCameraFocus = self.activeOcclusionModule:Update(dt, newCameraCFrame, newCameraFocus)
		end

		-- Here is where the new CFrame and Focus are set for this render frame
		local currentCamera = workspace.CurrentCamera :: Camera
		currentCamera.CFrame = newCameraCFrame
		currentCamera.Focus = newCameraFocus

		-- Efeitos dinâmicos de câmera (bobbing, roll, lean, drift) - só em 1ª pessoa
		local isInFirstPerson = primeiraPessoaState.ativo
		local character = Players.LocalPlayer.Character
		if character then
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local isDashing = ClientBridge.EstaEmDash and ClientBridge.EstaEmDash() or false
				currentCamera.CFrame = DynamicCamFX.Update(dt, currentCamera.CFrame, isInFirstPerson, isDashing, hrp)

				-- Sistema de Y fixo durante dash: mantém offset relativo ao HRP
				local fixarY = Modulo_Configuracoes.ObterConfiguracao("DashCameraFixarY")
				if fixarY and isInFirstPerson then
					if isDashing then
						local hrpY = (hrp :: BasePart).Position.Y
						if not dashCamState.ativo then
							-- Captura offset câmera→HRP no início do dash
							dashCamState.ativo = true
							dashCamState.offsetY = currentCamera.CFrame.Position.Y - hrpY
						end
						-- Força Y = HRP.Y + offset original
						local pos = currentCamera.CFrame.Position
						local fixedY = hrpY + (dashCamState.offsetY :: number)
						local fixedPos = Vector3.new(pos.X, fixedY, pos.Z)
						currentCamera.CFrame = currentCamera.CFrame - pos + fixedPos
					else
						dashCamState.ativo = false
						dashCamState.offsetY = nil
					end
				else
					dashCamState.ativo = false
					dashCamState.offsetY = nil
				end
			end
		end

		-- Update to character local transparency as needed based on camera-to-subject distance
		if self.activeTransparencyController then
			-- Só marca como primeira pessoa para transparência quando a transição terminar
			local fpTransicaoCompleta = isInFirstPerson
				and self.activeCameraController
				and self.activeCameraController.transicaoPrimeiraPessoaAlpha
				and self.activeCameraController.transicaoPrimeiraPessoaAlpha >= 1
			self.activeTransparencyController:Update(dt, fpTransicaoCompleta)
		end

		-- Sistema de FOV dinâmico baseado na velocidade do jogador
		updateFOV(currentCamera, dt, isInFirstPerson)

		-- Sincroniza Status.ShiftLockOn (para combate) baseado em 1ª pessoa ou MouseLock
		checkFirstPersonAndUpdateStatus(self.activeCameraController, self.activeMouseLockController)

		if CameraInput.getInputEnabled() then
			CameraInput.resetInputForFrameEnd()
		end
	end
end

function CameraModule:OnCharacterAdded(char: Model, player: Player)
	if self.activeOcclusionModule then
		self.activeOcclusionModule:CharacterAdded(char, player)
	end

	-- Reseta primeira pessoa ao respawnar
	if player == Players.LocalPlayer then
		-- Invalida caches de StatusLocal (novo character = novas instâncias)
		cachedEstadoMov = nil
		cachedShiftLockBool = nil
		lastShiftLockSet = nil

		if primeiraPessoaState.ativo then
			primeiraPessoaState.ativo = false
			primeiraPessoaState.transicaoAtiva = false
			if self.activeCameraController and self.activeCameraController.SetPrimeiraPessoa then
				self.activeCameraController:SetPrimeiraPessoa(false)
			end
		end
	end
end

function CameraModule:OnCharacterRemoving(char, player)
	if self.activeOcclusionModule then
		self.activeOcclusionModule:CharacterRemoving(char, player)
	end
end

function CameraModule:OnPlayerAdded(player: Player)
	if FFlagUserPlayerConnectionMemoryLeak then
		-- Return connectionUtil to non optional if FFlagUserPlayerConnectionMemoryLeak is removed
		if self.connectionUtil then
			self.connectionUtil:trackConnection(
				`{player.UserId}CharacterAdded`,
				player.CharacterAdded:Connect(function(char)
					self:OnCharacterAdded(char, player)
				end)
			)
			self.connectionUtil:trackConnection(
				`{player.UserId}CharacterRemoving`,
				player.CharacterRemoving:Connect(function(char)
					self:OnCharacterRemoving(char, player)
				end)
			)
		end
	else
		player.CharacterAdded:Connect(function(char)
			self:OnCharacterAdded(char, player)
		end)
		player.CharacterRemoving:Connect(function(char)
			self:OnCharacterRemoving(char, player)
		end)
	end
end

function CameraModule:OnPlayerRemoving(player: Player)
	-- Return connectionUtil to non optional if FFlagUserPlayerConnectionMemoryLeak is removed
	if self.connectionUtil then
		self.connectionUtil:disconnect(`{player.UserId}CharacterAdded`)
		self.connectionUtil:disconnect(`{player.UserId}CharacterRemoving`)
	end
end

function CameraModule:OnMouseLockToggled()
	if self.activeMouseLockController then
		local mouseLocked = self.activeMouseLockController:GetIsMouseLocked()
		local mouseLockOffset = self.activeMouseLockController:GetMouseLockOffset()
		if self.activeCameraController then
			self.activeCameraController:SetIsMouseLocked(mouseLocked)
			self.activeCameraController:SetMouseLockOffset(mouseLockOffset)
		end

		-- Sincroniza Status.ShiftLockOn com o sistema de combate
		checkFirstPersonAndUpdateStatus(self.activeCameraController, self.activeMouseLockController)

		-- Atualiza limites de zoom com transição
		updateZoomLimits(Players.LocalPlayer, mouseLocked)
	end
end

CameraModule.new()

return {} -- Corresponds to the expected return type in Roblox standard PlayerModule
