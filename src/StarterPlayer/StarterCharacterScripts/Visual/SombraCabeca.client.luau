--!nonstrict
--[[
	SombraCabeca.client.luau
	
	Projeta sombras da Head e acessórios da cabeça em primeira pessoa.
	
	Como LocalTransparencyModifier esconde a sombra localmente,
	criamos clones opacos invisíveis (Transparency = math.huge + Highlight)
	posicionados exatamente sobre as partes reais. O engine do Roblox
	projeta as sombras desses clones naturalmente.
	
	- Só ativa em primeira pessoa (via ClientBridge.EstaEmPrimeiraPessoa)
	- Sem memory leaks: limpa tudo no respawn/saída de 1ª pessoa
	- Apenas Head + acessórios da cabeça
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local ClientBridge = require(
	ReplicatedStorage:WaitForChild("Modulos"):WaitForChild("Core"):WaitForChild("ClientBridge")
)
local ProjetorSombra = require(
	ReplicatedStorage:WaitForChild("Modulos"):WaitForChild("Cliente"):WaitForChild("Visual"):WaitForChild("ProjetorSombra")
)

-- ═══════════════════════════════════════════════════════════════════
-- ESTADO
-- ═══════════════════════════════════════════════════════════════════

local projector: Model = Instance.new("Model")
projector.Name = "ShadowProjector"

local activeChar: Model? = nil
local registry: { [BasePart]: BasePart } = {} -- parte real → clone de sombra
local charConnections: { RBXScriptConnection } = {}
local wasActive = false

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES INTERNAS
-- ═══════════════════════════════════════════════════════════════════

--- Cria clone de sombra para uma parte
local function createShadowClone(part: BasePart): BasePart
	local clone = part:Clone()
	clone.Anchored = true
	clone.CanCollide = false
	clone.CanTouch = false
	clone.CanQuery = false
	clone.CastShadow = true
	clone.Transparency = math.huge

	-- Remove joints desnecessários
	for _, child in clone:GetChildren() do
		if child:IsA("JointInstance") or child:IsA("Weld") or child:IsA("WeldConstraint") then
			child:Destroy()
		end
	end

	-- Highlight invisível força o engine a manter o mesh no shadow map
	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.Parent = clone

	clone.Parent = projector
	return clone
end

--- Registra uma parte para projeção de sombra
local function registerPart(part: BasePart)
	if registry[part] then return end
	registry[part] = createShadowClone(part)
end

--- Remove o clone de uma parte
local function unregisterPart(part: BasePart)
	local clone = registry[part]
	if clone then
		clone:Destroy()
		registry[part] = nil
	end
end

--- Processa um child do character
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

--- Limpa tudo
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

--- Ativa projeção (mostra clones)
local function activate()
	if wasActive then return end
	wasActive = true
	projector.Parent = camera
end

--- Desativa projeção (esconde clones)
local function deactivate()
	if not wasActive then return end
	wasActive = false
	projector.Parent = nil
end

--- Atualiza posição dos clones a cada frame
local function update()
	if not activeChar then
		deactivate()
		return
	end

	-- Verifica se está em primeira pessoa
	local emPrimeiraPessoa = ClientBridge.EstaEmPrimeiraPessoa
		and ClientBridge.EstaEmPrimeiraPessoa()
		or false

	if not emPrimeiraPessoa then
		deactivate()
		return
	end

	activate()

	-- Atualiza CFrame dos clones para acompanhar as partes reais
	for realPart, shadowClone in registry do
		if realPart.Parent and realPart:IsDescendantOf(activeChar) then
			shadowClone.CFrame = realPart.CFrame
		else
			-- Parte foi removida do character
			shadowClone:Destroy()
			registry[realPart] = nil
		end
	end
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
	local addConn = char.ChildAdded:Connect(function(child)
		task.defer(processChild, child)
	end)
	table.insert(charConnections, addConn)

	-- Escuta partes removidas
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

-- ═══════════════════════════════════════════════════════════════════
-- INICIALIZAÇÃO
-- ═══════════════════════════════════════════════════════════════════

if player.Character then
	onCharacterAdded(player.Character)
end

player.CharacterAdded:Connect(onCharacterAdded)
player.CharacterRemoving:Connect(cleanup)
RunService:BindToRenderStep("HeadShadowProjection", Enum.RenderPriority.Camera.Value + 1, update)
