-- services
local StarterGui = game:GetService("StarterGui")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

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

-- Drop state
local isDropping = false
local dropConn = nil
local dropStart = 0
local dropTool = nil
local DROP_MAX = 2 -- segundos para completar 100%
local DROP_MIN_THRESHOLD = 0.1 -- segundos mínimos para reconhecer um hold

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
local function finalizeDrop(tool, elapsed, dropFrame)
	if not tool then
		return
	end
	local dadosFolder = tool:FindFirstChild("Dados")
	if not dadosFolder then
		return
	end
	local quantidadeValue = dadosFolder:FindFirstChild("Quantidade")
	local total = quantidadeValue and quantidadeValue.Value or 1
	local fraction = math.clamp(elapsed / DROP_MAX, 0, 1)
	local amountToDrop
	if elapsed < DROP_MIN_THRESHOLD then
		amountToDrop = 1
	else
		amountToDrop = math.floor(total * fraction)
		if amountToDrop < 1 then
			amountToDrop = 1
		end
	end
	if amountToDrop >= 1 then
		DroparToolEvent:FireServer(tool.Name, amountToDrop)
	end
	if dropFrame then
		dropFrame.Visible = false
	end
end

local function handlePartialDrop(_, inputState, _)
	if inputState == Enum.UserInputState.Begin then
		if isDropping then
			return Enum.ContextActionResult.Sink
		end

		local tool = getToolEquipped()
		if not tool then
			return Enum.ContextActionResult.Sink
		end

		-- Verificar se o Tool é do tipo 'ArmasEquipadas' (não pode dropar arma equipada)
		local dadosFolder = tool:FindFirstChild("Dados")
		if dadosFolder then
			local tipoValue = dadosFolder:FindFirstChild("Tipo")
			if tipoValue and tipoValue.Value == "ArmasEquipadas" then
				return Enum.ContextActionResult.Sink
			end
		end

		if not dadosFolder then
			warn("[InventoryController] Tool sem pasta 'Dados' - usando sistema padrão")
			return Enum.ContextActionResult.Pass
		end

		-- localizar frame do slot no hotBar
		local slotIndex = inventoryHandler:getToolPosition(tool)
		local slotFrame = nil
		if slotIndex then
			slotFrame = hotBar:FindFirstChild(tostring(slotIndex))
		end
		if not slotFrame then
			local toolObj = inventoryHandler.OBJECTS
				and inventoryHandler.OBJECTS.HotBar
				and inventoryHandler.OBJECTS.HotBar[slotIndex]
			slotFrame = toolObj and toolObj.Frame
		end

		local dropFrame = nil
		if slotFrame then
			dropFrame = slotFrame:FindFirstChild("DropProgress")
			if not dropFrame then
				dropFrame = Instance.new("Frame")
				dropFrame.Name = "DropProgress"
				dropFrame.AnchorPoint = Vector2.new(0, 1)
				dropFrame.Position = UDim2.new(0, 0, 1, 0)
				dropFrame.Size = UDim2.new(1, 0, 0, 0)
				dropFrame.BackgroundColor3 = Color3.new(1, 1, 1)
				dropFrame.BackgroundTransparency = 0.8
				dropFrame.BorderSizePixel = 0
				dropFrame.ZIndex = slotFrame.ZIndex and slotFrame.ZIndex + 1 or 5
				dropFrame.Visible = false
				dropFrame.Parent = slotFrame
			end
			dropFrame.Visible = true
		end

		-- iniciar o processo de hold
		isDropping = true
		dropStart = tick()
		dropTool = tool

		dropConn = RunService.RenderStepped:Connect(function()
			if not isDropping then
				return
			end
			local elapsed = tick() - dropStart
			if not dropTool or not dropTool.Parent then
				-- ferramenta removida/cancelada
				isDropping = false
				if dropConn then
					dropConn:Disconnect()
					dropConn = nil
				end
				if dropFrame then
					dropFrame.Visible = false
				end
				dropTool = nil
				return
			end

			local fraction = math.clamp(elapsed / DROP_MAX, 0, 1)
			if dropFrame then
				dropFrame.Size = UDim2.new(1, 0, fraction, 0)
				dropFrame.Position = UDim2.new(0, 0, 1, 0)
			end

			if fraction >= 1 then
				finalizeDrop(dropTool, elapsed, dropFrame)
				isDropping = false
				if dropConn then
					dropConn:Disconnect()
					dropConn = nil
				end
				dropTool = nil
			end
		end)

		return Enum.ContextActionResult.Sink
	elseif inputState == Enum.UserInputState.End then
		if not isDropping then
			return Enum.ContextActionResult.Sink
		end

		local elapsed = tick() - dropStart
		local slotIndex = dropTool and inventoryHandler:getToolPosition(dropTool)
		local slotFrame = slotIndex and hotBar:FindFirstChild(tostring(slotIndex))
		local dropFrame = slotFrame and slotFrame:FindFirstChild("DropProgress")

		finalizeDrop(dropTool, elapsed, dropFrame)

		isDropping = false
		if dropConn then
			dropConn:Disconnect()
			dropConn = nil
		end
		dropTool = nil

		return Enum.ContextActionResult.Sink
	end

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

		-- Bloqueia troca por scroll se não pode alterar tool
		if _G.PodeAlterarTool and not _G.PodeAlterarTool() then
			return
		end

		for i = toolPosition + direction, direction < 0 and 1 or inventoryHandler.slotAmount, direction do
			local toolObject = inventoryHandler.OBJECTS.HotBar[i]
			if toolObject and humanoid then
				humanoid:EquipTool(toolObject.Tool)
				break
			end
		end
	end
end)
