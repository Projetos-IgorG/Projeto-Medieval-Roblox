--!strict
--[[
	Script: init.luau
	Caminho: src/ReplicatedStorage/Jogador/Aparencia/UnificacaoFacial
	Responsabilidade: Substitui dynamic heads por seus equivalentes classicos 2D usando o modulo Facial Unification (v1.5) do Dogutsune.
	Uso: ModuleScript; consumido pelo servidor (precisa de CreateHumanoidModelFromDescriptionAsync e ApplyDescriptionAsync).
	Nao faz: Nao escuta eventos de Players nem aplica conversao automaticamente; quem chama decide quando converter.
	Funcoes principais: ConvertFromHumanoidDescription, ConvertAnimatedHead, GetHeadShape
]]

local EXCLUDED_ACCESSORIES = {
	Enum.AccessoryType.Eyebrow,
	Enum.AccessoryType.Eyelash,
}

local Players = game:GetService("Players")
local ToHatModule: ModuleScript = script:WaitForChild("ToHat")
local TO_HAT = require(ToHatModule)
local ToFaceModule: ModuleScript = script:WaitForChild("ToFace")
local TO_FACE = require(ToFaceModule)
local HeadShapesModule: ModuleScript = script:WaitForChild("HeadShapes")
local HEAD_SHAPES = require(HeadShapesModule) :: { [string]: number }

local Desc = Instance.new("HumanoidDescription")
Desc.HeadScale = 1
Desc.WidthScale = 1
Desc.DepthScale = 1
Desc.HeightScale = 1
Desc.BodyTypeScale = 0
Desc.ProportionScale = 0

local function CreateRetexture(name: string, hatId: number, texture: number): Accoutrement?
	local textureID = `rbxassetid://{texture}`

	local DescHolder = Desc:Clone()
	DescHolder.HatAccessory = tostring(hatId)

	local R15 = Players:CreateHumanoidModelFromDescriptionAsync(DescHolder, Enum.HumanoidRigType.R15)
	local hat = R15:FindFirstChildWhichIsA("Accoutrement")
	if hat then
		hat.Name = name
		local handle = hat:FindFirstChild("Handle")
		if handle and handle:IsA("MeshPart") then
			handle.TextureID = textureID
		elseif handle and handle:IsA("BasePart") then
			local mesh = handle:FindFirstChildWhichIsA("SpecialMesh")
			if mesh and mesh:IsA("SpecialMesh") then
				mesh.TextureId = textureID
			end
		end
	end

	return hat
end

local function ReturnHeadFromShape(headShape: string): number
	assert(headShape, "Expected HeadShape string but got nil instead!")
	local id = HEAD_SHAPES[headShape]
	return id or 0
end

local FacialU = {}

local function RemoveFaceAccessories(humanoidDescription: HumanoidDescription)
	local getAccessories = humanoidDescription:GetAccessories(true)
	local setAccessories = {}
	for _, v in pairs(getAccessories) do
		local accType = v.AccessoryType or Enum.AccessoryType.Unknown
		local isInTable = table.find(EXCLUDED_ACCESSORIES, accType) ~= nil
		if not isInTable then
			table.insert(setAccessories, v)
		end
	end
	humanoidDescription:SetAccessories(setAccessories, true)
end

function FacialU:GetHeadShape(humanoidDescription: HumanoidDescription): string
	assert(
		humanoidDescription,
		"Expected HumanoidDescription but got nil instead, please provide a humanoid description!"
	)
	local shape = ""

	for _, bodyPart in pairs(humanoidDescription:GetChildren()) do
		if bodyPart and bodyPart:IsA("BodyPartDescription") and bodyPart.HeadShape ~= "" then
			shape = bodyPart.HeadShape
			break
		end
	end

	return shape
end

function FacialU:ConvertFromHumanoidDescription(
	humanoidDescription: HumanoidDescription,
	useDefaultHead: boolean?
): (boolean, Accoutrement?)
	assert(
		humanoidDescription,
		"Expected HumanoidDescription but got nil instead, please provide a humanoid description!"
	)

	useDefaultHead = useDefaultHead or false

	local ID = humanoidDescription.Head
	local removeFaceStuff = false
	local hatToCopy: Accoutrement?

	if TO_HAT[ID] then
		hatToCopy = CreateRetexture(TO_HAT[ID].Name, TO_HAT[ID].OriginalHat, TO_HAT[ID].Texture)
		humanoidDescription.Head = 0
		removeFaceStuff = true
	elseif TO_FACE[ID] then
		humanoidDescription.Face = TO_FACE[ID].Face
		removeFaceStuff = true

		if useDefaultHead then
			humanoidDescription.Head = 0
		else
			local name = self:GetHeadShape(humanoidDescription)
			humanoidDescription.Head = (name and name ~= "") and ReturnHeadFromShape(name) or TO_FACE[ID].Head or 0
		end
	end

	if removeFaceStuff then
		RemoveFaceAccessories(humanoidDescription)

		if hatToCopy and hatToCopy:IsA("Accoutrement") then
			local newHat = Instance.new("AccessoryDescription")
			newHat.AccessoryType = hatToCopy:IsA("Accessory") and hatToCopy.AccessoryType or Enum.AccessoryType.Hat
			newHat.Instance = hatToCopy
			newHat.Parent = humanoidDescription
		end
	end

	return removeFaceStuff, hatToCopy
end

function FacialU:ConvertAnimatedHead(
	humanoid: Humanoid,
	useDefaultHead: boolean?,
	forceClassicFallback: boolean?
): boolean
	assert(humanoid, "Expected Humanoid but got nil instead!")
	useDefaultHead = useDefaultHead or false
	forceClassicFallback = forceClassicFallback == true

	humanoid:WaitForChild("HumanoidDescription", 1)
	local desc = humanoid:GetAppliedDescription() :: HumanoidDescription
	if desc then
		local wasConverted = self:ConvertFromHumanoidDescription(desc, useDefaultHead)
		if not wasConverted and forceClassicFallback then
			-- Avatar sem entrada em ToHat/ToFace: ainda assim garantimos head
			-- classico e nenhum acessorio facial; deixamos desc.Face como veio
			-- (0 ou id do proprio avatar) para que ApplyDescriptionAsync use o
			-- padrao do engine sem hardcode local.
			RemoveFaceAccessories(desc)
			desc.Head = 0
			wasConverted = true
		end

		if wasConverted then
			humanoid:ApplyDescriptionAsync(desc)
			humanoid.ApplyDescriptionFinished:Wait()
			return true
		end
	end

	return false
end

local Attribution: ModuleScript = script:FindFirstChild("Attribution")
if Attribution and Attribution:IsA("ModuleScript") then
	require(Attribution)
end

return FacialU
