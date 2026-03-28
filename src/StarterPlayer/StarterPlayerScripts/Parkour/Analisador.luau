local Workspace = game:GetService("Workspace")

local Configs = require(script.Parent:WaitForChild("Configs"))
local Utilidades = require(script.Parent:WaitForChild("Utilidades"))
local Debug = require(script.Parent:WaitForChild("Debug"))

local Analisador = {}

-- ══════════════════════════════════════
-- Funções Internas (local)
-- ══════════════════════════════════════

local function computeFaceVerticalEdges(part, result)
	local half = part.Size / 2

	local hitLocal = part.CFrame:PointToObjectSpace(result.Position)
	local normalLocal = part.CFrame:VectorToObjectSpace(result.Normal)
	local worldUpLocal = part.CFrame:VectorToObjectSpace(Vector3.new(0, 1, 0))

	local faceAxis, faceSign, tangentA, tangentB = Utilidades.getFaceAxes(normalLocal)

	local verticalAxis
	local otherAxis

	if math.abs(Utilidades.getAxisValue(worldUpLocal, tangentA))
		>= math.abs(Utilidades.getAxisValue(worldUpLocal, tangentB))
	then
		verticalAxis = tangentA
		otherAxis = tangentB
	else
		verticalAxis = tangentB
		otherAxis = tangentA
	end

	local topSign = Utilidades.getAxisValue(worldUpLocal, verticalAxis) >= 0 and 1 or -1

	local coords = {
		X = math.clamp(hitLocal.X, -half.X, half.X),
		Y = math.clamp(hitLocal.Y, -half.Y, half.Y),
		Z = math.clamp(hitLocal.Z, -half.Z, half.Z),
	}

	coords[faceAxis] = faceSign * Utilidades.getAxisValue(half, faceAxis)
	coords[otherAxis] = math.clamp(
		Utilidades.getAxisValue(hitLocal, otherAxis),
		-Utilidades.getAxisValue(half, otherAxis),
		Utilidades.getAxisValue(half, otherAxis)
	)

	local topCoords = {
		X = coords.X,
		Y = coords.Y,
		Z = coords.Z,
	}

	local bottomCoords = {
		X = coords.X,
		Y = coords.Y,
		Z = coords.Z,
	}

	topCoords[verticalAxis] = topSign * Utilidades.getAxisValue(half, verticalAxis)
	bottomCoords[verticalAxis] = -topSign * Utilidades.getAxisValue(half, verticalAxis)

	return Utilidades.vectorFromTable(topCoords), Utilidades.vectorFromTable(bottomCoords)
end

local function buildResultFromCast(castData)
	if not castData then
		return nil
	end

	local topLocal, bottomLocal = computeFaceVerticalEdges(castData.Part, castData.Result)

	castData.TopEdgePosition = castData.Part.CFrame:PointToWorldSpace(topLocal)
	castData.BottomEdgePosition = castData.Part.CFrame:PointToWorldSpace(bottomLocal)

	return castData
end

local function isWallLikeNormal(normal, config)
	local maxWallNormalY = config.MaxWallNormalY or 0.35
	return math.abs(normal.Unit.Y) <= maxWallNormalY
end

local function hasBothClearances(character, part, edgePosition, normal, finalConfig)
	local data = {
		Character = character,
		Part = part,
		EdgePosition = edgePosition,
		Normal = normal,
	}

	local hasTopClearance = Analisador.HasTopClearance(data, finalConfig)
	if not hasTopClearance then
		return false, false
	end

	local hasFrontClearance = Analisador.HasFrontClearance(data, finalConfig)
	return hasTopClearance, hasFrontClearance
end

local function checkEscalarAtEdge(character, currentEdgePos, currentNormal, currentPart, finalConfig, debugContext)
	if not isWallLikeNormal(currentNormal, finalConfig) then
		Debug.Verbose("  RESULTADO: InvalidCurrentNormalForEscalar | Normal:", currentNormal)
		return {
			CanEscalar = false,
			Reason = "InvalidCurrentNormalForEscalar",
		}
	end

	if debugContext then
		Debug.Verbose("═══ CheckEscalar [" .. debugContext .. "] ═══")
	else
		Debug.Verbose("═══ CheckEscalar ═══")
	end
	Debug.Verbose("  EdgePos:", currentEdgePos, "| Normal:", currentNormal)
	Debug.Verbose("  Part:", currentPart and currentPart.Name or "nil")

	local look = -currentNormal.Unit
	local center = currentEdgePos
		+ Vector3.yAxis * (finalConfig.EscalarClearanceUpOffset or finalConfig.EscalarUpOffset)
		+ look * (finalConfig.EscalarClearanceForwardOffset or finalConfig.EscalarForwardOffset)

	local cf = CFrame.lookAt(center, center + look, Vector3.yAxis)
	local clearanceSize = finalConfig.EscalarClearanceSize or finalConfig.VaultClearanceSize
	local minH = finalConfig.MinPartHeight

	Debug.Verbose("  ClearanceCenter:", center, "| Size:", clearanceSize)

	local ignoreList = {character}
	if currentPart then
		table.insert(ignoreList, currentPart)
	end

	local clear, blocker = Utilidades.firstBlockingPartInBox(
		cf,
		clearanceSize,
		ignoreList,
		function(part) return Utilidades.isIgnorablePart(part, minH) end
	)

	Debug.Verbose("  ClearanceResult: clear=", clear, "| blocker=", blocker and blocker.Name or "nil")

	local posFinal = currentEdgePos
		+ Vector3.yAxis * finalConfig.EscalarUpOffset
		+ look * finalConfig.EscalarForwardOffset

	if not clear then
		Debug.Verbose("  RESULTADO: NoClearanceOnTop | Blocker:", blocker and blocker.Name or "nil")
		return {
			CanEscalar = false,
			Reason = "NoClearanceOnTop",
			Blocker = blocker,
			ClearanceCFrame = cf,
			ClearanceSize = clearanceSize,
		}
	end

	Debug.Verbose("  RESULTADO: CanEscalar=true | PosFinal:", posFinal)
	return {
		CanEscalar = true,
		PosFinal = posFinal,
		EdgePosition = currentEdgePos,
		Normal = currentNormal,
		Part = currentPart,
		ClearanceCFrame = cf,
		ClearanceSize = clearanceSize,
	}
end

-- ══════════════════════════════════════
-- Debug (repassa para o módulo Debug)
-- ══════════════════════════════════════

function Analisador.ClearDebug()
	Debug.ClearDebug()
end

function Analisador.DrawDebug(data)
	Debug.DrawDebug(data)
end

-- ══════════════════════════════════════
-- Clearance (Topo / Frente)
-- ══════════════════════════════════════

function Analisador.HasTopClearance(data, config)
	local finalConfig = Configs.mergeConfig(config)
	local normal = data.Normal.Unit
	local center = data.EdgePosition
		+ Vector3.yAxis * finalConfig.TopClearanceUpOffset
		+ normal * finalConfig.TopClearanceNormalOffset

	local cf = Utilidades.getSurfaceFrame(center, normal)
	local minH = finalConfig.MinPartHeight
	local clear, blocker = Utilidades.firstBlockingPartInBox(
		cf,
		finalConfig.TopClearanceSize,
		{data.Character, data.Part},
		function(part) return Utilidades.isIgnorablePart(part, minH) end
	)

	return clear, blocker, cf, finalConfig.TopClearanceSize
end

function Analisador.HasFrontClearance(data, config)
	local finalConfig = Configs.mergeConfig(config)
	local normal = data.Normal.Unit
	local center = data.EdgePosition
		+ Vector3.yAxis * finalConfig.FrontClearanceUpOffset
		+ normal * finalConfig.FrontClearanceNormalOffset

	local cf = Utilidades.getSurfaceFrame(center, normal)
	local minH = finalConfig.MinPartHeight
	local clear, blocker = Utilidades.firstBlockingPartInBox(
		cf,
		finalConfig.FrontClearanceSize,
		{data.Character, data.Part},
		function(part) return Utilidades.isIgnorablePart(part, minH) end
	)

	return clear, blocker, cf, finalConfig.FrontClearanceSize
end

-- ══════════════════════════════════════
-- Idle Mode (suporte vs suspenso)
-- ══════════════════════════════════════

function Analisador.ResolveIdleMode(data, config)
	local finalConfig = Configs.mergeConfig(config)

	if Utilidades.hasTagDeep(data.Part, Configs.Tags.FORCAR_SUSPENSO) then
		return "IdleSuspenso", nil, nil
	end

	local boxSize = finalConfig.LegSupportBoxSize or Vector3.new(1.9, 1.8, 1.4)
	local downOffset = finalConfig.LegSupportBoxDownOffset or finalConfig.LegProbeDownOffset or 2.8
	local normalOffset = finalConfig.LegSupportBoxNormalOffset or finalConfig.LegProbeStartNormalOffset or 0.9
	local center = data.EdgePosition
		- Vector3.yAxis * downOffset
		+ data.Normal.Unit * normalOffset
	local cf = Utilidades.getSurfaceFrame(center, data.Normal.Unit)
	local minH = finalConfig.MinPartHeight
	local clear, blocker = Utilidades.firstBlockingPartInBox(
		cf,
		boxSize,
		{data.Character},
		function(part) return Utilidades.isIgnorablePart(part, minH) end
	)

	local supportDebug = {
		CFrame = cf,
		Size = boxSize,
		Clear = clear,
		Blocker = blocker,
	}

	if not clear then
		return "IdleSuporte", blocker, supportDebug
	end

	return "IdleSuspenso", nil, supportDebug
end


-- ══════════════════════════════════════
-- Vault: Clearance no Destino
-- ══════════════════════════════════════

function Analisador.HasVaultClearance(data, config)
	local finalConfig = Configs.mergeConfig(config)
	local look = data.LookVector
	local bordaReal = data.EdgePosition

	-- Centro da caixa de verificação (clearance) - precisa de espaço real
	local margin = 0.05
	local clearanceCenter = bordaReal
		+ Vector3.yAxis * (finalConfig.VaultClearanceUpOffset + margin)
		+ look * finalConfig.VaultClearanceForwardOffset

	local cf = CFrame.lookAt(clearanceCenter, clearanceCenter + look, Vector3.yAxis)
	local minH = finalConfig.MinPartHeight
	local clear, blocker = Utilidades.firstBlockingPartInBox(
		cf,
		finalConfig.VaultClearanceSize,
		{data.Character, data.Part},
		function(part) return Utilidades.isIgnorablePart(part, minH) end
	)

	-- Posição final: apenas ACIMA da borda (sem offset pra frente)
	-- O impulso horizontal será aplicado depois via LinearVelocity
	local posFinal = bordaReal
		+ Vector3.yAxis * finalConfig.VaultMoveUpOffset

	return clear, blocker, cf, finalConfig.VaultClearanceSize, posFinal
end

-- ══════════════════════════════════════
-- Vault: Clearance na Borda (espaço pra passar)
-- ══════════════════════════════════════

function Analisador.HasVaultEdgeClearance(data, config)
	local finalConfig = Configs.mergeConfig(config)
	local bordaReal = data.EdgePosition
	local look = data.LookVector

	local center = bordaReal + Vector3.yAxis * (finalConfig.VaultEdgeClearanceUpOffset or (finalConfig.VaultClearanceSize.Y / 2))

	local cf = CFrame.lookAt(center, center + look, Vector3.yAxis)
	local minH = finalConfig.MinPartHeight
	local clear, blocker = Utilidades.firstBlockingPartInBox(
		cf,
		finalConfig.VaultClearanceSize,
		{data.Character, data.Part},
		function(part) return Utilidades.isIgnorablePart(part, minH) end
	)

	return clear, blocker, cf, finalConfig.VaultClearanceSize
end

-- ══════════════════════════════════════
-- Probes XZ (torso + perna)
-- ══════════════════════════════════════

local function getHorizontalUnit(vector)
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < 0.001 then
		return nil
	end

	return flat.Unit
end

local function isValidForwardProbeHit(result, config)
	if not result or not result.Instance or not result.Instance:IsA("BasePart") then
		return false
	end

	local hitPart = result.Instance
	if Utilidades.isIgnorablePart(hitPart, config.MinPartHeight) then
		return false
	end

	if Utilidades.hasTagDeep(hitPart, Configs.Tags.NAO_AGARRAVEL) then
		return false
	end

	return true
end

local function castRayToEdgeXZ(hrpPosition, edgePosition, yOffset, distance, extraDistance, rayParams, config)
	local origin = hrpPosition + Vector3.yAxis * yOffset
	local toEdge = Vector3.new(edgePosition.X - origin.X, 0, edgePosition.Z - origin.Z)

	if toEdge.Magnitude < 0.05 then
		return {
			Origin = origin,
			HitPosition = origin,
			Hit = false,
			Result = nil,
		}
	end

	local maxDistance = distance or 8
	local overshoot = extraDistance or 0
	local castDistance = math.min(maxDistance, toEdge.Magnitude + overshoot)
	local direction = toEdge.Unit * castDistance
	local result = Workspace:Raycast(origin, direction, rayParams)
	local validHit = isValidForwardProbeHit(result, config)

	return {
		Origin = origin,
		HitPosition = result and result.Position or (origin + direction),
		Hit = validHit,
		Result = result,
	}
end

local LATERAL_SAMPLE_MULTIPLIERS = table.freeze({ 0.7, 1.0, 1.25 })

local function getLateralDirection(currentNormal, direcao)
	local wallForward = -currentNormal.Unit
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

local function buildCastDataFromPartPoint(character, part, samplePoint, preferredNormal)
	local half = part.Size / 2
	local localPoint = part.CFrame:PointToObjectSpace(samplePoint)

	local axis
	local sign
	if preferredNormal and preferredNormal.Magnitude > 0.001 then
		local preferredLocal = part.CFrame:VectorToObjectSpace(preferredNormal.Unit)
		axis, sign = Utilidades.dominantAxis(preferredLocal)
	else
		local distances = {
			X = half.X - math.abs(localPoint.X),
			Y = half.Y - math.abs(localPoint.Y),
			Z = half.Z - math.abs(localPoint.Z),
		}

		axis = "X"
		if distances.Y < distances[axis] then
			axis = "Y"
		end
		if distances.Z < distances[axis] then
			axis = "Z"
		end

		sign = Utilidades.getAxisValue(localPoint, axis) >= 0 and 1 or -1
	end
	local clampedLocal = Vector3.new(
		math.clamp(localPoint.X, -half.X, half.X),
		math.clamp(localPoint.Y, -half.Y, half.Y),
		math.clamp(localPoint.Z, -half.Z, half.Z)
	)

	local facePointTable = {
		X = clampedLocal.X,
		Y = clampedLocal.Y,
		Z = clampedLocal.Z,
	}
	facePointTable[axis] = sign * Utilidades.getAxisValue(half, axis)

	local normalTable = { X = 0, Y = 0, Z = 0 }
	normalTable[axis] = sign

	local hitPosition = part.CFrame:PointToWorldSpace(Utilidades.vectorFromTable(facePointTable))
	local normal = part.CFrame:VectorToWorldSpace(Utilidades.vectorFromTable(normalTable)).Unit

	return {
		Character = character,
		Part = part,
		Result = {
			Position = hitPosition,
			Normal = normal,
		},
		Origin = samplePoint,
		HitPosition = hitPosition,
		Normal = normal,
	}
end

local function collectValidPartsInBox(cframe, size, ignoreList, minPartHeight)
	local params = Utilidades.createOverlapParams(ignoreList, 0)
	local rawParts = Workspace:GetPartBoundsInBox(cframe, size, params)
	local seen = {}
	local filtered = table.create(#rawParts)

	for _, part in ipairs(rawParts) do
		if part:IsA("BasePart") and not seen[part]
			and not Utilidades.isIgnorablePart(part, minPartHeight)
			and not Utilidades.hasTagDeep(part, Configs.Tags.NAO_AGARRAVEL)
		then
			seen[part] = true
			table.insert(filtered, part)
		end
	end

	return filtered
end

-- ══════════════════════════════════════
-- Busca frontal por bloco (caixa única)
-- ══════════════════════════════════════

local function findForwardEdgeInBox(character, hrp, look, config)
	local lookXZ = getHorizontalUnit(look)
	if not lookXZ then
		return nil, nil
	end

	local baseSize = config.ForwardObstacleBoxSize or Vector3.new(4.5, 5.5, 4.0)
	local nearOffset = math.max(0, config.ForwardObstacleBoxNearOffset or 0.05)
	local maxReach = math.max(nearOffset + 0.5, config.ForwardObstacleBoxDistance or 5.25)
	local depth = math.max(0.75, maxReach - nearOffset)
	local querySize = Vector3.new(baseSize.X, baseSize.Y, depth)
	local queryCenter = hrp.Position
		+ Vector3.yAxis * (config.ForwardObstacleBoxUpOffset or 0)
		+ lookXZ * (nearOffset + depth * 0.5)
	local queryCFrame = CFrame.lookAt(queryCenter, queryCenter + lookXZ, Vector3.yAxis)

	local parts = collectValidPartsInBox(queryCFrame, querySize, {character}, config.MinPartHeight)
	local samplePoint = hrp.Position + Vector3.yAxis * (config.ForwardObstacleSampleYOffset or 0)
	local maxDist = config.ForwardObstacleMaxDistance or config.RayDistance

	local candidatePoints = {}
	local bestData = nil
	local bestForwardDist = math.huge
	local bestLateralDist = math.huge

	for _, part in ipairs(parts) do
		local castData = buildCastDataFromPartPoint(character, part, samplePoint, -lookXZ)
		local built = buildResultFromCast(castData)
		if not built then
			continue
		end

		local edgePosition = built.TopEdgePosition
		local deltaXZ = Vector3.new(edgePosition.X - hrp.Position.X, 0, edgePosition.Z - hrp.Position.Z)
		local distXZ = deltaXZ.Magnitude
		local accepted = false

		if distXZ > 0.05 and distXZ <= maxDist then
			local forwardDist = deltaXZ:Dot(lookXZ)
			if forwardDist > 0.01 then
				accepted = true

				local lateral = (deltaXZ - lookXZ * forwardDist).Magnitude
				if forwardDist < bestForwardDist - 0.05
					or (math.abs(forwardDist - bestForwardDist) <= 0.05 and lateral < bestLateralDist)
				then
					bestData = built
					bestForwardDist = forwardDist
					bestLateralDist = lateral
				end
			end
		end

		table.insert(candidatePoints, {
			Position = edgePosition,
			Accepted = accepted,
		})
	end

	local debugData = {
		QueryBoxCFrame = queryCFrame,
		QueryBoxSize = querySize,
		CandidatePoints = candidatePoints,
	}

	return bestData, debugData
end

-- ══════════════════════════════════════
-- Classificar ação do pulo
-- ══════════════════════════════════════

local function classificarAcaoDePulo(bordaY, hrpY, torsoProbe, legProbe, config)
	local yTopoTorso = hrpY + config.TopoTorsoOffset

	if bordaY > yTopoTorso then
		return "Agarrar"
	elseif torsoProbe and torsoProbe.Hit then
		return "Agarrar"
	elseif legProbe and legProbe.Hit then
		return "VaultMedio"
	else
		return "VaultBaixo"
	end
end

-- ══════════════════════════════════════
-- Verificação Unificada: CheckParkour
-- ══════════════════════════════════════

function Analisador.CheckParkour(character, config)
	local finalConfig = Configs.mergeConfig(config)
	local hrp, head = Utilidades.getCharacterParts(character)
	local humanoid = character:FindFirstChild("Humanoid")
	if not hrp or not head or not humanoid then
		return {
			Aprovado = false,
			Reason = "NoCharacterParts",
		}
	end

	local look = hrp.CFrame.LookVector
	local lookXZ = getHorizontalUnit(look)
	if not lookXZ then
		return {
			Aprovado = false,
			Reason = "NoHorizontalLook",
		}
	end

	local rayParams = Utilidades.createRaycastParamsForCharacter(character)
	Debug.Verbose("═══ CheckParkour (Box+XZ) ═══")
	Debug.Verbose("  HRP:", hrp.Position, "| Floor:", humanoid.FloorMaterial)

	-- 1) Busca por bloco frontal: achar melhor borda candidata
	local edgeData, blockDebug = findForwardEdgeInBox(character, hrp, lookXZ, finalConfig)
	if not edgeData then
		Debug.Verbose(
			"  RESULTADO: NoForwardHit | candidates:",
			blockDebug and #blockDebug.CandidatePoints or 0,
			"| boxCenter:",
			blockDebug and blockDebug.QueryBoxCFrame and blockDebug.QueryBoxCFrame.Position or "nil"
		)
		return {
			Aprovado = false,
			Reason = "NoForwardHit",
			ForwardQueryBoxCFrame = blockDebug and blockDebug.QueryBoxCFrame or nil,
			ForwardQueryBoxSize = blockDebug and blockDebug.QueryBoxSize or nil,
			ForwardCandidatePoints = blockDebug and blockDebug.CandidatePoints or nil,
		}
	end

	-- Tag check
	if Utilidades.hasTagDeep(edgeData.Part, Configs.Tags.NAO_AGARRAVEL) then
		return {
			Aprovado = false,
			Reason = "TaggedNaoAgarravel",
			Part = edgeData.Part,
			ForwardQueryBoxCFrame = blockDebug and blockDebug.QueryBoxCFrame or nil,
			ForwardQueryBoxSize = blockDebug and blockDebug.QueryBoxSize or nil,
			ForwardCandidatePoints = blockDebug and blockDebug.CandidatePoints or nil,
		}
	end

	-- 2) Edge detection
	local data = edgeData
	data.EdgePosition = data.TopEdgePosition
	data.Mode = "Top"
	-- Na detecção por caixa não usamos ray frontal primário.
	-- Limpa campos legados para evitar qualquer dependência acidental de Origin/HitPosition.
	data.Origin = nil
	data.HitPosition = nil
	data.LookVector = lookXZ
	data.HrpPosition = hrp.Position
	data.ForwardQueryBoxCFrame = blockDebug and blockDebug.QueryBoxCFrame or nil
	data.ForwardQueryBoxSize = blockDebug and blockDebug.QueryBoxSize or nil
	data.ForwardCandidatePoints = blockDebug and blockDebug.CandidatePoints or nil

	-- 3) Rays XZ (torso + perna) na direção da borda encontrada
	data.TorsoRayDebug = castRayToEdgeXZ(
		hrp.Position,
		data.EdgePosition,
		finalConfig.TorsoRayOffset,
		finalConfig.ClassificationRayDistance or finalConfig.RayDistance,
		finalConfig.ClassificationRayExtraDistance,
		rayParams,
		finalConfig
	)
	data.LegRayDebug = castRayToEdgeXZ(
		hrp.Position,
		data.EdgePosition,
		finalConfig.PernaRayOffset,
		finalConfig.ClassificationRayDistance or finalConfig.RayDistance,
		finalConfig.ClassificationRayExtraDistance,
		rayParams,
		finalConfig
	)

	-- 4) Classificar ação
	local bordaReal = data.EdgePosition
	local acao = classificarAcaoDePulo(
		bordaReal.Y,
		hrp.Position.Y,
		data.TorsoRayDebug,
		data.LegRayDebug,
		finalConfig
	)
	data.Acao = acao

	Debug.Verbose(
		"  Classificacao:",
		acao,
		"| torsoHit:",
		data.TorsoRayDebug.Hit,
		"| legHit:",
		data.LegRayDebug.Hit,
		"| edge:",
		bordaReal
	)

	-- Calcular distancia real (3D) da borda até o HRP do player
	local distReal = (bordaReal - hrp.Position).Magnitude
	data.DistanceLine = {
		PosA = hrp.Position,
		PosB = bordaReal,
		Color = Color3.fromRGB(255, 0, 255), -- linha rosa para debug
	}

	-- 5) Verificações específicas por tipo
	local function tentarAgarrar()
		if humanoid.FloorMaterial ~= Enum.Material.Air then
			data.Aprovado = false
			data.Reason = "CantGrabOnGround"
			Debug.Verbose("  RESULTADO:", data.Reason)
			return data
		end

		if distReal > finalConfig.MaxGrabDistance then
			data.Aprovado = false
			data.Reason = "TooFarToGrab"
			Debug.Verbose("  RESULTADO:", data.Reason, "| dist:", distReal)
			return data
		end

		-- Top clearance
		local hasTopClearance, topBlocker, topCf, topSize = Analisador.HasTopClearance(data, finalConfig)
		data.TopClearanceCFrame = topCf
		data.TopClearanceSize = topSize

		if not hasTopClearance then
			data.Aprovado = false
			data.Reason = "NoTopClearance"
			data.TopBlocker = topBlocker
			Debug.Verbose("  RESULTADO:", data.Reason, "| blocker:", topBlocker and topBlocker.Name or "nil")
			return data
		end

		-- Front clearance
		local hasFrontClearance, frontBlocker, frontCf, frontSize = Analisador.HasFrontClearance(data, finalConfig)
		data.FrontClearanceCFrame = frontCf
		data.FrontClearanceSize = frontSize

		if not hasFrontClearance then
			data.Aprovado = false
			data.Reason = "NoFrontClearance"
			data.FrontBlocker = frontBlocker
			Debug.Verbose("  RESULTADO:", data.Reason, "| blocker:", frontBlocker and frontBlocker.Name or "nil")
			return data
		end

		-- Idle mode
		local idleMode, legHit, legProbeRaysDebug = Analisador.ResolveIdleMode(data, finalConfig)
		data.Aprovado = true
		data.Reason = "Ok"
		data.IdleMode = idleMode
		data.LegHit = legHit
		data.LegProbeRaysDebug = legProbeRaysDebug
		Debug.Verbose("  RESULTADO: Ok | Acao=Agarrar | Idle:", idleMode)

		return data
	end

	if acao == "Agarrar" then
		return tentarAgarrar()

	else -- VaultMedio ou VaultBaixo
		if distReal > finalConfig.MaxVaultDistance then
			data.Aprovado = false
			data.Reason = "TooFarToVault"
			Debug.Verbose("  RESULTADO:", data.Reason, "| dist:", distReal)
			return data
		end

		-- Vault clearance (destino)
		local hasVaultClearance, vaultBlocker, vaultCf, vaultSize, posFinal =
			Analisador.HasVaultClearance(data, finalConfig)
		data.VaultClearanceCFrame = vaultCf
		data.VaultClearanceSize = vaultSize
		data.PosFinal = posFinal

		if not hasVaultClearance then
			-- Fallback para Agarrar em caso de VaultMedio no ar
			if acao == "VaultMedio" and humanoid.FloorMaterial == Enum.Material.Air then
				data.Acao = "Agarrar"
				Debug.Verbose("  Fallback: VaultMedio -> Agarrar (NoVaultClearance)")
				return tentarAgarrar()
			end

			data.Aprovado = false
			data.Reason = "NoVaultClearance"
			data.VaultBlocker = vaultBlocker
			Debug.Verbose("  RESULTADO:", data.Reason, "| blocker:", vaultBlocker and vaultBlocker.Name or "nil")
			return data
		end

		-- Vault edge clearance (espaço na borda pra passar)
		local hasEdgeClearance, edgeBlocker, edgeCf, edgeSize =
			Analisador.HasVaultEdgeClearance(data, finalConfig)
		data.VaultClearanceCFrame = edgeCf
		data.VaultClearanceSize = edgeSize

		if not hasEdgeClearance then
			-- Fallback para Agarrar em caso de VaultMedio no ar
			if acao == "VaultMedio" and humanoid.FloorMaterial == Enum.Material.Air then
				data.Acao = "Agarrar"
				Debug.Verbose("  Fallback: VaultMedio -> Agarrar (NoVaultEdgeClearance)")
				return tentarAgarrar()
			end

			data.Aprovado = false
			data.Reason = "NoVaultEdgeClearance"
			data.VaultEdgeBlocker = edgeBlocker
			Debug.Verbose("  RESULTADO:", data.Reason, "| blocker:", edgeBlocker and edgeBlocker.Name or "nil")
			return data
		end

		data.Aprovado = true
		data.Reason = "Ok"
		Debug.Verbose("  RESULTADO: Ok | Acao:", data.Acao)
	end

	return data
end

-- ══════════════════════════════════════
-- Subir: Detectar superfície agarrável acima
-- Busca parts em volume acima e seleciona borda válida
-- ══════════════════════════════════════

function Analisador.CheckSubir(character, currentEdgePos, currentNormal, config)
	local finalConfig = Configs.mergeConfig(config)
	local hrp = Utilidades.getCharacterParts(character)
	if not hrp then
		return nil
	end

	if not isWallLikeNormal(currentNormal, finalConfig) then
		Debug.Verbose("  RESULTADO: InvalidCurrentNormalForSubir | Normal:", currentNormal)
		return {
			CanSubir = false,
			Reason = "InvalidCurrentNormalForSubir",
		}
	end

	local probeOffset = finalConfig.SubirProbeNormalOffset or 2.0
	local areaSize = finalConfig.SubirAreaSize or Vector3.new(6.0, 10.0, 6.0)
	local areaUpOffset = finalConfig.SubirAreaUpOffset or 5.0
	local areaCenter = currentEdgePos
		+ currentNormal.Unit * (probeOffset - areaSize.Z * 0.5)
		+ Vector3.yAxis * areaUpOffset
	local areaCFrame = Utilidades.getSurfaceFrame(areaCenter, currentNormal.Unit)

	local subirDebug = {
		QueryBoxCFrame = areaCFrame,
		QueryBoxSize = areaSize,
		CandidatePoints = {},
		EscalarChecks = {},
	}

	Debug.Verbose("═══ CheckSubir (Area) ═══")
	Debug.Verbose("  EdgePos:", currentEdgePos, "| Normal:", currentNormal)
	Debug.Verbose("  QueryCenter:", areaCenter, "| AreaSize:", areaSize)

	local parts = collectValidPartsInBox(areaCFrame, areaSize, {character}, finalConfig.MinPartHeight)
	local candidates = table.create(#parts)
	local minVerticalDelta = finalConfig.SubirMinVerticalDelta or 0.5
	local samplePointBase = currentEdgePos + currentNormal.Unit * probeOffset
	local maxEscalarVerticalDistance = finalConfig.EscalarMaxVerticalDistance or finalConfig.SubirMaxAltura or 6.0

	for _, part in ipairs(parts) do
		local castData = buildCastDataFromPartPoint(character, part, samplePointBase, currentNormal)
		local built = buildResultFromCast(castData)
		if not built then
			continue
		end

		local topEdge = built.TopEdgePosition
		local vertDist = topEdge.Y - currentEdgePos.Y
		if vertDist <= minVerticalDelta then
			table.insert(subirDebug.CandidatePoints, {
				Position = topEdge,
				Accepted = false,
			})
			continue
		end

		if not isWallLikeNormal(built.Normal, finalConfig) then
			table.insert(subirDebug.CandidatePoints, {
				Position = topEdge,
				Accepted = false,
			})
			continue
		end

		local horizDelta = Vector3.new(topEdge.X - currentEdgePos.X, 0, topEdge.Z - currentEdgePos.Z)
		local horizDist = horizDelta.Magnitude

		table.insert(candidates, {
			Part = part,
			EdgePosition = topEdge,
			Normal = built.Normal,
			VertDist = vertDist,
			HorizDist = horizDist,
		})

		table.insert(subirDebug.CandidatePoints, {
			Position = topEdge,
			Accepted = true,
		})
	end

	if #candidates == 0 then
		Debug.Verbose("  RESULTADO: NoSurfaceAbove")
		return {
			CanSubir = false,
			Reason = "NoSurfaceAbove",
			Debug = subirDebug,
		}
	end

	-- Subir prioriza borda mais próxima em altura; em empate, menor deslocamento horizontal.
	table.sort(candidates, function(a, b)
		if math.abs(a.VertDist - b.VertDist) > 0.1 then
			return a.VertDist < b.VertDist
		end
		if math.abs(a.HorizDist - b.HorizDist) > 0.1 then
			return a.HorizDist < b.HorizDist
		end
		return false
	end)

	local bestCandidate = nil
	local bestTipo = nil
	local firstValidDistCandidate = nil
	local bestEscalarFallback = nil

	for _, cand in ipairs(candidates) do
		local tipo
		if cand.VertDist <= finalConfig.SubirMaxAltura then
			tipo = "Subir"
		elseif cand.VertDist <= finalConfig.SubirSaltoMaxAltura then
			tipo = "SubirSalto"
		else
			Debug.Verbose("  Candidato rejeitado (TooFarAbove):", cand.Part.Name, "| VertDist:", string.format("%.1f", cand.VertDist))
			continue
		end

		if not firstValidDistCandidate then
			firstValidDistCandidate = { cand = cand, tipo = tipo }
		end

		if not bestEscalarFallback and cand.VertDist <= maxEscalarVerticalDistance then
			local escalarCandidate = checkEscalarAtEdge(
				character,
				cand.EdgePosition,
				cand.Normal,
				cand.Part,
				finalConfig,
				"SubirCandidate"
			)

			if escalarCandidate and escalarCandidate.ClearanceCFrame and escalarCandidate.ClearanceSize then
				table.insert(subirDebug.EscalarChecks, {
					ClearanceCFrame = escalarCandidate.ClearanceCFrame,
					ClearanceSize = escalarCandidate.ClearanceSize,
					CanEscalar = escalarCandidate.CanEscalar,
				})
			end

			if escalarCandidate and escalarCandidate.CanEscalar then
				escalarCandidate.SourceEdgePosition = currentEdgePos
				escalarCandidate.VerticalDistance = cand.VertDist
				bestEscalarFallback = escalarCandidate
			end
		end

		Debug.Verbose("  Testando candidato:", cand.Part.Name, "| HorizDist:", string.format("%.2f", cand.HorizDist), "| VertDist:", string.format("%.1f", cand.VertDist))

		local hasTopClearance, hasFrontClearance = hasBothClearances(
			character,
			cand.Part,
			cand.EdgePosition,
			cand.Normal,
			finalConfig
		)

		if hasTopClearance and hasFrontClearance then
			bestCandidate = cand
			bestTipo = tipo
			Debug.Verbose("    → MELHOR candidato VÁLIDO!")
			break
		else
			Debug.Verbose("    → Sem espaço! Top:", hasTopClearance, "| Front:", hasFrontClearance)
		end
	end

	if not bestCandidate then
		if bestEscalarFallback then
			Debug.Verbose("  RESULTADO: CanSubir=true | Tipo: Escalar (candidate)")
			return {
				CanSubir = true,
				Tipo = "Escalar",
				SourceEdgePosition = currentEdgePos,
				EdgePosition = bestEscalarFallback.EdgePosition,
				Normal = bestEscalarFallback.Normal,
				Part = bestEscalarFallback.Part,
				VerticalDistance = bestEscalarFallback.VerticalDistance,
				PosFinal = bestEscalarFallback.PosFinal,
				ClearanceCFrame = bestEscalarFallback.ClearanceCFrame,
				ClearanceSize = bestEscalarFallback.ClearanceSize,
				FloorRayDebug = bestEscalarFallback.FloorRayDebug,
				Debug = subirDebug,
			}
		end

		-- Se nem passou do filtro de TooFarAbove
		if not firstValidDistCandidate then
			local firstCand = candidates[1]
			Debug.Verbose("  RESULTADO: TooFarAbove | VertDist:", string.format("%.1f", firstCand.VertDist))
			return {
				CanSubir = false,
				Reason = "TooFarAbove",
				VerticalDistance = firstCand.VertDist,
				EdgePosition = firstCand.EdgePosition,
				Debug = subirDebug,
			}
		end

		-- Teve candidato com distância válida, mas sem espaço
		local failCand = firstValidDistCandidate.cand
		Debug.Verbose("  RESULTADO: NoClearanceAbove")
		return {
			CanSubir = false,
			Reason = "NoClearanceAbove",
			Tipo = firstValidDistCandidate.tipo,
			EdgePosition = failCand.EdgePosition,
			Normal = failCand.Normal,
			VerticalDistance = failCand.VertDist,
			Debug = subirDebug,
		}
	end

	Debug.Verbose("  RESULTADO: CanSubir=true | Tipo:", bestTipo)
	local idleMode, legHit, legProbeRaysDebug = Analisador.ResolveIdleMode({
		Character = character,
		Part = bestCandidate.Part,
		EdgePosition = bestCandidate.EdgePosition,
		Normal = bestCandidate.Normal,
	}, finalConfig)

	return {
		CanSubir = true,
		Tipo = bestTipo,
		SourceEdgePosition = currentEdgePos,
		EdgePosition = bestCandidate.EdgePosition,
		Normal = bestCandidate.Normal,
		Part = bestCandidate.Part,
		IdleMode = idleMode,
		LegHit = legHit,
		LegProbeRaysDebug = legProbeRaysDebug,
		VerticalDistance = bestCandidate.VertDist,
		Debug = subirDebug,
	}
end

-- ══════════════════════════════════════
-- Descer: Detectar superfície agarrável abaixo
-- Busca parts em volume abaixo e seleciona borda válida
-- ══════════════════════════════════════

function Analisador.CheckDescer(character, currentEdgePos, currentNormal, config)
	local finalConfig = Configs.mergeConfig(config)
	local hrp = Utilidades.getCharacterParts(character)
	if not hrp then
		return nil
	end

	if not isWallLikeNormal(currentNormal, finalConfig) then
		Debug.Verbose("  RESULTADO: InvalidCurrentNormalForDescer | Normal:", currentNormal)
		return {
			CanDescer = false,
			Reason = "InvalidCurrentNormalForDescer",
		}
	end

	local probeOffset = finalConfig.DescerProbeNormalOffset or 2.0
	local areaSize = finalConfig.DescerAreaSize or Vector3.new(6.0, 10.0, 6.0)
	local areaDownOffset = finalConfig.DescerAreaDownOffset or -5.0
	local areaCenter = currentEdgePos
		+ currentNormal.Unit * (probeOffset - areaSize.Z * 0.5)
		+ Vector3.yAxis * areaDownOffset
	local areaCFrame = Utilidades.getSurfaceFrame(areaCenter, currentNormal.Unit)

	Debug.Verbose("═══ CheckDescer (Area) ═══")
	Debug.Verbose("  EdgePos:", currentEdgePos, "| Normal:", currentNormal)
	Debug.Verbose("  QueryCenter:", areaCenter, "| AreaSize:", areaSize)

	local descerDebug = {
		QueryBoxCFrame = areaCFrame,
		QueryBoxSize = areaSize,
		CandidatePoints = {},
	}

	local parts = collectValidPartsInBox(areaCFrame, areaSize, {character}, finalConfig.MinPartHeight)
	local candidates = table.create(#parts)
	local minVerticalDelta = finalConfig.DescerMinVerticalDelta or 0.5
	local samplePointBase = currentEdgePos + currentNormal.Unit * probeOffset
	local maxDepth = math.max(finalConfig.LateralMaxProfundidade or 2.2, 0.1)
	local wallPlanarNormal = Vector3.new(currentNormal.X, 0, currentNormal.Z)
	if wallPlanarNormal.Magnitude < 0.05 then
		wallPlanarNormal = currentNormal.Unit
	else
		wallPlanarNormal = wallPlanarNormal.Unit
	end

	for _, part in ipairs(parts) do
		local castData = buildCastDataFromPartPoint(character, part, samplePointBase, currentNormal)
		local built = buildResultFromCast(castData)
		if not built then
			continue
		end

		local topEdge = built.TopEdgePosition
		local vertDist = currentEdgePos.Y - topEdge.Y
		if vertDist <= minVerticalDelta then
			table.insert(descerDebug.CandidatePoints, {
				Position = topEdge,
				Accepted = false,
			})
			continue
		end

		if not isWallLikeNormal(built.Normal, finalConfig) then
			table.insert(descerDebug.CandidatePoints, {
				Position = topEdge,
				Accepted = false,
			})
			continue
		end

		local horizDelta = Vector3.new(topEdge.X - currentEdgePos.X, 0, topEdge.Z - currentEdgePos.Z)
		local horizDist = horizDelta.Magnitude
		local depthDistance = math.abs((topEdge - currentEdgePos):Dot(wallPlanarNormal))
		if depthDistance > maxDepth then
			table.insert(descerDebug.CandidatePoints, {
				Position = topEdge,
				Accepted = false,
			})
			continue
		end

		table.insert(candidates, {
			Part = part,
			EdgePosition = topEdge,
			Normal = built.Normal,
			VertDist = vertDist,
			HorizDist = horizDist,
		})

		table.insert(descerDebug.CandidatePoints, {
			Position = topEdge,
			Accepted = true,
		})
	end

	if #candidates == 0 then
		Debug.Verbose("  RESULTADO: NoSurfaceBelow")
		return {
			CanDescer = false,
			Reason = "NoSurfaceBelow",
			Debug = descerDebug,
		}
	end

	table.sort(candidates, function(a, b)
		if math.abs(a.VertDist - b.VertDist) > 0.1 then
			return a.VertDist < b.VertDist
		end
		return a.HorizDist < b.HorizDist
	end)

	local bestCandidate = nil
	local firstValidDistCandidate = nil

	for _, cand in ipairs(candidates) do
		if cand.VertDist > finalConfig.DescerMaxAltura then
			Debug.Verbose("  Candidato rejeitado (TooFarBelow):", cand.Part.Name, "| VertDist:", string.format("%.1f", cand.VertDist))
			continue
		end

		if not firstValidDistCandidate then
			firstValidDistCandidate = cand
		end

		Debug.Verbose("  Testando candidato:", cand.Part.Name, "| HorizDist:", string.format("%.2f", cand.HorizDist), "| VertDist:", string.format("%.1f", cand.VertDist))

		local hasTopClearance, hasFrontClearance = hasBothClearances(
			character,
			cand.Part,
			cand.EdgePosition,
			cand.Normal,
			finalConfig
		)

		if hasTopClearance and hasFrontClearance then
			bestCandidate = cand
			Debug.Verbose("    → MELHOR candidato VÁLIDO!")
			break
		else
			Debug.Verbose("    → Sem espaço! Top:", hasTopClearance, "| Front:", hasFrontClearance)
		end
	end

	if not bestCandidate then
		if not firstValidDistCandidate then
			local firstCand = candidates[1]
			Debug.Verbose("  RESULTADO: TooFarBelow | VertDist:", string.format("%.1f", firstCand.VertDist))
			return {
				CanDescer = false,
				Reason = "TooFarBelow",
				VerticalDistance = firstCand.VertDist,
				EdgePosition = firstCand.EdgePosition,
				Debug = descerDebug,
			}
		end

		Debug.Verbose("  RESULTADO: NoClearanceBelow")
		return {
			CanDescer = false,
			Reason = "NoClearanceBelow",
			EdgePosition = firstValidDistCandidate.EdgePosition,
			Normal = firstValidDistCandidate.Normal,
			VerticalDistance = firstValidDistCandidate.VertDist,
			Debug = descerDebug,
		}
	end

	Debug.Verbose("  RESULTADO: CanDescer=true | Tipo: Descer")
	local idleMode, legHit, legProbeRaysDebug = Analisador.ResolveIdleMode({
		Character = character,
		Part = bestCandidate.Part,
		EdgePosition = bestCandidate.EdgePosition,
		Normal = bestCandidate.Normal,
	}, finalConfig)

	return {
		CanDescer = true,
		Tipo = "Descer",
		SourceEdgePosition = currentEdgePos,
		EdgePosition = bestCandidate.EdgePosition,
		Normal = bestCandidate.Normal,
		Part = bestCandidate.Part,
		IdleMode = idleMode,
		LegHit = legHit,
		LegProbeRaysDebug = legProbeRaysDebug,
		VerticalDistance = bestCandidate.VertDist,
		Debug = descerDebug,
	}
end

-- ══════════════════════════════════════
-- Lateral: Detectar superfície agarrável à direita/esquerda
-- Usa uma única caixa espelhada por direção e classifica Lateral/LateralSalto
-- ══════════════════════════════════════

function Analisador.CheckLateral(character, currentEdgePos, currentNormal, direcao, config, currentPart)
	local finalConfig = Configs.mergeConfig(config)
	if direcao ~= "Direita" and direcao ~= "Esquerda" then
		return {
			CanMoveLateral = false,
			Reason = "InvalidDirection",
		}
	end

	local hrp = Utilidades.getCharacterParts(character)
	if not hrp then
		return {
			CanMoveLateral = false,
			Reason = "NoCharacterParts",
		}
	end

	local sideDir = getLateralDirection(currentNormal, direcao)
	local probeOffset = finalConfig.LateralProbeNormalOffset or 2.0
	local areaSize = finalConfig.LateralAreaSize or Vector3.new(6.0, 4.5, 6.0)
	local areaUpOffset = finalConfig.LateralAreaUpOffset or 0.0
	local lateralSideBias = math.clamp(finalConfig.LateralAreaSideBias or 0.35, 0.0, 1.0)
	local areaCenter = currentEdgePos
		+ currentNormal.Unit * (probeOffset - areaSize.Z * 0.5)
		+ Vector3.yAxis * areaUpOffset
		+ sideDir * (areaSize.X * lateralSideBias)
	local currentWallNormal = Vector3.new(currentNormal.X, 0, currentNormal.Z)
	if currentWallNormal.Magnitude < 0.05 then
		currentWallNormal = currentNormal.Unit
	else
		currentWallNormal = currentWallNormal.Unit
	end
	local areaCFrame = Utilidades.getSurfaceFrame(areaCenter, currentNormal.Unit)

	local lateralDebug = {
		Direction = direcao,
		BasePosition = areaCenter,
		SideDirection = sideDir,
		QueryBoxCFrame = areaCFrame,
		QueryBoxSize = areaSize,
		CandidatePoints = {},
		PathClearanceBoxes = {},
		PathClearanceRays = {},
		RejectionCounts = {},
		AcceptedCounts = {
			Lateral = 0,
			LateralSalto = 0,
		},
	}

	Debug.Verbose("═══ CheckLateral (Area) ═══")
	Debug.Verbose("  Direction:", direcao, "| EdgePos:", currentEdgePos, "| Normal:", currentNormal)
	Debug.Verbose("  QueryCenter:", areaCenter, "| AreaSize:", areaSize)

	if not isWallLikeNormal(currentNormal, finalConfig) then
		Debug.Verbose("  RESULTADO: InvalidCurrentNormalForLateral | Normal:", currentNormal)
		return {
			CanMoveLateral = false,
			Reason = "InvalidCurrentNormalForLateral",
			Direction = direcao,
			Debug = lateralDebug,
		}
	end

	local candidates = {}
	local jumpCandidates = {}
	local lateralTopEdgeTolerance = finalConfig.LateralTopEdgeTolerance or 2.0
	local lateralSaltoMaxVertical = finalConfig.LateralSaltoMaxVertical or 2.8
	local lateralSaltoTopEdgeTolerance = math.max(
		finalConfig.LateralSaltoTopEdgeTolerance or lateralSaltoMaxVertical,
		lateralTopEdgeTolerance
	)
	local desiredSideOffset = math.max(finalConfig.LateralTargetSideOffset or 2.2, 0.4)
	local sampleSideOffset = math.min(areaSize.X * 0.5, desiredSideOffset)
	local minLateralSideDistance = finalConfig.LateralMinSideDistance or 0.05
	local lateralSaltoMinSideDistance = math.max(
		finalConfig.LateralSaltoMinSideDistance or math.max(minLateralSideDistance, 1.0),
		minLateralSideDistance
	)
	local lateralReverseTolerance = math.max(finalConfig.LateralReverseTolerance or 0.05, 0.0)
	local lateralCandidateBoxMargin = math.max(finalConfig.LateralCandidateBoxMargin or 0.5, 0.0)
	local pathClearanceNormalOffset = finalConfig.LateralPathClearanceNormalOffset or 1.2
	local pathClearanceHeightOffset = finalConfig.LateralPathClearanceHeightOffset or 0.0
	local allowCorner = finalConfig.LateralAllowCorner ~= false
	local allowExternalCorner = finalConfig.LateralAllowExternalCorner ~= false
	local cornerMinDot = finalConfig.LateralCornerMinDot or -0.15
	local externalCornerMinDot = finalConfig.LateralExternalCornerMinDot or -0.35
	local pathClearanceEnabled = finalConfig.LateralPathClearanceEnabled ~= false
	local pathClearanceSize = finalConfig.LateralPathClearanceSize or Vector3.new(1.8, 3.8, 1.4)
	local sideClearanceDistance = math.max(finalConfig.LateralPathSideDistance or (finalConfig.LateralTargetSideOffset or 3.2), 0.5)
	local maxDepth = math.max(finalConfig.LateralMaxProfundidade or 2.2, 0.1)
	local cornerMaxDepth = math.max(finalConfig.LateralCornerMaxProfundidade or 4.5, maxDepth)
	local externalCornerMaxDepth = math.max(finalConfig.LateralExternalCornerMaxProfundidade or 8.0, cornerMaxDepth)
	local cornerRespectsBaseDepth = finalConfig.LateralCornerRespectsBaseDepth ~= false
	local externalPathRayEnabled = finalConfig.LateralExternalPathRayEnabled ~= false
	local externalPathRayUpOffset = finalConfig.LateralExternalPathRayUpOffset or 0.2
	local externalPathRayNormalOffset = finalConfig.LateralExternalPathRayNormalOffset or pathClearanceNormalOffset

	local function fmt2(v)
		return string.format("%.2f", v or 0)
	end

	local function boolStr(v)
		return v and "true" or "false"
	end

	local function addRejection(reason)
		lateralDebug.RejectionCounts[reason] = (lateralDebug.RejectionCounts[reason] or 0) + 1
	end

	local function recordRejected(part, topEdge, reason, extra)
		addRejection(reason)
		local pointData = {
			Position = topEdge,
			Accepted = false,
			Reason = reason,
			Part = part and part.Name or "nil",
		}
		if extra then
			for k, v in pairs(extra) do
				pointData[k] = v
			end
		end
		table.insert(lateralDebug.CandidatePoints, pointData)
	end

	local function recordAccepted(part, topEdge, moveType, extra)
		lateralDebug.AcceptedCounts[moveType] = (lateralDebug.AcceptedCounts[moveType] or 0) + 1
		local pointData = {
			Position = topEdge,
			Accepted = true,
			Reason = "Accepted" .. moveType,
			Part = part and part.Name or "nil",
		}
		if extra then
			for k, v in pairs(extra) do
				pointData[k] = v
			end
		end
		table.insert(lateralDebug.CandidatePoints, pointData)
	end

	local function isSameAssemblyPart(candidatePart, referencePart)
		if not candidatePart or not referencePart then
			return false
		end

		if candidatePart == referencePart then
			return true
		end

		local candidateRoot = candidatePart.AssemblyRootPart
		local referenceRoot = referencePart.AssemblyRootPart
		if candidateRoot and referenceRoot and candidateRoot == referenceRoot then
			return true
		end

		return false
	end

	local function hasLateralPathClearance(targetPart)
		if not pathClearanceEnabled then
			return true, nil
		end

		local ignoreList = { character }
		if currentPart then
			table.insert(ignoreList, currentPart)
		end
		if targetPart and targetPart ~= currentPart then
			table.insert(ignoreList, targetPart)
		end

		local probeBase = currentEdgePos
			+ currentNormal.Unit * pathClearanceNormalOffset
			+ Vector3.yAxis * pathClearanceHeightOffset
		local probeCenter = probeBase + sideDir * sideClearanceDistance
		local probeCf = Utilidades.getSurfaceFrame(probeCenter, currentNormal.Unit)
		local probeSize = pathClearanceSize
		local clear, blocker = Utilidades.firstBlockingPartInBox(
			probeCf,
			probeSize,
			ignoreList,
			function(part)
				if Utilidades.isIgnorablePart(part, finalConfig.MinPartHeight) then
					return true
				end

				if targetPart and isSameAssemblyPart(part, targetPart) then
					return true
				end

				return false
			end
		)

		table.insert(lateralDebug.PathClearanceBoxes, {
			CFrame = probeCf,
			Size = probeSize,
			Clear = clear,
		})

		return clear, blocker
	end

	local function hasExternalCurvePathClearance(targetEdgePos, targetNormal, targetPart)
		if not externalPathRayEnabled then
			return true, nil
		end

		local ignoreList = { character }
		if currentPart then
			table.insert(ignoreList, currentPart)
		end
		if targetPart and targetPart ~= currentPart then
			table.insert(ignoreList, targetPart)
		end

		local rayParams = Utilidades.createRaycastParams(ignoreList)
		local rayOrigin = hrp.Position + Vector3.yAxis * externalPathRayUpOffset
		local rayTarget = targetEdgePos
			+ targetNormal.Unit * externalPathRayNormalOffset
			+ Vector3.yAxis * externalPathRayUpOffset
		local rayDir = rayTarget - rayOrigin
		if rayDir.Magnitude < 0.05 then
			return true, nil
		end

		local rayResult = Workspace:Raycast(rayOrigin, rayDir, rayParams)
		local hitIsTargetSurface = targetPart ~= nil and rayResult ~= nil and isSameAssemblyPart(rayResult.Instance, targetPart)
		table.insert(lateralDebug.PathClearanceRays, {
			Origin = rayOrigin,
			HitPosition = rayResult and rayResult.Position or rayTarget,
			Hit = rayResult ~= nil,
			Clear = rayResult == nil or hitIsTargetSurface,
		})

		if not rayResult then
			return true, nil
		end

		if hitIsTargetSurface then
			return true, nil
		end

		return false, rayResult.Instance
	end

	local function evaluateBuiltCandidate(part, built, isCornerProbe)
		local topEdge = built.TopEdgePosition
		local topEdgeDeltaY = math.abs(topEdge.Y - currentEdgePos.Y)
		if topEdgeDeltaY > lateralSaltoTopEdgeTolerance then
			recordRejected(part, topEdge, "TopEdgeDeltaTooHigh", {
				TopEdgeDeltaY = topEdgeDeltaY,
				TopEdgeTolerance = lateralSaltoTopEdgeTolerance,
			})
			return
		end

		local hitWallNormal = Vector3.new(built.Normal.X, 0, built.Normal.Z)
		if hitWallNormal.Magnitude < 0.05 then
			hitWallNormal = currentWallNormal
		else
			hitWallNormal = hitWallNormal.Unit
		end

		if not isWallLikeNormal(built.Normal, finalConfig) then
			recordRejected(part, topEdge, "NotWallLike", {
				NormalY = built.Normal.Y,
			})
			return
		end

		local delta = topEdge - currentEdgePos
		local horizontalDistance = Vector3.new(delta.X, 0, delta.Z).Magnitude
		local verticalDelta = topEdge.Y - currentEdgePos.Y
		local normalDot = hitWallNormal:Dot(currentWallNormal)

		local isInternalCornerCandidate = allowCorner and isCornerProbe and part == currentPart and normalDot >= cornerMinDot
		local isExternalCornerCandidate = allowExternalCorner
			and currentPart ~= nil
			and part ~= currentPart
			and normalDot >= externalCornerMinDot
			and normalDot < (finalConfig.LateralNormalMinDot or 0.5)
		local isCornerCandidate = isInternalCornerCandidate or isExternalCornerCandidate
		local cornerType = isExternalCornerCandidate and "Externa" or (isInternalCornerCandidate and "Interna" or "Nenhuma")

		local sideDistanceRaw = delta:Dot(sideDir)
		local lateralDistance = sideDistanceRaw
		local sideDistanceClamped = false

		if lateralDistance < -lateralReverseTolerance then
			recordRejected(part, topEdge, "WrongDirection", {
				SideDistanceRaw = sideDistanceRaw,
				ReverseTolerance = lateralReverseTolerance,
				CornerType = cornerType,
			})
			return
		end

		if lateralDistance <= minLateralSideDistance and not isCornerCandidate then
			recordRejected(part, topEdge, "SideDistanceTooSmall", {
				SideDistanceRaw = sideDistanceRaw,
				MinSideDistance = minLateralSideDistance,
			})
			return
		elseif isCornerCandidate and lateralDistance >= 0 and lateralDistance <= minLateralSideDistance then
			lateralDistance = minLateralSideDistance
			sideDistanceClamped = true
		end

		local depthDistance = math.abs(delta:Dot(currentWallNormal))
		if cornerRespectsBaseDepth and isCornerCandidate and depthDistance > maxDepth then
			recordRejected(part, topEdge, "DepthTooHighBaseMax", {
				DepthDistance = depthDistance,
				BaseMaxDepth = maxDepth,
				CornerType = cornerType,
			})
			return
		end

		local allowedDepth = maxDepth
		if isInternalCornerCandidate then
			allowedDepth = cornerMaxDepth
		elseif isExternalCornerCandidate then
			allowedDepth = externalCornerMaxDepth
		end
		if depthDistance > allowedDepth then
			recordRejected(part, topEdge, "DepthTooHigh", {
				DepthDistance = depthDistance,
				AllowedDepth = allowedDepth,
				CornerType = cornerType,
			})
			return
		end

		if normalDot < finalConfig.LateralNormalMinDot and not isCornerCandidate then
			recordRejected(part, topEdge, "NormalDotTooLow", {
				NormalDot = normalDot,
				RequiredNormalDot = finalConfig.LateralNormalMinDot,
			})
			return
		end

		local edgePos = topEdge
		local edgePosLocal = areaCFrame:PointToObjectSpace(edgePos)
		local maxX = areaSize.X * 0.5 + lateralCandidateBoxMargin
		local maxY = areaSize.Y * 0.5 + lateralCandidateBoxMargin
		local maxZ = areaSize.Z * 0.5 + lateralCandidateBoxMargin
		if math.abs(edgePosLocal.X) > maxX or math.abs(edgePosLocal.Y) > maxY or math.abs(edgePosLocal.Z) > maxZ then
			recordRejected(part, topEdge, "EdgeOutsideQueryBox", {
				EdgeLocalX = edgePosLocal.X,
				EdgeLocalY = edgePosLocal.Y,
				EdgeLocalZ = edgePosLocal.Z,
			})
			return
		end

		local hasTopClearance, hasFrontClearance = hasBothClearances(
			character,
			part,
			edgePos,
			hitWallNormal,
			finalConfig
		)
		local hasPathClearance
		if isExternalCornerCandidate then
			hasPathClearance = hasExternalCurvePathClearance(edgePos, hitWallNormal, part)
		else
			hasPathClearance = hasLateralPathClearance(part)
		end
		if not (hasTopClearance and hasFrontClearance and hasPathClearance) then
			recordRejected(part, topEdge, "NoClearance", {
				TopClear = hasTopClearance,
				FrontClear = hasFrontClearance,
				PathClear = hasPathClearance,
				CornerType = cornerType,
			})
			return
		end

		local isLateral = lateralDistance <= (finalConfig.LateralMaxHorizontal or 4.5)
			and math.abs(verticalDelta) <= (finalConfig.LateralMaxVertical or 1.75)
		if (not isLateral) and lateralDistance < lateralSaltoMinSideDistance then
			recordRejected(part, topEdge, "SideDistanceTooSmallForLateralSalto", {
				SideDistance = lateralDistance,
				RequiredSideDistance = lateralSaltoMinSideDistance,
				CornerType = cornerType,
			})
			return
		end

		local isLateralSalto = lateralDistance <= (finalConfig.LateralSaltoMaxHorizontal or 11.0)
			and math.abs(verticalDelta) <= lateralSaltoMaxVertical

		if not isLateralSalto then
			recordRejected(part, topEdge, "OutsideLateralSaltoLimits", {
				SideDistance = lateralDistance,
				VerticalDelta = verticalDelta,
			})
			return
		end

		local candidate = {
			Part = part,
			PartName = part and part.Name or "nil",
			EdgePosition = edgePos,
			Normal = hitWallNormal,
			SideDistance = lateralDistance,
			SideDistanceRaw = sideDistanceRaw,
			SideDistanceClamped = sideDistanceClamped,
			HorizontalDistance = horizontalDistance,
			VertDelta = verticalDelta,
			DepthDistance = depthDistance,
			NormalDot = normalDot,
			IsCorner = isCornerCandidate,
			CornerType = cornerType,
			IsOtherPart = currentPart ~= nil and part ~= currentPart,
		}

		if isLateral then
			table.insert(candidates, candidate)
			recordAccepted(part, topEdge, "Lateral", {
				SideDistance = lateralDistance,
				SideDistanceRaw = sideDistanceRaw,
				SideDistanceClamped = sideDistanceClamped,
				VerticalDelta = verticalDelta,
				HorizontalDistance = horizontalDistance,
				CornerType = cornerType,
			})
		else
			table.insert(jumpCandidates, candidate)
			recordAccepted(part, topEdge, "LateralSalto", {
				SideDistance = lateralDistance,
				SideDistanceRaw = sideDistanceRaw,
				SideDistanceClamped = sideDistanceClamped,
				VerticalDelta = verticalDelta,
				HorizontalDistance = horizontalDistance,
				CornerType = cornerType,
			})
		end
	end

	local function logTopCandidates(tag, list, maxCount)
		local maxItems = math.min(#list, maxCount or 3)
		for i = 1, maxItems do
			local cand = list[i]
			Debug.Verbose(
				"    ",
				tag .. "[" .. i .. "]",
				"Part:", cand.PartName,
				"| Side:", fmt2(cand.SideDistance),
				"| SideRaw:", fmt2(cand.SideDistanceRaw),
				"| Clamped:", boolStr(cand.SideDistanceClamped),
				"| Horiz:", fmt2(cand.HorizontalDistance),
				"| Vert:", fmt2(cand.VertDelta),
				"| Depth:", fmt2(cand.DepthDistance),
				"| Dot:", fmt2(cand.NormalDot),
				"| Curva:", cand.CornerType,
				"| OtherPart:", boolStr(cand.IsOtherPart)
			)
		end
	end

	local function sortJumpCandidatesByPriority(list)
		table.sort(list, function(a, b)
			local aIsWeakCorner = a.CornerType == "Interna" and a.SideDistanceClamped
			local bIsWeakCorner = b.CornerType == "Interna" and b.SideDistanceClamped
			if aIsWeakCorner ~= bIsWeakCorner then
				return not aIsWeakCorner
			end

			if math.abs(a.SideDistance - b.SideDistance) > 0.05 then
				return a.SideDistance < b.SideDistance
			end
			if math.abs(a.HorizontalDistance - b.HorizontalDistance) > 0.05 then
				return a.HorizontalDistance < b.HorizontalDistance
			end

			local aVert = math.abs(a.VertDelta)
			local bVert = math.abs(b.VertDelta)
			if math.abs(aVert - bVert) > 0.05 then
				return aVert < bVert
			end

			local aIsOtherPart = currentPart and a.Part ~= currentPart or false
			local bIsOtherPart = currentPart and b.Part ~= currentPart or false
			if aIsOtherPart ~= bIsOtherPart then
				return not aIsOtherPart
			end

			return false
		end)
	end

	local function buildLateralSaltoTarget(jumpBest)
		local idleMode, legHit, legProbeRaysDebug = Analisador.ResolveIdleMode({
			Character = character,
			Part = jumpBest.Part,
			EdgePosition = jumpBest.EdgePosition,
			Normal = jumpBest.Normal,
		}, finalConfig)

		return {
			Direction = direcao,
			IdleMode = idleMode,
			EdgePosition = jumpBest.EdgePosition,
			Normal = jumpBest.Normal,
			Part = jumpBest.Part,
			VerticalDelta = jumpBest.VertDelta,
			HorizontalDistance = jumpBest.SideDistance,
			TravelDistance = jumpBest.HorizontalDistance,
			LegHit = legHit,
			LegProbeRaysDebug = legProbeRaysDebug,
		}
	end

	local parts = collectValidPartsInBox(areaCFrame, areaSize, {character}, finalConfig.MinPartHeight)
	local oppositeSideDir = -sideDir
	for _, part in ipairs(parts) do
		for _, multiplier in ipairs(LATERAL_SAMPLE_MULTIPLIERS) do
			local samplePoint = currentEdgePos
				+ currentNormal.Unit * probeOffset
				+ sideDir * (sampleSideOffset * multiplier)

			local castCurrent = buildCastDataFromPartPoint(character, part, samplePoint, currentWallNormal)
			local builtCurrent = buildResultFromCast(castCurrent)
			if builtCurrent then
				evaluateBuiltCandidate(part, builtCurrent, false)
			end

			local castSide = buildCastDataFromPartPoint(character, part, samplePoint, sideDir)
			local builtSide = buildResultFromCast(castSide)
			if builtSide then
				evaluateBuiltCandidate(part, builtSide, false)
			end

			local castOppSide = buildCastDataFromPartPoint(character, part, samplePoint, oppositeSideDir)
			local builtOppSide = buildResultFromCast(castOppSide)
			if builtOppSide then
				evaluateBuiltCandidate(part, builtOppSide, false)
			end

			local castAuto = buildCastDataFromPartPoint(character, part, samplePoint)
			local builtAuto = buildResultFromCast(castAuto)
			if builtAuto then
				evaluateBuiltCandidate(part, builtAuto, false)
			end
		end

		if allowCorner and currentPart and part == currentPart then
			local cornerSamplePoint = currentEdgePos
				+ currentNormal.Unit * probeOffset
				+ sideDir * (sampleSideOffset + 0.8)
			local cornerCastData = buildCastDataFromPartPoint(character, part, cornerSamplePoint, sideDir)
			local cornerBuilt = buildResultFromCast(cornerCastData)
			if cornerBuilt then
				evaluateBuiltCandidate(part, cornerBuilt, true)
			end
		end
	end

	Debug.Verbose(
		"  Summary: PartsInBox:", #parts,
		"| AcceptedLateral:", #candidates,
		"| AcceptedLateralSalto:", #jumpCandidates,
		"| Rejected:", #lateralDebug.CandidatePoints - #candidates - #jumpCandidates
	)
	for reason, count in pairs(lateralDebug.RejectionCounts) do
		Debug.Verbose("    RejectReason:", reason, "| Count:", count)
	end

	if #candidates == 0 then
		if #jumpCandidates > 0 then
			sortJumpCandidatesByPriority(jumpCandidates)

			Debug.Verbose("  Ranking LateralSalto (top 3):")
			logTopCandidates("Jump", jumpCandidates, 3)

			local jumpBest = jumpCandidates[1]
			local jumpTarget = buildLateralSaltoTarget(jumpBest)

			lateralDebug.Selected = {
				Type = "LateralSalto",
				Part = jumpBest.PartName,
				SideDistance = jumpBest.SideDistance,
				SideDistanceRaw = jumpBest.SideDistanceRaw,
				SideDistanceClamped = jumpBest.SideDistanceClamped,
				CornerType = jumpBest.CornerType,
			}

			Debug.Verbose(
				"  RESULTADO: NoLateralSurface + CanLateralSalto=true",
				"| Dist:", fmt2(jumpBest.SideDistance),
				"| SideRaw:", fmt2(jumpBest.SideDistanceRaw),
				"| Clamped:", boolStr(jumpBest.SideDistanceClamped),
				"| Travel:", fmt2(jumpBest.HorizontalDistance),
				"| Curva:", jumpBest.CornerType,
				"| Part:", jumpBest.PartName
			)
			return {
				CanMoveLateral = false,
				CanLateralSalto = true,
				Reason = "NoLateralSurface",
				Direction = direcao,
				LateralSaltoTarget = jumpTarget,
				Debug = lateralDebug,
			}
		end

		Debug.Verbose("  RESULTADO: NoLateralSurface")
		return {
			CanMoveLateral = false,
			CanLateralSalto = false,
			Reason = "NoLateralSurface",
			Direction = direcao,
			Debug = lateralDebug,
		}
	end

	table.sort(candidates, function(a, b)
		local preferStraightOverCorner = finalConfig.LateralPreferStraightOverCorner ~= false
		local aIsWeakCorner = a.CornerType == "Interna" and a.SideDistanceClamped
		local bIsWeakCorner = b.CornerType == "Interna" and b.SideDistanceClamped
		if aIsWeakCorner ~= bIsWeakCorner then
			return not aIsWeakCorner
		end
		if preferStraightOverCorner and a.IsCorner ~= b.IsCorner then
			return not a.IsCorner
		end

		local aIsOtherPart = currentPart and a.Part ~= currentPart or false
		local bIsOtherPart = currentPart and b.Part ~= currentPart or false
		if aIsOtherPart ~= bIsOtherPart then
			return not aIsOtherPart
		end
		if aIsOtherPart and bIsOtherPart then
			if a.Part == b.Part then
				if math.abs(a.SideDistance - b.SideDistance) > 0.05 then
					return a.SideDistance > b.SideDistance
				end
			else
				if math.abs(a.SideDistance - b.SideDistance) > 0.05 then
					return a.SideDistance < b.SideDistance
				end
			end
		end
		if math.abs(a.SideDistance - b.SideDistance) > 0.05 then
			return a.SideDistance < b.SideDistance
		end
		if math.abs(a.HorizontalDistance - b.HorizontalDistance) > 0.05 then
			return a.HorizontalDistance < b.HorizontalDistance
		end
		return math.abs(a.VertDelta) < math.abs(b.VertDelta)
	end)

	Debug.Verbose("  Ranking Lateral (top 3):")
	logTopCandidates("Move", candidates, 3)

	local best = candidates[1]
	local preferSaltoOverInternalCorner = finalConfig.LateralSaltoPreferOverInternalCorner ~= false
	if preferSaltoOverInternalCorner and best and best.CornerType == "Interna" and #jumpCandidates > 0 then
		sortJumpCandidatesByPriority(jumpCandidates)
		Debug.Verbose("  Ranking LateralSalto (top 3):")
		logTopCandidates("Jump", jumpCandidates, 3)

		local jumpBest = jumpCandidates[1]
		local jumpTarget = buildLateralSaltoTarget(jumpBest)

		local curvaIdleMode = jumpTarget.IdleMode
		local curvaLegHit = jumpTarget.LegHit
		local curvaLegProbeRaysDebug = jumpTarget.LegProbeRaysDebug
		if best.Part ~= jumpBest.Part or best.EdgePosition ~= jumpBest.EdgePosition then
			curvaIdleMode, curvaLegHit, curvaLegProbeRaysDebug = Analisador.ResolveIdleMode({
				Character = character,
				Part = best.Part,
				EdgePosition = best.EdgePosition,
				Normal = best.Normal,
			}, finalConfig)
		end
		local curvaEstado = direcao .. (curvaIdleMode == "IdleSuporte" and "Suporte" or "Suspenso")

		lateralDebug.Selected = {
			Type = "LateralSaltoPreferido",
			Part = jumpBest.PartName,
			SideDistance = jumpBest.SideDistance,
			SideDistanceRaw = jumpBest.SideDistanceRaw,
			SideDistanceClamped = jumpBest.SideDistanceClamped,
			CornerType = jumpBest.CornerType,
		}

		Debug.Verbose(
			"  RESULTADO: PreferLateralSaltoOverInternalCorner",
			"| CurvaPart:", best.PartName,
			"| SaltoPart:", jumpBest.PartName,
			"| CurvaDist:", fmt2(best.SideDistance),
			"| SaltoDist:", fmt2(jumpBest.SideDistance)
		)

		return {
			CanMoveLateral = false,
			CanLateralSalto = true,
			Reason = "PreferLateralSaltoOverInternalCorner",
			Direction = direcao,
			LateralSaltoTarget = jumpTarget,
			CurvaInternaFallbackTarget = {
				Direction = direcao,
				Estado = curvaEstado,
				IdleMode = curvaIdleMode,
				EdgePosition = best.EdgePosition,
				Normal = best.Normal,
				Part = best.Part,
				VerticalDelta = best.VertDelta,
				HorizontalDistance = best.SideDistance,
				IsCorner = best.IsCorner,
				CornerType = best.CornerType,
				LegHit = curvaLegHit,
				LegProbeRaysDebug = curvaLegProbeRaysDebug,
			},
			Debug = lateralDebug,
		}
	end

	local idleMode, legHit, legProbeRaysDebug = Analisador.ResolveIdleMode({
		Character = character,
		Part = best.Part,
		EdgePosition = best.EdgePosition,
		Normal = best.Normal,
	}, finalConfig)

	lateralDebug.Selected = {
		Type = "Lateral",
		Part = best.PartName,
		SideDistance = best.SideDistance,
		SideDistanceRaw = best.SideDistanceRaw,
		SideDistanceClamped = best.SideDistanceClamped,
		CornerType = best.CornerType,
	}

	local estadoLateral = direcao .. (idleMode == "IdleSuporte" and "Suporte" or "Suspenso")
	Debug.Verbose(
		"  RESULTADO: CanMoveLateral=true",
		"| Estado:", estadoLateral,
		"| Dist:", fmt2(best.SideDistance),
		"| SideRaw:", fmt2(best.SideDistanceRaw),
		"| Clamped:", boolStr(best.SideDistanceClamped),
		"| Curva:", best.CornerType,
		"| Part:", best.PartName
	)

	return {
		CanMoveLateral = true,
		Reason = "Ok",
		Direction = direcao,
		Estado = estadoLateral,
		IdleMode = idleMode,
		IsCorner = best.IsCorner,
		CornerType = best.CornerType,
		EdgePosition = best.EdgePosition,
		Normal = best.Normal,
		Part = best.Part,
		VerticalDelta = best.VertDelta,
		HorizontalDistance = best.SideDistance,
		LegHit = legHit,
		LegProbeRaysDebug = legProbeRaysDebug,
		Debug = lateralDebug,
	}
end

-- ══════════════════════════════════════
-- Escalar: Verificar se cabe em cima da borda atual
-- ══════════════════════════════════════

function Analisador.CheckEscalar(character, currentEdgePos, currentNormal, currentPart, config)
	local finalConfig = Configs.mergeConfig(config)
	return checkEscalarAtEdge(character, currentEdgePos, currentNormal, currentPart, finalConfig, "CurrentGrab")
end

-- ══════════════════════════════════════
-- Verificações extraídas do init.client
-- ══════════════════════════════════════

--- Verifica se o jogador está correndo (necessário para Vault).
--- Extraído de init.client (isRunningForVault).
function Analisador.IsRunningForVault(humanoid, ClientBridgeRef)
	if ClientBridgeRef and ClientBridgeRef.LerStatusLocal then
		local estadoMov = ClientBridgeRef.LerStatusLocal("estadoMov")
		if type(estadoMov) == "string" and estadoMov == "Correndo" then
			return true
		end

		local correndoOn = ClientBridgeRef.LerStatusLocal("CorrendoOn")
		if type(correndoOn) == "boolean" then
			return correndoOn
		end
	end

	-- Fallback simples caso StatusLocal ainda não esteja disponível no primeiro frame.
	return humanoid.MoveDirection.Magnitude > 0.1 and humanoid.WalkSpeed > 18
end

--- Tenta fazer fallback de Agarrar quando o jogador não está correndo.
--- Extraído de init.client (tentarFallbackAgarrarSemCorrida).
function Analisador.TentarFallbackAgarrar(character, parkourResult, config)
	if not parkourResult or not parkourResult.EdgePosition or not parkourResult.Normal then
		return nil
	end

	local hrp = Utilidades.getCharacterParts(character)
	if not hrp then
		return nil
	end

	local finalConfig = Configs.mergeConfig(config)
	local fallback = table.clone(parkourResult)
	fallback.Character = character
	fallback.Acao = "Agarrar"
	fallback.Aprovado = false

	local distReal = (fallback.EdgePosition - hrp.Position).Magnitude
	if distReal > finalConfig.MaxGrabDistance then
		fallback.Reason = "TooFarToGrab"
		return fallback
	end

	local hasTopClearance, topBlocker, topCf, topSize = Analisador.HasTopClearance(fallback, finalConfig)
	fallback.TopClearanceCFrame = topCf
	fallback.TopClearanceSize = topSize
	if not hasTopClearance then
		fallback.Reason = "NoTopClearance"
		fallback.TopBlocker = topBlocker
		return fallback
	end

	local hasFrontClearance, frontBlocker, frontCf, frontSize = Analisador.HasFrontClearance(fallback, finalConfig)
	fallback.FrontClearanceCFrame = frontCf
	fallback.FrontClearanceSize = frontSize
	if not hasFrontClearance then
		fallback.Reason = "NoFrontClearance"
		fallback.FrontBlocker = frontBlocker
		return fallback
	end

	local idleMode, legHit, legProbeRaysDebug = Analisador.ResolveIdleMode(fallback, finalConfig)
	fallback.IdleMode = idleMode
	fallback.LegHit = legHit
	fallback.LegProbeRaysDebug = legProbeRaysDebug
	fallback.Reason = "OkFallbackNoRun"
	fallback.Aprovado = true

	return fallback
end

return Analisador
