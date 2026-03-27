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
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modulos = ReplicatedStorage:WaitForChild("Modulos")
local ClientBridge = require(Modulos:WaitForChild("Core"):WaitForChild("ClientBridge"))
local AnimacaoParkour = require(Modulos:WaitForChild("Cliente"):WaitForChild("Visual"):WaitForChild("AnimacaoParkour"))

local Movimento = {}

-- ══════════════════════════════════════
-- Estado Interno
-- ══════════════════════════════════════

local estado = {
	EmAcao = false,
	Agarrado = false,
	ActiveConstraints = {} :: { Instance },
	TempNoCollisionConstraints = {} :: { NoCollisionConstraint },
	CharacterBaseParts = nil :: { BasePart }?,
	CharacterBasePartsFor = nil :: Model?,
	DiedConnection = nil :: RBXScriptConnection?,
	CurrentCharacter = nil :: Model?,
	SavedCollisions = {} :: { [BasePart]: boolean },
	SavedHeadCanCollide = nil :: boolean?,
	HeadPart = nil :: BasePart?,
	CameraBypassPart = nil :: BasePart?,
	CameraBypassPartCanCollide = nil :: boolean?,
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

local function clearCharacterPartsCache()
	estado.CharacterBaseParts = nil
	estado.CharacterBasePartsFor = nil
end

local function getCharacterBaseParts(character: Model): { BasePart }
	if estado.CharacterBasePartsFor == character and estado.CharacterBaseParts then
		return estado.CharacterBaseParts
	end

	local charParts = table.create(24)
	for _, inst in ipairs(character:GetDescendants()) do
		if inst:IsA("BasePart") then
			table.insert(charParts, inst)
		end
	end

	estado.CharacterBaseParts = charParts
	estado.CharacterBasePartsFor = character
	return charParts
end

local function zeroAssemblyVelocity(hrp)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
end

local function setGrabData(edgePosition, normal, part, idleMode, lateralState, config)
	local grabData = estado.GrabData
	if not grabData then
		grabData = {}
		estado.GrabData = grabData
	end

	grabData.EdgePosition = edgePosition
	grabData.Normal = normal
	grabData.Part = part
	grabData.IdleMode = idleMode
	grabData.LateralState = lateralState
	grabData.Config = config

	return grabData
end

local function getValidGrabData()
	local grabData = estado.GrabData
	if not grabData then
		return nil
	end

	if grabData.Part and not grabData.Part.Parent then
		grabData.Part = nil
	end

	return grabData
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

local function clearTemporaryNoCollisionConstraints()
	for _, constraint in ipairs(estado.TempNoCollisionConstraints) do
		if constraint and constraint.Parent then
			constraint:Destroy()
		end
	end
	table.clear(estado.TempNoCollisionConstraints)
end

local function createTemporaryNoCollisionConstraints(character: Model, surfaceParts: { BasePart })
	clearTemporaryNoCollisionConstraints()

	if not character then
		return
	end

	local charParts = getCharacterBaseParts(character)

	if #charParts == 0 or #surfaceParts == 0 then
		return
	end

	for _, charPart in ipairs(charParts) do
		for _, surfacePart in ipairs(surfaceParts) do
			if charPart ~= surfacePart and surfacePart and surfacePart.Parent then
				local nc = Instance.new("NoCollisionConstraint")
				nc.Part0 = charPart
				nc.Part1 = surfacePart
				nc.Parent = charPart
				table.insert(estado.TempNoCollisionConstraints, nc)
			end
		end
	end
end

local function clearOccludedPartVisual()
	if estado.CameraBypassPart and estado.CameraBypassPart.Parent and estado.CameraBypassPartCanCollide ~= nil then
		estado.CameraBypassPart.CanCollide = estado.CameraBypassPartCanCollide
	end

	estado.CameraBypassPart = nil
	estado.CameraBypassPartCanCollide = nil
end

local function applyOccludedPartVisual(part: BasePart?, config)
	if not part then
		clearOccludedPartVisual()
		return
	end

	if estado.CameraBypassPart == part then
		return
	end

	clearOccludedPartVisual()

	local finalConfig = Configs.mergeConfig(config)
	if finalConfig.GrabCameraCollisionBypass ~= false then
		estado.CameraBypassPart = part
		estado.CameraBypassPartCanCollide = part.CanCollide
		part.CanCollide = false
	end
end

-- ══════════════════════════════════════
-- Colisão: Desabilitar / Restaurar
-- ══════════════════════════════════════

local function desabilitarColisao(character)
	table.clear(estado.SavedCollisions)
	for _, part in ipairs(getCharacterBaseParts(character)) do
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

local function setHeadCollisionDuringParkour(character, enableNoCollision)
	if not character then
		return
	end

	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end

	if enableNoCollision then
		if estado.HeadPart ~= head then
			estado.HeadPart = head
			estado.SavedHeadCanCollide = head.CanCollide
		elseif estado.SavedHeadCanCollide == nil then
			estado.SavedHeadCanCollide = head.CanCollide
		end

		head.CanCollide = false
		return
	end

	if estado.HeadPart and estado.HeadPart.Parent and estado.SavedHeadCanCollide ~= nil then
		estado.HeadPart.CanCollide = estado.SavedHeadCanCollide
	end

	estado.HeadPart = nil
	estado.SavedHeadCanCollide = nil
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
	setHeadCollisionDuringParkour(estado.CurrentCharacter, false)
	clearOccludedPartVisual()
	clearTemporaryNoCollisionConstraints()

	AnimacaoParkour.PararTudo()
	AnimacaoParkour.ResetarBraco()
	if ClientBridge.SairParkour then
		ClientBridge.SairParkour()
	end

	destroyConstraints()
	restaurarColisao()
	clearLateralNoSurfaceCache()
	clearCharacterPartsCache()

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

local function obterOffsetsGrab(idleMode: string?, finalConfig)
	if idleMode == "IdleSuspenso" then
		return finalConfig.GrabVerticalOffsetSuspenso or finalConfig.GrabVerticalOffset,
			finalConfig.GrabSurfaceOffsetSuspenso or finalConfig.GrabSurfaceOffset
	end

	return finalConfig.GrabVerticalOffsetSuporte or finalConfig.GrabVerticalOffset,
		finalConfig.GrabSurfaceOffsetSuporte or finalConfig.GrabSurfaceOffset
end

local function resolverIdleModeParaGrab(character, part, edgePosition, normal, finalConfig, fallbackIdleMode)
	if character and part and edgePosition and normal then
		local idleMode = Analisador.ResolveIdleMode({
			Character = character,
			Part = part,
			EdgePosition = edgePosition,
			Normal = normal,
		}, finalConfig)

		if idleMode then
			return idleMode
		end
	end

	return fallbackIdleMode or "IdleSuporte"
end

local function calcularPosicaoGrab(edgePosition, normal, config, idleMode)
	local finalConfig = Configs.mergeConfig(config)
	local verticalOffset, surfaceOffset = obterOffsetsGrab(idleMode, finalConfig)

	local posicao = edgePosition
		+ Vector3.yAxis * verticalOffset
		+ normal.Unit * surfaceOffset

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

local function podeIniciarParkour(): boolean
	if ClientBridge.EmDialogo and ClientBridge.EmDialogo() then
		return false
	end

	if ClientBridge.EstaEmDash and ClientBridge.EstaEmDash() then
		return false
	end

	if ClientBridge.EstaEmAnimacaoEquip and ClientBridge.EstaEmAnimacaoEquip() then
		return false
	end

	if ClientBridge.EstaComboAtivo and ClientBridge.EstaComboAtivo() then
		return false
	end

	if ClientBridge.EstaAtaquePesadoAtivo and ClientBridge.EstaAtaquePesadoAtivo() then
		return false
	end

	return true
end

local function sincronizarGrabComIdle(idleMode: string?): boolean
	local grabData = getValidGrabData()
	local character = estado.CurrentCharacter
	if not grabData or not character then
		return false
	end

	local hrp = Utilidades.getCharacterParts(character)
	if not hrp then
		return false
	end

	local finalConfig = Configs.mergeConfig(grabData.Config)
	local idleFinal = idleMode or grabData.IdleMode or "IdleSuporte"
	grabData.IdleMode = idleFinal
	applyOccludedPartVisual(grabData.Part, finalConfig)

	local posAlvo, cfAlvo = calcularPosicaoGrab(grabData.EdgePosition, grabData.Normal, finalConfig, idleFinal)
	local atualizouPos = false
	local atualizouOri = false

	for _, constraint in ipairs(estado.ActiveConstraints) do
		if constraint:IsA("AlignPosition") then
			constraint.Position = posAlvo
			atualizouPos = true
		elseif constraint:IsA("AlignOrientation") then
			constraint.CFrame = cfAlvo
			atualizouOri = true
		end
	end

	if not atualizouPos then
		criarAlignPosition(hrp, posAlvo, 40)
	end

	if not atualizouOri then
		criarAlignOrientation(hrp, cfAlvo, 40)
	end

	zeroAssemblyVelocity(hrp)
	AnimacaoParkour.TocarIdle(idleFinal)

	return true
end

local function finalizarAcaoMantendoGrab()
	estado.EmAcao = false
	if estado.Agarrado and getValidGrabData() then
		local grabData = getValidGrabData()
		if not grabData then
			return
		end
		local idleResolvido = resolverIdleModeParaGrab(
			estado.CurrentCharacter,
			grabData.Part,
			grabData.EdgePosition,
			grabData.Normal,
			grabData.Config,
			grabData.IdleMode
		)
		sincronizarGrabComIdle(idleResolvido)
	end
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
		finalConfig,
		result.IdleMode
	)

	-- Criar constraints para grudar o player
	local alignPos = criarAlignPosition(hrp, posAlvo, 1 / finalConfig.GrabTransitionTime * 10)
	local alignOri = criarAlignOrientation(hrp, cfAlvo, 1 / finalConfig.GrabTransitionTime * 10)

	-- Zerar velocidade atual para transição suave
	zeroAssemblyVelocity(hrp)
	setHeadCollisionDuringParkour(character, true)

	-- Salvar dados do grab para ações futuras (Subir, Escalar, PuloTras)
	setGrabData(
		result.EdgePosition,
		result.Normal,
		result.Part or (result.Result and result.Result.Instance),
		result.IdleMode,
		nil,
		finalConfig
	)
	applyOccludedPartVisual(estado.GrabData.Part, finalConfig)

	-- Marcar como agarrado após tempo de transição
	local idleInicial = result.IdleMode or "IdleSuporte"
	task.delay(finalConfig.GrabIdleStartDelay or 0.02, function()
		if estado.CurrentCharacter == character and isCharacterAlive(character) then
			AnimacaoParkour.TocarIdle(idleInicial)
		end
	end)

	task.delay(finalConfig.GrabTransitionTime, function()
		if alignPos.Parent and alignOri.Parent and isCharacterAlive(character) then
			estado.Agarrado = true
			estado.EmAcao = false
			if ClientBridge.EntrarParkour then
				ClientBridge.EntrarParkour()
			end
			AnimacaoParkour.TocarIdle(idleInicial)
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
	if not podeIniciarParkour() then
		return false
	end

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
	zeroAssemblyVelocity(hrp)

	local movimentoConcluido = false
	local animacaoConcluida = false

	local function tentarFinalizar()
		if not (movimentoConcluido and animacaoConcluida) then
			return
		end
		estado.EmAcao = false
	end

	-- Fase 2: Após chegar na posição (acima da borda), aplicar impulso via LinearVelocity
	task.delay(transitionTime, function()
		if not isCharacterAlive(character) then
			removeConstraint(alignPos)
			removeConstraint(alignOri)
			movimentoConcluido = true
			tentarFinalizar()
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
		movimentoConcluido = true
		tentarFinalizar()
	end)

	local nomeAnimacao = if impulso == finalConfig.VaultMedioImpulse then "VaultMedio" else "VaultBaixo"
	local okAnimacao = AnimacaoParkour.TocarAcao(nomeAnimacao, nil, function()
		animacaoConcluida = true
		tentarFinalizar()
	end)

	if not okAnimacao then
		animacaoConcluida = true
		tentarFinalizar()
	end

	return true
end

-- ══════════════════════════════════════
-- Executar: Subir (move para nova superfície acima)
-- Destrói constraints antigos e cria novos
-- ══════════════════════════════════════

local function executarSubir(novaEdgePos, novaNormal, novaPart, config, nomeAnimacao, confirmarAcaoPausada, idleModePreferido)
	local finalConfig = Configs.mergeConfig(config)
	local character = estado.CurrentCharacter
	if not character then
		return false
	end

	local hrp = Utilidades.getCharacterParts(character)
	if not hrp then
		return false
	end

	if not podeIniciarParkour() then
		return false
	end

	estado.EmAcao = true
	local movimentoExecutado = false
	local transicaoConcluida = false
	local animacaoConcluida = false
	local finalizacaoExecutada = false
	local idleAtual = estado.GrabData and estado.GrabData.IdleMode or "IdleSuporte"
	local nome = nomeAnimacao or AnimacaoParkour.ObterAnimacaoSubir(idleAtual)
	local finalizarNoFimDaTransicao = string.find(nome, "SubirSalto", 1, true) ~= nil
	local tempoMinimoSubirSaltoConcluido = not finalizarNoFimDaTransicao
	local tentarFinalizarSubir

	if finalizarNoFimDaTransicao then
		local tempoMinimoAcao = finalConfig.SubirSaltoMinActionTime or 0.55
		task.delay(tempoMinimoAcao, function()
			tempoMinimoSubirSaltoConcluido = true
			if tentarFinalizarSubir then
				tentarFinalizarSubir()
			end
		end)
	end

	tentarFinalizarSubir = function()
		if finalizacaoExecutada then
			return
		end

		if finalizarNoFimDaTransicao then
			if not transicaoConcluida or not (animacaoConcluida or tempoMinimoSubirSaltoConcluido) then
				return
			end
		else
			if not (animacaoConcluida and transicaoConcluida) then
				return
			end
		end

		finalizacaoExecutada = true

		if finalizarNoFimDaTransicao then
			AnimacaoParkour.EncerrarAcaoAtual(finalConfig.SubirSaltoIdleFadeOut or 0.06)
		end

		if isCharacterAlive(character) then
			estado.Agarrado = true
		end

		finalizarAcaoMantendoGrab()
	end

	local function executarMovimentoSubir()
		if movimentoExecutado then
			return
		end
		movimentoExecutado = true
		estado.Agarrado = false

		destroyConstraints()

		local fallbackIdle = estado.GrabData and estado.GrabData.IdleMode or "IdleSuporte"
		local idleModeNovo = idleModePreferido
			or resolverIdleModeParaGrab(character, novaPart, novaEdgePos, novaNormal, finalConfig, fallbackIdle)
		local posAlvo, cfAlvo = calcularPosicaoGrab(novaEdgePos, novaNormal, finalConfig, idleModeNovo)

		local totalTime = finalConfig.SubirTransitionTime
		local startPos = hrp.Position
		local posVertical = Vector3.new(startPos.X, posAlvo.Y, startPos.Z)
		local responsivenessVertical = 1 / math.max(totalTime, 0.01) * 10

		criarAlignPosition(hrp, posVertical, responsivenessVertical)
		criarAlignOrientation(hrp, cfAlvo, responsivenessVertical)

		zeroAssemblyVelocity(hrp)

		setGrabData(
			novaEdgePos,
			novaNormal,
			novaPart or (estado.GrabData and estado.GrabData.Part),
			idleModeNovo,
			nil,
			finalConfig
		)
		applyOccludedPartVisual(estado.GrabData.Part, finalConfig)

		task.delay(totalTime, function()
			transicaoConcluida = true
			tentarFinalizarSubir()
		end)
	end

	local okAnimacao = false
	if confirmarAcaoPausada then
		okAnimacao = AnimacaoParkour.ConfirmarAcaoPausada(executarMovimentoSubir, function()
			animacaoConcluida = true
			tentarFinalizarSubir()
		end)
	else
		okAnimacao = AnimacaoParkour.TocarAcao(nome, executarMovimentoSubir, function()
			animacaoConcluida = true
			tentarFinalizarSubir()
		end)
	end

	if not okAnimacao then
		estado.EmAcao = false
		estado.Agarrado = true
		if estado.GrabData and estado.GrabData.IdleMode then
			AnimacaoParkour.TocarIdle(estado.GrabData.IdleMode)
		end
		return false
	end

	return true
end

local function executarDescer(novaEdgePos, novaNormal, novaPart, config, idleModePreferido)
	local finalConfig = Configs.mergeConfig(config)
	local character = estado.CurrentCharacter
	if not character then
		return false
	end

	local hrp = Utilidades.getCharacterParts(character)
	if not hrp then
		return false
	end

	if not podeIniciarParkour() then
		return false
	end

	estado.EmAcao = true
	estado.Agarrado = false
	local movimentoExecutado = false
	local transicaoConcluida = false
	local animacaoConcluida = false
	local finalizacaoExecutada = false

	local function tentarFinalizarDescer(forcarEncerrarAcao: boolean)
		if finalizacaoExecutada then
			return
		end

		if not transicaoConcluida then
			return
		end

		if not animacaoConcluida and not forcarEncerrarAcao then
			return
		end

		finalizacaoExecutada = true

		if not animacaoConcluida then
			AnimacaoParkour.EncerrarAcaoAtual(finalConfig.SubirSaltoIdleFadeOut or 0.06)
		end

		finalizarAcaoMantendoGrab()
	end

	local function executarMovimentoDescer()
		if movimentoExecutado then
			return
		end
		movimentoExecutado = true

		destroyConstraints()

		local fallbackIdle = estado.GrabData and estado.GrabData.IdleMode or "IdleSuporte"
		local idleModeNovo = idleModePreferido
			or resolverIdleModeParaGrab(character, novaPart, novaEdgePos, novaNormal, finalConfig, fallbackIdle)
		local posAlvo, cfAlvo = calcularPosicaoGrab(novaEdgePos, novaNormal, finalConfig, idleModeNovo)
		local responsiveness = 1 / finalConfig.DescerTransitionTime * 10
		local alignPos = criarAlignPosition(hrp, posAlvo, responsiveness)
		local alignOri = criarAlignOrientation(hrp, cfAlvo, responsiveness)

		zeroAssemblyVelocity(hrp)

		setGrabData(
			novaEdgePos,
			novaNormal,
			novaPart or (estado.GrabData and estado.GrabData.Part),
			idleModeNovo,
			nil,
			finalConfig
		)
		applyOccludedPartVisual(estado.GrabData.Part, finalConfig)

		task.delay(finalConfig.DescerTransitionTime, function()
			if alignPos.Parent and alignOri.Parent and isCharacterAlive(character) then
				estado.Agarrado = true
			end

			transicaoConcluida = true
			tentarFinalizarDescer(true)
		end)
	end

	local okAnimacao = AnimacaoParkour.TocarAcao("Descer", executarMovimentoDescer, function()
		animacaoConcluida = true
		tentarFinalizarDescer(false)
	end)

	if not okAnimacao then
		estado.EmAcao = false
		estado.Agarrado = true
		if estado.GrabData and estado.GrabData.IdleMode then
			AnimacaoParkour.TocarIdle(estado.GrabData.IdleMode)
		end
		return false
	end

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

	if not podeIniciarParkour() then
		return false
	end

	local currentEdgePos = estado.GrabData and estado.GrabData.EdgePosition
	if currentEdgePos and lateralResult.EdgePosition then
		local delta = lateralResult.EdgePosition - currentEdgePos
		local horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude
		local vertical = math.abs((lateralResult.VerticalDelta ~= nil) and lateralResult.VerticalDelta or delta.Y)
		local maxHorizontal = finalConfig.LateralSaltoMaxHorizontal or 11.0
		local maxVertical = finalConfig.LateralSaltoMaxVertical or 2.8
		if horizontal > maxHorizontal or vertical > maxVertical then
			print("[Parkour] Lateral bloqueado por segurança | Horiz:", string.format("%.2f", horizontal), "| Vert:", string.format("%.2f", vertical))
			return false
		end
	end

	estado.EmAcao = true
	estado.Agarrado = false
	local transicaoConcluida = false
	local animacaoConcluida = false
	local finalizacaoExecutada = false
	local movimentoExecutado = false
	local nomeAnimacao = lateralResult.Estado or "DireitaSuporte"
	local tempoTotal = math.max(finalConfig.LateralTransitionTime or 0.2, 0.01)

	local function tentarFinalizarLateral(forcarEncerrarAcao: boolean)
		if finalizacaoExecutada then
			return
		end

		if not transicaoConcluida then
			return
		end

		if not animacaoConcluida and not forcarEncerrarAcao then
			return
		end

		finalizacaoExecutada = true

		if not animacaoConcluida then
			AnimacaoParkour.EncerrarAcaoAtual(finalConfig.SubirSaltoIdleFadeOut or 0.06)
		end

		clearTemporaryNoCollisionConstraints()
		finalizarAcaoMantendoGrab()
	end

	local function executarMovimentoLateral()
		if movimentoExecutado then
			return
		end
		movimentoExecutado = true

		destroyConstraints()
		clearTemporaryNoCollisionConstraints()

		local surfaceParts = {}
		local currentPart = estado.GrabData and estado.GrabData.Part
		if currentPart and currentPart:IsA("BasePart") then
			table.insert(surfaceParts, currentPart)
		end
		if lateralResult.Part and lateralResult.Part:IsA("BasePart") and lateralResult.Part ~= currentPart then
			table.insert(surfaceParts, lateralResult.Part)
		end
		if #surfaceParts > 0 then
			createTemporaryNoCollisionConstraints(character, surfaceParts)
		end

		local posAlvo = calcularPosicaoGrab(
			lateralResult.EdgePosition,
			lateralResult.Normal,
			finalConfig,
			lateralResult.IdleMode
		)
		local posAtual = hrp.Position
		local direcao = lateralResult.Direction
			or (string.find(nomeAnimacao, "Esquerda", 1, true) and "Esquerda" or "Direita")
		local baseNormal = (estado.GrabData and estado.GrabData.Normal) or lateralResult.Normal
		local sideDir = getLateralDirection(baseNormal, direcao)
		local planarNormal = Vector3.new(baseNormal.X, 0, baseNormal.Z)
		if planarNormal.Magnitude < 0.05 then
			planarNormal = baseNormal.Unit
		else
			planarNormal = planarNormal.Unit
		end

		local delta = posAlvo - posAtual
		local sideDelta = sideDir * delta:Dot(sideDir)
		local depthDelta = planarNormal * delta:Dot(planarNormal)
		local verticalDelta = Vector3.new(0, delta.Y, 0)
		local residualDelta = delta - sideDelta - depthDelta - verticalDelta

		local isCurve = lateralResult.IsCorner == true
		if not isCurve and estado.GrabData and estado.GrabData.Normal and lateralResult.Normal then
			isCurve = lateralResult.Normal:Dot(estado.GrabData.Normal) < (finalConfig.LateralNormalMinDot or 0.5)
		end

		local phase1Delta = isCurve and sideDelta or depthDelta
		local phase2Delta = (isCurve and depthDelta or sideDelta) + verticalDelta + residualDelta
		local phase1Target = posAtual + phase1Delta
		local rotAtual = hrp.CFrame - hrp.CFrame.Position
		local cfAlvo = CFrame.new(posAlvo) * rotAtual

		local phaseSplit = math.clamp(finalConfig.LateralTransitionPhaseSplit or 0.55, 0.2, 0.8)
		local tempoFase1 = math.max(tempoTotal * phaseSplit, 0.01)
		local tempoFase2 = math.max(tempoTotal - tempoFase1, 0.01)
		local responsivenessFase1 = 1 / tempoFase1 * 10
		local responsivenessFase2 = 1 / tempoFase2 * 10

		local alignPos = criarAlignPosition(hrp, phase1Target, responsivenessFase1)
		local alignOri = criarAlignOrientation(hrp, cfAlvo, responsivenessFase1)

		zeroAssemblyVelocity(hrp)

		setGrabData(
			lateralResult.EdgePosition,
			lateralResult.Normal,
			lateralResult.Part,
			lateralResult.IdleMode,
			lateralResult.Estado,
			finalConfig
		)
		applyOccludedPartVisual(estado.GrabData.Part, finalConfig)

		task.delay(tempoFase1, function()
			if alignPos.Parent and alignOri.Parent and isCharacterAlive(character) then
				alignPos.Position = phase1Target + phase2Delta
				alignPos.Responsiveness = responsivenessFase2
				alignOri.Responsiveness = responsivenessFase2
			end
		end)

		task.delay(tempoTotal, function()
			if alignPos.Parent and alignOri.Parent and isCharacterAlive(character) then
				estado.Agarrado = true
			end

			transicaoConcluida = true
			tentarFinalizarLateral(true)
		end)
	end

	local okAnimacao = AnimacaoParkour.TocarAcao(nomeAnimacao, executarMovimentoLateral, function()
		animacaoConcluida = true
		tentarFinalizarLateral(false)
	end)

	if not okAnimacao then
		clearTemporaryNoCollisionConstraints()
		estado.EmAcao = false
		estado.Agarrado = true
		return false
	end

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

	if not podeIniciarParkour() then
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

	-- Fase 1: subir apenas no eixo Y a partir da posição atual
	local startPos = hrp.Position
	local posUp = Vector3.new(startPos.X, escalarResult.EdgePosition.Y + finalConfig.EscalarUpOffset, startPos.Z)

	-- Fase 2: mover pra frente na posição final
	local posFinal = escalarResult.PosFinal

	local ratioVertical = math.clamp(finalConfig.EscalarVerticalFirstRatio or 0.5, 0.1, 0.9)
	local tempoVertical = finalConfig.EscalarTransitionTime * ratioVertical
	local tempoHorizontal = finalConfig.EscalarTransitionTime - tempoVertical
	local responsivenessVertical = 1 / math.max(tempoVertical, 0.01) * 12
	local responsivenessHorizontal = 1 / math.max(tempoHorizontal, 0.01) * 12

	-- Orientação: olhar para frente durante toda a escalada
	local targetOri = CFrame.lookAt(posFinal, posFinal + look, Vector3.yAxis)

	-- Fase 1: AlignPosition leva o player para CIMA
	local alignPos = criarAlignPosition(hrp, posUp, responsivenessVertical)
	local alignOri = criarAlignOrientation(hrp, targetOri, responsivenessVertical)

	zeroAssemblyVelocity(hrp)

	local movimentoConcluido = false
	local animacaoConcluida = false

	local function tentarFinalizar()
		if not (movimentoConcluido and animacaoConcluida) then
			return
		end

		setHeadCollisionDuringParkour(character, false)
		clearOccludedPartVisual()

		AnimacaoParkour.ResetarBraco()
		if ClientBridge.SairParkour then
			ClientBridge.SairParkour()
		end

		estado.EmAcao = false
		estado.GrabData = nil
		estado.CurrentCharacter = nil
	end

	-- Fase 2: Após subir, mover pra FRENTE
	task.delay(tempoVertical, function()
		if alignPos.Parent and isCharacterAlive(character) then
			alignPos.Position = posFinal
			alignPos.Responsiveness = responsivenessHorizontal
			alignOri.Responsiveness = responsivenessHorizontal
		end
	end)

	-- Após transição completa, restaurar tudo
	task.delay(finalConfig.EscalarTransitionTime, function()
		if not isCharacterAlive(character) then
			removeConstraint(alignPos)
			removeConstraint(alignOri)
			movimentoConcluido = true
			tentarFinalizar()
			return
		end

		removeConstraint(alignPos)
		removeConstraint(alignOri)

		humanoid.AutoRotate = true
		humanoid.PlatformStand = false
		restaurarColisao()

		zeroAssemblyVelocity(hrp)
		movimentoConcluido = true
		tentarFinalizar()
	end)

	local idleAtual = estado.GrabData and estado.GrabData.IdleMode or "IdleSuporte"
	local nomeEscalar = AnimacaoParkour.ObterAnimacaoEscalar(idleAtual)
	local okAnimacao = AnimacaoParkour.TocarAcao(nomeEscalar, nil, function()
		animacaoConcluida = true
		tentarFinalizar()
	end)

	if not okAnimacao then
		animacaoConcluida = true
		tentarFinalizar()
	end

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

	if not podeIniciarParkour() then
		return false
	end

	estado.EmAcao = true
	estado.Agarrado = false

	-- Pegar a normal antes de limpar
	local normal = estado.GrabData and estado.GrabData.Normal or hrp.CFrame.LookVector

	destroyConstraints()
	restaurarColisao()
	clearLateralNoSurfaceCache()
	humanoid.AutoRotate = true
	humanoid.PlatformStand = false
	estado.GrabData = nil
	estado.CurrentCharacter = character

	-- Direção do impulso: normal (para longe da parede) + componente pra cima
	local impulseDir = (normal.Unit + Vector3.yAxis * finalConfig.PuloTrasUpComponent).Unit
	local impulseVel = impulseDir * finalConfig.PuloTrasImpulse

	hrp.AssemblyLinearVelocity = impulseVel

	-- Sustentação via LinearVelocity (como Dash)
	criarLinearVelocity(hrp, impulseVel, 0.2)

	local okAnimacao = AnimacaoParkour.TocarAcao("PuloTras", nil, function()
		AnimacaoParkour.ResetarBraco()
		fullCleanup()
	end)

	if not okAnimacao then
		AnimacaoParkour.ResetarBraco()
		fullCleanup()
	end

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

local function _executarPuloLateralComAnimacao(direcao, config)
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

	destroyConstraints()
	restaurarColisao()
	clearLateralNoSurfaceCache()
	setHeadCollisionDuringParkour(character, false)

	local humanoid = character:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.AutoRotate = true
		humanoid.PlatformStand = false
	end

	if ClientBridge.SairParkour then
		ClientBridge.SairParkour()
	end

	estado.Agarrado = false
	estado.GrabData = nil

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

	if not podeIniciarParkour() then
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

	local grabData = getValidGrabData()
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
		local ok = executarSubir(
			subirResult.EdgePosition,
			subirResult.Normal,
			subirResult.Part,
			grabData.Config,
			nil,
			nil,
			subirResult.IdleMode
		)
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

	local grabData = getValidGrabData()
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

	local ok = executarDescer(
		descerResult.EdgePosition,
		descerResult.Normal,
		descerResult.Part,
		grabData.Config,
		descerResult.IdleMode
	)
	if ok then
		print("[Parkour] Descer para superfície abaixo | Dist:", string.format("%.1f", descerResult.VerticalDistance))
	end

	return ok, "Descer", descerResult
end

function Movimento.TentarMoverLateral(direcao)
	if not estado.Agarrado or estado.EmAcao then
		return false, nil
	end

	local grabData = getValidGrabData()
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
		grabData.Config,
		grabData.Part
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

	local grabData = getValidGrabData()
	if not grabData then
		return false
	end

	local idleAtual = grabData.IdleMode or "IdleSuporte"
	local nomeAnimacao = AnimacaoParkour.ObterAnimacaoSubirSalto(idleAtual)
	local ok = executarSubir(
		subirResult.EdgePosition,
		subirResult.Normal,
		subirResult.Part,
		grabData.Config,
		nomeAnimacao,
		nil,
		subirResult.IdleMode
	)
	if ok then
		print("[Parkour] SubirSalto para superfície | Dist:", string.format("%.1f", subirResult.VerticalDistance))
	end
	return ok
end

function Movimento.IniciarPreviewSubirSalto(subirResult)
	if not estado.Agarrado or estado.EmAcao then
		return false
	end

	if not subirResult or not subirResult.CanSubir then
		return false
	end

	local grabData = getValidGrabData()
	if not grabData then
		return false
	end

	local idleAtual = grabData.IdleMode or "IdleSuporte"
	local nomeAnimacao = AnimacaoParkour.ObterAnimacaoSubirSalto(idleAtual)
	return AnimacaoParkour.TocarAcaoPausadaNoMarker(nomeAnimacao, nil)
end

function Movimento.ConfirmarPreviewSubirSalto(subirResult)
	if not estado.Agarrado or estado.EmAcao then
		return false
	end

	if not subirResult or not subirResult.CanSubir then
		return false
	end

	local grabData = getValidGrabData()
	if not grabData then
		return false
	end

	local idleAtual = grabData.IdleMode or "IdleSuporte"
	local nomeAnimacao = AnimacaoParkour.ObterAnimacaoSubirSalto(idleAtual)
	local confirmarComPreview = true

	local ok = executarSubir(
		subirResult.EdgePosition,
		subirResult.Normal,
		subirResult.Part,
		grabData.Config,
		nomeAnimacao,
		confirmarComPreview,
		subirResult.IdleMode
	)
	if ok then
		print("[Parkour] SubirSalto confirmado")
	end
	return ok
end

function Movimento.IniciarPreviewLateralSalto(direcao)
	if not estado.Agarrado or estado.EmAcao then
		return false
	end

	if direcao ~= "Direita" and direcao ~= "Esquerda" then
		return false
	end

	local grabData = getValidGrabData()
	if not grabData then
		return false
	end

	local idleAtual = grabData.IdleMode or "IdleSuporte"
	local nomeAnimacao = AnimacaoParkour.ObterAnimacaoLateralSalto(direcao, idleAtual)
	return AnimacaoParkour.TocarAcaoPausadaNoMarker(nomeAnimacao, nil)
end

function Movimento.ConfirmarPreviewLateralSalto(direcao, alvoLateralSalto)
	if not estado.Agarrado or estado.EmAcao then
		return false
	end

	if direcao ~= "Direita" and direcao ~= "Esquerda" then
		return false
	end

	local grabData = getValidGrabData()
	if not grabData then
		return false
	end
	local character = estado.CurrentCharacter
	if not character then
		return false
	end
	if not alvoLateralSalto or not alvoLateralSalto.EdgePosition or not alvoLateralSalto.Normal then
		return false
	end

	local finalConfig = Configs.mergeConfig(grabData.Config)
	local hrp = Utilidades.getCharacterParts(character)
	if not hrp then
		return false
	end

	local transicaoConcluida = false
	local animacaoConcluida = false
	local finalizacaoExecutada = false
	local movimentoExecutado = false
	local transicaoTempo = finalConfig.LateralSaltoTransitionTime or finalConfig.LateralTransitionTime or 0.28

	local function tentarFinalizarLateralSalto()
		if finalizacaoExecutada then
			return
		end

		if not (transicaoConcluida and animacaoConcluida) then
			return
		end

		finalizacaoExecutada = true
		if isCharacterAlive(character) then
			estado.Agarrado = true
		end
		finalizarAcaoMantendoGrab()
	end

	estado.EmAcao = true
	local ok = AnimacaoParkour.ConfirmarAcaoPausada(function()
		if movimentoExecutado then
			return
		end
		movimentoExecutado = true
		estado.Agarrado = false

		destroyConstraints()

		local idleModeNovo = alvoLateralSalto.IdleMode
			or resolverIdleModeParaGrab(character, alvoLateralSalto.Part, alvoLateralSalto.EdgePosition, alvoLateralSalto.Normal, finalConfig, grabData.IdleMode)
		local posAlvo, cfAlvo = calcularPosicaoGrab(alvoLateralSalto.EdgePosition, alvoLateralSalto.Normal, finalConfig, idleModeNovo)
		local responsiveness = 1 / math.max(transicaoTempo, 0.01) * 10
		local alignPos = criarAlignPosition(hrp, posAlvo, responsiveness)
		local alignOri = criarAlignOrientation(hrp, cfAlvo, responsiveness)

		zeroAssemblyVelocity(hrp)

		setGrabData(
			alvoLateralSalto.EdgePosition,
			alvoLateralSalto.Normal,
			alvoLateralSalto.Part,
			idleModeNovo,
			direcao .. "Salto",
			finalConfig
		)
		applyOccludedPartVisual(estado.GrabData.Part, finalConfig)

		task.delay(transicaoTempo, function()
			if alignPos.Parent and alignOri.Parent and isCharacterAlive(character) then
				estado.Agarrado = true
			end
			transicaoConcluida = true
			tentarFinalizarLateralSalto()
		end)
	end, function()
		AnimacaoParkour.ResetarBraco()
		animacaoConcluida = true
		tentarFinalizarLateralSalto()
	end)

	if not ok then
		estado.EmAcao = false
		return false
	end

	print("[Parkour] LateralSalto confirmado:", direcao)
	return true
end

function Movimento.CancelarPreviewLateralAoSoltar(config)
	if not estado.Agarrado or estado.EmAcao then
		return false
	end

	local velocidade = (config and config.LateralSaltoCancelSpeedAbs) or 1.3
	estado.EmAcao = true

	local ok = AnimacaoParkour.RecuarAcaoPausada(velocidade, function()
		estado.EmAcao = false
		if estado.Agarrado and estado.GrabData and estado.GrabData.IdleMode then
			sincronizarGrabComIdle(estado.GrabData.IdleMode)
		end
	end)

	if not ok then
		estado.EmAcao = false
		return Movimento.CancelarPreviewAcao(config)
	end

	return true
end

function Movimento.CancelarPreviewAcao(config)
	if not AnimacaoParkour.CancelarAcaoPausada((config and config.SubirSaltoIdleFadeOut) or nil) then
		return false
	end

	if estado.Agarrado and estado.GrabData and estado.GrabData.IdleMode then
		AnimacaoParkour.TocarIdle(estado.GrabData.IdleMode)
	end

	return true
end

function Movimento.ReavaliarIdleAgarrado()
	if not estado.Agarrado or estado.EmAcao then
		return false
	end

	local grabData = getValidGrabData()
	local character = estado.CurrentCharacter
	if not grabData or not character then
		return false
	end

	local hrp = Utilidades.getCharacterParts(character)
	if not hrp then
		return false
	end

	local finalConfig = Configs.mergeConfig(grabData.Config)
	local idleNovo = resolverIdleModeParaGrab(
		character,
		grabData.Part,
		grabData.EdgePosition,
		grabData.Normal,
		finalConfig,
		grabData.IdleMode
	)
	if not idleNovo then
		return false
	end

	local mudouIdle = idleNovo ~= grabData.IdleMode
	sincronizarGrabComIdle(idleNovo)
	return mudouIdle
end

-- Tentar Escalar: subir em cima da plataforma atual
function Movimento.TentarEscalar()
	if not estado.Agarrado or estado.EmAcao then
		return false
	end

	local grabData = getValidGrabData()
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

	local grabData = getValidGrabData()
	if not grabData then
		return false
	end

	if grabData.IdleMode ~= "IdleSuporte" then
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

	local grabData = getValidGrabData()
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
	return getValidGrabData()
end

return Movimento
