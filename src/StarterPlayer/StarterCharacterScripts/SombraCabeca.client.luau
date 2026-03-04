--!nonstrict
--[[
	SombraCabeca.client.luau
	
	Projeta sombras da Head e acessórios da cabeça em primeira pessoa.
	Adaptado e otimizado a partir de um script de shadow projection.
	
	Funciona criando clones invisíveis das partes da cabeça,
	posicionando-os na direção do sol relativo à câmera.
	
	- Só ativa em primeira pessoa
	- Só quando a câmera olha na direção oposta ao sol
	- Sem memory leaks: limpa conexões e clones no respawn
	- Apenas Head + acessórios da cabeça (HatAttachment, HairAttachment, etc.)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- ═══════════════════════════════════════════════════════════════════
-- CONFIGURAÇÃO
-- ═══════════════════════════════════════════════════════════════════

-- Attachments que indicam que o acessório está na cabeça
local HEAD_ATTACHMENTS: { [string]: boolean } = {
	HatAttachment = true,
	HairAttachment = true,
	FaceFrontAttachment = true,
	FaceCenterAttachment = true,
}

-- ═══════════════════════════════════════════════════════════════════
-- ESTADO
-- ═══════════════════════════════════════════════════════════════════

local projector = Instance.new("Model")
projector.Name = "ShadowProjector"

local activeChar: Model? = nil
local registry: { [BasePart]: BasePart } = {} -- real part → shadow clone
local connections: { RBXScriptConnection } = {}

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES
-- ═══════════════════════════════════════════════════════════════════

--- Verifica se um acessório está preso à cabeça
local function isHeadAccessory(accessory: Accessory): boolean
	local handle = accessory:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		return false
	end

	-- Verifica se algum Attachment do Handle é de cabeça
	for _, child in handle:GetChildren() do
		if child:IsA("Attachment") and HEAD_ATTACHMENTS[child.Name] then
			return true
		end
	end

	-- Fallback: verifica se o Handle está welded à Head
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

--- Cria um clone-sombra de uma parte
local function createShadowClone(part: BasePart): BasePart
	local clone = part:Clone()
	clone.Anchored = true
	clone.CanCollide = false
	clone.CanTouch = false
	clone.CanQuery = false
	clone.CastShadow = true

	-- Remove joints (não precisam de física)
	for _, child in clone:GetChildren() do
		if child:IsA("JointInstance") then
			child:Destroy()
		end
	end

	-- Se é visível, mantém opaco pra projetar sombra
	if clone.Transparency < 1 then
		clone.Transparency = 0
	end

	clone.Parent = projector
	return clone
end

--- Registra uma parte para projeção de sombra
local function registerPart(part: BasePart)
	if registry[part] then
		return -- Já registrada
	end

	local clone = createShadowClone(part)
	registry[part] = clone

	-- Escuta mudanças de mesh na parte original
	local conn = part.ChildAdded:Connect(function(child)
		if child:IsA("SpecialMesh") then
			-- Atualiza mesh no clone
			for _, c in clone:GetChildren() do
				if c:IsA("SpecialMesh") then
					c:Destroy()
				end
			end
			child:Clone().Parent = clone
		end
	end)
	table.insert(connections, conn)
end

--- Processa um child do character
local function processChild(child: Instance)
	if child.Name == "Head" and child:IsA("BasePart") then
		registerPart(child)
	elseif child:IsA("Accessory") and isHeadAccessory(child :: Accessory) then
		local handle = child:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") then
			registerPart(handle)
		end
	end
end

--- Limpa tudo (connections, clones, registry)
local function cleanup()
	for _, conn in connections do
		conn:Disconnect()
	end
	table.clear(connections)

	projector:ClearAllChildren()
	table.clear(registry)

	projector.Parent = nil
	activeChar = nil
end

--- Atualiza posição da sombra a cada frame
local function update()
	if not activeChar then
		return
	end

	-- Limpa partes removidas do character
	for realPart, shadowPart in registry do
		if not realPart:IsDescendantOf(activeChar) then
			shadowPart:Destroy()
			registry[realPart] = nil
		end
	end

	-- Verifica se o sol está visível
	local sunDir = Lighting:GetSunDirection()
	if sunDir.Y <= 0 then
		projector.Parent = nil
		return
	end

	-- Verifica se está em primeira pessoa
	local cf = camera.CFrame
	local focus = camera.Focus
	local dist = (focus.Position - cf.Position).Magnitude

	if dist >= 1 then
		projector.Parent = nil
		return
	end

	-- Verifica se está olhando na direção oposta ao sol
	local sunPos = sunDir * 10000
	if sunDir:Dot(cf.LookVector) >= 0 then
		projector.Parent = nil
		return
	end

	-- Pega a Head como referência de posição
	local head = activeChar:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") or not registry[head] then
		projector.Parent = nil
		return
	end

	-- Calcula projeção da sombra
	local focusPoint = focus.Position
	local sunDist = (focusPoint - sunPos).Magnitude
	local headCF = head.CFrame
	local headPos = headCF.Position
	local headRot = headCF.Rotation

	local realDist = (focusPoint - headPos).Magnitude
	local lerpScale = (realDist / sunDist) * 9

	local projectPos = focusPoint:Lerp(sunPos, lerpScale)
	local camOffset = headPos - focusPoint
	local shadowHeadCF = CFrame.new(projectPos + camOffset) * headRot

	-- Atualiza posição do clone da Head
	local shadowHead = registry[head]
	shadowHead.CFrame = shadowHeadCF

	-- Atualiza posição dos acessórios relativos à Head
	for realPart, shadowPart in registry do
		if realPart ~= head then
			local offset = headCF:ToObjectSpace(realPart.CFrame)
			shadowPart.CFrame = shadowHeadCF * offset
			shadowPart:BreakJoints()
		end
	end

	projector.Parent = camera
end

--- Inicializa para um novo character
local function onCharacterAdded(char: Model)
	cleanup()
	activeChar = char

	-- Registra partes existentes
	for _, child in char:GetChildren() do
		processChild(child)
	end

	-- Escuta novas partes (ex: acessórios equipados depois)
	local conn = char.ChildAdded:Connect(function(child)
		-- Pequeno delay para garantir que Attachments já existem
		task.defer(processChild, child)
	end)
	table.insert(connections, conn)
end

-- ═══════════════════════════════════════════════════════════════════
-- INICIALIZAÇÃO
-- ═══════════════════════════════════════════════════════════════════

if player.Character then
	onCharacterAdded(player.Character)
end

player.CharacterAdded:Connect(onCharacterAdded)
RunService:BindToRenderStep("HeadShadowProjection", Enum.RenderPriority.Camera.Value + 1, update)
