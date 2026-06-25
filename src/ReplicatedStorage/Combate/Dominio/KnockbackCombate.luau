--!strict

--[[
    Script: KnockbackCombate.luau
    Caminho: src/ReplicatedStorage/Combate/Dominio
    Responsabilidade: Calcula direcao, forca e aplicacao de knockback em alvos atingidos.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao dispara acoes por conta propria; apenas calcula regras para o script chamador.
    Funcoes principais: ValidarAlvo, ValidarAtacante, ObterMagnitudeKnockback, ModoPermiteKnockback, AplicarKnockback
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modulo_Configuracoes = require(ReplicatedStorage:WaitForChild("Combate"):WaitForChild("Configuracoes"):WaitForChild("ConfigCombate"))

local Remotos = ReplicatedStorage:FindFirstChild("Remotos")
local AplicarKnockbackRemote = Remotos and Remotos:FindFirstChild("AplicarKnockback")

export type ResultadoKnockback = {
	sucesso: boolean,
	magnitudeAplicada: number?,
	metodo: string?,
	erro: string?,
}

local Modulo_Knockback = {}

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

function Modulo_Knockback.ObterMagnitudeKnockback(tipoAtaque: string): number
	local config = Modulo_Configuracoes.ConfiguracaoGlobal

	if tipoAtaque == "AtaqueFinal" then
		return 25
	end

	return config.MagnitudeKnockbackLeve or 15
end

function Modulo_Knockback.ModoPermiteKnockback(modoAnimacao: string): boolean
	return Modulo_Configuracoes.AplicaKnockback(modoAnimacao)
end

function Modulo_Knockback.AplicarKnockback(
	atacante: Model,
	alvo: Model,
	modoAnimacao: string,
	tipoAtaque: string
): ResultadoKnockback

	if not Modulo_Knockback.ModoPermiteKnockback(modoAnimacao) then
		return {
			sucesso = false,
			magnitudeAplicada = nil,
			metodo = nil,
			erro = "Modo '" .. modoAnimacao .. "' não permite knockback",
		}
	end

	local atacanteValido, atacanteErro = Modulo_Knockback.ValidarAtacante(atacante)
	if not atacanteValido then
		return {
			sucesso = false,
			magnitudeAplicada = nil,
			metodo = nil,
			erro = atacanteErro,
		}
	end

	local alvoValido, alvoErro = Modulo_Knockback.ValidarAlvo(alvo)
	if not alvoValido then
		return {
			sucesso = false,
			magnitudeAplicada = nil,
			metodo = nil,
			erro = alvoErro,
		}
	end

	local magnitude = Modulo_Knockback.ObterMagnitudeKnockback(tipoAtaque)

	local atacanteRoot = atacante:FindFirstChild("HumanoidRootPart") :: BasePart
	local direcao = atacanteRoot.CFrame.LookVector
	direcao = Vector3.new(direcao.X, 0, direcao.Z).Unit

	local player = Players:GetPlayerFromCharacter(alvo)

	if player and AplicarKnockbackRemote then

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

		local alvoRoot = alvo:FindFirstChild("HumanoidRootPart") :: BasePart

		local sucesso, resultado = pcall(function()
			if alvoRoot.Anchored then
				local deslocamento = math.clamp(magnitude * 0.05, 1.5, 8)
				local novaPosicao = alvoRoot.Position + direcao * deslocamento
				alvoRoot.CFrame = CFrame.lookAt(novaPosicao, novaPosicao + direcao)
			else
				-- Knockback puramente horizontal: sem elevacao Y para evitar pulinhos.
				local velocidadeAtual = alvoRoot.AssemblyLinearVelocity
				alvoRoot.AssemblyLinearVelocity = Vector3.new(
					direcao.X * magnitude,
					velocidadeAtual.Y,
					direcao.Z * magnitude
				)
			end
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
