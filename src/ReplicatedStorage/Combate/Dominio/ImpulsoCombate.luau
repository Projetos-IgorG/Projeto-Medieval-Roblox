--!strict

--[[
    Script: ImpulsoCombate.luau
    Caminho: src/ReplicatedStorage/Combate/Dominio
    Responsabilidade: Calcula impulsos fisicos gerados por ataques, bloqueios e impactos.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao dispara acoes por conta propria; apenas calcula regras para o script chamador.
    Funcoes principais: ValidarEntidade, ObterMagnitudeImpulso, ModoPermiteImpulso, AplicarImpulso
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modulo_Configuracoes = require(ReplicatedStorage:WaitForChild("Combate"):WaitForChild("Configuracoes"):WaitForChild("ConfigCombate"))

export type ResultadoImpulso = {
	sucesso: boolean,
	magnitudeAplicada: number?,
	erro: string?,
}

local Modulo_Impulso = {}

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

function Modulo_Impulso.ObterMagnitudeImpulso(tipoAtaque: string): number
	local config = Modulo_Configuracoes.ConfiguracaoGlobal

	if tipoAtaque == "AtaquePesado" or tipoAtaque == "AtaqueLeveFinal" then
		return config.MagnitudeImpulsoAtaquePesado
	end

	return config.MagnitudeImpulsoAtaqueLeve
end

function Modulo_Impulso.ModoPermiteImpulso(modoAnimacao: string): boolean
	return Modulo_Configuracoes.AplicaImpulso(modoAnimacao)
end

function Modulo_Impulso.AplicarImpulso(atacante: Model, modoAnimacao: string, tipoAtaque: string): ResultadoImpulso

	if not Modulo_Impulso.ModoPermiteImpulso(modoAnimacao) then
		return {
			sucesso = false,
			magnitudeAplicada = nil,
			erro = "Modo '" .. modoAnimacao .. "' não permite impulso",
		}
	end

	local valido, erro = Modulo_Impulso.ValidarEntidade(atacante)
	if not valido then
		return {
			sucesso = false,
			magnitudeAplicada = nil,
			erro = erro,
		}
	end

	local magnitude = Modulo_Impulso.ObterMagnitudeImpulso(tipoAtaque)

	local humanoidRoot = atacante:FindFirstChild("HumanoidRootPart") :: BasePart

	local direcao = humanoidRoot.CFrame.LookVector
	local elevacao = Vector3.new(0, 5, 0)

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
