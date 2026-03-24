--[[
	Movimento.luau
	Módulo de movimento do sistema de Parkour.
	Responsável por executar Agarrar, VaultBaixo, VaultMédio,
	Subir, SubirSalto, Escalar e PuloTras.

	Vault e Escalar usam LinearVelocity para impulso suave (sem tremor em 1ª pessoa).
	Constraints são limpas automaticamente (anti memory leak).
]]

local Configs = require(script.Parent:WaitForChild("Configs"))
local Utilidades = require(script.Parent:WaitForChild("Utilidades"))
local Analisador = require(script.Parent:WaitForChild("Analisador"))

local Movimento = {}

-- ══════════════════════════════════════
-- Estado Interno
-- ══════════════════════════════════════

local estado = {
	EmAcao = false,
	Agarrado = false,
	ActiveConstraints = {} :: { Instance },
	DiedConnection = nil :: RBXScriptConnection?,
	CurrentCharacter = nil :: Model?,
	SavedCollisions = {} :: { [BasePart]: boolean },
	GrabData = nil, -- { EdgePosition, Normal, Part, Config }
}

local lateralNoSurfaceCache = {
	Direction = nil,
	EdgePosition = nil,
	Normal = nil,
	ExpiresAt = 0,
}

local function clearLateralNoSurfaceCache()
	lateralNoSurfaceCache.Direction = nil
	lateralNoSurfaceCache.EdgePosition = nil
	lateralNoSurfaceCache.Normal = nil
	lateralNoSurfaceCache.ExpiresAt = 0
end

local function isSameGrabForLateralCache(direction, edgePosition, normal)
	if lateralNoSurfaceCache.ExpiresAt <= 0 then
		return false
	end

	if lateralNoSurfaceCache.Direction ~= direction then
		return false
	end

	if not lateralNoSurfaceCache.EdgePosition or not lateralNoSurfaceCache.Normal then
		return false
	end

	if not edgePosition or not normal then
		return false
	end

	local sameEdge = (lateralNoSurfaceCache.EdgePosition - edgePosition).Magnitude <= 0.15
	local sameNormal = lateralNoSurfaceCache.Normal:Dot(normal.Unit) >= 0.98
	return sameEdge and sameNormal
end

-- ══════════════════════════════════════
-- Cleanup (Anti Memory Leak)
-- ══════════════════════════════════════

local function destroyConstraints()
	for _, constraint in ipairs(estado.ActiveConstraints) do
		if constraint and constraint.Parent then
			constraint:Destroy()
		end
	end
	table.clear(estado.ActiveConstraints)
end

local function removeConstraint(constraint)
	if constraint and constraint.Parent then
		constraint:Destroy()
	end
	local idx = table.find(estado.ActiveConstraints, constraint)
	if idx then
		table.remove(estado.ActiveConstraints, idx)
	end
end

-- ══════════════════════════════════════
-- Colisão: Desabilitar / Restaurar
-- ══════════════════════════════════════

local function desabilitarColisao(character)
	table.clear(estado.SavedCollisions)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part.CanCollide then
			estado.SavedCollisions[part] = true
			part.CanCollide = false
		end
	end
end

local function restaurarColisao()
	for part, _ in pairs(estado.SavedCollisions) do
		if part and part.Parent then
			part.CanCollide = true
		end
	end
	table.clear(estado.SavedCollisions)
end

-- ══════════════════════════════════════
-- Humanoid State Reset
-- ══════════════════════════════════════

local function resetHumanoidState(character)
	if not character then
		return
	end
	local humanoid = character:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.AutoRotate = true
		humanoid.PlatformStand = false
	end
end

local function isCharacterAlive(character)
	if not character or not character.Parent then
		return false
	end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then
		return false
	end

	return humanoid.Health > 0
end

local function fullCleanup()
	destroyConstraints()
	restaurarColisao()
	clearLateralNoSurfaceCache()

	if estado.CurrentCharacter then
		resetHumanoidState(estado.CurrentCharacter)
	end

	if estado.DiedConnection then
		estado.DiedConnection:Disconnect()
		estado.DiedConnection = nil
	end

	estado.EmAcao = false
	estado.Agarrado = false
	estado.CurrentCharacter = nil
	estado.GrabData = nil
end

-- ══════════════════════════════════════
-- Helpers: Criar Constraints
-- ══════════════════════════════════════

local function criarAlignPosition(hrp, targetPosition, responsiveness)
	local align = Instance.new("AlignPosition")
	align.Mode = Enum.PositionAlignmentMode.OneAttachment
	align.Attachment0 = hrp:FindFirstChild("RootAttachment")
		or hrp:FindFirstChildOfClass("Attachment")
	align.Position = targetPosition
	align.MaxForce = 100000
	align.MaxVelocity = math.huge
	align.Responsiveness = responsiveness or 40
	align.Parent = hrp

	table.insert(estado.ActiveConstraints, align)
	return align
end

local function criarAlignOrientation(hrp, targetCFrame, responsiveness)
	local align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = hrp:FindFirstChild("RootAttachment")
		or hrp:FindFirstChildOfClass("Attachment")
	align.CFrame = targetCFrame
	align.MaxTorque = 100000
	align.Responsiveness = responsiveness or 40
	align.Parent = hrp

	table.insert(estado.ActiveConstraints, align)
	return align
end

--- Cria um LinearVelocity com auto-destruição.
--- Conceito igual ao Dash: aplica velocidade constante na direção, sem definir trajetória.
local function criarLinearVelocity(hrp, velocity, duracao)
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = hrp:FindFirstChild("RootAttachment")
		or hrp:FindFirstChildOfClass("Attachment")
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = 100000
	lv.VectorVelocity = velocity
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = hrp

	table.insert(estado.ActiveConstraints, lv)

	-- Auto-destruir após duração
	task.delay(duracao, function()
		removeConstraint(lv)
	end)

	return lv
end

-- ══════════════════════════════════════
-- Conectar cleanup no Died
-- ══════════════════════════════════════

local function conectarDied(character)
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then
		return
	end

	if estado.DiedConnection then
		estado.DiedConnection:Disconnect()
	end

	estado.DiedConnection = humanoid.Died:Once(function()
		fullCleanup()
	end)
end

-- ══════════════════════════════════════
-- Calcular posição de Agarrar
-- ══════════════════════════════════════

local function calcularPosicaoGrab(edgePosition, normal, config)
	local finalConfig = Configs.mergeConfig(config)

	local posicao = edgePosition
		+ Vector3.yAxis * finalConfig.GrabVerticalOffset
		+ normal.Unit * finalConfig.GrabSurfaceOffset

	local lookTarget = posicao - normal.Unit
	local orientacao = CFrame.lookAt(posicao, lookTarget, Vector3.yAxis)

	return posicao, orientacao
end

local function getLateralDirection(normal, direcao)
	local wallForward = -normal.Unit
	local right = wallForward:Cross(Vector3.yAxis)

	if right.Magnitude < 0.05 then
		right = Vector3.xAxis
	else
		right = right.Unit
	end

	if direcao == "Esquerda" then
		return -right
	end

	return right
end

-- ══════════════════════════════════════
-- Executar: Agarrar
-- ══════════════════════════════════════

local function executarAgarrar(result, config)
	local finalConfig = Configs.mergeConfig(config)
	local character = result.Character
	local hrp = Utilidades.getCharacterParts(character)
	local humanoid = character:FindFirstChild("Humanoid")

	if not hrp or not humanoid then
		return false
	end

	estado.EmAcao = true
	estado.Agarrado = false
	estado.CurrentCharacter = character

	conectarDied(character)

	-- Travar o humanoid
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true

	-- Calcular posição alvo
	local posAlvo, cfAlvo = calcularPosicaoGrab(
		result.EdgePosition,
		result.Normal,
		finalConfig
	)

	-- Criar constraints para grudar o player
	local alignPos = criarAlignPosition(hrp, posAlvo, 1 / finalConfig.GrabTransitionTime * 10)
	local alignOri = criarAlignOrientation(hrp, cfAlvo, 1 / finalConfig.GrabTransitionTime * 10)

	-- Zerar velocidade atual para transição suave
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero

	-- Salvar dados do grab para ações futuras (Subir, Escalar, PuloTras)
	estado.GrabData = {
		EdgePosition = result.EdgePosition,
		Normal = result.Normal,
		Part = result.Part or (result.Result and result.Result.Instance),
		IdleMode = result.IdleMode,
		LateralState = nil,
		Config = finalConfig,
	}

	-- Marcar como agarrado após tempo de transição
	task.delay(finalConfig.GrabTransitionTime, function()
		if alignPos.Parent and alignOri.Parent and isCharacterAlive(character) then
			estado.Agarrado = true
			estado.EmAcao = false
		end
	end)

	return true
end

-- ══════════════════════════════════════
-- Executar: Vault (Baixo e Médio)
-- Fase 1: AlignPosition move o player APENAS para cima (sem colisão)
-- Fase 2: Aplica impulso via LinearVelocity (conceito do Dash)
--         Não define trajetória, apenas aplica velocidade constante
-- ══════════════════════════════════════

local function executarVault(result, _config, impulso, transitionTime)
	local character = result.Character
	local hrp = Utilidades.getCharacterParts(character)
	local humanoid = character:FindFirstChild("Humanoid")

	if not hrp or not humanoid then
		return false
	end

	local finalConfig = Configs.mergeConfig(_config)

	estado.EmAcao = true
	estado.CurrentCharacter = character

	conectarDied(character)

	-- Desabilitar colisão para não travar no obstáculo
	desabilitarColisao(character)

	-- Travar humanoid durante a transição
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true

	-- Posição final: APENAS acima da borda (sem offset horizontal)
	local posFinal = result.PosFinal or result.EdgePosition
	local look = result.LookVector or hrp.CFrame.LookVector

	-- Fase 1: AlignPosition leva o player para cima suavemente
	local responsiveness = 1 / transitionTime * 12
	local alignPos = criarAlignPosition(hrp, posFinal, responsiveness)
	local alignOri = criarAlignOrientation(
		hrp,
		CFrame.lookAt(posFinal, posFinal + look, Vector3.yAxis),
		responsiveness
	)

	-- Zerar velocidade para transição limpa
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero

	-- Fase 2: Após chegar na posição (acima da borda), aplicar impulso via LinearVelocity
	task.delay(transitionTime, function()
		if not isCharacterAlive(character) then
			removeConstraint(alignPos)
			removeConstraint(alignOri)
			estado.EmAcao = false
			return
		end

		-- Destruir as constraints de posicionamento
		removeConstraint(alignPos)
		removeConstraint(alignOri)

		-- Restaurar colisão e humanoid
		humanoid.AutoRotate = true
		humanoid.PlatformStand = false
		restaurarColisao()

		-- Impulso via LinearVelocity (frente + cima)
		local lookFlat = Vector3.new(look.X, 0, look.Z).Unit
		local impulseVel = lookFlat * impulso + Vector3.new(0, impulso * 0.4, 0)

		criarLinearVelocity(hrp, impulseVel, finalConfig.VaultImpulseDuration)

		estado.EmAcao = false
	end)

	return true
end

-- ══════════════════════════════════════
-- Executar: Subir (move para nova superfície acima)
-- Destrói constraints antigos e cria novos
-- ══════════════════════════════════════

local function executarSubir(novaEdgePos, novaNormal, config)
	local finalConfig = Configs.mergeConfig(config)
	local character = estado.CurrentCharacter
	if not character then
		return false
	end

	local hrp = Utilidades.getCharacterParts(character)
	if not hrp then
		return false
	end

	estado.EmAcao = true
	estado.Agarrado = false

	-- Destruir constraints anteriores
	destroyConstraints()

	-- Calcular nova posição de grab
	local posAlvo, cfAlvo = calcularPosicaoGrab(novaEdgePos, novaNormal, finalConfig)

	-- Criar novos constraints para a nova posição
	local responsiveness = 1 / finalConfig.SubirTransitionTime * 10
	local alignPos = criarAlignPosition(hrp, posAlvo, responsiveness)
	local alignOri = criarAlignOrientation(hrp, cfAlvo, responsiveness)

	-- Zerar velocidade
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero

	-- Atualizar dados do grab
	estado.GrabData = {
		EdgePosition = novaEdgePos,
		Normal = novaNormal,
		Part = estado.GrabData and estado.GrabData.Part,
		IdleMode = estado.GrabData and estado.GrabData.IdleMode,
		LateralState = nil,
		Config = finalConfig,
	}

	-- Marcar como agarrado após transição
	task.delay(finalConfig.SubirTransitionTime, function()
		if alignPos.Parent and alignOri.Parent and isCharacterAlive(character) then
			estado.Agarrado = true
			estado.EmAcao = false
		end
	end)

	return true
end

local function executarDescer(novaEdgePos, novaNormal, novaPart, config)
	local finalConfig = Configs.mergeConfig(config)
	local character = estado.CurrentCharacter
	if not character then
		return false
	end

	local hrp = Utilidades.getCharacterParts(character)
	if not hrp then
		return false
	end

	estado.EmAcao = true
	estado.Agarrado = false

	destroyConstraints()

	local posAlvo, cfAlvo = calcularPosicaoGrab(novaEdgePos, novaNormal, finalConfig)

	local responsiveness = 1 / finalConfig.DescerTransitionTime * 10
	local alignPos = criarAlignPosition(hrp, posAlvo, responsiveness)
	local alignOri = criarAlignOrientation(hrp, cfAlvo, responsiveness)

	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero

	estado.GrabData = {
		EdgePosition = novaEdgePos,
		Normal = novaNormal,
		Part = novaPart or (estado.GrabData and estado.GrabData.Part),
		IdleMode = estado.GrabData and estado.GrabData.IdleMode,
		LateralState = nil,
		Config = finalConfig,
	}

	task.delay(finalConfig.DescerTransitionTime, function()
		if alignPos.Parent and alignOri.Parent and isCharacterAlive(character) then
			estado.Agarrado = true
			estado.EmAcao = false
		end
	end)

	return true
end

local function executarLateral(lateralResult, config)
	local finalConfig = Configs.mergeConfig(config)
	local character = estado.CurrentCharacter
	if not character then
		return false
	end

	local hrp = Utilidades.getCharacterParts(character)
	if not hrp then
		return false
	end

	local currentEdgePos = estado.GrabData and estado.GrabData.EdgePosition
	if currentEdgePos and lateralResult.EdgePosition then
		local maxTravel = finalConfig.LateralMaxTravelDistance or 4.5
		local travel = (lateralResult.EdgePosition - currentEdgePos).Magnitude
		if travel > maxTravel then
			print("[Parkour] Lateral bloqueado por segurança | Travel:", string.format("%.2f", travel), "| Max:", maxTravel)
			return false
		end
	end

	estado.EmAcao = true
	estado.Agarrado = false

	destroyConstraints()

	local posAlvo = calcularPosicaoGrab(
		lateralResult.EdgePosition,
		lateralResult.Normal,
		finalConfig
	)
	local rotAtual = hrp.CFrame - hrp.CFrame.Position
	local cfAlvo = CFrame.new(posAlvo) * rotAtual

	local responsiveness = 1 / finalConfig.LateralTransitionTime * 10
	local alignPos = criarAlignPosition(hrp, posAlvo, responsiveness)
	local alignOri = criarAlignOrientation(hrp, cfAlvo, responsiveness)

	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero

	estado.GrabData = {
		EdgePosition = lateralResult.EdgePosition,
		Normal = lateralResult.Normal,
		Part = lateralResult.Part,
		IdleMode = lateralResult.IdleMode,
		LateralState = lateralResult.Estado,
		Config = finalConfig,
	}

	task.delay(finalConfig.LateralTransitionTime, function()
		if alignPos.Parent and alignOri.Parent and isCharacterAlive(character) then
			estado.Agarrado = true
			estado.EmAcao = false
		end
	end)

	return true
end

-- ══════════════════════════════════════
-- Executar: Escalar (subir em cima da plataforma)
-- Move o player diretamente para PosFinal (acima + pra frente da borda)
-- Sem impulso — apenas AlignPosition para posição final
-- ══════════════════════════════════════

local function executarEscalar(escalarResult, config)
	local finalConfig = Configs.mergeConfig(config)
	local character = estado.CurrentCharacter
	if not character then
		return false
	end

	local hrp = Utilidades.getCharacterParts(character)
	local humanoid = character:FindFirstChild("Humanoid")
	if not hrp or not humanoid then
		return false
	end

	estado.EmAcao = true
	estado.Agarrado = false

	-- Destruir constraints anteriores (do grab)
	destroyConstraints()

	-- Desabilitar colisão para subir sem travar
	desabilitarColisao(character)

	-- Calcular posições das duas fases
	local normal = escalarResult.Normal or (estado.GrabData and estado.GrabData.Normal) or hrp.CFrame.LookVector
	local look = -normal.Unit -- direção para dentro da plataforma (frente)

	-- Fase 1: subir para cima da borda (sem offset pra frente)
	local posUp = escalarResult.EdgePosition + Vector3.yAxis * finalConfig.EscalarUpOffset

	-- Fase 2: mover pra frente na posição final
	local posFinal = escalarResult.PosFinal

	local halfTime = finalConfig.EscalarTransitionTime * 0.5
	local responsiveness = 1 / halfTime * 12

	-- Orientação: olhar para frente durante toda a escalada
	local targetOri = CFrame.lookAt(posFinal, posFinal + look, Vector3.yAxis)

	-- Fase 1: AlignPosition leva o player para CIMA
	local alignPos = criarAlignPosition(hrp, posUp, responsiveness)
	local alignOri = criarAlignOrientation(hrp, targetOri, responsiveness)

	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero

	-- Fase 2: Após subir, mover pra FRENTE
	task.delay(halfTime, function()
		if alignPos.Parent and isCharacterAlive(character) then
			alignPos.Position = posFinal
		end
	end)

	-- Após transição completa, restaurar tudo
	task.delay(finalConfig.EscalarTransitionTime, function()
		if not isCharacterAlive(character) then
			removeConstraint(alignPos)
			removeConstraint(alignOri)
			estado.EmAcao = false
			return
		end

		removeConstraint(alignPos)
		removeConstraint(alignOri)

		humanoid.AutoRotate = true
		humanoid.PlatformStand = false
		restaurarColisao()

		hrp.AssemblyLinearVelocity = Vector3.zero

		estado.EmAcao = false
		estado.GrabData = nil
		estado.CurrentCharacter = nil
	end)

	return true
end

-- ══════════════════════════════════════
-- Executar: PuloTras (salto para trás)
-- Solta + impulso na direção da normal (afastando da parede)
-- ══════════════════════════════════════

local function executarPuloTras(config)
	local finalConfig = Configs.mergeConfig(config)
	local character = estado.CurrentCharacter
	if not character then
		return false
	end

	local hrp = Utilidades.getCharacterParts(character)
	local humanoid = character:FindFirstChild("Humanoid")
	if not hrp or not humanoid then
		return false
	end

	-- Pegar a normal antes de limpar
	local normal = estado.GrabData and estado.GrabData.Normal or hrp.CFrame.LookVector

	-- Limpar tudo (soltar)
	fullCleanup()

	-- Direção do impulso: normal (para longe da parede) + componente pra cima
	local impulseDir = (normal.Unit + Vector3.yAxis * finalConfig.PuloTrasUpComponent).Unit
	local impulseVel = impulseDir * finalConfig.PuloTrasImpulse

	hrp.AssemblyLinearVelocity = impulseVel

	-- Sustentação via LinearVelocity (como Dash)
	criarLinearVelocity(hrp, impulseVel, 0.2)

	return true
end

local function executarPuloLateral(direcao, config)
	local finalConfig = Configs.mergeConfig(config)
	local character = estado.CurrentCharacter
	if not character then
		return false
	end

	local hrp = Utilidades.getCharacterParts(character)
	if not hrp then
		return false
	end

	local normal = estado.GrabData and estado.GrabData.Normal or -hrp.CFrame.LookVector
	local lateralDir = getLateralDirection(normal, direcao)

	fullCleanup()

	local impulseDir = (lateralDir + Vector3.yAxis * finalConfig.LateralJumpUpComponent).Unit
	local impulseVel = impulseDir * finalConfig.LateralJumpImpulse

	hrp.AssemblyLinearVelocity = impulseVel
	criarLinearVelocity(hrp, impulseVel, 0.2)

	return true
end

-- ══════════════════════════════════════
-- API Pública
-- ══════════════════════════════════════

function Movimento.Executar(parkourResult, config)
	if not parkourResult or not parkourResult.Aprovado then
		return false
	end

	if estado.EmAcao then
		return false
	end

	local acao = parkourResult.Acao
	local finalConfig = Configs.mergeConfig(config)

	if acao == "Agarrar" then
		return executarAgarrar(parkourResult, finalConfig)
	elseif acao == "VaultBaixo" then
		return executarVault(
			parkourResult,
			finalConfig,
			finalConfig.VaultBaixoImpulse,
			finalConfig.VaultBaixoTransitionTime
		)
	elseif acao == "VaultMedio" then
		return executarVault(
			parkourResult,
			finalConfig,
			finalConfig.VaultMedioImpulse,
			finalConfig.VaultMedioTransitionTime
		)
	end

	return false
end

function Movimento.Soltar()
	if not estado.Agarrado and not estado.EmAcao then
		return
	end
	fullCleanup()
end

-- Tentar Subir: detecta superfície acima e move para ela
-- Retorna: ok, tipo, subirResult, escalarDebug, subirDebug
function Movimento.TentarSubir()
	if not estado.Agarrado or estado.EmAcao then
		return false, nil
	end

	local grabData = estado.GrabData
	if not grabData then
		return false, nil
	end

	local character = estado.CurrentCharacter
	if not character then
		return false, nil
	end

	-- Primeiro: verificar se pode escalar (subir em cima da plataforma atual)
	-- Usa CheckEscalar que verifica se o player CABE EM CIMA da plataforma + tem chão
	local escalarResult = Analisador.CheckEscalar(
		character,
		grabData.EdgePosition,
		grabData.Normal,
		grabData.Part,
		grabData.Config
	)

	if escalarResult and escalarResult.CanEscalar then
		-- Se cabe em cima, escalar ao invés de subir
		local ok = executarEscalar(escalarResult, grabData.Config)
		if ok then
			print("[Parkour] Escalar para cima da plataforma")
		end
		return ok, "Escalar", nil, escalarResult
	end

	-- Segundo: verificar se tem superfície acima para subir (agarrar mais alto)
	local subirResult = Analisador.CheckSubir(
		character,
		grabData.EdgePosition,
		grabData.Normal,
		grabData.Config
	)

	if not subirResult or not subirResult.CanSubir then
		-- Retornar debug data mesmo quando falha (para visualização)
		return false, nil, subirResult, escalarResult
	end

	if subirResult.Tipo == "Subir" then
		local ok = executarSubir(subirResult.EdgePosition, subirResult.Normal, grabData.Config)
		if ok then
			print("[Parkour] Subir para nova superfície | Dist:", string.format("%.1f", subirResult.VerticalDistance))
		end
		return ok, "Subir", subirResult, escalarResult
	elseif subirResult.Tipo == "SubirSalto" then
		return true, "SubirSalto", subirResult, escalarResult
	elseif subirResult.Tipo == "Escalar" then
		-- Fallback disparado pelo CheckSubir
		local ok = executarEscalar(subirResult, grabData.Config)
		if ok then
			print("[Parkour] Escalar direto para nova superfície acima | Dist:", string.format("%.1f", subirResult.VerticalDistance))
		end
		return ok, "Escalar", subirResult, escalarResult
	end

	return false, nil, subirResult, escalarResult
end

-- Tentar Descer: detecta superfície abaixo e move para ela
-- Retorna: ok, tipo, descerResult
function Movimento.TentarDescer()
	if not estado.Agarrado or estado.EmAcao then
		return false, nil
	end

	local grabData = estado.GrabData
	if not grabData then
		return false, nil
	end

	local character = estado.CurrentCharacter
	if not character then
		return false, nil
	end

	local descerResult = Analisador.CheckDescer(
		character,
		grabData.EdgePosition,
		grabData.Normal,
		grabData.Config
	)

	if not descerResult or not descerResult.CanDescer then
		return false, nil, descerResult
	end

	local ok = executarDescer(descerResult.EdgePosition, descerResult.Normal, descerResult.Part, grabData.Config)
	if ok then
		print("[Parkour] Descer para superfície abaixo | Dist:", string.format("%.1f", descerResult.VerticalDistance))
	end

	return ok, "Descer", descerResult
end

function Movimento.TentarMoverLateral(direcao)
	if not estado.Agarrado or estado.EmAcao then
		return false, nil
	end

	local grabData = estado.GrabData
	if not grabData then
		return false, nil
	end

	local character = estado.CurrentCharacter
	if not character then
		return false, nil
	end

	local now = os.clock()
	if now < lateralNoSurfaceCache.ExpiresAt
		and isSameGrabForLateralCache(direcao, grabData.EdgePosition, grabData.Normal)
	then
		return false, nil, {
			CanMoveLateral = false,
			Reason = "NoLateralSurfaceCached",
			Direction = direcao,
		}
	end

	local lateralResult = Analisador.CheckLateral(
		character,
		grabData.EdgePosition,
		grabData.Normal,
		direcao,
		grabData.Config
	)

	if not lateralResult or not lateralResult.CanMoveLateral then
		if lateralResult and lateralResult.Reason == "NoLateralSurface" then
			local finalConfig = Configs.mergeConfig(grabData.Config)
			local backoff = finalConfig.LateralNoSurfaceBackoff or 0.15
			lateralNoSurfaceCache.Direction = direcao
			lateralNoSurfaceCache.EdgePosition = grabData.EdgePosition
			lateralNoSurfaceCache.Normal = grabData.Normal and grabData.Normal.Unit or nil
			lateralNoSurfaceCache.ExpiresAt = now + backoff
		else
			clearLateralNoSurfaceCache()
		end

		return false, nil, lateralResult
	end

	clearLateralNoSurfaceCache()

	local ok = executarLateral(lateralResult, grabData.Config)
	if ok then
		print("[Parkour]", lateralResult.Estado, "| Dist:", string.format("%.2f", lateralResult.HorizontalDistance))
	end

	return ok, lateralResult.Estado, lateralResult
end

-- Executar SubirSalto (quando W+Pular confirmado)
function Movimento.ExecutarSubirSalto(subirResult)
	if not estado.Agarrado or estado.EmAcao then
		return false
	end

	if not subirResult or not subirResult.CanSubir then
		return false
	end

	local grabData = estado.GrabData
	if not grabData then
		return false
	end

	local ok = executarSubir(subirResult.EdgePosition, subirResult.Normal, grabData.Config)
	if ok then
		print("[Parkour] SubirSalto para superfície | Dist:", string.format("%.1f", subirResult.VerticalDistance))
	end
	return ok
end

-- Tentar Escalar: subir em cima da plataforma atual
function Movimento.TentarEscalar()
	if not estado.Agarrado or estado.EmAcao then
		return false
	end

	local grabData = estado.GrabData
	if not grabData then
		return false
	end

	local character = estado.CurrentCharacter
	if not character then
		return false
	end

	local escalarResult = Analisador.CheckEscalar(
		character,
		grabData.EdgePosition,
		grabData.Normal,
		grabData.Part,
		grabData.Config
	)

	if not escalarResult or not escalarResult.CanEscalar then
		return false
	end

	local ok = executarEscalar(escalarResult, grabData.Config)
	if ok then
		print("[Parkour] Escalar para cima da plataforma")
	end
	return ok
end

-- PuloTras: salto para trás estando agarrado
function Movimento.PuloTras()
	if not estado.Agarrado or estado.EmAcao then
		return false
	end

	local grabData = estado.GrabData
	if not grabData then
		return false
	end

	local ok = executarPuloTras(grabData.Config)
	if ok then
		print("[Parkour] PuloTras")
	end
	return ok
end

function Movimento.PuloLateral(direcao)
	if not estado.Agarrado or estado.EmAcao then
		return false
	end

	if direcao ~= "Direita" and direcao ~= "Esquerda" then
		return false
	end

	local grabData = estado.GrabData
	if not grabData then
		return false
	end

	local ok = executarPuloLateral(direcao, grabData.Config)
	if ok then
		print("[Parkour]", direcao .. "Salto")
	end

	return ok
end

function Movimento.EstaAgarrado()
	return estado.Agarrado
end

function Movimento.EstaEmAcao()
	return estado.EmAcao
end

function Movimento.GetGrabData()
	return estado.GrabData
end

return Movimento
