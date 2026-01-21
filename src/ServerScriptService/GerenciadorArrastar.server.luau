--[[
    GerenciadorArrastar.server.luau
    
    Sistema de arrastar itens com física estilo Skyrim (servidor):
    - Gerencia NetworkOwnership dos itens arrastáveis
    - Valida permissões e distância (anti-exploit)
    - Libera itens quando jogador desconecta
    - Configura DragDetector com física realista
    
    Configuração de itens:
    - Atributo "Draggable" (boolean) = true para permitir arrastar
    - Atributo "Peso" (number) = multiplicador de dificuldade (padrão: 1.0)
      * 0.5 = muito leve (fácil mover)
      * 1.0 = normal
      * 2.0 = pesado (difícil mover)
      * 5.0+ = muito pesado
]]

-- ═══════════════════════════════════════════════════════════════════
-- CONFIGURAÇÃO DE DEBUG
-- ═══════════════════════════════════════════════════════════════════
local DEBUG_ENABLED = true

local function DebugPrint(...)
	if DEBUG_ENABLED then
		print("[GerenciadorArrastar]", ...)
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
	-- Distância máxima para iniciar/manter drag (anti-exploit)
	DISTANCIA_MAXIMA = 12,

	-- Força base para física do drag
	FORCA_BASE = 4000,

	-- Damping base para estabilidade
	DAMPING_BASE = 50,

	-- Responsividade base
	RESPONSIVIDADE_BASE = 20,

	-- Nomes dos collision groups
	GRUPO_PLAYERS = "Players",
	GRUPO_ITENS_ARRASTANDO = "ItensArrastando",
}

-- ═══════════════════════════════════════════════════════════════════
-- REFERÊNCIAS
-- ═══════════════════════════════════════════════════════════════════
local Remotos = ReplicatedStorage:WaitForChild("Remotos")
local ArrastarItemEvent = Remotos:WaitForChild("ArrastarItem")

-- Mapa de jogadores arrastando itens: [Player] = {item, dragDetector, collisionGroupsOriginais, promptsDesativados}
local jogadoresArrastando: {
	[Player]: {
		item: Instance,
		dragDetector: DragDetector?,
		collisionGroupsOriginais: { [BasePart]: string },
		promptsDesativados: { ProximityPrompt },
	},
} =
	{}

-- ═══════════════════════════════════════════════════════════════════
-- CONFIGURAÇÃO DE COLLISION GROUPS
-- ═══════════════════════════════════════════════════════════════════

local function InicializarCollisionGroups()
	-- Registra grupos se não existirem (API atualizada)
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

	-- Configura colisão: Itens arrastando NÃO colidem com Players
	PhysicsService:CollisionGroupSetCollidable(CONFIG.GRUPO_ITENS_ARRASTANDO, CONFIG.GRUPO_PLAYERS, false)

	DebugPrint("Collision groups configurados")
end

-- Configura character do player para usar collision group "Players"
local function ConfigurarCollisionCharacter(character: Model)
	for _, parte in ipairs(character:GetDescendants()) do
		if parte:IsA("BasePart") then
			parte.CollisionGroup = CONFIG.GRUPO_PLAYERS
		end
	end
end

-- Inicializa collision groups
InicializarCollisionGroups()

-- Configura characters existentes e novos
local function OnCharacterAdded(character: Model)
	ConfigurarCollisionCharacter(character)

	-- Configura partes adicionadas depois (acessórios, etc)
	character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = CONFIG.GRUPO_PLAYERS
		end
	end)
end

Players.PlayerAdded:Connect(function(player)
	if player.Character then
		OnCharacterAdded(player.Character)
	end
	player.CharacterAdded:Connect(OnCharacterAdded)
end)

-- Para jogadores já conectados
for _, player in ipairs(Players:GetPlayers()) do
	if player.Character then
		OnCharacterAdded(player.Character)
	end
	player.CharacterAdded:Connect(OnCharacterAdded)
end

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES AUXILIARES
-- ═══════════════════════════════════════════════════════════════════

-- Obtém o HumanoidRootPart do jogador
local function ObterHRP(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Obtém a parte principal de um objeto (BasePart, Model, Tool, etc.)
local function ObterPartePrincipal(objeto: Instance): BasePart?
	if objeto:IsA("BasePart") then
		return objeto
	elseif objeto:IsA("Model") then
		return objeto.PrimaryPart or objeto:FindFirstChildWhichIsA("BasePart", true)
	elseif objeto:IsA("Tool") then
		return objeto:FindFirstChild("Handle") :: BasePart?
	end
	return nil
end

-- Verifica se o objeto é arrastável
local function EhArrastavel(objeto: Instance): boolean
	return objeto:GetAttribute("Draggable") == true
end

-- Obtém o peso do objeto (multiplicador)
local function ObterPeso(objeto: Instance): number
	local peso = objeto:GetAttribute("Peso")
	if typeof(peso) == "number" and peso > 0 then
		return peso
	end
	return 1.0 -- Peso padrão
end

-- Define NetworkOwnership de todas as partes de um objeto
local function DefinirNetworkOwner(objeto: Instance, owner: Player?)
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

-- Define collision group de todas as partes de um objeto e retorna os grupos originais
local function DefinirCollisionGroup(objeto: Instance, grupo: string): { [BasePart]: string }
	local gruposOriginais: { [BasePart]: string } = {}
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

-- Restaura collision groups originais
local function RestaurarCollisionGroups(gruposOriginais: { [BasePart]: string })
	for parte, grupoOriginal in pairs(gruposOriginais) do
		if parte and parte.Parent then
			parte.CollisionGroup = grupoOriginal
		end
	end
	DebugPrint("CollisionGroups restaurados")
end

-- Desativa ProximityPrompts do objeto e retorna lista dos desativados
local function DesativarProximityPrompts(objeto: Instance): { ProximityPrompt }
	local promptsDesativados: { ProximityPrompt } = {}

	-- Verifica o próprio objeto
	if objeto:IsA("ProximityPrompt") and objeto.Enabled then
		objeto.Enabled = false
		table.insert(promptsDesativados, objeto)
	end

	-- Verifica descendentes
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

-- Reativa ProximityPrompts que foram desativados
local function ReativarProximityPrompts(prompts: { ProximityPrompt })
	for _, prompt in ipairs(prompts) do
		if prompt and prompt.Parent then
			prompt.Enabled = true
		end
	end

	if #prompts > 0 then
		DebugPrint("ProximityPrompts reativados:", #prompts)
	end
end

-- Cria ou obtém DragDetector de um objeto
local function ObterOuCriarDragDetector(objeto: Instance, peso: number): DragDetector?
	local partePrincipal = ObterPartePrincipal(objeto)
	if not partePrincipal then
		return nil
	end

	-- Verifica se já existe um DragDetector
	local dragDetector = partePrincipal:FindFirstChildOfClass("DragDetector")

	if not dragDetector then
		-- Cria novo DragDetector
		dragDetector = Instance.new("DragDetector")
		dragDetector.Name = "DragDetectorSistema"

		-- Configuração física estilo Skyrim
		dragDetector.ResponseStyle = Enum.DragDetectorResponseStyle.Physical
		dragDetector.DragStyle = Enum.DragDetectorDragStyle.TranslatePlane

		-- Ativa para todos os tipos de input
		dragDetector.Enabled = true
		dragDetector.MaxActivationDistance = CONFIG.DISTANCIA_MAXIMA
		dragDetector.RunLocally = false -- Processa no servidor

		dragDetector.Parent = partePrincipal
	end

	-- Ajusta força baseada no peso (quanto mais pesado, menos força relativa)
	local forcaAjustada = CONFIG.FORCA_BASE / peso
	local _dampingAjustado = CONFIG.DAMPING_BASE * math.sqrt(peso) -- Reservado para uso futuro
	local responsividadeAjustada = CONFIG.RESPONSIVIDADE_BASE / math.sqrt(peso)

	-- Aplica configurações de física
	dragDetector.ApplyAtCenterOfMass = true
	dragDetector.MaxForce = forcaAjustada
	dragDetector.MaxTorque = forcaAjustada * 0.5
	dragDetector.Responsiveness = responsividadeAjustada

	DebugPrint("DragDetector configurado - Peso:", peso, "Força:", forcaAjustada)

	return dragDetector
end

-- Limpa DragDetector criado pelo sistema
local function LimparDragDetector(objeto: Instance)
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

-- ═══════════════════════════════════════════════════════════════════
-- VALIDAÇÃO
-- ═══════════════════════════════════════════════════════════════════

local function ValidarAlvo(player: Player, objeto: Instance): boolean
	-- Verifica se é uma instância válida
	if typeof(objeto) ~= "Instance" then
		DebugPrint("Alvo inválido: não é Instance")
		return false
	end

	-- Verifica se é arrastável
	if not EhArrastavel(objeto) then
		DebugPrint("Alvo inválido: não tem atributo Draggable")
		return false
	end

	-- Verifica se tem parte principal
	local partePrincipal = ObterPartePrincipal(objeto)
	if not partePrincipal then
		DebugPrint("Alvo inválido: sem parte principal")
		return false
	end

	-- Valida distância (anti-exploit)
	local hrp = ObterHRP(player)
	if not hrp then
		DebugPrint("Alvo inválido: jogador sem HRP")
		return false
	end

	local distancia = (hrp.Position - partePrincipal.Position).Magnitude
	if distancia > CONFIG.DISTANCIA_MAXIMA * 1.5 then -- Margem de tolerância
		DebugPrint("Alvo inválido: distância muito grande", distancia)
		return false
	end

	-- Verifica se outro jogador já está arrastando
	for outroPlayer, dados in pairs(jogadoresArrastando) do
		if outroPlayer ~= player and dados.item == objeto then
			DebugPrint("Alvo inválido: outro jogador já está arrastando")
			return false
		end
	end

	return true
end

-- ═══════════════════════════════════════════════════════════════════
-- LÓGICA PRINCIPAL
-- ═══════════════════════════════════════════════════════════════════

local function IniciarArrasto(player: Player, objeto: Instance)
	if not ValidarAlvo(player, objeto) then
		return
	end

	-- Para qualquer arrasto anterior
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

	-- Define NetworkOwnership para o jogador
	DefinirNetworkOwner(objeto, player)

	-- Marca o objeto como sendo arrastado
	objeto:SetAttribute("ArrastadoPor", player.UserId)

	-- Define collision group para não colidir com players
	local collisionGroupsOriginais = DefinirCollisionGroup(objeto, CONFIG.GRUPO_ITENS_ARRASTANDO)

	-- Desativa ProximityPrompts do objeto
	local promptsDesativados = DesativarProximityPrompts(objeto)

	-- Registra no mapa
	jogadoresArrastando[player] = {
		item = objeto,
		dragDetector = dragDetector,
		collisionGroupsOriginais = collisionGroupsOriginais,
		promptsDesativados = promptsDesativados,
	}

	DebugPrint("Arrasto iniciado:", player.Name, "->", objeto.Name)
end

function PararArrasto(player: Player)
	local dados = jogadoresArrastando[player]
	if not dados then
		return
	end

	local objeto = dados.item

	if objeto and objeto.Parent then
		-- Remove marca de arrasto
		objeto:SetAttribute("ArrastadoPor", nil)

		-- Limpa DragDetector criado pelo sistema
		LimparDragDetector(objeto)

		-- Retorna NetworkOwnership ao automático (servidor decide)
		DefinirNetworkOwner(objeto, nil)

		-- Restaura collision groups originais
		if dados.collisionGroupsOriginais then
			RestaurarCollisionGroups(dados.collisionGroupsOriginais)
		end

		-- Reativa ProximityPrompts
		if dados.promptsDesativados then
			ReativarProximityPrompts(dados.promptsDesativados)
		end
	end

	-- Remove do mapa
	jogadoresArrastando[player] = nil

	DebugPrint("Arrasto parado:", player.Name)
end

-- ═══════════════════════════════════════════════════════════════════
-- EVENTOS
-- ═══════════════════════════════════════════════════════════════════

ArrastarItemEvent.OnServerEvent:Connect(function(player: Player, acao: string, objeto: Instance?)
	DebugPrint("Evento recebido:", player.Name, acao, objeto and objeto.Name or "nil")

	if acao == "Iniciar" and objeto then
		IniciarArrasto(player, objeto)
	elseif acao == "Parar" then
		PararArrasto(player)
	end
end)

-- Segurança: libera item quando jogador sai
Players.PlayerRemoving:Connect(function(player: Player)
	PararArrasto(player)
end)

-- Segurança: libera item quando personagem morre/respawna
Players.PlayerAdded:Connect(function(player: Player)
	player.CharacterRemoving:Connect(function()
		PararArrasto(player)
	end)
end)

-- Para jogadores que já estão no jogo
for _, player in ipairs(Players:GetPlayers()) do
	player.CharacterRemoving:Connect(function()
		PararArrasto(player)
	end)
end

DebugPrint("Sistema de arrastar inicializado")
