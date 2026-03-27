local Configs = {}
local MERGED_SENTINEL = "__ParkourMergedConfig"

-- ══════════════════════════════════════
-- Flags de Debug
-- ══════════════════════════════════════

Configs.DebugEnabled = false -- visuais (linhas, caixas, pontos)
Configs.DebugVerbose = false -- prints detalhados no console
Configs.DebugLifetime = 1.5
Configs.DebugFolderName = "ParkourDebugFolder"

-- ══════════════════════════════════════
-- Tags do CollectionService
-- ══════════════════════════════════════

Configs.Tags = {
	NAO_AGARRAVEL = "NaoAgarravel",
	FORCAR_SUSPENSO = "ForcarSuspenso",
}

-- ══════════════════════════════════════
-- Configuração padrão para detecção
-- ══════════════════════════════════════

Configs.DefaultConfig = {
	RayDistance = 8,

	-- Base no HumanoidRootPart
	HeadHeightOffset = 0,

	-- Varredura vertical de cima para baixo
	VerticalOffsets = { 3, 2.5, 2, 1.5, 1, 0.5, 0, -0.5, -1, -1.5, -2 },

	EdgeMode = "Top", -- "Top" ou "Bottom"

	-- Clearance no topo (espaço acima da borda — para AGARRAR)
	TopClearanceSize = Vector3.new(2.2, 0.4, 0.5),
	TopClearanceUpOffset = 0.21,
	TopClearanceNormalOffset = 0.1,

	-- Clearance frontal (espaço na frente da borda — para AGARRAR)
	FrontClearanceSize = Vector3.new(2.2, 3.0, 1.6),
	FrontClearanceUpOffset = -1.2,
	FrontClearanceNormalOffset = 0.9,

	-- Probe de pernas (verificar suporte abaixo)
	LegProbeDownOffset = 2.8,
	LegProbeStartNormalOffset = 0.75,
	LegProbeDistance = 1.8,
	LegSupportBoxEnabled = true, -- usa caixa para decidir IdleSuporte/IdleSuspenso
	LegSupportBoxSize = Vector3.new(1.9, 1.8, 1.4), -- volume de verificação de suporte das pernas
	LegSupportBoxDownOffset = 3.2, -- quanto desce da borda atual para testar suporte
	LegSupportBoxNormalOffset = -0.1, -- quanto aproxima da parede no teste de suporte
	-- Ajuste principal de suporte/suspenso:
	-- Rays horizontais empilhados na vertical (de baixo para cima).
	-- Configure aqui: ponto inicial no eixo Y, espacamento e distancia.
	LegProbeRayCount = 5,
	LegProbeStartYOffset = -2,
	LegProbeVerticalSpacing = 0.5,
	LegProbeRayDistance = 1.2,
	-- Legacy: se definido, sobrepoe o calculo por StartYOffset/Spacing.
	LegProbeVerticalOffsets = nil,

	-- ═══ Offsets do corpo (relativos ao HRP.Y) ═══
	TopoTorsoOffset = 1.2, -- HRP.Y + offset = linha do topo do torso
	BaseTorsoOffset = -0.5, -- HRP.Y + offset = linha da base do torso
	PernaRayOffset = -1.5, -- altura do ray de perna
	TorsoRayOffset = 1.0, -- altura do ray de torso

	-- ═══ Vault: clearance no destino (caixa verde) ═══
	VaultClearanceSize = Vector3.new(1.9, 5.0, 2.0),
	VaultClearanceForwardOffset = 1.5, -- studs pra frente além da borda
	VaultClearanceUpOffset = 2.5, -- studs acima da borda

	-- ═══ Vault: offset de movimento (posição ANTES do impulso) ═══
	-- O player é movido APENAS para cima antes do impulso
	VaultMoveUpOffset = 5.0, -- o quanto sobe antes de receber o impulso

	-- ═══ Vault: clearance do caminho (subida vertical) ═══
	VaultPathClearanceSize = Vector3.new(1.9, 1.0, 1.6),
	VaultPathCheckSteps = 3, -- quantos checks intermediários

	-- ═══ Vault: impulso (fase de sustentação com LinearVelocity) ═══
	VaultImpulseDuration = 0.25, -- duração (s) do LinearVelocity de impulso

	-- ═══ Limites de Distância (ação) ═══
	MaxGrabDistance = 4.5, -- quão perto precisa estar do ponto para agarrar
	MaxVaultDistance = 5.0, -- quão perto precisa estar para dar vault

	-- ═══ Filtro de peças pequenas ═══
	MinPartHeight = 0.6, -- peças com Size.Y menor que isso são ignoradas (grama, decoração)

	-- ═══ Movimento: Agarrar ═══
	GrabSurfaceOffset = 2.0, -- distância do HRP à superfície (studs) ao agarrar
	GrabVerticalOffset = -2.0, -- quão abaixo da borda o HRP fica (studs)
	-- Offsets específicos por estado de idle agarrado
	GrabSurfaceOffsetSuporte = 1.3,
	GrabVerticalOffsetSuporte = -2.4,
	GrabSurfaceOffsetSuspenso = 0.8,
	GrabVerticalOffsetSuspenso = -2.7,
	GrabTransitionTime = 0.25, -- tempo (s) pra player chegar na posição agarrada
	GrabIdleStartDelay = 0.02, -- atraso para iniciar idle após agarrar (menor = entra mais rápido)
	GrabIdleRecheckInterval = 0.2, -- intervalo (s) para reavaliar idle e sincronizar offset enquanto agarrado
	GrabCameraCollisionBypass = true, -- evita colisão da câmera desabilitando colisão local da part agarrada (sem transparência)

	-- ═══ Movimento: Vault Baixo ═══
	VaultBaixoImpulse = 50, -- magnitude da velocidade (studs/s) no VaultBaixo
	VaultBaixoTransitionTime = 0.15, -- duração (s) do movimento pra cima

	-- ═══ Movimento: Vault Médio ═══
	VaultMedioImpulse = 40, -- magnitude da velocidade (studs/s) no VaultMédio
	VaultMedioTransitionTime = 0.2, -- duração (s) do movimento pra cima

	-- ═══ Subir: detecção de superfície acima (area query) ═══
	SubirAreaSize = Vector3.new(3.5, 10.0, 6.0), -- volume de busca (X=lateral da parede, Y=altura, Z=profundidade)
	SubirAreaUpOffset = 5.0, -- deslocamento vertical do centro da caixa em relação à borda atual
	SubirProbeNormalOffset = 2.0, -- afastamento inicial da parede para posicionar a busca
	SubirMinVerticalDelta = 0.5, -- diferença mínima em Y para considerar uma borda acima
	SubirMaxAltura = 6.0, -- dist. máx. vertical para "Subir" (só W)
	SubirSaltoMaxAltura = 10.5, -- dist. máx. vertical para "SubirSalto" (W+Pulo)
	SubirTransitionTime = 0.3, -- tempo (s) de transição ao subir
	SubirSaltoMinActionTime = 0.55, -- tempo mínimo (s) para a ação SubirSalto tocar antes de voltar ao Idle
	SubirSaltoIdleFadeOut = 0.12, -- fade-out (s) para encerrar SubirSalto e entrar no Idle ao fim da transição
	SubirSaltoCheckCooldown = 0.25, -- cooldown curto da verificação de SubirSalto (evita spam de log em Heartbeat)
	SubirSaltoConfirmWindow = 0.9, -- tempo máximo para confirmar SubirSalto após ficar pendente
	SubirSaltoConfirmEdgeTolerance = 2.5, -- deslocamento máximo permitido da borda original ao confirmar
	MaxWallNormalY = 0.8, -- permite parede inclinada (montanha), ainda bloqueando superfícies quase horizontais

	-- ═══ Descer: detecção de superfície abaixo (area query) ═══
	DescerAreaSize = Vector3.new(6.0, 10.0, 6.0), -- volume de busca (X=lateral da parede, Y=altura, Z=profundidade)
	DescerAreaDownOffset = -5.0, -- deslocamento vertical do centro da caixa em relação à borda atual
	DescerProbeNormalOffset = 2.0, -- afastamento inicial da parede para posicionar a busca
	DescerMinVerticalDelta = 0.5, -- diferença mínima em Y para considerar uma borda abaixo
	DescerMaxAltura = 10.0, -- dist. máx. vertical para "Descer" (só S)
	DescerTransitionTime = 0.2, -- tempo (s) de transição ao descer

	-- ═══ Lateral: deslocamento agarrado direita/esquerda (area query) ═══
	LateralAreaSize = Vector3.new(12.0, 6.5, 6.0), -- volume de busca por direção (uma única caixa espelhada)
	LateralAreaUpOffset = -1.0, -- deslocamento vertical do centro da caixa lateral
	LateralAreaSideBias = 0.35, -- porcentagem da largura deslocada para o lado (0=centro no player, 0.5=caixa começa na borda atual)
	LateralTargetSideOffset = 3.2, -- alvo de deslocamento lateral para amostrar um ponto mais próximo (evita ir direto para a ponta distante)
	LateralProbeNormalOffset = 2.0, -- distância da parede para iniciar probe lateral
	LateralMaxProfundidade = 2.2, -- profundidade máxima (em relação ao plano da parede atual) para aceitar alvo lateral
	LateralTopEdgeTolerance = 2.0, -- quão perto o topo real da superfície deve estar da linha atual de agarrar
	LateralMaxHorizontal = 6, -- limite horizontal para classificar como Lateral
	LateralMaxVertical = 1.75, -- limite vertical para classificar como Lateral
	LateralSaltoMaxHorizontal = 11.0, -- limite horizontal para classificar como LateralSalto
	LateralSaltoMaxVertical = 2.8, -- limite vertical para classificar como LateralSalto
	LateralNormalMinDot = 0.5, -- semelhança mínima entre normal atual e candidata (evita virar quina abrupta)
	LateralAllowCorner = true, -- permite fazer curva em quina para face adjacente quando houver borda livre
	LateralPreferStraightOverCorner = true, -- quando houver múltiplos candidatos válidos, prioriza deslocamento lateral reto antes de curva
	LateralCornerRespectsBaseDepth = true, -- curvas também respeitam LateralMaxProfundidade (desative para comportamento antigo)
	LateralCornerMinDot = -0.15, -- dot mínimo para aceitar face adjacente em curva (mais baixo = mais permissivo)
	LateralCornerMaxProfundidade = 4.5, -- profundidade máxima permitida para curva em quina na mesma part
	LateralAllowExternalCorner = true, -- permite curva externa para outra parede/part com normal diferente
	LateralExternalCornerMinDot = -0.35, -- dot mínimo para aceitar curva externa (normal mais diferente da atual)
	LateralExternalCornerMaxProfundidade = 8.0, -- profundidade máxima permitida para curva externa
	LateralPathClearanceEnabled = true, -- valida espaço livre no caminho lateral até a borda alvo
	LateralPathClearanceSize = Vector3.new(1.8, 3.8, 1.4), -- caixa de validação do caminho lateral
	LateralPathSideDistance = 3.2, -- deslocamento lateral da caixa única de validação (não usa mais sweep até o destino)
	LateralMinSideDistance = 0.1, -- distância lateral mínima para aceitar candidato na direção
	LateralReverseTolerance = 0.05, -- tolerância para não aceitar candidato no sentido oposto ao input lateral
	LateralCandidateBoxMargin = 0.5, -- margem extra da caixa de query para aceitar edgePos (evita alvo muito fora da área)
	LateralPathClearanceNormalOffset = 1.2, -- offset normal da caixa lateral de clearance
	LateralPathClearanceHeightOffset = 0.0, -- offset vertical da caixa lateral de clearance
	LateralExternalPathRayEnabled = true, -- curva externa usa ray do player até o destino em vez de caixa lateral
	LateralExternalPathRayUpOffset = 0.2, -- ajuste em Y para origem/destino do ray de curva externa
	LateralExternalPathRayNormalOffset = 1.2, -- offset normal aplicado no destino do ray de curva externa
	LateralPathCheckSteps = 2, -- quantidade de checks intermediários no caminho lateral
	LateralTransitionTime = 0.2, -- tempo (s) da transição lateral
	LateralTransitionPhaseSplit = 0.55, -- proporção de tempo da fase 1 na transição lateral em duas fases
	LateralInputDotThreshold = 0.35, -- threshold de intenção para A/D
	DirectionUseCameraBasis = true, -- interpreta MoveDirection usando base da camera no parkour agarrado
	DirectionInputDeadzone = 0.2, -- deadzone horizontal minima para considerar intencao direcional
	DirectionForwardDotThreshold = 0.6, -- dot minimo de frente/tras para classificar eixo frontal
	DirectionLateralDotThreshold = 0.6, -- dot minimo de direita/esquerda para classificar eixo lateral
	DirectionDominanceMargin = 0.12, -- vantagem minima entre eixos para aceitar classificacao e evitar ambiguidades
	LateralJumpImpulse = 32, -- magnitude do salto lateral
	LateralJumpUpComponent = 0.6, -- componente vertical do salto lateral
	LateralSaltoCancelSpeedAbs = 1.3, -- velocidade absoluta para recuar a animacao de LateralSalto ao soltar input
	LateralSaltoAutoGrabWindow = 0.65, -- janela (s) para tentar auto-agarrar apos confirmar LateralSalto
	LateralSaltoAutoGrabStartDelay = 0.12, -- atraso inicial (s) antes de tentar auto-agarrar no LateralSalto
	LateralSaltoAutoGrabInterval = 0.05, -- intervalo (s) entre tentativas de auto-agarrar apos LateralSalto
	LateralSaltoAutoGrabMinLateralProgress = 1.8, -- progresso lateral mínimo (studs) para aceitar auto-grab após LateralSalto
	LateralSaltoAutoGrabMinTravel = 2.0, -- deslocamento total mínimo (studs) para aceitar auto-grab após LateralSalto

	-- ═══ Escalar: subir em cima da plataforma atual ═══
	-- Clearance de escalar: agora usa os MESMOS valores do Vault (VaultClearanceSize, VaultClearanceUpOffset, VaultClearanceForwardOffset)
	EscalarForwardOffset = 1.2, -- studs pra frente da borda ao escalar (posição final)
	EscalarUpOffset = 2.5, -- studs acima da borda (posição final)
	EscalarTransitionTime = 0.3, -- duração (s) da escalada
	EscalarVerticalFirstRatio = 0.5, -- proporção do tempo de Escalar usada para fase vertical
	EscalarFloorRayDistance = 5, -- distância do ray pra baixo para verificar chão
	EscalarFloorProbeUpOffset = 1.1, -- altura inicial dos rays de piso de escalar
	EscalarFloorProbeOffsets = { 0.0, 0.3, 0.7 }, -- offsets para frente testados no floor check (qualquer hit aprova)

	-- ═══ PuloTras: salto para trás estando agarrado ═══
	PuloTrasImpulse = 30, -- magnitude do impulso para trás (studs/s)
	PuloTrasUpComponent = 0.4, -- componente vertical do impulso (0-1)

	-- ═══ Descer: cooldown antes de soltar (evita conflito com PuloTras) ═══
	DescerHoldTime = 0.15, -- segundos que precisa segurar S antes de soltar
	DescerNoOptionReleaseDelay = 0.2, -- tempo adicional segurando S sem opção válida antes de realmente soltar

	-- ═══ Cooldown dinâmico por ação ═══
	CooldownDinamicoEnabled = true,
	ActionCooldowns = {
		Lateral = 1.0,
		LateralSalto = 2.0,
		Subir = 1.0,
		SubirSalto = 2.0,
		Descer = 0.5,
	},
	MinimumCooldowns = {
		Lateral = 0.5,
		LateralSalto = 2.0,
		Subir = 0.5,
		SubirSalto = 2.0,
		Descer = 0.25,
	},
	CooldownStreakReduction = 0.1, -- redução por repetição válida
	CooldownRepeatWindow = 1.5, -- janela para manter streak com toque rápido
	CooldownStreakMaxUses = 10, -- limite de contagem para bater no mínimo
	CooldownBlockedLogInterval = 0.25, -- intervalo mínimo entre logs de bloqueio por ação/direção
	SubirFailCooldown = 0.35, -- cooldown aplicado quando Subir/Escalar falha (evita spam de verificações)
	DescerFailCooldown = 0.2, -- cooldown curto de falha na tentativa de descer
	LateralNoSurfaceCooldown = 0.5, -- cooldown aplicado quando lateral falha por falta de superfície
	LateralNoSurfaceBackoff = 0.15, -- espera curta antes de refazer CheckLateral sem superfície válida
}

-- ══════════════════════════════════════
-- Merge de config parcial com defaults
-- ══════════════════════════════════════

function Configs.mergeConfig(config)
	if config and config[MERGED_SENTINEL] then
		return config
	end

	local final = table.clone(Configs.DefaultConfig)

	if config then
		for key, value in pairs(config) do
			final[key] = value
		end

		if config.VerticalOffsets == nil and config.LateralOffsets ~= nil then
			final.VerticalOffsets = config.LateralOffsets
		end
	end

	final[MERGED_SENTINEL] = true

	return final
end

return Configs
