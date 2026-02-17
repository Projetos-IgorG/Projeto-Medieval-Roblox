--[[
	Modulo_Equipamento.luau
	ReplicatedStorage > Modulos > Modulo_Equipamento.luau

	Módulo compartilhado (server + client) com constantes, validação e
	resolução de modo de animação para o Sistema de Equipamento.

	Responsabilidades:
	- Definir categorias válidas de armas e slots de equipamento
	- Resolver qual modo de animação ativo usar baseado na combinação
	  de arma direita + estado da mão esquerda
	- Validar entradas do sistema de equipamento
	- Mapear categorias para slots destino

	IMPORTANTE: Este módulo NÃO altera nenhum ValueObject em Tools.
	Ele apenas retorna valores para serem usados pelo sistema.
]]

--!strict

local Modulo_Equipamento = {}

-- ═══════════════════════════════════════════════════════════════════
-- CONSTANTES — CATEGORIAS DE ARMAS
-- ═══════════════════════════════════════════════════════════════════

Modulo_Equipamento.Categorias = {
	ArmasUmaMao = "ArmasUmaMao",
	ArmasDuasMaos = "ArmasDuasMaos",
	Escudos = "Escudos",
	Arcos = "Arcos",
}

-- Set para validação rápida
local CATEGORIAS_VALIDAS: { [string]: boolean } = {
	ArmasUmaMao = true,
	ArmasDuasMaos = true,
	Escudos = true,
	Arcos = true,
}

-- ═══════════════════════════════════════════════════════════════════
-- CONSTANTES — SLOTS DE EQUIPAMENTO
-- ═══════════════════════════════════════════════════════════════════

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

-- ═══════════════════════════════════════════════════════════════════
-- CONSTANTES — ESTADOS DA MÃO ESQUERDA
-- ═══════════════════════════════════════════════════════════════════

Modulo_Equipamento.EstadoMaoEsquerda = {
	Vazio = "Vazio",
	Escudo = "Escudo",
	SegundaArma = "SegundaArma",
	Flechas = "Flechas",
}

-- ═══════════════════════════════════════════════════════════════════
-- CONSTANTES — TIPOS DE TOOL
-- ═══════════════════════════════════════════════════════════════════

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

-- ═══════════════════════════════════════════════════════════════════
-- CATEGORIAS QUE BLOQUEIAM A MÃO ESQUERDA
-- ═══════════════════════════════════════════════════════════════════

local CATEGORIAS_BLOQUEIAM_ESQUERDA: { [string]: boolean } = {
	ArmasDuasMaos = true,
	Arcos = true,
}

-- ═══════════════════════════════════════════════════════════════════
-- MAPEAMENTO CATEGORIA → SLOT DESTINO
-- ═══════════════════════════════════════════════════════════════════

local CATEGORIA_PARA_SLOT: { [string]: string } = {
	ArmasUmaMao = "RightArm", -- Vai para direita; se já há arma, pode ir para esquerda (dual)
	ArmasDuasMaos = "RightArm",
	Arcos = "RightArm",
	Escudos = "LeftArm",
}

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES DE VALIDAÇÃO
-- ═══════════════════════════════════════════════════════════════════

--- Valida se uma categoria é válida
---@param categoria string
---@return boolean
function Modulo_Equipamento.ValidarCategoria(categoria: string): boolean
	if type(categoria) ~= "string" then
		return false
	end
	return CATEGORIAS_VALIDAS[categoria] == true
end

--- Valida se um slot de corpo é válido
---@param slot string
---@return boolean
function Modulo_Equipamento.ValidarSlotCorpo(slot: string): boolean
	if type(slot) ~= "string" then
		return false
	end
	return SLOTS_CORPO_VALIDOS[slot] == true
end

--- Valida se um slot (braço ou corpo) é válido
---@param slot string
---@return boolean
function Modulo_Equipamento.ValidarSlot(slot: string): boolean
	if type(slot) ~= "string" then
		return false
	end
	return SLOTS_BRACOS_VALIDOS[slot] == true or SLOTS_CORPO_VALIDOS[slot] == true
end

--- Verifica se é um slot de braço
---@param slot string
---@return boolean
function Modulo_Equipamento.EhSlotBraco(slot: string): boolean
	return SLOTS_BRACOS_VALIDOS[slot] == true
end

--- Verifica se é um slot de corpo
---@param slot string
---@return boolean
function Modulo_Equipamento.EhSlotCorpo(slot: string): boolean
	return SLOTS_CORPO_VALIDOS[slot] == true
end

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES DE MAPEAMENTO
-- ═══════════════════════════════════════════════════════════════════

--- Mapeia uma categoria ao slot destino padrão
---@param categoria string
---@return string? -- "RightArm" | "LeftArm" | nil
function Modulo_Equipamento.ObterSlotDestino(categoria: string): string?
	return CATEGORIA_PARA_SLOT[categoria]
end

--- Verifica se uma categoria bloqueia a mão esquerda (ocupa ambas as mãos)
---@param categoria string
---@return boolean
function Modulo_Equipamento.CategoriaBloqueiaMaoEsquerda(categoria: string): boolean
	return CATEGORIAS_BLOQUEIAM_ESQUERDA[categoria] == true
end

--- Converte o Id de uma arma para o Id do template equipada correspondente
--- Exemplo: "espada_ferro" → "espada_ferro-equipada"
---@param idOriginal string
---@return string
function Modulo_Equipamento.ResolverIdEquipada(idOriginal: string): string
	return idOriginal .. "-equipada"
end

-- ═══════════════════════════════════════════════════════════════════
-- RESOLUÇÃO DE ESTADO DA MÃO ESQUERDA
-- ═══════════════════════════════════════════════════════════════════

--- Resolve o estado atual da mão esquerda baseado no Tool equipado
--- Lê a Categoria do Tool para determinar o tipo
---@param toolEsq Tool? -- Tool equipado na mão esquerda (ou nil)
---@return string -- "Vazio" | "Escudo" | "SegundaArma" | "Flechas"
function Modulo_Equipamento.ResolverEstadoMaoEsquerda(toolEsq: Tool?): string
	if not toolEsq then
		return Modulo_Equipamento.EstadoMaoEsquerda.Vazio
	end

	local dadosFolder = toolEsq:FindFirstChild("Dados")
	if not dadosFolder then
		return Modulo_Equipamento.EstadoMaoEsquerda.Vazio
	end

	-- Verificar Categoria
	local categoriaValue = dadosFolder:FindFirstChild("Categoria")
	if categoriaValue and categoriaValue:IsA("StringValue") then
		local cat = categoriaValue.Value
		if cat == "Escudos" then
			return Modulo_Equipamento.EstadoMaoEsquerda.Escudo
		elseif cat == "ArmasUmaMao" then
			return Modulo_Equipamento.EstadoMaoEsquerda.SegundaArma
		end
	end

	-- Verificar se é flechas (Tipo == "Materiais" com alguma flag especial, ou nome)
	local tipoValue = dadosFolder:FindFirstChild("Tipo")
	if tipoValue and tipoValue:IsA("StringValue") then
		if tipoValue.Value == "Materiais" then
			-- Flechas são materiais no LeftArm
			return Modulo_Equipamento.EstadoMaoEsquerda.Flechas
		end
	end

	return Modulo_Equipamento.EstadoMaoEsquerda.Vazio
end

-- ═══════════════════════════════════════════════════════════════════
-- RESOLUÇÃO DE MODO DE ANIMAÇÃO ATIVO
-- ═══════════════════════════════════════════════════════════════════

--[[
	ResolverModoAtivo decide o modo de animação/combate ativo em runtime.

	Parâmetros:
	- modoTool: string? — o valor de Dados.modoAnimacao do Tool equipado
	  (ex: "UmaMao", "UmaMao2v", "Punhos"). Este valor NUNCA é alterado.
	- estadoEsq: string — resultado de ResolverEstadoMaoEsquerda()
	- categoriaDir: string? — Categoria da arma na mão direita (ou nil se Punhos)

	Retorno:
	- string — o modo ativo que o sistema de combate/animação deve usar.

	Regras de resolução:
	1. Se categoriaDir == "Arcos" → "Arco" (modo fixo, ignora modoTool)
	2. Se categoriaDir == "ArmasDuasMaos" → "DuasMaos" (modo fixo)
	3. Se modoTool == "Punhos":
	   - estadoEsq == "Escudo" → "PunhosEscudo"
	   - caso contrário → "Punhos"
	4. Para modos de arma de uma mão (modoTool ex: "UmaMao", "UmaMao2v"):
	   - estadoEsq == "Escudo" → modoTool .. "Escudo" (ex: "UmaMaoEscudo", "UmaMao2vEscudo")
	   - estadoEsq == "SegundaArma" → modoTool .. "Dupla" (ex: "UmaMaoDupla", "UmaMao2vDupla")
	   - caso contrário → modoTool (ex: "UmaMao", "UmaMao2v")
	5. Fallback: retorna modoTool ou "Base"
]]
---@param modoTool string? -- Dados.modoAnimacao do Tool (nunca alterado)
---@param estadoEsq string -- Resultado de ResolverEstadoMaoEsquerda()
---@param categoriaDir string? -- Categoria da arma direita (ou nil para Punhos)
---@return string -- Modo ativo para o sistema de animação
function Modulo_Equipamento.ResolverModoAtivo(modoTool: string?, estadoEsq: string, categoriaDir: string?): string
	-- 1. Categorias com modo fixo (ignora modoTool)
	if categoriaDir == "Arcos" then
		return "Arco"
	end
	if categoriaDir == "ArmasDuasMaos" then
		return "DuasMaos"
	end

	-- 2. Sem modo no Tool → fallback
	if not modoTool or modoTool == "" or modoTool == "Base" then
		return "Base"
	end

	-- 3. Punhos
	if modoTool == "Punhos" then
		if estadoEsq == Modulo_Equipamento.EstadoMaoEsquerda.Escudo then
			return "PunhosEscudo"
		end
		return "Punhos"
	end

	-- 4. Armas de uma mão — aplicar sufixo baseado no estado da esquerda
	if estadoEsq == Modulo_Equipamento.EstadoMaoEsquerda.Escudo then
		return modoTool .. "Escudo"
	elseif estadoEsq == Modulo_Equipamento.EstadoMaoEsquerda.SegundaArma then
		return modoTool .. "Dupla"
	end

	-- 5. Sem modificador, usar modo base do Tool
	return modoTool
end

-- ═══════════════════════════════════════════════════════════════════
-- UTILITÁRIOS DE LEITURA DE DADOS
-- ═══════════════════════════════════════════════════════════════════

--- Lê a Categoria de um Tool a partir do folder Dados
---@param tool Tool
---@return string?
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

--- Lê o Tipo de um Tool a partir do folder Dados
---@param tool Tool
---@return string?
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

--- Lê o Slot de um Tool de armadura a partir do folder Dados
---@param tool Tool
---@return string?
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

--- Lê o modoAnimacao de um Tool a partir do folder Dados
---@param tool Tool
---@return string?
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
