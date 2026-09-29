--!strict

--[[
	Script: ResolucaoDefesa.luau
	Caminho: src/ServerScriptService/Combate/Servidor
	Responsabilidade: Decide se um golpe vira Parry, Block ou Hit, avaliando
	    angulo frontal, janela de parry compensada por latencia e validade dos
	    CFrames reportados pelo cliente.
	Uso: ModuleScript; ResolucaoDefesa.Resolver(contexto) retorna o veredito.
	Nao faz: Nao aplica dano, animacao, stun nem knockback.
	Funcoes principais: Resolver, ValidarCFrameCliente
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modulo_Configuracoes =
	require(ReplicatedStorage:WaitForChild("Combate"):WaitForChild("Configuracoes"):WaitForChild("ConfigCombate"))
local RegistroNPC = require(ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC"):WaitForChild("RegistroNPC"))

-- Um CFrame de cliente so e aceito se estiver perto e olhando na mesma direcao
-- que o servidor ve. Fora disso, o servidor manda.
local MAX_DIVERGENCIA_POSICAO = 15
local MIN_DOT_ROTACAO = 0.5 -- cos(60 graus)
local TOLERANCIA_PARRY_NEGATIVA = 0.05

local ResolucaoDefesa = {}

export type Contexto = {
	atacante: Model,
	alvo: Model,
	maquinaAlvo: any,
	tipoAtaque: string,
	cframeAtacanteCliente: CFrame?,
	cframeAlvoCliente: CFrame?,
	momentoHit: number,
	rttAlvo: number,
}

export type Resultado = {
	tipo: string, -- "Parry" | "Block" | "Hit"
	bypassou: boolean,
}

local function semDefesa(bypassou: boolean): Resultado
	return { tipo = "Hit", bypassou = bypassou }
end

local function planoXZ(v: Vector3): Vector3?
	local xz = Vector3.new(v.X, 0, v.Z)
	if xz.Magnitude <= 0.001 then
		return nil
	end
	return xz.Unit
end

-- Aceita o CFrame do cliente so quando ele bate com o do servidor. Antes esse
-- bloco existia duplicado para atacante e alvo.
function ResolucaoDefesa.ValidarCFrameCliente(cliente: CFrame?, servidor: CFrame): CFrame
	if not cliente then
		return servidor
	end
	if (cliente.Position - servidor.Position).Magnitude > MAX_DIVERGENCIA_POSICAO then
		return servidor
	end

	local olharCliente = planoXZ(cliente.LookVector)
	local olharServidor = planoXZ(servidor.LookVector)
	if olharCliente and olharServidor and olharCliente:Dot(olharServidor) < MIN_DOT_ROTACAO then
		return servidor
	end

	return cliente
end

-- NPC mira o alvo dele, nao o LookVector cru do HRP.
local function obterOlharDefensivo(alvo: Model, cframeAlvo: CFrame): Vector3
	local alvoRef = alvo:GetAttribute("NPC_AlvoRef")
	if typeof(alvoRef) ~= "number" or alvoRef == 0 then
		return cframeAlvo.LookVector
	end

	local focado: Model? = nil
	if alvoRef > 0 then
		local player = Players:GetPlayerByUserId(alvoRef)
		focado = player and player.Character or nil
	else
		focado = RegistroNPC.Obter(-alvoRef)
	end

	local hrpFocado = focado and focado:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrpFocado then
		return hrpFocado.Position - cframeAlvo.Position
	end
	return cframeAlvo.LookVector
end

function ResolucaoDefesa.Resolver(ctx: Contexto): Resultado
	local maquinaAlvo = ctx.maquinaAlvo
	if not maquinaAlvo or not maquinaAlvo:EstaBloqueando() then
		return semDefesa(false)
	end

	local hrpAtacante = ctx.atacante:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hrpAlvo = ctx.alvo:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrpAtacante or not hrpAlvo then
		return semDefesa(false)
	end

	local cfAtacante = ResolucaoDefesa.ValidarCFrameCliente(ctx.cframeAtacanteCliente, hrpAtacante.CFrame)
	local cfAlvo = ResolucaoDefesa.ValidarCFrameCliente(ctx.cframeAlvoCliente, hrpAlvo.CFrame)

	local direcao = planoXZ(cfAtacante.Position - cfAlvo.Position)
	local olhar = planoXZ(obterOlharDefensivo(ctx.alvo, cfAlvo))
	if not direcao or not olhar then
		return semDefesa(false)
	end

	local limiteDefesa = Modulo_Configuracoes.ObterConfiguracao("LimiteAnguloDefesa") or 0.342
	local dot = olhar:Dot(direcao)
	if dot < limiteDefesa then
		-- Backstab / flanco: a defesa nao cobre esse angulo.
		return semDefesa(true)
	end

	local dadosAlvo = maquinaAlvo.dados
	local momentoDefesa = dadosAlvo.pendingParryTimestamp or dadosAlvo.momentoBloqueio or ctx.momentoHit
	local decorrido = ctx.momentoHit - momentoDefesa

	local janelaBase = Modulo_Configuracoes.ObterConfiguracao("JanelaParry") or 0.2
	local maxTolerancia = Modulo_Configuracoes.ObterConfiguracao("MaxToleranciaParry") or 0.25
	local janela = janelaBase + math.clamp(ctx.rttAlvo, 0, maxTolerancia)

	local dentroDaJanela = decorrido >= -TOLERANCIA_PARRY_NEGATIVA and decorrido <= janela
	if dentroDaJanela then
		return { tipo = "Parry", bypassou = false }
	end

	return { tipo = "Block", bypassou = false }
end

return ResolucaoDefesa
