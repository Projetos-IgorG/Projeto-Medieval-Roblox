local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local EMPTY_ARRAY = table.freeze({})
local ORDERED_OFFSETS_CACHE_KEY = "__ParkourOrderedVerticalOffsets"

local Utilidades = {}

-- ══════════════════════════════════════
-- Funções de Vetores / Eixos
-- ══════════════════════════════════════

function Utilidades.getAxisValue(v, axis)
	if axis == "X" then
		return v.X
	elseif axis == "Y" then
		return v.Y
	else
		return v.Z
	end
end

function Utilidades.vectorFromTable(t)
	return Vector3.new(t.X, t.Y, t.Z)
end

function Utilidades.dominantAxis(v)
	local ax, ay, az = math.abs(v.X), math.abs(v.Y), math.abs(v.Z)

	if ax >= ay and ax >= az then
		return "X", v.X >= 0 and 1 or -1
	elseif ay >= ax and ay >= az then
		return "Y", v.Y >= 0 and 1 or -1
	else
		return "Z", v.Z >= 0 and 1 or -1
	end
end

function Utilidades.getFaceAxes(normalLocal)
	local faceAxis, faceSign = Utilidades.dominantAxis(normalLocal)

	if faceAxis == "X" then
		return faceAxis, faceSign, "Y", "Z"
	elseif faceAxis == "Y" then
		return faceAxis, faceSign, "X", "Z"
	else
		return faceAxis, faceSign, "X", "Y"
	end
end

-- ══════════════════════════════════════
-- Funções de Ordenação / Offsets
-- ══════════════════════════════════════

function Utilidades.getOrderedVerticalOffsets(config)
	if config and config[ORDERED_OFFSETS_CACHE_KEY] then
		return config[ORDERED_OFFSETS_CACHE_KEY]
	end

	local offsets = table.clone(config.VerticalOffsets or {0})
	table.sort(offsets, function(a, b)
		return a > b
	end)

	if config then
		config[ORDERED_OFFSETS_CACHE_KEY] = offsets
	end

	return offsets
end

-- ══════════════════════════════════════
-- Tags / Hierarquia
-- ══════════════════════════════════════

function Utilidades.hasTagDeep(instance, tag)
	local current = instance

	while current do
		if CollectionService:HasTag(current, tag) then
			return true
		end
		current = current.Parent
	end

	return false
end

-- ══════════════════════════════════════
-- Character
-- ══════════════════════════════════════

function Utilidades.getCharacterParts(character)
	if not character then
		return nil, nil
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil, nil
	end

	local head = character:FindFirstChild("Head")
	return hrp, head
end

-- ══════════════════════════════════════
-- Raycast / Overlap Params
-- ══════════════════════════════════════

function Utilidades.createRaycastParams(ignoreList)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignoreList or EMPTY_ARRAY
	return params
end

function Utilidades.createRaycastParamsForCharacter(character, extraIgnore)
	local ignoreCount = extraIgnore and #extraIgnore or 0
	local ignoreList = table.create(ignoreCount + 1)
	ignoreList[1] = character

	for i = 1, ignoreCount do
		ignoreList[i + 1] = extraIgnore[i]
	end

	return Utilidades.createRaycastParams(ignoreList)
end

function Utilidades.createOverlapParams(ignoreList, maxParts)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignoreList or EMPTY_ARRAY
	params.MaxParts = maxParts or 0
	params.RespectCanCollide = false
	return params
end

-- ══════════════════════════════════════
-- Geometria de Superfície
-- ══════════════════════════════════════

function Utilidades.getSurfaceFrame(position, normal)
	local lookAtPos = position - normal
	local cf = CFrame.lookAt(position, lookAtPos, Vector3.yAxis)

	if math.abs(cf.LookVector:Dot(Vector3.yAxis)) > 0.98 then
		cf = CFrame.lookAt(position, lookAtPos, Vector3.xAxis)
	end

	return cf
end

function Utilidades.firstBlockingPartInBox(cframe, size, ignoreList, shouldIgnorePart)
	local parts = Workspace:GetPartBoundsInBox(
		cframe,
		size,
		Utilidades.createOverlapParams(ignoreList, 0)
	)

	for _, part in ipairs(parts) do
		if not shouldIgnorePart or not shouldIgnorePart(part) then
			return false, part
		end
	end

	return true, nil
end

function Utilidades.isIgnorablePart(part, minHeight)
	if not part:IsA("BasePart") then
		return false
	end

	-- Peças muito pequenas em altura (decoração, grama, detalhes)
	if part.Size.Y < (minHeight or 0.5) then
		return true
	end

	return false
end

return Utilidades
