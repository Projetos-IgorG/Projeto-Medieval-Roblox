--[[
    Script: ConstrutorFerramentas.luau
    Caminho: src/ReplicatedStorage/Equipamentos
    Responsabilidade: Monta Tools do Roblox a partir dos dados e modelos de equipamentos.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao roda sozinho nem cria fluxo de jogo por conta propria; depende dos scripts que importam este modulo.
    Funcoes principais: CriarTool, CriarToolNoMundo, ExtrairDados, RestaurarComponentesTool, ExtrairDadosDoMundo, PodeEmpilhar
]]
local ToolBuilder = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TemplatesFolder = ReplicatedStorage:WaitForChild("Equipamentos"):WaitForChild("Modelos")
local ColetaFolder = ReplicatedStorage:WaitForChild("Equipamentos"):WaitForChild("Coleta")
local ColetorToolTemplate = ColetaFolder:WaitForChild("ColetarTool")

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

	local pastaTipo = TemplatesFolder:FindFirstChild(itemData.Tipo .. "s")
	if not pastaTipo then

		pastaTipo = TemplatesFolder:FindFirstChild(itemData.Tipo)
		if not pastaTipo then
			warn("[ToolBuilder] ERRO: Pasta de templates não encontrada para tipo:", itemData.Tipo)
			return nil
		end
	end

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

local function AtualizarDados(tool, itemData)
	warn("[ToolBuilder] Atualizando dados do Tool:", tool.Name)

	local dadosFolder = tool:FindFirstChild("Dados")
	if not dadosFolder then
		warn("[ToolBuilder] ERRO: Folder 'Dados' não encontrado no template:", tool.Name)
		return false
	end

	for campo, valor in pairs(itemData) do
		local valueObject = dadosFolder:FindFirstChild(campo)

		if valueObject then

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

			local tipoValor = type(valor)
			local novoValue = nil

			if tipoValor == "string" then
				novoValue = Instance.new("StringValue")
				novoValue.Value = valor
			elseif tipoValor == "number" then

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

	local nomeValue = dadosFolder:FindFirstChild("Nome")
	if nomeValue and nomeValue:IsA("StringValue") then
		tool.Name = nomeValue.Value
		warn("[ToolBuilder] Nome do Tool atualizado para:", tool.Name)
	end

	return true
end

local function ValidarItemData(itemData)
	if not itemData then
		warn("[ToolBuilder] ERRO: itemData é nil!")
		return false
	end

	if type(itemData) ~= "table" then
		warn("[ToolBuilder] ERRO: itemData não é uma tabela!")
		return false
	end

	local camposObrigatorios = { "Tipo", "Id", "Nome" }
	for _, campo in ipairs(camposObrigatorios) do
		if not itemData[campo] then
			warn("[ToolBuilder] ERRO: Campo obrigatório ausente:", campo)
			return false
		end
	end

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

local function RemoverColetaTool(tool)
	local remover = {}

	for _, desc in ipairs(tool:GetDescendants()) do
		if desc:IsA("ProximityPrompt") then
			if desc.Name == "ColetarTool" or desc.ActionText == "Coletar" or desc.ActionText == "Pegar" then
				table.insert(remover, desc)
			end
		elseif desc:IsA("Script") then
			if desc.Name == "Coletar" or desc.Name == "ColetarTool" or desc:GetAttribute("ColetaToolBuilder") == true then
				table.insert(remover, desc)
			end
		elseif desc:IsA("Folder") and desc.Name == "ColetarTool" then
			table.insert(remover, desc)
		end
	end

	for _, instancia in ipairs(remover) do
		if instancia.Parent then
			instancia:Destroy()
		end
	end
end

local function CriarPromptColeta(tool, handle, itemData)
	RemoverColetaTool(tool)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ColetarTool"
	prompt.ActionText = "Coletar"
	prompt.ObjectText = tostring(itemData.Nome or tool.Name)
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.1
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Parent = handle

	local quantidade = tonumber(itemData.Quantidade) or 1
	if quantidade > 1 then
		prompt.ObjectText = prompt.ObjectText .. " (x" .. tostring(quantidade) .. ")"
	end

	local coletor = ColetorToolTemplate:Clone()
	coletor.Name = "ColetarTool"
	coletor:SetAttribute("ColetaToolBuilder", true)
	coletor.Parent = tool

	return prompt
end

function ToolBuilder.CriarTool(itemData, parent)
	warn("[ToolBuilder] ========================================")
	warn("[ToolBuilder] Iniciando criação de Tool")

	if not ValidarItemData(itemData) then
		warn("[ToolBuilder] ERRO: Validação de itemData falhou!")
		return nil
	end

	if not parent then
		warn("[ToolBuilder] ERRO: Parent não fornecido!")
		return nil
	end

	if parent and parent:IsA("Backpack") then

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

	local template = ObterTemplate(itemData)
	if not template then
		warn("[ToolBuilder] ERRO: Falha ao obter template!")
		return nil
	end

	local novoTool = template:Clone()
	warn("[ToolBuilder] Template clonado com sucesso")
	RemoverColetaTool(novoTool)

	local sucesso = AtualizarDados(novoTool, itemData)
	if not sucesso then
		warn("[ToolBuilder] ERRO: Falha ao atualizar dados do Tool!")
		novoTool:Destroy()
		return nil
	end

	if itemData.Tipo == "ArmasEquipadas" then
		novoTool.CanBeDropped = false
		warn("[ToolBuilder] ArmasEquipadas configurada como não dropável")
	end

	local dadosFolder = novoTool:FindFirstChild("Dados")
	if dadosFolder then
		local draggableValue = dadosFolder:FindFirstChild("Draggable")
		if draggableValue and draggableValue:IsA("BoolValue") then
			draggableValue.Value = false
			warn("[ToolBuilder] Draggable definido como false")
		end
	end

	local handle = novoTool:FindFirstChild("Handle")
	if handle then
		for _, child in ipairs(handle:GetChildren()) do
			if child:IsA("ProximityPrompt") then
				child:Destroy()
				warn("[ToolBuilder] ProximityPrompt removido do Tool")
			end
		end
	end

	ToolBuilder.RestaurarComponentesTool(novoTool)

	novoTool.Parent = parent
	warn("[ToolBuilder] Tool criado e parentado com sucesso:", novoTool.Name)
	warn("[ToolBuilder] ========================================")

	return novoTool
end

function ToolBuilder.CriarToolNoMundo(itemData, cframe)
	warn("[ToolBuilder] ========================================")
	warn("[ToolBuilder] Criando item no mundo")

	if not ValidarItemData(itemData) then
		warn("[ToolBuilder] ERRO: Validação de itemData falhou!")
		return nil
	end

	if not cframe then
		warn("[ToolBuilder] ERRO: CFrame não fornecido!")
		return nil
	end

	local template = ObterTemplate(itemData)
	if not template then
		warn("[ToolBuilder] ERRO: Falha ao obter template!")
		return nil
	end

	local toolClone = template:Clone()
	warn("[ToolBuilder] Template clonado para o mundo")
	RemoverColetaTool(toolClone)

	local sucesso = AtualizarDados(toolClone, itemData)
	if not sucesso then
		warn("[ToolBuilder] ERRO: Falha ao atualizar dados!")
		toolClone:Destroy()
		return nil
	end

	local handle = toolClone:FindFirstChild("Handle")
	if not handle then
		warn("[ToolBuilder] ERRO: Handle não encontrado no template!")
		toolClone:Destroy()
		return nil
	end

	local dadosFolder = toolClone:FindFirstChild("Dados")
	if dadosFolder then
		local draggableValue = dadosFolder:FindFirstChild("Draggable")
		if draggableValue and draggableValue:IsA("BoolValue") then
			draggableValue.Value = true
			warn("[ToolBuilder] Draggable definido como true para item no mundo")
		end
	end

	toolClone.CanBeDropped = false

	CriarPromptColeta(toolClone, handle, itemData)

	toolClone.Parent = workspace
	warn("[ToolBuilder] Tool parentado ao workspace")

	handle.Anchored = false
	handle.CanCollide = true
	handle.CFrame = cframe

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

	warn("[ToolBuilder] Tool dropado criado no mundo:", toolClone.Name)
	warn("[ToolBuilder] ========================================")

	return toolClone
end

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

function ToolBuilder.RestaurarComponentesTool(tool: Tool)
	for _, desc in ipairs(tool:GetDescendants()) do
		if desc:IsA("BasePart") then

			local ehComponenteVisual = desc:FindFirstAncestorOfClass("Accessory")
				or desc:FindFirstAncestorOfClass("Model")

			if ehComponenteVisual then

				desc.Transparency = 1
				desc.CanCollide = false
				desc.CanTouch = false
				desc.CanQuery = false
				desc.Massless = true
				desc.Anchored = true
			else

				desc.Transparency = 0
				desc.CanCollide = false
				desc.CanTouch = false
				desc.CanQuery = false
				desc.Massless = false
				desc.Anchored = false
			end
		elseif desc:IsA("Decal") or desc:IsA("Texture") then
			local ehComponenteVisual = desc:FindFirstAncestorOfClass("Accessory")
				or desc:FindFirstAncestorOfClass("Model")
			desc.Transparency = if ehComponenteVisual then 1 else 0
		elseif desc:IsA("Light") or desc:IsA("ParticleEmitter") or desc:IsA("Trail") or desc:IsA("Beam") then
			local ehComponenteVisual = desc:FindFirstAncestorOfClass("Accessory")
				or desc:FindFirstAncestorOfClass("Model")
			desc.Enabled = not ehComponenteVisual
		end
	end
end

function ToolBuilder.ExtrairDadosDoMundo(itemInstance)
	if not itemInstance then
		warn("[ToolBuilder] ERRO: Instância inválida fornecida para ExtrairDadosDoMundo!")
		return nil
	end

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

function ToolBuilder.PodeEmpilhar(itemA, itemB)

	if itemA.Tipo ~= itemB.Tipo then
		return false
	end

	if itemA.Id ~= itemB.Id then
		return false
	end

	if
		itemA.Tipo == "Materiais"
		or itemA.Tipo == "Comidas"
		or itemA.Tipo == "Bebidas"
		or itemA.Tipo == "Pocoes"
		or itemA.Tipo == "Ingredientes"
	then
		return true
	end

	if itemA.Tipo == "Armas" or itemA.Tipo == "Armaduras" or itemA.Tipo == "Ferramentas" then
		local atributosParaComparar = { "MaterialBase", "Upgrade", "Dano", "Resistencia", "Eficiencia", "Slot" }

		for _, atributo in ipairs(atributosParaComparar) do
			if itemA[atributo] ~= itemB[atributo] then
				return false
			end
		end

		return true
	end

	if itemA.Tipo == "ArmasEquipadas" then
		return false
	end

	return false
end

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

function ToolBuilder.CalcularPesoTotal(itemData)
	local pesoUnitario = itemData.Peso or 0
	local quantidade = itemData.Quantidade or 1
	return pesoUnitario * quantidade
end

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

	local idEquipada = dadosArma.Id .. "-equipada"
	warn("[ToolBuilder] Template equipada ID:", idEquipada)

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

	local armaEquipada = template:Clone()
	warn("[ToolBuilder] Template equipada clonado com sucesso")

	local dadosFolder = armaEquipada:FindFirstChild("Dados")
	if dadosFolder then

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

		local tipoValue = dadosFolder:FindFirstChild("Tipo")
		if tipoValue and tipoValue:IsA("StringValue") then
			tipoValue.Value = "ArmasEquipadas"
		end

		local qtdValue = dadosFolder:FindFirstChild("Quantidade")
		if qtdValue then
			qtdValue.Value = 1
		end
	end

	armaEquipada.CanBeDropped = false

	local handle = armaEquipada:FindFirstChild("Handle")
	if handle then
		for _, child in ipairs(handle:GetChildren()) do
			if child:IsA("ProximityPrompt") then
				child:Destroy()
			end
		end
	end

	for _, desc in ipairs(armaEquipada:GetDescendants()) do
		if desc:IsA("BasePart") then

			local ehComponenteVisual = desc:FindFirstAncestorOfClass("Accessory")
				or desc:FindFirstAncestorOfClass("Model")
			if ehComponenteVisual then
				desc.Transparency = 1
				desc.CanCollide = false
				desc.CanTouch = false
				desc.CanQuery = false
				desc.Massless = true
				desc.Anchored = true
			else

				desc.Transparency = 1
				desc.CanCollide = false
				desc.CanTouch = false
				desc.CanQuery = false
				desc.Massless = true
				desc.Anchored = false
			end
		elseif desc:IsA("Decal") or desc:IsA("Texture") then
			desc.Transparency = 1
		elseif desc:IsA("ParticleEmitter") or desc:IsA("Trail") or desc:IsA("Beam") or desc:IsA("Light") then
			desc.Enabled = false
		end
	end
	warn("[ToolBuilder]   Componentes visuais internos ocultados (Handle desancorado)")

	armaEquipada.Parent = parent
	warn("[ToolBuilder] ArmaEquipada criada:", armaEquipada.Name, "->", parent:GetFullName())
	warn("[ToolBuilder] ========================================")

	return armaEquipada
end

return ToolBuilder
