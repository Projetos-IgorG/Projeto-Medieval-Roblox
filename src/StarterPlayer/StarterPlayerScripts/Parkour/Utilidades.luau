local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local EMPTY_ARRAY = table.freeze({})

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

-- ══════════════════════════════════════
-- Intenção Direcional (Input XZ)
-- Extraído de init.client
-- ══════════════════════════════════════

function Utilidades.GetIntencaoDirecional(humanoid, hrp, config)
	local moveDir = humanoid.MoveDirection
	local deadzone = config.DirectionInputDeadzone or 0.2
	if moveDir.Magnitude < deadzone then
		return nil
	end

	local moveFlat = Vector3.new(moveDir.X, 0, moveDir.Z)
	if moveFlat.Magnitude < deadzone then
		return nil
	end

	local useCameraBasis = config.DirectionUseCameraBasis ~= false
	local basisCFrame = hrp.CFrame
	if useCameraBasis then
		local currentCamera = Workspace.CurrentCamera
		if currentCamera then
			local camLookFlat = Vector3.new(currentCamera.CFrame.LookVector.X, 0, currentCamera.CFrame.LookVector.Z)
			if camLookFlat.Magnitude > 0.001 then
				basisCFrame = CFrame.lookAt(Vector3.zero, camLookFlat.Unit)
			end
		end
	end

	local lookFlat = Vector3.new(basisCFrame.LookVector.X, 0, basisCFrame.LookVector.Z)
	if lookFlat.Magnitude <= 0.001 then
		lookFlat = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
		if lookFlat.Magnitude <= 0.001 then
			return nil
		end
	end
	lookFlat = lookFlat.Unit

	local rightFlat = Vector3.new(basisCFrame.RightVector.X, 0, basisCFrame.RightVector.Z)
	if rightFlat.Magnitude <= 0.001 then
		rightFlat = Vector3.new(hrp.CFrame.RightVector.X, 0, hrp.CFrame.RightVector.Z)
		if rightFlat.Magnitude <= 0.001 then
			return nil
		end
	end
	rightFlat = rightFlat.Unit

	moveFlat = moveFlat.Unit

	local dotForward = lookFlat:Dot(moveFlat)
	local dotRight = rightFlat:Dot(moveFlat)
	local absForward = math.abs(dotForward)
	local absRight = math.abs(dotRight)
	local dominanceMargin = config.DirectionDominanceMargin or 0.12
	local forwardThreshold = config.DirectionForwardDotThreshold or 0.6
	local lateralThreshold = config.DirectionLateralDotThreshold or config.LateralInputDotThreshold or 0.6

	if absForward >= forwardThreshold and absForward >= (absRight + dominanceMargin) then
		if dotForward > 0 then
			return "Frente"
		end
		return "Tras"
	end

	if absRight >= lateralThreshold and absRight >= (absForward + dominanceMargin) then
		if dotRight >= 0 then
			return "Direita"
		end
		return "Esquerda"
	elseif dotRight >= lateralThreshold then
		return "Direita"
	elseif dotRight <= -lateralThreshold then
		return "Esquerda"
	end

	return nil -- ambíguo
end

return Utilidades
