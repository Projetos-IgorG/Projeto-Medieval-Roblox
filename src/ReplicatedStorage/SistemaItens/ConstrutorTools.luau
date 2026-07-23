local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CatalogoItens =
	require(ReplicatedStorage:WaitForChild("Dados"):WaitForChild("Itens"):WaitForChild("CatalogoItens"))

local ConstrutorTools = {}

local PastaModelos = ReplicatedStorage:WaitForChild("Modelos"):WaitForChild("Itens")

-- Procura o template do modelo correspondente nas subpastas tipadas de ReplicatedStorage.Modelos.Itens
local function acharModelo(dados)
	local pastaTipo = PastaModelos:FindFirstChild(dados.Tipo)
	if not pastaTipo then
		warn(
			"[ConstrutorTools] Pasta para tipo nao encontrada no ReplicatedStorage.Modelos.Itens: "
				.. tostring(dados.Tipo)
		)
		return nil
	end
	local modelo = pastaTipo:FindFirstChild(dados.Modelo)
	if not modelo then
		warn("[ConstrutorTools] Modelo nao encontrado: " .. tostring(dados.Modelo) .. " na pasta " .. pastaTipo.Name)
	end
	return modelo
end

-- Junta o estado salvo com os valores base do catalogo.
-- O que nao ver no save cai no padrao do catalogo.
local function montarAttributes(id, dados, salvo)
	salvo = salvo or {}
	local attrs = { Id = id }
	attrs.Quantidade = salvo.Quantidade or 1
	if dados.QualidadeNumBase then
		attrs.QualidadeNum = salvo.QualidadeNum or dados.QualidadeNumBase
	end
	if dados.DurabilidadeMax then
		attrs.Durabilidade = salvo.Durabilidade or dados.DurabilidadeMax
	end
	if salvo.TextureId then
		attrs.TextureId = salvo.TextureId
	end
	return attrs
end

-- Le os Attributes de volta pra uma tabela de save (so o que muda por instancia).
local function lerSalvo(instancia)
	if not instancia then
		return nil
	end
	local id = instancia:GetAttribute("Id")
	local dados = id and CatalogoItens.Get(id)
	if not dados then
		-- Causa mais comum: Tool criada fora do ConstrutorTools (ex: StarterPack)
		-- nao tem o Attribute "Id" definido. Use ConstrutorTools.CriarTool() para criar items validos.
		warn("[ConstrutorTools] Instancia sem Id valido no catalogo: " .. tostring(id)
			.. " (instancia: " .. tostring(instancia.Name) .. ") — verifique se o Attribute 'Id' foi definido.")
		return nil
	end

	local salvo = { Id = id }
	salvo.Quantidade = instancia:GetAttribute("Quantidade") or 1

	if instancia:IsA("Tool") and instancia.TextureId ~= "" then
		salvo.TextureId = instancia.TextureId
	elseif instancia:GetAttribute("TextureId") then
		salvo.TextureId = instancia:GetAttribute("TextureId")
	end

	if instancia:GetAttribute("QualidadeNum") then
		salvo.QualidadeNum = instancia:GetAttribute("QualidadeNum")
	elseif dados.QualidadeNumBase then
		salvo.QualidadeNum = dados.QualidadeNumBase
	end
	if instancia:GetAttribute("Durabilidade") then
		salvo.Durabilidade = instancia:GetAttribute("Durabilidade")
	elseif dados.DurabilidadeMax then
		salvo.Durabilidade = dados.DurabilidadeMax
	end

	-- Adiciona metadados estáticos do catálogo para compatibilidade
	salvo.Nome = dados.Nome
	salvo.Peso = dados.Peso
	salvo.ValorBase = dados.ValorBase
	salvo.Arrastavel = dados.Arrastavel
	salvo.Modelo = dados.Modelo
	salvo.Tipo = dados.Tipo
	salvo.Subtipo = dados.Subtipo
	if dados.Tipo == "Tool" then
		if dados.Subtipo == "Arma" then
			if dados.ModoAnimacao == "UmaMao" then
				salvo.Categoria = "ArmasUmaMao"
			elseif dados.ModoAnimacao == "DuasMaos" or dados.ModoAnimacao == "Punhos" then
				salvo.Categoria = "ArmasDuasMaos"
			elseif dados.ModoAnimacao == "Arco" or dados.ModoAnimacao == "Arcos" then
				salvo.Categoria = "Arcos"
			elseif dados.ModoAnimacao == "Escudo" or dados.ModoAnimacao == "Escudos" then
				salvo.Categoria = "Escudos"
			end
		elseif dados.Subtipo == "Ferramenta" then
			salvo.Categoria = "Ferramentas"
		else
			salvo.Categoria = dados.Subtipo
		end
	else
		salvo.Categoria = dados.Categoria or dados.Subtipo
	end
	salvo.Slot = dados.Slot
	salvo.modoAnimacao = dados.ModoAnimacao
	salvo.Dano = dados.Dano or dados.StatBase
	salvo.Alcance = dados.Alcance
	salvo.DurabilidadeMax = dados.DurabilidadeMax

	return salvo
end

-- Anexa o modelo dentro do Tool.
-- A estrutura dos templates é flat: Handle (BasePart principal), mais partes esteticas
-- e HitboxPart, todos filhos diretos do Model template.
-- Cada filho é movido diretamente para dentro do Tool, mantendo a estrutura flat.
local function anexarModelo(tool, modelo)
	local copia = modelo:Clone()
	if copia:IsA("BasePart") then
		-- Template simples de BasePart unica — vira o Handle diretamente
		copia.Name = "Handle"
		copia.Parent = tool
	else
		-- Template é um Model com multiplas partes (Handle, Lamina, HitboxPart, etc.)
		-- Move todos os filhos direto para o Tool (estrutura flat)
		for _, filho in ipairs(copia:GetChildren()) do
			filho.Parent = tool
		end
		copia:Destroy()
	end
end

-- Cria um Tool pronto (pra Backpack/Character).
function ConstrutorTools.CriarTool(id, salvo)
	local dados = CatalogoItens.Get(id)
	if not dados then
		warn("[ConstrutorTools] Id inexistente no catalogo: " .. tostring(id))
		return nil
	end

	local tool = Instance.new("Tool")
	tool.Name = dados.Nome
	tool.ToolTip = dados.Nome
	tool.RequiresHandle = true
	tool.CanBeDropped = false -- drop vira modelo no mundo (CriarToolNoMundo)

	local modelo = acharModelo(dados)
	if modelo then
		anexarModelo(tool, modelo)
	end

	if dados.TextureId then
		tool.TextureId = dados.TextureId
	elseif salvo and salvo.TextureId then
		tool.TextureId = salvo.TextureId
	end

	for chave, valor in pairs(montarAttributes(id, dados, salvo)) do
		tool:SetAttribute(chave, valor)
	end

	-- Garante que nenhuma parte do Tool fica ancorada (causaria o player ficar preso)
	for _, part in ipairs(tool:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end

	return tool
end

-- Empilhamento por ASSINATURA: dois itens so somam na mesma pilha se forem
-- IDENTICOS -- mesmo Id + mesmos attributes que variam por instancia
-- (QualidadeNum e Durabilidade, quando o tipo os usa). Assim duas espadas com
-- a mesma qualidade e durabilidade empilham; se diferirem, viram pilhas
-- separadas. Pra proibir empilhamento de um item, use MaxQuantidade = 1.
local function camposInstancia(dados)
	local campos = { "Id" } -- o Id sempre entra na comparacao
	if dados.QualidadeNumBase then
		table.insert(campos, "QualidadeNum")
	end
	if dados.DurabilidadeMax then
		table.insert(campos, "Durabilidade")
	end
	return campos
end

-- A Tool tem a mesma assinatura dos attributes-alvo? (todos os campos batem)
local function mesmaAssinatura(inst, attrs, campos)
	for _, campo in ipairs(campos) do
		if inst:GetAttribute(campo) ~= attrs[campo] then
			return false
		end
	end
	return true
end

-- Procura no container uma Tool IDENTICA (mesma assinatura) com espaco na pilha.
local function acharPilhaIgual(container, attrs, campos, maxPilha)
	for _, inst in ipairs(container:GetChildren()) do
		if inst:IsA("Tool") and mesmaAssinatura(inst, attrs, campos) then
			local q = inst:GetAttribute("Quantidade") or 1
			if q < maxPilha then
				return inst
			end
		end
	end
	return nil
end

-- Adiciona a quantidade de itens a um container (Backpack).
-- Tenta preencher pilhas existentes do mesmo item no container. Se sobrar ou
-- nao achar pilha compativel, cria uma nova Tool com o restante.
function ConstrutorTools.EmpilharNoContainer(container, id, salvo)
	local dados = CatalogoItens.Get(id)
	if not dados then
		warn("[ConstrutorTools] Id inexistente no catalogo: " .. tostring(id))
		return false
	end
	salvo = salvo or {}
	local restante = salvo.Quantidade or 1
	local maxPilha = dados.MaxQuantidade or 1
	local campos = camposInstancia(dados)

	-- Assinatura alvo de busca (Attributes)
	local attrs = montarAttributes(id, dados, salvo)

	while restante > 0 do
		local pilha = acharPilhaIgual(container, attrs, campos, maxPilha)
		if pilha then
			local q = pilha:GetAttribute("Quantidade") or 1
			local cabe = math.min(restante, maxPilha - q)
			pilha:SetAttribute("Quantidade", q + cabe)
			restante -= cabe
		else
			-- Nao cabe em nenhuma pilha existente, cria uma nova Tool
			local novoSalvo = table.clone(salvo)
			novoSalvo.Quantidade = restante
			local novaTool = ConstrutorTools.CriarTool(id, novoSalvo)
			if novaTool then
				novaTool.Parent = container
			end
			break -- A nova Tool ja consome todo o restante criado
		end
	end
	return true
end

-- Reduz a quantidade da Tool segurada (ou container). Se a quantidade zerar,
-- destroi a Tool e retorna nil. Se ainda restar quantidade, altera o attribute
-- e retorna a propria Tool. Util para itens consumiveis/desempilhar.
function ConstrutorTools.ConsumirUnidade(tool)
	local q = tool:GetAttribute("Quantidade") or 1
	if q <= 1 then
		tool:Destroy()
		return nil
	end
	tool:SetAttribute("Quantidade", q - 1)
	return tool
end

-- Remove uma unidade desta Tool e cria uma nova Tool isolada contendo apenas
-- essa unidade (ex.: para equipar/jogar de uma pilha).
function ConstrutorTools.ExtrairUmaUnidade(tool)
	local q = tool:GetAttribute("Quantidade") or 1
	if q <= 0 then
		return nil
	end
	local salvo = lerSalvo(tool)
	if not salvo then
		return nil
	end
	tool:SetAttribute("Quantidade", q - 1)
	salvo.Quantidade = 1
	local unidade = ConstrutorTools.CriarTool(salvo.Id, salvo)
	if unidade then
		unidade.Parent = tool.Parent
	end
	return unidade
end

-- Tenta empilhar uma Tool JA EXISTENTE em pilhas IDENTICAS do container (ate o
-- MaxQuantidade), sem contar ela mesma. Escoa o quanto couber; se zerar tudo,
-- destroi a Tool e devolve true. Se sobrar, atualiza a Quantidade dela e devolve
-- false. Util pra re-empilhar ao desequipar/guardar uma unidade solta.
function ConstrutorTools.EmpilharExistente(container, tool)
	local id = tool:GetAttribute("Id")
	local dados = id and CatalogoItens.Get(id)
	if not dados then
		return false
	end
	local maxPilha = dados.MaxQuantidade or 1
	local campos = camposInstancia(dados)
	-- Assinatura desta Tool (Id + QualidadeNum/Durabilidade quando o tipo usa).
	local attrs = {}
	for _, campo in ipairs(campos) do
		attrs[campo] = tool:GetAttribute(campo)
	end
	local restante = tool:GetAttribute("Quantidade") or 1
	for _, inst in ipairs(container:GetChildren()) do
		if restante <= 0 then
			break
		end
		if inst ~= tool and inst:IsA("Tool") and mesmaAssinatura(inst, attrs, campos) then
			local q = inst:GetAttribute("Quantidade") or 1
			if q < maxPilha then
				local cabe = math.min(restante, maxPilha - q)
				inst:SetAttribute("Quantidade", q + cabe)
				restante -= cabe
			end
		end
	end
	if restante <= 0 then
		tool:Destroy()
		return true
	end
	tool:SetAttribute("Quantidade", restante)
	return false
end

-- Cria o item dropado no mundo (com prompt de coleta e flag Arrastavel).
function ConstrutorTools.CriarToolNoMundo(id, salvo, cframe)
	local dados = CatalogoItens.Get(id)
	if not dados then
		warn("[ConstrutorTools] Id inexistente no catalogo: " .. tostring(id))
		return nil
	end

	local modelo = acharModelo(dados)
	if not modelo then
		return nil
	end

	local dropado = modelo:Clone()
	dropado.Name = id

	for chave, valor in pairs(montarAttributes(id, dados, salvo)) do
		dropado:SetAttribute(chave, valor)
	end
	dropado:SetAttribute("Arrastavel", true)

	local alvo = dropado:IsA("Model") and (dropado.PrimaryPart or dropado:FindFirstChildWhichIsA("BasePart")) or dropado
	if alvo and alvo:IsA("BasePart") then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ColetarTool"
		prompt.ActionText = "Pegar"
		prompt.ObjectText = dados.Nome
		prompt.Parent = alvo
	end

	if cframe then
		if dropado:IsA("Model") then
			dropado:PivotTo(cframe)
		elseif dropado:IsA("BasePart") then
			dropado.CFrame = cframe
		end
	end

	-- Ativa colisões para que o item caia no chão e aplique física
	local function ativarFisica(inst)
		if inst:IsA("BasePart") then
			inst.Anchored = false
			if inst.Name ~= "HitboxPart" then
				inst.CanCollide = true
			end
		end
	end
	
	ativarFisica(dropado)
	for _, desc in ipairs(dropado:GetDescendants()) do
		ativarFisica(desc)
	end

	dropado.Parent = workspace
	return dropado
end

-- Extrai o estado salvo de um Tool.
function ConstrutorTools.ExtrairDados(tool)
	return lerSalvo(tool)
end

-- Extrai o estado salvo de um item dropado no mundo.
function ConstrutorTools.ExtrairDadosDoMundo(modelo)
	return lerSalvo(modelo)
end

return ConstrutorTools
