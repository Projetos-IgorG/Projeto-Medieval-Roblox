--!strict

--[[
    Script: DanoCombate.luau
    Caminho: src/ReplicatedStorage/Combate/Dominio
    Responsabilidade: Calcula regras de dano e modificadores antes da aplicacao final pelo servidor.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao dispara acoes por conta propria; apenas calcula regras para o script chamador.
    Funcoes principais: ValidarEstruturaTool, ValidarAtacante, ValidarAlvo, ObterDanoBase, ObterMultiplicador, CalcularDano
]]
local PASTA_DADOS = "Dados"
local PROP_DANO = "Dano"
local CHAVE_VIDA_ENTIDADE = "Ent_Vida"

local MULTIPLICADORES_DANO: { [string]: number } = {
	Ataque = 1.0,
	AtaqueFinal = 1.15,
}

export type ResultadoDano = {
	sucesso: boolean,
	danoAplicado: number?,
	erro: string?,
}

local Modulo_Dano = {}

local function AplicarDanoNoModelo(alvo: Model, danoFinal: number)
	local humanoid = alvo:FindFirstChildOfClass("Humanoid")
	local vidaEntidade = alvo:GetAttribute(CHAVE_VIDA_ENTIDADE)

	if typeof(vidaEntidade) == "number" then
		local novaVida = math.max(0, vidaEntidade - danoFinal)
		alvo:SetAttribute(CHAVE_VIDA_ENTIDADE, novaVida)
		if humanoid then
			humanoid.Health = math.min(humanoid.MaxHealth, novaVida)
		end
	elseif humanoid then
		humanoid:TakeDamage(danoFinal)
	end
end

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

	if not (danoValue:IsA("NumberValue") or danoValue:IsA("IntValue")) then
		return false, "Propriedade Dano não é numérica (NumberValue ou IntValue)"
	end

	return true, nil
end

function Modulo_Dano.ValidarAtacante(atacante: Player | Model): (boolean, string?)
	if not atacante then
		return false, "Atacante é nil"
	end

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

function Modulo_Dano.ObterMultiplicador(tipoAtaque: string): number
	return MULTIPLICADORES_DANO[tipoAtaque] or 1.0
end

function Modulo_Dano.CalcularDano(danoBase: number, tipoAtaque: string): number
	local multiplicador = Modulo_Dano.ObterMultiplicador(tipoAtaque)
	return danoBase * multiplicador
end

function Modulo_Dano.AplicarDano(tool: Tool, atacante: Player | Model, alvo: Model, tipoAtaque: string): ResultadoDano

	local toolValido, toolErro = Modulo_Dano.ValidarEstruturaTool(tool)
	if not toolValido then
		return {
			sucesso = false,
			danoAplicado = nil,
			erro = toolErro,
		}
	end

	local atacanteValido, atacanteErro = Modulo_Dano.ValidarAtacante(atacante)
	if not atacanteValido then
		return {
			sucesso = false,
			danoAplicado = nil,
			erro = atacanteErro,
		}
	end

	local alvoValido, alvoErro = Modulo_Dano.ValidarAlvo(alvo)
	if not alvoValido then
		return {
			sucesso = false,
			danoAplicado = nil,
			erro = alvoErro,
		}
	end

	local danoBase = Modulo_Dano.ObterDanoBase(tool)
	if not danoBase then
		return {
			sucesso = false,
			danoAplicado = nil,
			erro = "Não foi possível obter dano base da Tool",
		}
	end

	local danoFinal = Modulo_Dano.CalcularDano(danoBase, tipoAtaque)

	local sucesso, erro = pcall(function()
		AplicarDanoNoModelo(alvo, danoFinal)
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

function Modulo_Dano.AplicarDanoComValor(
	atacante: Player | Model,
	alvo: Model,
	tipoAtaque: string,
	danoBase: number
): ResultadoDano

	local atacanteValido, atacanteErro = Modulo_Dano.ValidarAtacante(atacante)
	if not atacanteValido then
		return {
			sucesso = false,
			danoAplicado = nil,
			erro = atacanteErro,
		}
	end

	local alvoValido, alvoErro = Modulo_Dano.ValidarAlvo(alvo)
	if not alvoValido then
		return {
			sucesso = false,
			danoAplicado = nil,
			erro = alvoErro,
		}
	end

	local danoFinal = Modulo_Dano.CalcularDano(danoBase, tipoAtaque)

	local sucesso, erro = pcall(function()
		AplicarDanoNoModelo(alvo, danoFinal)
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
