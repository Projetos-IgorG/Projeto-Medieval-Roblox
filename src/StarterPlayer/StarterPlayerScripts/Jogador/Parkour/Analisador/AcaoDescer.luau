--[[
	Módulo: AcaoDescer
	Pai: Analisador (Parkour)
	Responsabilidade: a partir de uma borda atual, encontrar uma superfície
		agarrável ABAIXO (descer) dentro dos limites de altura/profundidade e com
		espaço livre.

	Ponto de entrada: resolve `finalConfig` uma vez e passa adiante.
]]

local Configs = require(script.Parent.Parent.Configuracoes.ConfigParkour)
local Utilidades = require(script.Parent.Parent.Utilidades)
local Debug = require(script.Parent.Parent.Depuracao.DepuracaoParkour)
local Geometria = require(script.Parent.Geometria)
local Espacos = require(script.Parent.Espacos)
local Suporte = require(script.Parent.Suporte)

local AcaoDescer = {}

function AcaoDescer.CheckDescer(character, currentEdgePos, currentNormal, config)
	local finalConfig = Configs.mergeConfig(config)
	local hrp = Utilidades.getCharacterParts(character)
	if not hrp then
		return nil
	end

	if not Geometria.isWallLikeNormal(currentNormal, finalConfig) then
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
	local areaCenter = currentEdgePos + flatNormal * (probeOffset - areaSize.Z * 0.5) + Vector3.yAxis * areaDownOffset
	local areaCFrame = Utilidades.getSurfaceFrame(areaCenter, flatNormal)

	Debug.Verbose("═══ CheckDescer (Area) ═══")
	Debug.Verbose("  EdgePos:", currentEdgePos, "| Normal:", currentNormal)
	Debug.Verbose("  QueryCenter:", areaCenter, "| AreaSize:", areaSize)

	local descerDebug = Configs.DebugEnabled
			and {
				QueryBoxCFrame = areaCFrame,
				QueryBoxSize = areaSize,
				CandidatePoints = {},
			}
		or nil

	local parts = Geometria.collectValidPartsInBox(
		areaCFrame,
		areaSize,
		{ character },
		finalConfig.MinPartHeight,
		Configs.Tags.NAO_AGARRAVEL
	)
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
		local castData = Geometria.buildCastDataFromPartPoint(character, part, samplePointBase, currentNormal)
		local built = Geometria.buildResultFromCast(castData, finalConfig)
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

		if not Geometria.isWallLikeNormal(built.Normal, finalConfig) then
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
			Debug.Verbose(
				"  Candidato rejeitado (TooFarBelow):",
				cand.Part.Name,
				"| VertDist:",
				string.format("%.1f", cand.VertDist)
			)
			continue
		end

		if not firstValidDistCandidate then
			firstValidDistCandidate = cand
		end

		Debug.Verbose(
			"  Testando candidato:",
			cand.Part.Name,
			"| HorizDist:",
			string.format("%.2f", cand.HorizDist),
			"| VertDist:",
			string.format("%.1f", cand.VertDist)
		)

		local hasTopClearance, hasFrontClearance =
			Espacos.hasBothClearances(character, cand.Part, cand.EdgePosition, cand.Normal, finalConfig)

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
	local idleMode, legHit, legProbeRaysDebug = Suporte.ResolveIdleMode({
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

return AcaoDescer
