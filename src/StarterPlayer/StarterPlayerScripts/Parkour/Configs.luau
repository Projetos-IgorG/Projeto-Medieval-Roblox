local Configs = {}
local MERGED_SENTINEL = "__ParkourMergedConfig"

-- ══════════════════════════════════════
-- Flags de Debug
-- ══════════════════════════════════════

Configs.DebugEnabled = false -- visuais (linhas, caixas, pontos)
Configs.DebugVerbose = false -- prints detalhados no console
Configs.DebugLifetime = 2
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
	ClassificationRayDistance = 8, -- alcance dos rays XZ usados para classificar vault baixo/medio
	ClassificationRayExtraDistance = 0.75, -- margem extra para o ray passar da borda detectada

	-- Busca primária de obstáculo por grade de rays à frente
	ForwardRayGridRows = 7, -- fileiras verticais de rays
	ForwardRayGridColumns = 5, -- rays por fileira (horizontal)
	ForwardRayGridWidth = 4.5, -- largura total da grade (studs)
	ForwardRayGridHeight = 5.5, -- altura total da grade (studs)
	ForwardRayGridUpOffset = 0.8, -- deslocamento vertical do centro da grade
	ForwardRayGridDistance = 6, -- alcance (comprimento) de cada ray
	ForwardRayGridMaxPasses = 3, -- passes por ray para pular parts ignoradas
	ForwardRayGridVaultMedioStartRatio = 0.34, -- a partir desta altura relativa da grade, classifica como VaultMedio
	ForwardRayGridGrabStartRatio = 0.72, -- a partir desta altura relativa da grade, classifica como Agarrar
	ForwardObstacleSampleYOffset = 0.0, -- altura usada para amostrar a face mais próxima na part candidata
	ForwardObstacleMaxDistance = 9.0, -- limite de distância XZ para aceitar a borda candidata

	-- Clearance no topo (espaço acima da borda — para AGARRAR)
	TopClearanceSize = Vector3.new(2.2, 0.4, 0.5),
	TopClearanceUpOffset = 0.21,
	TopClearanceNormalOffset = 0.1,

	-- Clearance frontal (espaço na frente da borda — para AGARRAR)
	FrontClearanceSize = Vector3.new(2.2, 5.0, 1.6),
	FrontClearanceUpOffset = -2.4,
	FrontClearanceNormalOffset = 0.9,

	-- Probe de pernas (verificar suporte abaixo)
	LegProbeDownOffset = 2.8,
	LegProbeStartNormalOffset = 0.75,
	LegSupportRayDistance = 0.8, -- alcance de cada ray do suporte de pernas
	LegSupportRayOriginDownOffset = 3.5, -- quanto desce da borda atual para posicionar a origem-base dos rays
	LegSupportRayOriginForwardOffset = -0.1, -- deslocamento da origem-base para frente (em direção à parede)
	LegSupportRayHeights = { 0, -0.8 }, -- duas linhas verticais de rays: superior e inferior
	LegSupportRayLateralOffsets = { -0.7, 0.0, 0.7 }, -- três colunas laterais: esquerda, centro e direita
	LegSupportRayMaxPasses = 6, -- ignora superfícies decorativas no caminho e tenta o próximo hit do mesmo ray

	-- ═══ Offsets do corpo (relativos ao HRP.Y) ═══
	TopoTorsoOffset = 1.5, -- HRP.Y + offset = linha do topo do torso
	PernaRayOffset = -0.5, -- altura do ray de perna
	TorsoRayOffset = 1.0, -- altura do ray de torso

	-- ═══ Vault: clearance na borda (espaço pra passar) ═══
	VaultClearanceSize = Vector3.new(1.9, 4.0, 2.0),
	VaultEdgeClearanceUpOffset = 2.2, -- studs acima da borda para o CENTRO da caixa de edge clearance

	-- ═══ Vault: clearance no destino (caixa verde) ═══
	VaultClearanceForwardOffset = 2.0, -- studs pra frente além da borda (área estendida para verificar espaço livre)
	VaultClearanceUpOffset = 2.5, -- studs acima da borda (only affects destination check)

	-- ═══ Vault: offset de movimento (posição ANTES do impulso) ═══
	-- O player é movido APENAS para cima antes do impulso
	VaultMoveUpOffset = 5.0, -- o quanto sobe antes de receber o impulso

	-- ═══ Vault: impulso (fase de sustentação com LinearVelocity) ═══
	VaultImpulseDuration = 0.25, -- duração (s) do LinearVelocity de impulso

	-- ═══ Limites de Distância (ação) ═══
	MaxGrabDistance = 4.5, -- quão perto precisa estar do ponto para agarrar
	MaxGrabReachHeight = 6.0, -- altura máxima acima do HRP para considerar uma borda como alcançável (clamp para partes muito altas)
	MaxVaultDistance = 5.0, -- quão perto precisa estar para dar vault

	-- ═══ Filtro de peças pequenas ═══
	MinPartHeight = 0.6, -- peças com Size.Y menor que isso são ignoradas (grama, decoração)

	-- ═══ Movimento: Agarrar ═══
	GrabSurfaceOffset = 1.2, -- distância do HRP à superfície (studs) ao agarrar
	GrabVerticalOffset = -2.3, -- quão abaixo da borda o HRP fica (studs)
	GrabSurfaceSafetyMargin = 0.2, -- margem extra para garantir HRP fora da face da parede
	GrabSafetyProbeScale = 0.9, -- escala da caixa de teste (relativa ao HRP) para detectar penetração
	GrabSafetyPushStep = 0.15, -- passo de empurrão para fora da parede quando detectar penetração
	GrabSafetyMaxPushSteps = 6, -- limite de iterações de correção para evitar loop pesado
	GrabTransitionTime = 0.15, -- tempo (s) pra player chegar na posição agarrada (menor = idle entra mais rápido)
	GrabFinalReachDistance = 0.25, -- distância máxima para confirmar que chegou no alvo do grab
	GrabFinalSnapTimeout = 0.25, -- tempo máximo para forçar snap final e confirmar grab (menor = idle entra mais rápido)
	GrabMinSettleTime = 0.04, -- tempo mínimo antes de validar alcance final (evita confirmar cedo demais)
	GrabIdleStartDelay = 0.01, -- atraso para iniciar idle após agarrar (menor = entra mais rápido)
	GrabIdleRecheckInterval = 0.2, -- intervalo (s) para reavaliar idle e sincronizar offset enquanto agarrado
	IdleDebugVerbose = true, -- logs detalhados de decisao do idle (suporte vs suspenso)
	IdleDebugVisualEnabled = true, -- desenha probe de suporte/normal usado para decidir o idle
	IdleDebugStableLogInterval = 0.35, -- throttling dos logs quando o idle permanece estavel
	IdleDebugFlipWindow = 1.25, -- janela (s) para detectar ping-pong de idle
	IdleDebugFlipWarnThreshold = 4, -- quantidade de trocas na janela para emitir alerta de oscilacao
	IdleSwitchToSupportConfirmations = 2, -- checks consecutivos necessarios para trocar para IdleSuporte
	IdleSwitchToSuspensoConfirmations = 2, -- checks consecutivos necessarios para trocar para IdleSuspenso
	IdleSwitchMinInterval = 0.45, -- intervalo minimo (s) entre trocas de idle para reduzir ping-pong

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
	SubirMaxHorizontalDistance = 5.5, -- deslocamento máximo XZ permitido para um candidato de subir
	SubirMaxProfundidade = 1.5, -- profundidade máxima na direção da parede atual para "Subir" (só W)
	SubirSaltoMaxProfundidade = 2.4, -- profundidade máxima na direção da parede atual para "SubirSalto" (W+Pulo, permite bordas mais afastadas)
	SubirMaxAltura = 6.0, -- dist. máx. vertical para "Subir" (só W)
	SubirSaltoMaxAltura = 10.5, -- dist. máx. vertical para "SubirSalto" (W+Pulo)
	SubirTransitionTime = 0.3, -- tempo (s) de transição ao subir
	SubirSaltoMinActionTime = 0.55, -- tempo mínimo (s) para a ação SubirSalto tocar antes de voltar ao Idle
	SubirSaltoIdleFadeOut = 0.12, -- fade-out (s) para encerrar SubirSalto e entrar no Idle ao fim da transição
	SubirSaltoConfirmWindow = 0.9, -- tempo máximo para confirmar SubirSalto após ficar pendente
	SubirSaltoConfirmEdgeTolerance = 2.5, -- deslocamento máximo permitido da borda original ao confirmar
	SubirSaltoPreferTimeout = 0.77, -- ao segurar frente com SubirSalto+Escalar válidos, converte para Escalar automático
	MaxWallNormalY = 0.8, -- permite parede inclinada (montanha), ainda bloqueando superfícies quase horizontais

	-- ═══ Descer: detecção de superfície abaixo (area query) ═══
	DescerAreaSize = Vector3.new(2.0, 10.0, 6.0), -- volume de busca (X=lateral da parede, Y=altura, Z=profundidade)
	DescerAreaDownOffset = -5.0, -- deslocamento vertical do centro da caixa em relação à borda atual
	DescerProbeNormalOffset = 2.0, -- afastamento inicial da parede para posicionar a busca
	DescerMinVerticalDelta = 0.5, -- diferença mínima em Y para considerar uma borda abaixo
	DescerMaxAltura = 10.0, -- dist. máx. vertical para "Descer" (só S)
	DescerTransitionTime = 0.35, -- tempo (s) de transição ao descer

	-- ═══ Lateral: deslocamento agarrado direita/esquerda (area query) ═══
	LateralAreaSize = Vector3.new(12.0, 7, 6.0), -- volume de busca por direção (uma única caixa espelhada)
	LateralAreaUpOffset = -1.5, -- deslocamento vertical do centro da caixa lateral
	LateralAreaSideBias = 0.35, -- porcentagem da largura deslocada para o lado (0=centro no player, 0.5=caixa começa na borda atual)
	LateralTargetSideOffset = 3.2, -- alvo de deslocamento lateral para amostrar um ponto mais próximo (evita ir direto para a ponta distante)
	LateralProbeNormalOffset = 2.0, -- distância da parede para iniciar probe lateral
	LateralMaxProfundidade = 2.2, -- profundidade máxima (em relação ao plano da parede atual) para aceitar alvo lateral
	LateralTopEdgeTolerance = 2.0, -- quão perto o topo real da superfície deve estar da linha atual de agarrar
	LateralMaxHorizontal = 6, -- limite horizontal para classificar como Lateral
	LateralMaxVertical = 2.06, -- limite vertical para classificar como Lateral
	LateralSaltoMaxHorizontal = 11.0, -- limite horizontal para classificar como LateralSalto
	LateralSaltoMaxVertical = 4.0, -- limite vertical para classificar como LateralSalto
	LateralSaltoTopEdgeTolerance = 4.0, -- tolerância de diferença vertical do topo para o filtro inicial de candidatos de LateralSalto
	LateralNormalMinDot = 0.5, -- semelhança mínima entre normal atual e candidata (evita virar quina abrupta)
	LateralCornerMinDot = -0.15, -- dot mínimo para aceitar face adjacente em curva (mais baixo = mais permissivo)
	LateralCornerMaxProfundidade = 4.5, -- profundidade máxima permitida para curva em quina na mesma part
	LateralExternalCornerMinDot = -0.35, -- dot mínimo para aceitar curva externa (normal mais diferente da atual)
	LateralExternalCornerMaxProfundidade = 8.0, -- profundidade máxima permitida para curva externa
	LateralPathClearanceSize = Vector3.new(1.8, 3.8, 1.4), -- caixa de validação do caminho lateral
	LateralPathClearanceNormalOffset = 1.2, -- offset normal da caixa lateral de clearance
	LateralPathClearanceHeightOffset = -1.3, -- offset vertical da caixa lateral de clearance
	LateralPathSideDistance = 2.2, -- deslocamento lateral da caixa única de validação (não usa mais sweep até o destino)
	LateralMinSideDistance = 0.1, -- distância lateral mínima para aceitar candidato na direção
	LateralSaltoMinSideDistance = 1.0, -- distância lateral mínima exclusiva para aceitar LateralSalto (evita salto quase no mesmo alinhamento lateral)
	LateralReverseTolerance = 0.05, -- tolerância para não aceitar candidato no sentido oposto ao input lateral
	LateralCandidateBoxMargin = 0.5, -- margem extra da caixa de query para aceitar edgePos (evita alvo muito fora da área)
	LateralExternalPathRayUpOffset = 0.2, -- ajuste em Y para origem/destino do ray de curva externa
	LateralExternalPathRayNormalOffset = 1.2, -- offset normal aplicado no destino do ray de curva externa
	LateralTransitionTime = 0.35, -- tempo (s) da transição lateral
	LateralSaltoTransitionTime = 0.5, -- tempo (s) da transição do salto lateral
	LateralTransitionPhaseSplit = 0.55, -- proporção de tempo da fase 1 na transição lateral em duas fases
	LateralInputDotThreshold = 0.35, -- threshold de intenção para A/D
	DirectionInputDeadzone = 0.2, -- deadzone horizontal minima para considerar intencao direcional
	DirectionForwardDotThreshold = 0.6, -- dot minimo de frente/tras para classificar eixo frontal
	DirectionLateralDotThreshold = 0.6, -- dot minimo de direita/esquerda para classificar eixo lateral
	DirectionDominanceMargin = 0.12, -- vantagem minima entre eixos para aceitar classificacao e evitar ambiguidades
	LateralJumpImpulse = 32, -- magnitude do salto lateral
	LateralJumpUpComponent = 0.6, -- componente vertical do salto lateral
	LateralSaltoCancelSpeedAbs = 1.3, -- velocidade absoluta para recuar a animacao de LateralSalto ao soltar input
	LateralSaltoPreferTimeout = 0.77, -- segurando lateral nesse estado, após esse tempo executa curva interna automaticamente

	-- ═══ Escalar: subir em cima da plataforma atual ═══
	EscalarMaxVerticalDistance = 3.0,
	EscalarForwardOffset = 1.2, -- studs pra frente da borda ao escalar (posição final)
	EscalarUpOffset = 2.5, -- studs acima da borda (posição final)
	EscalarTransitionTime = 0.35, -- tempo (s) de transição ao escalar
	EscalarVerticalFirstRatio = 0.2, -- proporção do tempo de transição dedicada ao movimento vertical (vs. horizontal)
	EscalarFinalSnapDistance = 0.2, -- distância máxima para considerar que alcançou o alvo sem depender só do tempo
	EscalarFinalSnapTimeout = 0.6, -- tempo máximo (s) para forçar snap final mesmo se não convergir

	-- Caixa de clearance do Escalar: verifica se há espaço para o player subir por cima
	EscalarClearanceSize = Vector3.new(1.9, 4.0, 2.0), -- largura x altura x profundidade
	EscalarClearanceUpOffset = 2.5, -- centro da caixa: studs acima da borda (onde o player vai ficar)
	EscalarClearanceForwardOffset = -0.3, -- centro da caixa: studs para dentro da plataforma

	-- ═══ PuloTras: salto para trás estando agarrado ═══
	PuloTrasImpulse = 40, -- magnitude do impulso para trás (studs/s)
	PuloTrasUpComponent = 0.7, -- componente vertical do impulso (0-1)

	-- ═══ Descer: hold antes de soltar (evita conflito com PuloTras) ═══
	DescerHoldTime = 0.15, -- segundos que precisa segurar S antes de soltar
	DescerNoOptionReleaseDelay = 0.2, -- tempo adicional segurando S sem opção válida antes de realmente soltar

	-- ═══ Momentum: velocidade progressiva por ações consecutivas ═══
	MomentumBaseSpeed = 1.0, -- velocidade base da animação e transição
	MomentumMaxSpeed = 1.3, -- velocidade máxima (após 6 ações consecutivas)
	MomentumIncrement = 0.05, -- aumento por ação executada com sucesso
	MomentumDecayWindow = 2.0, -- segundos sem ação para resetar o momentum

	-- ═══ Fail-throttle: anti-spam de verificações que falharam ═══
	SubirFailThrottle = 0.35, -- throttle quando Subir/Escalar falha (evita spam de raycasts)
	DescerFailThrottle = 0.2, -- throttle curto de falha na tentativa de descer
	LateralNoSurfaceThrottle = 0.5, -- throttle quando lateral falha por falta de superfície
	LateralNoSurfaceBackoff = 0.15, -- espera curta antes de refazer CheckLateral sem superfície válida
}

-- ══════════════════════════════════════
-- Merge de config parcial com defaults (cached para nil)
-- ══════════════════════════════════════

local _cachedDefaultMerge = nil

--- Invalida o cache de mergeConfig e atualiza tabelas já entregues in-place
function Configs.invalidateCache()
	if _cachedDefaultMerge then
		-- Atualiza in-place para que referências existentes vejam os novos valores
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
