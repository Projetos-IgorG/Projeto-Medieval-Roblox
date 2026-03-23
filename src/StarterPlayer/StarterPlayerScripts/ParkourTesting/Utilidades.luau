local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

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
	local offsets = table.clone(config.VerticalOffsets or {0})
	table.sort(offsets, function(a, b)
		return a > b
	end)
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
	params.FilterDescendantsInstances = ignoreList
	return params
end

function Utilidades.createOverlapParams(ignoreList, maxParts)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignoreList
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

	-- Material de grama sempre ignora
	if part.Material == Enum.Material.Grass then
		return true
	end

	-- Peças muito pequenas em altura (decoração, grama, detalhes)
	if part.Size.Y < (minHeight or 0.5) then
		return true
	end

	return false
end

return Utilidades
