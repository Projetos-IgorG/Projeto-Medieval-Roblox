--[[
	Módulo: AcaoSubir
	Pai: Analisador (Parkour)
	Responsabilidade: a partir de uma borda atual, encontrar uma superfície
		agarrável ACIMA (Subir / SubirSalto) ou, na ausência de clearance total,
		um fallback de Escalar.

	Ponto de entrada: resolve `finalConfig` uma vez e passa adiante.
]]

local Configs = require(script.Parent.Parent.Configuracoes.ConfigParkour)
local Utilidades = require(script.Parent.Parent.Utilidades)
local Debug = require(script.Parent.Parent.Depuracao.DepuracaoParkour)
local Geometria = require(script.Parent.Geometria)
local Espacos = require(script.Parent.Espacos)
local Suporte = require(script.Parent.Suporte)
local Escalada = require(script.Parent.Escalada)

local AcaoSubir = {}

function AcaoSubir.CheckSubir(character, currentEdgePos, currentNormal, config)
	local finalConfig = Configs.mergeConfig(config)
	local hrp = Utilidades.getCharacterParts(character)
	if not hrp then
		return nil
	end

	if not Geometria.isWallLikeNormal(currentNormal, finalConfig) then
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
	local areaCenter = currentEdgePos + flatNormal * (probeOffset - areaSize.Z * 0.5) + Vector3.yAxis * areaUpOffset
	local areaCFrame = Utilidades.getSurfaceFrame(areaCenter, flatNormal)

	local subirDebug = Configs.DebugEnabled
			and {
				QueryBoxCFrame = areaCFrame,
				QueryBoxSize = areaSize,
				CandidatePoints = {},
				EscalarChecks = {},
			}
		or nil

	Debug.Verbose("═══ CheckSubir (Area) ═══")
	Debug.Verbose("  EdgePos:", currentEdgePos, "| Normal:", currentNormal)
	Debug.Verbose("  QueryCenter:", areaCenter, "| AreaSize:", areaSize)

	local parts = Geometria.collectValidPartsInBox(
		areaCFrame,
		areaSize,
		{ character },
		finalConfig.MinPartHeight,
		Configs.Tags.NAO_AGARRAVEL
	)
	local candidates = table.create(#parts)
	local minVerticalDelta = finalConfig.SubirMinVerticalDelta or 0.5
	local samplePointBase = currentEdgePos + currentNormal.Unit * probeOffset
	local maxEscalarVerticalDistance = finalConfig.EscalarMaxVerticalDistance or finalConfig.SubirMaxAltura or 6.0
	local wallForwardXZ = Geometria.getHorizontalUnit(-currentNormal)
	local maxHorizontalDistance = math.max(finalConfig.SubirMaxHorizontalDistance or 5.5, 0.1)
	local maxProfundidadeSubir = math.max(finalConfig.SubirMaxProfundidade or 3.0, 0.1)
	local maxProfundidadeSubirSalto = math.max(finalConfig.SubirSaltoMaxProfundidade or 4.5, 0.1)

	local maxDepthDistance = math.max(maxProfundidadeSubir, maxProfundidadeSubirSalto)

	for _, part in ipairs(parts) do
		local castData = Geometria.buildCastDataFromPartPoint(character, part, samplePointBase, currentNormal)
		local built = Geometria.buildResultFromCast(castData, finalConfig)
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

		if not Geometria.isWallLikeNormal(built.Normal, finalConfig) then
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
			Debug.Verbose(
				"  Candidato rejeitado (TooFarAbove):",
				cand.Part.Name,
				"| VertDist:",
				string.format("%.1f", cand.VertDist)
			)
			continue
		end

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
			local escalarCandidate = Escalada.checkEscalarAtEdge(
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

		local hasTopClearance, hasFrontClearance =
			Espacos.hasBothClearances(character, cand.Part, cand.EdgePosition, cand.Normal, finalConfig)

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
	local idleMode, legHit, legProbeRaysDebug = Suporte.ResolveIdleMode({
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

return AcaoSubir
