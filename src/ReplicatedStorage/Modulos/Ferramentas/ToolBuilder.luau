--[[
	ToolBuilder - Módulo de Geração de Tools
    ReplicatedStorage > Modulos > ToolBuilder.luau
	
	Responsável por criar Tools a partir de templates pré-definidos.
	Pega um template da pasta ToolsTemplates, clona e atualiza os valores
	dentro do folder "Dados" conforme os dados do item passado.
	
	ESTRUTURA DO TEMPLATE:
		Tool
		├── Handle (Part)
		└── Dados (Folder)
		    ├── Nome (StringValue)
		    ├── Id (StringValue)
		    ├── Tipo (StringValue)
		    ├── Quantidade (NumberValue)
		    ├── Peso (NumberValue)
		    └── ... outros atributos
	
	USO:
		local ToolBuilder = require(game.ReplicatedStorage.Modulos.Ferramentas.ToolBuilder)
		
		-- Criar Tool na backpack de um player
		local tool = ToolBuilder.CriarTool(itemData, player.Backpack)
		
		-- Criar Tool no mundo (item dropado)
		local tool = ToolBuilder.CriarToolNoMundo(itemData, posicaoCFrame)
		
		-- Criar Tool em um container (baú, etc.)
		local tool = ToolBuilder.CriarTool(itemData, bau.Inventario)

    TEMPLATES DOS TOOLS:
    ReplicatedStorage
    └── ToolsTemplates
        ├── Materiais
        │   ├── madeira_carvalho (Tool)
        │   ├── pedra_comum (Tool)
        │   └── ...
        ├── Armas
        │   ├── espada_ferro (Tool)
        │   ├── machado_guerra_ferro (Tool)
        │   └── ...
        ├── ArmasEquipadas
        │   ├── espada_ferro_equipada (Tool)
        │   ├── machado_guerra_ferro_equipada (Tool)
        │   └── ...
        ├── Ferramentas
        │   ├── picareta_ferro (Tool)
        │   ├── enxada_ferro (Tool)
        │   ├── machado_ferro (Tool)
        │   └── ...
        └── Armaduras
            ├── peitoral_ferro (Tool)
            ├── elmo_ferro (Tool)
            └── ...
--]]

local ToolBuilder = {}

-- ============================================
-- CONFIGURAÇÃO
-- ============================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TemplatesFolder = ReplicatedStorage:WaitForChild("ToolsTemplates")

-- ============================================
-- FUNÇÕES PRIVADAS
-- ============================================

-- Busca o template correto baseado no tipo e ID do item
local function ObterTemplate(itemData)
	warn("[ToolBuilder] Buscando template para:", itemData.Tipo, itemData.Id)

	if not itemData.Tipo then
		warn("[ToolBuilder] ERRO: itemData.Tipo não fornecido!")
		return nil
	end

	if not itemData.Id then
		warn("[ToolBuilder] ERRO: itemData.Id não fornecido!")
		return nil
	end

	-- Mapear tipo para pasta de templates
	local pastaTipo = TemplatesFolder:FindFirstChild(itemData.Tipo .. "s")
	if not pastaTipo then
		-- Tentar sem pluralização
		pastaTipo = TemplatesFolder:FindFirstChild(itemData.Tipo)
		if not pastaTipo then
			warn("[ToolBuilder] ERRO: Pasta de templates não encontrada para tipo:", itemData.Tipo)
			return nil
		end
	end

	-- Buscar template específico pelo ID
	local template = pastaTipo:FindFirstChild(itemData.Id)
	if not template then
		warn("[ToolBuilder] ERRO: Template não encontrado:", itemData.Id, "na pasta:", pastaTipo.Name)
		return nil
	end

	if not template:IsA("Tool") then
		warn("[ToolBuilder] ERRO: Template encontrado não é um Tool:", template.Name)
		return nil
	end

	warn("[ToolBuilder] Template encontrado:", template.Name)
	return template
end

-- Atualiza os valores dentro do folder "Dados" do Tool
local function AtualizarDados(tool, itemData)
	warn("[ToolBuilder] Atualizando dados do Tool:", tool.Name)

	local dadosFolder = tool:FindFirstChild("Dados")
	if not dadosFolder then
		warn("[ToolBuilder] ERRO: Folder 'Dados' não encontrado no template:", tool.Name)
		return false
	end

	-- Atualizar cada campo do itemData
	for campo, valor in pairs(itemData) do
		local valueObject = dadosFolder:FindFirstChild(campo)

		if valueObject then
			-- Atualizar valor existente
			if valueObject:IsA("StringValue") then
				valueObject.Value = tostring(valor)
			elseif valueObject:IsA("NumberValue") then
				valueObject.Value = tonumber(valor) or 0
			elseif valueObject:IsA("BoolValue") then
				valueObject.Value = valor == true or valor == "true"
			elseif valueObject:IsA("IntValue") then
				valueObject.Value = math.floor(tonumber(valor) or 0)
			end

			warn("[ToolBuilder]   Atualizado:", campo, "=", valueObject.Value)
		else
			-- Criar novo ValueObject se não existir
			local tipoValor = type(valor)
			local novoValue = nil

			if tipoValor == "string" then
				novoValue = Instance.new("StringValue")
				novoValue.Value = valor
			elseif tipoValor == "number" then
				-- Verificar se é inteiro ou decimal
				if valor == math.floor(valor) then
					novoValue = Instance.new("IntValue")
				else
					novoValue = Instance.new("NumberValue")
				end
				novoValue.Value = valor
			elseif tipoValor == "boolean" then
				novoValue = Instance.new("BoolValue")
				novoValue.Value = valor
			end

			if novoValue then
				novoValue.Name = campo
				novoValue.Parent = dadosFolder
				warn("[ToolBuilder]   Criado novo campo:", campo, "=", novoValue.Value)
			end
		end
	end

	-- Atualizar o nome do Tool baseado no campo "Nome"
	local nomeValue = dadosFolder:FindFirstChild("Nome")
	if nomeValue and nomeValue:IsA("StringValue") then
		tool.Name = nomeValue.Value
		warn("[ToolBuilder] Nome do Tool atualizado para:", tool.Name)
	end

	return true
end

-- Valida os dados do item antes de criar
local function ValidarItemData(itemData)
	if not itemData then
		warn("[ToolBuilder] ERRO: itemData é nil!")
		return false
	end

	if type(itemData) ~= "table" then
		warn("[ToolBuilder] ERRO: itemData não é uma tabela!")
		return false
	end

	-- Campos obrigatórios
	local camposObrigatorios = { "Tipo", "Id", "Nome" }
	for _, campo in ipairs(camposObrigatorios) do
		if not itemData[campo] then
			warn("[ToolBuilder] ERRO: Campo obrigatório ausente:", campo)
			return false
		end
	end

	-- Validação de tipos específicos
	if itemData.Tipo == "Materiais" and not itemData.Quantidade then
		warn("[ToolBuilder] AVISO: Materiais sem campo 'Quantidade', definindo como 1")
		itemData.Quantidade = 1
	end

	if not itemData.Peso then
		warn("[ToolBuilder] AVISO: Item sem campo 'Peso', definindo como 0")
		itemData.Peso = 0
	end

	return true
end

-- ============================================
-- FUNÇÕES PÚBLICAS
-- ============================================

--[[
    CriarTool
    Cria um Tool baseado nos dados fornecidos e o coloca no parent especificado.
    
    @param itemData (table): Dados do item (Tipo, Id, Nome, Quantidade, Peso, etc.)
    @param parent (Instance): Onde colocar o Tool criado (Backpack, Folder, etc.)
    @return (Tool|nil): Tool criado ou nil se falhar
]]
function ToolBuilder.CriarTool(itemData, parent)
	warn("[ToolBuilder] ========================================")
	warn("[ToolBuilder] Iniciando criação de Tool")

	-- Validar dados
	if not ValidarItemData(itemData) then
		warn("[ToolBuilder] ERRO: Validação de itemData falhou!")
		return nil
	end

	if not parent then
		warn("[ToolBuilder] ERRO: Parent não fornecido!")
		return nil
	end

	-- If parent is a player's Backpack, try to stack with an existing Tool
	if parent and parent:IsA("Backpack") then
		-- First, check if the player has the same item equipped (in Character)
		local player = parent.Parent
		if player and player:IsA("Player") then
			local character = player.Character
			if character then
				local equippedTool = character:FindFirstChildOfClass("Tool")
				if equippedTool then
					local dadosEquipped = ToolBuilder.ExtrairDados(equippedTool)
					if dadosEquipped and ToolBuilder.PodeEmpilhar(dadosEquipped, itemData) then
						local quantidadeAtual = dadosEquipped.Quantidade or 1
						local adicionar = itemData.Quantidade or 1
						local novaQuantidade = quantidadeAtual + adicionar
						ToolBuilder.AtualizarQuantidade(equippedTool, novaQuantidade)
						warn("[ToolBuilder] Item empilhado no Tool equipado. Nova quantidade:", novaQuantidade)
						return equippedTool
					end
				end
			end
		end

		-- If not stacked with equipped tool, check Backpack
		for _, child in ipairs(parent:GetChildren()) do
			if child and child:IsA("Tool") then
				local dadosExist = ToolBuilder.ExtrairDados(child)
				if dadosExist and ToolBuilder.PodeEmpilhar(dadosExist, itemData) then
					local quantidadeAtual = dadosExist.Quantidade or 1
					local adicionar = itemData.Quantidade or 1
					local novaQuantidade = quantidadeAtual + adicionar
					ToolBuilder.AtualizarQuantidade(child, novaQuantidade)
					warn("[ToolBuilder] Item empilhado na Backpack. Nova quantidade:", novaQuantidade)
					return child
				end
			end
		end
	end

	-- Obter template
	local template = ObterTemplate(itemData)
	if not template then
		warn("[ToolBuilder] ERRO: Falha ao obter template!")
		return nil
	end

	-- Clonar template
	local novoTool = template:Clone()
	warn("[ToolBuilder] Template clonado com sucesso")

	-- Atualizar dados
	local sucesso = AtualizarDados(novoTool, itemData)
	if not sucesso then
		warn("[ToolBuilder] ERRO: Falha ao atualizar dados do Tool!")
		novoTool:Destroy()
		return nil
	end

	-- Configurações adicionais baseadas no tipo
	if itemData.Tipo == "ArmasEquipadas" then
		novoTool.CanBeDropped = false
		warn("[ToolBuilder] ArmasEquipadas configurada como não dropável")
	end

	-- Configurar Draggable como false para Tools na backpack
	local dadosFolder = novoTool:FindFirstChild("Dados")
	if dadosFolder then
		local draggableValue = dadosFolder:FindFirstChild("Draggable")
		if draggableValue and draggableValue:IsA("BoolValue") then
			draggableValue.Value = false
			warn("[ToolBuilder] Draggable definido como false")
		end
	end

	-- Remover qualquer ProximityPrompt se existir (buscar por tipo, não por nome)
	local handle = novoTool:FindFirstChild("Handle")
	if handle then
		for _, child in ipairs(handle:GetChildren()) do
			if child:IsA("ProximityPrompt") then
				child:Destroy()
				warn("[ToolBuilder] ProximityPrompt removido do Tool")
			end
		end
	end

	-- Configurar componentes visuais e físicos para uso na mão (Backpack)
	ToolBuilder.RestaurarComponentesTool(novoTool)

	-- Parentar o Tool
	novoTool.Parent = parent
	warn("[ToolBuilder] Tool criado e parentado com sucesso:", novoTool.Name)
	warn("[ToolBuilder] ========================================")

	return novoTool
end

--[[
    CriarToolNoMundo
    Cria um Tool no mundo (como item dropado) com ProximityPrompt para coleta.
    
    @param itemData (table): Dados do item
    @param cframe (CFrame): Posição onde spawnar o item
    @return (Tool|nil): Tool dropado no mundo ou nil se falhar
]]
function ToolBuilder.CriarToolNoMundo(itemData, cframe)
	warn("[ToolBuilder] ========================================")
	warn("[ToolBuilder] Criando item no mundo")

	-- Validar dados
	if not ValidarItemData(itemData) then
		warn("[ToolBuilder] ERRO: Validação de itemData falhou!")
		return nil
	end

	if not cframe then
		warn("[ToolBuilder] ERRO: CFrame não fornecido!")
		return nil
	end

	-- Obter template
	local template = ObterTemplate(itemData)
	if not template then
		warn("[ToolBuilder] ERRO: Falha ao obter template!")
		return nil
	end

	-- Clonar template
	local toolClone = template:Clone()
	warn("[ToolBuilder] Template clonado para o mundo")

	-- Atualizar dados
	local sucesso = AtualizarDados(toolClone, itemData)
	if not sucesso then
		warn("[ToolBuilder] ERRO: Falha ao atualizar dados!")
		toolClone:Destroy()
		return nil
	end

	-- Obter o Handle
	local handle = toolClone:FindFirstChild("Handle")
	if not handle then
		warn("[ToolBuilder] ERRO: Handle não encontrado no template!")
		toolClone:Destroy()
		return nil
	end

	-- Configurar Draggable como true para items no mundo
	local dadosFolder = toolClone:FindFirstChild("Dados")
	if dadosFolder then
		local draggableValue = dadosFolder:FindFirstChild("Draggable")
		if draggableValue and draggableValue:IsA("BoolValue") then
			draggableValue.Value = true
			warn("[ToolBuilder] Draggable definido como true para item no mundo")
		end
	end

	-- Configurar Tool para não poder ser dropado novamente (evita loops)
	toolClone.CanBeDropped = false

	-- Parentar o Tool completo ao workspace PRIMEIRO
	toolClone.Parent = workspace
	warn("[ToolBuilder] Tool parentado ao workspace")

	-- Configurar Handle DEPOIS de parentar (ancorado e colidível)
	handle.Anchored = false
	handle.CanCollide = true
	handle.CFrame = cframe

	-- Garantir que todas as partes filhas do Handle também estejam visíveis e colidíveis (armaduras, etc.)
	for _, desc in ipairs(handle:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Transparency = 0
			desc.Anchored = false
			desc.CanCollide = true
			desc.CanTouch = true
			desc.CanQuery = true
		end
	end

	warn("[ToolBuilder] Handle posicionado em:", cframe.Position)

	-- Atualizar ObjectText do ProximityPrompt com quantidade (se > 1)
	local quantidade = itemData.Quantidade or 1
	if quantidade > 1 then
		for _, child in ipairs(handle:GetChildren()) do
			if child:IsA("ProximityPrompt") then
				local nomeBase = child.ObjectText or ""
				child.ObjectText = nomeBase .. " (x" .. tostring(quantidade) .. ")"
				warn("[ToolBuilder] ProximityPrompt ObjectText atualizado com quantidade:", child.ObjectText)
				break
			end
		end
	end

	warn("[ToolBuilder] Tool dropado criado no mundo:", toolClone.Name)
	warn("[ToolBuilder] ========================================")

	return toolClone
end

--[[
    ExtrairDados
    Extrai os dados de um Tool existente (lê o folder "Dados").
    
    @param tool (Tool): Tool para extrair dados
    @return (table|nil): Tabela com os dados ou nil se falhar
]]
function ToolBuilder.ExtrairDados(tool)
	if not tool or not tool:IsA("Tool") then
		warn("[ToolBuilder] ERRO: Tool inválido fornecido para ExtrairDados!")
		return nil
	end

	local dadosFolder = tool:FindFirstChild("Dados")
	if not dadosFolder then
		warn("[ToolBuilder] ERRO: Folder 'Dados' não encontrado no Tool:", tool.Name)
		return nil
	end

	local dados = {}

	-- Ler todos os ValueObjects
	for _, valueObject in ipairs(dadosFolder:GetChildren()) do
		if
			valueObject:IsA("StringValue")
			or valueObject:IsA("NumberValue")
			or valueObject:IsA("IntValue")
			or valueObject:IsA("BoolValue")
		then
			dados[valueObject.Name] = valueObject.Value
		end
	end

	warn("[ToolBuilder] Dados extraídos do Tool:", tool.Name)
	return dados
end

--- Restaura as propriedades visuais de um Tool (para quando ele volta para a Backpack ou é criado)
function ToolBuilder.RestaurarComponentesTool(tool: Tool)
	for _, desc in ipairs(tool:GetDescendants()) do
		if desc:IsA("BasePart") then
			-- Verificar se a parte está dentro de um Accessory
			local ehAcessorio = desc:FindFirstAncestorOfClass("Accessory")

			if ehAcessorio then
				-- Acessórios dentro do Tool ficam invisíveis, ancorados e sem colisão
				desc.Transparency = 1
				desc.CanCollide = false
				desc.CanTouch = false
				desc.CanQuery = false
				desc.Massless = true
				desc.Anchored = true
			else
				-- Parte principal do Tool (Handle/Handler) fica visível, mas sem colisão/toque
				desc.Transparency = 0
				desc.CanCollide = false
				desc.CanTouch = false
				desc.CanQuery = false
				desc.Massless = false
				desc.Anchored = false
			end
		elseif desc:IsA("Decal") or desc:IsA("Texture") then
			local ehAcessorio = desc:FindFirstAncestorOfClass("Accessory")
			desc.Transparency = if ehAcessorio then 1 else 0
		elseif desc:IsA("Light") or desc:IsA("ParticleEmitter") or desc:IsA("Trail") or desc:IsA("Beam") then
			local ehAcessorio = desc:FindFirstAncestorOfClass("Accessory")
			desc.Enabled = not ehAcessorio
		end
	end
end

--[[
    ExtrairDadosDoMundo
    Extrai os dados de um item dropado no mundo (Tool ou Model com folder "Dados").
    
    @param itemInstance (Tool|Model): Tool ou Model do item no mundo
    @return (table|nil): Tabela com os dados ou nil se falhar
]]
function ToolBuilder.ExtrairDadosDoMundo(itemInstance)
	if not itemInstance then
		warn("[ToolBuilder] ERRO: Instância inválida fornecida para ExtrairDadosDoMundo!")
		return nil
	end

	-- Aceitar tanto Tool quanto Model
	if not (itemInstance:IsA("Tool") or itemInstance:IsA("Model")) then
		warn("[ToolBuilder] ERRO: ExtrairDadosDoMundo espera Tool ou Model, recebeu:", itemInstance.ClassName)
		return nil
	end

	local dadosFolder = itemInstance:FindFirstChild("Dados")
	if not dadosFolder then
		warn("[ToolBuilder] ERRO: Folder 'Dados' não encontrado em:", itemInstance.Name)
		return nil
	end

	local dados = {}

	-- Ler todos os ValueObjects
	for _, valueObject in ipairs(dadosFolder:GetChildren()) do
		if
			valueObject:IsA("StringValue")
			or valueObject:IsA("NumberValue")
			or valueObject:IsA("IntValue")
			or valueObject:IsA("BoolValue")
		then
			dados[valueObject.Name] = valueObject.Value
		end
	end

	warn("[ToolBuilder] Dados extraídos do mundo:", itemInstance.Name)
	return dados
end

--[[
    PodeEmpilhar
    Verifica se dois itens podem ser empilhados juntos.
    
    @param itemA (table): Dados do primeiro item
    @param itemB (table): Dados do segundo item
    @return (boolean): true se podem empilhar, false caso contrário
]]
function ToolBuilder.PodeEmpilhar(itemA, itemB)
	-- Tipos diferentes não empilham
	if itemA.Tipo ~= itemB.Tipo then
		return false
	end

	-- IDs diferentes não empilham
	if itemA.Id ~= itemB.Id then
		return false
	end

	-- Materiais, Comidas, Bebidas, Pocoes e Ingredientes empilham livremente por ID
	if
		itemA.Tipo == "Materiais"
		or itemA.Tipo == "Comidas"
		or itemA.Tipo == "Bebidas"
		or itemA.Tipo == "Pocoes"
		or itemA.Tipo == "Ingredientes"
	then
		return true
	end

	-- Armas, Armaduras e Ferramentas empilham apenas se todos atributos forem idênticos
	if itemA.Tipo == "Armas" or itemA.Tipo == "Armaduras" or itemA.Tipo == "Ferramentas" then
		local atributosParaComparar = { "MaterialBase", "Upgrade", "Dano", "Resistencia", "Eficiencia", "Slot" }

		for _, atributo in ipairs(atributosParaComparar) do
			if itemA[atributo] ~= itemB[atributo] then
				return false
			end
		end

		return true
	end

	-- ArmasEquipadas não empilham
	if itemA.Tipo == "ArmasEquipadas" then
		return false
	end

	-- Padrão: não empilhar
	return false
end

--[[
    AtualizarQuantidade
    Atualiza a quantidade de um Tool existente.
    
    @param tool (Tool): Tool para atualizar
    @param novaQuantidade (number): Nova quantidade
    @return (boolean): true se sucesso, false se falhar
]]
function ToolBuilder.AtualizarQuantidade(tool, novaQuantidade)
	if not tool or not tool:IsA("Tool") then
		warn("[ToolBuilder] ERRO: Tool inválido fornecido para AtualizarQuantidade!")
		return false
	end

	local dadosFolder = tool:FindFirstChild("Dados")
	if not dadosFolder then
		warn("[ToolBuilder] ERRO: Folder 'Dados' não encontrado no Tool:", tool.Name)
		return false
	end

	local quantidadeValue = dadosFolder:FindFirstChild("Quantidade")
	if not quantidadeValue then
		warn("[ToolBuilder] ERRO: Campo 'Quantidade' não encontrado no Tool:", tool.Name)
		return false
	end

	quantidadeValue.Value = novaQuantidade
	warn("[ToolBuilder] Quantidade atualizada para:", novaQuantidade, "no Tool:", tool.Name)

	return true
end

--[[
    CalcularPesoTotal
    Calcula o peso total de um item considerando quantidade.
    
    @param itemData (table): Dados do item
    @return (number): Peso total
]]
function ToolBuilder.CalcularPesoTotal(itemData)
	local pesoUnitario = itemData.Peso or 0
	local quantidade = itemData.Quantidade or 1
	return pesoUnitario * quantidade
end

--[[
    CriarArmaEquipada
    Cria um Tool do tipo ArmaEquipada a partir dos dados de uma arma original.

    Fluxo:
    1. Converte o Id da arma para o Id do template equipada (ex: "espada_ferro" → "espada_ferro-equipada")
    2. Clona o template de ArmasEquipadas correspondente
    3. Sobrescreve os Dados com os valores da arma original (Dano, Alcance, Peso, etc.)
    4. NÃO altera Dados.modoAnimacao (mantém o valor do template)
    5. Define CanBeDropped = false
    6. Coloca no parent

    @param dadosArma (table): Dados extraídos da arma original via ExtrairDados()
    @param parent (Instance): Onde colocar a ArmaEquipada (tipicamente player.Backpack)
    @return (Tool|nil): ArmaEquipada criada ou nil se falhar
]]
function ToolBuilder.CriarArmaEquipada(dadosArma, parent)
	warn("[ToolBuilder] ========================================")
	warn("[ToolBuilder] Criando ArmaEquipada a partir de:", dadosArma.Id)

	if not dadosArma or not dadosArma.Id then
		warn("[ToolBuilder] ERRO: dadosArma inválidos ou sem Id!")
		return nil
	end

	if not parent then
		warn("[ToolBuilder] ERRO: Parent não fornecido para ArmaEquipada!")
		return nil
	end

	-- Resolver o Id do template equipada
	local idEquipada = dadosArma.Id .. "-equipada"
	warn("[ToolBuilder] Template equipada ID:", idEquipada)

	-- Buscar o template na pasta ArmasEquipadas
	local pastaEquipadas = TemplatesFolder:FindFirstChild("ArmasEquipadas")
	if not pastaEquipadas then
		warn("[ToolBuilder] ERRO: Pasta 'ArmasEquipadas' não encontrada em ToolsTemplates!")
		return nil
	end

	local template = pastaEquipadas:FindFirstChild(idEquipada)
	if not template then
		warn("[ToolBuilder] ERRO: Template equipada não encontrado:", idEquipada)
		return nil
	end

	if not template:IsA("Tool") then
		warn("[ToolBuilder] ERRO: Template equipada não é um Tool:", idEquipada)
		return nil
	end

	-- Clonar o template
	local armaEquipada = template:Clone()
	warn("[ToolBuilder] Template equipada clonado com sucesso")

	-- Sobrescrever dados com valores da arma original
	local dadosFolder = armaEquipada:FindFirstChild("Dados")
	if dadosFolder then
		-- Campos a sobrescrever da arma original
		local camposSobrescrever = {
			"Dano",
			"Alcance",
			"Peso",
			"MaterialBase",
			"Upgrade",
			"Categoria",
		}

		for _, campo in ipairs(camposSobrescrever) do
			local valor = dadosArma[campo]
			if valor ~= nil then
				local valueObject = dadosFolder:FindFirstChild(campo)
				if valueObject then
					-- Atualizar existente
					if valueObject:IsA("StringValue") then
						valueObject.Value = tostring(valor)
					elseif valueObject:IsA("NumberValue") then
						valueObject.Value = tonumber(valor) or 0
					elseif valueObject:IsA("BoolValue") then
						valueObject.Value = valor == true
					elseif valueObject:IsA("IntValue") then
						valueObject.Value = math.floor(tonumber(valor) or 0)
					end
				else
					-- Criar novo se não existir
					local tipoValor = type(valor)
					local novoValue = nil

					if tipoValor == "string" then
						novoValue = Instance.new("StringValue")
						novoValue.Value = valor
					elseif tipoValor == "number" then
						novoValue = Instance.new("NumberValue")
						novoValue.Value = valor
					elseif tipoValor == "boolean" then
						novoValue = Instance.new("BoolValue")
						novoValue.Value = valor
					end

					if novoValue then
						novoValue.Name = campo
						novoValue.Parent = dadosFolder
					end
				end
				warn("[ToolBuilder]   Sobrescrito:", campo, "=", tostring(valor))
			end
		end

		-- Garantir que Tipo está correto (sempre ArmasEquipadas)
		local tipoValue = dadosFolder:FindFirstChild("Tipo")
		if tipoValue and tipoValue:IsA("StringValue") then
			tipoValue.Value = "ArmasEquipadas"
		end

		-- Quantidade sempre 1 para ArmaEquipada
		local qtdValue = dadosFolder:FindFirstChild("Quantidade")
		if qtdValue then
			qtdValue.Value = 1
		end
	end

	-- Configurar ArmaEquipada
	armaEquipada.CanBeDropped = false

	-- Remover ProximityPrompt se existir
	local handle = armaEquipada:FindFirstChild("Handle")
	if handle then
		for _, child in ipairs(handle:GetChildren()) do
			if child:IsA("ProximityPrompt") then
				child:Destroy()
			end
		end
	end

	-- Ocultar componentes visuais internos do Tool
	-- (só os clones no Character serão visíveis)
	for _, desc in ipairs(armaEquipada:GetDescendants()) do
		if desc:IsA("BasePart") then
			-- Se for parte de um Acessório, ocultar e ancorar
			local ehAcessorio = desc:FindFirstAncestorOfClass("Accessory")
			if ehAcessorio then
				desc.Transparency = 1
				desc.CanCollide = false
				desc.CanTouch = false
				desc.CanQuery = false
				desc.Massless = true
				desc.Anchored = true
			else
				-- Se for parte da arma (Handle), deve ficar invisível mas NÃO ancorado
				-- para poder ser usado pelo sistema de armas do Roblox
				desc.Transparency = 1
				desc.CanCollide = false
				desc.CanTouch = false
				desc.CanQuery = false
				desc.Massless = true
				desc.Anchored = false
			end
		elseif desc:IsA("Decal") or desc:IsA("Texture") then
			desc.Transparency = 1
		elseif desc:IsA("ParticleEmitter") or desc:IsA("Trail") or desc:IsA("Beam") then
			desc.Enabled = false
		elseif desc:IsA("Light") then
			desc.Enabled = false
		end
	end
	warn("[ToolBuilder]   Componentes visuais internos ocultados (Handle desancorado)")

	-- Parentar
	armaEquipada.Parent = parent
	warn("[ToolBuilder] ArmaEquipada criada:", armaEquipada.Name, "→", parent:GetFullName())
	warn("[ToolBuilder] ========================================")

	return armaEquipada
end

return ToolBuilder
