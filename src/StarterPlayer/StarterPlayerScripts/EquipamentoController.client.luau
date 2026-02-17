--[[
	EquipamentoController.client.luau

	Controlador client-side do sistema de equipamento.
	Responsável por:
	- Interceptar Tool.Activated em Tools de Tipo "Armas" e "Armaduras"
	- Enviar RemoteEvent EquipamentoAcao para o servidor
	- Atualizar UI dos slots de equipamento (ArmsEquipment, BodyEquipment)
	- Desequipar via clique nos slots da UI
	- Expor globais _G.ObterEquipamentoBraco() e _G.ObterCategoriaRightArm()

	NÃO interfere com Tools de Tipo "ArmasEquipadas" (fluxo de combate via EntradaJogador).
]]

-- ═══════════════════════════════════════════════════════════════════
-- CONFIGURAÇÃO DE DEBUG
-- ═══════════════════════════════════════════════════════════════════
local DEBUG_ENABLED = true

local function DebugPrint(...)
	if DEBUG_ENABLED then
		print(...)
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- SERVICES
-- ═══════════════════════════════════════════════════════════════════
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ═══════════════════════════════════════════════════════════════════
-- MÓDULOS
-- ═══════════════════════════════════════════════════════════════════
local Modulos = ReplicatedStorage:WaitForChild("Modulos")
local ModEquip = require(Modulos:WaitForChild("Modulo_Equipamento"))

-- ═══════════════════════════════════════════════════════════════════
-- REMOTE EVENTS
-- ═══════════════════════════════════════════════════════════════════
local Remotos = ReplicatedStorage:WaitForChild("Remotos")
local EquipamentoAcao = Remotos:WaitForChild("EquipamentoAcao")

-- ═══════════════════════════════════════════════════════════════════
-- CONSTANTES
-- ═══════════════════════════════════════════════════════════════════
local DEBOUNCE_EQUIPAR = 0.5 -- Mínimo entre cliques de equipar (anti-spam)
local DEBOUNCE_DESEQUIPAR = 0.5 -- Mínimo entre cliques de desequipar

-- Cor padrão e highlight para os slots
local COR_SLOT_VAZIO = Color3.fromRGB(40, 40, 40)
local COR_SLOT_OCUPADO = Color3.fromRGB(80, 120, 80)
local COR_SLOT_HIGHLIGHT = Color3.fromRGB(200, 200, 100)

-- ═══════════════════════════════════════════════════════════════════
-- ESTADO LOCAL
-- ═══════════════════════════════════════════════════════════════════
local ultimoEquipar = 0
local ultimoDesequipar = 0

-- Conexões de Tool.Activated para Tools interceptados
local toolConexoes: { [Tool]: { RBXScriptConnection } } = {}

-- Referências de UI slots (preenchido em Inicializar)
local slotsUI: { [string]: ImageButton } = {}

-- Imagens originais dos slots (para restaurar quando desequipar)
local imagensOriginaisSlots: { [string]: string } = {}

-- Referências dos ObjectValues no Character.Equipamento
local equipOVs: { [string]: ObjectValue } = {}

-- Conexões de ObjectValue.Changed
local ovConexoes: { RBXScriptConnection } = {}

-- Conexões de character monitoring
local charConexoes: { RBXScriptConnection } = {}

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES UTILITÁRIAS
-- ═══════════════════════════════════════════════════════════════════

--- Lê Tipo do Tool
local function LerTipo(tool: Tool): string?
	local dados = tool:FindFirstChild("Dados")
	if not dados then
		return nil
	end
	local tipoValue = dados:FindFirstChild("Tipo")
	if tipoValue and tipoValue:IsA("StringValue") then
		return tipoValue.Value
	end
	return nil
end

--- Lê Nome amigável do Tool
local function LerNome(tool: Tool): string
	local dados = tool:FindFirstChild("Dados")
	if dados then
		local nomeValue = dados:FindFirstChild("Nome")
		if nomeValue and nomeValue:IsA("StringValue") and nomeValue.Value ~= "" then
			return nomeValue.Value
		end
	end
	return tool.Name
end

--- Verifica se um Tool deve ser interceptado pelo sistema de equipamento
local function DeveInterceptar(tool: Tool): boolean
	local tipo = LerTipo(tool)
	return tipo == "Armas" or tipo == "Armaduras"
end

--- Mapa de nomes dos slots na UI para os nomes canônicos do sistema
local SLOT_UI_MAP = {
	["1RightArm"] = "RightArm",
	["2LeftArm"] = "LeftArm",
	["1Head"] = "Head",
	["2Torso"] = "Torso",
	["3Leg"] = "Legs",
	["4Foot"] = "Foot",
}

--- Mapa inverso: slot canônico → nome na UI
local SLOT_CANONICO_PARA_UI = {}
for uiName, canonicoName in pairs(SLOT_UI_MAP) do
	SLOT_CANONICO_PARA_UI[canonicoName] = uiName
end

-- ═══════════════════════════════════════════════════════════════════
-- TOOL.ACTIVATED HANDLING
-- ═══════════════════════════════════════════════════════════════════

--- Conecta Tool.Activated para interceptar M1 em Armas/Armaduras
local function ConectarToolActivated(tool: Tool)
	if toolConexoes[tool] then
		return -- Já conectado
	end

	local tipo = LerTipo(tool)
	if not tipo then
		return
	end

	local conexoes = {}

	local activated = tool.Activated:Connect(function()
		local agora = tick()
		if (agora - ultimoEquipar) < DEBOUNCE_EQUIPAR then
			DebugPrint("[EquipamentoController] Debounce: equipar muito rápido")
			return
		end
		ultimoEquipar = agora

		if tipo == "Armas" then
			DebugPrint("[EquipamentoController] Tool.Activated → EquiparArma:", tool.Name)
			EquipamentoAcao:FireServer("EquiparArma", tool)
		elseif tipo == "Armaduras" then
			DebugPrint("[EquipamentoController] Tool.Activated → EquiparArmadura:", tool.Name)
			EquipamentoAcao:FireServer("EquiparArmadura", tool)
		end
	end)
	table.insert(conexoes, activated)

	toolConexoes[tool] = conexoes
	DebugPrint("[EquipamentoController] Conectado Tool.Activated para:", tool.Name, "Tipo:", tipo)
end

--- Desconecta Tool.Activated de um Tool
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

--- Monitora Tools no Character para conectar/desconectar Activated
local function MonitorarCharacter(character: Model)
	-- Limpar conexões anteriores do character
	for _, conn in ipairs(charConexoes) do
		conn:Disconnect()
	end
	table.clear(charConexoes)

	-- Limpar conexões de tools anteriores
	for tool, _ in pairs(toolConexoes) do
		DesconectarToolActivated(tool)
	end

	-- Monitor ChildAdded ao Character (quando tool é equipado nas mãos)
	local addedConn = character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and DeveInterceptar(child) then
			ConectarToolActivated(child)
		end
	end)
	table.insert(charConexoes, addedConn)

	-- Monitor ChildRemoved do Character
	local removedConn = character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			DesconectarToolActivated(child)
		end
	end)
	table.insert(charConexoes, removedConn)

	-- Conectar tools existentes
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and DeveInterceptar(child) then
			ConectarToolActivated(child)
		end
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- EQUIPMENT UI
-- ═══════════════════════════════════════════════════════════════════

--- Atualiza visual de um slot de UI
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
		-- Slot ocupado: mostrar ícone do Tool
		local textureId = toolRef.TextureId

		-- Atualiza a imagem do próprio botão conforme pedido
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
		DebugPrint("[EquipamentoController] Slot UI atualizado:", slotName, "→", nomeExibicao)
	else
		-- Slot vazio: limpar e restaurar imagem original
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

--- Conecta clique nos slots de UI para desequipar
local function ConectarSlotClick(uiName: string, slotButton: ImageButton)
	local canonicoName = SLOT_UI_MAP[uiName]
	if not canonicoName then
		return
	end

	slotButton.MouseButton1Click:Connect(function()
		local agora = tick()
		if (agora - ultimoDesequipar) < DEBOUNCE_DESEQUIPAR then
			DebugPrint("[EquipamentoController] Debounce: desequipar muito rápido")
			return
		end

		-- Verificar se slot tem item
		local ov = equipOVs[canonicoName]
		if not ov or not ov.Value then
			DebugPrint("[EquipamentoController] Slot vazio, nada para desequipar:", canonicoName)
			return
		end

		ultimoDesequipar = agora
		DebugPrint("[EquipamentoController] Desequipar slot:", canonicoName)

		-- Feedback visual: highlight temporário
		slotButton.BackgroundColor3 = COR_SLOT_HIGHLIGHT
		task.delay(0.2, function()
			-- Só restaura se ainda existe
			if slotButton and slotButton.Parent then
				-- Verificar se slot ainda está ocupado
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

--- Inicializa conexões com ObjectValues do Equipamento
local function ConectarEquipamentoOVs(character: Model)
	-- Limpar conexões anteriores
	for _, conn in ipairs(ovConexoes) do
		conn:Disconnect()
	end
	table.clear(ovConexoes)
	table.clear(equipOVs)

	-- Esperar Equipamento folder
	local equipamento = character:WaitForChild("Equipamento", 10)
	if not equipamento then
		warn("[EquipamentoController] Equipamento folder não encontrado no Character!")
		return
	end

	local bracos = equipamento:WaitForChild("Bracos", 5)
	local corpo = equipamento:WaitForChild("Corpo", 5)

	-- Conectar ObjectValues dos Bracos
	if bracos then
		for _, ov in ipairs(bracos:GetChildren()) do
			if ov:IsA("ObjectValue") then
				equipOVs[ov.Name] = ov
				-- Atualizar UI com valor atual
				AtualizarSlotUI(ov.Name, ov.Value)
				-- Escutar mudanças
				local conn = ov:GetPropertyChangedSignal("Value"):Connect(function()
					AtualizarSlotUI(ov.Name, ov.Value)
				end)
				table.insert(ovConexoes, conn)
			end
		end
	end

	-- Conectar ObjectValues do Corpo
	if corpo then
		for _, ov in ipairs(corpo:GetChildren()) do
			if ov:IsA("ObjectValue") then
				equipOVs[ov.Name] = ov
				-- Atualizar UI com valor atual
				AtualizarSlotUI(ov.Name, ov.Value)
				-- Escutar mudanças
				local conn = ov:GetPropertyChangedSignal("Value"):Connect(function()
					AtualizarSlotUI(ov.Name, ov.Value)
				end)
				table.insert(ovConexoes, conn)
			end
		end
	end

	DebugPrint("[EquipamentoController] ObjectValues do Equipamento conectados")
end

-- ═══════════════════════════════════════════════════════════════════
-- GLOBAIS EXPOSTOS
-- ═══════════════════════════════════════════════════════════════════

--- Retorna o Tool equipado em um slot de braço
_G.ObterEquipamentoBraco = function(slot: string): Tool?
	local ov = equipOVs[slot]
	if ov and ov.Value then
		return ov.Value :: Tool
	end
	return nil
end

--- Retorna a Categoria da arma equipada no RightArm
_G.ObterCategoriaRightArm = function(): string?
	local ov = equipOVs["RightArm"]
	if not ov or not ov.Value then
		return nil
	end
	return ModEquip.LerCategoria(ov.Value)
end

--- Retorna o Tool equipado em um slot do corpo
_G.ObterEquipamentoCorpo = function(slot: string): Tool?
	local ov = equipOVs[slot]
	if ov and ov.Value then
		return ov.Value :: Tool
	end
	return nil
end

-- ═══════════════════════════════════════════════════════════════════
-- INICIALIZAÇÃO
-- ═══════════════════════════════════════════════════════════════════

local function InicializarUI()
	-- Buscar a EquipmentInventory GUI
	local customInventory = playerGui:WaitForChild("Custom Inventory", 10)
	if not customInventory then
		warn("[EquipamentoController] Custom Inventory GUI não encontrada!")
		return
	end

	local equipmentInventory = customInventory:FindFirstChild("Inventory"):FindFirstChild("EquipmentInventory")
	if not equipmentInventory then
		warn("[EquipamentoController] EquipmentInventory não encontrada! UI de equipamento não será funcional.")
		return
	end

	-- Buscar seções
	local armsEquipment = equipmentInventory:FindFirstChild("ArmsEquipment")
	local bodyEquipment = equipmentInventory:FindFirstChild("BodyEquipment")

	-- Mapear slots de braços
	if armsEquipment then
		for _, child in ipairs(armsEquipment:GetChildren()) do
			if child:IsA("ImageButton") or child:IsA("TextButton") or child:IsA("Frame") then
				if SLOT_UI_MAP[child.Name] then
					slotsUI[child.Name] = child :: ImageButton
					imagensOriginaisSlots[child.Name] = (child :: ImageButton).Image
					ConectarSlotClick(child.Name, child :: ImageButton)
					DebugPrint("[EquipamentoController] Slot UI mapeado:", child.Name, "→", SLOT_UI_MAP[child.Name])
				end
			end
		end
	else
		warn("[EquipamentoController] ArmsEquipment não encontrado!")
	end

	-- Mapear slots de corpo
	if bodyEquipment then
		for _, child in ipairs(bodyEquipment:GetChildren()) do
			if child:IsA("ImageButton") or child:IsA("TextButton") or child:IsA("Frame") then
				if SLOT_UI_MAP[child.Name] then
					slotsUI[child.Name] = child :: ImageButton
					imagensOriginaisSlots[child.Name] = (child :: ImageButton).Image
					ConectarSlotClick(child.Name, child :: ImageButton)
					DebugPrint("[EquipamentoController] Slot UI mapeado:", child.Name, "→", SLOT_UI_MAP[child.Name])
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

	-- Inicializar UI
	InicializarUI()

	-- Monitorar Character atual e futuros
	local function OnCharacterAdded(character: Model)
		DebugPrint("[EquipamentoController] Character adicionado:", character.Name)

		-- Monitorar Tools no Character
		MonitorarCharacter(character)

		-- Conectar ObjectValues do Equipamento
		ConectarEquipamentoOVs(character)
	end

	-- Character atual
	if player.Character then
		OnCharacterAdded(player.Character)
	end

	-- Futuros characters (respawn)
	player.CharacterAdded:Connect(OnCharacterAdded)

	DebugPrint("[EquipamentoController] Inicializado com sucesso!")
end

-- Executar
Inicializar()
