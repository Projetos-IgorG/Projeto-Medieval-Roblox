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
local Hud = require(script.Parent.Parent:WaitForChild("Principal"):WaitForChild("HudConfig") :: ModuleScript)

local function IsAlreadyEquipped(tool: Tool): boolean
	local char = player.Character
	if not char then
		return false
	end
	local equipamento = char:FindFirstChild("Equipamento")
	if not equipamento then
		return false
	end
	local bracos = equipamento:FindFirstChild("Bracos")
	local corpo = equipamento:FindFirstChild("Corpo")

	if bracos then
		local rightArm = bracos:FindFirstChild("RightArm") :: ObjectValue
		local leftArm = bracos:FindFirstChild("LeftArm") :: ObjectValue
		if (rightArm and rightArm.Value == tool) or (leftArm and leftArm.Value == tool) then
			return true
		end
	end

	if corpo then
		for _, ov in ipairs(corpo:GetChildren()) do
			if ov:IsA("ObjectValue") and ov.Value == tool then
				return true
			end
		end
	end

	return false
end

local Modulos = ReplicatedStorage
local ModEquip = require(Modulos:WaitForChild("SistemaItens"):WaitForChild("ValidacaoEquipamentos") :: ModuleScript)

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
local itensFrame: Instance?

local imagensOriginaisSlots: { [string]: string } = {}

local equipOVs: { [string]: ObjectValue } = {}

local ovConexoes: { RBXScriptConnection } = {}

local charConexoes: { RBXScriptConnection } = {}

local EquipmentHelpers =
	require(ReplicatedStorage:WaitForChild("SistemaItens"):WaitForChild("LeituraDadosEquipamento") :: ModuleScript)

local LerTipo = EquipmentHelpers.LerTipo
local LerNome = EquipmentHelpers.LerNome
local DeveInterceptar = EquipmentHelpers.DeveInterceptar

local SLOT_UI_MAP = {
	-- [nome do botao no Studio] = "nome canonico do OV no servidor"
	["RightArm"] = "RightArm",
	["LeftArm"] = "LeftArm",
	["Head"] = "Head",
	["Torso"] = "Torso",
	["Leg"] = "Legs", -- botao chama-se "Leg", OV do servidor chama-se "Legs"
	["Foot"] = "Foot",
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
		if DEBUG_ENABLED then
			print("[Equip:CLIENTE] ⛔ '", tool.Name, "' ignorado: nao reconhecido como Arma ou Armadura")
			print("  Id Attribute:", tostring(tool:GetAttribute("Id")), "| Tipo resolvido: nil")
		end
		return
	end

	if DEBUG_ENABLED then
		print("[Equip:CLIENTE] ✓ '", tool.Name, "' registrado para interceptar")
		print("  Id:", tostring(tool:GetAttribute("Id")), "| Tipo:", tipo)
	end

	local conexoes = {}

	local activated = tool.Activated:Connect(function()
		local agora = os.clock()
		if (agora - ultimoEquipar) < DEBOUNCE_EQUIPAR then
			if DEBUG_ENABLED then
				print("[Equip:CLIENTE] ⏳ Debounce ativo, clique ignorado")
			end
			return
		end
		ultimoEquipar = agora

		if tipo == "Armas" then
			if DEBUG_ENABLED then
				print("[Equip:CLIENTE] 🗡️ Arma clicada:")
				print("  Nome:", tool.Name)
				print("  Id:", tostring(tool:GetAttribute("Id")))
				print("  Acao enviada: EquiparArma (servidor decidira RightArm ou LeftArm por categoria)")
			end
			EquipamentoAcao:FireServer("EquiparArma", tool)
		elseif tipo == "Armaduras" then
			if DEBUG_ENABLED then
				print("[Equip:CLIENTE] 🛡️ Armadura clicada:")
				print("  Nome:", tool.Name)
				print("  Id:", tostring(tool:GetAttribute("Id")))
				print("  Acao enviada: EquiparArmadura (servidor decidira qual slot de corpo)")
			end
			EquipamentoAcao:FireServer("EquiparArmadura", tool)
		end
	end)
	table.insert(conexoes, activated)

	toolConexoes[tool] = conexoes
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
		if child:IsA("Tool") and DeveInterceptar(child) and not IsAlreadyEquipped(child) then
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
		if child:IsA("Tool") and DeveInterceptar(child) and not IsAlreadyEquipped(child) then
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

	-- "Icone": ImageLabel filho do ImageButton do slot — exibe a textura do item equipado
	-- "Nome":  TextLabel filho — exibe o nome do item (tooltip/hover)
	local icone = slotButton:FindFirstChild("Icone") :: ImageLabel
	local toolName = slotButton:FindFirstChild("Nome") :: TextLabel

	if toolRef and toolRef.Parent then
		local textureId = toolRef.TextureId or toolRef:GetAttribute("TextureId") or ""

		-- Esconde o outline/background do ImageButton para so aparecer o Icone do item
		slotButton.ImageTransparency = 1

		if textureId == "" and itensFrame then
			local nameToSearch = toolRef.Name
			local foundIcon = nil

			-- 1. Procurar na Hotbar
			local hotbar = itensFrame:FindFirstChild("Hotbar")
			if hotbar then
				local hotbarBtn = hotbar:FindFirstChild(nameToSearch)
				if hotbarBtn then
					local iconeLabel = hotbarBtn:FindFirstChild("Icone")
					if iconeLabel and iconeLabel:IsA("ImageLabel") and iconeLabel.Image ~= "" then
						foundIcon = iconeLabel.Image
					end
				end
			end

			-- 2. Procurar no Inventario Scroll
			if not foundIcon then
				local inventoryFrame = itensFrame:FindFirstChild("Inventory")
				local scrollFrame = inventoryFrame and inventoryFrame:FindFirstChild("ScrollingFrame")
				if scrollFrame then
					local invBtn = scrollFrame:FindFirstChild(nameToSearch)
					if invBtn then
						local iconeLabel = invBtn:FindFirstChild("Icone")
						if iconeLabel and iconeLabel:IsA("ImageLabel") and iconeLabel.Image ~= "" then
							foundIcon = iconeLabel.Image
						end
					end
				end
			end

			if foundIcon then
				textureId = foundIcon
			end
		end

		if icone then
			if textureId ~= "" then
				icone.Image = textureId
				icone.Visible = true
			else
				icone.Image = ""
				icone.Visible = false
			end
		end

		if toolName then
			toolName.Text = LerNome(toolRef)
			toolName.Visible = true
		end

		slotButton.BackgroundColor3 = COR_SLOT_OCUPADO
		DebugPrint(
			"[EquipamentoController] Slot UI atualizado:",
			slotName,
			"->",
			LerNome(toolRef),
			"| Icone:",
			textureId
		)
	else
		-- Restaura a imagem original do botao (outline vazio)
		slotButton.ImageTransparency = 0
		slotButton.Image = imagensOriginaisSlots[uiName] or ""

		if icone then
			icone.Image = ""
			icone.Visible = false
		end

		if toolName then
			toolName.Text = ""
			toolName.Visible = false -- Oculta para esconder o UiShadow do slot vazio
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
		if ClientBridge.PodeAlterarTool and not ClientBridge.PodeAlterarTool() then
			if DEBUG_ENABLED then
				print("[Equip:CLIENTE] Clique de desequipar slot ignorado - em animacao")
			end
			return
		end

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
		warn("[EquipamentoController] Equipamento folder nao encontrado no Character!")
		return
	end
	if DEBUG_ENABLED then
		print("[Equip:CLIENTE] Pasta Equipamento encontrada no Character")
	end

	local bracos = equipamento:WaitForChild("Bracos", 5)
	local corpo = equipamento:WaitForChild("Corpo", 5)

	if bracos then
		if DEBUG_ENABLED then
			print("[Equip:CLIENTE] Bracos OVs:")
		end
		for _, ov in ipairs(bracos:GetChildren()) do
			if ov:IsA("ObjectValue") then
				equipOVs[ov.Name] = ov
				AtualizarSlotUI(ov.Name, ov.Value)
				if DEBUG_ENABLED then
					print("  OV:", ov.Name, "| valor atual:", tostring(ov.Value))
				end

				local conn = ov:GetPropertyChangedSignal("Value"):Connect(function()
					if DEBUG_ENABLED then
						print("[Equip:CLIENTE] OV mudou! Slot:", ov.Name, "| novo valor:", tostring(ov.Value))
					end
					AtualizarSlotUI(ov.Name, ov.Value)
				end)
				table.insert(ovConexoes, conn)
			end
		end
	end

	if corpo then
		if DEBUG_ENABLED then
			print("[Equip:CLIENTE] Corpo OVs:")
		end
		for _, ov in ipairs(corpo:GetChildren()) do
			if ov:IsA("ObjectValue") then
				equipOVs[ov.Name] = ov
				AtualizarSlotUI(ov.Name, ov.Value)
				if DEBUG_ENABLED then
					print("  OV:", ov.Name, "| valor atual:", tostring(ov.Value))
				end

				local conn = ov:GetPropertyChangedSignal("Value"):Connect(function()
					if DEBUG_ENABLED then
						print("[Equip:CLIENTE] OV mudou! Slot:", ov.Name, "| novo valor:", tostring(ov.Value))
					end
					AtualizarSlotUI(ov.Name, ov.Value)
				end)
				table.insert(ovConexoes, conn)
			end
		end
	end

	if DEBUG_ENABLED then
		print("[Equip:CLIENTE] OVs conectados. Total:", #ovConexoes)
	end
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
	if DEBUG_ENABLED then
		print("[Equip:CLIENTE] InicializarUI iniciando...")
	end

	local customInventory = script.Parent.Parent:WaitForChild("HUD", 15)
	if not customInventory then
		warn("[EquipamentoController] HUD nao encontrada!")
		return
	end
	if DEBUG_ENABLED then
		print("[Equip:CLIENTE] HUD encontrado:", customInventory:GetFullName())
	end

	itensFrame = customInventory:WaitForChild("ItensFrame", 10)
	local equipmentInventory = itensFrame and itensFrame:WaitForChild("EquipamentoFrame", 10)
	if not equipmentInventory then
		warn("[EquipamentoController] EquipamentoFrame nao encontrada! UI de equipamento nao sera funcional.")
		if DEBUG_ENABLED then
			print("  ItensFrame encontrado:", itensFrame ~= nil)
			if itensFrame then
				print("  Filhos de ItensFrame:")
				for _, c in itensFrame:GetChildren() do
					print("    -", c.Name, "(", c.ClassName, ")")
				end
			end
		end
		return
	end
	if DEBUG_ENABLED then
		print("[Equip:CLIENTE] EquipamentoFrame encontrado")
	end

	local bodyEquipment = equipmentInventory:WaitForChild("BodyEquipment", 10)

	if bodyEquipment then
		if DEBUG_ENABLED then
			print("[Equip:CLIENTE] BodyEquipment encontrado. Filhos:")
			for _, c in bodyEquipment:GetChildren() do
				local noMapa = SLOT_UI_MAP[c.Name] and ("-> " .. SLOT_UI_MAP[c.Name]) or "(NAO no SLOT_UI_MAP)"
				print("  -", c.Name, "(", c.ClassName, ")", noMapa)
			end
		end

		for _, child in ipairs(bodyEquipment:GetChildren()) do
			if child:IsA("ImageButton") or child:IsA("TextButton") or child:IsA("Frame") then
				if SLOT_UI_MAP[child.Name] then
					slotsUI[child.Name] = child :: ImageButton
					imagensOriginaisSlots[child.Name] = (child :: ImageButton).Image
					ConectarSlotClick(child.Name, child :: ImageButton)
					if DEBUG_ENABLED then
						print("[Equip:CLIENTE] Slot UI mapeado:", child.Name, "->", SLOT_UI_MAP[child.Name])
					end

					-- Registro de hover do HudConfig
					local labelNome = child:FindFirstChild("Nome") or child:FindFirstChild("toolName")
					if labelNome then
						labelNome.Name = "Nome" -- Garante nome canonico para Hud.registrarSlot
						Hud.registrarSlot(child, -0.4)
					end
				end
			end
		end
	else
		warn("[EquipamentoController] BodyEquipment nao encontrado!")
		if DEBUG_ENABLED then
			print("  Filhos de EquipamentoFrame:")
			for _, c in equipmentInventory:GetChildren() do
				print("    -", c.Name, "(", c.ClassName, ")")
			end
		end
	end

	local numSlots = 0
	for _ in pairs(slotsUI) do
		numSlots += 1
	end
	if DEBUG_ENABLED then
		print("[Equip:CLIENTE] UI inicializada. Slots mapeados:", numSlots)
	end
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
