--!strict

--[[
    Script: ValidacaoEquipamentos.luau
    Caminho: src/ReplicatedStorage/Equipamentos
    Responsabilidade: Valida dados, tipos e modelos de equipamentos antes do uso.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao roda sozinho nem cria fluxo de jogo por conta propria; depende dos scripts que importam este modulo.
    Funcoes principais: ValidarCategoria, ValidarSlotCorpo, ValidarSlot, EhSlotBraco, EhSlotCorpo, ObterSlotDestino
]]
local Modulo_Equipamento = {}

Modulo_Equipamento.Categorias = {
	ArmasUmaMao = "ArmasUmaMao",
	ArmasDuasMaos = "ArmasDuasMaos",
	Escudos = "Escudos",
	Arcos = "Arcos",
}

local CATEGORIAS_VALIDAS: { [string]: boolean } = {
	ArmasUmaMao = true,
	ArmasDuasMaos = true,
	Escudos = true,
	Arcos = true,
}

Modulo_Equipamento.SlotsBracos = {
	RightArm = "RightArm",
	LeftArm = "LeftArm",
}

Modulo_Equipamento.SlotsCorpo = {
	Head = "Head",
	Torso = "Torso",
	Legs = "Legs",
	Foot = "Foot",
}

local SLOTS_CORPO_VALIDOS: { [string]: boolean } = {
	Head = true,
	Torso = true,
	Legs = true,
	Foot = true,
}

local SLOTS_BRACOS_VALIDOS: { [string]: boolean } = {
	RightArm = true,
	LeftArm = true,
}

Modulo_Equipamento.EstadoMaoEsquerda = {
	Vazio = "Vazio",
	Escudo = "Escudo",
	SegundaArma = "SegundaArma",
	Flechas = "Flechas",
}

Modulo_Equipamento.Tipos = {
	Armas = "Armas",
	ArmasEquipadas = "ArmasEquipadas",
	Armaduras = "Armaduras",
	Materiais = "Materiais",
	Ferramentas = "Ferramentas",
	Comidas = "Comidas",
	Bebidas = "Bebidas",
	Pocoes = "Pocoes",
	Ingredientes = "Ingredientes",
}

local CATEGORIAS_BLOQUEIAM_ESQUERDA: { [string]: boolean } = {
	ArmasDuasMaos = true,
	Arcos = true,
}

local CATEGORIA_PARA_SLOT: { [string]: string } = {
	ArmasUmaMao = "RightArm",
	ArmasDuasMaos = "RightArm",
	Arcos = "RightArm",
	Escudos = "LeftArm",
}

function Modulo_Equipamento.ValidarCategoria(categoria: string): boolean
	if type(categoria) ~= "string" then
		return false
	end
	return CATEGORIAS_VALIDAS[categoria] == true
end

function Modulo_Equipamento.ValidarSlotCorpo(slot: string): boolean
	if type(slot) ~= "string" then
		return false
	end
	return SLOTS_CORPO_VALIDOS[slot] == true
end

function Modulo_Equipamento.ValidarSlot(slot: string): boolean
	if type(slot) ~= "string" then
		return false
	end
	return SLOTS_BRACOS_VALIDOS[slot] == true or SLOTS_CORPO_VALIDOS[slot] == true
end

function Modulo_Equipamento.EhSlotBraco(slot: string): boolean
	return SLOTS_BRACOS_VALIDOS[slot] == true
end

function Modulo_Equipamento.EhSlotCorpo(slot: string): boolean
	return SLOTS_CORPO_VALIDOS[slot] == true
end

function Modulo_Equipamento.ObterSlotDestino(categoria: string): string?
	return CATEGORIA_PARA_SLOT[categoria]
end

function Modulo_Equipamento.CategoriaBloqueiaMaoEsquerda(categoria: string): boolean
	return CATEGORIAS_BLOQUEIAM_ESQUERDA[categoria] == true
end

function Modulo_Equipamento.ResolverIdEquipada(idOriginal: string): string
	return idOriginal .. "-equipada"
end

function Modulo_Equipamento.ResolverEstadoMaoEsquerda(toolEsq: Tool?): string
	if not toolEsq then
		return Modulo_Equipamento.EstadoMaoEsquerda.Vazio
	end

	local dadosFolder = toolEsq:FindFirstChild("Dados")
	if not dadosFolder then
		return Modulo_Equipamento.EstadoMaoEsquerda.Vazio
	end

	local categoriaValue = dadosFolder:FindFirstChild("Categoria")
	if categoriaValue and categoriaValue:IsA("StringValue") then
		local cat = categoriaValue.Value
		if cat == "Escudos" then
			return Modulo_Equipamento.EstadoMaoEsquerda.Escudo
		elseif cat == "ArmasUmaMao" then
			return Modulo_Equipamento.EstadoMaoEsquerda.SegundaArma
		end
	end

	local tipoValue = dadosFolder:FindFirstChild("Tipo")
	if tipoValue and tipoValue:IsA("StringValue") then
		if tipoValue.Value == "Materiais" then

			return Modulo_Equipamento.EstadoMaoEsquerda.Flechas
		end
	end

	return Modulo_Equipamento.EstadoMaoEsquerda.Vazio
end

function Modulo_Equipamento.ResolverModoAtivo(modoTool: string?, estadoEsq: string, categoriaDir: string?): string

	if categoriaDir == "Arcos" then
		return "Arco"
	end
	if categoriaDir == "ArmasDuasMaos" then
		return "DuasMaos"
	end

	if not modoTool or modoTool == "" or modoTool == "Base" then
		return "Base"
	end

	if modoTool == "Punhos" then
		if estadoEsq == Modulo_Equipamento.EstadoMaoEsquerda.Escudo then
			return "PunhosEscudo"
		end
		return "Punhos"
	end

	if estadoEsq == Modulo_Equipamento.EstadoMaoEsquerda.Escudo then
		return modoTool .. "Escudo"
	elseif estadoEsq == Modulo_Equipamento.EstadoMaoEsquerda.SegundaArma then
		return modoTool .. "Dupla"
	end

	return modoTool
end

function Modulo_Equipamento.LerCategoria(tool: Tool): string?
	local dados = tool:FindFirstChild("Dados")
	if not dados then
		return nil
	end
	local catValue = dados:FindFirstChild("Categoria")
	if catValue and catValue:IsA("StringValue") and catValue.Value ~= "" then
		return catValue.Value
	end
	return nil
end

function Modulo_Equipamento.LerTipo(tool: Tool): string?
	local dados = tool:FindFirstChild("Dados")
	if not dados then
		return nil
	end
	local tipoValue = dados:FindFirstChild("Tipo")
	if tipoValue and tipoValue:IsA("StringValue") and tipoValue.Value ~= "" then
		return tipoValue.Value
	end
	return nil
end

function Modulo_Equipamento.LerSlot(tool: Tool): string?
	local dados = tool:FindFirstChild("Dados")
	if not dados then
		return nil
	end
	local slotValue = dados:FindFirstChild("Slot")
	if slotValue and slotValue:IsA("StringValue") and slotValue.Value ~= "" then
		return slotValue.Value
	end
	return nil
end

function Modulo_Equipamento.LerModoAnimacao(tool: Tool): string?
	local dados = tool:FindFirstChild("Dados")
	if not dados then
		return nil
	end
	local modoValue = dados:FindFirstChild("modoAnimacao")
	if modoValue and modoValue:IsA("StringValue") and modoValue.Value ~= "" then
		return modoValue.Value
	end
	return nil
end

return Modulo_Equipamento
