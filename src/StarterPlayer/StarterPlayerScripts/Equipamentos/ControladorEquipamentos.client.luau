--[[
    Script: ControladorEquipamentos.client.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/Equipamentos
    Responsabilidade: Controla entrada, selecao e feedback local de equipamentos do jogador.
    Uso: LocalScript; roda automaticamente para o jogador local em src/StarterPlayer/StarterPlayerScripts/Equipamentos.
    Nao faz: Nao valida autoridade do servidor, nao salva dados persistentes e nao substitui regras server-side.
    Funcoes principais: ObterEquipamentoBraco, ObterCategoriaRightArm, ObterEquipamentoCorpo, ConectarToolActivated, DesconectarToolActivated, MonitorarCharacter
]]
local DEBUG_ENABLED = false

local function DebugPrint(...)
	if DEBUG_ENABLED then
		print(...)
	end
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientBridge =
	require(ReplicatedStorage:WaitForChild("Jogador"):WaitForChild("ComunicacaoCliente"):WaitForChild("PonteCliente"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Modulos = ReplicatedStorage
local ModEquip = require(Modulos:WaitForChild("Equipamentos"):WaitForChild("ValidacaoEquipamentos"))

local Remotos = ReplicatedStorage:WaitForChild("Remotos")
local EquipamentoAcao = Remotos:WaitForChild("EquipamentoAcao")

local DEBOUNCE_EQUIPAR = 0.5
local DEBOUNCE_DESEQUIPAR = 0.5

local COR_SLOT_VAZIO = Color3.fromRGB(40, 40, 40)
local COR_SLOT_OCUPADO = Color3.fromRGB(80, 120, 80)
local COR_SLOT_HIGHLIGHT = Color3.fromRGB(200, 200, 100)

local ultimoEquipar = 0
local ultimoDesequipar = 0

local toolConexoes: { [Tool]: { RBXScriptConnection } } = {}

local slotsUI: { [string]: ImageButton } = {}

local imagensOriginaisSlots: { [string]: string } = {}

local equipOVs: { [string]: ObjectValue } = {}

local ovConexoes: { RBXScriptConnection } = {}

local charConexoes: { RBXScriptConnection } = {}

local EquipmentHelpers = require(ReplicatedStorage:WaitForChild("Equipamentos"):WaitForChild("LeituraDadosEquipamento"))

local LerTipo = EquipmentHelpers.LerTipo
local LerNome = EquipmentHelpers.LerNome
local DeveInterceptar = EquipmentHelpers.DeveInterceptar

local SLOT_UI_MAP = {
	["1RightArm"] = "RightArm",
	["2LeftArm"] = "LeftArm",
	["1Head"] = "Head",
	["2Torso"] = "Torso",
	["3Leg"] = "Legs",
	["4Foot"] = "Foot",
}

local SLOT_CANONICO_PARA_UI = {}
for uiName, canonicoName in pairs(SLOT_UI_MAP) do
	SLOT_CANONICO_PARA_UI[canonicoName] = uiName
end

local function ConectarToolActivated(tool: Tool)
	if toolConexoes[tool] then
		return
	end

	local tipo = LerTipo(tool)
	if not tipo then
		return
	end

	local conexoes = {}

	local activated = tool.Activated:Connect(function()
		local agora = os.clock()
		if (agora - ultimoEquipar) < DEBOUNCE_EQUIPAR then
			DebugPrint("[EquipamentoController] Debounce: equipar muito rápido")
			return
		end
		ultimoEquipar = agora

		if tipo == "Armas" then
			DebugPrint("[EquipamentoController] Tool.Activated -> EquiparArma:", tool.Name)
			EquipamentoAcao:FireServer("EquiparArma", tool)
		elseif tipo == "Armaduras" then
			DebugPrint("[EquipamentoController] Tool.Activated -> EquiparArmadura:", tool.Name)
			EquipamentoAcao:FireServer("EquiparArmadura", tool)
		end
	end)
	table.insert(conexoes, activated)

	toolConexoes[tool] = conexoes
	DebugPrint("[EquipamentoController] Conectado Tool.Activated para:", tool.Name, "Tipo:", tipo)
end

local function DesconectarToolActivated(tool: Tool)
	local conexoes = toolConexoes[tool]
	if not conexoes then
		return
	end

	for _, conn in ipairs(conexoes) do
		conn:Disconnect()
	end
	toolConexoes[tool] = nil
	DebugPrint("[EquipamentoController] Desconectado Tool.Activated para:", tool.Name)
end

local function MonitorarCharacter(character: Model)

	for _, conn in ipairs(charConexoes) do
		conn:Disconnect()
	end
	table.clear(charConexoes)

	for tool, _ in pairs(toolConexoes) do
		DesconectarToolActivated(tool)
	end

	local addedConn = character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and DeveInterceptar(child) then
			ConectarToolActivated(child)
		end
	end)
	table.insert(charConexoes, addedConn)

	local removedConn = character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			DesconectarToolActivated(child)
		end
	end)
	table.insert(charConexoes, removedConn)

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and DeveInterceptar(child) then
			ConectarToolActivated(child)
		end
	end
end

local function AtualizarSlotUI(slotName: string, toolRef: Tool?)
	local uiName = SLOT_CANONICO_PARA_UI[slotName]
	if not uiName then
		return
	end

	local slotButton = slotsUI[uiName]
	if not slotButton then
		return
	end

	local toolIcon = slotButton:FindFirstChild("toolIcon") :: ImageLabel
	local toolName = slotButton:FindFirstChild("toolName") :: TextLabel

	if toolRef and toolRef.Parent then

		local textureId = toolRef.TextureId

		if textureId and textureId ~= "" then
			slotButton.Image = textureId
		end

		if toolIcon then
			if textureId and textureId ~= "" then
				toolIcon.Image = textureId
				toolIcon.Visible = true
			else
				toolIcon.Image = ""
				toolIcon.Visible = false
			end
		end

		if toolName then
			toolName.Text = LerNome(toolRef)
			toolName.Visible = true
		end

		slotButton.BackgroundColor3 = COR_SLOT_OCUPADO
		local nomeExibicao = LerNome(toolRef)
		DebugPrint("[EquipamentoController] Slot UI atualizado:", slotName, "->", nomeExibicao)
	else

		slotButton.Image = imagensOriginaisSlots[uiName] or ""

		if toolIcon then
			toolIcon.Image = ""
			toolIcon.Visible = false
		end

		if toolName then
			toolName.Text = ""
			toolName.Visible = false
		end

		slotButton.BackgroundColor3 = COR_SLOT_VAZIO
		DebugPrint("[EquipamentoController] Slot UI limpo:", slotName)
	end
end

local function ConectarSlotClick(uiName: string, slotButton: ImageButton)
	local canonicoName = SLOT_UI_MAP[uiName]
	if not canonicoName then
		return
	end

	slotButton.MouseButton1Click:Connect(function()
		local agora = os.clock()
		if (agora - ultimoDesequipar) < DEBOUNCE_DESEQUIPAR then
			DebugPrint("[EquipamentoController] Debounce: desequipar muito rápido")
			return
		end

		local ov = equipOVs[canonicoName]
		if not ov or not ov.Value then
			DebugPrint("[EquipamentoController] Slot vazio, nada para desequipar:", canonicoName)
			return
		end

		ultimoDesequipar = agora
		DebugPrint("[EquipamentoController] Desequipar slot:", canonicoName)

		slotButton.BackgroundColor3 = COR_SLOT_HIGHLIGHT
		task.delay(0.2, function()

			if slotButton and slotButton.Parent then

				if ov and ov.Value then
					slotButton.BackgroundColor3 = COR_SLOT_OCUPADO
				else
					slotButton.BackgroundColor3 = COR_SLOT_VAZIO
				end
			end
		end)

		EquipamentoAcao:FireServer("DesequiparSlot", canonicoName)
	end)
end

local function ConectarEquipamentoOVs(character: Model)

	for _, conn in ipairs(ovConexoes) do
		conn:Disconnect()
	end
	table.clear(ovConexoes)
	table.clear(equipOVs)

	local equipamento = character:WaitForChild("Equipamento", 10)
	if not equipamento then
		warn("[EquipamentoController] Equipamento folder não encontrado no Character!")
		return
	end

	local bracos = equipamento:WaitForChild("Bracos", 5)
	local corpo = equipamento:WaitForChild("Corpo", 5)

	if bracos then
		for _, ov in ipairs(bracos:GetChildren()) do
			if ov:IsA("ObjectValue") then
				equipOVs[ov.Name] = ov

				AtualizarSlotUI(ov.Name, ov.Value)

				local conn = ov:GetPropertyChangedSignal("Value"):Connect(function()
					AtualizarSlotUI(ov.Name, ov.Value)
				end)
				table.insert(ovConexoes, conn)
			end
		end
	end

	if corpo then
		for _, ov in ipairs(corpo:GetChildren()) do
			if ov:IsA("ObjectValue") then
				equipOVs[ov.Name] = ov

				AtualizarSlotUI(ov.Name, ov.Value)

				local conn = ov:GetPropertyChangedSignal("Value"):Connect(function()
					AtualizarSlotUI(ov.Name, ov.Value)
				end)
				table.insert(ovConexoes, conn)
			end
		end
	end

	DebugPrint("[EquipamentoController] ObjectValues do Equipamento conectados")
end

ClientBridge.ObterEquipamentoBraco = function(slot: string): Tool?
	local ov = equipOVs[slot]
	if ov and ov.Value then
		return ov.Value :: Tool
	end
	return nil
end

ClientBridge.ObterCategoriaRightArm = function(): string?
	local ov = equipOVs["RightArm"]
	if not ov or not ov.Value then
		return nil
	end
	return ModEquip.LerCategoria(ov.Value)
end

ClientBridge.ObterEquipamentoCorpo = function(slot: string): Tool?
	local ov = equipOVs[slot]
	if ov and ov.Value then
		return ov.Value :: Tool
	end
	return nil
end

local function InicializarUI()

	local customInventory = playerGui:WaitForChild("Inventario", 10)
	if not customInventory then
		warn("[EquipamentoController] Custom Inventory GUI não encontrada!")
		return
	end

	local inventoryFrame = customInventory:FindFirstChild("Inventario")
	local equipmentInventory = inventoryFrame and inventoryFrame:FindFirstChild("EquipmentInventory")
	if not equipmentInventory then
		warn("[EquipamentoController] EquipmentInventory não encontrada! UI de equipamento não será funcional.")
		return
	end

	local armsEquipment = equipmentInventory:FindFirstChild("ArmsEquipment")
	local bodyEquipment = equipmentInventory:FindFirstChild("BodyEquipment")

	if armsEquipment then
		for _, child in ipairs(armsEquipment:GetChildren()) do
			if child:IsA("ImageButton") or child:IsA("TextButton") or child:IsA("Frame") then
				if SLOT_UI_MAP[child.Name] then
					slotsUI[child.Name] = child :: ImageButton
					imagensOriginaisSlots[child.Name] = (child :: ImageButton).Image
					ConectarSlotClick(child.Name, child :: ImageButton)
					DebugPrint("[EquipamentoController] Slot UI mapeado:", child.Name, "->", SLOT_UI_MAP[child.Name])
				end
			end
		end
	else
		warn("[EquipamentoController] ArmsEquipment não encontrado!")
	end

	if bodyEquipment then
		for _, child in ipairs(bodyEquipment:GetChildren()) do
			if child:IsA("ImageButton") or child:IsA("TextButton") or child:IsA("Frame") then
				if SLOT_UI_MAP[child.Name] then
					slotsUI[child.Name] = child :: ImageButton
					imagensOriginaisSlots[child.Name] = (child :: ImageButton).Image
					ConectarSlotClick(child.Name, child :: ImageButton)
					DebugPrint("[EquipamentoController] Slot UI mapeado:", child.Name, "->", SLOT_UI_MAP[child.Name])
				end
			end
		end
	else
		warn("[EquipamentoController] BodyEquipment não encontrado!")
	end

	local numSlots = 0
	for _ in pairs(slotsUI) do
		numSlots += 1
	end
	DebugPrint("[EquipamentoController] UI inicializada. Slots mapeados:", numSlots)
end

local function Inicializar()
	DebugPrint("[EquipamentoController] Inicializando...")

	InicializarUI()

	local function OnCharacterAdded(character: Model)
		DebugPrint("[EquipamentoController] Character adicionado:", character.Name)

		MonitorarCharacter(character)

		ConectarEquipamentoOVs(character)
	end

	if player.Character then
		OnCharacterAdded(player.Character)
	end

	player.CharacterAdded:Connect(OnCharacterAdded)

	DebugPrint("[EquipamentoController] Inicializado com sucesso!")
end

Inicializar()
