--[[
    Script: ConfigParkour.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/Jogador/Parkour/Configuracoes
    Responsabilidade: Centraliza parametros, alcances, tempos e animacoes do sistema de parkour.
    Uso: ModuleScript; use require(caminho) para ler as tabelas e valores exportados.
    Nao faz: Nao executa comportamento sozinho; apenas fornece dados para outros scripts.
    Funcoes principais: invalidateCache, mergeConfig
]]
local Configs = {}
local MERGED_SENTINEL = "__ParkourMergedConfig"

Configs.DebugEnabled = false
Configs.DebugVerbose = false
Configs.DebugLifetime = 2
Configs.DebugFolderName = "ParkourDebugFolder"

Configs.Tags = {
	NAO_AGARRAVEL = "NaoAgarravel",
	FORCAR_SUSPENSO = "ForcarSuspenso",
}

Configs.DefaultConfig = {
	RayDistance = 8,
	ClassificationRayDistance = 8,
	ClassificationRayExtraDistance = 0.75,

	ForwardRayGridRows = 7,
	ForwardRayGridColumns = 5,
	ForwardRayGridWidth = 4.5,
	ForwardRayGridHeight = 5.5,
	ForwardRayGridUpOffset = 0.8,
	ForwardRayGridDistance = 6,
	ForwardRayGridMaxPasses = 3,
	ForwardRayGridBorderOnly = true,
	ForwardRayGridVaultMedioStartRatio = 0.34,
	ForwardRayGridGrabStartRatio = 0.72,
	ForwardObstacleSampleYOffset = 0.0,
	ForwardObstacleMaxDistance = 9.0,

	TopClearanceSize = Vector3.new(2.2, 0.4, 0.5),
	TopClearanceUpOffset = 0.21,
	TopClearanceNormalOffset = 0.1,

	FrontClearanceSize = Vector3.new(2.2, 5.0, 1.6),
	FrontClearanceUpOffset = -2.4,
	FrontClearanceNormalOffset = 0.9,

	LegProbeDownOffset = 2.8,
	LegProbeStartNormalOffset = 0.75,
	LegSupportRayDistance = 0.8,
	LegSupportRayOriginDownOffset = 3.5,
	LegSupportRayOriginForwardOffset = -0.1,
	LegSupportRayHeights = { 0, -0.8 },
	LegSupportRayLateralOffsets = { -0.7, 0.0, 0.7 },
	LegSupportRayMaxPasses = 6,

	TopoTorsoOffset = 1.5,
	PernaRayOffset = -0.5,
	TorsoRayOffset = 1.0,

	VaultClearanceSize = Vector3.new(1.9, 4.0, 2.0),
	VaultEdgeClearanceUpOffset = 2.2,

	VaultClearanceForwardOffset = 2.0,
	VaultClearanceUpOffset = 2.5,

	VaultMoveUpOffset = 5.0,

	VaultImpulseDuration = 0.2,

	MaxGrabDistance = 4.5,
	MaxGrabReachHeight = 5.5,
	MaxVaultDistance = 6.0,

	MinPartHeight = 0.6,

	GrabSurfaceOffset = 1.2,
	GrabVerticalOffset = -2.3,
	GrabSurfaceSafetyMargin = 0.2,
	GrabSafetyProbeScale = 0.9,
	GrabSafetyPushStep = 0.15,
	GrabSafetyMaxPushSteps = 6,
	GrabTransitionTime = 0.15,
	GrabFinalReachDistance = 0.25,
	GrabFinalSnapTimeout = 0.25,
	GrabMinSettleTime = 0.04,
	GrabIdleStartDelay = 0.01,
	GrabIdleRecheckInterval = 0.2,
	IdleDebugVerbose = true,
	IdleDebugVisualEnabled = true,
	IdleDebugStableLogInterval = 0.35,
	IdleDebugFlipWindow = 1.25,
	IdleDebugFlipWarnThreshold = 4,
	IdleSwitchToSupportConfirmations = 2,
	IdleSwitchToSuspensoConfirmations = 2,
	IdleSwitchMinInterval = 0.45,

	VaultBaixoImpulse = 50,
	VaultBaixoTransitionTime = 0.15,

	VaultMedioImpulse = 40,
	VaultMedioTransitionTime = 0.2,

	SubirAreaSize = Vector3.new(3.5, 10.0, 6.0),
	SubirAreaUpOffset = 5.0,
	SubirProbeNormalOffset = 2.0,
	SubirMinVerticalDelta = 0.5,
	SubirMaxHorizontalDistance = 5.5,
	SubirMaxProfundidade = 1.5,
	SubirSaltoMaxProfundidade = 2.4,
	SubirMaxAltura = 6.0,
	SubirSaltoMaxAltura = 10.5,
	SubirTransitionTime = 0.4,
	SubirSaltoMinActionTime = 0.55,
	SubirSaltoIdleFadeOut = 0.2,
	SubirSaltoConfirmWindow = 0.9,
	SubirSaltoConfirmEdgeTolerance = 2.5,
	SubirSaltoPreferTimeout = 0.77,
	MaxWallNormalY = 0.8,

	DescerAreaSize = Vector3.new(2.0, 10.0, 6.0),
	DescerAreaDownOffset = -5.0,
	DescerProbeNormalOffset = 2.0,
	DescerMinVerticalDelta = 0.5,
	DescerMaxAltura = 10.0,
	DescerTransitionTime = 0.35,
	DescerGrandeTransitionTimeMultiplier = 1.4,

	LateralAreaSize = Vector3.new(12.0, 7, 6.0),
	LateralAreaUpOffset = -1.5,
	LateralAreaSideBias = 0.35,
	LateralTargetSideOffset = 3.2,
	LateralProbeNormalOffset = 2.0,
	LateralMaxProfundidade = 2.2,
	LateralTopEdgeTolerance = 2.0,
	LateralMaxHorizontal = 6,
	LateralMaxVertical = 2.06,
	LateralSaltoMaxHorizontal = 11.0,
	LateralSaltoMaxVertical = 4.0,
	LateralSaltoTopEdgeTolerance = 4.0,
	LateralNormalMinDot = 0.5,
	LateralCornerMinDot = -0.15,
	LateralCornerMaxProfundidade = 4.5,
	LateralExternalCornerMinDot = -0.35,
	LateralExternalCornerMaxProfundidade = 8.0,
	LateralPathClearanceSize = Vector3.new(1.8, 3.8, 1.4),
	LateralPathClearanceNormalOffset = 1.2,
	LateralPathClearanceHeightOffset = -1.3,
	LateralPathSideDistance = 2.2,
	LateralMinSideDistance = 0.1,
	LateralSaltoMinSideDistance = 4.5,
	LateralReverseTolerance = 0.05,
	LateralCandidateBoxMargin = 0.5,
	LateralExternalPathRayUpOffset = 0.2,
	LateralExternalPathRayNormalOffset = 1.2,
	LateralTransitionTime = 0.35,
	LateralSaltoTransitionTime = 0.5,
	LateralTransitionPhaseSplit = 0.55,
	LateralInputDotThreshold = 0.35,
	DirectionInputDeadzone = 0.2,
	DirectionForwardDotThreshold = 0.6,
	DirectionLateralDotThreshold = 0.6,
	DirectionDominanceMargin = 0.12,
	LateralJumpImpulse = 32,
	LateralJumpUpComponent = 0.6,
	LateralSaltoCancelSpeedAbs = 1.3,
	LateralSaltoPreferTimeout = 0.77,

	EscalarMaxVerticalDistance = 3.0,
	EscalarForwardOffset = 1.2,
	EscalarUpOffset = 2.5,
	EscalarTransitionTime = 0.35,
	EscalarVerticalFirstRatio = 0.2,
	EscalarFinalSnapDistance = 0.2,
	EscalarFinalSnapTimeout = 0.6,

	EscalarClearanceSize = Vector3.new(1.9, 4.0, 2.0),
	EscalarClearanceUpOffset = 2.5,
	EscalarClearanceForwardOffset = -0.3,

	PuloTrasImpulse = 40,
	PuloTrasUpComponent = 0.8,

	DescerHoldTime = 0.15,
	DescerNoOptionReleaseDelay = 0.2,

	MomentumBaseSpeed = 1.0,
	MomentumMaxSpeed = 1.3,
	MomentumIncrement = 0.05,
	MomentumDecayWindow = 2.0,

	SubirFailThrottle = 0.35,
	DescerFailThrottle = 0.2,
	LateralNoSurfaceThrottle = 0.5,
	LateralNoSurfaceBackoff = 0.15,
}

local _cachedDefaultMerge = nil

function Configs.invalidateCache()
	if _cachedDefaultMerge then
		for key, value in pairs(Configs.DefaultConfig) do
			_cachedDefaultMerge[key] = value
		end
	end
end

function Configs.mergeConfig(config)
	if config == nil then
		local cached = _cachedDefaultMerge
		if cached then
			return cached
		end
		local final = table.clone(Configs.DefaultConfig)
		final[MERGED_SENTINEL] = true
		_cachedDefaultMerge = final
		return final
	end

	if config[MERGED_SENTINEL] then
		return config
	end

	local final = table.clone(Configs.DefaultConfig)
	for key, value in pairs(config) do
		final[key] = value
	end
	final[MERGED_SENTINEL] = true
	return final
end

return Configs
