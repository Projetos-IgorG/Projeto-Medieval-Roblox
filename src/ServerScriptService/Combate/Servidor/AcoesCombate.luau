--!strict

--[[
	Script: AcoesCombate.luau
	Caminho: src/ServerScriptService/Combate/Servidor
	Responsabilidade: Implementa as acoes de combate e movimento pedidas pelo
	    cliente (atacar, bloquear, esquivar, correr, equipar, combo) validando
	    tudo contra a maquina de estados antes de aplicar efeito.
	Uso: ModuleScript; usado pelo roteador em CombateServidor.
	Nao faz: Nao conecta RemoteEvents, nao aplica dano e nao resolve defesa.
	Funcoes principais: ProcessarAtacarEmPe, ProcessarBloquear, ProcessarRoll,
	    ProcessarDash, ProcessarEquipar, ProcessarComboHitbox
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combate = ReplicatedStorage:WaitForChild("Combate")
local Modulo_Configuracoes = require(Combate:WaitForChild("Configuracoes"):WaitForChild("ConfigCombate"))

local Nucleo = require(script.Parent:WaitForChild("NucleoCombate"))
local MaquinaDeEstados = Nucleo.MaquinaDeEstados
local DebugPrint = Nucleo.DebugPrint

-- Margem alem do RTT aceita num timestamp reportado pelo cliente.
local MARGEM_TIMESTAMP = 0.05

local AcoesCombate = {}

local function definirStatusBool(entidade: Model, nome: string, valor: boolean)
	local status = entidade:FindFirstChild("Status")
	local obj = status and status:FindFirstChild(nome)
	if obj and obj:IsA("BoolValue") then
		obj.Value = valor
	end
end

local function definirWalkSpeed(entidade: Model, chaveConfig: string, padrao: number, fator: number?)
	local humanoid = entidade:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local base = Modulo_Configuracoes.ObterConfiguracao(chaveConfig) or padrao
	humanoid.WalkSpeed = base * (fator or 1)
end

local function velocidadeDosDados(dados: any): number
	if typeof(dados) == "table" and typeof(dados.velocidade) == "number" then
		return dados.velocidade
	end
	return 1.0
end

-- =============================================================================
-- Ataque.
-- =============================================================================

function AcoesCombate.ProcessarAtacarEmPe(entidade: Model, dados: any?): (boolean, string?)
	local maquina = Nucleo.ObterMaquina(entidade)
	local sucesso, tipoAtaque, motivo = maquina:TenteAtacarEmPe()

	if not sucesso then
		if motivo == "ComboContinuado" then
			DebugPrint(string.format("[Combate] %s: combo input registrado", entidade.Name))
			return true, nil
		end
		DebugPrint(string.format("[Combate] %s: AtacarEmPe FALHOU - %s", entidade.Name, motivo or "?"))
		return false, motivo
	end

	if not tipoAtaque then
		return true, nil
	end

	maquina.dados.carregando = false
	maquina.dados.momentoLiberacaoCarga = nil
	Nucleo.AgendarTimeoutAtaque(entidade, maquina)

	Nucleo.TocarAnimacao(entidade, tipoAtaque, false, velocidadeDosDados(dados))
	Nucleo.AplicarImpulsoAtacante(entidade, tipoAtaque)
	definirWalkSpeed(entidade, "VelocidadeBloqueando", 6, 1.5)

	DebugPrint(string.format("[Combate] %s: AtacarEmPe OK - tipo=%s", entidade.Name, tipoAtaque))
	return true, tipoAtaque
end

function AcoesCombate.ProcessarAtacarAgachado(entidade: Model, dados: any?): (boolean, string?)
	local maquina = Nucleo.ObterMaquina(entidade)
	local sucesso, tipoAtaque, motivo = maquina:TenteAtacarAgachado()
	if not sucesso then
		return false, motivo
	end

	tipoAtaque = tipoAtaque or "Ataque"
	maquina.dados.carregando = false
	maquina.dados.momentoLiberacaoCarga = nil
	Nucleo.AgendarTimeoutAtaque(entidade, maquina)

	Nucleo.TocarAnimacao(entidade, tipoAtaque, false, velocidadeDosDados(dados))
	Nucleo.AplicarImpulsoAtacante(entidade, tipoAtaque)
	definirWalkSpeed(entidade, "VelocidadeBloqueando", 6, 1.5)

	return true, tipoAtaque
end

function AcoesCombate.ProcessarComboHitbox(entidade: Model, dados: any): (boolean, string?)
	local indiceGolpe = if typeof(dados) == "table" then (dados.indice or 0) else (tonumber(dados) or 0)
	local maquina = Nucleo.ObterMaquina(entidade)

	if maquina:ObterEstadoAcao() ~= "Atacando" then
		return false, "NaoAtacando"
	end

	local modo = maquina:ObterModo()
	local tipoAtaque = Nucleo.DeterminarTipoAtaque(modo, indiceGolpe)

	maquina:AvancarGolpeCombo(indiceGolpe)
	maquina.dados.hitboxAtivou = true
	Nucleo.NotificarHitbox(entidade, maquina.dados)
	Nucleo.AplicarImpulsoAtacante(entidade, tipoAtaque)

	if Nucleo.EhGolpeFinal(modo, indiceGolpe) then
		local tempoFinal = Modulo_Configuracoes.ObterConfiguracao("JanelaCancelamentoComboFinal") or 0.6
		Nucleo.AgendarTimeoutAtaque(entidade, maquina, tempoFinal)
	end

	DebugPrint(string.format("[Combate] %s: ComboHitbox %d (%s)", entidade.Name, indiceGolpe, tipoAtaque))
	return true, tipoAtaque
end

function AcoesCombate.ProcessarComboContinuado(entidade: Model, proximoIndice: number): (boolean, string?)
	local maquina = Nucleo.ObterMaquina(entidade)
	if maquina:ObterEstadoAcao() ~= "Atacando" then
		return false, "NaoAtacando"
	end

	maquina:DesativarJanelaCombo()
	local agora = os.clock()
	maquina.dados.ultimaContinuacaoCombo = agora
	maquina.dados.ultimoAtaque = agora
	maquina.dados.hitboxAtivou = false
	maquina.dados.velocidadeAnimacao = 1.0
	maquina.dados.carregando = false
	maquina.dados.momentoLiberacaoCarga = nil

	Nucleo.AgendarTimeoutAtaque(entidade, maquina)
	DebugPrint(string.format("[Combate] %s: combo continuado para %d", entidade.Name, proximoIndice))
	return true, nil
end

function AcoesCombate.ProcessarComboTerminou(entidade: Model): (boolean, string?)
	local maquina = Nucleo.ObterMaquina(entidade)
	if maquina:ObterEstadoAcao() == "Atacando" then
		Nucleo.CancelarTimeoutAtaque(maquina)
		maquina:CompletarAcao()
		Nucleo.PararAnimacao(entidade)
		Nucleo.SincronizarEstado(entidade)
	end
	return true, nil
end

function AcoesCombate.ProcessarComboEarlyCancel(entidade: Model): (boolean, string?)
	local maquina = Nucleo.ObterMaquina(entidade)
	if maquina:ObterEstadoAcao() == "Atacando" then
		Nucleo.CancelarTimeoutAtaque(maquina)
		maquina:CompletarAcao()
		definirWalkSpeed(entidade, "VelocidadeAndando", 14)
		Nucleo.PararAnimacao(entidade)
		Nucleo.SincronizarEstado(entidade)
	end
	return true, nil
end

function AcoesCombate.ProcessarFintar(entidade: Model, tipoAtaque: string): (boolean, string?)
	local maquina = Nucleo.ObterMaquina(entidade)
	local estadoAcao = maquina:ObterEstadoAcao()
	local hitboxAtivou = maquina.dados.hitboxAtivou == true

	-- Cancelar so vale enquanto o golpe nao saiu.
	if not (tipoAtaque == "Ataque" and estadoAcao == "Atacando" and not hitboxAtivou) then
		DebugPrint(
			string.format(
				"[Combate] %s: finta REJEITADA - estado=%s hitboxAtivou=%s",
				entidade.Name,
				tostring(estadoAcao),
				tostring(hitboxAtivou)
			)
		)
		return true, nil
	end

	Nucleo.CancelarTimeoutAtaque(maquina)
	maquina:CompletarAcao()

	local cooldownCompleto = Modulo_Configuracoes.ObterConfiguracao("CooldownComboLeve") or 0.4
	maquina.dados.ultimoComboTerminou = os.clock() - cooldownCompleto + 0.1

	definirWalkSpeed(entidade, "VelocidadeAndando", 14)
	Nucleo.PararAnimacao(entidade)
	Nucleo.SincronizarEstado(entidade)

	DebugPrint(string.format("[Combate] %s: ataque fintado", entidade.Name))
	return true, nil
end

function AcoesCombate.ProcessarAjustarVelocidadeAnimacao(entidade: Model, dados: any): (boolean, string?)
	local maquina = Nucleo.ObterMaquina(entidade)
	if maquina:ObterEstadoAcao() ~= "Atacando" then
		return false, "NaoAtacando"
	end
	if typeof(dados) ~= "table" or typeof(dados.velocidade) ~= "number" then
		return false, "DadosInvalidos"
	end

	local velocidade = math.clamp(dados.velocidade, 0.1, 3.0)
	maquina.dados.velocidadeAnimacao = velocidade

	local velCarga = Modulo_Configuracoes.ObterConfiguracao("VelocidadeCargaAtaque") or 0.4
	if velocidade <= velCarga + 0.05 then
		maquina.dados.carregando = true
	elseif maquina.dados.carregando then
		maquina.dados.carregando = false
		maquina.dados.momentoLiberacaoCarga = os.clock()
	end

	Nucleo.AjustarVelocidadeAnimacao(entidade, velocidade)
	return true, nil
end

-- =============================================================================
-- Defesa.
-- =============================================================================

function AcoesCombate.ProcessarBloquear(
	entidade: Model,
	shiftLockAtivo: boolean?,
	clienteTimestamp: number?
): (boolean, string?)
	local maquina = Nucleo.ObterMaquina(entidade)
	local sucesso, motivo = maquina:TenteBloquear(shiftLockAtivo)
	if not sucesso then
		DebugPrint(string.format("[Combate] %s: Bloquear FALHOU - %s", entidade.Name, motivo or "?"))
		return false, motivo
	end

	definirWalkSpeed(entidade, "VelocidadeBloqueando", 6)

	local agoraServidor = workspace:GetServerTimeNow()
	local agoraClock = os.clock()
	local cooldownParry = Modulo_Configuracoes.ObterConfiguracao("CooldownParry") or 2.4
	local podeParry = (agoraClock - (maquina.dados.ultimoParry or 0)) >= cooldownParry

	maquina.dados.momentoBloqueio = agoraServidor

	if not podeParry then
		maquina.dados.prontoParaAparar = false
		maquina.dados.pendingParryTimestamp = agoraServidor
		definirStatusBool(entidade, "ProntoAparar", false)
		Nucleo.SincronizarEstado(entidade)
		return true, nil
	end

	-- Timestamp do cliente clampado dos DOIS lados. Antes so havia teto, entao
	-- mandar sempre (agora + 0.09) esticava a janela de parry de graca.
	local rtt = Nucleo.ObterRTT(entidade)
	local piso = agoraServidor - (rtt + MARGEM_TIMESTAMP)
	local timestamp = agoraServidor
	if typeof(clienteTimestamp) == "number" then
		timestamp = math.clamp(clienteTimestamp, piso, agoraServidor)
	end

	maquina.dados.prontoParaAparar = true
	maquina.dados.ultimoParry = agoraClock
	maquina.dados.pendingParryTimestamp = timestamp
	definirStatusBool(entidade, "ProntoAparar", true)
	Nucleo.SincronizarEstado(entidade)

	local tokenParry = (maquina.dados.tokenParry or 0) + 1
	maquina.dados.tokenParry = tokenParry

	task.delay(Modulo_Configuracoes.ObterConfiguracao("JanelaParry") or 0.2, function()
		if maquina.dados.tokenParry ~= tokenParry or not entidade.Parent then
			return
		end
		maquina:DesativarParry()
		maquina.dados.pendingParryTimestamp = nil
		definirStatusBool(entidade, "ProntoAparar", false)
		Nucleo.SincronizarEstado(entidade)
	end)

	return true, nil
end

function AcoesCombate.ProcessarPararBloqueio(entidade: Model): (boolean, string?)
	local maquina = Nucleo.ObterMaquina(entidade)
	local sucesso, motivo = maquina:TentePararBloqueio()
	if not sucesso then
		return false, motivo
	end

	maquina.dados.tokenParry = (maquina.dados.tokenParry or 0) + 1
	definirStatusBool(entidade, "ProntoAparar", false)

	if maquina:ObterEstadoAcao() == "Nenhuma" then
		Nucleo.PararAnimacao(entidade)
	end
	Nucleo.SincronizarEstado(entidade)
	return true, nil
end

function AcoesCombate.ProcessarQuebrarDefesa(entidade: Model): (boolean, string?)
	local maquina = Nucleo.ObterMaquina(entidade)
	local sucesso, motivo = maquina:TenteQuebrarDefesa()
	if not sucesso then
		return false, motivo
	end

	definirWalkSpeed(entidade, "VelocidadeDefesaQuebrada", 3)
	Nucleo.TocarAnimacao(entidade, "DefesaQuebrada")
	return true, nil
end

-- =============================================================================
-- Postura e movimento.
-- =============================================================================

function AcoesCombate.ProcessarAgachar(entidade: Model): (boolean, string?)
	local maquina = Nucleo.ObterMaquina(entidade)
	local sucesso, motivo = maquina:TenteAgachar()
	if not sucesso then
		return false, motivo
	end
	definirWalkSpeed(entidade, "VelocidadeAgachando", 9)
	return true, nil
end

function AcoesCombate.ProcessarLevantar(entidade: Model): (boolean, string?)
	local maquina = Nucleo.ObterMaquina(entidade)
	local sucesso, motivo = maquina:TenteLevantar()
	if not sucesso then
		return false, motivo
	end
	definirWalkSpeed(entidade, "VelocidadeAndando", 14)
	return true, nil
end

function AcoesCombate.ProcessarPular(entidade: Model): (boolean, string?)
	local maquina = Nucleo.ObterMaquina(entidade)
	return maquina:TentePular()
end

function AcoesCombate.ProcessarAterrissar(entidade: Model): boolean
	local maquina = Nucleo.ObterMaquina(entidade)
	local sucesso = maquina:TenteAterrissar()
	if sucesso then
		Nucleo.SincronizarEstado(entidade)
	end
	return sucesso
end

function AcoesCombate.ProcessarCorrer(entidade: Model): (boolean, string?)
	local maquina = Nucleo.ObterMaquina(entidade)
	local sucesso, motivo = maquina:TenteCorrer()

	if not sucesso then
		local estadoAcao = maquina.dados.estadoAcao
		local enfileiravel = motivo == "AcaoEmAndamento"
			or (
				motivo == "EstadoBloqueante"
				and (
					estadoAcao == MaquinaDeEstados.EstadoAcao.Equipando
					or estadoAcao == MaquinaDeEstados.EstadoAcao.Desequipando
					or estadoAcao == MaquinaDeEstados.EstadoAcao.Rolando
					or estadoAcao == MaquinaDeEstados.EstadoAcao.Dashando
				)
			)

		if enfileiravel then
			(maquina.dados :: any).correndoIntent = true
			DebugPrint(string.format("[Combate] %s: correr enfileirado (%s)", entidade.Name, tostring(estadoAcao)))
			return true, nil
		end
		return false, motivo
	end

	Nucleo.SincronizarEstado(entidade)
	return true, nil
end

function AcoesCombate.ProcessarPararCorrer(entidade: Model): (boolean, string?)
	local maquina = Nucleo.ObterMaquina(entidade)
	maquina:TentePararCorrer()
	maquina.dados.correndoIntent = nil
	Nucleo.SincronizarEstado(entidade)
	return true, nil
end

function AcoesCombate.ProcessarSincronizarMovimento(entidade: Model, novoEstado: string): boolean
	local maquina = Nucleo.ObterMaquina(entidade)
	local sucesso = maquina:DefinirEstadoMov(novoEstado)
	if sucesso then
		Nucleo.SincronizarEstado(entidade)
	end
	return sucesso
end

-- =============================================================================
-- Esquiva.
-- =============================================================================

local function iniciarEsquiva(
	entidade: Model,
	direcao: string,
	tentar: string,
	prefixoAnim: string,
	chaveVelocidade: string,
	statusNome: string
): (boolean, string?)
	local maquina = Nucleo.ObterMaquina(entidade)
	local estavaCorrendo = maquina.dados.correndo

	local sucesso, motivo = (maquina :: any)[tentar](maquina, direcao)
	if not sucesso then
		DebugPrint(string.format("[Combate] %s: %s FALHOU - %s", entidade.Name, prefixoAnim, motivo or "?"))
		return false, motivo
	end

	if estavaCorrendo then
		(maquina.dados :: any).correndoIntent = true
	end

	local velocidadeAnim = Modulo_Configuracoes.ObterConfiguracao(chaveVelocidade) or 1.0
	Nucleo.TocarAnimacao(entidade, prefixoAnim .. direcao, false, velocidadeAnim)
	definirStatusBool(entidade, statusNome, true)
	Nucleo.SincronizarEstado(entidade)

	return true, nil
end

local function terminarEsquiva(
	entidade: Model,
	estadoEsperado: string,
	completar: string,
	statusNome: string,
	motivoErro: string
): (boolean, string?)
	local maquina = Nucleo.ObterMaquina(entidade)
	if maquina.dados.estadoAcao ~= estadoEsperado then
		return false, motivoErro
	end

	(maquina :: any)[completar](maquina)
	definirStatusBool(entidade, statusNome, false)
	maquina.dados.correndoIntent = nil
	Nucleo.SincronizarEstado(entidade)
	return true, nil
end

function AcoesCombate.ProcessarRoll(entidade: Model, direcao: string): (boolean, string?)
	return iniciarEsquiva(entidade, direcao, "TenteRoll", "Roll", "VelocidadeAnimacaoRoll", "RollOn")
end

function AcoesCombate.ProcessarRollTerminou(entidade: Model): (boolean, string?)
	return terminarEsquiva(entidade, MaquinaDeEstados.EstadoAcao.Rolando, "CompletarRoll", "RollOn", "NaoEstaRolando")
end

function AcoesCombate.ProcessarRollEarlyCancel(entidade: Model): (boolean, string?)
	local maquina = Nucleo.ObterMaquina(entidade)
	if maquina:ObterEstadoAcao() == MaquinaDeEstados.EstadoAcao.Rolando then
		maquina:CompletarRoll()
		maquina.dados.correndoIntent = nil
		definirStatusBool(entidade, "RollOn", false)
		Nucleo.SincronizarEstado(entidade)
	end
	return true, nil
end

function AcoesCombate.ProcessarDash(entidade: Model, direcao: string): (boolean, string?)
	return iniciarEsquiva(entidade, direcao, "TenteDash", "Dash", "VelocidadeAnimacaoDash", "DashOn")
end

function AcoesCombate.ProcessarDashTerminou(entidade: Model): (boolean, string?)
	return terminarEsquiva(entidade, MaquinaDeEstados.EstadoAcao.Dashando, "CompletarDash", "DashOn", "NaoEstaDashando")
end

function AcoesCombate.ProcessarDashEarlyCancel(entidade: Model): (boolean, string?)
	local maquina = Nucleo.ObterMaquina(entidade)
	if maquina:ObterEstadoAcao() == MaquinaDeEstados.EstadoAcao.Dashando then
		maquina:CompletarDash()
		maquina.dados.correndoIntent = nil
		definirStatusBool(entidade, "DashOn", false)
		Nucleo.SincronizarEstado(entidade)
	end
	return true, nil
end

-- =============================================================================
-- Equipamento.
-- =============================================================================

function AcoesCombate.ProcessarEquipar(entidade: Model, modo: string): (boolean, string?)
	local maquina = Nucleo.ObterMaquina(entidade)
	local sucesso, motivo = maquina:TenteEquipar(modo)
	if not sucesso then
		DebugPrint(string.format("[Combate] %s: Equipar '%s' FALHOU - %s", entidade.Name, modo, motivo or "?"))
		return false, motivo
	end

	maquina:DefinirModo(modo)
	Nucleo.TocarAnimacao(entidade, "Equipar")
	return true, nil
end

function AcoesCombate.ProcessarDesequipar(entidade: Model): (boolean, string?)
	local maquina = Nucleo.ObterMaquina(entidade)
	local sucesso, motivo = maquina:TenteDesequipar()
	if not sucesso then
		return false, motivo
	end

	Nucleo.TocarAnimacao(entidade, "Desequipar")
	task.delay(0.1, function()
		if not entidade.Parent then
			return
		end
		maquina:DefinirModo("Base")
		Nucleo.SincronizarEstado(entidade)
	end)
	return true, nil
end

function AcoesCombate.ProcessarShiftLock(entidade: Model, ativo: boolean)
	local maquina = Nucleo.ObterMaquina(entidade)
	maquina:DefinirShiftLock(ativo)
	definirStatusBool(entidade, "ShiftLockOn", ativo)
end

function AcoesCombate.ProcessarAnimacaoEquipTerminou(entidade: Model)
	local maquina = Nucleo.ObterMaquinaExistente(entidade)
	if not maquina then
		return
	end
	local estadoAcao = maquina:ObterEstadoAcao()
	if
		estadoAcao == MaquinaDeEstados.EstadoAcao.Equipando
		or estadoAcao == MaquinaDeEstados.EstadoAcao.Desequipando
	then
		maquina:CompletarAcao()
		Nucleo.SincronizarEstado(entidade)
	end
end

function AcoesCombate.ProcessarAcaoAnimacaoTerminou(entidade: Model, nomeAcao: string)
	local maquina = Nucleo.ObterMaquinaExistente(entidade)
	if not maquina or maquina:ObterEstadoAcao() ~= nomeAcao then
		return
	end
	Nucleo.CancelarTimeoutAtaque(maquina)
	maquina:CompletarAcao()
	definirWalkSpeed(entidade, "VelocidadeAndando", 14)
	Nucleo.SincronizarEstado(entidade)
end

return AcoesCombate
