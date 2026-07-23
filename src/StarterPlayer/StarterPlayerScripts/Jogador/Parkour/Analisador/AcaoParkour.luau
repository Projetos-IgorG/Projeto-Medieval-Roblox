--[[
	Módulo: AcaoParkour
	Pai: Analisador (Parkour)
	Responsabilidade: fluxo principal de parkour em corrida/queda -> decide entre
		Agarrar e Vault (médio/baixo), com fallback de agarrar quando o vault não
		tem clearance e o personagem está no ar.

	Ponto de entrada: resolve `finalConfig` uma vez e passa adiante.

	Refatoração: o boilerplate de anexar debug do grid frontal (7 campos Forward*)
	foi extraído para `applyForwardDebug`, eliminando duplicação entre
	`buildActionDataFromEdge` e `buildGrabCandidateFromCast`.
]]

local Configs = require(script.Parent.Parent.Configuracoes.ConfigParkour)
local Utilidades = require(script.Parent.Parent.Utilidades)
local Debug = require(script.Parent.Parent.Depuracao.DepuracaoParkour)
local Geometria = require(script.Parent.Geometria)
local Espacos = require(script.Parent.Espacos)
local Suporte = require(script.Parent.Suporte)
local DeteccaoFrontal = require(script.Parent.DeteccaoFrontal)

local AcaoParkour = {}

local MAGENTA = Color3.fromRGB(255, 0, 255)

-- Copia os 7 campos de debug do grid frontal para o candidato (DRY).
local function applyForwardDebug(target, blockDebug)
	target.ForwardCandidatePoints = blockDebug and blockDebug.CandidatePoints or nil
	target.ForwardGridRays = blockDebug and blockDebug.GridRays or nil
	target.ForwardGridOrigin = blockDebug and blockDebug.GridOrigin or nil
	target.ForwardGridLookXZ = blockDebug and blockDebug.GridLookXZ or nil
	target.ForwardGridDistance = blockDebug and blockDebug.GridDistance or nil
	target.ForwardBoxCFrame = blockDebug and blockDebug.BoxCFrame or nil
	target.ForwardBoxSize = blockDebug and blockDebug.BoxSize or nil
end

function AcaoParkour.CheckParkour(character, config)
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
	local lookXZ = Geometria.getHorizontalUnit(look)
	if not lookXZ then
		return {
			Aprovado = false,
			Reason = "NoHorizontalLook",
		}
	end

	Debug.Verbose("═══ CheckParkour (RayGrid) ═══")
	Debug.Verbose("  HRP:", hrp.Position, "| Floor:", humanoid.FloorMaterial)

	local edgeData, blockDebug, rankedForwardCandidates =
		DeteccaoFrontal.findForwardEdgeByRayGrid(character, hrp, lookXZ, finalConfig)
	if not edgeData then
		Debug.Verbose("  RESULTADO: NoForwardHit | candidates:", blockDebug and #blockDebug.CandidatePoints or 0)
		local result = {
			Aprovado = false,
			Reason = "NoForwardHit",
		}
		applyForwardDebug(result, blockDebug)
		return result
	end

	if Utilidades.hasTagDeep(edgeData.Part, Configs.Tags.NAO_AGARRAVEL) then
		local result = {
			Aprovado = false,
			Reason = "TaggedNaoAgarravel",
			Part = edgeData.Part,
		}
		applyForwardDebug(result, blockDebug)
		return result
	end

	local rayParams = Utilidades.createRaycastParamsForCharacter(character)

	local function buildActionDataFromEdge(castData)
		local candidateData = table.clone(castData)
		candidateData.EdgePosition = candidateData.TopEdgePosition
		candidateData.Mode = "Top"

		candidateData.Origin = nil
		candidateData.HitPosition = nil
		candidateData.LookVector = lookXZ
		candidateData.HrpPosition = hrp.Position
		applyForwardDebug(candidateData, blockDebug)

		candidateData.TorsoRayDebug = DeteccaoFrontal.castRayToEdgeXZ(
			hrp.Position,
			candidateData.EdgePosition,
			finalConfig.TorsoRayOffset,
			finalConfig.ClassificationRayDistance or finalConfig.RayDistance,
			finalConfig.ClassificationRayExtraDistance,
			rayParams,
			finalConfig
		)
		candidateData.LegRayDebug = DeteccaoFrontal.castRayToEdgeXZ(
			hrp.Position,
			candidateData.EdgePosition,
			finalConfig.PernaRayOffset,
			finalConfig.ClassificationRayDistance or finalConfig.RayDistance,
			finalConfig.ClassificationRayExtraDistance,
			rayParams,
			finalConfig
		)

		candidateData.Acao, candidateData.ClassificationDebug = DeteccaoFrontal.classificarAcaoDePulo(
			candidateData.EdgePosition.Y,
			hrp.Position.Y,
			candidateData.TorsoRayDebug,
			candidateData.LegRayDebug,
			candidateData.GridHitStats,
			finalConfig
		)

		candidateData.DistanceLine = {
			PosA = hrp.Position,
			PosB = candidateData.EdgePosition,
			Color = MAGENTA,
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
		applyForwardDebug(candidateData, blockDebug)
		candidateData.Acao = "Agarrar"
		candidateData.DistanceLine = {
			PosA = hrp.Position,
			PosB = candidateData.EdgePosition,
			Color = MAGENTA,
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
			local castData = Geometria.buildCastDataFromPartPoint(character, sourceCandidate.Part, samplePoint, -lookXZ)
			local built = Geometria.buildResultFromCast(castData, finalConfig)
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
			Color = MAGENTA,
		}
		return snapshot
	end

	local data = buildActionDataFromEdge(edgeData)
	local bordaReal = data.EdgePosition
	local acao = data.Acao

	Debug.Verbose(
		"  Classificacao:",
		acao,
		"| mode:",
		data.ClassificationDebug and data.ClassificationDebug.Mode or "Unknown",
		"| highestRow:",
		data.ClassificationDebug and data.ClassificationDebug.HighestRow or "nil",
		"/",
		data.ClassificationDebug and data.ClassificationDebug.TotalRows or "nil",
		"| torsoHit:",
		data.TorsoRayDebug.Hit,
		"| legHit:",
		data.LegRayDebug.Hit,
		"| edge:",
		bordaReal
	)

	local distReal = (bordaReal - hrp.Position).Magnitude

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

			local hasTopClearance, topBlocker, topCf, topSize = Espacos.HasTopClearance(candidate, finalConfig)
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

			local hasFrontClearance, frontBlocker, frontCf, frontSize =
				Espacos.HasFrontClearance(candidate, finalConfig)
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

			local idleMode, legHit, legProbeRaysDebug = Suporte.ResolveIdleMode(candidate, finalConfig)
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
				if
					existing.Part == candidateData.Part
					and (existing.EdgePosition - candidateData.EdgePosition).Magnitude <= 0.05
				then
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
	else
		if distReal > finalConfig.MaxVaultDistance then
			data.Aprovado = false
			data.Reason = "TooFarToVault"
			Debug.Verbose("  RESULTADO:", data.Reason, "| dist:", distReal)
			return data
		end

		local hasVaultClearance, vaultBlocker, vaultCf, vaultSize, posFinal =
			Espacos.HasVaultClearance(data, finalConfig)
		data.VaultClearanceCFrame = vaultCf
		data.VaultClearanceSize = vaultSize
		data.PosFinal = posFinal

		if not hasVaultClearance then
			if humanoid.FloorMaterial == Enum.Material.Air then
				data.Acao = "Agarrar"
				Debug.Verbose("  Fallback:", acao, "-> Agarrar (NoVaultClearance)")
				return tentarAgarrar()
			end

			data.Aprovado = false
			data.Reason = "NoVaultClearance"
			data.VaultBlocker = vaultBlocker
			Debug.Verbose("  RESULTADO:", data.Reason, "| blocker:", vaultBlocker and vaultBlocker.Name or "nil")
			return data
		end

		local hasEdgeClearance, edgeBlocker, edgeCf, edgeSize = Espacos.HasVaultEdgeClearance(data, finalConfig)
		data.VaultClearanceCFrame = edgeCf
		data.VaultClearanceSize = edgeSize

		if not hasEdgeClearance then
			if humanoid.FloorMaterial == Enum.Material.Air then
				data.Acao = "Agarrar"
				Debug.Verbose("  Fallback:", acao, "-> Agarrar (NoVaultEdgeClearance)")
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

return AcaoParkour
