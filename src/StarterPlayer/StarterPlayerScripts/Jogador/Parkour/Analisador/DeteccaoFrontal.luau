--[[
	Módulo: DeteccaoFrontal
	Pai: Analisador (Parkour)
	Responsabilidade: encontrar a borda à frente do personagem via grade de raios
		(+ caixa de apoio), validar hits e classificar a ação de pulo
		(Agarrar / VaultMedio / VaultBaixo).

	Recebe `finalConfig` já resolvido. RaycastParams próprios e exclusivos deste
	módulo, separados dos de Geometria (evita clobber entre chamadas aninhadas).
]]

local Workspace = game:GetService("Workspace")

local Configs = require(script.Parent.Parent.Configuracoes.ConfigParkour)
local Utilidades = require(script.Parent.Parent.Utilidades)
local Debug = require(script.Parent.Parent.Depuracao.DepuracaoParkour)
local Geometria = require(script.Parent.Geometria)

local DeteccaoFrontal = {}

-- RaycastParams exclusivos deste módulo.
local includeRayParams = RaycastParams.new()
includeRayParams.FilterType = Enum.RaycastFilterType.Include
includeRayParams.IgnoreWater = true

local gridExcludeRayParams = RaycastParams.new()
gridExcludeRayParams.FilterType = Enum.RaycastFilterType.Exclude
gridExcludeRayParams.IgnoreWater = true

local function isValidForwardProbeHit(result, config)
	if not result or not result.Instance or not result.Instance:IsA("BasePart") then
		return false
	end

	local hitPart = result.Instance
	if Utilidades.isParkourIgnoredPart(hitPart, config.MinPartHeight) then
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

local function findForwardEdgeByRayGrid(character, hrp, look, finalConfig)
	local lookXZ = Geometria.getHorizontalUnit(look)
	if not lookXZ then
		return nil, nil, nil
	end

	local rows = finalConfig.ForwardRayGridRows or 7
	local cols = finalConfig.ForwardRayGridColumns or 5
	local width = finalConfig.ForwardRayGridWidth or 4.5
	local height = finalConfig.ForwardRayGridHeight or 5.5
	local upOffset = finalConfig.ForwardRayGridUpOffset or 0.8
	local distance = finalConfig.ForwardRayGridDistance or 5.25
	local maxPasses = finalConfig.ForwardRayGridMaxPasses or 3
	local minPartHeight = finalConfig.MinPartHeight or 0.6
	local borderOnly = finalConfig.ForwardRayGridBorderOnly ~= false

	local rightXZ = lookXZ:Cross(Vector3.yAxis)
	if rightXZ.Magnitude < 0.05 then
		rightXZ = Vector3.xAxis
	else
		rightXZ = rightXZ.Unit
	end

	local baseOrigin = hrp.Position + Vector3.yAxis * upOffset
	local halfWidth = width * 0.5
	local halfHeight = height * 0.5
	local rowStep = rows > 1 and height / (rows - 1) or 0
	local colStep = cols > 1 and width / (cols - 1) or 0

	local boxCenter = baseOrigin + lookXZ * (distance * 0.5)
	local boxCFrame = CFrame.lookAt(boxCenter, boxCenter + lookXZ)
	local boxSize = Vector3.new(width, height, distance)
	local boxParts =
		Geometria.collectValidPartsInBox(boxCFrame, boxSize, { character }, minPartHeight, Configs.Tags.NAO_AGARRAVEL)

	gridExcludeRayParams.FilterDescendantsInstances = { character }

	local partHits = {}
	local seen = {}
	local boxPartSet = {}
	for _, bp in ipairs(boxParts) do
		boxPartSet[bp] = true
	end
	local debugRays = Configs.DebugEnabled and {} or nil

	for row = 0, rows - 1 do
		local yOffset = -halfHeight + row * rowStep
		for col = 0, cols - 1 do
			if borderOnly and row > 0 and row < rows - 1 and col > 0 and col < cols - 1 then
				continue
			end

			local xOffset = -halfWidth + col * colStep
			local rayOrigin = baseOrigin + Vector3.yAxis * yOffset + rightXZ * xOffset

			local currentOrigin = rayOrigin
			local remainingDist = distance
			local hitSomething = false
			local rayHitPosition = nil

			for _ = 1, maxPasses do
				if remainingDist < 0.01 then
					break
				end

				local result = Workspace:Raycast(currentOrigin, lookXZ * remainingDist, gridExcludeRayParams)
				if not result then
					break
				end

				local hitPart = result.Instance
				if
					hitPart
					and hitPart:IsA("BasePart")
					and not Utilidades.isParkourIgnoredPart(hitPart, minPartHeight)
					and not Utilidades.hasTagDeep(hitPart, Configs.Tags.NAO_AGARRAVEL)
				then
					hitSomething = true
					rayHitPosition = result.Position
					local distToHRP = (result.Position - hrp.Position).Magnitude
					if not seen[hitPart] then
						seen[hitPart] = true
						partHits[hitPart] = {
							Origin = rayOrigin,
							Result = result,
							Distance = distToHRP,
							GridHitStats = {
								TotalRows = rows,
								TotalColumns = cols,
								HighestRow = row + 1,
								LowestRow = row + 1,
								HitCount = 1,
							},
						}
					elseif distToHRP < partHits[hitPart].Distance then
						partHits[hitPart].Origin = rayOrigin
						partHits[hitPart].Result = result
						partHits[hitPart].Distance = distToHRP
					end

					local stats = partHits[hitPart].GridHitStats
					stats.HighestRow = math.max(stats.HighestRow, row + 1)
					stats.LowestRow = math.min(stats.LowestRow, row + 1)
					stats.HitCount += 1
					break
				end

				local advance = (result.Position - currentOrigin).Magnitude + 0.02
				remainingDist -= advance
				currentOrigin = currentOrigin + lookXZ * advance
			end

			if debugRays then
				table.insert(debugRays, {
					Origin = rayOrigin,
					Hit = hitSomething,
					HitPosition = rayHitPosition,
				})
			end
		end
	end

	local gridBot = baseOrigin.Y - halfHeight
	for _, boxPart in ipairs(boxParts) do
		if not seen[boxPart] then
			local dirXZ = (boxPart.Position - hrp.Position) * Vector3.new(1, 0, 1)
			if dirXZ.Magnitude < 0.01 then
				dirXZ = lookXZ
			else
				dirXZ = dirXZ.Unit
			end

			local rayOrig = Vector3.new(baseOrigin.X, boxPart.Position.Y, baseOrigin.Z)
			includeRayParams.FilterDescendantsInstances = { boxPart }
			local result = Workspace:Raycast(rayOrig, dirXZ * (distance + 2), includeRayParams)
			if result and result.Instance == boxPart then
				seen[boxPart] = true
				local distToHRP = (result.Position - hrp.Position).Magnitude

				local partHalfY = boxPart.Size.Y * 0.5
				local partTop = boxPart.Position.Y + partHalfY
				local partBot = boxPart.Position.Y - partHalfY
				local topRatio = math.clamp((partTop - gridBot) / math.max(height, 0.01), 0, 1)
				local botRatio = math.clamp((partBot - gridBot) / math.max(height, 0.01), 0, 1)
				local highestRow = math.clamp(math.ceil(topRatio * rows), 1, rows)
				local lowestRow = math.clamp(math.floor(botRatio * rows) + 1, 1, rows)

				partHits[boxPart] = {
					Origin = rayOrig,
					Result = result,
					Distance = distToHRP,
					GridHitStats = {
						TotalRows = rows,
						TotalColumns = cols,
						HighestRow = highestRow,
						LowestRow = lowestRow,
						HitCount = 1,
						FromBox = true,
					},
				}

				if debugRays then
					table.insert(debugRays, {
						Origin = rayOrig,
						Hit = true,
						HitPosition = result.Position,
						FromBox = true,
					})
				end
			end
		end
	end

	local maxDist = finalConfig.ForwardObstacleMaxDistance or (distance + 0.5)
	local maxGrabReachHeight = finalConfig.MaxGrabReachHeight or 6.0

	local candidatePoints = {}
	local rankedCandidates = {}

	for part, hitData in pairs(partHits) do
		local fallbackSamplePoint = hitData.Result.Position

		local hitY = hitData.Result.Position.Y
		local sampleYOffset = finalConfig.ForwardObstacleSampleYOffset or 0
		local playerSample = Vector3.new(hrp.Position.X, hitY + sampleYOffset, hrp.Position.Z)
		local primaryCast = Geometria.buildCastDataFromPartPoint(character, part, playerSample, -lookXZ)
		if primaryCast then
			primaryCast.GridHitStats = hitData.GridHitStats
		end
		local built = primaryCast and Geometria.buildResultFromCast(primaryCast, finalConfig) or nil

		if not built then
			includeRayParams.FilterDescendantsInstances = { part }
			local alignResult = Workspace:Raycast(playerSample, lookXZ * (distance + 2), includeRayParams)
			if alignResult and alignResult.Instance == part then
				local castData = {
					Character = character,
					Part = part,
					Result = alignResult,
					Origin = playerSample,
					HitPosition = alignResult.Position,
					Normal = alignResult.Normal,
					GridHitStats = hitData.GridHitStats,
				}
				built = Geometria.buildResultFromCast(castData, finalConfig)
			end
		end

		if not built then
			local castData = {
				Character = character,
				Part = part,
				Result = hitData.Result,
				Origin = hitData.Origin,
				HitPosition = hitData.Result.Position,
				Normal = hitData.Result.Normal,
				GridHitStats = hitData.GridHitStats,
			}
			built = Geometria.buildResultFromCast(castData, finalConfig)
		end

		if not built then
			local fallbackCast = Geometria.buildCastDataFromPartPoint(character, part, fallbackSamplePoint, -lookXZ)
			if fallbackCast then
				fallbackCast.GridHitStats = hitData.GridHitStats
			end
			built = fallbackCast and Geometria.buildResultFromCast(fallbackCast, finalConfig) or nil
		end

		if not built then
			local toPlayerXZ = (hrp.Position - part.Position) * Vector3.new(1, 0, 1)
			if toPlayerXZ.Magnitude > 0.01 then
				local fallbackCast2 =
					Geometria.buildCastDataFromPartPoint(character, part, fallbackSamplePoint, toPlayerXZ.Unit)
				if fallbackCast2 then
					fallbackCast2.GridHitStats = hitData.GridHitStats
				end
				built = fallbackCast2 and Geometria.buildResultFromCast(fallbackCast2, finalConfig) or nil
			end
		end

		if not built then
			continue
		end

		local topEdge = built.TopEdgePosition
		local rawEdgeY = topEdge.Y
		local maxReachY = hrp.Position.Y + maxGrabReachHeight
		local clampedEdgeY = math.min(rawEdgeY, maxReachY)

		local edgePosition = Vector3.new(topEdge.X, clampedEdgeY, topEdge.Z)
		built.TopEdgePosition = edgePosition

		local deltaXZ = Vector3.new(edgePosition.X - hrp.Position.X, 0, edgePosition.Z - hrp.Position.Z)
		local distXZ = deltaXZ.Magnitude
		local forwardDist = deltaXZ:Dot(lookXZ)
		local lateral = (deltaXZ - lookXZ * forwardDist).Magnitude
		local accepted = distXZ > 0.05 and distXZ <= maxDist

		table.insert(candidatePoints, {
			Position = edgePosition,
			Accepted = accepted,
			DistanceXZ = distXZ,
			ForwardDistance = forwardDist,
		})

		if accepted then
			table.insert(rankedCandidates, {
				Part = part,
				CastData = built,
				ForwardDist = math.max(forwardDist, 0.01),
				LateralDist = lateral,
				DistXZ = distXZ,
				FromBox = boxPartSet[part] == true,
			})
		end
	end

	table.sort(rankedCandidates, function(a, b)
		if a.FromBox ~= b.FromBox then
			return a.FromBox
		end

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
		CandidatePoints = candidatePoints,
		GridRays = debugRays,
		GridOrigin = baseOrigin,
		GridLookXZ = lookXZ,
		GridDistance = distance,
		BoxCFrame = boxCFrame,
		BoxSize = boxSize,
	}

	return bestData, debugData, rankedCandidates
end

local function classificarAcaoDePulo(bordaY, hrpY, torsoProbe, legProbe, gridHitStats, config)
	if gridHitStats and (gridHitStats.TotalRows or 0) > 0 then
		local totalRows = math.max(gridHitStats.TotalRows or 1, 1)
		local highestRow = math.clamp(gridHitStats.HighestRow or 1, 1, totalRows)
		local highestRatio = totalRows > 1 and ((highestRow - 1) / (totalRows - 1)) or 0
		local grabStartRatio = math.clamp(config.ForwardRayGridGrabStartRatio or 0.72, 0.05, 0.98)
		local vaultMedioStartRatio =
			math.clamp(config.ForwardRayGridVaultMedioStartRatio or 0.34, 0.0, grabStartRatio - 0.05)

		if highestRatio >= grabStartRatio then
			return "Agarrar",
				{
					Mode = "RayGrid",
					HighestRow = highestRow,
					TotalRows = totalRows,
					HighestRatio = highestRatio,
				}
		elseif highestRatio >= vaultMedioStartRatio then
			return "VaultMedio",
				{
					Mode = "RayGrid",
					HighestRow = highestRow,
					TotalRows = totalRows,
					HighestRatio = highestRatio,
				}
		else
			return "VaultBaixo",
				{
					Mode = "RayGrid",
					HighestRow = highestRow,
					TotalRows = totalRows,
					HighestRatio = highestRatio,
				}
		end
	end

	local yTopoTorso = hrpY + config.TopoTorsoOffset

	if bordaY > yTopoTorso then
		return "Agarrar", { Mode = "Legacy", Reason = "EdgeAboveTorso" }
	elseif torsoProbe and torsoProbe.Hit then
		return "Agarrar", { Mode = "Legacy", Reason = "TorsoHit" }
	elseif legProbe and legProbe.Hit then
		return "VaultMedio", { Mode = "Legacy", Reason = "LegHit" }
	else
		return "VaultBaixo", { Mode = "Legacy", Reason = "NoBodyHit" }
	end
end

DeteccaoFrontal.isValidForwardProbeHit = isValidForwardProbeHit
DeteccaoFrontal.castRayToEdgeXZ = castRayToEdgeXZ
DeteccaoFrontal.findForwardEdgeByRayGrid = findForwardEdgeByRayGrid
DeteccaoFrontal.classificarAcaoDePulo = classificarAcaoDePulo

return DeteccaoFrontal
