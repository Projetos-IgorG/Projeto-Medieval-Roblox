--[[
	Módulo: Suporte
	Pai: Analisador (Parkour)
	Responsabilidade: decidir o modo de "idle" na borda (IdleSuporte quando há
		superfície para os pés, IdleSuspenso caso contrário), via grade de raios
		para baixo/frente a partir da borda.

	Recebe `finalConfig` já resolvido.
]]

local Workspace = game:GetService("Workspace")

local Configs = require(script.Parent.Parent.Configuracoes.ConfigParkour)
local Utilidades = require(script.Parent.Parent.Utilidades)

local Suporte = {}

-- Scratch reutilizado para a lista de ignore dos raios de perna.
local _legIgnoreBuffer = table.create(8)
local _legIgnoreLen = 0

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
	local baseLen = #baseIgnoreList
	for i = 1, baseLen do
		_legIgnoreBuffer[i] = baseIgnoreList[i]
	end
	_legIgnoreLen = baseLen

	for i = baseLen + 1, #_legIgnoreBuffer do
		_legIgnoreBuffer[i] = nil
	end
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
			Utilidades.createRaycastParams(_legIgnoreBuffer)
		)

		if not rayResult then
			break
		end

		local hitPart = rayResult.Instance
		if hitPart and hitPart:IsA("BasePart") and not Utilidades.isParkourIgnoredPart(hitPart, minPartHeight) then
			return hitPart, rayResult.Position
		end

		_legIgnoreLen += 1
		_legIgnoreBuffer[_legIgnoreLen] = hitPart

		local advance = (rayResult.Position - currentOrigin).Magnitude + 0.02
		remainingDistance = math.max(0, remainingDistance - advance)
		currentOrigin = currentOrigin + directionUnit * advance
	end

	return nil, nil
end

function Suporte.ResolveIdleMode(data, finalConfig)
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
	local baseOrigin = data.EdgePosition - Vector3.yAxis * downOffset + forward * forwardOffset

	local rayDirection = forward * rayDistance
	local minH = finalConfig.MinPartHeight
	local blocker = nil
	local hitCount = 0
	local _dbg = Configs.DebugEnabled
	local raysDebug = _dbg and {} or nil

	for _, heightOffset in ipairs(rayHeights) do
		for _, lateralOffset in ipairs(rayLateralOffsets) do
			local rayOrigin = baseOrigin + Vector3.yAxis * heightOffset + right * lateralOffset

			local hitPart, hitPosition = castLegSupportRay(rayOrigin, rayDirection, { data.Character }, minH, maxPasses)

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

	local supportDebug = _dbg
			and {
				BaseOrigin = baseOrigin,
				Distance = rayDistance,
				Direction = rayDirection,
				HitCount = hitCount,
				Rays = raysDebug,
				Clear = clear,
				Blocker = blocker,
			}
		or nil

	if not clear then
		return "IdleSuporte", blocker, supportDebug
	end

	return "IdleSuspenso", nil, supportDebug
end

return Suporte
