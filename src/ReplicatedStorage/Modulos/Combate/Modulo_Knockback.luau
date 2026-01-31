--[[
	Modulo_Knockback.luau
	
	Aplica knockback no player atacado baseado na configuração do modoAnimacao.
	
	Responsabilidades:
	- Verificar se o modoAnimacao permite knockback
	- Validar estado do alvo
	- Aplicar knockback físico ao alvo atacado
	
	O knockback é DESABILITADO para:
	- Ferramentas de interação (tipo "Interacao")
]]

--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ═══════════════════════════════════════════════════════════════════
-- DEPENDÊNCIAS
-- ═══════════════════════════════════════════════════════════════════

local Combate = ReplicatedStorage:WaitForChild("Modulos"):WaitForChild("Combate")
local Modulo_Configuracoes = require(Combate:WaitForChild("Modulo_Configuracoes"))

-- RemoteEvent para knockback no cliente (pode não existir)
local Remotos = ReplicatedStorage:FindFirstChild("Remotos")
local AplicarKnockbackRemote = Remotos and Remotos:FindFirstChild("AplicarKnockback")

-- ═══════════════════════════════════════════════════════════════════
-- TYPES
-- ═══════════════════════════════════════════════════════════════════

export type ResultadoKnockback = {
	sucesso: boolean,
	magnitudeAplicada: number?,
	metodo: string?, -- "cliente" ou "servidor"
	erro: string?,
}

-- ═══════════════════════════════════════════════════════════════════
-- MÓDULO
-- ═══════════════════════════════════════════════════════════════════

local Modulo_Knockback = {}

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES DE VALIDAÇÃO
-- ═══════════════════════════════════════════════════════════════════

--- Valida se um alvo pode receber knockback
---@param alvo Model
---@return boolean sucesso
---@return string? erro
function Modulo_Knockback.ValidarAlvo(alvo: Model): (boolean, string?)
	if not alvo then
		return false, "Alvo é nil"
	end

	if not alvo:IsA("Model") then
		return false, "Alvo não é um Model"
	end

	local humanoidRoot = alvo:FindFirstChild("HumanoidRootPart")
	if not humanoidRoot then
		return false, "Alvo sem HumanoidRootPart"
	end

	if not humanoidRoot:IsA("BasePart") then
		return false, "HumanoidRootPart não é BasePart"
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

--- Valida se o atacante é válido (para obter direção)
---@param atacante Model
---@return boolean sucesso
---@return string? erro
function Modulo_Knockback.ValidarAtacante(atacante: Model): (boolean, string?)
	if not atacante then
		return false, "Atacante é nil"
	end

	local humanoidRoot = atacante:FindFirstChild("HumanoidRootPart")
	if not humanoidRoot then
		return false, "Atacante sem HumanoidRootPart"
	end

	return true, nil
end

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES DE ACESSO
-- ═══════════════════════════════════════════════════════════════════

--- Obtém a magnitude do knockback baseado no tipo de ataque
---@param tipoAtaque string
---@return number
function Modulo_Knockback.ObterMagnitudeKnockback(tipoAtaque: string): number
	local config = Modulo_Configuracoes.ConfiguracaoGlobal

	if tipoAtaque == "AtaquePesado" or tipoAtaque == "AtaqueLeveFinal" then
		return config.MagnitudeKnockbackPesado
	end

	return config.MagnitudeKnockbackLeve
end

--- Verifica se um modo de animação permite knockback
---@param modoAnimacao string
---@return boolean
function Modulo_Knockback.ModoPermiteKnockback(modoAnimacao: string): boolean
	return Modulo_Configuracoes.AplicaKnockback(modoAnimacao)
end

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÃO PRINCIPAL
-- ═══════════════════════════════════════════════════════════════════

--- Aplica knockback ao alvo atacado
---@param atacante Model Character atacante (para direção)
---@param alvo Model Character ou NPC alvo
---@param modoAnimacao string Modo de animação atual
---@param tipoAtaque string Tipo de ataque sendo executado
---@return ResultadoKnockback
function Modulo_Knockback.AplicarKnockback(
	atacante: Model,
	alvo: Model,
	modoAnimacao: string,
	tipoAtaque: string
): ResultadoKnockback
	-- Verifica se o modo permite knockback
	if not Modulo_Knockback.ModoPermiteKnockback(modoAnimacao) then
		return {
			sucesso = false,
			magnitudeAplicada = nil,
			metodo = nil,
			erro = "Modo '" .. modoAnimacao .. "' não permite knockback",
		}
	end

	-- Validação de atacante
	local atacanteValido, atacanteErro = Modulo_Knockback.ValidarAtacante(atacante)
	if not atacanteValido then
		return {
			sucesso = false,
			magnitudeAplicada = nil,
			metodo = nil,
			erro = atacanteErro,
		}
	end

	-- Validação de alvo
	local alvoValido, alvoErro = Modulo_Knockback.ValidarAlvo(alvo)
	if not alvoValido then
		return {
			sucesso = false,
			magnitudeAplicada = nil,
			metodo = nil,
			erro = alvoErro,
		}
	end

	-- Obtém magnitude
	local magnitude = Modulo_Knockback.ObterMagnitudeKnockback(tipoAtaque)

	-- Calcula direção baseada no LookVector do ATACANTE
	local atacanteRoot = atacante:FindFirstChild("HumanoidRootPart") :: BasePart
	local direcao = atacanteRoot.CFrame.LookVector
	direcao = Vector3.new(direcao.X, 0, direcao.Z).Unit -- Remove componente Y

	-- Verifica se deve enviar para cliente ou aplicar diretamente
	local player = Players:GetPlayerFromCharacter(alvo)

	if player and AplicarKnockbackRemote then
		-- Envia para o cliente do alvo
		local sucesso, resultado = pcall(function()
			AplicarKnockbackRemote:FireClient(player, direcao, magnitude)
		end)

		if not sucesso then
			return {
				sucesso = false,
				magnitudeAplicada = nil,
				metodo = nil,
				erro = "Erro ao enviar knockback para cliente: " .. tostring(resultado),
			}
		end

		return {
			sucesso = true,
			magnitudeAplicada = magnitude,
			metodo = "cliente",
			erro = nil,
		}
	else
		-- NPC ou RemoteEvent não existe: aplica diretamente no servidor
		local alvoRoot = alvo:FindFirstChild("HumanoidRootPart") :: BasePart

		local sucesso, resultado = pcall(function()
			local velocidadeAtual = alvoRoot.AssemblyLinearVelocity
			alvoRoot.AssemblyLinearVelocity = Vector3.new(
				direcao.X * magnitude,
				velocidadeAtual.Y + 5, -- Leve elevação
				direcao.Z * magnitude
			)
		end)

		if not sucesso then
			return {
				sucesso = false,
				magnitudeAplicada = nil,
				metodo = nil,
				erro = "Erro ao aplicar knockback no servidor: " .. tostring(resultado),
			}
		end

		return {
			sucesso = true,
			magnitudeAplicada = magnitude,
			metodo = "servidor",
			erro = nil,
		}
	end
end

return Modulo_Knockback
