--[[
	Movimento.luau
	Módulo de movimento do sistema de Parkour.
	Responsável por executar Agarrar, VaultBaixo e VaultMédio
	usando constraints do Roblox, com cleanup automático.
]]

local Configs = require(script.Parent:WaitForChild("Configs"))
local Utilidades = require(script.Parent:WaitForChild("Utilidades"))

local Movimento = {}

-- ══════════════════════════════════════
-- Estado Interno
-- ══════════════════════════════════════

local estado = {
	EmAcao = false,
	Agarrado = false,
	ActiveConstraints = {},
	DiedConnection = nil,
	CurrentCharacter = nil,
	StepConnection = nil,
	SavedCollisions = {}, -- backup de CanCollide das partes do character
}

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

local function disconnectStep()
	if estado.StepConnection then
		estado.StepConnection:Disconnect()
		estado.StepConnection = nil
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

local function fullCleanup()
	disconnectStep()
	destroyConstraints()
	restaurarColisao()

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
		if lv and lv.Parent then
			lv:Destroy()
		end
		local idx = table.find(estado.ActiveConstraints, lv)
		if idx then
			table.remove(estado.ActiveConstraints, idx)
		end
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

	-- Marcar como agarrado após tempo de transição
	task.delay(finalConfig.GrabTransitionTime, function()
		if alignPos.Parent and alignOri.Parent then
			estado.Agarrado = true
			estado.EmAcao = false
		end
	end)

	return true
end

-- ══════════════════════════════════════
-- Executar: Vault (Baixo e Médio)
-- Fase 1: AlignPosition leva o player até a posição final (sem colisão)
-- Fase 2: Após chegar, aplica impulso na direção do LookVector e restaura colisão
-- ══════════════════════════════════════

local function executarVault(result, _config, impulso, transitionTime)
	local character = result.Character
	local hrp = Utilidades.getCharacterParts(character)
	local humanoid = character:FindFirstChild("Humanoid")

	if not hrp or not humanoid then
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

	-- Posição final: acima da borda (ponto de destino do vault)
	local posFinal = result.PosFinal or result.EdgePosition
	local look = result.LookVector or hrp.CFrame.LookVector

	-- Fase 1: AlignPosition leva o player até a posição final suavemente
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

	-- Fase 2: Após chegar na posição, aplicar impulso para frente e restaurar tudo
	task.delay(transitionTime, function()
		-- Destruir as constraints de posicionamento
		if alignPos and alignPos.Parent then
			alignPos:Destroy()
		end
		if alignOri and alignOri.Parent then
			alignOri:Destroy()
		end

		-- Restaurar humanoid e colisão
		humanoid.AutoRotate = true
		humanoid.PlatformStand = false
		restaurarColisao()

		-- Aplicar impulso na direção que o player está olhando + um pouco pra cima
		local impulseDir = (look + Vector3.yAxis * 0.3).Unit
		hrp.AssemblyLinearVelocity = impulseDir * impulso

		-- Sustentação breve via LinearVelocity
		criarLinearVelocity(hrp, impulseDir * impulso, 0.15)

		estado.EmAcao = false
	end)

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

function Movimento.EstaAgarrado()
	return estado.Agarrado
end

function Movimento.EstaEmAcao()
	return estado.EmAcao
end

return Movimento
