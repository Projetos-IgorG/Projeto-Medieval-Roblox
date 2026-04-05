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

local function isWallLikeNormal(normal, config)
	local maxWallNormalY = config.MaxWallNormalY or 0.35
	return math.abs(normal.Unit.Y) <= maxWallNormalY
end

local function buildResultFromCast(castData)
	if not castData then
		return nil
	end

	-- Filtrar faces não-laterais (chão/teto): apenas bordas de faces tipo parede são válidas
	local resultNormal = castData.Normal or (castData.Result and castData.Result.Normal)
	if resultNormal and not isWallLikeNormal(resultNormal, Configs.DefaultConfig) then
		return nil
	end

	local topLocal, bottomLocal = computeFaceVerticalEdges(castData.Part, castData.Result)

	castData.TopEdgePosition = castData.Part.CFrame:PointToWorldSpace(topLocal)
	castData.BottomEdgePosition = castData.Part.CFrame:PointToWorldSpace(bottomLocal)

	return castData
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

local function getLegSupportRayFrame(normal)
	local flatNormal = Vector3.new(normal.X, 0, normal.Z)
	if flatNormal.Magnitude < 0.01 then
		flatNormal = Vector3.new(0, 0, 1)
	end

	local forward = -flatNormal.Unit
	local right = forward:Cross(Vector3.yAxis)
	if right.Magnitude < 0.01 then
		right = Vector3.xAxis
	else
		right = right.Unit
	end

	return forward, right
end

local function castLegSupportRay(origin, direction, baseIgnoreList, minPartHeight, maxPasses)
	local ignoreList = table.clone(baseIgnoreList)
	local remainingDistance = direction.Magnitude
	if remainingDistance < 0.001 then
		return nil, nil
	end

	local directionUnit = direction.Unit
	local currentOrigin = origin
	local tries = math.max(maxPasses or 1, 1)

	for _ = 1, tries do
		if remainingDistance < 0.001 then
			break
		end

		local rayResult = Workspace:Raycast(
			currentOrigin,
			directionUnit * remainingDistance,
			Utilidades.createRaycastParams(ignoreList)
		)

		if not rayResult then
			break
		end

		local hitPart = rayResult.Instance
		if hitPart and hitPart:IsA("BasePart") and not Utilidades.isIgnorablePart(hitPart, minPartHeight) then
			return hitPart, rayResult.Position
		end

		table.insert(ignoreList, hitPart)

		local advance = (rayResult.Position - currentOrigin).Magnitude + 0.02
		remainingDistance = math.max(0, remainingDistance - advance)
		currentOrigin = currentOrigin + directionUnit * advance
	end

	return nil, nil
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

	-- Flatten look para escalar sempre na vertical (sem influência de pitch da part)
	local flatLook = Vector3.new(-currentNormal.X, 0, -currentNormal.Z)
	if flatLook.Magnitude < 0.01 then
		flatLook = Vector3.new(0, 0, -1)
	end
	flatLook = flatLook.Unit

	local center = currentEdgePos
		+ Vector3.yAxis * (finalConfig.EscalarClearanceUpOffset or finalConfig.EscalarUpOffset)
		+ flatLook * (finalConfig.EscalarClearanceForwardOffset or finalConfig.EscalarForwardOffset)

	local cf = CFrame.lookAt(center, center + flatLook, Vector3.yAxis)
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

	-- PosFinal usa flatLook para que o offset forward seja puramente horizontal
	local posFinal = currentEdgePos
		+ Vector3.yAxis * finalConfig.EscalarUpOffset
		+ flatLook * finalConfig.EscalarForwardOffset

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

	-- Normal flattenada: verificação de topo sempre horizontal (sem influência de pitch da part)
	local flatNormal = Vector3.new(normal.X, 0, normal.Z)
	if flatNormal.Magnitude < 0.01 then
		flatNormal = Vector3.new(0, 0, -1)
	end
	flatNormal = flatNormal.Unit

	local center = data.EdgePosition
		+ Vector3.yAxis * finalConfig.TopClearanceUpOffset
		+ flatNormal * finalConfig.TopClearanceNormalOffset

	local cf = CFrame.lookAt(center, center - flatNormal, Vector3.yAxis)
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

	-- Normal flattenada: verificação frontal sempre 100% vertical (sem influência de pitch da part)
	local flatNormal = Vector3.new(normal.X, 0, normal.Z)
	if flatNormal.Magnitude < 0.01 then
		flatNormal = Vector3.new(0, 0, -1)
	end
	flatNormal = flatNormal.Unit

	local center = data.EdgePosition
		+ Vector3.yAxis * finalConfig.FrontClearanceUpOffset
		+ flatNormal * finalConfig.FrontClearanceNormalOffset

	local cf = CFrame.lookAt(center, center - flatNormal, Vector3.yAxis)
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

	local downOffset = finalConfig.LegSupportRayOriginDownOffset or finalConfig.LegProbeDownOffset or 2.8
	local forwardOffset = finalConfig.LegSupportRayOriginForwardOffset or 0
	local rayDistance = math.max(finalConfig.LegSupportRayDistance or 1.8, 0.1)
	local rayHeights = finalConfig.LegSupportRayHeights or { 1.0, -1.0 }
	local rayLateralOffsets = finalConfig.LegSupportRayLateralOffsets or { -1.0, 0.0, 1.0 }
	local maxPasses = finalConfig.LegSupportRayMaxPasses or 6

	local forward, right = getLegSupportRayFrame(data.Normal.Unit)
	local baseOrigin = data.EdgePosition
		- Vector3.yAxis * downOffset
		+ forward * forwardOffset

	local rayDirection = forward * rayDistance
	local minH = finalConfig.MinPartHeight
	local blocker = nil
	local hitCount = 0
	local _dbg = Configs.DebugEnabled
	local raysDebug = _dbg and {} or nil

	for _, heightOffset in ipairs(rayHeights) do
		for _, lateralOffset in ipairs(rayLateralOffsets) do
			local rayOrigin = baseOrigin
				+ Vector3.yAxis * heightOffset
				+ right * lateralOffset

			local hitPart, hitPosition = castLegSupportRay(
				rayOrigin,
				rayDirection,
				{ data.Character },
				minH,
				maxPasses
			)

			local rayHit = hitPart ~= nil
			if rayHit then
				hitCount += 1
				if not blocker then
					blocker = hitPart
				end
			end

			if raysDebug then
				table.insert(raysDebug, {
					Origin = rayOrigin,
					Direction = rayDirection,
					Hit = rayHit,
					HitPosition = hitPosition,
					Blocker = hitPart,
					HeightOffset = heightOffset,
					LateralOffset = lateralOffset,
				})
			end
		end
	end

	local clear = blocker == nil

	local supportDebug = _dbg and {
		BaseOrigin = baseOrigin,
		Distance = rayDistance,
		Direction = rayDirection,
		HitCount = hitCount,
		Rays = raysDebug,
		Clear = clear,
		Blocker = blocker,
	} or nil

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

local LATERAL_SAMPLE_MULTIPLIERS = table.freeze({ 0.7, 1.2 })

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

local function getClosestSurfacePointOnPart(part, worldPoint, preferredDirWorld)
	local half = part.Size / 2
	local localPoint = part.CFrame:PointToObjectSpace(worldPoint)
	local clamped = Vector3.new(
		math.clamp(localPoint.X, -half.X, half.X),
		math.clamp(localPoint.Y, -half.Y, half.Y),
		math.clamp(localPoint.Z, -half.Z, half.Z)
	)

	local isOutside = math.abs(localPoint.X) > half.X
		or math.abs(localPoint.Y) > half.Y
		or math.abs(localPoint.Z) > half.Z

	if isOutside then
		return part.CFrame:PointToWorldSpace(clamped)
	end

	local dirLocal = nil
	if preferredDirWorld and preferredDirWorld.Magnitude > 0.001 then
		dirLocal = part.CFrame:VectorToObjectSpace(preferredDirWorld.Unit)
	end

	local distToFace = {
		X = half.X - math.abs(localPoint.X),
		Y = half.Y - math.abs(localPoint.Y),
		Z = half.Z - math.abs(localPoint.Z),
	}

	local axis = "X"
	if distToFace.Y < distToFace[axis] then
		axis = "Y"
	end
	if distToFace.Z < distToFace[axis] then
		axis = "Z"
	end

	local axisValue = Utilidades.getAxisValue(localPoint, axis)
	local sign = axisValue >= 0 and 1 or -1
	if math.abs(axisValue) < 0.01 and dirLocal and math.abs(Utilidades.getAxisValue(dirLocal, axis)) > 0.01 then
		sign = Utilidades.getAxisValue(dirLocal, axis) >= 0 and 1 or -1
	end

	local facePoint = {
		X = clamped.X,
		Y = clamped.Y,
		Z = clamped.Z,
	}
	facePoint[axis] = sign * Utilidades.getAxisValue(half, axis)

	return part.CFrame:PointToWorldSpace(Utilidades.vectorFromTable(facePoint))
end

local function buildCastDataByRayToPart(character, part, origin, lookXZ, includeRayParams, includeList)
	local toCenter = part.Position - origin
	local preferredDir = toCenter.Magnitude > 0.001 and toCenter.Unit or lookXZ
	local targetPoint = getClosestSurfacePointOnPart(part, origin, preferredDir)
	local toTarget = targetPoint - origin

	if toTarget.Magnitude < 0.02 then
		local nudgeDir = preferredDir
		if not nudgeDir or nudgeDir.Magnitude < 0.001 then
			nudgeDir = Vector3.zAxis
		end
		targetPoint = getClosestSurfacePointOnPart(part, origin + nudgeDir.Unit * 0.2, nudgeDir)
		toTarget = targetPoint - origin
	end

	if toTarget.Magnitude < 0.02 then
		local fallback = buildCastDataFromPartPoint(character, part, origin, -lookXZ)
		fallback.ClosestTargetPoint = targetPoint
		return fallback
	end

	includeList[1] = part
	includeRayParams.FilterDescendantsInstances = includeList

	-- Overshoot curto evita miss por precisão no limite da superfície.
	local castDistance = toTarget.Magnitude + 0.2
	local result = Workspace:Raycast(origin, toTarget.Unit * castDistance, includeRayParams)

	if result and result.Instance == part then
		return {
			Character = character,
			Part = part,
			Result = result,
			Origin = origin,
			HitPosition = result.Position,
			Normal = result.Normal,
			ClosestTargetPoint = targetPoint,
		}
	end

	local fallback = buildCastDataFromPartPoint(character, part, targetPoint, -lookXZ)
	fallback.Origin = origin
	fallback.HitPosition = fallback.Result and fallback.Result.Position or targetPoint
	fallback.ClosestTargetPoint = targetPoint
	return fallback
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
		return nil, nil, nil
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
	local maxDist = config.ForwardObstacleMaxDistance or (maxReach + 0.5)

	local includeRayParams = RaycastParams.new()
	includeRayParams.FilterType = Enum.RaycastFilterType.Include
	includeRayParams.IgnoreWater = true
	local includeList = table.create(1)

	local candidatePoints = {}
	local rankedCandidates = {}
	local maxGrabReachHeight = config.MaxGrabReachHeight or 6.0

	for _, part in ipairs(parts) do
		local castData = buildCastDataByRayToPart(character, part, samplePoint, lookXZ, includeRayParams, includeList)
		local built = buildResultFromCast(castData)

		-- Se a face detectada não é wall-like (ex: topo de ledge), tentar forçar a face lateral
		if not built then
			local fallbackCast = buildCastDataFromPartPoint(character, part, samplePoint, -lookXZ)
			built = buildResultFromCast(fallbackCast)
		end

		if not built then
			continue
		end

		-- Clampar Y da borda ao alcance do jogador (evita bordas inalcançáveis em partes muito altas)
		local topEdge = built.TopEdgePosition
		local rawEdgeY = topEdge.Y
		local maxReachY = hrp.Position.Y + maxGrabReachHeight
		local clampedEdgeY = math.min(rawEdgeY, maxReachY)

		-- Usar a posição real do TopEdge (3D correto para faces inclinadas).
		-- Para faces verticais, XZ do TopEdge == XZ do hit; para inclinadas, preserva a geometria.
		local edgePosition = Vector3.new(
			topEdge.X,
			clampedEdgeY,
			topEdge.Z
		)
		built.TopEdgePosition = edgePosition

		local deltaXZ = Vector3.new(edgePosition.X - hrp.Position.X, 0, edgePosition.Z - hrp.Position.Z)
		local distXZ = deltaXZ.Magnitude
		local forwardDist = deltaXZ:Dot(lookXZ)
		local lateral = (deltaXZ - lookXZ * forwardDist).Magnitude
		local accepted = distXZ > 0.05 and distXZ <= maxDist

		table.insert(candidatePoints, {
			Position = edgePosition,
			Accepted = accepted,
		})

		if accepted then
			table.insert(rankedCandidates, {
				Part = part,
				CastData = built,
				ForwardDist = math.max(forwardDist, 0.01),
				LateralDist = lateral,
				DistXZ = distXZ,
			})
		end
	end

	table.sort(rankedCandidates, function(a, b)
		if math.abs(a.DistXZ - b.DistXZ) > 0.05 then
			return a.DistXZ < b.DistXZ
		end
		if math.abs(a.LateralDist - b.LateralDist) > 0.05 then
			return a.LateralDist < b.LateralDist
		end
		return a.ForwardDist > b.ForwardDist
	end)

	local bestData = rankedCandidates[1] and rankedCandidates[1].CastData or nil

	local debugData = {
		QueryBoxCFrame = queryCFrame,
		QueryBoxSize = querySize,
		CandidatePoints = candidatePoints,
	}

	return bestData, debugData, rankedCandidates
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

	Debug.Verbose("═══ CheckParkour (Box+XZ) ═══")
	Debug.Verbose("  HRP:", hrp.Position, "| Floor:", humanoid.FloorMaterial)

	-- 1) Busca por bloco frontal: achar melhor borda candidata
	local edgeData, blockDebug, rankedForwardCandidates = findForwardEdgeInBox(character, hrp, lookXZ, finalConfig)
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

	local rayParams = Utilidades.createRaycastParamsForCharacter(character)

	local function buildActionDataFromEdge(castData)
		local candidateData = table.clone(castData)
		candidateData.EdgePosition = candidateData.TopEdgePosition
		candidateData.Mode = "Top"
		-- Na detecção por caixa não usamos ray frontal primário.
		-- Limpa campos legados para evitar qualquer dependência acidental de Origin/HitPosition.
		candidateData.Origin = nil
		candidateData.HitPosition = nil
		candidateData.LookVector = lookXZ
		candidateData.HrpPosition = hrp.Position
		candidateData.ForwardQueryBoxCFrame = blockDebug and blockDebug.QueryBoxCFrame or nil
		candidateData.ForwardQueryBoxSize = blockDebug and blockDebug.QueryBoxSize or nil
		candidateData.ForwardCandidatePoints = blockDebug and blockDebug.CandidatePoints or nil

		candidateData.TorsoRayDebug = castRayToEdgeXZ(
			hrp.Position,
			candidateData.EdgePosition,
			finalConfig.TorsoRayOffset,
			finalConfig.ClassificationRayDistance or finalConfig.RayDistance,
			finalConfig.ClassificationRayExtraDistance,
			rayParams,
			finalConfig
		)
		candidateData.LegRayDebug = castRayToEdgeXZ(
			hrp.Position,
			candidateData.EdgePosition,
			finalConfig.PernaRayOffset,
			finalConfig.ClassificationRayDistance or finalConfig.RayDistance,
			finalConfig.ClassificationRayExtraDistance,
			rayParams,
			finalConfig
		)

		candidateData.Acao = classificarAcaoDePulo(
			candidateData.EdgePosition.Y,
			hrp.Position.Y,
			candidateData.TorsoRayDebug,
			candidateData.LegRayDebug,
			finalConfig
		)

		candidateData.DistanceLine = {
			PosA = hrp.Position,
			PosB = candidateData.EdgePosition,
			Color = Color3.fromRGB(255, 0, 255),
		}

		return candidateData
	end

	local function buildGrabCandidateFromCast(castData)
		local candidateData = table.clone(castData)
		candidateData.EdgePosition = candidateData.TopEdgePosition
		candidateData.Mode = "Top"
		candidateData.Origin = nil
		candidateData.HitPosition = nil
		candidateData.LookVector = lookXZ
		candidateData.HrpPosition = hrp.Position
		candidateData.ForwardQueryBoxCFrame = blockDebug and blockDebug.QueryBoxCFrame or nil
		candidateData.ForwardQueryBoxSize = blockDebug and blockDebug.QueryBoxSize or nil
		candidateData.ForwardCandidatePoints = blockDebug and blockDebug.CandidatePoints or nil
		candidateData.Acao = "Agarrar"
		candidateData.DistanceLine = {
			PosA = hrp.Position,
			PosB = candidateData.EdgePosition,
			Color = Color3.fromRGB(255, 0, 255),
		}
		return candidateData
	end

	local rightXZ = lookXZ:Cross(Vector3.yAxis)
	if rightXZ.Magnitude < 0.05 then
		rightXZ = Vector3.xAxis
	else
		rightXZ = rightXZ.Unit
	end
	local grabRetargetLateralOffset = math.max((finalConfig.GrabRetargetLateralOffset or 0.75), 0.1)

	local function buildRetargetedGrabCandidates(sourceCandidate)
		if not sourceCandidate or not sourceCandidate.Part then
			return nil
		end

		local sampleBase = hrp.Position + Vector3.yAxis * (finalConfig.ForwardObstacleSampleYOffset or 0)
		local offsets = { -grabRetargetLateralOffset, grabRetargetLateralOffset }
		local retargeted = {}

		for _, lateralOffset in ipairs(offsets) do
			local samplePoint = sampleBase + rightXZ * lateralOffset
			local castData = buildCastDataFromPartPoint(character, sourceCandidate.Part, samplePoint, -lookXZ)
			local built = buildResultFromCast(castData)
			if built and built.TopEdgePosition then
				local retargetedCandidate = buildGrabCandidateFromCast(built)
				if (retargetedCandidate.EdgePosition - sourceCandidate.EdgePosition).Magnitude > 0.08 then
					retargetedCandidate.Retargeted = true
					retargetedCandidate.RetargetLateralOffset = lateralOffset
					table.insert(retargeted, retargetedCandidate)
				end
			end
		end

		return retargeted
	end

	local function snapshotCandidateForDebug(candidateData)
		local snapshot = table.clone(candidateData)
		snapshot.DistanceLine = {
			PosA = hrp.Position,
			PosB = candidateData.EdgePosition,
			Color = Color3.fromRGB(255, 0, 255),
		}
		return snapshot
	end

	-- 2-4) Preparar e classificar candidato primário
	local data = buildActionDataFromEdge(edgeData)
	local bordaReal = data.EdgePosition
	local acao = data.Acao

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

	-- Calcular distancia real (3D) da borda primária até o HRP do player
	local distReal = (bordaReal - hrp.Position).Magnitude

	-- 5) Verificações específicas por tipo
	local function avaliarCandidatoAgarrar(candidateData)
		local _dbgP = Configs.DebugEnabled
		local checkAttempts = _dbgP and {} or nil

		local function registerAttempt(candidate)
			if checkAttempts then
				table.insert(checkAttempts, snapshotCandidateForDebug(candidate))
			end
		end

		local function avaliarSemRetarget(candidate)
			local candidateDist = (candidate.EdgePosition - hrp.Position).Magnitude

		if candidateDist > finalConfig.MaxGrabDistance then
			candidate.Aprovado = false
			candidate.Reason = "TooFarToGrab"
			candidate.GrabDistance = candidateDist
			registerAttempt(candidate)
			return false, candidate
		end

		local hasTopClearance, topBlocker, topCf, topSize = Analisador.HasTopClearance(candidate, finalConfig)
		candidate.TopClearanceCFrame = topCf
		candidate.TopClearanceSize = topSize
		candidate.HasTopClearance = hasTopClearance

		if not hasTopClearance then
			candidate.Aprovado = false
			candidate.Reason = "NoTopClearance"
			candidate.TopBlocker = topBlocker
			candidate.GrabDistance = candidateDist
			registerAttempt(candidate)
			return false, candidate
		end

		local hasFrontClearance, frontBlocker, frontCf, frontSize = Analisador.HasFrontClearance(candidate, finalConfig)
		candidate.FrontClearanceCFrame = frontCf
		candidate.FrontClearanceSize = frontSize
		candidate.HasFrontClearance = hasFrontClearance

		if not hasFrontClearance then
			candidate.Aprovado = false
			candidate.Reason = "NoFrontClearance"
			candidate.FrontBlocker = frontBlocker
			candidate.GrabDistance = candidateDist
			registerAttempt(candidate)
			return false, candidate
		end

		local idleMode, legHit, legProbeRaysDebug = Analisador.ResolveIdleMode(candidate, finalConfig)
		candidate.Aprovado = true
		candidate.Reason = "Ok"
		candidate.IdleMode = idleMode
		candidate.LegHit = legHit
		candidate.LegProbeRaysDebug = legProbeRaysDebug
		candidate.GrabDistance = candidateDist
		registerAttempt(candidate)

		return true, candidate
		end

		local okPrimary, evaluatedPrimary = avaliarSemRetarget(candidateData)
		if okPrimary then
			evaluatedPrimary.CheckAttempts = checkAttempts
			return true, evaluatedPrimary
		end

		if evaluatedPrimary.Reason == "NoTopClearance" or evaluatedPrimary.Reason == "NoFrontClearance" then
			for _, retargetedCandidate in ipairs(buildRetargetedGrabCandidates(candidateData) or {}) do
				local okRetargeted, evaluatedRetargeted = avaliarSemRetarget(retargetedCandidate)
				if okRetargeted then
					evaluatedRetargeted.Reason = "OkRetargeted"
					evaluatedRetargeted.CheckAttempts = checkAttempts
					return true, evaluatedRetargeted
				end
			end
		end

		evaluatedPrimary.CheckAttempts = checkAttempts
		return false, evaluatedPrimary
	end

	local function tentarAgarrar()
		if humanoid.FloorMaterial ~= Enum.Material.Air then
			data.Aprovado = false
			data.Reason = "CantGrabOnGround"
			Debug.Verbose("  RESULTADO:", data.Reason)
			return data
		end

		local grabCandidates = {}

		local function alreadyAdded(candidateData)
			for _, existing in ipairs(grabCandidates) do
				if existing.Part == candidateData.Part and (existing.EdgePosition - candidateData.EdgePosition).Magnitude <= 0.05 then
					return true
				end
			end
			return false
		end

		local function pushCandidate(candidateData, forwardDist)
			if not candidateData or candidateData.Acao ~= "Agarrar" then
				return
			end
			if alreadyAdded(candidateData) then
				return
			end

			candidateData.GrabDistance = (candidateData.EdgePosition - hrp.Position).Magnitude
			candidateData.ForwardDist = forwardDist or math.huge
			table.insert(grabCandidates, candidateData)
		end

		pushCandidate(data, 0)

		for _, ranked in ipairs(rankedForwardCandidates or {}) do
			if ranked and ranked.CastData then
				local candidateData = buildGrabCandidateFromCast(ranked.CastData)
				pushCandidate(candidateData, ranked.ForwardDist)
			end
		end

		table.sort(grabCandidates, function(a, b)
			if math.abs((a.GrabDistance or math.huge) - (b.GrabDistance or math.huge)) > 0.05 then
				return (a.GrabDistance or math.huge) < (b.GrabDistance or math.huge)
			end
			return (a.ForwardDist or math.huge) < (b.ForwardDist or math.huge)
		end)

		Debug.Verbose("  Grab candidates válidos para teste:", #grabCandidates)

		local evaluatedCandidatesDebug = Configs.DebugEnabled and {} or nil
		local lastFailedCandidate = data
		local preferredFailedCandidate = nil
		for index, candidateData in ipairs(grabCandidates) do
			local okGrab, evaluatedData = avaliarCandidatoAgarrar(candidateData)

			if evaluatedCandidatesDebug then
				for _, attempt in ipairs(evaluatedData.CheckAttempts or { evaluatedData }) do
					attempt.GrabCandidateIndex = index
					attempt.GrabCandidateCount = #grabCandidates
					table.insert(evaluatedCandidatesDebug, attempt)
				end
			end

			if okGrab then
				evaluatedData.GrabCandidateIndex = index
				evaluatedData.GrabCandidateCount = #grabCandidates
				evaluatedData.GrabCandidatesDebug = evaluatedCandidatesDebug
				Debug.Verbose(
					"  RESULTADO: Ok | Acao=Agarrar | Candidate:",
					index,
					"/",
					#grabCandidates,
					"| Dist:",
					string.format("%.2f", evaluatedData.GrabDistance or 0),
					"| Idle:",
					evaluatedData.IdleMode
				)
				return evaluatedData
			end

			lastFailedCandidate = evaluatedData
			if evaluatedData.Reason ~= "TooFarToGrab" and not preferredFailedCandidate then
				preferredFailedCandidate = evaluatedData
			end
			Debug.Verbose(
				"  Candidato agarrar rejeitado:",
				index,
				"/",
				#grabCandidates,
				"| Reason:",
				evaluatedData.Reason,
				"| Dist:",
				string.format("%.2f", evaluatedData.GrabDistance or 0),
				"| TopClear:",
				evaluatedData.HasTopClearance,
				"| FrontClear:",
				evaluatedData.HasFrontClearance,
				"| TopBlocker:",
				evaluatedData.TopBlocker and evaluatedData.TopBlocker.Name or "nil",
				"| FrontBlocker:",
				evaluatedData.FrontBlocker and evaluatedData.FrontBlocker.Name or "nil",
				"| Retargeted:",
				evaluatedData.Retargeted == true
			)
		end

		local failedCandidate = preferredFailedCandidate or lastFailedCandidate
		if failedCandidate and evaluatedCandidatesDebug then
			failedCandidate.GrabCandidatesDebug = evaluatedCandidatesDebug
		end

		Debug.Verbose("  RESULTADO:", failedCandidate and failedCandidate.Reason or "NoGrabCandidate")
		return failedCandidate
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
	local flatNormal = Vector3.new(currentNormal.X, 0, currentNormal.Z)
	if flatNormal.Magnitude < 0.01 then
		flatNormal = currentNormal.Unit
	else
		flatNormal = flatNormal.Unit
	end
	local areaCenter = currentEdgePos
		+ flatNormal * (probeOffset - areaSize.Z * 0.5)
		+ Vector3.yAxis * areaUpOffset
	local areaCFrame = Utilidades.getSurfaceFrame(areaCenter, flatNormal)

	local subirDebug = Configs.DebugEnabled and {
		QueryBoxCFrame = areaCFrame,
		QueryBoxSize = areaSize,
		CandidatePoints = {},
		EscalarChecks = {},
	} or nil

	Debug.Verbose("═══ CheckSubir (Area) ═══")
	Debug.Verbose("  EdgePos:", currentEdgePos, "| Normal:", currentNormal)
	Debug.Verbose("  QueryCenter:", areaCenter, "| AreaSize:", areaSize)

	local parts = collectValidPartsInBox(areaCFrame, areaSize, {character}, finalConfig.MinPartHeight)
	local candidates = table.create(#parts)
	local minVerticalDelta = finalConfig.SubirMinVerticalDelta or 0.5
	local samplePointBase = currentEdgePos + currentNormal.Unit * probeOffset
	local maxEscalarVerticalDistance = finalConfig.EscalarMaxVerticalDistance or finalConfig.SubirMaxAltura or 6.0
	local wallForwardXZ = getHorizontalUnit(-currentNormal)
	local maxHorizontalDistance = math.max(finalConfig.SubirMaxHorizontalDistance or 5.5, 0.1)
	local maxProfundidadeSubir = math.max(finalConfig.SubirMaxProfundidade or 3.0, 0.1)
	local maxProfundidadeSubirSalto = math.max(finalConfig.SubirSaltoMaxProfundidade or 4.5, 0.1)
	-- Filtro inicial usa o maior dos dois limites para não descartar candidatos prematuramente
	local maxDepthDistance = math.max(maxProfundidadeSubir, maxProfundidadeSubirSalto)

	for _, part in ipairs(parts) do
		local castData = buildCastDataFromPartPoint(character, part, samplePointBase, currentNormal)
		local built = buildResultFromCast(castData)
		if not built then
			continue
		end

		local topEdge = built.TopEdgePosition
		local vertDist = topEdge.Y - currentEdgePos.Y
		if vertDist <= minVerticalDelta then
			if subirDebug then
				table.insert(subirDebug.CandidatePoints, {
					Position = topEdge,
					Accepted = false,
				})
			end
			continue
		end

		if not isWallLikeNormal(built.Normal, finalConfig) then
			if subirDebug then
				table.insert(subirDebug.CandidatePoints, {
					Position = topEdge,
					Accepted = false,
				})
			end
			continue
		end

		local horizDelta = Vector3.new(topEdge.X - currentEdgePos.X, 0, topEdge.Z - currentEdgePos.Z)
		local horizDist = horizDelta.Magnitude
		local depthDist = wallForwardXZ and math.abs(horizDelta:Dot(wallForwardXZ)) or horizDist

		if horizDist > maxHorizontalDistance then
			Debug.Verbose(
				"  Candidato rejeitado (TooFarHorizontally):",
				part.Name,
				"| HorizDist:",
				string.format("%.2f", horizDist),
				"| Max:",
				string.format("%.2f", maxHorizontalDistance)
			)
			if subirDebug then
				table.insert(subirDebug.CandidatePoints, {
					Position = topEdge,
					Accepted = false,
				})
			end
			continue
		end

		if depthDist > maxDepthDistance then
			Debug.Verbose(
				"  Candidato rejeitado (TooDeepFromCurrentWall):",
				part.Name,
				"| DepthDist:",
				string.format("%.2f", depthDist),
				"| Max:",
				string.format("%.2f", maxDepthDistance)
			)
			if subirDebug then
				table.insert(subirDebug.CandidatePoints, {
					Position = topEdge,
					Accepted = false,
				})
			end
			continue
		end

		table.insert(candidates, {
			Part = part,
			EdgePosition = topEdge,
			Normal = built.Normal,
			VertDist = vertDist,
			HorizDist = horizDist,
			DepthDist = depthDist,
		})

		if subirDebug then
			table.insert(subirDebug.CandidatePoints, {
				Position = topEdge,
				Accepted = true,
			})
		end
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

		-- Filtro de profundidade por tipo de ação
		local maxProfundidadeParaTipo = if tipo == "SubirSalto" then maxProfundidadeSubirSalto else maxProfundidadeSubir
		if cand.DepthDist > maxProfundidadeParaTipo then
			Debug.Verbose(
				"  Candidato rejeitado (TooDeepFor" .. tipo .. "):",
				cand.Part.Name,
				"| DepthDist:",
				string.format("%.2f", cand.DepthDist),
				"| MaxProfundidade:",
				string.format("%.2f", maxProfundidadeParaTipo)
			)
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
				if subirDebug then
					table.insert(subirDebug.EscalarChecks, {
						ClearanceCFrame = escalarCandidate.ClearanceCFrame,
						ClearanceSize = escalarCandidate.ClearanceSize,
						CanEscalar = escalarCandidate.CanEscalar,
					})
				end
			end

			if escalarCandidate and escalarCandidate.CanEscalar then
				escalarCandidate.SourceEdgePosition = currentEdgePos
				escalarCandidate.VerticalDistance = cand.VertDist
				bestEscalarFallback = escalarCandidate
			end
		end

		Debug.Verbose(
			"  Testando candidato:",
			cand.Part.Name,
			"| HorizDist:",
			string.format("%.2f", cand.HorizDist),
			"| DepthDist:",
			string.format("%.2f", cand.DepthDist or 0),
			"| VertDist:",
			string.format("%.1f", cand.VertDist)
		)

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
	local flatNormal = Vector3.new(currentNormal.X, 0, currentNormal.Z)
	if flatNormal.Magnitude < 0.01 then
		flatNormal = currentNormal.Unit
	else
		flatNormal = flatNormal.Unit
	end
	local areaCenter = currentEdgePos
		+ flatNormal * (probeOffset - areaSize.Z * 0.5)
		+ Vector3.yAxis * areaDownOffset
	local areaCFrame = Utilidades.getSurfaceFrame(areaCenter, flatNormal)

	Debug.Verbose("═══ CheckDescer (Area) ═══")
	Debug.Verbose("  EdgePos:", currentEdgePos, "| Normal:", currentNormal)
	Debug.Verbose("  QueryCenter:", areaCenter, "| AreaSize:", areaSize)

	local descerDebug = Configs.DebugEnabled and {
		QueryBoxCFrame = areaCFrame,
		QueryBoxSize = areaSize,
		CandidatePoints = {},
	} or nil

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
			if descerDebug then
				table.insert(descerDebug.CandidatePoints, {
					Position = topEdge,
					Accepted = false,
				})
			end
			continue
		end

		if not isWallLikeNormal(built.Normal, finalConfig) then
			if descerDebug then
				table.insert(descerDebug.CandidatePoints, {
					Position = topEdge,
					Accepted = false,
				})
			end
			continue
		end

		local horizDelta = Vector3.new(topEdge.X - currentEdgePos.X, 0, topEdge.Z - currentEdgePos.Z)
		local horizDist = horizDelta.Magnitude
		local depthDistance = math.abs((topEdge - currentEdgePos):Dot(wallPlanarNormal))
		if depthDistance > maxDepth then
			if descerDebug then
				table.insert(descerDebug.CandidatePoints, {
					Position = topEdge,
					Accepted = false,
				})
			end
			continue
		end

		table.insert(candidates, {
			Part = part,
			EdgePosition = topEdge,
			Normal = built.Normal,
			VertDist = vertDist,
			HorizDist = horizDist,
		})

		if descerDebug then
			table.insert(descerDebug.CandidatePoints, {
				Position = topEdge,
				Accepted = true,
			})
		end
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
	local flatNormal = Vector3.new(currentNormal.X, 0, currentNormal.Z)
	if flatNormal.Magnitude < 0.01 then
		flatNormal = currentNormal.Unit
	else
		flatNormal = flatNormal.Unit
	end
	local areaCenter = currentEdgePos
		+ flatNormal * (probeOffset - areaSize.Z * 0.5)
		+ Vector3.yAxis * areaUpOffset
		+ sideDir * (areaSize.X * lateralSideBias)
	local currentWallNormal = flatNormal
	local areaCFrame = Utilidades.getSurfaceFrame(areaCenter, flatNormal)

	local lateralDebug = Configs.DebugEnabled and {
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
	} or nil

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
		if not lateralDebug then return end
		lateralDebug.RejectionCounts[reason] = (lateralDebug.RejectionCounts[reason] or 0) + 1
	end

	local function recordRejected(part, topEdge, reason, extra)
		if not lateralDebug then return end
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
		if not lateralDebug then return end
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
			+ flatNormal * pathClearanceNormalOffset
			+ Vector3.yAxis * pathClearanceHeightOffset
		local probeCenter = probeBase + sideDir * sideClearanceDistance
		local probeCf = Utilidades.getSurfaceFrame(probeCenter, flatNormal)
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

		if lateralDebug then
			table.insert(lateralDebug.PathClearanceBoxes, {
				CFrame = probeCf,
				Size = probeSize,
				Clear = clear,
			})
		end

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
		if lateralDebug then
			table.insert(lateralDebug.PathClearanceRays, {
				Origin = rayOrigin,
				HitPosition = rayResult and rayResult.Position or rayTarget,
				Hit = rayResult ~= nil,
				Clear = rayResult == nil or hitIsTargetSurface,
			})
		end

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

			if lateralDebug then
				lateralDebug.Selected = {
					Type = "LateralSalto",
					Part = jumpBest.PartName,
					SideDistance = jumpBest.SideDistance,
					SideDistanceRaw = jumpBest.SideDistanceRaw,
					SideDistanceClamped = jumpBest.SideDistanceClamped,
					CornerType = jumpBest.CornerType,
				}
			end

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

		if lateralDebug then
			lateralDebug.Selected = {
				Type = "LateralSaltoPreferido",
				Part = jumpBest.PartName,
				SideDistance = jumpBest.SideDistance,
				SideDistanceRaw = jumpBest.SideDistanceRaw,
				SideDistanceClamped = jumpBest.SideDistanceClamped,
				CornerType = jumpBest.CornerType,
			}
		end

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

	if lateralDebug then
		lateralDebug.Selected = {
			Type = "Lateral",
			Part = best.PartName,
			SideDistance = best.SideDistance,
			SideDistanceRaw = best.SideDistanceRaw,
			SideDistanceClamped = best.SideDistanceClamped,
			CornerType = best.CornerType,
		}
	end

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

	if not isWallLikeNormal(fallback.Normal, finalConfig) then
		local lookBase = fallback.LookVector
		if not lookBase or lookBase.Magnitude < 0.001 then
			lookBase = hrp.CFrame.LookVector
		end

		local lookXZ = Vector3.new(lookBase.X, 0, lookBase.Z)
		if lookXZ.Magnitude > 0.001 then
			fallback.Normal = -lookXZ.Unit
		else
			local planarNormal = Vector3.new(fallback.Normal.X, 0, fallback.Normal.Z)
			if planarNormal.Magnitude > 0.001 then
				fallback.Normal = planarNormal.Unit
			else
				fallback.Normal = Vector3.new(0, 0, -1)
			end
		end

		Debug.Verbose("[Parkour] Fallback Agarrar normal ajustada para parede | novo:", fallback.Normal)
	end

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
