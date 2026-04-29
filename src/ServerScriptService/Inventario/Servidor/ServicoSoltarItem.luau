--[[
    Script: ServicoSoltarItem.luau
    Caminho: src/ServerScriptService/Inventario/Servidor
    Responsabilidade: Valida e executa soltura de itens do inventario no mundo.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao roda sozinho nem cria fluxo de jogo por conta propria; depende dos scripts que importam este modulo.
    Funcoes principais: Iniciar, DebugLog, CalcularPosicaoDrop, ConfigurarCollisionGroups, ConfigurarCollisionCharacter, ConfigurarCollisionTool
]]
local ServicoDrop = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")

local ToolBuilder = require(ReplicatedStorage:WaitForChild("Equipamentos"):WaitForChild("ConstrutorFerramentas"))

local ALTURA_DROP = 2
local DISTANCIA_FRENTE = 3
local DEBUG = false

local COLLISION_GROUP_PLAYERS = "Players"
local COLLISION_GROUP_TOOLS = "DroppedTools"

local function DebugLog(...)
	if DEBUG then
		print("[ServicoDrop]", ...)
	end
end

local function CalcularPosicaoDrop(character, tipo)
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		warn("[ServicoDrop] HumanoidRootPart não encontrada!")
		return nil
	end

	local lookVector = humanoidRootPart.CFrame.LookVector
	local posicao = humanoidRootPart.Position + (lookVector * DISTANCIA_FRENTE) + Vector3.new(0, ALTURA_DROP, 0)

	local rotacaoPlayer = humanoidRootPart.CFrame - humanoidRootPart.CFrame.Position
	local cframeBase = CFrame.new(posicao) * rotacaoPlayer

	local cframeFinal
	if tipo == "Armaduras" then

		cframeFinal = cframeBase * CFrame.Angles(math.rad(-90), 0, 0)
	else

		cframeFinal = cframeBase * CFrame.Angles(0, 0, math.rad(90))
	end

	return cframeFinal
end

local function ConfigurarCollisionGroups()

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

	PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUP_PLAYERS, COLLISION_GROUP_TOOLS, false)

	DebugLog("Collision groups configurados!")
end

local function ConfigurarCollisionCharacter(character)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = COLLISION_GROUP_PLAYERS
		end
	end
	DebugLog("Character configurado com collision group:", COLLISION_GROUP_PLAYERS)
end

local function ConfigurarCollisionTool(tool)
	for _, part in ipairs(tool:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = COLLISION_GROUP_TOOLS
		end
	end
	DebugLog("Todas as partes do Tool configuradas com collision group:", COLLISION_GROUP_TOOLS)
end

local function ProcessarDrop(player, toolNome, quantidade)
	DebugLog("========================================")
	DebugLog("Processando drop do Tool:", toolNome, "Quantidade:", quantidade)

	if not player or not player.Parent then
		warn("[ServicoDrop] Player não está mais no jogo!")
		return
	end

	local character = player.Character
	if not character then
		warn("[ServicoDrop] Character não encontrado!")
		return
	end

	local tool = player.Backpack:FindFirstChild(toolNome) or character:FindFirstChild(toolNome)
	if not tool or not tool:IsA("Tool") then
		warn("[ServicoDrop] Tool não encontrado:", toolNome)
		return
	end

	local dadosFolder = tool:FindFirstChild("Dados")
	if dadosFolder then
		local tipoValue = dadosFolder:FindFirstChild("Tipo")
		if tipoValue and tipoValue.Value == "ArmasEquipadas" then
			warn("[ServicoDrop] Tentativa de dropar Tool do tipo 'ArmasEquipadas' bloqueada!")
			return
		end
	end

	local itemData = ToolBuilder.ExtrairDados(tool)
	if not itemData then
		warn("[ServicoDrop] ERRO: Não foi possível extrair dados do Tool!")
		return
	end

	DebugLog("Dados extraídos:", itemData.Nome or "N/A")

	local quantidadeAtual = itemData.Quantidade or 1
	if quantidade < quantidadeAtual then

		ToolBuilder.AtualizarQuantidade(tool, quantidadeAtual - quantidade)
		itemData.Quantidade = quantidade
		DebugLog("Dropando quantidade parcial:", quantidade, "Restando:", quantidadeAtual - quantidade)
	else

		DebugLog("Dropando quantidade total - destruindo Tool original")
		tool:Destroy()
	end

	local cframeDrop = CalcularPosicaoDrop(character, itemData.Tipo)
	if not cframeDrop then
		warn("[ServicoDrop] ERRO: Não foi possível calcular posição de drop!")
		return
	end

	DebugLog("Criando Tool no mundo usando ToolBuilder...")
	local toolNoMundo = ToolBuilder.CriarToolNoMundo(itemData, cframeDrop)

	if toolNoMundo then

		ConfigurarCollisionTool(toolNoMundo)
		DebugLog("Tool criado no mundo com sucesso:", toolNoMundo.Name)
	else
		warn("[ServicoDrop] ERRO: Falha ao criar Tool no mundo!")
	end

	DebugLog("========================================")
end

function ServicoDrop:Iniciar()
	DebugLog("Inicializando ServicoDrop...")

	local Remotos = ReplicatedStorage:WaitForChild("Remotos")
	local DroparToolEvent = Remotos:WaitForChild("DroparTool")

	ConfigurarCollisionGroups()

	DroparToolEvent.OnServerEvent:Connect(function(player, toolNome, quantidade)
		DebugLog("RemoteEvent recebido de:", player.Name, "Tool:", toolNome, "Quantidade:", quantidade)

		if type(toolNome) ~= "string" then
			warn("[ServicoDrop] Nome do Tool inválido!")
			return
		end

		if type(quantidade) ~= "number" or quantidade <= 0 then
			warn("[ServicoDrop] Quantidade inválida!")
			return
		end

		ProcessarDrop(player, toolNome, quantidade)
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			DebugLog("Character carregado para:", player.Name)
			character:WaitForChild("HumanoidRootPart")
			ConfigurarCollisionCharacter(character)
		end)

		if player.Character then
			ConfigurarCollisionCharacter(player.Character)
		end
	end)

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
