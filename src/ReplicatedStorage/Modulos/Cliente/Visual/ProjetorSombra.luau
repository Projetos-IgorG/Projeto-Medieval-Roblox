-- ReplicatedStorage > Modulos > Cliente > Visual > ProjetorSombra.luau

local ProjetorSombra = {}

local HEAD_ATTACHMENTS = {
	HatAttachment = true,
	HairAttachment = true,
	FaceFrontAttachment = true,
	FaceCenterAttachment = true,
}

function ProjetorSombra.IsHeadAccessory(accessory: Accessory): boolean
	local handle = accessory:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		return false
	end

	for _, child in handle:GetChildren() do
		if child:IsA("Attachment") and HEAD_ATTACHMENTS[child.Name] then
			return true
		end
	end

	for _, desc in handle:GetDescendants() do
		if desc:IsA("Weld") or desc:IsA("WeldConstraint") then
			local part0 = (desc :: any).Part0
			local part1 = (desc :: any).Part1
			if (part0 and part0.Name == "Head") or (part1 and part1.Name == "Head") then
				return true
			end
		end
	end

	return false
end

function ProjetorSombra.CreateShadowClone(part: BasePart, projector: Instance): BasePart
	local clone = part:Clone()
	clone.Anchored = true
	clone.CanCollide = false
	clone.CanTouch = false
	clone.CanQuery = false
	clone.CastShadow = true

	for _, child in clone:GetChildren() do
		if child:IsA("JointInstance") then
			child:Destroy()
		end
	end

	if clone.Transparency < 1 then
		clone.Transparency = 0
	end

	clone.Parent = projector
	return clone
end

return ProjetorSombra
