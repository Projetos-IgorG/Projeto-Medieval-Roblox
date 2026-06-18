--!strict

--[[
    Script: init.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/PlayerModule/CameraModule
    Responsabilidade: Seleciona, ativa e atualiza o controlador de camera apropriado para o jogador.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao implementa regras de gameplay do projeto; apenas apoia camera, controle e compatibilidade do jogador.
    Funcoes principais: new, GetCameraMovementModeFromSettings, ActivateOcclusionModule, ShouldUseVehicleCamera, ActivateCameraController, OnCameraSubjectChanged
]]
local CameraModule = {}
CameraModule.__index = CameraModule

local PLAYER_CAMERA_PROPERTIES = {
	"CameraMinZoomDistance",
	"CameraMaxZoomDistance",
	"CameraMode",
	"DevCameraOcclusionMode",
	"DevComputerCameraMode",
	"DevTouchCameraMode",

	"DevComputerMovementMode",
	"DevTouchMovementMode",
	"DevEnableMouseLock",
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

local CameraUtils = require(script:WaitForChild("CameraUtils"))
local CameraInput = require(script:WaitForChild("CameraInput"))

local ClassicCamera = require(script:WaitForChild("ClassicCamera"))
local OrbitalCamera = require(script:WaitForChild("OrbitalCamera"))
local LegacyCamera = require(script:WaitForChild("LegacyCamera"))
local VehicleCamera = require(script:WaitForChild("VehicleCamera"))

local VRCamera = require(script:WaitForChild("VRCamera"))
local VRVehicleCamera = require(script:WaitForChild("VRVehicleCamera"))

local Invisicam = require(script:WaitForChild("Invisicam"))
local Poppercam = require(script:WaitForChild("Poppercam"))

local TransparencyController = require(script:WaitForChild("TransparencyController"))
local MouseLockController = require(script:WaitForChild("MouseLockController"))
local DynamicCamFX = require(script:WaitForChild("DynamicCamFX"))
local ZoomController = require(script:WaitForChild("ZoomController"))

local ConfigJogador = require(
	ReplicatedStorage:WaitForChild("Jogador"):WaitForChild("Camera"):WaitForChild("Configuracoes"):WaitForChild("ConfigCamera")
)

local ClientBridge =
	require(ReplicatedStorage:WaitForChild("Jogador"):WaitForChild("ComunicacaoCliente"):WaitForChild("PonteCliente"))

local Modulo_Configuracoes = require(
	ReplicatedStorage:WaitForChild("Combate"):WaitForChild("Configuracoes"):WaitForChild("ConfigCombate")
)

local dashCamState = {
	ativo = false,
	offsetY = nil :: number?,
}

local instantiatedCameraControllers = {}
local instantiatedOcclusionModules = {}

local fovState = {
	runRampProgress = 0,
}

do
	local cam = workspace.CurrentCamera
	if cam then
		cam.FieldOfView = ConfigJogador.ObterConfiguracao("DefaultFOV") or 78
	end
end

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

local function updateFOV(camera: Camera, dt: number, emPrimeiraPessoa: boolean)
	local estadoMov = getCachedEstadoMov()

	local isRunning = (estadoMov == "Correndo")
	local isMoving = (estadoMov == "Andando") or isRunning

	local rampTime = ConfigJogador.ObterConfiguracao("RunFOVRampTime") or 0.8
	if isRunning then
		fovState.runRampProgress = math.min(fovState.runRampProgress + dt / rampTime, 1)
	else
		fovState.runRampProgress = math.max(fovState.runRampProgress - dt / rampTime, 0)
	end

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

	local transitionSpeed = ConfigJogador.ObterConfiguracao("FOVTransitionTime") or 0.3
	local lerpRate = math.clamp(dt / transitionSpeed, 0, 1)
	camera.FieldOfView = camera.FieldOfView + (targetFOV - camera.FieldOfView) * lerpRate
end

local zoomState = {
	currentTween = nil :: Tween?,
}

local primeiraPessoaState = {
	ativo = false,
	transicaoAtiva = false,
	zoomAnterior = 10,
	shiftLockAntesDePrimeiraPessoa = false,
	cursorDesbloqueado = false,
}

local function updateShiftLockStatus(isLocked: boolean)

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

local function entrarPrimeiraPessoa(cameraModule: any)
	if primeiraPessoaState.ativo or primeiraPessoaState.transicaoAtiva then
		return
	end

	local controller = cameraModule.activeCameraController
	local mouseController = cameraModule.activeMouseLockController
	if not controller then
		return
	end

	primeiraPessoaState.shiftLockAntesDePrimeiraPessoa = mouseController
		and mouseController.GetIsMouseLocked
		and mouseController:GetIsMouseLocked() or false

	if controller.GetCameraToSubjectDistance then
		primeiraPessoaState.zoomAnterior = controller:GetCameraToSubjectDistance()
	end

	primeiraPessoaState.ativo = true
	primeiraPessoaState.transicaoAtiva = true

	if mouseController and mouseController.SetIsMouseLocked then
		mouseController:SetIsMouseLocked(true)
	elseif controller.SetIsMouseLocked then
		controller:SetIsMouseLocked(true)
	end
	if controller.EnterFirstPerson then
		controller:EnterFirstPerson()
	end

	if controller.SetPrimeiraPessoa then
		controller:SetPrimeiraPessoa(true)
	end

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

	if controller.SetPrimeiraPessoa then
		controller:SetPrimeiraPessoa(false)
	end
	if controller.LeaveFirstPerson then
		controller:LeaveFirstPerson()
	end

	if mouseController and mouseController.SetIsMouseLocked then
		mouseController:SetIsMouseLocked(restaurarShiftLock)
	elseif controller.SetIsMouseLocked then
		controller:SetIsMouseLocked(restaurarShiftLock)
	end

	if restaurarShiftLock and controller then
		if controller.GetMouseLockOffset and controller.currentShoulderOffset ~= nil then
			controller.currentShoulderOffset = controller:GetMouseLockOffset()
		end
		if controller.transicaoPrimeiraPessoaAlpha then
			controller.transicaoPrimeiraPessoaAlpha = 0
		end
	end

	local isMouseLocked = restaurarShiftLock
	local zoomRange = if isMouseLocked
		then ConfigJogador.ObterConfiguracao("ZoomRangeOn")
		else ConfigJogador.ObterConfiguracao("ZoomRangeOff")
	local zoomMinimo = zoomRange and zoomRange.Min or 4

	if controller.SetCameraToSubjectDistance then
		controller:SetCameraToSubjectDistance(zoomMinimo)
	end

	ZoomController.ReleaseSpring()

	local tempo = ConfigJogador.ObterConfiguracao("TransicaoPrimeiraPessoaTempo") or 0.4
	task.delay(tempo, function()
		primeiraPessoaState.transicaoAtiva = false
	end)
end

local function obterEstadoPrimeiraPessoa(): boolean
	return primeiraPessoaState.ativo
end

if not Players.LocalPlayer then
	return {}
end
assert(Players.LocalPlayer, "Strict typing check")

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

	self.activeCameraController = nil
	self.activeOcclusionModule = nil
	self.activeMouseLockController = nil

	self.currentComputerCameraMovementMode = nil

	self.cameraSubjectChangedConn = nil
	self.cameraTypeChangedConn = nil

	for _, player in Players:GetPlayers() do
		self:OnPlayerAdded(player)
	end

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

	if self.activeMouseLockController then
		updateZoomLimits(Players.LocalPlayer, self.activeMouseLockController:GetIsMouseLocked())
	end

	self:ActivateCameraController()
	self:ActivateOcclusionModule(Players.LocalPlayer.DevCameraOcclusionMode)
	self:OnCurrentCameraChanged()
	RunService:BindToRenderStep("cameraRenderUpdate", Enum.RenderPriority.Camera.Value, function(dt)
		self:Update(dt)
	end)

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

	ClientBridge.EstaEmPrimeiraPessoa = obterEstadoPrimeiraPessoa

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

	if self.activeOcclusionModule and self.activeOcclusionModule:GetOcclusionMode() == occlusionMode then
		if not self.activeOcclusionModule:GetEnabled() then
			self.activeOcclusionModule:Enable(true)
		end
		return
	end

	local prevOcclusionModule = self.activeOcclusionModule

	self.activeOcclusionModule = instantiatedOcclusionModules[newModuleCreator]

	if not self.activeOcclusionModule then
		self.activeOcclusionModule = newModuleCreator.new()
		if self.activeOcclusionModule then
			instantiatedOcclusionModules[newModuleCreator] = self.activeOcclusionModule
		end
	end

	if self.activeOcclusionModule then
		local newModuleOcclusionMode = self.activeOcclusionModule:GetOcclusionMode()

		if newModuleOcclusionMode ~= occlusionMode then
			warn(
				"CameraScript ActivateOcclusionModule mismatch: ",
				self.activeOcclusionModule:GetOcclusionMode(),
				"~=",
				occlusionMode
			)
		end

		if prevOcclusionModule then

			if prevOcclusionModule ~= self.activeOcclusionModule then
				prevOcclusionModule:Enable(false)
			else
				warn("CameraScript ActivateOcclusionModule failure to detect already running correct module")
			end
		end

		if occlusionMode == Enum.DevCameraOcclusionMode.Invisicam then

			if Players.LocalPlayer.Character then
				self.activeOcclusionModule:CharacterAdded(Players.LocalPlayer.Character, Players.LocalPlayer)
			end
		else

			for _, player in Players:GetPlayers() do
				if player and player.Character then
					self.activeOcclusionModule:CharacterAdded(player.Character, player)
				end
			end
			self.activeOcclusionModule:OnCameraSubjectChanged((workspace.CurrentCamera :: Camera).CameraSubject)
		end

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

	local legacyCameraType = (workspace.CurrentCamera :: Camera).CameraType
	local cameraMovementMode = self:GetCameraMovementModeFromSettings()
	local newCameraCreator = nil

	if legacyCameraType == Enum.CameraType.Scriptable then
		if self.activeCameraController then
			self.activeCameraController:Enable(false)
			self.activeCameraController = nil
		end
		return
	elseif legacyCameraType == Enum.CameraType.Custom then
		cameraMovementMode = self:GetCameraMovementModeFromSettings()
	elseif legacyCameraType == Enum.CameraType.Track then

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

		if self.activeCameraController ~= newCameraController then
			self.activeCameraController:Enable(false)
			self.activeCameraController = newCameraController
			self.activeCameraController:Enable(true)
		elseif not self.activeCameraController:GetEnabled() then
			self.activeCameraController:Enable(true)
		end
	elseif newCameraController ~= nil then

		self.activeCameraController = newCameraController
		assert(self.activeCameraController, "Strict typing check")

		self.activeCameraController:Enable(true)
	end

	if self.activeCameraController then

		self.activeCameraController:SetCameraMovementMode(cameraMovementMode)

		self.activeCameraController:SetCameraType(legacyCameraType)
	end
end

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

	self:ActivateCameraController()
end

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

		if Players.LocalPlayer.CameraMode == Enum.CameraMode.LockFirstPerson then

			if not self.activeCameraController or self.activeCameraController:GetModuleName() ~= "ClassicCamera" then
				self:ActivateCameraController()
			end

			if self.activeCameraController then
				self.activeCameraController:UpdateForDistancePropertyChange()
			end
		elseif Players.LocalPlayer.CameraMode == Enum.CameraMode.Classic then

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

function CameraModule:Update(dt)
	if self.activeCameraController then

		if primeiraPessoaState.ativo then
			local zoomDelta = CameraInput.getZoomDelta()
			if zoomDelta > 0 then

				sairPrimeiraPessoa(self)

				CameraInput.resetInputForFrameEnd()
			end

		end

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

		local currentCamera = workspace.CurrentCamera :: Camera
		currentCamera.CFrame = newCameraCFrame
		currentCamera.Focus = newCameraFocus

		local isInFirstPerson = primeiraPessoaState.ativo
		local character = Players.LocalPlayer.Character
		if character then
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local isRolling = ClientBridge.EstaEmRoll and ClientBridge.EstaEmRoll() or false
				local isDashing = ClientBridge.EstaEmDash and ClientBridge.EstaEmDash() or false
				local isRollOrDash = isRolling or isDashing
				currentCamera.CFrame = DynamicCamFX.Update(dt, currentCamera.CFrame, isInFirstPerson, isRollOrDash, hrp)

				local fixarY = Modulo_Configuracoes.ObterConfiguracao("DashCameraFixarY")
				if fixarY and isInFirstPerson then
					if isRollOrDash then
						local hrpY = (hrp :: BasePart).Position.Y
						if not dashCamState.ativo then

							dashCamState.ativo = true
							dashCamState.offsetY = currentCamera.CFrame.Position.Y - hrpY
						end

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

		if self.activeTransparencyController then

			local fpTransicaoCompleta = isInFirstPerson
				and self.activeCameraController
				and self.activeCameraController.transicaoPrimeiraPessoaAlpha
				and self.activeCameraController.transicaoPrimeiraPessoaAlpha >= 1
			self.activeTransparencyController:Update(dt, fpTransicaoCompleta)
		end

		updateFOV(currentCamera, dt, isInFirstPerson)

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

	if player == Players.LocalPlayer then

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

		checkFirstPersonAndUpdateStatus(self.activeCameraController, self.activeMouseLockController)

		updateZoomLimits(Players.LocalPlayer, mouseLocked)
	end
end

CameraModule.new()

return {}
