local Configs = {}

-- ══════════════════════════════════════
-- Flags de Debug
-- ══════════════════════════════════════

Configs.DebugEnabled = true -- visuais (linhas, caixas, pontos)
Configs.DebugVerbose = true -- prints detalhados no console
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
	TopClearanceSize = Vector3.new(2.2, 0.4, 1.8),
	TopClearanceUpOffset = 0.21,
	TopClearanceNormalOffset = 0.45,

	-- Clearance frontal (espaço na frente da borda — para AGARRAR)
	FrontClearanceSize = Vector3.new(2.2, 3.0, 1.6),
	FrontClearanceUpOffset = -1.2,
	FrontClearanceNormalOffset = 0.9,

	-- Probe de pernas (verificar suporte abaixo)
	LegProbeDownOffset = 2.8,
	LegProbeStartNormalOffset = 0.75,
	LegProbeDistance = 1.8,

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
	GrabTransitionTime = 0.25, -- tempo (s) pra player chegar na posição agarrada

	-- ═══ Movimento: Vault Baixo ═══
	VaultBaixoImpulse = 50, -- magnitude da velocidade (studs/s) no VaultBaixo
	VaultBaixoTransitionTime = 0.15, -- duração (s) do movimento pra cima

	-- ═══ Movimento: Vault Médio ═══
	VaultMedioImpulse = 35, -- magnitude da velocidade (studs/s) no VaultMédio
	VaultMedioTransitionTime = 0.25, -- duração (s) do movimento pra cima

	-- ═══ Subir: detecção de superfície acima ═══
	SubirRayUpDistance = 12, -- distância máxima do ray vertical (para cima)
	SubirRayForwardCount = 15, -- quantidade de rays horizontais por coluna
	SubirRayForwardSpacing = 1.0, -- espaçamento vertical entre rays horizontais
	SubirRayForwardDistance = 6, -- distância dos rays horizontais (para frente/parede)
	SubirProbeNormalOffset = 2.0, -- studs de distância da parede para iniciar os rays (maior = detecta estruturas salientes)
	SubirMaxAltura = 6.0, -- dist. máx. vertical para "Subir" (só W)
	SubirSaltoMaxAltura = 10.5, -- dist. máx. vertical para "SubirSalto" (W+Pulo)
	SubirTransitionTime = 0.3, -- tempo (s) de transição ao subir
	SubirSaltoCheckCooldown = 0.25, -- cooldown curto da verificação de SubirSalto (evita spam de log em Heartbeat)
	SubirSaltoConfirmWindow = 0.35, -- tempo máximo para confirmar SubirSalto após ficar pendente
	SubirSaltoConfirmEdgeTolerance = 2.5, -- deslocamento máximo permitido da borda original ao confirmar
	MaxWallNormalY = 0.8, -- permite parede inclinada (montanha), ainda bloqueando superfícies quase horizontais

	-- ═══ Descer: detecção de superfície abaixo ═══
	DescerRayDownDistance = 12, -- distância máxima do ray vertical (para baixo)
	DescerRayForwardCount = 15, -- quantidade de rays horizontais por coluna
	DescerRayForwardSpacing = 1.0, -- espaçamento vertical entre rays horizontais
	DescerRayForwardDistance = 6, -- distância dos rays horizontais (para frente/parede)
	DescerProbeNormalOffset = 2.0, -- studs de distância da parede para iniciar os rays
	DescerMaxAltura = 6.0, -- dist. máx. vertical para "Descer" (só S)
	DescerTransitionTime = 0.3, -- tempo (s) de transição ao descer

	-- ═══ Lateral: deslocamento agarrado direita/esquerda ═══
	LateralRayDistance = 10.5, -- distância máxima de varredura lateral
	LateralRayCount = 9, -- quantidade de amostras laterais
	LateralRaySpacing = 2.0, -- espaçamento entre amostras laterais
	LateralForwardRayDistance = 8.0, -- distância do ray secundário para dentro da parede
	LateralProbeNormalOffset = 2.0, -- distância da parede para iniciar probe lateral
	LateralMaxVerticalDelta = 1.75, -- diferença vertical máxima permitida para snap lateral
	LateralNormalMinDot = 0.5, -- semelhança mínima entre normal atual e candidata (evita virar quina abrupta)
	LateralMaxTravelDistance = 4.5, -- limite de deslocamento total do alvo lateral por passo
	LateralTopEdgeTolerance = 1.5, -- quão perto o topo real da superfície deve estar da linha atual de agarrar
	LateralTransitionTime = 0.2, -- tempo (s) da transição lateral
	LateralInputDotThreshold = 0.35, -- threshold de intenção para A/D
	LateralJumpImpulse = 32, -- magnitude do salto lateral
	LateralJumpUpComponent = 0.45, -- componente vertical do salto lateral

	-- ═══ Escalar: subir em cima da plataforma atual ═══
	-- Clearance de escalar: agora usa os MESMOS valores do Vault (VaultClearanceSize, VaultClearanceUpOffset, VaultClearanceForwardOffset)
	EscalarForwardOffset = 1.2, -- studs pra frente da borda ao escalar (posição final)
	EscalarUpOffset = 2.5, -- studs acima da borda (posição final)
	EscalarTransitionTime = 0.35, -- duração (s) da escalada
	EscalarFloorRayDistance = 5, -- distância do ray pra baixo para verificar chão

	-- ═══ PuloTras: salto para trás estando agarrado ═══
	PuloTrasImpulse = 30, -- magnitude do impulso para trás (studs/s)
	PuloTrasUpComponent = 0.4, -- componente vertical do impulso (0-1)

	-- ═══ Descer: cooldown antes de soltar (evita conflito com PuloTras) ═══
	DescerHoldTime = 0.15, -- segundos que precisa segurar S antes de soltar

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
	CooldownStreakReduction = 0.05, -- redução por repetição válida
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
	local final = table.clone(Configs.DefaultConfig)

	if config then
		for key, value in pairs(config) do
			final[key] = value
		end

		if config.VerticalOffsets == nil and config.LateralOffsets ~= nil then
			final.VerticalOffsets = config.LateralOffsets
		end
	end

	return final
end

return Configs
