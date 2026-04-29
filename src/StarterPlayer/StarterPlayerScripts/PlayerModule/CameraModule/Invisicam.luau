--!nonstrict

--[[
    Script: Invisicam.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/PlayerModule/CameraModule
    Responsabilidade: Controla transparencia de objetos que bloqueiam a visao da camera.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao implementa regras de gameplay do projeto; apenas apoia camera, controle e compatibilidade do jogador.
    Funcoes principais: new, Enable, GetOcclusionMode, LimbBehavior, MoveBehavior, CornerBehavior
]]
local PlayersService = game:GetService("Players")

local CommonUtils = script.Parent.Parent:WaitForChild("CommonUtils")
local FlagUtil = require(CommonUtils:WaitForChild("FlagUtil"))

local FFlagUserRaycastUpdateAPI = FlagUtil.getUserFlag("UserRaycastUpdateAPI")

local ZERO_VECTOR3 = Vector3.new(0, 0, 0)
local USE_STACKING_TRANSPARENCY = true
local TARGET_TRANSPARENCY = 0.75
local TARGET_TRANSPARENCY_PERIPHERAL = 0.5

local MODE = {

	LIMBS = 2,
	MOVEMENT = 3,
	CORNERS = 4,
	CIRCLE1 = 5,
	CIRCLE2 = 6,
	LIMBMOVE = 7,
	SMART_CIRCLE = 8,
	CHAR_OUTLINE = 9,
}

local LIMB_TRACKING_SET = {

	["Head"] = true,

	["Left Arm"] = true,
	["Right Arm"] = true,
	["Left Leg"] = true,
	["Right Leg"] = true,

	["LeftLowerArm"] = true,
	["RightLowerArm"] = true,
	["LeftUpperLeg"] = true,
	["RightUpperLeg"] = true,
}

local CORNER_FACTORS = {
	Vector3.new(1, 1, -1),
	Vector3.new(1, -1, -1),
	Vector3.new(-1, -1, -1),
	Vector3.new(-1, 1, -1),
}

local CIRCLE_CASTS = 10
local MOVE_CASTS = 3
local SMART_CIRCLE_CASTS = 24
local SMART_CIRCLE_INCREMENT = 2.0 * math.pi / SMART_CIRCLE_CASTS
local CHAR_OUTLINE_CASTS = 24

local excludeParams = RaycastParams.new()
excludeParams.FilterType = Enum.RaycastFilterType.Exclude

local includeParams = RaycastParams.new()
includeParams.FilterType = Enum.RaycastFilterType.Include

local function AssertTypes(param, ...)
	local allowedTypes = {}
	local typeString = ""
	for _, typeName in pairs({ ... }) do
		allowedTypes[typeName] = true
		typeString = typeString .. (typeString == "" and "" or " or ") .. typeName
	end
	local theType = type(param)
	assert(allowedTypes[theType], typeString .. " type expected, got: " .. theType)
end

local function Det3x3(
	a: number,
	b: number,
	c: number,
	d: number,
	e: number,
	f: number,
	g: number,
	h: number,
	i: number
): number
	return (a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g))
end

local function RayIntersection(p0: Vector3, v0: Vector3, p1: Vector3, v1: Vector3): Vector3
	local v2 = v0:Cross(v1)
	local d1 = p1.X - p0.X
	local d2 = p1.Y - p0.Y
	local d3 = p1.Z - p0.Z
	local denom = Det3x3(v0.X, -v1.X, v2.X, v0.Y, -v1.Y, v2.Y, v0.Z, -v1.Z, v2.Z)

	if denom == 0 then
		return ZERO_VECTOR3
	end

	local t0 = Det3x3(d1, -v1.X, v2.X, d2, -v1.Y, v2.Y, d3, -v1.Z, v2.Z) / denom
	local t1 = Det3x3(v0.X, d1, v2.X, v0.Y, d2, v2.Y, v0.Z, d3, v2.Z) / denom
	local s0 = p0 + t0 * v0
	local s1 = p1 + t1 * v1
	local s = s0 + 0.5 * (s1 - s0)

	if (s1 - s0).Magnitude < 0.25 then
		return s
	else
		return ZERO_VECTOR3
	end
end

local BaseOcclusion = require(script.Parent:WaitForChild("BaseOcclusion"))
local Invisicam = setmetatable({}, BaseOcclusion)
Invisicam.__index = Invisicam

function Invisicam.new()
	local self = setmetatable(BaseOcclusion.new(), Invisicam)

	self.char = nil
	self.humanoidRootPart = nil
	self.torsoPart = nil
	self.headPart = nil

	self.childAddedConn = nil
	self.childRemovedConn = nil

	self.behaviors = {}
	self.behaviors[MODE.LIMBS] = self.LimbBehavior
	self.behaviors[MODE.MOVEMENT] = self.MoveBehavior
	self.behaviors[MODE.CORNERS] = self.CornerBehavior
	self.behaviors[MODE.CIRCLE1] = self.CircleBehavior
	self.behaviors[MODE.CIRCLE2] = self.CircleBehavior
	self.behaviors[MODE.LIMBMOVE] = self.LimbMoveBehavior
	self.behaviors[MODE.SMART_CIRCLE] = self.SmartCircleBehavior
	self.behaviors[MODE.CHAR_OUTLINE] = self.CharacterOutlineBehavior

	self.mode = MODE.SMART_CIRCLE
	self.behaviorFunction = self.SmartCircleBehavior

	self.savedHits = {}
	self.trackedLimbs = {}

	self.camera = workspace.CurrentCamera

	self.enabled = false
	return self
end

function Invisicam:Enable(enable)
	self.enabled = enable

	if not enable then
		self:Cleanup()
	end
end

function Invisicam:GetOcclusionMode()
	return Enum.DevCameraOcclusionMode.Invisicam
end

function Invisicam:LimbBehavior(castPoints)
	for limb, _ in pairs(self.trackedLimbs) do
		castPoints[#castPoints + 1] = limb.Position
	end
end

function Invisicam:MoveBehavior(castPoints)
	for i = 1, MOVE_CASTS do
		local position: Vector3, velocity: Vector3 =
			self.humanoidRootPart.Position, self.humanoidRootPart.AssemblyLinearVelocity
		local horizontalSpeed: number = Vector3.new(velocity.X, 0, velocity.Z).Magnitude / 2
		local offsetVector: Vector3 = (i - 1) * self.humanoidRootPart.CFrame.lookVector :: Vector3 * horizontalSpeed
		castPoints[#castPoints + 1] = position + offsetVector
	end
end

function Invisicam:CornerBehavior(castPoints)
	local cframe: CFrame = self.humanoidRootPart.CFrame
	local centerPoint: Vector3 = cframe.Position
	local rotation = cframe - centerPoint
	local halfSize = self.char:GetExtentsSize() / 2
	castPoints[#castPoints + 1] = centerPoint
	for i = 1, #CORNER_FACTORS do
		castPoints[#castPoints + 1] = centerPoint + (rotation * (halfSize * CORNER_FACTORS[i]))
	end
end

function Invisicam:CircleBehavior(castPoints)
	local cframe: CFrame
	if self.mode == MODE.CIRCLE1 then
		cframe = self.humanoidRootPart.CFrame
	else
		local camCFrame: CFrame = self.camera.CoordinateFrame
		cframe = camCFrame - camCFrame.Position + self.humanoidRootPart.Position
	end
	castPoints[#castPoints + 1] = cframe.Position
	for i = 0, CIRCLE_CASTS - 1 do
		local angle = (2 * math.pi / CIRCLE_CASTS) * i
		local offset = 3 * Vector3.new(math.cos(angle), math.sin(angle), 0)
		castPoints[#castPoints + 1] = cframe * offset
	end
end

function Invisicam:LimbMoveBehavior(castPoints)
	self:LimbBehavior(castPoints)
	self:MoveBehavior(castPoints)
end

function Invisicam:CharacterOutlineBehavior(castPoints)
	local torsoUp = self.torsoPart.CFrame.upVector.unit
	local torsoRight = self.torsoPart.CFrame.rightVector.unit

	castPoints[#castPoints + 1] = self.torsoPart.CFrame.Position
	castPoints[#castPoints + 1] = self.torsoPart.CFrame.Position + torsoUp
	castPoints[#castPoints + 1] = self.torsoPart.CFrame.Position - torsoUp
	castPoints[#castPoints + 1] = self.torsoPart.CFrame.Position + torsoRight
	castPoints[#castPoints + 1] = self.torsoPart.CFrame.Position - torsoRight
	if self.headPart then
		castPoints[#castPoints + 1] = self.headPart.CFrame.Position
	end

	local cframe = CFrame.new(
		ZERO_VECTOR3,
		Vector3.new(self.camera.CoordinateFrame.lookVector.X, 0, self.camera.CoordinateFrame.lookVector.Z)
	)
	local centerPoint = (self.torsoPart and self.torsoPart.Position or self.humanoidRootPart.Position)

	local partsWhitelist = { self.torsoPart }
	if self.headPart then
		partsWhitelist[#partsWhitelist + 1] = self.headPart
	end

	for i = 1, CHAR_OUTLINE_CASTS do
		local angle = (2 * math.pi * i / CHAR_OUTLINE_CASTS)
		local offset = cframe * (3 * Vector3.new(math.cos(angle), math.sin(angle), 0))

		offset = Vector3.new(offset.X, math.max(offset.Y, -2.25), offset.Z)

		if FFlagUserRaycastUpdateAPI then
			includeParams.FilterDescendantsInstances = partsWhitelist
			local raycastResult = workspace:Raycast(centerPoint + offset, -3 * offset, includeParams)

			if raycastResult then

				local position = raycastResult.Position
				castPoints[#castPoints + 1] = position + 0.2 * (centerPoint - position).unit
			end
		else
			local raycastParams = RaycastParams.new()
			raycastParams.FilterType = Enum.RaycastFilterType.Include
			raycastParams.FilterDescendantsInstances = partsWhitelist
			raycastParams.IgnoreWater = true
			local result = workspace:Raycast(centerPoint + offset, -3 * offset, raycastParams)

			if result and result.Instance then

				local hitPoint = result.Position
				castPoints[#castPoints + 1] = hitPoint + 0.2 * (centerPoint - hitPoint).unit
			end
		end
	end
end

function Invisicam:SmartCircleBehavior(castPoints)
	local torsoUp = self.torsoPart.CFrame.upVector.unit
	local torsoRight = self.torsoPart.CFrame.rightVector.unit

	castPoints[#castPoints + 1] = self.torsoPart.CFrame.Position
	castPoints[#castPoints + 1] = self.torsoPart.CFrame.Position + torsoUp
	castPoints[#castPoints + 1] = self.torsoPart.CFrame.Position - torsoUp
	castPoints[#castPoints + 1] = self.torsoPart.CFrame.Position + torsoRight
	castPoints[#castPoints + 1] = self.torsoPart.CFrame.Position - torsoRight
	if self.headPart then
		castPoints[#castPoints + 1] = self.headPart.CFrame.Position
	end

	local cameraOrientation = self.camera.CFrame - self.camera.CFrame.Position
	local torsoPoint = Vector3.new(0, 0.5, 0)
		+ (self.torsoPart and self.torsoPart.Position or self.humanoidRootPart.Position)
	local radius = 2.5

	for i = 1, SMART_CIRCLE_CASTS do
		local angle = SMART_CIRCLE_INCREMENT * i - 0.5 * math.pi
		local offset = radius * Vector3.new(math.cos(angle), math.sin(angle), 0)
		local circlePoint = torsoPoint + cameraOrientation * offset

		local vp = circlePoint - self.camera.CFrame.Position

		if FFlagUserRaycastUpdateAPI then
			excludeParams.FilterDescendantsInstances = { self.char }
			local raycastResult = workspace:Raycast(torsoPoint, circlePoint - torsoPoint, excludeParams)

			local castPoint = circlePoint
			if raycastResult then
				local position = raycastResult.Position
				local normal = raycastResult.Normal
				local hprime = position + 0.1 * normal.unit
				local v0 = hprime - torsoPoint

				local perp = (v0:Cross(vp)).unit

				local v1 = (perp:Cross(normal)).unit

				local vprime = (hprime - self.camera.CFrame.Position).unit

				if v0.unit:Dot(-v1) < v0.unit:Dot(vprime) then
					castPoint = RayIntersection(hprime, v1, circlePoint, vp)

					if castPoint.Magnitude > 0 then
						raycastResult = workspace:Raycast(hprime, castPoint - hprime, excludeParams)

						if raycastResult then
							local hprime2 = raycastResult.Position + 0.1 * raycastResult.Normal.Unit
							castPoint = hprime2
						end
					else
						castPoint = hprime
					end
				else
					castPoint = hprime
				end

				raycastResult = workspace:Raycast(torsoPoint, castPoint - torsoPoint, excludeParams)

				if raycastResult then
					local castPoint2 = raycastResult.Position - 0.1 * (castPoint - torsoPoint).unit
					castPoint = castPoint2
				end
			end

			castPoints[#castPoints + 1] = castPoint
		else
			local rayParams = RaycastParams.new()
			rayParams.FilterType = Enum.RaycastFilterType.Exclude
			rayParams.FilterDescendantsInstances = { self.char }
			local result = workspace:Raycast(torsoPoint, circlePoint - torsoPoint, rayParams)
			local castPoint = circlePoint

			if result and result.Instance then
				local hp = result.Position
				local hitNormal = result.Normal
				local hprime = hp + 0.1 * hitNormal.unit
				local v0 = hprime - torsoPoint

				local perp = (v0:Cross(vp)).unit

				local v1 = (perp:Cross(hitNormal)).unit

				local vprime = (hprime - self.camera.CFrame.Position).unit

				if v0.unit:Dot(-v1) < v0.unit:Dot(vprime) then
					castPoint = RayIntersection(hprime, v1, circlePoint, vp)

					if castPoint.Magnitude > 0 then
						local checkResult = workspace:Raycast(hprime, castPoint - hprime, rayParams)

						if checkResult and checkResult.Instance then
							local hprime2 = checkResult.Position + 0.1 * checkResult.Normal.unit
							castPoint = hprime2
						end
					else
						castPoint = hprime
					end
				else
					castPoint = hprime
				end

				local finalResult = workspace:Raycast(torsoPoint, (castPoint - torsoPoint), rayParams)

				if finalResult and finalResult.Instance then
					local castPoint2 = finalResult.Position - 0.1 * (castPoint - torsoPoint).unit
					castPoint = castPoint2
				end
			end

			castPoints[#castPoints + 1] = castPoint
		end
	end
end

function Invisicam:CheckTorsoReference()
	if self.char then
		self.torsoPart = self.char:FindFirstChild("Torso")
		if not self.torsoPart then
			self.torsoPart = self.char:FindFirstChild("UpperTorso")
			if not self.torsoPart then
				self.torsoPart = self.char:FindFirstChild("HumanoidRootPart")
			end
		end

		self.headPart = self.char:FindFirstChild("Head")
	end
end

function Invisicam:CharacterAdded(char: Model, player: Player)

	if player ~= PlayersService.LocalPlayer then
		return
	end

	if self.childAddedConn then
		self.childAddedConn:Disconnect()
		self.childAddedConn = nil
	end
	if self.childRemovedConn then
		self.childRemovedConn:Disconnect()
		self.childRemovedConn = nil
	end

	self.char = char

	self.trackedLimbs = {}
	local function childAdded(child)
		if child:IsA("BasePart") then
			if LIMB_TRACKING_SET[child.Name] then
				self.trackedLimbs[child] = true
			end

			if child.Name == "Torso" or child.Name == "UpperTorso" then
				self.torsoPart = child
			end

			if child.Name == "Head" then
				self.headPart = child
			end
		end
	end

	local function childRemoved(child)
		self.trackedLimbs[child] = nil

		self:CheckTorsoReference()
	end

	self.childAddedConn = char.ChildAdded:Connect(childAdded)
	self.childRemovedConn = char.ChildRemoved:Connect(childRemoved)
	for _, child in pairs(self.char:GetChildren()) do
		childAdded(child)
	end
end

function Invisicam:SetMode(newMode: number)
	AssertTypes(newMode, "number")
	for _, modeNum in pairs(MODE) do
		if modeNum == newMode then
			self.mode = newMode
			self.behaviorFunction = self.behaviors[self.mode]
			return
		end
	end
	error("Invalid mode number")
end

function Invisicam:GetObscuredParts()
	return self.savedHits
end

function Invisicam:Cleanup()
	for hit, originalFade in pairs(self.savedHits) do
		hit.LocalTransparencyModifier = originalFade
	end
end

function Invisicam:Update(_dt: number, desiredCameraCFrame: CFrame, desiredCameraFocus: CFrame): (CFrame, CFrame)

	if not self.enabled or not self.char then
		return desiredCameraCFrame, desiredCameraFocus
	end

	self.camera = workspace.CurrentCamera

	if not self.humanoidRootPart then
		local humanoid = self.char:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.RootPart then
			self.humanoidRootPart = humanoid.RootPart
		else

			self.humanoidRootPart = self.char:FindFirstChild("HumanoidRootPart")
			if not self.humanoidRootPart then

				return desiredCameraCFrame, desiredCameraFocus
			end
		end

		local ancestryChangedConn
		ancestryChangedConn = self.humanoidRootPart.AncestryChanged:Connect(function(child, parent)
			if child == self.humanoidRootPart and not parent then
				self.humanoidRootPart = nil
				if ancestryChangedConn and ancestryChangedConn.Connected then
					ancestryChangedConn:Disconnect()
					ancestryChangedConn = nil
				end
			end
		end)
	end

	if not self.torsoPart then
		self:CheckTorsoReference()
		if not self.torsoPart then

			return desiredCameraCFrame, desiredCameraFocus
		end
	end

	local castPoints = {}
	self.behaviorFunction(self, castPoints)

	local currentHits = {}
	local ignoreList = { self.char }
	local function add(hit)
		currentHits[hit] = true
		if not self.savedHits[hit] then
			self.savedHits[hit] = hit.LocalTransparencyModifier
		end
	end

	local hitParts
	local hitPartCount = 0

	local headTorsoRayHitParts = {}

	local perPartTransparencyHeadTorsoHits = TARGET_TRANSPARENCY
	local perPartTransparencyOtherHits = TARGET_TRANSPARENCY

	if USE_STACKING_TRANSPARENCY then

		local headPoint = self.headPart and self.headPart.CFrame.Position or castPoints[1]
		local torsoPoint = self.torsoPart and self.torsoPart.CFrame.Position or castPoints[2]
		hitParts = self.camera:GetPartsObscuringTarget({ headPoint, torsoPoint }, ignoreList)

		for i = 1, #hitParts do
			local hitPart = hitParts[i]
			hitPartCount = hitPartCount + 1
			headTorsoRayHitParts[hitPart] = true
			for _, child in pairs(hitPart:GetChildren()) do
				if child:IsA("Decal") or child:IsA("Texture") then
					hitPartCount = hitPartCount + 1
					break
				end
			end
		end

		if hitPartCount > 0 then
			perPartTransparencyHeadTorsoHits =
				math.pow(((0.5 * TARGET_TRANSPARENCY) + (0.5 * TARGET_TRANSPARENCY / hitPartCount)), 1 / hitPartCount)
			perPartTransparencyOtherHits = math.pow(
				((0.5 * TARGET_TRANSPARENCY_PERIPHERAL) + (0.5 * TARGET_TRANSPARENCY_PERIPHERAL / hitPartCount)),
				1 / hitPartCount
			)
		end
	end

	hitParts = self.camera:GetPartsObscuringTarget(castPoints, ignoreList)

	local partTargetTransparency = {}

	for i = 1, #hitParts do
		local hitPart = hitParts[i]

		partTargetTransparency[hitPart] = headTorsoRayHitParts[hitPart] and perPartTransparencyHeadTorsoHits
			or perPartTransparencyOtherHits

		if hitPart.Transparency < partTargetTransparency[hitPart] then
			add(hitPart)
		end

		for _, child in pairs(hitPart:GetChildren()) do
			if child:IsA("Decal") or child:IsA("Texture") then
				if child.Transparency < partTargetTransparency[hitPart] then
					partTargetTransparency[child] = partTargetTransparency[hitPart]
					add(child)
				end
			end
		end
	end

	for hitPart, originalLTM in pairs(self.savedHits) do
		if currentHits[hitPart] then

			hitPart.LocalTransparencyModifier = (hitPart.Transparency < 1)
					and ((partTargetTransparency[hitPart] - hitPart.Transparency) / (1.0 - hitPart.Transparency))
				or 0
		else
			hitPart.LocalTransparencyModifier = originalLTM
			self.savedHits[hitPart] = nil
		end
	end

	return desiredCameraCFrame, desiredCameraFocus
end

return Invisicam
