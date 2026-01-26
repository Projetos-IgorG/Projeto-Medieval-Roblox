--[[
	DropTool - Sistema de Drop de Ferramentas
	ReplicatedStorage > DropTool.server.luau
	
	Detecta quando um player dropa uma ferramenta e recria o item no mundo
	usando o ToolBuilder para garantir consistência.
	
	FUNCIONAMENTO:
	1. Detecta quando um Tool é removido da Backpack do player
	2. Extrai os dados do Tool que foi dropado
	3. Apaga o Tool físico original
	4. Recria o Tool no mundo usando ToolBuilder.CriarToolNoMundo
--]]

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
local DEBUG = true -- Ativar logs de debug

-- Collision Groups
local COLLISION_GROUP_PLAYERS = "Players"
local COLLISION_GROUP_TOOLS = "DroppedTools"

-- ============================================
-- FUNÇÕES AUXILIARES
-- ============================================

local function DebugLog(...)
	if DEBUG then
		print("[DropTool]", ...)
	end
end

-- Calcula a posição e rotação onde o item deve ser dropado
local function CalcularPosicaoDrop(character)
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		warn("[DropTool] HumanoidRootPart não encontrada!")
		return nil
	end

	-- Posição na frente do player, ligeiramente acima
	local lookVector = humanoidRootPart.CFrame.LookVector
	local posicao = humanoidRootPart.Position + (lookVector * DISTANCIA_FRENTE) + Vector3.new(0, ALTURA_DROP, 0)

	-- Criar CFrame com rotação do player
	local rotacaoPlayer = humanoidRootPart.CFrame - humanoidRootPart.CFrame.Position
	local cframeBase = CFrame.new(posicao) * rotacaoPlayer

	-- Rotacionar 90 graus para a esquerda (deitado)
	-- CFrame.Angles(pitch, yaw, roll) - rotacionar no eixo Z para deitar
	local cframeFinal = cframeBase * CFrame.Angles(0, 0, math.rad(90))

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
	-- Configurar todas as BaseParts dentro do Tool
	for _, part in ipairs(tool:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = COLLISION_GROUP_TOOLS
		end
	end
	DebugLog("Todas as partes do Tool configuradas com collision group:", COLLISION_GROUP_TOOLS)
end

-- ============================================
-- SISTEMA DE DETECÇÃO DE DROP
-- ============================================

-- Rastreia os Tools que estão sendo monitorados por player
local toolsMonitorados = {} -- [player] = {[tool] = true}

-- Monitora um Tool específico para detectar quando é dropado
local function MonitorarTool(player, tool)
	if not tool:IsA("Tool") then
		return
	end

	-- Inicializar tabela do player se não existir
	if not toolsMonitorados[player] then
		toolsMonitorados[player] = {}
	end

	-- Evitar monitorar o mesmo tool múltiplas vezes
	if toolsMonitorados[player][tool] then
		return
	end

	toolsMonitorados[player][tool] = true
	DebugLog("Monitorando Tool:", tool.Name, "do player:", player.Name)

	-- Detectar quando o Tool é equipado (vai para o Character)
	local conexaoEquipado = tool.AncestryChanged:Connect(function(_, parent)
		-- Se foi equipado (parent agora é o character)
		if parent == player.Character then
			DebugLog("Tool equipado:", tool.Name)

			-- Detectar quando é desequipado/dropado
			local conexaoDrop = tool.AncestryChanged:Connect(function(_, newParent)
				-- Se foi dropado (parent agora é workspace ou nil)
				if newParent == workspace or newParent == nil then
					DebugLog("Tool DROPADO detectado:", tool.Name)

					-- Processar o drop
					task.spawn(function()
						ProcessarDrop(player, tool)
					end)
				end
			end)

			-- Limpar conexão quando tool for destruído ou voltar para backpack
			tool.AncestryChanged:Connect(function(_, p)
				if p == player:FindFirstChild("Backpack") or p == nil then
					conexaoDrop:Disconnect()
				end
			end)
		end
	end)

	-- Limpar quando o tool for removido/destruído
	tool.Destroying:Connect(function()
		if toolsMonitorados[player] then
			toolsMonitorados[player][tool] = nil
		end
		conexaoEquipado:Disconnect()
	end)
end

-- Monitora a Backpack de um player para novos Tools
local function MonitorarBackpack(player)
	local backpack = player:WaitForChild("Backpack")

	-- Monitorar Tools existentes
	for _, item in ipairs(backpack:GetChildren()) do
		if item:IsA("Tool") then
			MonitorarTool(player, item)
		end
	end

	-- Monitorar novos Tools adicionados
	backpack.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			DebugLog("Novo Tool adicionado à backpack:", child.Name)
			MonitorarTool(player, child)
		end
	end)
end

-- ============================================
-- PROCESSAMENTO DO DROP
-- ============================================

function ProcessarDrop(player, toolDropado)
	DebugLog("========================================")
	DebugLog("Processando drop do Tool:", toolDropado.Name)

	-- Verificar se o player ainda está no jogo
	if not player or not player.Parent then
		warn("[DropTool] Player não está mais no jogo!")
		return
	end

	local character = player.Character
	if not character then
		warn("[DropTool] Character não encontrado!")
		return
	end

	-- Extrair dados do Tool
	local itemData = ToolBuilder.ExtrairDados(toolDropado)
	if not itemData then
		warn("[DropTool] ERRO: Não foi possível extrair dados do Tool!")
		return
	end

	DebugLog("Dados extraídos:", itemData.Nome or "N/A")

	-- Calcular posição de drop
	local cframeDrop = CalcularPosicaoDrop(character)
	if not cframeDrop then
		warn("[DropTool] ERRO: Não foi possível calcular posição de drop!")
		return
	end

	-- Apagar o Tool físico original
	DebugLog("Destruindo Tool físico original...")
	toolDropado:Destroy()

	-- Limpar da tabela de monitoramento
	if toolsMonitorados[player] then
		toolsMonitorados[player][toolDropado] = nil
	end

	-- Criar novo Tool no mundo usando ToolBuilder
	DebugLog("Criando Tool no mundo usando ToolBuilder...")
	local toolNoMundo = ToolBuilder.CriarToolNoMundo(itemData, cframeDrop)

	if toolNoMundo then
		-- Configurar collision group para não colidir com players
		ConfigurarCollisionTool(toolNoMundo)
		DebugLog("Tool criado no mundo com sucesso:", toolNoMundo.Name)
	else
		warn("[DropTool] ERRO: Falha ao criar Tool no mundo!")
	end

	DebugLog("========================================")
end

-- ============================================
-- INICIALIZAÇÃO
-- ============================================

-- Configurar collision groups no início
ConfigurarCollisionGroups()

-- Monitorar players que entram
Players.PlayerAdded:Connect(function(player)
	DebugLog("Player entrou:", player.Name)

	-- Aguardar character carregar
	player.CharacterAdded:Connect(function(character)
		DebugLog("Character carregado para:", player.Name)

		-- Configurar collision no character
		character:WaitForChild("HumanoidRootPart")
		ConfigurarCollisionCharacter(character)

		MonitorarBackpack(player)
	end)

	-- Se já tem character, monitorar agora
	if player.Character then
		ConfigurarCollisionCharacter(player.Character)
		MonitorarBackpack(player)
	end
end)

-- Limpar dados quando player sair
Players.PlayerRemoving:Connect(function(player)
	DebugLog("Player saindo:", player.Name)
	toolsMonitorados[player] = nil
end)

-- Monitorar players que já estão no jogo
for _, player in ipairs(Players:GetPlayers()) do
	if player.Character then
		ConfigurarCollisionCharacter(player.Character)
		MonitorarBackpack(player)
	end

	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart")
		ConfigurarCollisionCharacter(character)
		MonitorarBackpack(player)
	end)
end

DebugLog("Sistema DropTool inicializado!")
