--[[
	Módulo: AcaoLateral
	Pai: Analisador (Parkour)
	Responsabilidade: a partir de uma borda agarrada, encontrar movimento lateral
		(shimmy) para esquerda/direita, incluindo curvas internas/externas e o
		fallback de LateralSalto. Preserva integralmente a lógica original.

	Ponto de entrada: resolve `finalConfig` uma vez e passa adiante.
]]

local Workspace = game:GetService("Workspace")

local Configs = require(script.Parent.Parent.Configuracoes.ConfigParkour)
local Utilidades = require(script.Parent.Parent.Utilidades)
local Debug = require(script.Parent.Parent.Depuracao.DepuracaoParkour)
local Geometria = require(script.Parent.Geometria)
local Espacos = require(script.Parent.Espacos)
local Suporte = require(script.Parent.Suporte)

local AcaoLateral = {}

local LATERAL_SAMPLE_MULTIPLIERS = table.freeze({ 0.7, 1.2 })
local NAO_AGARRAVEL = Configs.Tags.NAO_AGARRAVEL

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

function AcaoLateral.CheckLateral(character, currentEdgePos, currentNormal, direcao, config, currentPart)
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

	local lateralDebug = Configs.DebugEnabled
			and {
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
		or nil

	Debug.Verbose("═══ CheckLateral (Area) ═══")
	Debug.Verbose("  Direction:", direcao, "| EdgePos:", currentEdgePos, "| Normal:", currentNormal)
	Debug.Verbose("  QueryCenter:", areaCenter, "| AreaSize:", areaSize)

	if not Geometria.isWallLikeNormal(currentNormal, finalConfig) then
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
	local lateralSaltoTopEdgeTolerance =
		math.max(finalConfig.LateralSaltoTopEdgeTolerance or lateralSaltoMaxVertical, lateralTopEdgeTolerance)
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
	local sideClearanceDistance =
		math.max(finalConfig.LateralPathSideDistance or (finalConfig.LateralTargetSideOffset or 3.2), 0.5)
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
		if not lateralDebug then
			return
		end
		lateralDebug.RejectionCounts[reason] = (lateralDebug.RejectionCounts[reason] or 0) + 1
	end

	local function recordRejected(part, topEdge, reason, extra)
		if not lateralDebug then
			return
		end
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
		if not lateralDebug then
			return
		end
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
		local clear, blocker = Utilidades.firstBlockingPartInBox(probeCf, probeSize, ignoreList, function(part)
			if Utilidades.isParkourIgnoredPart(part, finalConfig.MinPartHeight) then
				return true
			end

			if targetPart and isSameAssemblyPart(part, targetPart) then
				return true
			end

			return false
		end)

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

		local rayParams = Utilidades.createRaycastParams(ignoreList)
		local rayOrigin = hrp.Position + Vector3.yAxis * externalPathRayUpOffset
		local targetNormalUnit = targetNormal.Unit
		local rayTarget = targetEdgePos
			+ targetNormalUnit * externalPathRayNormalOffset
			+ Vector3.yAxis * externalPathRayUpOffset
		local rayDir = rayTarget - rayOrigin
		if rayDir.Magnitude < 0.05 then
			return true, nil
		end

		local rayResult = Workspace:Raycast(rayOrigin, rayDir, rayParams)
		local hitIsTargetPart = targetPart ~= nil
			and rayResult ~= nil
			and isSameAssemblyPart(rayResult.Instance, targetPart)
		local isCorrectFace = hitIsTargetPart and rayResult.Normal:Dot(targetNormalUnit) > 0.5
		local isClear = rayResult == nil or isCorrectFace
		if lateralDebug then
			table.insert(lateralDebug.PathClearanceRays, {
				Origin = rayOrigin,
				HitPosition = rayResult and rayResult.Position or rayTarget,
				Hit = rayResult ~= nil,
				Clear = isClear,
				HitIsTargetPart = hitIsTargetPart,
				IsCorrectFace = isCorrectFace,
			})
		end

		if not rayResult then
			return true, nil
		end

		if hitIsTargetPart then
			if isCorrectFace then
				return true, nil
			end

			return false, rayResult.Instance
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

		if not Geometria.isWallLikeNormal(built.Normal, finalConfig) then
			recordRejected(part, topEdge, "NotWallLike", {
				NormalY = built.Normal.Y,
			})
			return
		end

		local delta = topEdge - currentEdgePos
		local horizontalDistance = Vector3.new(delta.X, 0, delta.Z).Magnitude
		local verticalDelta = topEdge.Y - currentEdgePos.Y
		local normalDot = hitWallNormal:Dot(currentWallNormal)

		local isInternalCornerCandidate = allowCorner
			and isCornerProbe
			and part == currentPart
			and normalDot >= cornerMinDot
		local isExternalCornerCandidate = allowExternalCorner
			and currentPart ~= nil
			and part ~= currentPart
			and normalDot >= externalCornerMinDot
			and normalDot < (finalConfig.LateralNormalMinDot or 0.5)
		local isCornerCandidate = isInternalCornerCandidate or isExternalCornerCandidate
		local cornerType = isExternalCornerCandidate and "Externa"
			or (isInternalCornerCandidate and "Interna" or "Nenhuma")

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

		local hasTopClearance, hasFrontClearance =
			Espacos.hasBothClearances(character, part, edgePos, hitWallNormal, finalConfig)
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
				"Part:",
				cand.PartName,
				"| Side:",
				fmt2(cand.SideDistance),
				"| SideRaw:",
				fmt2(cand.SideDistanceRaw),
				"| Clamped:",
				boolStr(cand.SideDistanceClamped),
				"| Horiz:",
				fmt2(cand.HorizontalDistance),
				"| Vert:",
				fmt2(cand.VertDelta),
				"| Depth:",
				fmt2(cand.DepthDistance),
				"| Dot:",
				fmt2(cand.NormalDot),
				"| Curva:",
				cand.CornerType,
				"| OtherPart:",
				boolStr(cand.IsOtherPart)
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
		local idleMode, legHit, legProbeRaysDebug = Suporte.ResolveIdleMode({
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

	local parts =
		Geometria.collectValidPartsInBox(areaCFrame, areaSize, { character }, finalConfig.MinPartHeight, NAO_AGARRAVEL)
	local oppositeSideDir = -sideDir
	for _, part in ipairs(parts) do
		for _, multiplier in ipairs(LATERAL_SAMPLE_MULTIPLIERS) do
			local samplePoint = currentEdgePos
				+ currentNormal.Unit * probeOffset
				+ sideDir * (sampleSideOffset * multiplier)

			local castCurrent = Geometria.buildCastDataFromPartPoint(character, part, samplePoint, currentWallNormal)
			local builtCurrent = Geometria.buildResultFromCast(castCurrent, finalConfig)
			if builtCurrent then
				evaluateBuiltCandidate(part, builtCurrent, false)
			end

			local castSide = Geometria.buildCastDataFromPartPoint(character, part, samplePoint, sideDir)
			local builtSide = Geometria.buildResultFromCast(castSide, finalConfig)
			if builtSide then
				evaluateBuiltCandidate(part, builtSide, false)
			end

			local castOppSide = Geometria.buildCastDataFromPartPoint(character, part, samplePoint, oppositeSideDir)
			local builtOppSide = Geometria.buildResultFromCast(castOppSide, finalConfig)
			if builtOppSide then
				evaluateBuiltCandidate(part, builtOppSide, false)
			end

			local castAuto = Geometria.buildCastDataFromPartPoint(character, part, samplePoint)
			local builtAuto = Geometria.buildResultFromCast(castAuto, finalConfig)
			if builtAuto then
				evaluateBuiltCandidate(part, builtAuto, false)
			end
		end

		if allowCorner and currentPart and part == currentPart then
			local cornerSamplePoint = currentEdgePos
				+ currentNormal.Unit * probeOffset
				+ sideDir * (sampleSideOffset + 0.8)
			local cornerCastData = Geometria.buildCastDataFromPartPoint(character, part, cornerSamplePoint, sideDir)
			local cornerBuilt = Geometria.buildResultFromCast(cornerCastData, finalConfig)
			if cornerBuilt then
				evaluateBuiltCandidate(part, cornerBuilt, true)
			end
		end
	end

	local rejectedCount = 0
	if lateralDebug then
		rejectedCount = #lateralDebug.CandidatePoints - #candidates - #jumpCandidates
	end

	Debug.Verbose(
		"  Summary: PartsInBox:",
		#parts,
		"| AcceptedLateral:",
		#candidates,
		"| AcceptedLateralSalto:",
		#jumpCandidates,
		"| Rejected:",
		rejectedCount
	)
	for reason, count in pairs(lateralDebug and lateralDebug.RejectionCounts or {}) do
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
				"| Dist:",
				fmt2(jumpBest.SideDistance),
				"| SideRaw:",
				fmt2(jumpBest.SideDistanceRaw),
				"| Clamped:",
				boolStr(jumpBest.SideDistanceClamped),
				"| Travel:",
				fmt2(jumpBest.HorizontalDistance),
				"| Curva:",
				jumpBest.CornerType,
				"| Part:",
				jumpBest.PartName
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
			curvaIdleMode, curvaLegHit, curvaLegProbeRaysDebug = Suporte.ResolveIdleMode({
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
			"| CurvaPart:",
			best.PartName,
			"| SaltoPart:",
			jumpBest.PartName,
			"| CurvaDist:",
			fmt2(best.SideDistance),
			"| SaltoDist:",
			fmt2(jumpBest.SideDistance)
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

	local idleMode, legHit, legProbeRaysDebug = Suporte.ResolveIdleMode({
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
		"| Estado:",
		estadoLateral,
		"| Dist:",
		fmt2(best.SideDistance),
		"| SideRaw:",
		fmt2(best.SideDistanceRaw),
		"| Clamped:",
		boolStr(best.SideDistanceClamped),
		"| Curva:",
		best.CornerType,
		"| Part:",
		best.PartName
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

return AcaoLateral
