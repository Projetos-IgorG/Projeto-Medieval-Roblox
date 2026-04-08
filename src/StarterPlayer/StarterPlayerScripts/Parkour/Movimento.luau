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
local Debug = require(script.Parent:WaitForChild("Debug"))
local MomentumManager = require(script.Parent:WaitForChild("MomentumManager"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Modulos = ReplicatedStorage:WaitForChild("Modulos")
local ClientBridge = require(Modulos:WaitForChild("Core"):WaitForChild("ClientBridge"))
local AnimacaoParkour = require(Modulos:WaitForChild("Cliente"):WaitForChild("Visual"):WaitForChild("AnimacaoParkour"))
local CameraBypass = require(Modulos:WaitForChild("Cliente"):WaitForChild("Core"):WaitForChild("CameraBypass"))

local CAMERA_BYPASS_BOX_SIZE = Vector3.new(5, 5, 5)

local Movimento = {}
local function dbgPrint(...)
	Debug.Verbose(...)
end

local function getScaledTransitionTime(baseTime: number): number
	return baseTime / MomentumManager.GetSpeedMultiplier(os.clock())
end

local function formatVector3Short(v)
	if not v then
		return "nil"
	end

	return string.format("(%.2f, %.2f, %.2f)", v.X, v.Y, v.Z)
end

local idleDebugState = {
	LastIdleMode = nil :: string?,
	LastStableLogAt = 0,
	FlipWindowStart = 0,
	FlipCount = 0,
}

-- ══════════════════════════════════════
-- Estado Interno
-- ══════════════════════════════════════

local estado = {
	EmAcao = false,
	Agarrado = false,
	ActiveConstraints = {} :: { Instance },
	CharacterBaseParts = nil :: { BasePart }?,
	CharacterBasePartsFor = nil :: Model?,
	DiedConnection = nil :: RBXScriptConnection?,
	CurrentCharacter = nil :: Model?,
	SavedCollisions = {} :: { [BasePart]: boolean },
	SavedHeadCanCollide = nil :: boolean?,
	HeadPart = nil :: BasePart?,
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

local function drawIdleDecisionVisual(decisionDebug, idleMode, finalConfig)
	if not Configs.DebugEnabled or finalConfig.IdleDebugVisualEnabled == false then
		return
	end

	if not decisionDebug then
		return
	end

	local supportDebug = decisionDebug.SupportDebug
	local idleColor = idleMode == "IdleSuporte"
		and Color3.fromRGB(90, 255, 120)
		or Color3.fromRGB(255, 160, 70)

	if supportDebug and supportDebug.Rays then
		for _, rayData in ipairs(supportDebug.Rays) do
			if rayData.Origin and rayData.Direction then
				local endPoint = rayData.Origin + rayData.Direction
				if rayData.HitPosition then
					endPoint = rayData.HitPosition
				end

				local rayColor = rayData.Hit
					and Color3.fromRGB(60, 230, 120)
					or Color3.fromRGB(255, 120, 60)

				Debug.DrawLine(rayData.Origin, endPoint, rayColor)

				if rayData.HitPosition then
					Debug.DrawPoint(rayData.HitPosition, rayColor, Vector3.new(0.16, 0.16, 0.16))
				end
			end
		end

		if supportDebug.Blocker and supportDebug.Blocker:IsA("BasePart") then
			Debug.DrawPoint(supportDebug.Blocker.Position, Color3.fromRGB(255, 50, 50), Vector3.new(0.18, 0.18, 0.18))
		end
	end

	if decisionDebug.EdgePosition then
		Debug.DrawPoint(decisionDebug.EdgePosition, idleColor, Vector3.new(0.22, 0.22, 0.22))
	end

	if decisionDebug.EdgePosition and decisionDebug.Normal and decisionDebug.Normal.Magnitude > 0.001 then
		local edge = decisionDebug.EdgePosition
		local tip = edge + decisionDebug.Normal.Unit * 1.4
		Debug.DrawLine(edge, tip, Color3.fromRGB(100, 190, 255))
	end

	if decisionDebug.HrpPosition and decisionDebug.EdgePosition then
		local dist = (decisionDebug.HrpPosition - decisionDebug.EdgePosition).Magnitude
		if dist > 0.02 then
			Debug.DrawLine(decisionDebug.HrpPosition, decisionDebug.EdgePosition, Color3.fromRGB(255, 235, 120))
		end
	end
end

local function traceIdleDecision(source, idleAnterior, idleNovo, decisionDebug, finalConfig, sincronizou)
	local debugVerboseEnabled = Configs.DebugVerbose and finalConfig.IdleDebugVerbose ~= false
	if not debugVerboseEnabled then
		return
	end

	local now = os.clock()
	local changed = idleAnterior ~= idleNovo
	local stableInterval = math.max(finalConfig.IdleDebugStableLogInterval or 0.35, 0)

	if not changed and now - idleDebugState.LastStableLogAt < stableInterval then
		return
	end

	if changed then
		local window = math.max(finalConfig.IdleDebugFlipWindow or 1.25, 0.2)
		if now - idleDebugState.FlipWindowStart > window then
			idleDebugState.FlipWindowStart = now
			idleDebugState.FlipCount = 0
		end

		idleDebugState.FlipCount += 1
	else
		idleDebugState.LastStableLogAt = now
	end

	local blockerName = "nil"
	if decisionDebug and decisionDebug.Blocker and decisionDebug.Blocker:IsA("BasePart") then
		blockerName = decisionDebug.Blocker.Name
	elseif decisionDebug and decisionDebug.SupportDebug and decisionDebug.SupportDebug.Blocker and decisionDebug.SupportDebug.Blocker:IsA("BasePart") then
		blockerName = decisionDebug.SupportDebug.Blocker.Name
	end

	dbgPrint(
		"[Parkour][IdleTrace]",
		"src=" .. (source or "Unknown"),
		"|",
		idleAnterior,
		"->",
		idleNovo,
		"| changed:",
		changed,
		"| sync:",
		sincronizou,
		"| reason:",
		decisionDebug and decisionDebug.Reason or "n/a",
		"| gate:",
		decisionDebug and decisionDebug.Gate or "n/a",
		"| supportHits:",
		decisionDebug and decisionDebug.SupportHitCount or "n/a",
		"/",
		decisionDebug and decisionDebug.SupportRayCount or "n/a",
		"| fallback:",
		decisionDebug and decisionDebug.FallbackIdle or "nil",
		"| edge:",
		formatVector3Short(decisionDebug and decisionDebug.EdgePosition or nil),
		"| normal:",
		formatVector3Short(decisionDebug and decisionDebug.Normal or nil),
		"| hrp:",
		formatVector3Short(decisionDebug and decisionDebug.HrpPosition or nil),
		"| blocker:",
		blockerName
	)

	if changed then
		local warnThreshold = math.max(finalConfig.IdleDebugFlipWarnThreshold or 4, 2)
		if idleDebugState.FlipCount >= warnThreshold then
			dbgPrint(
				"[Parkour][IdleTrace][WARN] Oscilacao detectada",
				"| flips:",
				idleDebugState.FlipCount,
				"| janela:",
				string.format("%.2fs", finalConfig.IdleDebugFlipWindow or 1.25)
			)
		end
	end

	idleDebugState.LastIdleMode = idleNovo

	drawIdleDecisionVisual(decisionDebug, idleNovo, finalConfig)
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

local function normalizarNormalGrab(normal, config, fallbackLook)
	local finalConfig = Configs.mergeConfig(config)
	local maxWallNormalY = finalConfig.MaxWallNormalY or 0.8

	if normal and normal.Magnitude > 0.001 then
		local normalUnit = normal.Unit
		if math.abs(normalUnit.Y) <= maxWallNormalY then
			return normalUnit
		end

		local planarNormal = Vector3.new(normalUnit.X, 0, normalUnit.Z)
		if planarNormal.Magnitude > 0.001 then
			return planarNormal.Unit
		end
	end

	if fallbackLook and fallbackLook.Magnitude > 0.001 then
		local lookXZ = Vector3.new(fallbackLook.X, 0, fallbackLook.Z)
		if lookXZ.Magnitude > 0.001 then
			return -lookXZ.Unit
		end
	end

	return Vector3.new(0, 0, -1)
end

local function setGrabData(edgePosition, normal, part, idleMode, lateralState, config, fallbackLook)
	local grabData = estado.GrabData
	local previousIdle = grabData and grabData.IdleMode or nil
	if not grabData then
		grabData = {}
		estado.GrabData = grabData
	end

	local normalSegura = normalizarNormalGrab(normal, config, fallbackLook)

	grabData.EdgePosition = edgePosition
	grabData.Normal = normalSegura
	grabData.Part = part
	grabData.IdleMode = idleMode
	grabData.LateralState = lateralState
	grabData.Config = config
	grabData.PendingIdleMode = nil
	grabData.PendingIdleCount = 0
	if previousIdle ~= idleMode then
		grabData.LastIdleSwitchAt = os.clock()
	else
		grabData.LastIdleSwitchAt = grabData.LastIdleSwitchAt or os.clock()
	end

	if part and typeof(part) == "Instance" and part:IsA("BasePart") then
		grabData.LocalEdgePosition = part.CFrame:PointToObjectSpace(edgePosition)
		grabData.LocalNormal = part.CFrame:VectorToObjectSpace(normalSegura)
	else
		grabData.LocalEdgePosition = nil
		grabData.LocalNormal = nil
	end

	return grabData
end

local function getValidGrabData()
	local grabData = estado.GrabData
	if not grabData then
		return nil
	end

	if grabData.Part then
		if not grabData.Part.Parent then
			grabData.Part = nil
			grabData.LocalEdgePosition = nil
			grabData.LocalNormal = nil
		elseif grabData.LocalEdgePosition and grabData.LocalNormal and typeof(grabData.Part) == "Instance" and grabData.Part:IsA("BasePart") then
			grabData.EdgePosition = grabData.Part.CFrame:PointToWorldSpace(grabData.LocalEdgePosition)
			local fallbackLook = nil
			if estado.CurrentCharacter then
				local hrp = Utilidades.getCharacterParts(estado.CurrentCharacter)
				fallbackLook = hrp and hrp.CFrame.LookVector or nil
			end
			grabData.Normal = normalizarNormalGrab(
				grabData.Part.CFrame:VectorToWorldSpace(grabData.LocalNormal),
				grabData.Config,
				fallbackLook
			)
		end
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

-- ══════════════════════════════════════
-- Camera Bypass
-- ══════════════════════════════════════

local _cameraBypassOverlap = OverlapParams.new()
_cameraBypassOverlap.FilterType = Enum.RaycastFilterType.Exclude
_cameraBypassOverlap.RespectCanCollide = false
_cameraBypassOverlap.MaxParts = 0

local function updateCameraBypass(hrp: BasePart)
	CameraBypass.clear()
	local character = estado.CurrentCharacter
	if not character then
		return
	end

	_cameraBypassOverlap.FilterDescendantsInstances = { character }
	local parts = Workspace:GetPartBoundsInBox(hrp.CFrame, CAMERA_BYPASS_BOX_SIZE, _cameraBypassOverlap)
	for _, part in parts do
		CameraBypass.add(part)
	end
end

local function fullCleanup()
	setHeadCollisionDuringParkour(estado.CurrentCharacter, false)

	AnimacaoParkour.PararTudo()
	AnimacaoParkour.ResetarBraco()
	if ClientBridge.SairParkour then
		ClientBridge.SairParkour()
	end

	destroyConstraints()
	restaurarColisao()
	CameraBypass.clear()
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
	idleDebugState.LastIdleMode = nil
	idleDebugState.LastStableLogAt = 0
	idleDebugState.FlipWindowStart = 0
	idleDebugState.FlipCount = 0
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

--- Calcula a velocidade angular (rad/s) necessária para rotacionar de currentCF até targetCF
--- em exatamente `tempo` segundos, com margem de 15% para compensar desaceleração da spring.
local function calcularVelocidadeAngularSuave(currentCFrame: CFrame, targetCFrame: CFrame, tempo: number): number
	local rel = currentCFrame:ToObjectSpace(targetCFrame)
	local _, angle = rel:ToAxisAngle()
	angle = math.abs(angle)
	if angle < 0.02 or tempo <= 0 then
		return math.huge
	end
	return angle / tempo * 1.15
end

local function criarAlignOrientation(hrp, targetCFrame, responsiveness, maxAngularVelocity)
	local align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = hrp:FindFirstChild("RootAttachment")
		or hrp:FindFirstChildOfClass("Attachment")
	align.CFrame = targetCFrame
	align.MaxTorque = 100000
	align.Responsiveness = responsiveness or 40
	if maxAngularVelocity and maxAngularVelocity < math.huge then
		align.MaxAngularVelocity = maxAngularVelocity
	end
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

--- Cria um Attachment na part agarrada na posição/orientação world indicada.
--- O Attachment se move junto com a part (local space).
--- Se worldCF for fornecido, inclui orientação (para AlignOrientation TwoAttachment).
local function criarGrabAttachment(part, worldPosition, worldCF)
	local attachment = Instance.new("Attachment")
	if worldCF then
		attachment.CFrame = part.CFrame:ToObjectSpace(worldCF)
	else
		attachment.CFrame = part.CFrame:ToObjectSpace(CFrame.new(worldPosition))
	end
	attachment.Parent = part
	table.insert(estado.ActiveConstraints, attachment)
	return attachment
end

--- AlignPosition TwoAttachment: suave ou rígido.
--- Se rigido=true, RigidityEnabled garante posição exata (ignora MaxForce/Responsiveness).
--- Se rigido=false, usa MaxForce/Responsiveness para transição suave.
local function criarAlignPositionDoisPontos(hrp, targetAttachment, rigido, responsiveness)
	local align = Instance.new("AlignPosition")
	align.Mode = Enum.PositionAlignmentMode.TwoAttachment
	align.Attachment0 = hrp:FindFirstChild("RootAttachment")
		or hrp:FindFirstChildOfClass("Attachment")
	align.Attachment1 = targetAttachment
	align.RigidityEnabled = rigido == true
	align.ReactionForceEnabled = true
	if not rigido then
		align.MaxForce = 100000
		align.MaxVelocity = math.huge
		align.Responsiveness = responsiveness or 40
	end
	align.Parent = hrp
	table.insert(estado.ActiveConstraints, align)
	return align
end

--- AlignOrientation TwoAttachment: suave ou rígido.
--- Se rigido=true, RigidityEnabled garante rotação exata (segue part rigidamente).
local function criarAlignOrientationDoisPontos(hrp, targetAttachment, rigido, responsiveness)
	local align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.TwoAttachment
	align.Attachment0 = hrp:FindFirstChild("RootAttachment")
		or hrp:FindFirstChildOfClass("Attachment")
	align.Attachment1 = targetAttachment
	align.RigidityEnabled = rigido == true
	if not rigido then
		align.MaxTorque = 100000
		align.Responsiveness = responsiveness or 40
	end
	align.Parent = hrp
	table.insert(estado.ActiveConstraints, align)
	return align
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

local function obterOffsetsGrab(finalConfig)
	return finalConfig.GrabVerticalOffset, finalConfig.GrabSurfaceOffset
end

local function resolverIdleModeParaGrab(character, part, edgePosition, normal, finalConfig, fallbackIdleMode, debugSource)
	if character and part and edgePosition and normal then
		local idleMode, blocker, supportDebug = Analisador.ResolveIdleMode({
			Character = character,
			Part = part,
			EdgePosition = edgePosition,
			Normal = normal,
		}, finalConfig)

		if idleMode then
			local idleDebug = nil
			if Configs.DebugEnabled or Configs.DebugVerbose then
				local sHit = supportDebug and supportDebug.HitCount or 0
				local sRay = supportDebug and supportDebug.Rays and #supportDebug.Rays or 0
				idleDebug = {
					Source = debugSource or "ResolveIdleMode",
					Reason = supportDebug
						and (idleMode == "IdleSuporte"
							and ("LegSupportDetected(" .. tostring(sHit) .. "/" .. tostring(sRay) .. ")")
							or ("NoLegSupport(" .. tostring(sHit) .. "/" .. tostring(sRay) .. ")"))
						or "ForcedSuspensoTag",
					FallbackIdle = fallbackIdleMode,
					Blocker = blocker,
					SupportDebug = supportDebug,
					SupportHitCount = sHit,
					SupportRayCount = sRay,
					EdgePosition = edgePosition,
					Normal = normal,
				}
			end
			return idleMode, idleDebug
		end
	end

	local fallbackDebug = nil
	if Configs.DebugEnabled or Configs.DebugVerbose then
		fallbackDebug = {
			Source = debugSource or "ResolveIdleModeFallback",
			Reason = "FallbackIdle",
			FallbackIdle = fallbackIdleMode,
			Blocker = nil,
			SupportDebug = nil,
			SupportHitCount = 0,
			SupportRayCount = 0,
			EdgePosition = edgePosition,
			Normal = normal,
		}
	end
	return fallbackIdleMode or "IdleSuporte", fallbackDebug
end

local function resolveStableIdleMode(grabData, idleCandidate, finalConfig, decisionDebug)
	local currentIdle = grabData.IdleMode or idleCandidate or "IdleSuporte"
	local candidateIdle = idleCandidate or currentIdle
	local confirmationsToSupport = math.max(math.floor(finalConfig.IdleSwitchToSupportConfirmations or 2), 1)
	local confirmationsToSuspenso = math.max(math.floor(finalConfig.IdleSwitchToSuspensoConfirmations or 2), 1)
	local minSwitchInterval = math.max(finalConfig.IdleSwitchMinInterval or 0.45, 0)

	if candidateIdle == currentIdle then
		grabData.PendingIdleMode = nil
		grabData.PendingIdleCount = 0
		if decisionDebug then
			decisionDebug.Gate = "Stable"
		end
		return currentIdle, false
	end

	if grabData.PendingIdleMode ~= candidateIdle then
		grabData.PendingIdleMode = candidateIdle
		grabData.PendingIdleCount = 1
	else
		grabData.PendingIdleCount = (grabData.PendingIdleCount or 0) + 1
	end

	local requiredConfirmations = candidateIdle == "IdleSuporte"
		and confirmationsToSupport
		or confirmationsToSuspenso

	if (grabData.PendingIdleCount or 0) < requiredConfirmations then
		if decisionDebug then
			decisionDebug.Gate = "CandidateAccum(" .. tostring(grabData.PendingIdleCount or 0)
				.. "/" .. tostring(requiredConfirmations) .. ")"
		end
		return currentIdle, false
	end

	local now = os.clock()
	local elapsed = now - (grabData.LastIdleSwitchAt or 0)
	if elapsed < minSwitchInterval then
		if decisionDebug then
			decisionDebug.Gate = "MinIntervalGate(" .. string.format("%.2f", elapsed)
				.. "/" .. string.format("%.2f", minSwitchInterval) .. ")"
		end
		return currentIdle, false
	end

	grabData.PendingIdleMode = nil
	grabData.PendingIdleCount = 0
	grabData.LastIdleSwitchAt = now
	if decisionDebug then
		decisionDebug.Gate = "SwitchConfirmed"
	end

	return candidateIdle, true
end

local function calcularPosicaoGrab(edgePosition, normal, config, _idleMode)
	local finalConfig = Configs.mergeConfig(config)
	local verticalOffset, surfaceOffset = obterOffsetsGrab(finalConfig)

	-- Flatten da normal: projetar no plano XZ para nunca inclinar o player (só yaw)
	local flatNormal = Vector3.new(normal.X, 0, normal.Z)
	if flatNormal.Magnitude < 0.01 then
		flatNormal = Vector3.new(0, 0, -1)
	end
	flatNormal = flatNormal.Unit

	local posicao = edgePosition
		+ Vector3.yAxis * verticalOffset
		+ flatNormal * surfaceOffset

	local lookTarget = posicao - flatNormal
	local orientacao = CFrame.lookAt(posicao, lookTarget, Vector3.yAxis)

	return posicao, orientacao
end

local function calcularPosicaoGrabSegura(character, hrp, edgePosition, normal, part, config, idleMode)
	local finalConfig = Configs.mergeConfig(config)
	local posicao, orientacao = calcularPosicaoGrab(edgePosition, normal, finalConfig, idleMode)
	local ajustada = false
	local ultimoBloqueador = nil

	if part and typeof(part) == "Instance" and part:IsA("BasePart") then
		local normalUnit = normal.Unit
		local minGap = math.max((hrp.Size.Z * 0.5) + (finalConfig.GrabSurfaceSafetyMargin or 0.2), 0.9)
		local signedGap

		-- MeshParts/UnionOperations: usar raycast para medir distância real até a superfície
		if part:IsA("MeshPart") or part:IsA("UnionOperation") then
			local rayOrigin = posicao
			local rayDir = -normalUnit * (part.Size.Magnitude * 0.5 + 2.0)
			local rayParams = RaycastParams.new()
			rayParams.FilterType = Enum.RaycastFilterType.Include
			rayParams.FilterDescendantsInstances = { part }
			rayParams.IgnoreWater = true
			local rayResult = Workspace:Raycast(rayOrigin, rayDir, rayParams)
			if rayResult and rayResult.Instance == part then
				signedGap = (posicao - rayResult.Position):Dot(normalUnit)
			end
		end

		-- Parts normais (ou fallback se ray falhou): box math original
		if signedGap == nil then
			local normalLocal = part.CFrame:VectorToObjectSpace(normalUnit)
			local axis, sign = Utilidades.dominantAxis(normalLocal)
			local half = part.Size / 2
			local faceCoord = sign * Utilidades.getAxisValue(half, axis)
			local localPos = part.CFrame:PointToObjectSpace(posicao)
			local coord = Utilidades.getAxisValue(localPos, axis)
			signedGap = sign * (coord - faceCoord)
		end

		if signedGap < minGap then
			posicao += normalUnit * (minGap - signedGap)
			orientacao = CFrame.new(posicao) * orientacao.Rotation
			ajustada = true
		end
	end

	local probeScale = math.clamp(finalConfig.GrabSafetyProbeScale or 0.9, 0.6, 1.0)
	local probeSize = hrp.Size * probeScale
	local pushStep = math.max(finalConfig.GrabSafetyPushStep or 0.15, 0.05)
	local maxPushSteps = math.max(math.floor(finalConfig.GrabSafetyMaxPushSteps or 6), 1)
	-- Excluir a part agarrada do overlap: a distância até ela já foi garantida pelo signedGap acima.
	-- Sem isso, MeshParts com bounding box maior que a mesh causam falso-positivo no push loop.
	local overlapIgnore = { character }
	if part and typeof(part) == "Instance" then
		table.insert(overlapIgnore, part)
	end
	local overlapParams = Utilidades.createOverlapParams(overlapIgnore, 0)
	local normalUnit = normal.Unit

	for _ = 1, maxPushSteps do
		local probeCf = CFrame.new(posicao) * orientacao.Rotation
		local touching = Workspace:GetPartBoundsInBox(probeCf, probeSize, overlapParams)
		local blocker = nil

		for _, hitPart in ipairs(touching) do
			if hitPart:IsA("BasePart") and not hitPart:IsDescendantOf(character)
				and not Utilidades.isParkourIgnoredPart(hitPart, finalConfig.MinPartHeight)
			then
				blocker = hitPart
				break
			end
		end

		if not blocker then
			break
		end

		ultimoBloqueador = blocker
		posicao += normalUnit * pushStep
		orientacao = CFrame.new(posicao) * orientacao.Rotation
		ajustada = true
	end

	return posicao, orientacao, ajustada, ultimoBloqueador
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

local function sincronizarGrabComIdle(idleMode: string?, debugSource: string?, idleDecisionDebug): boolean
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
	local idleAnterior = grabData.IdleMode or "IdleSuporte"
	local idleFinal = idleMode or grabData.IdleMode or "IdleSuporte"
	grabData.IdleMode = idleFinal

	local posAlvo, cfAlvo, ajustadaPosicao, bloqueador = calcularPosicaoGrabSegura(
		character,
		hrp,
		grabData.EdgePosition,
		grabData.Normal,
		grabData.Part,
		finalConfig,
		idleFinal
	)

	if ajustadaPosicao then
		dbgPrint(
			"[Parkour] Re-sync grab ajustado para posição segura",
			"| blocker:",
			bloqueador and bloqueador.Name or "nil"
		)
	end

	-- Destruir constraints antigos antes de recriar
	destroyConstraints()

	-- Posicionar diretamente via CFrame e criar ancoragem rígida
	hrp.CFrame = CFrame.new(posAlvo) * cfAlvo.Rotation
	zeroAssemblyVelocity(hrp)

	-- Ancoragem rígida TwoAttachment (RigidityEnabled) para acompanhar part móvel
	local grabPart = grabData.Part
	if grabPart and grabPart.Parent then
		local grabAtt = criarGrabAttachment(grabPart, posAlvo, cfAlvo)
		criarAlignPositionDoisPontos(hrp, grabAtt, true)
		criarAlignOrientationDoisPontos(hrp, grabAtt, true)
	else
		criarAlignPosition(hrp, posAlvo, 40)
		criarAlignOrientation(hrp, cfAlvo, 40)
	end

	if Configs.DebugVerbose then
		local resolvedDebug = idleDecisionDebug or {}
		resolvedDebug.Source = resolvedDebug.Source or debugSource or "SyncGrab"
		resolvedDebug.Reason = resolvedDebug.Reason or "SyncRequested"
		resolvedDebug.EdgePosition = resolvedDebug.EdgePosition or grabData.EdgePosition
		resolvedDebug.Normal = resolvedDebug.Normal or grabData.Normal
		resolvedDebug.HrpPosition = hrp.Position
		traceIdleDecision(resolvedDebug.Source, idleAnterior, idleFinal, resolvedDebug, finalConfig, true)
	end
	AnimacaoParkour.TocarIdle(idleFinal)
	updateCameraBypass(hrp)

	return true
end

local function finalizarAcaoMantendoGrab()
	estado.EmAcao = false
	if estado.Agarrado and getValidGrabData() then
		local grabData = getValidGrabData()
		if not grabData then
			return
		end
		local idleResolvido, idleDebug = resolverIdleModeParaGrab(
			estado.CurrentCharacter,
			grabData.Part,
			grabData.EdgePosition,
			grabData.Normal,
			grabData.Config,
			grabData.IdleMode,
			"FinalizarAcaoMantendoGrab"
		)
		sincronizarGrabComIdle(idleResolvido, "FinalizarAcaoMantendoGrab", idleDebug)
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
	if ClientBridge.EntrarParkour then
		ClientBridge.EntrarParkour()
	end

	conectarDied(character)

	-- Travar o humanoid
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true

	-- Calcular posição alvo
	local grabPart = result.Part or (result.Result and result.Result.Instance)
	local posAlvo, cfAlvo, ajustadaPosicao, bloqueador = calcularPosicaoGrabSegura(
		character,
		hrp,
		result.EdgePosition,
		result.Normal,
		grabPart,
		finalConfig,
		result.IdleMode
	)

	if ajustadaPosicao then
		dbgPrint(
			"[Parkour] Grab target ajustado para posição segura",
			"| blocker:",
			bloqueador and bloqueador.Name or "nil"
		)
	end

	-- Criar constraints para transição suave (OneAttachment — estável, sem feedback de força)
	local grabTransitionTime = getScaledTransitionTime(finalConfig.GrabTransitionTime)
	local grabResponsiveness = 1 / grabTransitionTime * 10
	local grabAngVel = calcularVelocidadeAngularSuave(hrp.CFrame, cfAlvo, grabTransitionTime)
	local alignPos = criarAlignPosition(hrp, posAlvo, grabResponsiveness)
	local alignOri = criarAlignOrientation(hrp, cfAlvo, grabResponsiveness, grabAngVel)
	local grabReachDistance = math.max(finalConfig.GrabFinalReachDistance or 0.2, 0.03)
	local grabSnapTimeout = math.max(
		finalConfig.GrabFinalSnapTimeout or (grabTransitionTime + 0.25),
		grabTransitionTime
	)
	local grabMinSettleTime = math.max(finalConfig.GrabMinSettleTime or math.min(grabTransitionTime, 0.1), 0)

	-- Zerar velocidade atual para transição suave
	zeroAssemblyVelocity(hrp)
	setHeadCollisionDuringParkour(character, true)

	-- Salvar dados do grab para ações futuras (Subir, Escalar, PuloTras)
	setGrabData(
		result.EdgePosition,
		result.Normal,
		grabPart,
		result.IdleMode,
		nil,
		finalConfig,
		hrp.CFrame.LookVector
	)

	-- Marcar como agarrado após tempo de transição
	local idleInicial = result.IdleMode or "IdleSuporte"

	local grabFinalizado = false
	local grabHeartbeatConn: RBXScriptConnection? = nil

	local function finalizarGrabComConfirmacao()
		if grabFinalizado then
			return
		end
		grabFinalizado = true

		if grabHeartbeatConn then
			grabHeartbeatConn:Disconnect()
			grabHeartbeatConn = nil
		end

		if not isCharacterAlive(character) or estado.CurrentCharacter ~= character then
			return
		end

		-- Garantia rígida: só confirma agarrado depois de snap exato no alvo de grab.
		hrp.CFrame = CFrame.new(posAlvo) * cfAlvo.Rotation
		zeroAssemblyVelocity(hrp)

		local sincronizou = sincronizarGrabComIdle(idleInicial, "FinalizarGrabInicial", nil)
		if not sincronizou then
			removeConstraint(alignPos)
			removeConstraint(alignOri)
			local partAtual = estado.GrabData and estado.GrabData.Part
			if partAtual and partAtual.Parent then
				local grabAtt = criarGrabAttachment(partAtual, posAlvo, cfAlvo)
				criarAlignPositionDoisPontos(hrp, grabAtt, true)
				criarAlignOrientationDoisPontos(hrp, grabAtt, true)
			else
				criarAlignPosition(hrp, posAlvo, 80)
				criarAlignOrientation(hrp, cfAlvo, 80)
			end
			AnimacaoParkour.TocarIdle(idleInicial)
		end

		estado.Agarrado = true
		estado.EmAcao = false
	end

	local grabStart = os.clock()
	grabHeartbeatConn = RunService.Heartbeat:Connect(function()
		if grabFinalizado then
			return
		end

		if not alignPos.Parent or not alignOri.Parent then
			finalizarGrabComConfirmacao()
			return
		end

		if not isCharacterAlive(character) or estado.CurrentCharacter ~= character then
			if grabHeartbeatConn then
				grabHeartbeatConn:Disconnect()
				grabHeartbeatConn = nil
			end
			return
		end

		local elapsed = os.clock() - grabStart
		local dist = (hrp.Position - posAlvo).Magnitude
		if (elapsed >= grabMinSettleTime and dist <= grabReachDistance) or elapsed >= grabSnapTimeout then
			if elapsed >= grabSnapTimeout and dist > grabReachDistance then
				dbgPrint(
					"[Parkour] Grab snap por timeout",
					"| dist:",
					string.format("%.2f", dist)
				)
			end
			finalizarGrabComConfirmacao()
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
	local vaultTargetOri = CFrame.lookAt(posFinal, posFinal + look, Vector3.yAxis)
	local vaultAngVel = calcularVelocidadeAngularSuave(hrp.CFrame, vaultTargetOri, transitionTime)
	local alignPos = criarAlignPosition(hrp, posFinal, responsiveness)
	local alignOri = criarAlignOrientation(hrp, vaultTargetOri, responsiveness, vaultAngVel)

	-- Zerar velocidade para transição limpa
	zeroAssemblyVelocity(hrp)

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

		-- Libera EmAcao imediatamente ao completar o movimento.
		-- A animação continua blendando normalmente em paralelo.
		-- Permite encadear vaults em superfícies próximas sem cooldown artificial.
		estado.EmAcao = false
	end)

	local nomeAnimacao = if impulso == finalConfig.VaultMedioImpulse then "VaultMedio" else "VaultBaixo"
	AnimacaoParkour.TocarAcao(nomeAnimacao, nil, nil)

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

		local totalTime = getScaledTransitionTime(finalConfig.SubirTransitionTime)
		local startPos = hrp.Position
		local posVertical = Vector3.new(startPos.X, posAlvo.Y, startPos.Z)

		-- Duas fases como lateral: fase 1 = vertical, fase 2 = horizontal até posição final
		-- Rotação constante distribuída por todo o tempo total
		local phaseSplit = math.clamp(finalConfig.SubirTransitionPhaseSplit or 0.55, 0.2, 0.8)
		local tempoFase1 = math.max(totalTime * phaseSplit, 0.01)
		local tempoFase2 = math.max(totalTime - tempoFase1, 0.01)
		local responsivenessFase1 = 1 / tempoFase1 * 10
		local responsivenessFase2 = 1 / tempoFase2 * 10
		local subirAngVel = calcularVelocidadeAngularSuave(hrp.CFrame, cfAlvo, totalTime)

		local alignPos = criarAlignPosition(hrp, posVertical, responsivenessFase1)
		criarAlignOrientation(hrp, cfAlvo, responsivenessFase1, subirAngVel)

		zeroAssemblyVelocity(hrp)

		setGrabData(
			novaEdgePos,
			novaNormal,
			novaPart or (estado.GrabData and estado.GrabData.Part),
			idleModeNovo,
			nil,
			finalConfig,
			hrp.CFrame.LookVector
		)

		task.delay(tempoFase1, function()
			if alignPos.Parent and isCharacterAlive(character) then
				alignPos.Position = posAlvo
				alignPos.Responsiveness = responsivenessFase2
				-- Não altera orientação: rotação constante por todo totalTime
			end
		end)

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

	local function tentarFinalizarDescer()
		if finalizacaoExecutada then
			return
		end

		if not (transicaoConcluida and animacaoConcluida) then
			return
		end

		finalizacaoExecutada = true
		-- Encerrar a pose estática de Descer antes de ir pro Idle
		AnimacaoParkour.EncerrarAcaoAtual(finalConfig.SubirSaltoIdleFadeOut or 0.06)
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
		local descerTime = getScaledTransitionTime(finalConfig.DescerTransitionTime)
		local responsiveness = 1 / descerTime * 10
		local descerAngVel = calcularVelocidadeAngularSuave(hrp.CFrame, cfAlvo, descerTime)
		local alignPos = criarAlignPosition(hrp, posAlvo, responsiveness)
		local alignOri = criarAlignOrientation(hrp, cfAlvo, responsiveness, descerAngVel)

		zeroAssemblyVelocity(hrp)

		setGrabData(
			novaEdgePos,
			novaNormal,
			novaPart or (estado.GrabData and estado.GrabData.Part),
			idleModeNovo,
			nil,
			finalConfig,
			hrp.CFrame.LookVector
		)

		task.delay(descerTime, function()
			if alignPos.Parent and alignOri.Parent and isCharacterAlive(character) then
				estado.Agarrado = true
			end

			transicaoConcluida = true
			tentarFinalizarDescer()
		end)
	end

	local okAnimacao = AnimacaoParkour.TocarAcao("Descer", executarMovimentoDescer, function()
		animacaoConcluida = true
		tentarFinalizarDescer()
	end)

	-- Animação de Descer é um único frame (pose estática).
	-- Marcar como concluída imediatamente para não travar esperando Stopped.
	if okAnimacao then
		animacaoConcluida = true
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
			dbgPrint("[Parkour] Lateral bloqueado por segurança | Horiz:", string.format("%.2f", horizontal), "| Vert:", string.format("%.2f", vertical))
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
	local tempoTotal = math.max(getScaledTransitionTime(finalConfig.LateralTransitionTime or 0.2), 0.01)

	local function tentarFinalizarLateral()
		if finalizacaoExecutada then
			return
		end

		if not (transicaoConcluida and animacaoConcluida) then
			return
		end

		finalizacaoExecutada = true
		finalizarAcaoMantendoGrab()
	end

	local function executarMovimentoLateral()
		if movimentoExecutado then
			return
		end
		movimentoExecutado = true

		destroyConstraints()

		local posAlvo, cfAlvo = calcularPosicaoGrab(
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

		local phaseSplit = math.clamp(finalConfig.LateralTransitionPhaseSplit or 0.55, 0.2, 0.8)
		local tempoFase1 = math.max(tempoTotal * phaseSplit, 0.01)
		local tempoFase2 = math.max(tempoTotal - tempoFase1, 0.01)
		local responsivenessFase1 = 1 / tempoFase1 * 10
		local responsivenessFase2 = 1 / tempoFase2 * 10

		-- Rotação suave constante: alvo final (normal da nova superfície), velocidade distribuída por todo tempoTotal
		local lateralAngVel = calcularVelocidadeAngularSuave(hrp.CFrame, cfAlvo, tempoTotal)
		local alignPos = criarAlignPosition(hrp, phase1Target, responsivenessFase1)
		local alignOri = criarAlignOrientation(hrp, cfAlvo, responsivenessFase1, lateralAngVel)

		zeroAssemblyVelocity(hrp)

		setGrabData(
			lateralResult.EdgePosition,
			lateralResult.Normal,
			lateralResult.Part,
			lateralResult.IdleMode,
			lateralResult.Estado,
			finalConfig,
			hrp.CFrame.LookVector
		)

		task.delay(tempoFase1, function()
			if alignPos.Parent and alignOri.Parent and isCharacterAlive(character) then
				alignPos.Position = phase1Target + phase2Delta
				alignPos.Responsiveness = responsivenessFase2
				-- Não altera responsiveness/velocidade da orientação: rotação constante por todo tempoTotal
			end
		end)

		task.delay(tempoTotal, function()
			if alignPos.Parent and alignOri.Parent and isCharacterAlive(character) then
				estado.Agarrado = true
			end

			transicaoConcluida = true
			tentarFinalizarLateral()
		end)
	end

	local okAnimacao = AnimacaoParkour.TocarAcao(nomeAnimacao, executarMovimentoLateral, function()
		animacaoConcluida = true
		tentarFinalizarLateral()
	end)

	if not okAnimacao then
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

	-- Calcular posições das duas fases
	local normal = escalarResult.Normal or (estado.GrabData and estado.GrabData.Normal) or hrp.CFrame.LookVector

	-- Flatten look para escalar sempre na vertical (sem inclinação)
	local look = Vector3.new(-normal.X, 0, -normal.Z)
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	look = look.Unit

	-- Fase 1: subir apenas no eixo Y a partir da posição atual
	local startPos = hrp.Position
	local posUp = Vector3.new(startPos.X, escalarResult.EdgePosition.Y + finalConfig.EscalarUpOffset, startPos.Z)

	-- Fase 2: mover pra frente na posição final
	local posFinal = escalarResult.PosFinal

	local ratioVertical = math.clamp(finalConfig.EscalarVerticalFirstRatio or 0.5, 0.1, 0.9)
	local escalarTime = getScaledTransitionTime(finalConfig.EscalarTransitionTime)
	local tempoVertical = escalarTime * ratioVertical
	local tempoHorizontal = escalarTime - tempoVertical
	local responsivenessVertical = 1 / math.max(tempoVertical, 0.01) * 12
	local responsivenessHorizontal = 1 / math.max(tempoHorizontal, 0.01) * 12
	local snapDistance = math.max(finalConfig.EscalarFinalSnapDistance or 0.2, 0.05)
	local snapTimeout = math.max(
		finalConfig.EscalarFinalSnapTimeout or (escalarTime + 0.2),
		escalarTime
	)

	-- Orientação: sempre vertical (100% reto), olhar para frente
	local targetOri = CFrame.lookAt(posFinal, posFinal + look, Vector3.yAxis)

	-- Fase 1: AlignPosition leva o player para CIMA
	local escalarAngVel = calcularVelocidadeAngularSuave(hrp.CFrame, targetOri, escalarTime)
	local alignPos = criarAlignPosition(hrp, posUp, responsivenessVertical)
	local alignOri = criarAlignOrientation(hrp, targetOri, responsivenessVertical, escalarAngVel)

	zeroAssemblyVelocity(hrp)

	local movimentoConcluido = false
	local animacaoConcluida = false
	local heartbeatConn: RBXScriptConnection? = nil

	local function tentarFinalizar()
		if not (movimentoConcluido and animacaoConcluida) then
			return
		end

		setHeadCollisionDuringParkour(character, false)

		AnimacaoParkour.ResetarBraco()
		if ClientBridge.SairParkour then
			ClientBridge.SairParkour()
		end

		CameraBypass.clear()

		estado.EmAcao = false
		estado.GrabData = nil
		estado.CurrentCharacter = nil
	end

	local function finalizarMovimentoEscalar()
		if movimentoConcluido then
			return
		end

		if heartbeatConn then
			heartbeatConn:Disconnect()
			heartbeatConn = nil
		end

		removeConstraint(alignPos)
		removeConstraint(alignOri)

		hrp.CFrame = CFrame.new(posFinal) * targetOri.Rotation
		zeroAssemblyVelocity(hrp)

		humanoid.AutoRotate = true
		humanoid.PlatformStand = false

		-- Snap final pós-restore para garantir posição exata.
		hrp.CFrame = CFrame.new(posFinal) * targetOri.Rotation
		zeroAssemblyVelocity(hrp)

		movimentoConcluido = true
		tentarFinalizar()
	end

	-- Fase 2: Após subir, mover pra FRENTE
	task.delay(tempoVertical, function()
		if alignPos.Parent and isCharacterAlive(character) then
			alignPos.Position = posFinal
			alignPos.Responsiveness = responsivenessHorizontal
			alignOri.Responsiveness = responsivenessHorizontal
		end
	end)

	local startTime = os.clock()
	heartbeatConn = RunService.Heartbeat:Connect(function()
		if movimentoConcluido then
			return
		end

		if not isCharacterAlive(character) then
			if heartbeatConn then
				heartbeatConn:Disconnect()
				heartbeatConn = nil
			end
			removeConstraint(alignPos)
			removeConstraint(alignOri)
			movimentoConcluido = true
			tentarFinalizar()
			return
		end

		local dist = (hrp.Position - posFinal).Magnitude
		local elapsed = os.clock() - startTime
		if dist <= snapDistance or elapsed >= snapTimeout then
			if elapsed >= snapTimeout and dist > snapDistance then
				dbgPrint(
					"[Parkour] Escalar snap por timeout",
					"| dist:",
					string.format("%.2f", dist)
				)
			end
			finalizarMovimentoEscalar()
		end
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

	local finalizadoPuloTras = false
	local function finalizarPuloTras()
		if finalizadoPuloTras then
			return
		end
		finalizadoPuloTras = true
		AnimacaoParkour.ResetarBraco()
		fullCleanup()
	end

	-- Não esperar a animação inteira para liberar re-detecção de parkour no ar.
	task.delay(0.2, finalizarPuloTras)

	local okAnimacao = AnimacaoParkour.TocarAcao("PuloTras", nil, function()
		finalizarPuloTras()
	end)

	if not okAnimacao then
		finalizarPuloTras()
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

	-- Verificar escalar e subir no mesmo frame para permitir preferência contextual.
	local escalarResult = Analisador.CheckEscalar(
		character,
		grabData.EdgePosition,
		grabData.Normal,
		grabData.Part,
		grabData.Config
	)
	local subirResult = Analisador.CheckSubir(
		character,
		grabData.EdgePosition,
		grabData.Normal,
		grabData.Config
	)

	local escalarDisponivel = escalarResult and escalarResult.CanEscalar
	local subirDisponivel = subirResult and subirResult.CanSubir

	-- Entre SubirSalto e Escalar, prioriza SubirSalto (confirmação por pulo/hold no input layer).
	if subirDisponivel and subirResult.Tipo == "SubirSalto" then
		return true, "SubirSalto", subirResult, escalarResult
	end

	if escalarDisponivel then
		local ok = executarEscalar(escalarResult, grabData.Config)
		if ok then
				dbgPrint("[Parkour] Escalar para cima da plataforma")
		end
		return ok, "Escalar", nil, escalarResult
	end

	if not subirDisponivel then
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
				dbgPrint("[Parkour] Subir para nova superfície | Dist:", string.format("%.1f", subirResult.VerticalDistance))
		end
		return ok, "Subir", subirResult, escalarResult
	elseif subirResult.Tipo == "SubirSalto" then
		return true, "SubirSalto", subirResult, escalarResult
	elseif subirResult.Tipo == "Escalar" then
		-- Fallback disparado pelo CheckSubir
		local ok = executarEscalar(subirResult, grabData.Config)
		if ok then
				dbgPrint("[Parkour] Escalar direto para nova superfície acima | Dist:", string.format("%.1f", subirResult.VerticalDistance))
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
		dbgPrint("[Parkour] Descer para superfície abaixo | Dist:", string.format("%.1f", descerResult.VerticalDistance))
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
		dbgPrint("[Parkour]", lateralResult.Estado, "| Dist:", string.format("%.2f", lateralResult.HorizontalDistance))
	end

	return ok, lateralResult.Estado, lateralResult
end

function Movimento.ExecutarLateralForcado(lateralTarget)
	if not estado.Agarrado or estado.EmAcao then
		return false
	end

	if not lateralTarget or not lateralTarget.EdgePosition or not lateralTarget.Normal then
		return false
	end

	local grabData = getValidGrabData()
	if not grabData then
		return false
	end

	local direcao = lateralTarget.Direction
	if direcao ~= "Direita" and direcao ~= "Esquerda" then
		if type(lateralTarget.Estado) == "string" and string.find(lateralTarget.Estado, "Esquerda", 1, true) then
			direcao = "Esquerda"
		else
			direcao = "Direita"
		end
	end

	local idleMode = lateralTarget.IdleMode or grabData.IdleMode or "IdleSuporte"
	local lateralEstado = lateralTarget.Estado or (direcao .. (idleMode == "IdleSuporte" and "Suporte" or "Suspenso"))

	local lateralResult = {
		CanMoveLateral = true,
		Reason = "Forced",
		Direction = direcao,
		Estado = lateralEstado,
		IdleMode = idleMode,
		IsCorner = lateralTarget.IsCorner,
		CornerType = lateralTarget.CornerType,
		EdgePosition = lateralTarget.EdgePosition,
		Normal = lateralTarget.Normal,
		Part = lateralTarget.Part,
		VerticalDelta = lateralTarget.VerticalDelta,
		HorizontalDistance = lateralTarget.HorizontalDistance,
	}

	local ok = executarLateral(lateralResult, grabData.Config)
	if ok then
		dbgPrint("[Parkour] Curva interna automática após espera do LateralSalto")
	end

	return ok
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
		dbgPrint("[Parkour] SubirSalto para superfície | Dist:", string.format("%.1f", subirResult.VerticalDistance))
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
		dbgPrint("[Parkour] SubirSalto confirmado")
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
	local transicaoTempo = getScaledTransitionTime(finalConfig.LateralSaltoTransitionTime or finalConfig.LateralTransitionTime or 0.28)

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
		local lateralSaltoAngVel = calcularVelocidadeAngularSuave(hrp.CFrame, cfAlvo, transicaoTempo)
		local alignPos = criarAlignPosition(hrp, posAlvo, responsiveness)
		local alignOri = criarAlignOrientation(hrp, cfAlvo, responsiveness, lateralSaltoAngVel)

		zeroAssemblyVelocity(hrp)

		setGrabData(
			alvoLateralSalto.EdgePosition,
			alvoLateralSalto.Normal,
			alvoLateralSalto.Part,
			idleModeNovo,
			direcao .. "Salto",
			finalConfig,
			hrp.CFrame.LookVector
		)

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

	dbgPrint("[Parkour] LateralSalto confirmado:", direcao)
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
			sincronizarGrabComIdle(estado.GrabData.IdleMode, "CancelarPreviewLateralAoSoltar", nil)
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
	local idleAtual = grabData.IdleMode or "IdleSuporte"
	local idleNovo, idleDebug = resolverIdleModeParaGrab(
		character,
		grabData.Part,
		grabData.EdgePosition,
		grabData.Normal,
		finalConfig,
		grabData.IdleMode,
		"HeartbeatRecheck"
	)
	if not idleNovo then
		return false
	end

	local idleEstavel, confirmouTroca = resolveStableIdleMode(grabData, idleNovo, finalConfig, idleDebug)
	if confirmouTroca then
		sincronizarGrabComIdle(idleEstavel, "HeartbeatRecheck", idleDebug)
	elseif idleDebug then
		idleDebug.HrpPosition = hrp.Position
		traceIdleDecision("HeartbeatRecheck", idleAtual, idleEstavel, idleDebug, finalConfig, false)
	end
	return confirmouTroca
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
		dbgPrint("[Parkour] Escalar para cima da plataforma")
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
		dbgPrint("[Parkour] PuloTras")
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
		dbgPrint("[Parkour]", direcao .. "Salto")
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
