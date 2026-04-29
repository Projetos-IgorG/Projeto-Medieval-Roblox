--!nonstrict

--[[
    Script: SombraCabeca.client.luau
    Caminho: src/StarterPlayer/StarterCharacterScripts/Jogador/Camera
    Responsabilidade: Atualiza sombra e visibilidade da cabeca do personagem local.
    Uso: LocalScript; roda automaticamente para o jogador local em src/StarterPlayer/StarterCharacterScripts/Jogador/Camera.
    Nao faz: Nao valida autoridade do servidor, nao salva dados persistentes e nao substitui regras server-side.
    Funcoes principais: createShadowClone, registerPart, unregisterPart, processChild, cleanup, activate
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local ClientBridge = require(
	ReplicatedStorage:WaitForChild("Jogador"):WaitForChild("ComunicacaoCliente"):WaitForChild("PonteCliente")
)
local ProjetorSombra = require(
	ReplicatedStorage:WaitForChild("Jogador"):WaitForChild("Camera"):WaitForChild("Sombra"):WaitForChild("ProjetorSombra")
)

local projector: Model = Instance.new("Model")
projector.Name = "ShadowProjector"

local activeChar: Model? = nil
local registry: { [BasePart]: BasePart } = {}
local charConnections: { RBXScriptConnection } = {}
local wasActive = false

local function createShadowClone(part: BasePart): BasePart
	local clone = part:Clone()
	clone.Anchored = true
	clone.CanCollide = false
	clone.CanTouch = false
	clone.CanQuery = false
	clone.CastShadow = true
	clone.Transparency = math.huge

	for _, child in clone:GetChildren() do
		if child:IsA("JointInstance") or child:IsA("Weld") or child:IsA("WeldConstraint") then
			child:Destroy()
		end
	end

	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.Parent = clone

	clone.Parent = projector
	return clone
end

local function registerPart(part: BasePart)
	if registry[part] then return end
	registry[part] = createShadowClone(part)
end

local function unregisterPart(part: BasePart)
	local clone = registry[part]
	if clone then
		clone:Destroy()
		registry[part] = nil
	end
end

local function processChild(child: Instance)
	if child.Name == "Head" and child:IsA("BasePart") then
		registerPart(child)
	elseif child:IsA("Accessory") and ProjetorSombra.IsHeadAccessory(child :: Accessory) then
		local handle = child:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") then
			registerPart(handle)
		end
	end
end

local function cleanup()
	for _, conn in charConnections do
		conn:Disconnect()
	end
	table.clear(charConnections)

	for _part, clone in registry do
		clone:Destroy()
	end
	table.clear(registry)

	projector.Parent = nil
	activeChar = nil
	wasActive = false
end

local function activate()
	if wasActive then return end
	wasActive = true
	projector.Parent = camera
end

local function deactivate()
	if not wasActive then return end
	wasActive = false
	projector.Parent = nil
end

local function update()
	if not activeChar then
		deactivate()
		return
	end

	local emPrimeiraPessoa = ClientBridge.EstaEmPrimeiraPessoa
		and ClientBridge.EstaEmPrimeiraPessoa()
		or false

	if not emPrimeiraPessoa then
		deactivate()
		return
	end

	activate()

	for realPart, shadowClone in registry do
		if realPart.Parent and realPart:IsDescendantOf(activeChar) then
			shadowClone.CFrame = realPart.CFrame
		else

			shadowClone:Destroy()
			registry[realPart] = nil
		end
	end
end

local function onCharacterAdded(char: Model)
	cleanup()
	activeChar = char

	for _, child in char:GetChildren() do
		processChild(child)
	end

	local addConn = char.ChildAdded:Connect(function(child)
		task.defer(processChild, child)
	end)
	table.insert(charConnections, addConn)

	local removeConn = char.ChildRemoved:Connect(function(child)
		if child.Name == "Head" and child:IsA("BasePart") then
			unregisterPart(child)
		elseif child:IsA("Accessory") then
			local handle = child:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				unregisterPart(handle)
			end
		end
	end)
	table.insert(charConnections, removeConn)
end

if player.Character then
	onCharacterAdded(player.Character)
end

player.CharacterAdded:Connect(onCharacterAdded)
player.CharacterRemoving:Connect(cleanup)
RunService:BindToRenderStep("HeadShadowProjection", Enum.RenderPriority.Camera.Value + 1, update)
