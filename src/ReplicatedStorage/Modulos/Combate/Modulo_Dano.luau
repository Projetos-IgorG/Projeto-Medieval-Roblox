--[[
	Modulo_Dano.luau
	
	Processa e aplica dano no sistema de combate.
	
	Responsabilidades:
	- Validar estrutura de dados da Tool (pasta "Dados", propriedade "Dano")
	- Obter dano base da Tool equipada
	- Calcular dano final baseado no tipo de ataque
	- Aplicar dano ao alvo com validações
	
	Tipos de ataque:
	- AtaqueLeve: Multiplicador 1.0x
	- AtaqueLeveFinal: Multiplicador 1.15x (+15%)
	- AtaquePesado: Multiplicador 1.5x (+50%)
]]

--!strict

-- ═══════════════════════════════════════════════════════════════════
-- CONSTANTES
-- ═══════════════════════════════════════════════════════════════════

local PASTA_DADOS = "Dados"
local PROP_DANO = "Dano"

local MULTIPLICADORES_DANO: { [string]: number } = {
	AtaqueLeve = 1.0,
	AtaqueLeveFinal = 1.15,
	AtaquePesado = 1.5,
}

-- ═══════════════════════════════════════════════════════════════════
-- TYPES
-- ═══════════════════════════════════════════════════════════════════

export type ResultadoDano = {
	sucesso: boolean,
	danoAplicado: number?,
	erro: string?,
}

-- ═══════════════════════════════════════════════════════════════════
-- MÓDULO
-- ═══════════════════════════════════════════════════════════════════

local Modulo_Dano = {}

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES DE VALIDAÇÃO
-- ═══════════════════════════════════════════════════════════════════

--- Valida se a Tool tem a estrutura de dados correta
---@param tool Tool
---@return boolean sucesso
---@return string? erro
function Modulo_Dano.ValidarEstruturaTool(tool: Tool): (boolean, string?)
	if not tool then
		return false, "Tool é nil"
	end

	if not tool:IsA("Tool") then
		return false, "Objeto não é um Tool"
	end

	local dados = tool:FindFirstChild(PASTA_DADOS)
	if not dados then
		return false, "Tool sem pasta '" .. PASTA_DADOS .. "'"
	end

	local danoValue = dados:FindFirstChild(PROP_DANO)
	if not danoValue then
		return false, "Pasta Dados sem propriedade '" .. PROP_DANO .. "'"
	end

	-- Verifica se é um NumberValue ou IntValue
	if not (danoValue:IsA("NumberValue") or danoValue:IsA("IntValue")) then
		return false, "Propriedade Dano não é numérica (NumberValue ou IntValue)"
	end

	return true, nil
end

--- Valida se um atacante é válido para aplicar dano
---@param atacante Player | Model
---@return boolean sucesso
---@return string? erro
function Modulo_Dano.ValidarAtacante(atacante: Player | Model): (boolean, string?)
	if not atacante then
		return false, "Atacante é nil"
	end

	-- Se for Player, pega o Character
	local character: Model?
	if typeof(atacante) == "Instance" and atacante:IsA("Player") then
		character = (atacante :: Player).Character
	elseif typeof(atacante) == "Instance" and atacante:IsA("Model") then
		character = atacante :: Model
	else
		return false, "Atacante não é Player nem Model"
	end

	if not character then
		return false, "Atacante sem Character"
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, "Atacante sem Humanoid"
	end

	if humanoid.Health <= 0 then
		return false, "Atacante está morto"
	end

	return true, nil
end

--- Valida se um alvo é válido para receber dano
---@param alvo Model
---@return boolean sucesso
---@return string? erro
function Modulo_Dano.ValidarAlvo(alvo: Model): (boolean, string?)
	if not alvo then
		return false, "Alvo é nil"
	end

	if not alvo:IsA("Model") then
		return false, "Alvo não é um Model"
	end

	local humanoid = alvo:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, "Alvo sem Humanoid"
	end

	if humanoid.Health <= 0 then
		return false, "Alvo já está morto"
	end

	return true, nil
end

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES DE ACESSO
-- ═══════════════════════════════════════════════════════════════════

--- Obtém o valor de dano base da Tool
---@param tool Tool
---@return number?
function Modulo_Dano.ObterDanoBase(tool: Tool): number?
	local valido, erro = Modulo_Dano.ValidarEstruturaTool(tool)
	if not valido then
		warn("[Modulo_Dano] " .. (erro or "Erro desconhecido"))
		return nil
	end

	local dados = tool:FindFirstChild(PASTA_DADOS)
	local danoValue = dados and dados:FindFirstChild(PROP_DANO)

	if danoValue and (danoValue:IsA("NumberValue") or danoValue:IsA("IntValue")) then
		return (danoValue :: any).Value
	end

	return nil
end

--- Obtém o multiplicador de dano para um tipo de ataque
---@param tipoAtaque string
---@return number
function Modulo_Dano.ObterMultiplicador(tipoAtaque: string): number
	return MULTIPLICADORES_DANO[tipoAtaque] or 1.0
end

--- Calcula o dano final
---@param danoBase number
---@param tipoAtaque string
---@return number
function Modulo_Dano.CalcularDano(danoBase: number, tipoAtaque: string): number
	local multiplicador = Modulo_Dano.ObterMultiplicador(tipoAtaque)
	return danoBase * multiplicador
end

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÃO PRINCIPAL
-- ═══════════════════════════════════════════════════════════════════

--- Aplica dano a um alvo
---@param tool Tool Ferramenta equipada
---@param atacante Player | Model Jogador ou Character atacante
---@param alvo Model Character ou NPC alvo
---@param tipoAtaque string Tipo de ataque (AtaqueLeve, AtaqueLeveFinal, AtaquePesado)
---@return ResultadoDano
function Modulo_Dano.AplicarDano(tool: Tool, atacante: Player | Model, alvo: Model, tipoAtaque: string): ResultadoDano
	-- Validação de Tool
	local toolValido, toolErro = Modulo_Dano.ValidarEstruturaTool(tool)
	if not toolValido then
		return {
			sucesso = false,
			danoAplicado = nil,
			erro = toolErro,
		}
	end

	-- Validação de atacante
	local atacanteValido, atacanteErro = Modulo_Dano.ValidarAtacante(atacante)
	if not atacanteValido then
		return {
			sucesso = false,
			danoAplicado = nil,
			erro = atacanteErro,
		}
	end

	-- Validação de alvo
	local alvoValido, alvoErro = Modulo_Dano.ValidarAlvo(alvo)
	if not alvoValido then
		return {
			sucesso = false,
			danoAplicado = nil,
			erro = alvoErro,
		}
	end

	-- Obtém dano base
	local danoBase = Modulo_Dano.ObterDanoBase(tool)
	if not danoBase then
		return {
			sucesso = false,
			danoAplicado = nil,
			erro = "Não foi possível obter dano base da Tool",
		}
	end

	-- Calcula dano final
	local danoFinal = Modulo_Dano.CalcularDano(danoBase, tipoAtaque)

	-- Aplica dano com pcall para segurança
	local sucesso, erro = pcall(function()
		local humanoid = alvo:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:TakeDamage(danoFinal)
		end
	end)

	if not sucesso then
		return {
			sucesso = false,
			danoAplicado = nil,
			erro = "Erro ao aplicar dano: " .. tostring(erro),
		}
	end

	return {
		sucesso = true,
		danoAplicado = danoFinal,
		erro = nil,
	}
end

return Modulo_Dano
