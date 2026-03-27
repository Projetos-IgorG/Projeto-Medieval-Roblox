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

local function addEdgeInfo(data, edgeMode)
	if not data then
		return nil
	end

	if edgeMode == "Bottom" then
		data.EdgePosition = data.BottomEdgePosition
		data.Mode = "Bottom"
	else
		data.EdgePosition = data.TopEdgePosition
		data.Mode = "Top"
	end

	return data
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
-- Raycast Público
-- ══════════════════════════════════════

function Analisador.CreateRaycastParams(character, extraIgnore)
	return Utilidades.createRaycastParamsForCharacter(character, extraIgnore)
end

function Analisador.RaycastForward(character, distance)
	local hrp = Utilidades.getCharacterParts(character)
	if not hrp then
		return nil
	end

	local origin = hrp.Position
	local direction = hrp.CFrame.LookVector * distance
	local result = Workspace:Raycast(origin, direction, Utilidades.createRaycastParamsForCharacter(character))

	if not result or not result.Instance or not result.Instance:IsA("BasePart") then
		return nil
	end

	return {
		Character = character,
		Part = result.Instance,
		Result = result,
		Origin = origin,
		HitPosition = result.Position,
		Normal = result.Normal,
	}
end

-- ══════════════════════════════════════
-- Varredura Vertical (melhor hit)
-- ══════════════════════════════════════

function Analisador.FindBestForwardHit(character, config)
	local finalConfig = Configs.mergeConfig(config)
	local hrp = Utilidades.getCharacterParts(character)
	if not hrp then
		return nil
	end

	local look = hrp.CFrame.LookVector
	local baseOrigin = hrp.Position + Vector3.yAxis * finalConfig.HeadHeightOffset

	local orderedOffsets = Utilidades.getOrderedVerticalOffsets(finalConfig)
	local rayParams = Utilidades.createRaycastParamsForCharacter(character)
	local rayDebug = {}

	local bestHitData = nil
	local bestDistance = math.huge

	for _, verticalOffset in ipairs(orderedOffsets) do
		local origin = baseOrigin + Vector3.yAxis * verticalOffset
		local direction = look * finalConfig.RayDistance
		local result = Workspace:Raycast(origin, direction, rayParams)

		table.insert(rayDebug, {
			Origin = origin,
			HitPosition = result and result.Position or (origin + direction),
			Hit = result ~= nil,
		})

		if result and result.Instance and result.Instance:IsA("BasePart") then
			-- Ignorar peças muito pequenas (grama, decoração)
			if not Utilidades.isIgnorablePart(result.Instance, finalConfig.MinPartHeight) then
				local dist = (result.Position - origin).Magnitude

				-- Priorizar a superfície mais próxima (menor distância horizontal)
				-- Isso permite detectar uma borda ou ledge que está "para fora" de uma parede de fundo
				if dist < bestDistance then
					bestDistance = dist
					bestHitData = {
						Character = character,
						Part = result.Instance,
						Result = result,
						Origin = origin,
						HitPosition = result.Position,
						Normal = result.Normal,
						Distance = dist,
						-- Vamos guardar o rayDebug completo no final
					}
				end
			end
		end
	end

	if bestHitData then
		bestHitData.RayDebug = rayDebug
		return bestHitData
	end

	return nil
end

-- ══════════════════════════════════════
-- Bordas (Top / Bottom)
-- ══════════════════════════════════════

function Analisador.GetTopEdge(character, distance)
	local data = buildResultFromCast(Analisador.FindBestForwardHit(character, {
		RayDistance = distance,
		VerticalOffsets = {0},
	}))

	if not data then
		return nil
	end

	return addEdgeInfo(data, "Top")
end

function Analisador.GetBottomEdge(character, distance)
	local data = buildResultFromCast(Analisador.FindBestForwardHit(character, {
		RayDistance = distance,
		VerticalOffsets = {0},
	}))

	if not data then
		return nil
	end

	return addEdgeInfo(data, "Bottom")
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
-- Verificação Completa: CheckGrabbable
-- ══════════════════════════════════════

function Analisador.CheckGrabbable(character, config)
	local finalConfig = Configs.mergeConfig(config)

	local castData = Analisador.FindBestForwardHit(character, finalConfig)
	if not castData then
		return {
			CanGrab = false,
			Reason = "NoForwardHit",
		}
	end

	if Utilidades.hasTagDeep(castData.Part, Configs.Tags.NAO_AGARRAVEL) then
		return {
			CanGrab = false,
			Reason = "TaggedNaoAgarravel",
			Part = castData.Part,
			Result = castData.Result,
			HitPosition = castData.HitPosition,
			Origin = castData.Origin,
			Normal = castData.Normal,
			RayDebug = castData.RayDebug,
		}
	end

	local data = buildResultFromCast(castData)
	addEdgeInfo(data, finalConfig.EdgeMode)

	local hasTopClearance, topBlocker, topCf, topSize = Analisador.HasTopClearance(data, finalConfig)
	if not hasTopClearance then
		data.CanGrab = false
		data.Reason = "NoTopClearance"
		data.TopBlocker = topBlocker
		data.TopClearanceCFrame = topCf
		data.TopClearanceSize = topSize
		return data
	end

	local hasFrontClearance, frontBlocker, frontCf, frontSize = Analisador.HasFrontClearance(data, finalConfig)
	if not hasFrontClearance then
		data.CanGrab = false
		data.Reason = "NoFrontClearance"
		data.FrontBlocker = frontBlocker
		data.FrontClearanceCFrame = frontCf
		data.FrontClearanceSize = frontSize
		return data
	end

	local idleMode, legHit, legProbeRaysDebug = Analisador.ResolveIdleMode(data, finalConfig)

	data.CanGrab = true
	data.Reason = "Ok"
	data.IdleMode = idleMode
	data.LegHit = legHit
	data.LegProbeRaysDebug = legProbeRaysDebug
	data.TopClearanceCFrame = topCf
	data.TopClearanceSize = topSize
	data.FrontClearanceCFrame = frontCf
	data.FrontClearanceSize = frontSize

	return data
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

	-- Centralizado em cima da borda
	local margin = 0.05
	local center = bordaReal + Vector3.yAxis * (finalConfig.VaultClearanceSize.Y / 2 + margin)

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
-- Rays Extras (torso + perna)
-- ══════════════════════════════════════

local function castExtraRay(hrp, look, yOffset, distance, rayParams)
	local origin = hrp.Position + Vector3.yAxis * yOffset
	local direction = look * distance
	local result = Workspace:Raycast(origin, direction, rayParams)

	return {
		Origin = origin,
		HitPosition = result and result.Position or (origin + direction),
		Hit = result ~= nil,
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
-- Classificar altura da borda
-- ══════════════════════════════════════

local function classificarAltura(bordaY, hrpY, config)
	local yTopoTorso = hrpY + config.TopoTorsoOffset
	local yBaseTorso = hrpY + config.BaseTorsoOffset

	if bordaY > yTopoTorso then
		return "Agarrar"
	elseif bordaY >= yBaseTorso then
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
	local rayParams = Utilidades.createRaycastParamsForCharacter(character)

	-- 1) Varredura vertical: achar superfície
	local castData = Analisador.FindBestForwardHit(character, finalConfig)
	if not castData then
		return {
			Aprovado = false,
			Reason = "NoForwardHit",
		}
	end

	-- Tag check
	if Utilidades.hasTagDeep(castData.Part, Configs.Tags.NAO_AGARRAVEL) then
		return {
			Aprovado = false,
			Reason = "TaggedNaoAgarravel",
			Part = castData.Part,
			RayDebug = castData.RayDebug,
		}
	end

	-- 2) Edge detection
	local data = buildResultFromCast(castData)
	addEdgeInfo(data, "Top")
	data.LookVector = look
	data.HrpPosition = hrp.Position

	-- 3) Rays extras (torso + perna) para debug e reforço
	data.TorsoRayDebug = castExtraRay(hrp, look, finalConfig.TorsoRayOffset, finalConfig.RayDistance, rayParams)
	data.LegRayDebug = castExtraRay(hrp, look, finalConfig.PernaRayOffset, finalConfig.RayDistance, rayParams)

	-- 4) Classificar altura
	local bordaReal = data.EdgePosition
	local acao = classificarAltura(bordaReal.Y, hrp.Position.Y, finalConfig)
	data.Acao = acao

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
			return data
		end

		if distReal > finalConfig.MaxGrabDistance then
			data.Aprovado = false
			data.Reason = "TooFarToGrab"
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
			return data
		end

		-- Idle mode
		local idleMode, legHit, legProbeRaysDebug = Analisador.ResolveIdleMode(data, finalConfig)
		data.Aprovado = true
		data.Reason = "Ok"
		data.IdleMode = idleMode
		data.LegHit = legHit
		data.LegProbeRaysDebug = legProbeRaysDebug

		return data
	end

	if acao == "Agarrar" then
		return tentarAgarrar()

	else -- VaultMedio ou VaultBaixo
		if distReal > finalConfig.MaxVaultDistance then
			data.Aprovado = false
			data.Reason = "TooFarToVault"
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
				return tentarAgarrar()
			end

			data.Aprovado = false
			data.Reason = "NoVaultClearance"
			data.VaultBlocker = vaultBlocker
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
				return tentarAgarrar()
			end

			data.Aprovado = false
			data.Reason = "NoVaultEdgeClearance"
			data.VaultEdgeBlocker = edgeBlocker
			return data
		end

		data.Aprovado = true
		data.Reason = "Ok"
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
	}

	Debug.Verbose("═══ CheckSubir (Area) ═══")
	Debug.Verbose("  EdgePos:", currentEdgePos, "| Normal:", currentNormal)
	Debug.Verbose("  QueryCenter:", areaCenter, "| AreaSize:", areaSize)

	local parts = collectValidPartsInBox(areaCFrame, areaSize, {character}, finalConfig.MinPartHeight)
	local candidates = table.create(#parts)
	local minVerticalDelta = finalConfig.SubirMinVerticalDelta or 0.5
	local samplePointBase = currentEdgePos + currentNormal.Unit * probeOffset

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
		PosFinal = bestCandidate.PosFinal, -- Necessário para o fallback do Escalar
		ClearanceCFrame = bestCandidate.ClearanceCFrame,
		ClearanceSize = bestCandidate.ClearanceSize,
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
	local desiredSideOffset = math.max(finalConfig.LateralTargetSideOffset or 2.2, 0.4)
	local sampleSideOffset = math.min(areaSize.X * 0.5, desiredSideOffset)
	local minLateralSideDistance = finalConfig.LateralMinSideDistance or 0.05
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
			function(part) return Utilidades.isIgnorablePart(part, finalConfig.MinPartHeight) end
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
		table.insert(lateralDebug.PathClearanceRays, {
			Origin = rayOrigin,
			HitPosition = rayResult and rayResult.Position or rayTarget,
			Hit = rayResult ~= nil,
			Clear = rayResult == nil or (targetPart ~= nil and rayResult.Instance == targetPart),
		})

		if not rayResult then
			return true, nil
		end

		if targetPart and rayResult.Instance == targetPart then
			return true, nil
		end

		return false, rayResult.Instance
	end

	local function evaluateBuiltCandidate(part, built, isCornerProbe)
		local topEdge = built.TopEdgePosition
		local topEdgeDeltaY = math.abs(topEdge.Y - currentEdgePos.Y)
		if topEdgeDeltaY > lateralTopEdgeTolerance then
			recordRejected(part, topEdge, "TopEdgeDeltaTooHigh", {
				TopEdgeDeltaY = topEdgeDeltaY,
				TopEdgeTolerance = lateralTopEdgeTolerance,
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
		local isLateralSalto = lateralDistance <= (finalConfig.LateralSaltoMaxHorizontal or 11.0)
			and math.abs(verticalDelta) <= (finalConfig.LateralSaltoMaxVertical or 2.8)

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
			table.sort(jumpCandidates, function(a, b)
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

			Debug.Verbose("  Ranking LateralSalto (top 3):")
			logTopCandidates("Jump", jumpCandidates, 3)

			local jumpBest = jumpCandidates[1]
			local idleMode, legHit, legProbeRaysDebug = Analisador.ResolveIdleMode({
				Character = character,
				Part = jumpBest.Part,
				EdgePosition = jumpBest.EdgePosition,
				Normal = jumpBest.Normal,
			}, finalConfig)

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
				LateralSaltoTarget = {
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
				},
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
	local rayParams = Utilidades.createRaycastParamsForCharacter(character)

	if not isWallLikeNormal(currentNormal, finalConfig) then
		Debug.Verbose("  RESULTADO: InvalidCurrentNormalForEscalar | Normal:", currentNormal)
		return {
			CanEscalar = false,
			Reason = "InvalidCurrentNormalForEscalar",
		}
	end

	Debug.Verbose("═══ CheckEscalar ═══")
	Debug.Verbose("  EdgePos:", currentEdgePos, "| Normal:", currentNormal)
	Debug.Verbose("  Part:", currentPart and currentPart.Name or "nil")

	-- Verificar se o player cabe EM CIMA da plataforma (em pé)
	-- Usa os MESMOS valores de tamanho e offset do Vault (referência a partir da borda)
	local look = -currentNormal.Unit -- direção para frente (para dentro da plataforma)
	local margin = 0.05
	local center = currentEdgePos
		+ Vector3.yAxis * (finalConfig.VaultClearanceUpOffset + margin)
		+ look * finalConfig.VaultClearanceForwardOffset

	local cf = CFrame.lookAt(center, center + look, Vector3.yAxis)
	local clearanceSize = finalConfig.VaultClearanceSize
	local minH = finalConfig.MinPartHeight

	Debug.Verbose("  ClearanceCenter:", center, "| Size:", clearanceSize)

	-- Ignore list: character + a part que o player está agarrado
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

	-- Posição final (onde o player ficaria em pé)
	local posFinal = currentEdgePos
		+ Vector3.yAxis * finalConfig.EscalarUpOffset
		+ look * finalConfig.EscalarForwardOffset

	-- Floor check robusto: testa multiplos offsets para nao falhar em cantos/quinas.
	local floorRayDir = -Vector3.yAxis * finalConfig.EscalarFloorRayDistance
	local floorProbeUpOffset = finalConfig.EscalarFloorProbeUpOffset or 1.1
	local floorProbeOffsets = finalConfig.EscalarFloorProbeOffsets or { 0.0, 0.3, 0.7 }
	local floorResult = nil
	local floorRayDebug = {
		Probes = {},
	}

	for _, forwardOffset in ipairs(floorProbeOffsets) do
		local floorRayOrigin = currentEdgePos
			+ Vector3.yAxis * floorProbeUpOffset
			+ look * forwardOffset
		local probeResult = Workspace:Raycast(floorRayOrigin, floorRayDir, rayParams)

		table.insert(floorRayDebug.Probes, {
			Origin = floorRayOrigin,
			HitPosition = probeResult and probeResult.Position or (floorRayOrigin + floorRayDir),
			Hit = probeResult ~= nil,
		})

		if probeResult then
			floorResult = probeResult
			break
		end
	end

	local firstProbe = floorRayDebug.Probes[1]
	Debug.Verbose("  FloorCheck: hit=", floorResult ~= nil, "| origin=", firstProbe and firstProbe.Origin or "nil")

	if not clear then
		Debug.Verbose("  RESULTADO: NoClearanceOnTop | Blocker:", blocker and blocker.Name or "nil")
		return {
			CanEscalar = false,
			Reason = "NoClearanceOnTop",
			Blocker = blocker,
			ClearanceCFrame = cf,
			ClearanceSize = clearanceSize,
			FloorRayDebug = floorRayDebug,
		}
	end

	-- Verificar se tem CHÃO para ficar em pé
	if not floorResult then
		Debug.Verbose("  RESULTADO: NoFloorOnTop")
		return {
			CanEscalar = false,
			Reason = "NoFloorOnTop",
			ClearanceCFrame = cf,
			ClearanceSize = clearanceSize,
			FloorRayDebug = floorRayDebug,
		}
	end

	Debug.Verbose("  RESULTADO: CanEscalar=true | PosFinal:", posFinal)
	return {
		CanEscalar = true,
		PosFinal = posFinal,
		EdgePosition = currentEdgePos,
		Normal = currentNormal,
		ClearanceCFrame = cf,
		ClearanceSize = clearanceSize,
		FloorRayDebug = floorRayDebug,
	}
end

return Analisador

