--!nonstrict

--[[
    Script: Popper.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/PlayerModule/CameraModule/ZoomController
    Responsabilidade: Calcula recuo de zoom para impedir colisao da camera com o mundo.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao implementa regras de gameplay do projeto; apenas apoia camera, controle e compatibilidade do jogador.
    Funcoes principais: getTotalTransparency, eraseFromEnd, updateProjection, refreshIgnoreList, playerAdded, characterAdded
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraBypass = require(
	ReplicatedStorage:WaitForChild("Jogador"):WaitForChild("Camera"):WaitForChild("Estado"):WaitForChild("BypassCamera")
)

local CommonUtils = script.Parent.Parent.Parent:WaitForChild("CommonUtils")
local FlagUtil = require(CommonUtils:WaitForChild("FlagUtil"))
local CameraWrapper = require(CommonUtils:WaitForChild("CameraWrapper"))
local ConnectionUtil = require(CommonUtils:WaitForChild("ConnectionUtil"))

local FFlagUserRaycastUpdateAPI = FlagUtil.getUserFlag("UserRaycastUpdateAPI")
local FFlagUserCurrentCameraUpdate = FlagUtil.getUserFlag("UserCurrentCameraUpdate2")
local FFlagUserPlayerConnectionMemoryLeak = FlagUtil.getUserFlag("UserPlayerConnectionMemoryLeak")

local cameraWrapper = if FFlagUserCurrentCameraUpdate then CameraWrapper.new() else nil
local camera = if FFlagUserCurrentCameraUpdate then nil else workspace.CurrentCamera

if FFlagUserCurrentCameraUpdate then
	cameraWrapper:Enable()
end

local min = math.min
local tan = math.tan
local rad = math.rad
local inf = math.huge

local excludeParams = RaycastParams.new()
excludeParams.IgnoreWater = true
excludeParams.FilterType = Enum.RaycastFilterType.Exclude

local includeParams = RaycastParams.new()
includeParams.IgnoreWater = true
includeParams.FilterType = Enum.RaycastFilterType.Include

local connectionUtil = if FFlagUserPlayerConnectionMemoryLeak then ConnectionUtil.new() else nil

local function getTotalTransparency(part)
	return 1 - (1 - part.Transparency) * (1 - part.LocalTransparencyModifier)
end

local function eraseFromEnd(t, toSize)
	for i = #t, toSize + 1, -1 do
		t[i] = nil
	end
end

local nearPlaneZ, projX, projY
if FFlagUserCurrentCameraUpdate then
	do
		local function updateProjection()
			assert(cameraWrapper, "cameraWrapper is required")
			local currentCamera = cameraWrapper:getCamera()
			local fov = rad(currentCamera.FieldOfView)
			local view = currentCamera.ViewportSize
			local ar = view.X / view.Y

			projY = 2 * tan(fov / 2)
			projX = ar * projY
		end

		cameraWrapper:Connect("FieldOfView", updateProjection)
		cameraWrapper:Connect("ViewportSize", updateProjection)

		updateProjection()

		nearPlaneZ = cameraWrapper:getCamera().NearPlaneZ
		cameraWrapper:Connect("NearPlaneZ", function()
			nearPlaneZ = cameraWrapper:getCamera().NearPlaneZ
		end)
	end
else
	do
		local function updateProjection()
			local fov = rad(camera.FieldOfView)
			local view = camera.ViewportSize
			local ar = view.X / view.Y
			projY = 2 * tan(fov / 2)
			projX = ar * projY
		end

		camera:GetPropertyChangedSignal("FieldOfView"):Connect(updateProjection)
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateProjection)

		updateProjection()

		nearPlaneZ = camera.NearPlaneZ
		camera:GetPropertyChangedSignal("NearPlaneZ"):Connect(function()
			nearPlaneZ = camera.NearPlaneZ
		end)
	end
end

local excludeList = {}
do
	local charMap = {}

	local function refreshIgnoreList()
		local n = 1
		excludeList = {}
		for _, character in pairs(charMap) do
			excludeList[n] = character
			n = n + 1
		end
	end

	local function playerAdded(player)
		local function characterAdded(character)
			charMap[player] = character
			refreshIgnoreList()
		end
		local function characterRemoving()
			charMap[player] = nil
			refreshIgnoreList()
		end

		if FFlagUserPlayerConnectionMemoryLeak then
			connectionUtil:trackConnection(
				`{player.UserId}CharacterAdded`,
				player.CharacterAdded:Connect(characterAdded)
			)
			connectionUtil:trackConnection(
				`{player.UserId}CharacterRemoving`,
				player.CharacterRemoving:Connect(characterRemoving)
			)
		else
			player.CharacterAdded:Connect(characterAdded)
			player.CharacterRemoving:Connect(characterRemoving)
		end

		if player.Character then
			characterAdded(player.Character)
		end
	end

	local function playerRemoving(player)
		charMap[player] = nil
		refreshIgnoreList()

		if FFlagUserPlayerConnectionMemoryLeak then
			connectionUtil:disconnect(`{player.UserId}CharacterAdded`)
			connectionUtil:disconnect(`{player.UserId}CharacterRemoving`)
		end
	end

	Players.PlayerAdded:Connect(playerAdded)
	Players.PlayerRemoving:Connect(playerRemoving)

	for _, player in ipairs(Players:GetPlayers()) do
		playerAdded(player)
	end
	refreshIgnoreList()
end

local subjectRoot
local subjectPart

if FFlagUserCurrentCameraUpdate then
	cameraWrapper:Connect("CameraSubject", function()
		local subject = cameraWrapper:getCamera().CameraSubject
		if subject and subject:IsA("Humanoid") then
			subjectPart = subject.RootPart
		elseif subject and subject:IsA("BasePart") then
			subjectPart = subject
		else
			subjectPart = nil
		end
	end)
else
	camera:GetPropertyChangedSignal("CameraSubject"):Connect(function()
		local subject = camera.CameraSubject
		if subject:IsA("Humanoid") then
			subjectPart = subject.RootPart
		elseif subject:IsA("BasePart") then
			subjectPart = subject
		else
			subjectPart = nil
		end
	end)
end

local function canOcclude(part)

	return getTotalTransparency(part) < 0.25
		and part.CanCollide
		and subjectRoot ~= (part:GetRootPart() or part)
		and not part:IsA("TrussPart")
		and not CameraBypass.has(part)
end

local SCAN_SAMPLE_OFFSETS = {
	Vector2.new(0.4, 0.0),
	Vector2.new(-0.4, 0.0),
	Vector2.new(0.0, -0.4),
	Vector2.new(0.0, 0.4),
	Vector2.new(0.0, 0.2),
}

local QUERY_POINT_CAST_LIMIT = 64

local function getCollisionPoint(origin, dir)
	if FFlagUserRaycastUpdateAPI then
		excludeParams.FilterDescendantsInstances = excludeList
		repeat
			local raycastResult = workspace:Raycast(origin, dir, excludeParams)

			if raycastResult then
				if raycastResult.Instance.CanCollide and not CameraBypass.has(raycastResult.Instance) then
					return raycastResult.Position, true
				end
				excludeParams:AddToFilter(raycastResult.Instance)
			end
		until not raycastResult
	else
		local originalSize = #excludeList
		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.IgnoreWater = true

		repeat
			raycastParams.FilterDescendantsInstances = excludeList
			local entryResult = workspace:Raycast(origin, dir, raycastParams)
			local hitPart = entryResult and entryResult.Instance
			local hitPoint = entryResult and entryResult.Position

			if hitPart then
				if hitPart.CanCollide and not CameraBypass.has(hitPart) then
					eraseFromEnd(excludeList, originalSize)
					return hitPoint, true
				end
				excludeList[#excludeList + 1] = hitPart
			end
		until not hitPart

		eraseFromEnd(excludeList, originalSize)
	end

	return origin + dir, false
end

local function queryPoint(origin, unitDir, dist, lastPos)
	debug.profilebegin("queryPoint")

	local originalSize = #excludeList

	dist = dist + nearPlaneZ
	local target = origin + unitDir * dist

	local softLimit = inf
	local hardLimit = inf
	local movingOrigin = origin

	local numPierced = 0

	if FFlagUserRaycastUpdateAPI then
		excludeParams.FilterDescendantsInstances = excludeList
		repeat
			local enterRaycastResult = workspace:Raycast(movingOrigin, target - movingOrigin, excludeParams)

			if not enterRaycastResult then
				break
			end

			numPierced += 1

			local entryInstance, entryPosition = enterRaycastResult.Instance, enterRaycastResult.Position
			local lim = (entryPosition - origin).Magnitude

			if numPierced >= QUERY_POINT_CAST_LIMIT then
				hardLimit = lim
			elseif canOcclude(entryInstance) then
				includeParams.FilterDescendantsInstances = { entryInstance }

				local exitRaycastResult = workspace:Raycast(target, entryPosition - target, includeParams)
				if exitRaycastResult then
					local promote = if lastPos
						then (workspace:Raycast(lastPos, target - lastPos, includeParams) or workspace:Raycast(
							target,
							lastPos - target,
							includeParams
						))
						else false

					if promote then

						hardLimit = lim
					elseif dist < softLimit then

						softLimit = lim
					end
				else

					hardLimit = lim
				end
			end

			excludeParams:AddToFilter(entryInstance)
			movingOrigin = entryPosition - unitDir * 1e-3
		until hardLimit < inf or not entryInstance
	else
		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.IgnoreWater = true

		local raycastParamsWl = RaycastParams.new()
		raycastParamsWl.FilterType = Enum.RaycastFilterType.Include
		raycastParamsWl.IgnoreWater = true

		repeat
			raycastParams.FilterDescendantsInstances = excludeList
			local entryResult = workspace:Raycast(movingOrigin, target - movingOrigin, raycastParams)
			local entryPart = entryResult and entryResult.Instance
			local entryPos = entryResult and entryResult.Position
			numPierced += 1

			if entryPart then

				local earlyAbort = numPierced >= QUERY_POINT_CAST_LIMIT

				if canOcclude(entryPart) or earlyAbort then
					raycastParamsWl.FilterDescendantsInstances = { entryPart }
					local exitResult = workspace:Raycast(target, entryPos - target, raycastParamsWl)
					local exitPart = exitResult and exitResult.Instance

					local lim = (entryPos - origin).Magnitude

					if exitPart and not earlyAbort then
						local promote = false
						if lastPos then
							local r1 = workspace:Raycast(lastPos, target - lastPos, raycastParamsWl)
							local r2 = workspace:Raycast(target, lastPos - target, raycastParamsWl)
							promote = (r1 and r1.Instance ~= nil) or (r2 and r2.Instance ~= nil)
						end

						if promote then

							hardLimit = lim
						elseif dist < softLimit then

							softLimit = lim
						end
					else

						hardLimit = lim
					end
				end

				excludeList[#excludeList + 1] = entryPart
				movingOrigin = entryPos - unitDir * 1e-3
			end
		until hardLimit < inf or not entryPart

		eraseFromEnd(excludeList, originalSize)
	end

	debug.profileend()
	return softLimit - nearPlaneZ, hardLimit - nearPlaneZ
end

local function queryViewport(focus, dist)
	debug.profilebegin("queryViewport")

	local fP = focus.Position
	local fX = focus.rightVector
	local fY = focus.upVector
	local fZ = -focus.lookVector

	camera = if FFlagUserCurrentCameraUpdate then cameraWrapper:getCamera() else camera

	local viewport = camera.ViewportSize

	local hardBoxLimit = inf
	local softBoxLimit = inf

	for viewX = 0, 1 do
		local worldX = fX * ((viewX - 0.5) * projX)

		for viewY = 0, 1 do
			local worldY = fY * ((viewY - 0.5) * projY)

			local origin = fP + nearPlaneZ * (worldX + worldY)
			local lastPos = camera:ViewportPointToRay(viewport.x * viewX, viewport.y * viewY).Origin

			local softPointLimit, hardPointLimit = queryPoint(origin, fZ, dist, lastPos)

			if hardPointLimit < hardBoxLimit then
				hardBoxLimit = hardPointLimit
			end
			if softPointLimit < softBoxLimit then
				softBoxLimit = softPointLimit
			end
		end
	end
	debug.profileend()

	return softBoxLimit, hardBoxLimit
end

local function testPromotion(focus, dist, focusExtrapolation)
	debug.profilebegin("testPromotion")

	local fP = focus.p
	local fX = focus.rightVector
	local fY = focus.upVector
	local fZ = -focus.lookVector

	do

		debug.profilebegin("extrapolate")

		local SAMPLE_DT = 0.0625
		local SAMPLE_MAX_T = 1.25

		local maxDist = (getCollisionPoint(fP, focusExtrapolation.posVelocity * SAMPLE_MAX_T) - fP).Magnitude

		local combinedSpeed = focusExtrapolation.posVelocity.magnitude

		for dt = 0, min(SAMPLE_MAX_T, focusExtrapolation.rotVelocity.magnitude + maxDist / combinedSpeed), SAMPLE_DT do
			local cfDt = focusExtrapolation.extrapolate(dt)

			if queryPoint(cfDt.p, -cfDt.lookVector, dist) >= dist then
				return false
			end
		end

		debug.profileend()
	end

	do

		debug.profilebegin("testOffsets")

		for _, offset in ipairs(SCAN_SAMPLE_OFFSETS) do
			local scaledOffset = offset
			local pos = getCollisionPoint(fP, fX * scaledOffset.x + fY * scaledOffset.y)
			if queryPoint(pos, (fP + fZ * dist - pos).Unit, dist) == inf then
				return false
			end
		end

		debug.profileend()
	end

	debug.profileend()
	return true
end

local function Popper(focus, targetDist, focusExtrapolation)
	debug.profilebegin("popper")

	subjectRoot = subjectPart and subjectPart:GetRootPart() or subjectPart

	local dist = targetDist
	local soft, hard = queryViewport(focus, targetDist)
	if hard < dist then
		dist = hard
	end
	if soft < dist and testPromotion(focus, targetDist, focusExtrapolation) then
		dist = soft
	end

	subjectRoot = nil

	debug.profileend()
	return dist
end

return Popper
