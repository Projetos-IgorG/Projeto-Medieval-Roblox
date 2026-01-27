--[[
    ServicoArrastar.luau
    
    Sistema de arrastar itens com física estilo Skyrim (servidor):
    - Gerencia NetworkOwnership dos itens arrastáveis
    - Valida permissões e distância (anti-exploit)
    - Libera itens quando jogador desconecta
    - Configura DragDetector com física realista
    
    Configuração de itens:
    - Atributo "Draggable" (boolean) = true para permitir arrastar
    - Atributo "Peso" (number) = multiplicador de dificuldade (padrão: 1.0)
]]

local ServicoArrastar = {}

-- ═══════════════════════════════════════════════════════════════════
-- CONFIGURAÇÃO DE DEBUG
-- ═══════════════════════════════════════════════════════════════════
local DEBUG_ENABLED = false

local function DebugPrint(...)
	if DEBUG_ENABLED then
		print("[ServicoArrastar]", ...)
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- SERVIÇOS
-- ═══════════════════════════════════════════════════════════════════
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")

-- ═══════════════════════════════════════════════════════════════════
-- CONFIGURAÇÕES
-- ═══════════════════════════════════════════════════════════════════
local CONFIG = {
	DISTANCIA_MAXIMA = 12,
	FORCA_BASE = 4000,
	DAMPING_BASE = 50,
	RESPONSIVIDADE_BASE = 20,
	GRUPO_PLAYERS = "Players",
	GRUPO_ITENS_ARRASTANDO = "ItensArrastando",
}

-- Mapa de jogadores arrastando itens
local jogadoresArrastando = {}

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES AUXILIARES (mesmas do original)
-- ═══════════════════════════════════════════════════════════════════

local function InicializarCollisionGroups()
	local gruposExistentes = PhysicsService:GetRegisteredCollisionGroups()
	local grupoPlayersExiste = false
	local grupoItensExiste = false

	for _, grupo in ipairs(gruposExistentes) do
		if grupo.name == CONFIG.GRUPO_PLAYERS then
			grupoPlayersExiste = true
		elseif grupo.name == CONFIG.GRUPO_ITENS_ARRASTANDO then
			grupoItensExiste = true
		end
	end

	if not grupoPlayersExiste then
		PhysicsService:RegisterCollisionGroup(CONFIG.GRUPO_PLAYERS)
		DebugPrint("Collision group criado:", CONFIG.GRUPO_PLAYERS)
	end

	if not grupoItensExiste then
		PhysicsService:RegisterCollisionGroup(CONFIG.GRUPO_ITENS_ARRASTANDO)
		DebugPrint("Collision group criado:", CONFIG.GRUPO_ITENS_ARRASTANDO)
	end

	PhysicsService:CollisionGroupSetCollidable(CONFIG.GRUPO_ITENS_ARRASTANDO, CONFIG.GRUPO_PLAYERS, false)
	DebugPrint("Collision groups configurados")
end

local function ConfigurarCollisionCharacter(character)
	for _, parte in ipairs(character:GetDescendants()) do
		if parte:IsA("BasePart") then
			parte.CollisionGroup = CONFIG.GRUPO_PLAYERS
		end
	end
end

local function OnCharacterAdded(character)
	ConfigurarCollisionCharacter(character)
	character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = CONFIG.GRUPO_PLAYERS
		end
	end)
end

local function ObterHRP(player)
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart")
end

local function ObterPartePrincipal(objeto)
	if objeto:IsA("BasePart") then
		return objeto
	elseif objeto:IsA("Model") then
		return objeto.PrimaryPart or objeto:FindFirstChildWhichIsA("BasePart", true)
	elseif objeto:IsA("Tool") then
		return objeto:FindFirstChild("Handle")
	end
	return nil
end

local function EhArrastavel(objeto)
	if objeto:IsA("Tool") then
		local dados = objeto:FindFirstChild("Dados")
		if dados and dados:IsA("Folder") then
			local draggableValue = dados:FindFirstChild("Draggable")
			if draggableValue and draggableValue:IsA("BoolValue") then
				return draggableValue.Value == true
			end
		end
		return false
	end
	return objeto:GetAttribute("Draggable") == true
end

local function ObterPeso(objeto)
	if objeto:IsA("Tool") then
		local dados = objeto:FindFirstChild("Dados")
		if dados and dados:IsA("Folder") then
			local pesoValue = dados:FindFirstChild("Peso")
			if pesoValue and pesoValue:IsA("NumberValue") then
				local p = pesoValue.Value
				if typeof(p) == "number" and p > 0 then
					return p
				end
			end
		end
		return 1.0
	end
	local peso = objeto:GetAttribute("Peso")
	if typeof(peso) == "number" and peso > 0 then
		return peso
	end
	return 1.0
end

local function DefinirNetworkOwner(objeto, owner)
	local partes = {}
	if objeto:IsA("BasePart") then
		table.insert(partes, objeto)
	end
	for _, descendente in ipairs(objeto:GetDescendants()) do
		if descendente:IsA("BasePart") then
			table.insert(partes, descendente)
		end
	end
	for _, parte in ipairs(partes) do
		local sucesso = parte:CanSetNetworkOwnership()
		if sucesso then
			if owner then
				parte:SetNetworkOwner(owner)
			else
				parte:SetNetworkOwnershipAuto()
			end
		end
	end
	DebugPrint("NetworkOwner definido para", owner and owner.Name or "Auto", "em", objeto.Name)
end

local function DefinirCollisionGroup(objeto, grupo)
	local gruposOriginais = {}
	local partes = {}
	if objeto:IsA("BasePart") then
		table.insert(partes, objeto)
	end
	for _, descendente in ipairs(objeto:GetDescendants()) do
		if descendente:IsA("BasePart") then
			table.insert(partes, descendente)
		end
	end
	for _, parte in ipairs(partes) do
		gruposOriginais[parte] = parte.CollisionGroup
		parte.CollisionGroup = grupo
	end
	DebugPrint("CollisionGroup definido para", grupo, "em", objeto.Name, "(", #partes, "partes)")
	return gruposOriginais
end

local function RestaurarCollisionGroups(gruposOriginais)
	for parte, grupoOriginal in pairs(gruposOriginais) do
		if parte and parte.Parent then
			parte.CollisionGroup = grupoOriginal
		end
	end
	DebugPrint("CollisionGroups restaurados")
end

local function DesativarProximityPrompts(objeto)
	local promptsDesativados = {}
	if objeto:IsA("ProximityPrompt") and objeto.Enabled then
		objeto.Enabled = false
		table.insert(promptsDesativados, objeto)
	end
	for _, descendente in ipairs(objeto:GetDescendants()) do
		if descendente:IsA("ProximityPrompt") and descendente.Enabled then
			descendente.Enabled = false
			table.insert(promptsDesativados, descendente)
		end
	end
	if #promptsDesativados > 0 then
		DebugPrint("ProximityPrompts desativados:", #promptsDesativados)
	end
	return promptsDesativados
end

local function ReativarProximityPrompts(prompts)
	for _, prompt in ipairs(prompts) do
		if prompt and prompt.Parent then
			prompt.Enabled = true
		end
	end
	if #prompts > 0 then
		DebugPrint("ProximityPrompts reativados:", #prompts)
	end
end

local function ObterOuCriarDragDetector(objeto, peso)
	local partePrincipal = ObterPartePrincipal(objeto)
	if not partePrincipal then
		return nil
	end
	local dragDetector = partePrincipal:FindFirstChildOfClass("DragDetector")
	if not dragDetector then
		dragDetector = Instance.new("DragDetector")
		dragDetector.Name = "DragDetectorSistema"
		dragDetector.ResponseStyle = Enum.DragDetectorResponseStyle.Physical
		dragDetector.DragStyle = Enum.DragDetectorDragStyle.TranslatePlane
		dragDetector.Enabled = true
		dragDetector.MaxActivationDistance = CONFIG.DISTANCIA_MAXIMA
		dragDetector.RunLocally = false
		dragDetector.Parent = partePrincipal
	end
	local forcaAjustada = CONFIG.FORCA_BASE / peso
	local responsividadeAjustada = CONFIG.RESPONSIVIDADE_BASE / math.sqrt(peso)
	dragDetector.ApplyAtCenterOfMass = true
	dragDetector.MaxForce = forcaAjustada
	dragDetector.MaxTorque = forcaAjustada * 0.5
	dragDetector.Responsiveness = responsividadeAjustada
	DebugPrint("DragDetector configurado - Peso:", peso, "Força:", forcaAjustada)
	return dragDetector
end

local function LimparDragDetector(objeto)
	local partePrincipal = ObterPartePrincipal(objeto)
	if not partePrincipal then
		return
	end
	local dragDetector = partePrincipal:FindFirstChild("DragDetectorSistema")
	if dragDetector then
		dragDetector:Destroy()
		DebugPrint("DragDetector removido de", objeto.Name)
	end
end

local function ValidarAlvo(player, objeto)
	if typeof(objeto) ~= "Instance" then
		DebugPrint("Alvo inválido: não é Instance")
		return false
	end
	if not EhArrastavel(objeto) then
		DebugPrint("Alvo inválido: não tem atributo Draggable")
		return false
	end
	local partePrincipal = ObterPartePrincipal(objeto)
	if not partePrincipal then
		DebugPrint("Alvo inválido: sem parte principal")
		return false
	end
	local hrp = ObterHRP(player)
	if not hrp then
		DebugPrint("Alvo inválido: jogador sem HRP")
		return false
	end
	local distancia = (hrp.Position - partePrincipal.Position).Magnitude
	if distancia > CONFIG.DISTANCIA_MAXIMA * 1.5 then
		DebugPrint("Alvo inválido: distância muito grande", distancia)
		return false
	end
	for outroPlayer, dados in pairs(jogadoresArrastando) do
		if outroPlayer ~= player and dados.item == objeto then
			DebugPrint("Alvo inválido: outro jogador já está arrastando")
			return false
		end
	end
	return true
end

local function PararArrasto(player)
	local dados = jogadoresArrastando[player]
	if not dados then
		return
	end
	local objeto = dados.item
	if objeto and objeto.Parent then
		objeto:SetAttribute("ArrastadoPor", nil)
		LimparDragDetector(objeto)
		DefinirNetworkOwner(objeto, nil)
		if dados.collisionGroupsOriginais then
			RestaurarCollisionGroups(dados.collisionGroupsOriginais)
		end
		if dados.promptsDesativados then
			ReativarProximityPrompts(dados.promptsDesativados)
		end
	end
	jogadoresArrastando[player] = nil
	DebugPrint("Arrasto parado:", player.Name)
end

local function IniciarArrasto(player, objeto)
	if not ValidarAlvo(player, objeto) then
		return
	end
	local dadosAnteriores = jogadoresArrastando[player]
	if dadosAnteriores then
		PararArrasto(player)
	end
	local peso = ObterPeso(objeto)
	local dragDetector = ObterOuCriarDragDetector(objeto, peso)
	if not dragDetector then
		DebugPrint("Falha ao criar DragDetector para", objeto.Name)
		return
	end
	DefinirNetworkOwner(objeto, player)
	objeto:SetAttribute("ArrastadoPor", player.UserId)
	local collisionGroupsOriginais = DefinirCollisionGroup(objeto, CONFIG.GRUPO_ITENS_ARRASTANDO)
	local promptsDesativados = DesativarProximityPrompts(objeto)
	jogadoresArrastando[player] = {
		item = objeto,
		dragDetector = dragDetector,
		collisionGroupsOriginais = collisionGroupsOriginais,
		promptsDesativados = promptsDesativados,
	}
	DebugPrint("Arrasto iniciado:", player.Name, "->", objeto.Name)
end

-- ═══════════════════════════════════════════════════════════════════
-- INICIALIZAÇÃO DO SERVIÇO
-- ═══════════════════════════════════════════════════════════════════

function ServicoArrastar:Iniciar()
	DebugPrint("Inicializando ServicoArrastar...")

	InicializarCollisionGroups()

	local Remotos = ReplicatedStorage:WaitForChild("Remotos")
	local ArrastarItemEvent = Remotos:WaitForChild("ArrastarItem")

	ArrastarItemEvent.OnServerEvent:Connect(function(player, acao, objeto)
		DebugPrint("Evento recebido:", player.Name, acao, objeto and objeto.Name or "nil")
		if acao == "Iniciar" and objeto then
			IniciarArrasto(player, objeto)
		elseif acao == "Parar" then
			PararArrasto(player)
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		if player.Character then
			OnCharacterAdded(player.Character)
		end
		player.CharacterAdded:Connect(OnCharacterAdded)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			OnCharacterAdded(player.Character)
		end
		player.CharacterAdded:Connect(OnCharacterAdded)
	end

	Players.PlayerRemoving:Connect(function(player)
		PararArrasto(player)
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterRemoving:Connect(function()
			PararArrasto(player)
		end)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterRemoving:Connect(function()
			PararArrasto(player)
		end)
	end

	DebugPrint("ServicoArrastar inicializado!")
end

return ServicoArrastar
