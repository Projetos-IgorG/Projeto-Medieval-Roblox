-- services
local StarterGui = game:GetService("StarterGui")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

-- references
local player = game:GetService("Players").LocalPlayer
local backpack = player:WaitForChild("Backpack")
local camera = workspace.CurrentCamera

-- DISABLE BASIC ROBLOX HOTBAR
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

local CustomInventoryGUI = script.Parent
local hotBar = CustomInventoryGUI.hotBar
local Inventory = CustomInventoryGUI.Inventory
local toolButton = script.toolButton

local inventoryHandler = require(script.Parent.SETTINGS)

local function showSlots()
	for index = 1, inventoryHandler.slotAmount do
		local toolObject = inventoryHandler.OBJECTS.HotBar[index]
		if not toolObject and not hotBar:FindFirstChild(index) and index <= inventoryHandler.slotAmount then
			local frame = toolButton:Clone()
			frame.toolName.Text = ""
			frame.toolAmount.Text = ""
			frame.toolNumber.Text = index
			frame.Name = index
			frame.Parent = hotBar
		end
	end
end
local function removeEmptySlots()
	for index = 1, 9 do
		local toolObject = inventoryHandler.OBJECTS.HotBar[index]
		local toolFrame = hotBar:FindFirstChild(index)
		if not toolObject and toolFrame then
			toolFrame:Destroy()
			if hotBar:FindFirstChild(index) then
				removeEmptySlots()
			end
		end
	end
end

local function manageInventory(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		Inventory.Visible = not Inventory.Visible
		local currentState = Inventory.Visible

		inventoryHandler:removeCurrentDescription()
		if currentState then
			showSlots()
			CustomInventoryGUI.openButton.Position = UDim2.fromScale(0.5, 0.5)
			CustomInventoryGUI.openButton.info.Text = "(') close inventory"
		else
			if not inventoryHandler.SETTINGS.SHOW_EMPTY_TOOL_FRAMES_IN_HOTBAR then
				removeEmptySlots()
			end
			CustomInventoryGUI.openButton.Position = UDim2.fromScale(0.5, 0.909)
			CustomInventoryGUI.openButton.info.Text = "(') open inventory"
		end
	elseif not inputState then
		for index = inventoryHandler.slotAmount + 1, inventoryHandler.slotAmount do
			local toolObject = inventoryHandler.OBJECTS.HotBar[index]
			local toolFrame = hotBar:FindFirstChild(index)
			if toolObject then
				local tool = toolObject.Tool
				toolObject:DisconnectAll()
				tool:SetAttribute("toolAdded", nil)
				inventoryHandler:newTool(tool)
			elseif toolFrame then
				toolFrame:Destroy()
			end
		end
	end
end

local function searchTool()
	inventoryHandler:searchTool()
end
local function newTool(tool)
	if tool:IsA("Tool") then
		inventoryHandler:newTool(tool)
	end
end

local function reloadInventory(character)
	inventoryHandler.currentlyEquipped = nil
	backpack = player:WaitForChild("Backpack")

	for _, tool in pairs(backpack:GetChildren()) do
		if tool:IsA("Tool") then
			newTool(tool)
		end
	end
	backpack.ChildAdded:Connect(newTool)
	character.ChildAdded:Connect(newTool)
end
local function updateHudPosition()
	local slotSize = UDim2.fromOffset(hotBar.AbsoluteSize.Y, hotBar.AbsoluteSize.Y)

	Inventory.Frame.Grid.CellSize = slotSize
	hotBar.Grid.CellSize = slotSize

	manageInventory()
end

updateHudPosition()
updateHudPosition()
reloadInventory(player.Character or player.CharacterAdded:Wait())
camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateHudPosition)
player.CharacterAdded:Connect(reloadInventory)
Inventory.SearchBox:GetPropertyChangedSignal("Text"):Connect(searchTool)
if inventoryHandler.SETTINGS.SHOW_EMPTY_TOOL_FRAMES_IN_HOTBAR then
	showSlots()
end
if inventoryHandler.SETTINGS.INVENTORY_KEYBIND then
	ContextActionService:BindAction(
		"manageInventory",
		manageInventory,
		false,
		inventoryHandler.SETTINGS.INVENTORY_KEYBIND
	)
end
if inventoryHandler.SETTINGS.OPEN_BUTTON then
	CustomInventoryGUI.openButton.MouseButton1Down:Connect(function()
		Inventory.Visible = not Inventory.Visible
		local currentState = Inventory.Visible

		inventoryHandler:removeCurrentDescription()
		if currentState then
			showSlots()
			CustomInventoryGUI.openButton.Position = UDim2.fromScale(0.5, 0.5)
			CustomInventoryGUI.openButton.info.Text = "(') close inventory"
		else
			if not inventoryHandler.SETTINGS.SHOW_EMPTY_TOOL_FRAMES_IN_HOTBAR then
				removeEmptySlots()
			end
			CustomInventoryGUI.openButton.Position = UDim2.fromScale(0.5, 0.909)
			CustomInventoryGUI.openButton.info.Text = "(') open inventory"
		end
	end)
else
	CustomInventoryGUI.openButton.Visible = false
end

local function getToolEquipped()
	local character = player.Character
	return character and character:FindFirstChildOfClass("Tool")
end

-- ============================================
-- SISTEMA DE DROP CUSTOMIZADO
-- ============================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotos = ReplicatedStorage:WaitForChild("Remotos")
local DroparToolEvent = Remotos:WaitForChild("DroparTool")

-- Use ContextActionService to capture Backspace and block the default Roblox drop action.
-- This ensures the engine's drop won't race with our custom logic.
local function handlePartialDrop(_, inputState, _)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end

	local tool = getToolEquipped()
	if not tool then
		return Enum.ContextActionResult.Sink
	end

	-- Verificar se o Tool tem a pasta "Dados" (é um Tool customizado)
	local dadosFolder = tool:FindFirstChild("Dados")
	if not dadosFolder then
		warn("[InventoryController] Tool sem pasta 'Dados' - usando sistema padrão")
		return Enum.ContextActionResult.Pass -- Permitir drop padrão do Roblox
	end

	-- Extrair quantidade do Tool
	local quantidadeValue = dadosFolder:FindFirstChild("Quantidade")
	local amount = quantidadeValue and quantidadeValue.Value or 1

	-- Determinar quanto dropar
	local quantidadeDropar = 1 -- Por padrão, dropa 1 unidade

	-- Se shift está pressionado e tem mais de 1, dropa tudo
	local shiftPressed = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
	if shiftPressed and amount > 1 then
		quantidadeDropar = amount
	end

	-- Chamar o servidor para processar o drop
	DroparToolEvent:FireServer(tool.Name, quantidadeDropar)

	return Enum.ContextActionResult.Sink
end

ContextActionService:BindAction("PartialDrop", handlePartialDrop, false, Enum.KeyCode.Backspace)

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseWheel and inventoryHandler.SETTINGS.SCROLL_HOTBAR_WITH_WHEEL then
		local direction = input.Position.Z
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")

		local toolEquipped = getToolEquipped()
		local toolPosition = inventoryHandler:getToolPosition(toolEquipped) or 0

		for i = toolPosition + direction, direction < 0 and 1 or inventoryHandler.slotAmount, direction do
			local toolObject = inventoryHandler.OBJECTS.HotBar[i]
			if toolObject and humanoid then
				humanoid:EquipTool(toolObject.Tool)
				break
			end
		end
	end
end)
