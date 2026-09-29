--!strict

--[[
	Script: ProcessadorHit.luau
	Caminho: src/ServerScriptService/Combate/Servidor
	Responsabilidade: Valida e aplica um acerto de hitbox. Faz rebobinagem de
	    posicao (lag compensation), respeita esquiva e i-frames do defensor,
	    delega o veredito de defesa a ResolucaoDefesa e aplica dano, stun,
	    knockback e feedback visual.
	Uso: ModuleScript; ProcessarHitboxAcerto vem do roteador de acoes e
	    ProcessarHit e chamado tambem pelo controlador de NPC do servidor.
	Nao faz: Nao conecta RemoteEvents nem gerencia estado de movimento.
	Funcoes principais: ProcessarHit, ProcessarHitboxAcerto
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CatalogoItens =
	require(ReplicatedStorage:WaitForChild("Dados"):WaitForChild("Itens"):WaitForChild("CatalogoItens"))
local Combate = ReplicatedStorage:WaitForChild("Combate")
local Modulo_Configuracoes = require(Combate:WaitForChild("Configuracoes"):WaitForChild("ConfigCombate"))
local Modulo_Dano = require(Combate:WaitForChild("Dominio"):WaitForChild("DanoCombate"))
local Modulo_Knockback = require(Combate:WaitForChild("Dominio"):WaitForChild("KnockbackCombate"))

local Nucleo = require(script.Parent:WaitForChild("NucleoCombate"))
local ResolucaoDefesa = require(script.Parent:WaitForChild("ResolucaoDefesa"))
local Historico = require(script.Parent:WaitForChild("HistoricoPosicoes"))
local Ragdoll = require(script.Parent:WaitForChild("Ragdoll"))

local MaquinaDeEstados = Nucleo.MaquinaDeEstados
local DebugPrint = Nucleo.DebugPrint

local Remotos = ReplicatedStorage:WaitForChild("Remotos")
local FeedbackCombate = Remotos:WaitForChild("DanoDebugVisual") :: RemoteEvent

-- Quanto o servidor aceita voltar no tempo para validar um hit.
local MAX_REBOBINAGEM = 0.3
-- Folga sobre o alcance da arma. Com rebobinagem nao precisa mais ser 2.0/2.5.
local FATOR_ALCANCE = 1.5
local MAO_PARA_SLOT = { Right = "RightArm", Left = "LeftArm" }

local ProcessadorHit = {}

local function obterToolPorMao(character: Model, mao: string): Tool?
	local slotName = MAO_PARA_SLOT[mao]
	if slotName then
		local equipamento = character:FindFirstChild("Equipamento")
		local bracos = equipamento and equipamento:FindFirstChild("Bracos")
		local slotOV = bracos and bracos:FindFirstChild(slotName) :: ObjectValue?
		if slotOV and slotOV.Value and slotOV.Value:IsA("Tool") then
			return slotOV.Value :: Tool
		end
	end
	return character:FindFirstChildOfClass("Tool")
end

-- =============================================================================
-- Favor the defender. Avaliado no tempo rebobinado E no tempo atual: se
-- qualquer um dos dois disser que o alvo esquivou, o hit cai.
-- =============================================================================

local function esquivandoEm(alvo: Model, maquinaAlvo: any, clockReferencia: number): (boolean, string?)
	if not maquinaAlvo then
		return false, nil
	end

	local estado = maquinaAlvo:ObterEstadoAcao()
	if estado == MaquinaDeEstados.EstadoAcao.Rolando or estado == MaquinaDeEstados.EstadoAcao.Dashando then
		return true, "AlvoEsquivando"
	end

	local dados = maquinaAlvo.dados
	local janelaIframes = Modulo_Configuracoes.ObterConfiguracao("JanelaIframesPosEsquiva") or 0.08
	local fimEsquiva = math.max(dados.ultimoRollFim or 0, dados.ultimoDashFim or 0)
	if clockReferencia - fimEsquiva < janelaIframes then
		return true, "AlvoIframesPosEsquiva"
	end

	-- Compensacao a favor do defensor: se ele acabou de iniciar a esquiva no
	-- cliente dele e o servidor ainda nao processou, o hit cai.
	local player = Players:GetPlayerFromCharacter(alvo)
	if player then
		local maxTol = Modulo_Configuracoes.ObterConfiguracao("MaxToleranciaEsquiva") or 0.15
		local tolerancia = math.clamp(Nucleo.ObterRTT(alvo, maxTol * 2) / 2, 0, maxTol)
		local inicioEsquiva = math.max(dados.ultimoRoll or 0, dados.ultimoDash or 0)
		if clockReferencia - inicioEsquiva < tolerancia then
			return true, "AlvoRecemEsquivou"
		end
	end

	return false, nil
end

-- =============================================================================
-- Aplicacao do golpe.
-- =============================================================================

local function feedback(alvo: Model, valor: number, info: any)
	if FeedbackCombate then
		FeedbackCombate:FireAllClients(alvo, valor, info)
	end
end

function ProcessadorHit.ProcessarHit(
	atacante: Model,
	alvo: Model,
	tipoAtaque: string,
	danoOverride: number?,
	_parteAtingida: string?,
	multiplicadorDano: number?,
	atacanteCFrameCliente: CFrame?,
	alvoCFrameCliente: CFrame?,
	momentoHitServidor: number?
)
	local maquinaAtacante = Nucleo.ObterMaquinaExistente(atacante)
	local maquinaAlvo = Nucleo.ObterMaquina(alvo)
	if not maquinaAtacante or not maquinaAlvo then
		return
	end

	local alvoHumanoid = alvo:FindFirstChildOfClass("Humanoid")
	if alvoHumanoid and alvoHumanoid.Health <= 0 then
		-- Alvo ja morto: registra no ragdoll e da feedback, sem dano nem stun.
		Ragdoll.RegistrarAtaque(alvo, atacante)
		feedback(alvo, 0, {
			tipo = "Hit",
			atacante = atacante,
			multiplicador = multiplicadorDano,
			bypassed = true,
		})
		return
	end

	local momentoHit = momentoHitServidor or workspace:GetServerTimeNow()

	local veredito = ResolucaoDefesa.Resolver({
		atacante = atacante,
		alvo = alvo,
		maquinaAlvo = maquinaAlvo,
		tipoAtaque = tipoAtaque,
		cframeAtacanteCliente = atacanteCFrameCliente,
		cframeAlvoCliente = alvoCFrameCliente,
		momentoHit = momentoHit,
		rttAlvo = Nucleo.ObterRTT(alvo),
	})

	-- O timestamp pendente vale por um swing so.
	maquinaAlvo.dados.pendingParryTimestamp = nil

	if veredito.tipo == "Parry" then
		local tempoStun = Modulo_Configuracoes.ObterConfiguracao("TempoStunAparado") or 0.7
		local tempoAparando = Modulo_Configuracoes.ObterConfiguracao("TempoAparando") or tempoStun

		Nucleo.TocarAnimacao(alvo, "Aparar")
		Nucleo.TocarAnimacao(atacante, "Aparado")
		Nucleo.CancelarTimeoutAtaque(maquinaAtacante)

		if maquinaAtacante.AplicarAparado then
			maquinaAtacante:AplicarAparado(tempoStun)
		else
			maquinaAtacante:EntrarStun(tempoStun)
		end
		if maquinaAlvo.AplicarAparando then
			maquinaAlvo:AplicarAparando(tempoAparando)
		end

		-- Parry bem sucedido zera o cooldown: da pra aparar o proximo na hora.
		maquinaAlvo.dados.ultimoParry = 0

		local impulso = require(Combate:WaitForChild("Dominio"):WaitForChild("ImpulsoCombate"))
		local resultadoImpulso = impulso.AplicarImpulsoParry(alvo, atacante)
		if not resultadoImpulso.sucesso then
			DebugPrint("[Combate] Falha no impulso de parry: " .. tostring(resultadoImpulso.erro))
		end

		feedback(alvo, 0, { tipo = "Parry", atacante = atacante })
		return
	end

	if veredito.tipo == "Block" then
		if tipoAtaque == "AtaqueFinal" then
			maquinaAlvo:QuebrarDefesa(0.6)
			Nucleo.TocarAnimacao(alvo, "DefesaQuebrada")
			Nucleo.AplicarKnockback(alvo, atacante, tipoAtaque)
			feedback(alvo, 0, { tipo = "BlockBroken", atacante = atacante })
			return
		end

		-- Ataque leve absorvido: sem dano, mas os dois sentem o impacto.
		Modulo_Knockback.AplicarKnockback(atacante, alvo, maquinaAtacante:ObterModo(), "Ataque")
		Modulo_Knockback.AplicarKnockback(alvo, atacante, maquinaAlvo:ObterModo(), "Ataque")

		local danoBase: number = 0
		if danoOverride then
			danoBase = danoOverride
		else
			local tool = obterToolPorMao(atacante, "Right") or obterToolPorMao(atacante, "Left") or atacante:FindFirstChildOfClass("Tool")
			local base = tool and Modulo_Dano.ObterDanoBase(tool)
			if base then
				danoBase = base
			end
		end
		feedback(alvo, danoBase, { tipo = "Block", atacante = atacante })
		return
	end

	-- ===== HIT =====
	Ragdoll.RegistrarAtaque(alvo, atacante)

	local resultado
	if danoOverride then
		resultado = Modulo_Dano.AplicarDanoComValor(atacante, alvo, tipoAtaque, danoOverride)
	else
		local tool = obterToolPorMao(atacante, "Right") or obterToolPorMao(atacante, "Left") or atacante:FindFirstChildOfClass("Tool")
		if not tool then
			DebugPrint("[Combate] Sem tool para aplicar dano")
			return
		end
		resultado = Modulo_Dano.AplicarDano(tool, atacante, alvo, tipoAtaque)
	end

	if not resultado.sucesso then
		DebugPrint("[Combate] Falha ao aplicar dano: " .. tostring(resultado.erro))
		return
	end

	local danoAplicado = resultado.danoAplicado or 0
	Nucleo.NotificarDano(atacante, alvo, tipoAtaque, danoAplicado)

	maquinaAlvo:EntrarStun(Modulo_Configuracoes.ObterConfiguracao("TempoStunLeve") or 0.3)
	Nucleo.TocarAnimacao(alvo, "Stunado")
	Nucleo.AplicarKnockback(alvo, atacante, tipoAtaque)

	feedback(alvo, danoAplicado, {
		tipo = "Hit",
		atacante = atacante,
		multiplicador = multiplicadorDano,
		bypassed = veredito.bypassou,
	})
end

-- =============================================================================
-- Entrada vinda do cliente atacante.
-- =============================================================================

function ProcessadorHit.ProcessarHitboxAcerto(entidade: Model, dados: any): (boolean, string?)
	if typeof(dados) ~= "table" then
		return false, "DadosInvalidos"
	end

	local mao = dados.mao
	if mao ~= "Right" and mao ~= "Left" then
		return false, "MaoInvalida"
	end

	local alvoInstance = dados.alvo
	if typeof(alvoInstance) ~= "Instance" or not alvoInstance:IsA("Model") then
		return false, "AlvoInvalido"
	end
	local alvo = alvoInstance :: Model
	if alvo == entidade then
		return false, "AutoHit"
	end

	local alvoHumanoid = alvo:FindFirstChildOfClass("Humanoid")
	if not alvoHumanoid or alvoHumanoid.Health <= 0 then
		return false, "AlvoSemHumanoid"
	end

	local maquina = Nucleo.ObterMaquina(entidade)
	local estadoAcao = maquina:ObterEstadoAcao()
	if estadoAcao ~= "Atacando" and estadoAcao ~= "AtacandoAgachado" then
		return false, "NaoAtacando"
	end

	-- Ataque interrompido por stun/parry nao produz hit.
	if (maquina.dados.ultimoStunTimestamp or 0) > (maquina.dados.ultimoAtaque or 0) then
		return false, "AtaqueInterrompido"
	end

	local tool = obterToolPorMao(entidade, mao)
	if not tool then
		return false, "SemTool"
	end

	local danoBase = Modulo_Dano.ObterDanoBase(tool)
	if not danoBase then
		return false, "SemDanoBase"
	end

	-- ===== Rebobinagem =====
	local agora = workspace:GetServerTimeNow()
	local momentoHit = agora - math.clamp(Nucleo.ObterRTT(entidade) / 2, 0, MAX_REBOBINAGEM)
	if typeof(dados.timestamp) == "number" then
		momentoHit = math.clamp(dados.timestamp, agora - MAX_REBOBINAGEM, agora)
	end
	-- Mesma defasagem, mas no relogio os.clock() usado pela maquina de estados.
	local clockDoHit = os.clock() - (agora - momentoHit)

	local alcanceMaximo = 8
	local idTool = tool:GetAttribute("Id")
	local catalogData = idTool and CatalogoItens.Get(idTool)
	if catalogData and catalogData.Alcance then
		alcanceMaximo = catalogData.Alcance
	end

	local hrpAtacante = entidade:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hrpAlvo = alvo:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrpAtacante and hrpAlvo then
		local posAtacante = Historico.ObterPosicao(entidade, momentoHit) or hrpAtacante.Position
		local posAlvo = Historico.ObterPosicao(alvo, momentoHit) or hrpAlvo.Position
		local distancia = (posAtacante - posAlvo).Magnitude
		if distancia > alcanceMaximo * FATOR_ALCANCE then
			DebugPrint(
				string.format(
					"[Combate] %s: hit rejeitado - distancia rebobinada %.1f > %.1f",
					entidade.Name,
					distancia,
					alcanceMaximo * FATOR_ALCANCE
				)
			)
			return false, "ForaDeAlcance"
		end
	end

	-- ===== Favor the defender, nos dois instantes =====
	local maquinaAlvo = Nucleo.ObterMaquina(alvo)
	local esquivouPassado, motivoPassado = esquivandoEm(alvo, maquinaAlvo, clockDoHit)
	if esquivouPassado then
		return false, motivoPassado
	end
	local esquivouAgora, motivoAgora = esquivandoEm(alvo, maquinaAlvo, os.clock())
	if esquivouAgora then
		return false, motivoAgora
	end

	-- ===== Dano =====
	local modo = maquina:ObterModo()
	local tipoAtaque = "Ataque"
	if estadoAcao == "Atacando" then
		tipoAtaque = Nucleo.DeterminarTipoAtaque(modo, maquina.dados.indiceCombo or 1)
	end

	local configCombo = Modulo_Configuracoes.ObterConfiguracaoCombo(modo)
	local divideDano = configCombo and configCombo.divideDano == true

	local multMax = Modulo_Configuracoes.ObterConfiguracao("MultiplicadorDanoMaximoCarga") or 1.2
	local multiplicador = 1.0
	if typeof(dados.multiplicadorDano) == "number" then
		multiplicador = math.clamp(dados.multiplicadorDano, 1.0, multMax)
	end

	local danoFinal = (if divideDano then danoBase / 2 else danoBase) * multiplicador

	-- Sem task.delay: o dano sai agora. A justica com o defensor ja foi feita
	-- pela rebobinagem e pela dupla checagem de esquiva.
	ProcessadorHit.ProcessarHit(
		entidade,
		alvo,
		tipoAtaque,
		danoFinal,
		dados.parteAtingida,
		multiplicador,
		dados.cframe,
		dados.alvoCFrame,
		momentoHit
	)

	DebugPrint(
		string.format(
			"[Combate] %s: HitboxAcerto - mao=%s alvo=%s tipo=%s mult=%.2f rebob=%.3fs",
			entidade.Name,
			mao,
			alvo.Name,
			tipoAtaque,
			multiplicador,
			agora - momentoHit
		)
	)

	return true, tipoAtaque
end

return ProcessadorHit
