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
	local ignoreList = {character}

	if extraIgnore then
		for _, item in ipairs(extraIgnore) do
			table.insert(ignoreList, item)
		end
	end

	return Utilidades.createRaycastParams(ignoreList)
end

function Analisador.RaycastForward(character, distance)
	local hrp = Utilidades.getCharacterParts(character)
	if not hrp then
		return nil
	end

	local origin = hrp.Position
	local direction = hrp.CFrame.LookVector * distance
	local result = Workspace:Raycast(origin, direction, Utilidades.createRaycastParams({character}))

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
	local rayParams = Utilidades.createRaycastParams({character})
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
		return "IdleSuspenso", nil
	end

	local origin = data.EdgePosition
		- Vector3.yAxis * finalConfig.LegProbeDownOffset
		+ data.Normal.Unit * finalConfig.LegProbeStartNormalOffset

	local direction = -data.Normal.Unit * finalConfig.LegProbeDistance
	local result = Workspace:Raycast(origin, direction, Utilidades.createRaycastParams({data.Character}))

	if result and result.Instance and result.Instance:IsA("BasePart") then
		return "IdleSuporte", result
	end

	return "IdleSuspenso", nil
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

	local idleMode, legHit = Analisador.ResolveIdleMode(data, finalConfig)

	data.CanGrab = true
	data.Reason = "Ok"
	data.IdleMode = idleMode
	data.LegHit = legHit
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

	-- Posição final: acima da borda e um pouco pra frente
	local posFinal = bordaReal
		+ Vector3.yAxis * finalConfig.VaultClearanceUpOffset
		+ look * finalConfig.VaultClearanceForwardOffset

	local cf = CFrame.lookAt(posFinal, posFinal + look, Vector3.yAxis)
	local minH = finalConfig.MinPartHeight
	local clear, blocker = Utilidades.firstBlockingPartInBox(
		cf,
		finalConfig.VaultClearanceSize,
		{data.Character, data.Part},
		function(part) return Utilidades.isIgnorablePart(part, minH) end
	)

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
	local center = bordaReal + Vector3.yAxis * (finalConfig.VaultClearanceSize.Y / 2)

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
	local rayParams = Utilidades.createRaycastParams({character})

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
	if acao == "Agarrar" then
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
		local idleMode, legHit = Analisador.ResolveIdleMode(data, finalConfig)
		data.Aprovado = true
		data.Reason = "Ok"
		data.IdleMode = idleMode
		data.LegHit = legHit

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

return Analisador
