--[[
	ServicoDrop - Serviço de Drop de Ferramentas
	ServerScriptService > Servicos > ServicoDrop.luau
	
	Recebe solicitações de drop do cliente e recria o item no mundo
	usando o ToolBuilder para garantir consistência.
	
	FUNCIONAMENTO:
	1. Cliente solicita drop via RemoteEvent "DroparTool"
	2. Servidor valida a solicitação
	3. Extrai os dados do Tool que foi dropado
	4. Apaga o Tool físico original
	5. Recria o Tool no mundo usando ToolBuilder.CriarToolNoMundo
--]]

local ServicoDrop = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")

-- Módulos
local ToolBuilder = require(ReplicatedStorage.Modulos.ToolBuilder)

-- ============================================
-- CONFIGURAÇÃO
-- ============================================
local ALTURA_DROP = 2 -- Altura acima do character para dropar o item
local DISTANCIA_FRENTE = 3 -- Distância na frente do character
local DEBUG = false -- Ativar logs de debug

-- Collision Groups
local COLLISION_GROUP_PLAYERS = "Players"
local COLLISION_GROUP_TOOLS = "DroppedTools"

-- ============================================
-- FUNÇÕES AUXILIARES
-- ============================================

local function DebugLog(...)
	if DEBUG then
		print("[ServicoDrop]", ...)
	end
end

-- Calcula a posição e rotação onde o item deve ser dropado
local function CalcularPosicaoDrop(character, tipo)
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		warn("[ServicoDrop] HumanoidRootPart não encontrada!")
		return nil
	end

	-- Posição na frente do player, ligeiramente acima
	local lookVector = humanoidRootPart.CFrame.LookVector
	local posicao = humanoidRootPart.Position + (lookVector * DISTANCIA_FRENTE) + Vector3.new(0, ALTURA_DROP, 0)

	-- Criar CFrame com rotação do player
	local rotacaoPlayer = humanoidRootPart.CFrame - humanoidRootPart.CFrame.Position
	local cframeBase = CFrame.new(posicao) * rotacaoPlayer

	-- Rotação depende do tipo do item
	local cframeFinal
	if tipo == "Armaduras" then
		-- Armaduras ficam deitadas para trás (rotação no eixo X)
		cframeFinal = cframeBase * CFrame.Angles(math.rad(-90), 0, 0)
	else
		-- Armas/outros ficam deitados para o lado (rotação no eixo Z)
		cframeFinal = cframeBase * CFrame.Angles(0, 0, math.rad(90))
	end

	return cframeFinal
end

-- Configura collision groups para evitar colisão entre Tools e Players
local function ConfigurarCollisionGroups()
	-- Registra grupos se não existirem (API atualizada)
	local gruposExistentes = PhysicsService:GetRegisteredCollisionGroups()
	local grupoPlayersExiste = false
	local grupoToolsExiste = false

	for _, grupo in ipairs(gruposExistentes) do
		if grupo.name == COLLISION_GROUP_PLAYERS then
			grupoPlayersExiste = true
		elseif grupo.name == COLLISION_GROUP_TOOLS then
			grupoToolsExiste = true
		end
	end

	if not grupoPlayersExiste then
		PhysicsService:RegisterCollisionGroup(COLLISION_GROUP_PLAYERS)
		DebugLog("Collision group criado:", COLLISION_GROUP_PLAYERS)
	end

	if not grupoToolsExiste then
		PhysicsService:RegisterCollisionGroup(COLLISION_GROUP_TOOLS)
		DebugLog("Collision group criado:", COLLISION_GROUP_TOOLS)
	end

	-- Configurar para não colidir entre si
	PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUP_PLAYERS, COLLISION_GROUP_TOOLS, false)

	DebugLog("Collision groups configurados!")
end

-- Define as partes do character no collision group de Players
local function ConfigurarCollisionCharacter(character)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = COLLISION_GROUP_PLAYERS
		end
	end
	DebugLog("Character configurado com collision group:", COLLISION_GROUP_PLAYERS)
end

-- Define o Handle do Tool no collision group de DroppedTools
local function ConfigurarCollisionTool(tool)
	for _, part in ipairs(tool:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = COLLISION_GROUP_TOOLS
		end
	end
	DebugLog("Todas as partes do Tool configuradas com collision group:", COLLISION_GROUP_TOOLS)
end

-- ============================================
-- PROCESSAMENTO DO DROP
-- ============================================

local function ProcessarDrop(player, toolNome, quantidade)
	DebugLog("========================================")
	DebugLog("Processando drop do Tool:", toolNome, "Quantidade:", quantidade)

	-- Verificar se o player ainda está no jogo
	if not player or not player.Parent then
		warn("[ServicoDrop] Player não está mais no jogo!")
		return
	end

	local character = player.Character
	if not character then
		warn("[ServicoDrop] Character não encontrado!")
		return
	end

	-- Buscar o Tool na Backpack ou no Character
	local tool = player.Backpack:FindFirstChild(toolNome) or character:FindFirstChild(toolNome)
	if not tool or not tool:IsA("Tool") then
		warn("[ServicoDrop] Tool não encontrado:", toolNome)
		return
	end

	-- Verificar se o Tool é do tipo 'ArmasEquipadas'
	local dadosFolder = tool:FindFirstChild("Dados")
	if dadosFolder then
		local tipoValue = dadosFolder:FindFirstChild("Tipo")
		if tipoValue and tipoValue.Value == "ArmasEquipadas" then
			warn("[ServicoDrop] Tentativa de dropar Tool do tipo 'ArmasEquipadas' bloqueada!")
			return
		end
	end

	-- Extrair dados do Tool
	local itemData = ToolBuilder.ExtrairDados(tool)
	if not itemData then
		warn("[ServicoDrop] ERRO: Não foi possível extrair dados do Tool!")
		return
	end

	DebugLog("Dados extraídos:", itemData.Nome or "N/A")

	-- Se a quantidade for menor que a quantidade total, ajustar
	local quantidadeAtual = itemData.Quantidade or 1
	if quantidade < quantidadeAtual then
		-- Reduzir quantidade do Tool no inventário
		ToolBuilder.AtualizarQuantidade(tool, quantidadeAtual - quantidade)
		itemData.Quantidade = quantidade
		DebugLog("Dropando quantidade parcial:", quantidade, "Restando:", quantidadeAtual - quantidade)
	else
		-- Dropar tudo - destruir o Tool original
		DebugLog("Dropando quantidade total - destruindo Tool original")
		tool:Destroy()
	end

	-- Calcular posição de drop (tipo determina orientação)
	local cframeDrop = CalcularPosicaoDrop(character, itemData.Tipo)
	if not cframeDrop then
		warn("[ServicoDrop] ERRO: Não foi possível calcular posição de drop!")
		return
	end

	-- Criar novo Tool no mundo usando ToolBuilder
	DebugLog("Criando Tool no mundo usando ToolBuilder...")
	local toolNoMundo = ToolBuilder.CriarToolNoMundo(itemData, cframeDrop)

	if toolNoMundo then
		-- Configurar collision group para não colidir com players
		ConfigurarCollisionTool(toolNoMundo)
		DebugLog("Tool criado no mundo com sucesso:", toolNoMundo.Name)
	else
		warn("[ServicoDrop] ERRO: Falha ao criar Tool no mundo!")
	end

	DebugLog("========================================")
end

-- ============================================
-- INICIALIZAÇÃO DO SERVIÇO
-- ============================================

function ServicoDrop:Iniciar()
	DebugLog("Inicializando ServicoDrop...")

	-- Obter referências
	local Remotos = ReplicatedStorage:WaitForChild("Remotos")
	local DroparToolEvent = Remotos:WaitForChild("DroparTool")

	-- Configurar collision groups no início
	ConfigurarCollisionGroups()

	-- Listener do RemoteEvent
	DroparToolEvent.OnServerEvent:Connect(function(player, toolNome, quantidade)
		DebugLog("RemoteEvent recebido de:", player.Name, "Tool:", toolNome, "Quantidade:", quantidade)

		-- Validações básicas
		if type(toolNome) ~= "string" then
			warn("[ServicoDrop] Nome do Tool inválido!")
			return
		end

		if type(quantidade) ~= "number" or quantidade <= 0 then
			warn("[ServicoDrop] Quantidade inválida!")
			return
		end

		-- Processar o drop
		ProcessarDrop(player, toolNome, quantidade)
	end)

	-- Configurar collision nos characters dos players
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			DebugLog("Character carregado para:", player.Name)
			character:WaitForChild("HumanoidRootPart")
			ConfigurarCollisionCharacter(character)
		end)

		-- Se já tem character, configurar agora
		if player.Character then
			ConfigurarCollisionCharacter(player.Character)
		end
	end)

	-- Processar players que já estão no jogo
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			ConfigurarCollisionCharacter(player.Character)
		end

		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("HumanoidRootPart")
			ConfigurarCollisionCharacter(character)
		end)
	end

	DebugLog("ServicoDrop inicializado!")
end

return ServicoDrop
