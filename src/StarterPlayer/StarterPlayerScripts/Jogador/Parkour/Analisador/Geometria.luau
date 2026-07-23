--[[
	Módulo: Geometria
	Pai: Analisador (Parkour)
	Responsabilidade: geometria pura de bordas/faces, sondagem de malhas
		(MeshPart/UnionOperation), construção de "cast data" e coleta de partes
		válidas dentro de uma caixa. NÃO decide ações de parkour: apenas fornece
		dados geométricos consumidos pelos demais módulos.
	Uso: ModuleScript; require(caminho) e use as funções da tabela retornada.

	Refatoração:
	- `buildResultFromCast` agora recebe `finalConfig` (antes usava
	  Configs.DefaultConfig fixo, ignorando MaxWallNormalY customizado). BUGFIX.
	- RaycastParams próprio e exclusivo do módulo (antes era um objeto global
	  compartilhado entre módulos que se chamavam entre si - frágil).
]]

local Workspace = game:GetService("Workspace")

local Utilidades = require(script.Parent.Parent.Utilidades)

local Geometria = {}

local MESH_PROBE_OFFSET = 0.5
local MESH_PROBE_COARSE_STEP = 0.35
local MESH_PROBE_BINARY_ITERS = 6
local MESH_PROBE_RAY_LENGTH = 2.0

-- RaycastParams reutilizável e EXCLUSIVO deste módulo (modo Include).
local includeRayParams = RaycastParams.new()
includeRayParams.FilterType = Enum.RaycastFilterType.Include
includeRayParams.IgnoreWater = true

-- Scratch buffers reutilizados para evitar alocação a cada frame.
local _probeDirBuffer = table.create(3)
local _probeDirLen = 0
local _collectSeen = {}

local function isMeshLikePart(part)
	return part:IsA("MeshPart") or part:IsA("UnionOperation")
end

local function isWallLikeNormal(normal, config)
	local maxWallNormalY = config.MaxWallNormalY or 0.35
	return math.abs(normal.Unit.Y) <= maxWallNormalY
end

local function getHorizontalUnit(vector)
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < 0.001 then
		return nil
	end
	return flat.Unit
end

local function setAxis(x, y, z, axis, value)
	if axis == "X" then
		return value, y, z
	elseif axis == "Y" then
		return x, value, z
	else
		return x, y, value
	end
end

local function computeFaceVerticalEdges(part, result)
	local half = part.Size / 2

	local hitLocal = part.CFrame:PointToObjectSpace(result.Position)
	local normalLocal = part.CFrame:VectorToObjectSpace(result.Normal)
	local worldUpLocal = part.CFrame:VectorToObjectSpace(Vector3.new(0, 1, 0))

	local faceAxis, faceSign, tangentA, tangentB = Utilidades.getFaceAxes(normalLocal)

	local verticalAxis
	local otherAxis

	if
		math.abs(Utilidades.getAxisValue(worldUpLocal, tangentA))
		>= math.abs(Utilidades.getAxisValue(worldUpLocal, tangentB))
	then
		verticalAxis = tangentA
		otherAxis = tangentB
	else
		verticalAxis = tangentB
		otherAxis = tangentA
	end

	local topSign = Utilidades.getAxisValue(worldUpLocal, verticalAxis) >= 0 and 1 or -1

	local cX = math.clamp(hitLocal.X, -half.X, half.X)
	local cY = math.clamp(hitLocal.Y, -half.Y, half.Y)
	local cZ = math.clamp(hitLocal.Z, -half.Z, half.Z)

	cX, cY, cZ = setAxis(cX, cY, cZ, faceAxis, faceSign * Utilidades.getAxisValue(half, faceAxis))
	local otherClamped = math.clamp(
		Utilidades.getAxisValue(hitLocal, otherAxis),
		-Utilidades.getAxisValue(half, otherAxis),
		Utilidades.getAxisValue(half, otherAxis)
	)
	cX, cY, cZ = setAxis(cX, cY, cZ, otherAxis, otherClamped)

	local topX, topY, topZ = setAxis(cX, cY, cZ, verticalAxis, topSign * Utilidades.getAxisValue(half, verticalAxis))
	local botX, botY, botZ = setAxis(cX, cY, cZ, verticalAxis, -topSign * Utilidades.getAxisValue(half, verticalAxis))

	return Vector3.new(topX, topY, topZ), Vector3.new(botX, botY, botZ)
end

local function probeMeshVerticalEdge(part, hitPosition, hitNormal, searchUp)
	local flatNormal = Vector3.new(hitNormal.X, 0, hitNormal.Z)
	if flatNormal.Magnitude < 0.01 then
		return nil
	end
	flatNormal = flatNormal.Unit

	local half = part.Size / 2
	local hitLocal = part.CFrame:PointToObjectSpace(hitPosition)
	local maxSweep = searchUp and (half.Y - hitLocal.Y) or (half.Y + hitLocal.Y)
	maxSweep = math.max(maxSweep + 0.5, 1.0)

	local step = MESH_PROBE_COARSE_STEP
	local direction = searchUp and 1 or -1
	local rayOriginOffset = flatNormal * MESH_PROBE_OFFSET
	local rayDir = -flatNormal * MESH_PROBE_RAY_LENGTH

	includeRayParams.FilterDescendantsInstances = { part }

	local lastHitPos = hitPosition
	local lastHitY = hitPosition.Y
	local transitionFound = false
	local missY = hitPosition.Y

	local steps = math.ceil(maxSweep / step)
	for i = 1, steps do
		local yOffset = direction * step * i
		local probePos = hitPosition + Vector3.yAxis * yOffset
		local rayOrigin = probePos + rayOriginOffset
		local result = Workspace:Raycast(rayOrigin, rayDir, includeRayParams)

		if result and result.Instance == part then
			lastHitPos = result.Position
			lastHitY = probePos.Y
		else
			missY = probePos.Y
			transitionFound = true
			break
		end
	end

	if not transitionFound then
		return lastHitPos
	end

	local lowY = math.min(lastHitY, missY)
	local highY = math.max(lastHitY, missY)
	local bestHitPos = lastHitPos

	for _ = 1, MESH_PROBE_BINARY_ITERS do
		local midY = (lowY + highY) / 2
		local probePos = Vector3.new(hitPosition.X, midY, hitPosition.Z)
		local rayOrigin = probePos + rayOriginOffset
		local result = Workspace:Raycast(rayOrigin, rayDir, includeRayParams)

		if result and result.Instance == part then
			bestHitPos = result.Position
			if searchUp then
				lowY = midY
			else
				highY = midY
			end
		else
			if searchUp then
				highY = midY
			else
				lowY = midY
			end
		end
	end

	return bestHitPos
end

local function computeMeshFaceVerticalEdges(part, result)
	local hitPos = result.Position
	local hitNormal = result.Normal

	local topWorld = probeMeshVerticalEdge(part, hitPos, hitNormal, true)
	local bottomWorld = probeMeshVerticalEdge(part, hitPos, hitNormal, false)

	if not topWorld or not bottomWorld then
		local topLocal, bottomLocal = computeFaceVerticalEdges(part, result)
		return part.CFrame:PointToWorldSpace(topLocal), part.CFrame:PointToWorldSpace(bottomLocal)
	end

	return topWorld, bottomWorld
end

-- Recebe finalConfig (merge já resolvido pelo chamador). Retorna castData
-- enriquecido com TopEdgePosition/BottomEdgePosition, ou nil se a normal não
-- for de parede.
local function buildResultFromCast(castData, finalConfig)
	if not castData then
		return nil
	end

	local resultNormal = castData.Normal or (castData.Result and castData.Result.Normal)
	if resultNormal and not isWallLikeNormal(resultNormal, finalConfig) then
		return nil
	end

	if isMeshLikePart(castData.Part) then
		local topWorld, bottomWorld = computeMeshFaceVerticalEdges(castData.Part, castData.Result)
		castData.TopEdgePosition = topWorld
		castData.BottomEdgePosition = bottomWorld
	else
		local topLocal, bottomLocal = computeFaceVerticalEdges(castData.Part, castData.Result)
		castData.TopEdgePosition = castData.Part.CFrame:PointToWorldSpace(topLocal)
		castData.BottomEdgePosition = castData.Part.CFrame:PointToWorldSpace(bottomLocal)
	end

	return castData
end

local function buildCastDataFromPartPoint(character, part, samplePoint, preferredNormal)
	if isMeshLikePart(part) then
		includeRayParams.FilterDescendantsInstances = { part }

		_probeDirLen = 0
		if preferredNormal and preferredNormal.Magnitude > 0.001 then
			_probeDirLen += 1
			_probeDirBuffer[_probeDirLen] = -preferredNormal.Unit
		end
		local toCenter = part.Position - samplePoint
		if toCenter.Magnitude > 0.01 then
			_probeDirLen += 1
			_probeDirBuffer[_probeDirLen] = toCenter.Unit
		end
		local toCenterXZ = Vector3.new(toCenter.X, 0, toCenter.Z)
		if toCenterXZ.Magnitude > 0.01 then
			_probeDirLen += 1
			_probeDirBuffer[_probeDirLen] = toCenterXZ.Unit
		end

		for i = 1, _probeDirLen do
			local dir = _probeDirBuffer[i]
			local rayOrigin = samplePoint
			local rayLength = (part.Size.Magnitude * 0.5) + MESH_PROBE_OFFSET + 1.0
			local result = Workspace:Raycast(rayOrigin, dir * rayLength, includeRayParams)
			if result and result.Instance == part then
				return {
					Character = character,
					Part = part,
					Result = result,
					Origin = samplePoint,
					HitPosition = result.Position,
					Normal = result.Normal,
				}
			end
		end
	end

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
	if isMeshLikePart(part) then
		includeRayParams.FilterDescendantsInstances = { part }

		local directions = {}

		if preferredDirWorld and preferredDirWorld.Magnitude > 0.001 then
			table.insert(directions, preferredDirWorld.Unit)
		end

		local toCenter = part.Position - worldPoint
		if toCenter.Magnitude > 0.01 then
			table.insert(directions, toCenter.Unit)
		end

		local rayLength = (part.Size.Magnitude * 0.5) + MESH_PROBE_OFFSET + 1.0
		for _, dir in ipairs(directions) do
			local result = Workspace:Raycast(worldPoint, dir * rayLength, includeRayParams)
			if result and result.Instance == part then
				return result.Position
			end
		end
	end

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

local function collectValidPartsInBox(cframe, size, ignoreList, minPartHeight, tagNaoAgarravel)
	local params = Utilidades.createOverlapParams(ignoreList, 0)
	local rawParts = Workspace:GetPartBoundsInBox(cframe, size, params)
	table.clear(_collectSeen)
	local filtered = table.create(#rawParts)

	for _, part in ipairs(rawParts) do
		if
			part:IsA("BasePart")
			and not _collectSeen[part]
			and not Utilidades.isParkourIgnoredPart(part, minPartHeight)
			and not Utilidades.hasTagDeep(part, tagNaoAgarravel)
		then
			_collectSeen[part] = true
			table.insert(filtered, part)
		end
	end

	return filtered
end

Geometria.isMeshLikePart = isMeshLikePart
Geometria.isWallLikeNormal = isWallLikeNormal
Geometria.getHorizontalUnit = getHorizontalUnit
Geometria.computeFaceVerticalEdges = computeFaceVerticalEdges
Geometria.computeMeshFaceVerticalEdges = computeMeshFaceVerticalEdges
Geometria.buildResultFromCast = buildResultFromCast
Geometria.buildCastDataFromPartPoint = buildCastDataFromPartPoint
Geometria.getClosestSurfacePointOnPart = getClosestSurfacePointOnPart
Geometria.collectValidPartsInBox = collectValidPartsInBox

return Geometria
