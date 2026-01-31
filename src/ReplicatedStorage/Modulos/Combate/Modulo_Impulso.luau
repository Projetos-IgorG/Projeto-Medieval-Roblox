--[[
	Modulo_Impulso.luau
	
	Aplica impulso no player atacante baseado na configuração do modoAnimacao.
	
	Responsabilidades:
	- Verificar se o modoAnimacao permite impulso
	- Validar parâmetros de entrada
	- Aplicar impulso físico ao atacante
	
	O impulso é DESABILITADO para:
	- Arcos (tipo "Combate" mas aplicaImpulso = false)
	- Ferramentas de interação (tipo "Interacao")
]]

--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ═══════════════════════════════════════════════════════════════════
-- DEPENDÊNCIAS
-- ═══════════════════════════════════════════════════════════════════

local Combate = ReplicatedStorage:WaitForChild("Modulos"):WaitForChild("Combate")
local Modulo_Configuracoes = require(Combate:WaitForChild("Modulo_Configuracoes"))

-- ═══════════════════════════════════════════════════════════════════
-- TYPES
-- ═══════════════════════════════════════════════════════════════════

export type ResultadoImpulso = {
	sucesso: boolean,
	magnitudeAplicada: number?,
	erro: string?,
}

-- ═══════════════════════════════════════════════════════════════════
-- MÓDULO
-- ═══════════════════════════════════════════════════════════════════

local Modulo_Impulso = {}

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES DE VALIDAÇÃO
-- ═══════════════════════════════════════════════════════════════════

--- Valida se uma entidade pode receber impulso
---@param entidade Model
---@return boolean sucesso
---@return string? erro
function Modulo_Impulso.ValidarEntidade(entidade: Model): (boolean, string?)
	if not entidade then
		return false, "Entidade é nil"
	end

	if not entidade:IsA("Model") then
		return false, "Entidade não é um Model"
	end

	local humanoidRoot = entidade:FindFirstChild("HumanoidRootPart")
	if not humanoidRoot then
		return false, "Entidade sem HumanoidRootPart"
	end

	if not humanoidRoot:IsA("BasePart") then
		return false, "HumanoidRootPart não é BasePart"
	end

	local humanoid = entidade:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, "Entidade sem Humanoid"
	end

	if humanoid.Health <= 0 then
		return false, "Entidade está morta"
	end

	return true, nil
end

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES DE ACESSO
-- ═══════════════════════════════════════════════════════════════════

--- Obtém a magnitude do impulso baseado no tipo de ataque
---@param tipoAtaque string
---@return number
function Modulo_Impulso.ObterMagnitudeImpulso(tipoAtaque: string): number
	local config = Modulo_Configuracoes.ConfiguracaoGlobal

	if tipoAtaque == "AtaquePesado" or tipoAtaque == "AtaqueLeveFinal" then
		return config.MagnitudeImpulsoAtaquePesado
	end

	return config.MagnitudeImpulsoAtaqueLeve
end

--- Verifica se um modo de animação permite impulso
---@param modoAnimacao string
---@return boolean
function Modulo_Impulso.ModoPermiteImpulso(modoAnimacao: string): boolean
	return Modulo_Configuracoes.AplicaImpulso(modoAnimacao)
end

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÃO PRINCIPAL
-- ═══════════════════════════════════════════════════════════════════

--- Aplica impulso ao atacante
---@param atacante Model Character atacante
---@param modoAnimacao string Modo de animação atual
---@param tipoAtaque string Tipo de ataque sendo executado
---@return ResultadoImpulso
function Modulo_Impulso.AplicarImpulso(atacante: Model, modoAnimacao: string, tipoAtaque: string): ResultadoImpulso
	-- Verifica se o modo permite impulso
	if not Modulo_Impulso.ModoPermiteImpulso(modoAnimacao) then
		return {
			sucesso = false,
			magnitudeAplicada = nil,
			erro = "Modo '" .. modoAnimacao .. "' não permite impulso",
		}
	end

	-- Validação de entidade
	local valido, erro = Modulo_Impulso.ValidarEntidade(atacante)
	if not valido then
		return {
			sucesso = false,
			magnitudeAplicada = nil,
			erro = erro,
		}
	end

	-- Obtém magnitude
	local magnitude = Modulo_Impulso.ObterMagnitudeImpulso(tipoAtaque)

	-- Obtém HumanoidRootPart
	local humanoidRoot = atacante:FindFirstChild("HumanoidRootPart") :: BasePart

	-- Calcula direção (para frente)
	local direcao = humanoidRoot.CFrame.LookVector
	local elevacao = Vector3.new(0, 2, 0) -- Pequena elevação

	-- Aplica impulso com pcall para segurança
	local sucesso, resultado = pcall(function()
		local impulsoVetor = (direcao * magnitude) + elevacao
		local massa = humanoidRoot.AssemblyMass or 1
		humanoidRoot:ApplyImpulse(impulsoVetor * massa)
	end)

	if not sucesso then
		return {
			sucesso = false,
			magnitudeAplicada = nil,
			erro = "Erro ao aplicar impulso: " .. tostring(resultado),
		}
	end

	return {
		sucesso = true,
		magnitudeAplicada = magnitude,
		erro = nil,
	}
end

return Modulo_Impulso
