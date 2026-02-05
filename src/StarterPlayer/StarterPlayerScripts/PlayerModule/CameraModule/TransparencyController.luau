--!nonstrict
--[[
	TransparencyController - Manages transparency of player character at close camera-to-subject distances
	2018 Camera Update - AllYourBlox
--]]

local _VRService = game:GetService("VRService")
local MAX_TWEEN_RATE = 2.8 -- per second

-- Classes with a LocalTransparencyModifier property that we should hide in first person
local HIDE_IN_FIRST_PERSON_CLASSES = {
	"BasePart",
	"Decal",
	"Beam",
	"ParticleEmitter",
	"Trail",
	"Fire",
	"Smoke",
	"Sparkles",
	"Explosion",
}

local Util = require(script.Parent:WaitForChild("CameraUtils"))

local FFlagUserHideCharacterParticlesInFirstPerson
do
	local success, result = pcall(function()
		return UserSettings():IsUserFeatureEnabled("UserHideCharacterParticlesInFirstPerson")
	end)
	FFlagUserHideCharacterParticlesInFirstPerson = success and result
end

--[[ The Module ]]
--
local TransparencyController = {}
TransparencyController.__index = TransparencyController

function TransparencyController.new()
	local self = setmetatable({}, TransparencyController)

	self.transparencyDirty = false
	self.enabled = false
	self.lastTransparency = nil

	self.descendantAddedConn, self.descendantRemovingConn = nil, nil
	self.toolDescendantAddedConns = {}
	self.toolDescendantRemovingConns = {}
	self.cachedParts = {}

	-- Tipos de acessórios que devem ficar transparentes em 1ª pessoa
	-- (apenas acessórios de cabeça - cabelo, chapéus, face, etc.)
	self.headAccessoryTypes = {
		[Enum.AccessoryType.Hat] = true,
		[Enum.AccessoryType.Hair] = true,
		[Enum.AccessoryType.Face] = true,
		[Enum.AccessoryType.Eyebrow] = true,
		[Enum.AccessoryType.Eyelash] = true,
	}

	return self
end

function TransparencyController:HasToolAncestor(object: Instance)
	if object.Parent == nil then
		return false
	end
	assert(object.Parent, "")
	return object.Parent:IsA("Tool") or self:HasToolAncestor(object.Parent)
end

-- Verifica se o objeto é um acessório de cabeça (cabelo, chapéu, face, etc.)
-- Apenas esses devem ficar transparentes em 1ª pessoa
function TransparencyController:IsHeadAccessory(object: Instance): boolean
	-- Verifica se é a parte Head diretamente
	if object.Name == "Head" then
		return true
	end

	-- Verifica se é parte de um acessório de cabeça
	local accessory = object:FindFirstAncestorWhichIsA("Accessory")
	if accessory then
		local accessoryType = accessory.AccessoryType
		if self.headAccessoryTypes[accessoryType] then
			return true
		end
	end

	return false
end

function TransparencyController:IsValidPartToModify(part: BasePart)
	if FFlagUserHideCharacterParticlesInFirstPerson then
		for _, className in HIDE_IN_FIRST_PERSON_CLASSES do
			if part:IsA(className) then
				return not self:HasToolAncestor(part)
			end
		end
	else
		if part:IsA("BasePart") or part:IsA("Decal") then
			return not self:HasToolAncestor(part)
		end
	end
	return false
end

function TransparencyController:CachePartsRecursive(object)
	if object then
		if self:IsValidPartToModify(object) then
			self.cachedParts[object] = true
			self.transparencyDirty = true
		end
		for _, child in pairs(object:GetChildren()) do
			self:CachePartsRecursive(child)
		end
	end
end

function TransparencyController:TeardownTransparency()
	for child, _ in pairs(self.cachedParts) do
		child.LocalTransparencyModifier = 0
	end
	self.cachedParts = {}
	self.transparencyDirty = true
	self.lastTransparency = nil

	if self.descendantAddedConn then
		self.descendantAddedConn:disconnect()
		self.descendantAddedConn = nil
	end
	if self.descendantRemovingConn then
		self.descendantRemovingConn:disconnect()
		self.descendantRemovingConn = nil
	end
	for object, conn in pairs(self.toolDescendantAddedConns) do
		conn:Disconnect()
		self.toolDescendantAddedConns[object] = nil
	end
	for object, conn in pairs(self.toolDescendantRemovingConns) do
		conn:Disconnect()
		self.toolDescendantRemovingConns[object] = nil
	end
end

function TransparencyController:SetupTransparency(character)
	self:TeardownTransparency()

	if self.descendantAddedConn then
		self.descendantAddedConn:disconnect()
	end
	self.descendantAddedConn = character.DescendantAdded:Connect(function(object)
		-- This is a part we want to invisify
		if self:IsValidPartToModify(object) then
			self.cachedParts[object] = true
			self.transparencyDirty = true
		-- There is now a tool under the character
		elseif object:IsA("Tool") then
			if self.toolDescendantAddedConns[object] then
				self.toolDescendantAddedConns[object]:Disconnect()
			end
			self.toolDescendantAddedConns[object] = object.DescendantAdded:Connect(function(toolChild)
				self.cachedParts[toolChild] = nil
				if toolChild:IsA("BasePart") or toolChild:IsA("Decal") then
					-- Reset the transparency
					toolChild.LocalTransparencyModifier = 0
				end
			end)
			if self.toolDescendantRemovingConns[object] then
				self.toolDescendantRemovingConns[object]:disconnect()
			end
			self.toolDescendantRemovingConns[object] = object.DescendantRemoving:Connect(function(formerToolChild)
				task.wait() -- wait for new parent
				if character and formerToolChild and formerToolChild:IsDescendantOf(character) then
					if self:IsValidPartToModify(formerToolChild) then
						self.cachedParts[formerToolChild] = true
						self.transparencyDirty = true
					end
				end
			end)
		end
	end)
	if self.descendantRemovingConn then
		self.descendantRemovingConn:disconnect()
	end
	self.descendantRemovingConn = character.DescendantRemoving:connect(function(object)
		if self.cachedParts[object] then
			self.cachedParts[object] = nil
			-- Reset the transparency
			object.LocalTransparencyModifier = 0
		end
	end)
	self:CachePartsRecursive(character)
end

function TransparencyController:Enable(enable: boolean)
	if self.enabled ~= enable then
		self.enabled = enable
	end
end

function TransparencyController:SetSubject(subject)
	local character = nil
	if subject and subject:IsA("Humanoid") then
		character = subject.Parent
	end
	if subject and subject:IsA("VehicleSeat") and subject.Occupant then
		character = subject.Occupant.Parent
	end
	if character then
		self:SetupTransparency(character)
	else
		self:TeardownTransparency()
	end
end

function TransparencyController:Update(dt)
	local currentCamera = workspace.CurrentCamera

	if currentCamera and self.enabled then
		-- calculate goal transparency based on distance
		local distance = (currentCamera.Focus.Position - currentCamera.CFrame.Position).Magnitude
		local transparency = (distance < 2) and (1.0 - (distance - 0.5) / 1.5) or 0 -- (7 - distance) / 5
		if transparency < 0.5 then -- too far, don't control transparency
			transparency = 0
		end

		-- tween transparency if the goal is not fully transparent and the subject was not fully transparent last frame
		if self.lastTransparency and transparency < 1 and self.lastTransparency < 0.95 then
			local deltaTransparency = transparency - self.lastTransparency
			local maxDelta = MAX_TWEEN_RATE * dt
			deltaTransparency = math.clamp(deltaTransparency, -maxDelta, maxDelta)
			transparency = self.lastTransparency + deltaTransparency
		else
			self.transparencyDirty = true
		end

		transparency = math.clamp(Util.Round(transparency, 2), 0, 1)

		-- update transparencies
		if self.transparencyDirty or self.lastTransparency ~= transparency then
			for child, _ in pairs(self.cachedParts) do
				-- MODIFICAÇÃO: Corpo deve ficar SEMPRE visível em 1ª pessoa
				-- Apenas cabelo e acessórios de cabeça ficam transparentes
				if self:IsHeadAccessory(child) then
					child.LocalTransparencyModifier = transparency
				else
					-- Corpo e outros acessórios sempre visíveis
					child.LocalTransparencyModifier = 0
				end
			end
			self.transparencyDirty = false
			self.lastTransparency = transparency
		end
	end
end

return TransparencyController
