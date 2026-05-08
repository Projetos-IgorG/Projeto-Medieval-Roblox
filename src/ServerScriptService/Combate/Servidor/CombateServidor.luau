--!strict

--[[
    Script: CombateServidor.luau
    Caminho: src/ServerScriptService/Combate/Servidor
    Responsabilidade: Autoriza, valida e aplica acoes de combate recebidas dos clientes.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao roda sozinho nem cria fluxo de jogo por conta propria; depende dos scripts que importam este modulo.
    Funcoes principais: ObterMaquina, RemoverMaquina, _SincronizarEstado, _TocarAnimacao, _AplicarImpulsoAtacante, _AplicarKnockback
]]
local DEBUG_ENABLED = false

local function DebugPrint(...)
	if DEBUG_ENABLED then
		print(...)
	end
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Combate = ReplicatedStorage:WaitForChild("Combate")
local DominioCombate = Combate:WaitForChild("Dominio")

local Modulo_Configuracoes = require(Combate:WaitForChild("Configuracoes"):WaitForChild("ConfigCombate"))
local Modulo_Dano = require(DominioCombate:WaitForChild("DanoCombate"))
local Modulo_Impulso = require(DominioCombate:WaitForChild("ImpulsoCombate"))
local Modulo_Knockback = require(DominioCombate:WaitForChild("KnockbackCombate"))
local MaquinaDeEstados = require(ReplicatedStorage:WaitForChild("Jogador"):WaitForChild("Estado"):WaitForChild("MaquinaEstadosJogador"))

local ControladorCombate = {}

local maquinasDeEstado = {}

local Remotos = ReplicatedStorage:WaitForChild("Remotos")
local TentarAcao = Remotos:WaitForChild("TentarAcao")
local MudarShiftLock = Remotos:WaitForChild("MudarShiftLock")
local SincronizarEstado = Remotos:WaitForChild("SincronizarEstado")
local TocarAnimacao = Remotos:WaitForChild("TocarAnimacao")
local EquipAnimacaoTerminou = Remotos:WaitForChild("EquipAnimacaoTerminou")

local function DeterminarTipoAtaque(indice: number): string
	if indice >= 4 then
		return "AtaqueLeveFinal"
	end
	return "AtaqueLeve"
end

local function EhGolpeFinal(indice: number): boolean
	return indice >= 4
end

local MAO_PARA_SLOT = {
	Right = "RightArm",
	Left = "LeftArm",
}

local function ObterToolPorMao(character: Model, mao: string): Tool?
	local slotName = MAO_PARA_SLOT[mao]
	if not slotName then
		return nil
	end

	local equipamento = character:FindFirstChild("Equipamento")
	if not equipamento then
		return nil
	end

	local bracos = equipamento:FindFirstChild("Bracos")
	if not bracos then
		return nil
	end

	local slotOV = bracos:FindFirstChild(slotName) :: ObjectValue?
	if slotOV and slotOV.Value and slotOV.Value:IsA("Tool") then
		return slotOV.Value :: Tool
	end

	local toolNaMao = character:FindFirstChildOfClass("Tool")
	if toolNaMao then
		return toolNaMao
	end

	return nil
end

function ControladorCombate.ObterMaquina(entidade: Model)
	if not maquinasDeEstado[entidade] then
		maquinasDeEstado[entidade] = MaquinaDeEstados.Novo(entidade)

		maquinasDeEstado[entidade]:AoMudarEstadoAcao(function(_novo, _anterior)
			ControladorCombate._SincronizarEstado(entidade)
		end)

		maquinasDeEstado[entidade]:AoMudarEstadoMov(function(_novo, _anterior)
			ControladorCombate._SincronizarEstado(entidade)
		end)

		maquinasDeEstado[entidade]:AoMudarModo(function(_novo, _anterior)
			ControladorCombate._SincronizarEstado(entidade)
		end)
	end

	return maquinasDeEstado[entidade]
end

function ControladorCombate.RemoverMaquina(entidade: Model)
	maquinasDeEstado[entidade] = nil
end

function ControladorCombate._SincronizarEstado(entidade: Model)
	local maquina = maquinasDeEstado[entidade]
	if not maquina then
		return
	end

	local dados = maquina:ObterDados()

	local status = entidade:FindFirstChild("Status")
	if status then
		local function atualizarValor(nome, valor)
			local obj = status:FindFirstChild(nome)
			if
				obj
				and (obj:IsA("IntValue") or obj:IsA("NumberValue") or obj:IsA("StringValue") or obj:IsA("BoolValue"))
			then
				(obj :: any).Value = valor
			end
		end

		atualizarValor("estadoAcao", dados.estadoAcao)
		atualizarValor("BloqueandoOn", dados.bloqueando)
		atualizarValor("ProntoAparar", dados.prontoParaAparar)
		atualizarValor("StunadoOn", dados.stunado)
		atualizarValor("DashOn", dados.dashando)
	end

	DebugPrint(
		string.format(
			"[Estado] %s: Mov=%s, Acao=%s, Modo=%s",
			entidade.Name,
			dados.estadoMov,
			dados.estadoAcao,
			dados.modoAnimacao
		)
	)

	local humanoid = entidade:FindFirstChildOfClass("Humanoid")
	if humanoid then
		if dados.estadoAcao == "Nenhuma" then

			if maquina.dados.correndoIntent then
				maquina.dados.correndoIntent = nil
				maquina.dados.correndo = true

			end

			if dados.agachado then
				humanoid.WalkSpeed = Modulo_Configuracoes.ObterConfiguracao("VelocidadeAgachando") or 9
			elseif dados.bloqueando then
				humanoid.WalkSpeed = Modulo_Configuracoes.ObterConfiguracao("VelocidadeBloqueando") or 6
			end

		end
	end

	SincronizarEstado:FireAllClients(entidade, dados)
end

function ControladorCombate._TocarAnimacao(entidade: Model, nomeAnimacao: string, loop: boolean?, velocidade: number?)
	local maquina = maquinasDeEstado[entidade]
	if not maquina then
		return
	end

	local modo = maquina:ObterModo()
	local animId = Modulo_Configuracoes.ObterAnimacao(modo, nomeAnimacao)

	if animId then
		TocarAnimacao:FireAllClients(entidade, animId, nomeAnimacao, loop or false, velocidade or 1)
	end
end

function ControladorCombate._AplicarImpulsoAtacante(entidade: Model, tipoAtaque: string)
	local maquina = maquinasDeEstado[entidade]
	if not maquina then
		return
	end

	local modo = maquina:ObterModo()
	local resultado = Modulo_Impulso.AplicarImpulso(entidade, modo, tipoAtaque)

	if not resultado.sucesso then
		DebugPrint("[Combate] Falha ao aplicar impulso: " .. tostring(resultado.erro))
	end
end

function ControladorCombate._AplicarKnockback(alvo: Model, atacante: Model, tipoAtaque: string)
	local maquina = maquinasDeEstado[atacante]
	if not maquina then
		return
	end

	local modo = maquina:ObterModo()

	local resultado = Modulo_Knockback.AplicarKnockback(atacante, alvo, modo, tipoAtaque)

	if resultado.sucesso then
		DebugPrint(
			string.format(
				"[Combate] Knockback aplicado via %s: %.1f",
				resultado.metodo or "?",
				resultado.magnitudeAplicada or 0
			)
		)
	else

		if resultado.erro and not resultado.erro:match("não permite") then
			DebugPrint("[Combate] Falha ao aplicar knockback: " .. tostring(resultado.erro))
		end
	end
end

function ControladorCombate._CriarHitbox(_atacante: Model, _tipoAtaque: string, _cframeCliente: CFrame?)
	warn("[ControladorCombate] _CriarHitbox está deprecado. Use ShapecastHitbox no cliente.")
	return {}
end

function ControladorCombate._ProcessarHit(atacante: Model, alvo: Model, tipoAtaque: string, danoOverride: number?)
	local maquinaAtacante = maquinasDeEstado[atacante]
	local maquinaAlvo = ControladorCombate.ObterMaquina(alvo)

	if not maquinaAtacante or not maquinaAlvo then
		return
	end

	-- ===== PARRY (defensor pronto para aparar) =====
	if maquinaAlvo:EstaProntoParaAparar() and maquinaAlvo:EstaBloqueando() then

		local tempoStun = Modulo_Configuracoes.ObterConfiguracao("TempoStunAparado") or 0.7
		local tempoAparando = Modulo_Configuracoes.ObterConfiguracao("TempoAparando") or tempoStun

		ControladorCombate._TocarAnimacao(alvo, "Aparar")
		ControladorCombate._TocarAnimacao(atacante, "Aparado")

		-- Atacante entra em estado APARADO (anim correta) em vez de Stunado generico.
		if maquinaAtacante.AplicarAparado then
			maquinaAtacante:AplicarAparado(tempoStun)
		else
			maquinaAtacante:EntrarStun(tempoStun)
		end
		if maquinaAlvo.AplicarAparando then
			maquinaAlvo:AplicarAparando(tempoAparando)
		end

		-- Reseta cooldown de parry do defensor: parry bem sucedido permite aparar
		-- o proximo ataque imediatamente. (REQ: 'Aparar resetar o proprio cooldown')
		maquinaAlvo.dados.ultimoParry = 0

		-- Impulso especifico de parry: metade do impulso do final de combo.
		local resultadoImpulso = Modulo_Impulso.AplicarImpulsoParry(alvo, atacante)
		if not resultadoImpulso.sucesso then
			DebugPrint("[Combate] Falha ao aplicar impulso de parry: " .. tostring(resultadoImpulso.erro))
		end

		DebugPrint(string.format("[Combate] %s APAROU ataque de %s!", alvo.Name, atacante.Name))
		return
	end

	-- ===== BLOQUEIO (sem parry) =====
	if maquinaAlvo:EstaBloqueando() then

		if tipoAtaque == "AtaquePesado" or tipoAtaque == "AtaqueLeveFinal" then
			local tempoStun = Modulo_Configuracoes.ObterConfiguracao("TempoStunPesado") or 0.6

			maquinaAlvo:QuebrarDefesa(tempoStun)
			ControladorCombate._TocarAnimacao(alvo, "DefesaQuebrada")
			ControladorCombate._TocarAnimacao(atacante, "AtaquePesado")

			-- Knockback no defensor (defesa quebrada).
			ControladorCombate._AplicarKnockback(alvo, atacante, tipoAtaque)

			DebugPrint(string.format("[Combate] %s teve a defesa QUEBRADA por %s!", alvo.Name, atacante.Name))
			return
		else

			-- Ataque leve absorvido: nao tira vida, mas cada lado sente um leve impacto.
			-- Defensor recua um pouco, atacante recua um pouco (feedback de hit).
			local modoAtacante = maquinaAtacante:ObterModo()
			local modoAlvo = maquinaAlvo:ObterModo()
			Modulo_Knockback.AplicarKnockback(atacante, alvo, modoAtacante, "AtaqueLeve")
			Modulo_Knockback.AplicarKnockback(alvo, atacante, modoAlvo, "AtaqueLeve")
			DebugPrint(string.format("[Combate] %s bloqueou ataque de %s", alvo.Name, atacante.Name))
			return
		end
	end

	-- ===== HIT NORMAL =====
	local resultado
	if danoOverride then

		resultado = Modulo_Dano.AplicarDanoComValor(atacante, alvo, tipoAtaque, danoOverride)
	else
		local characterAtacante = atacante
		local tool = characterAtacante:FindFirstChildOfClass("Tool")
		if not tool then
			DebugPrint("[Combate] Sem tool para aplicar dano")
			return
		end
		resultado = Modulo_Dano.AplicarDano(tool, atacante, alvo, tipoAtaque)
	end

	if resultado.sucesso then
		local danoAplicado = resultado.danoAplicado or 0
		DebugPrint(string.format("[Combate] Dano aplicado: %.1f em %s", danoAplicado, alvo.Name))

		local tempoStun
		if tipoAtaque == "AtaquePesado" then
			tempoStun = Modulo_Configuracoes.ObterConfiguracao("TempoStunPesado")
		else
			tempoStun = Modulo_Configuracoes.ObterConfiguracao("TempoStunLeve")
		end

		maquinaAlvo:EntrarStun(tempoStun or 0.3)
		ControladorCombate._TocarAnimacao(alvo, "Stunado")

		ControladorCombate._AplicarKnockback(alvo, atacante, tipoAtaque)
	else
		DebugPrint("[Combate] Falha ao aplicar dano: " .. tostring(resultado.erro))
	end
end

function ControladorCombate.ProcessarAtacarLeveEmPe(entidade: Model): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, tipoAtaque, motivo = maquina:TenteAtacarLeveEmPe()

	if not sucesso then

		if motivo == "ComboContinuado" then
			DebugPrint(string.format("[Combate] %s: Combo input registrado", entidade.Name))
			return true, nil
		end

		DebugPrint(string.format("[Combate] %s: AtacarLeveEmPe FALHOU - %s", entidade.Name, motivo or "?"))
		return false, motivo
	end

	if tipoAtaque then
		DebugPrint(string.format("[Combate] %s: AtacarLeveEmPe OK - tipo=%s", entidade.Name, tipoAtaque))

		ControladorCombate._TocarAnimacao(entidade, tipoAtaque)

		ControladorCombate._AplicarImpulsoAtacante(entidade, tipoAtaque)

		local humanoid = entidade:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local velBloq = Modulo_Configuracoes.ObterConfiguracao("VelocidadeBloqueando") or 6
			local velocidadeAtaque = velBloq * 1.5
			humanoid.WalkSpeed = velocidadeAtaque
		end
	end

	return true, tipoAtaque
end

function ControladorCombate.ProcessarComboHitbox(entidade: Model, dados: any): (boolean, string?)
	local indiceGolpe = typeof(dados) == "table" and dados.indice or (tonumber(dados) or 0)

	local maquina = ControladorCombate.ObterMaquina(entidade)

	if maquina:ObterEstadoAcao() ~= "AtacandoLeve" then
		DebugPrint(string.format("[Combate] %s: ComboHitbox ignorado - não está atacando", entidade.Name))
		return false, "NaoAtacando"
	end

	local tipoAtaque = DeterminarTipoAtaque(indiceGolpe)

	DebugPrint(string.format("[Combate] %s: ComboHitbox golpe %d - tipo=%s", entidade.Name, indiceGolpe, tipoAtaque))

	maquina:AvancarGolpeCombo(indiceGolpe)

	ControladorCombate._AplicarImpulsoAtacante(entidade, tipoAtaque)

	if EhGolpeFinal(indiceGolpe) then
		local tempoFinal = Modulo_Configuracoes.ObterConfiguracao("JanelaCancelamentoComboFinal") or 0.6
		task.delay(tempoFinal, function()
			if maquina:ObterEstadoAcao() == "AtacandoLeve" then
				maquina:CompletarAcao()
				ControladorCombate._SincronizarEstado(entidade)
			end
		end)
	end

	return true, tipoAtaque
end

function ControladorCombate.ProcessarComboContinuado(entidade: Model, proximoIndice: number): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	if maquina:ObterEstadoAcao() ~= "AtacandoLeve" then
		return false, "NaoAtacando"
	end

	maquina:DesativarJanelaCombo()
	maquina.dados.ultimaContinuacaoCombo = tick()

	DebugPrint(string.format("[Combate] %s: Combo continuado para golpe %d", entidade.Name, proximoIndice))

	return true, nil
end

function ControladorCombate.ProcessarComboTerminou(entidade: Model)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	if maquina:ObterEstadoAcao() == "AtacandoLeve" then
		maquina:CompletarAcao()
		ControladorCombate._SincronizarEstado(entidade)

		DebugPrint(string.format("[Combate] %s: Combo terminado", entidade.Name))
	end

	return true, nil
end

function ControladorCombate.ProcessarComboEarlyCancel(entidade: Model)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	if maquina:ObterEstadoAcao() == "AtacandoLeve" then
		maquina:CompletarAcao()

		local humanoid = entidade:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = Modulo_Configuracoes.ObterConfiguracao("VelocidadeAndando") or 14
		end

		ControladorCombate._SincronizarEstado(entidade)

		DebugPrint(string.format("[Combate] %s: Combo early cancel executado", entidade.Name))
	end

	return true, nil
end

function ControladorCombate.ProcessarHeavyAttackEarlyCancel(entidade: Model)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local estadoAcao = maquina:ObterEstadoAcao()
	if estadoAcao == "SoltandoPesado" or estadoAcao == "AtaquePesado" then
		maquina:CompletarAcao()

		local humanoid = entidade:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = Modulo_Configuracoes.ObterConfiguracao("VelocidadeAndando") or 14
		end

		ControladorCombate._SincronizarEstado(entidade)

		DebugPrint(string.format("[Combate] %s: Heavy attack early cancel executado", entidade.Name))
	end

	return true, nil
end

function ControladorCombate.ProcessarDashEarlyCancel(entidade: Model)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	if maquina:ObterEstadoAcao() == MaquinaDeEstados.EstadoAcao.Dashando then

		maquina:CompletarDash()

		maquina.dados.correndoIntent = nil

		local status = entidade:FindFirstChild("Status")
		if status then
			local dashOn = status:FindFirstChild("DashOn")
			if dashOn and dashOn:IsA("BoolValue") then
				dashOn.Value = false
			end
		end

		ControladorCombate._SincronizarEstado(entidade)

		DebugPrint(string.format("[Combate] %s: Dash early cancel executado", entidade.Name))
	end

	return true, nil
end

function ControladorCombate.ProcessarCancelarAtaquePorDefesa(entidade: Model, tipoAtaque: string)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local estadoAcao = maquina:ObterEstadoAcao()

	local podeCancel = (tipoAtaque == "AtaqueLeve" and estadoAcao == "AtacandoLeve")
		or (tipoAtaque == "CarregandoPesado"
			and (estadoAcao == "CarregandoPesado" or estadoAcao == "SoltandoPesado" or estadoAcao == "AtaquePesado"))

	if podeCancel then
		maquina:CompletarAcao()

		local humanoid = entidade:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = Modulo_Configuracoes.ObterConfiguracao("VelocidadeAndando") or 14
		end

		ControladorCombate._SincronizarEstado(entidade)

		DebugPrint(string.format("[Combate] %s: Ataque '%s' cancelado por defesa", entidade.Name, tipoAtaque))
	end

	return true, nil
end

function ControladorCombate.ProcessarAtacarLeveAgachado(entidade: Model)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, tipoAtaque, motivo = maquina:TenteAtacarLeveAgachado()

	if not sucesso then
		return false, motivo
	end

	tipoAtaque = tipoAtaque or "AtaqueLeve"

	ControladorCombate._TocarAnimacao(entidade, tipoAtaque)
	ControladorCombate._AplicarImpulsoAtacante(entidade, tipoAtaque)

	local humanoid = entidade:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local velBloq = Modulo_Configuracoes.ObterConfiguracao("VelocidadeBloqueando") or 6
		humanoid.WalkSpeed = velBloq * 1.5
	end

	return true, nil
end

function ControladorCombate.ProcessarCarregarPesado(entidade: Model)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, motivo = maquina:TenteCarregarPesado()

	if not sucesso then

		local player = Players:GetPlayerFromCharacter(entidade)
		if player then
			local rem = ReplicatedStorage:FindFirstChild("Remotos")
			if rem and rem:FindFirstChild("AcaoRejeitada") then
				rem:FindFirstChild("AcaoRejeitada"):FireClient(player, "CarregarPesado", motivo)
			end
		end
		return false, motivo
	end

	local humanoid = entidade:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local velBloq = Modulo_Configuracoes.ObterConfiguracao("VelocidadeBloqueando") or 6
		humanoid.WalkSpeed = velBloq * 1.5
	end

	local velocidadeCarregar = Modulo_Configuracoes.ObterConfiguracao("VelocidadeCarregandoPesado") or 1.1
	ControladorCombate._TocarAnimacao(entidade, "AtaquePesado", false, velocidadeCarregar)

	return true, nil
end

function ControladorCombate.ProcessarSoltarPesado(entidade: Model)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, motivo = maquina:TenteSoltarPesado()

	if not sucesso then

		local player = Players:GetPlayerFromCharacter(entidade)
		if player then
			local rem = ReplicatedStorage:FindFirstChild("Remotos")
			if rem and rem:FindFirstChild("AcaoRejeitada") then
				rem:FindFirstChild("AcaoRejeitada"):FireClient(player, "SoltarPesado", motivo)
			end
		end
		return false, motivo
	end

	local humanoid = entidade:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local velBloq = Modulo_Configuracoes.ObterConfiguracao("VelocidadeBloqueando") or 6
		humanoid.WalkSpeed = velBloq * 1.5
	end

	ControladorCombate._AplicarImpulsoAtacante(entidade, "AtaquePesado")

	ControladorCombate._SincronizarEstado(entidade)

	return true, nil
end

function ControladorCombate.ProcessarHeavyAttackHitbox(entidade: Model, _dados: any?): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	if maquina.dados.estadoAcao ~= "SoltandoPesado" then
		DebugPrint(
			string.format(
				"[Combate] %s: HeavyAttackHitbox FALHOU - não está em SoltandoPesado (está em %s)",
				entidade.Name,
				maquina.dados.estadoAcao
			)
		)
		return false, "EstadoInvalido"
	end

	local sucesso, motivo = maquina:TenteExecutarPesado()
	if not sucesso then
		DebugPrint(
			string.format(
				"[Combate] %s: HeavyAttackHitbox FALHOU - TenteExecutarPesado: %s",
				entidade.Name,
				motivo or "?"
			)
		)
		return false, motivo
	end

	DebugPrint(
		string.format("[Combate] %s: HeavyAttackHitbox - estado mudou para AtaquePesado", entidade.Name)
	)

	ControladorCombate._SincronizarEstado(entidade)

	return true, nil
end

function ControladorCombate.ProcessarBloquear(entidade: Model, shiftLockAtivo: boolean?): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, motivo = maquina:TenteBloquear(shiftLockAtivo)

	if not sucesso then
		DebugPrint(string.format("[Combate] %s: Bloquear FALHOU - %s", entidade.Name, motivo or "?"))
		return false, motivo
	end

	DebugPrint(string.format("[Combate] %s: Bloquear OK", entidade.Name))

	local humanoid = entidade:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Modulo_Configuracoes.ObterConfiguracao("VelocidadeBloqueando") or 6
	end

	ControladorCombate._TocarAnimacao(entidade, "Defesa", true)

	local status = entidade:FindFirstChild("Status")
	local agora = tick()
	local cooldownParry = Modulo_Configuracoes.ObterConfiguracao("CooldownParry") or 2.4
	local podeParry = (agora - (maquina.dados.ultimoParry or 0)) >= cooldownParry

	if podeParry then
		maquina.dados.prontoParaAparar = true
		maquina.dados.ultimoParry = agora
		if status then
			local prontoAparar = status:FindFirstChild("ProntoAparar")
			if prontoAparar and prontoAparar:IsA("BoolValue") then
				prontoAparar.Value = true
			end
		end
		ControladorCombate._SincronizarEstado(entidade)

		task.delay(Modulo_Configuracoes.ObterConfiguracao("JanelaParry") or 0.2, function()
			maquina:DesativarParry()
			if status then
				local prontoAparar = status:FindFirstChild("ProntoAparar")
				if prontoAparar and prontoAparar:IsA("BoolValue") then
					prontoAparar.Value = false
				end
			end
			ControladorCombate._SincronizarEstado(entidade)
		end)
	else
		maquina.dados.prontoParaAparar = false
		if status then
			local prontoAparar = status:FindFirstChild("ProntoAparar")
			if prontoAparar and prontoAparar:IsA("BoolValue") then
				prontoAparar.Value = false
			end
		end
		ControladorCombate._SincronizarEstado(entidade)
	end

	return true, nil
end

function ControladorCombate.ProcessarPararBloqueio(entidade: Model): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, motivo = maquina:TentePararBloqueio()

	if not sucesso then
		return false, motivo
	end

	local status = entidade:FindFirstChild("Status")
	if status then
		local prontoAparar = status:FindFirstChild("ProntoAparar")
		if prontoAparar and prontoAparar:IsA("BoolValue") then
			prontoAparar.Value = false
		end
	end

	ControladorCombate._SincronizarEstado(entidade)

	return true, nil
end

function ControladorCombate.ProcessarQuebrarDefesa(entidade: Model): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, motivo = maquina:TenteQuebrarDefesa()

	if not sucesso then
		return false, motivo
	end

	local humanoid = entidade:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Modulo_Configuracoes.ObterConfiguracao("VelocidadeDefesaQuebrada") or 3
	end

	ControladorCombate._TocarAnimacao(entidade, "DefesaQuebrada")

	return true, nil
end

function ControladorCombate.ProcessarAgachar(entidade: Model): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, motivo = maquina:TenteAgachar()

	if not sucesso then
		DebugPrint(string.format("[Combate] %s: Agachar FALHOU - %s", entidade.Name, motivo or "?"))
		return false, motivo
	end

	DebugPrint(string.format("[Combate] %s: Agachar OK", entidade.Name))

	local humanoid = entidade:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Modulo_Configuracoes.ObterConfiguracao("VelocidadeAgachando") or 9
	end

	return true, nil
end

function ControladorCombate.ProcessarLevantar(entidade: Model): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, motivo = maquina:TenteLevantar()

	if not sucesso then
		DebugPrint(string.format("[Combate] %s: Levantar FALHOU - %s", entidade.Name, motivo or "?"))
		return false, motivo
	end

	DebugPrint(string.format("[Combate] %s: Levantar OK", entidade.Name))

	local humanoid = entidade:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Modulo_Configuracoes.ObterConfiguracao("VelocidadeAndando") or 14
	end

	return true, nil
end

function ControladorCombate.ProcessarPular(entidade: Model)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, motivo = maquina:TentePular()

	if not sucesso then
		return false, motivo
	end

	return true, nil
end

function ControladorCombate.ProcessarEquipar(entidade: Model, modo: string): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, motivo = maquina:TenteEquipar(modo)

	if not sucesso then
		DebugPrint(string.format("[Combate] %s: Equipar '%s' FALHOU - %s", entidade.Name, modo, motivo or "?"))
		return false, motivo
	end

	DebugPrint(string.format("[Combate] %s: Equipar '%s' OK", entidade.Name, modo))

	maquina:DefinirModo(modo)

	ControladorCombate._TocarAnimacao(entidade, "Equipar")

	return true, nil
end

function ControladorCombate.ProcessarDesequipar(entidade: Model)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, motivo = maquina:TenteDesequipar()

	if not sucesso then
		return false, motivo
	end

	ControladorCombate._TocarAnimacao(entidade, "Desequipar")

	task.delay(0.1, function()
		maquina:DefinirModo("Base")
		ControladorCombate._SincronizarEstado(entidade)
	end)

	return true, nil
end

function ControladorCombate.ProcessarShiftLock(entidade: Model, ativo: boolean)
	local maquina = ControladorCombate.ObterMaquina(entidade)
	maquina:DefinirShiftLock(ativo)

	local status = entidade:FindFirstChild("Status")
	if status then
		local shiftLockValue = status:FindFirstChild("ShiftLockOn")
		if shiftLockValue and shiftLockValue:IsA("BoolValue") then
			shiftLockValue.Value = ativo
		end
	end
end

function ControladorCombate.ProcessarCorrer(entidade: Model): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, motivo = maquina:TenteCorrer()

	if not sucesso then
		DebugPrint(string.format("[Combate] %s: Correr FALHOU - %s", entidade.Name, motivo or "?"))

		if motivo == "AcaoEmAndamento" then
			(maquina.dados :: any).correndoIntent = true
			DebugPrint(
				string.format("[Combate] %s: Pedido de correr enfileirado enquanto ação em andamento", entidade.Name)
			)
			return true, nil
		end
		if motivo == "EstadoBloqueante" then
			local estadoAcao = maquina.dados.estadoAcao
			if
				estadoAcao == MaquinaDeEstados.EstadoAcao.Equipando
				or estadoAcao == MaquinaDeEstados.EstadoAcao.Desequipando
				or estadoAcao == MaquinaDeEstados.EstadoAcao.Dashando
			then
				(maquina.dados :: any).correndoIntent = true
				DebugPrint(
					string.format("[Combate] %s: Pedido de correr enfileirado durante %s", entidade.Name, estadoAcao)
				)
				return true, nil
			end
		end
		return false, motivo
	end

	DebugPrint(string.format("[Combate] %s: Correr OK", entidade.Name))

	ControladorCombate._SincronizarEstado(entidade)
	return true, nil
end

function ControladorCombate.ProcessarPararCorrer(entidade: Model)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local _sucesso = maquina:TentePararCorrer()

	DebugPrint(string.format("[Combate] %s: PararCorrer OK", entidade.Name))

	local humanoid = entidade:FindFirstChildOfClass("Humanoid")
	if humanoid then
		maquina.dados.correndoIntent = nil
	end

	ControladorCombate._SincronizarEstado(entidade)
	return true, nil
end

function ControladorCombate.ProcessarDash(entidade: Model, direcao: string): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local estavaCorrendo = maquina.dados.correndo

	local sucesso, motivo = maquina:TenteDash(direcao)

	if not sucesso then
		DebugPrint(string.format("[Combate] %s: Dash FALHOU - %s", entidade.Name, motivo or "?"))
		return false, motivo
	end

	DebugPrint(string.format("[Combate] %s: Dash OK - direção=%s", entidade.Name, direcao))

	if estavaCorrendo then
		(maquina.dados :: any).correndoIntent = true
	end

	local nomeAnimacao = "Dash" .. direcao
	local velocidadeAnim = Modulo_Configuracoes.ObterConfiguracao("VelocidadeAnimacaoDash") or 1.0
	ControladorCombate._TocarAnimacao(entidade, nomeAnimacao, false, velocidadeAnim)

	local status = entidade:FindFirstChild("Status")
	if status then
		local dashOn = status:FindFirstChild("DashOn")
		if dashOn and dashOn:IsA("BoolValue") then
			dashOn.Value = true
		end
	end

	ControladorCombate._SincronizarEstado(entidade)
	return true, nil
end

function ControladorCombate.ProcessarDashTerminou(entidade: Model): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	if maquina.dados.estadoAcao ~= MaquinaDeEstados.EstadoAcao.Dashando then
		return false, "NaoEstaDashando"
	end

	maquina:CompletarDash()

	DebugPrint(string.format("[Combate] %s: Dash TERMINOU", entidade.Name))

	local status = entidade:FindFirstChild("Status")
	if status then
		local dashOn = status:FindFirstChild("DashOn")
		if dashOn and dashOn:IsA("BoolValue") then
			dashOn.Value = false
		end
	end

	maquina.dados.correndoIntent = nil

	ControladorCombate._SincronizarEstado(entidade)
	return true, nil
end

function ControladorCombate.ProcessarAterrissar(entidade: Model)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso = maquina:TenteAterrissar()

	if sucesso then
		ControladorCombate._SincronizarEstado(entidade)
	end

	return sucesso
end

function ControladorCombate.ProcessarSincronizarMovimento(entidade: Model, novoEstado: string)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso = maquina:DefinirEstadoMov(novoEstado)

	if sucesso then
		ControladorCombate._SincronizarEstado(entidade)
	end

	return sucesso
end

function ControladorCombate.ProcessarHitboxAcerto(entidade: Model, dados: any): (boolean, string?)
	if typeof(dados) ~= "table" then
		return false, "DadosInvalidos"
	end

	local mao: string? = dados.mao
	local alvoInstance: any = dados.alvo
	local _cframeCliente: CFrame? = dados.cframe

	if not mao or (mao ~= "Right" and mao ~= "Left") then
		return false, "MaoInvalida"
	end

	if not alvoInstance or typeof(alvoInstance) ~= "Instance" or not alvoInstance:IsA("Model") then
		return false, "AlvoInvalido"
	end

	local alvo = alvoInstance :: Model

	if alvo == entidade then
		return false, "AutoHit"
	end

	local alvoHumanoid = alvo:FindFirstChildOfClass("Humanoid")
	if not alvoHumanoid or alvoHumanoid.Health <= 0 then
		return false, "AlvoMorto"
	end

	local maquina = ControladorCombate.ObterMaquina(entidade)

	local estadoAcao = maquina:ObterEstadoAcao()
	local emAtaque = estadoAcao == "AtacandoLeve"
		or estadoAcao == "AtaquePesado"
		or estadoAcao == "SoltandoPesado"
		or estadoAcao == "AtacandoLeveAgachado"

	if not emAtaque then
		DebugPrint(
			string.format("[Combate] %s: HitboxAcerto ignorado - não está atacando (estado=%s)", entidade.Name, estadoAcao)
		)
		return false, "NaoAtacando"
	end

	local hrpAtacante = entidade:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hrpAlvo = alvo:FindFirstChild("HumanoidRootPart") :: BasePart?

	if hrpAtacante and hrpAlvo then
		local alcanceMaximo = Modulo_Configuracoes.ObterConfiguracao("Alcance") or 8

		local distancia = (hrpAtacante.Position - hrpAlvo.Position).Magnitude
		if distancia > alcanceMaximo * 2 then
			DebugPrint(
				string.format(
					"[Combate] %s: HitboxAcerto rejeitado - distância %.1f > máximo %.1f",
					entidade.Name,
					distancia,
					alcanceMaximo * 2
				)
			)
			return false, "ForaDeAlcance"
		end
	end

	local tipoAtaque = "AtaqueLeve"
	if estadoAcao == "AtaquePesado" or estadoAcao == "SoltandoPesado" then
		tipoAtaque = "AtaquePesado"
	elseif estadoAcao == "AtacandoLeve" then

		local indiceCombo = maquina.dados.indiceCombo or 1
		tipoAtaque = DeterminarTipoAtaque(indiceCombo)
	end

	local modo = maquina:ObterModo()
	local configCombo = Modulo_Configuracoes.ObterConfiguracaoCombo(modo)
	local ehDivideDano = configCombo and configCombo.divideDano == true

	local tool = ObterToolPorMao(entidade, mao)
	if not tool then

		tool = entidade:FindFirstChildOfClass("Tool")
	end

	if not tool then
		DebugPrint(string.format("[Combate] %s: HitboxAcerto - sem tool para mao %s", entidade.Name, mao))
		return false, "SemTool"
	end

	local danoBase = Modulo_Dano.ObterDanoBase(tool)
	if not danoBase then
		return false, "SemDanoBase"
	end

	local danoOverride: number? = nil
	if ehDivideDano then
		danoOverride = danoBase / 2
	end

	ControladorCombate._ProcessarHit(entidade, alvo, tipoAtaque, danoOverride)

	DebugPrint(
		string.format(
			"[Combate] %s: HitboxAcerto processado - mao=%s, alvo=%s, tipo=%s",
			entidade.Name,
			mao,
			alvo.Name,
			tipoAtaque
		)
	)

	return true, tipoAtaque
end

local MapaAcoes = {
	AtacarLeveEmPe = ControladorCombate.ProcessarAtacarLeveEmPe,
	AtacarLeveAgachado = ControladorCombate.ProcessarAtacarLeveAgachado,
	CarregarPesado = ControladorCombate.ProcessarCarregarPesado,
	SoltarPesado = ControladorCombate.ProcessarSoltarPesado,
	HeavyAttackHitbox = ControladorCombate.ProcessarHeavyAttackHitbox,
	Bloquear = function(entidade, dados)

		local shiftLockAtivo = typeof(dados) == "table" and dados.shiftLock or nil
		return ControladorCombate.ProcessarBloquear(entidade, shiftLockAtivo)
	end,
	PararBloqueio = ControladorCombate.ProcessarPararBloqueio,
	QuebrarDefesa = ControladorCombate.ProcessarQuebrarDefesa,
	Agachar = ControladorCombate.ProcessarAgachar,
	Levantar = ControladorCombate.ProcessarLevantar,
	Pular = ControladorCombate.ProcessarPular,
	Correr = ControladorCombate.ProcessarCorrer,
	PararCorrer = ControladorCombate.ProcessarPararCorrer,
	Aterrissar = ControladorCombate.ProcessarAterrissar,
	Dash = function(entidade, dados)
		return ControladorCombate.ProcessarDash(entidade, dados)
	end,
	DashTerminou = ControladorCombate.ProcessarDashTerminou,
	SincronizarMovimento = function(entidade, dados)
		return ControladorCombate.ProcessarSincronizarMovimento(entidade, dados)
	end,
	Equipar = function(entidade, dados)
		return ControladorCombate.ProcessarEquipar(entidade, dados)
	end,
	Desequipar = ControladorCombate.ProcessarDesequipar,

	ComboHitbox = function(entidade, dados)

		return ControladorCombate.ProcessarComboHitbox(entidade, dados)
	end,
	ComboContinuado = function(entidade, dados)

		return ControladorCombate.ProcessarComboContinuado(entidade, dados)
	end,
	ComboTerminou = ControladorCombate.ProcessarComboTerminou,
	ComboEarlyCancel = ControladorCombate.ProcessarComboEarlyCancel,
	HeavyAttackEarlyCancel = ControladorCombate.ProcessarHeavyAttackEarlyCancel,
	DashEarlyCancel = ControladorCombate.ProcessarDashEarlyCancel,

	HitboxAcerto = function(entidade, dados)
		return ControladorCombate.ProcessarHitboxAcerto(entidade, dados)
	end,

	CancelarAtaquePorDefesa = function(entidade, dados)

		return ControladorCombate.ProcessarCancelarAtaquePorDefesa(entidade, dados)
	end,
}

function ControladorCombate.ProcessarAcao(entidade: Model, acao: string, dados: any?)
	local processador = MapaAcoes[acao]
	if not processador then
		warn("[ControladorCombate] Ação desconhecida: " .. acao)
		return false, "AcaoDesconhecida"
	end

	return processador(entidade, dados)
end

TentarAcao.OnServerEvent:Connect(function(player, acao, dados)
	local character = player.Character
	if not character then
		return
	end

	ControladorCombate.ProcessarAcao(character, acao, dados)
end)

MudarShiftLock.OnServerEvent:Connect(function(player, ativo)
	local character = player.Character
	if not character then
		return
	end

	ControladorCombate.ProcessarShiftLock(character, ativo)
end)

EquipAnimacaoTerminou.OnServerEvent:Connect(function(player)
	local character = player.Character
	if not character then
		return
	end

	local maquina = ControladorCombate.ObterMaquina(character)
	if not maquina then
		return
	end

	local estadoAcao = maquina:ObterEstadoAcao()
	if
		estadoAcao == MaquinaDeEstados.EstadoAcao.Equipando
		or estadoAcao == MaquinaDeEstados.EstadoAcao.Desequipando
	then
		DebugPrint(string.format("[Combate] %s: Animação de equip/desequip terminou", character.Name))
		maquina:CompletarAcao()
		ControladorCombate._SincronizarEstado(character)
	end
end)

local AcaoAnimacaoTerminou = Remotos:WaitForChild("AcaoAnimacaoTerminou")
AcaoAnimacaoTerminou.OnServerEvent:Connect(function(player, nomeAcao)
	local character = player.Character
	if not character then
		return
	end

	local maquina = ControladorCombate.ObterMaquina(character)
	if not maquina then
		return
	end

	local estadoAcao = maquina:ObterEstadoAcao()

	if estadoAcao == nomeAcao then
		DebugPrint(
			string.format(
				"[Combate] %s: Animação de AÇÃO '%s' terminou - completando ação",
				character.Name,
				nomeAcao or "(desconhecida)"
			)
		)
		maquina:CompletarAcao()

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = Modulo_Configuracoes.ObterConfiguracao("VelocidadeAndando") or 14
		end
		ControladorCombate._SincronizarEstado(character)
	else
		DebugPrint(
			string.format(
				"[Combate] %s: ignorando AcaoAnimacaoTerminou '%s' (estado atual é %s)",
				character.Name,
				tostring(nomeAcao),
				tostring(estadoAcao)
			)
		)
	end
end)

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)

		local status = character:WaitForChild("Status", 5)
		if not status then
			warn("[ControladorCombate] Status não encontrado para " .. player.Name)
		end

		local _maquina = ControladorCombate.ObterMaquina(character)

		task.defer(function()
			ControladorCombate._SincronizarEstado(character)
		end)

		local humanoid = character:FindFirstChild("Humanoid")
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.Died:Connect(function()
				local maquinaAtual = maquinasDeEstado[character]
				if maquinaAtual then
					maquinaAtual:AplicarMorte()
				end
			end)
		end
	end)

	player.CharacterRemoving:Connect(function(character)
		ControladorCombate.RemoverMaquina(character)
	end)
end)

for _, player in ipairs(Players:GetPlayers()) do
	if player.Character then

		local _status = player.Character:WaitForChild("Status", 5)
		ControladorCombate.ObterMaquina(player.Character)

		task.defer(function()
			ControladorCombate._SincronizarEstado(player.Character)
		end)
	end
end

DebugPrint("[ControladorCombate] Inicializado no servidor")

return ControladorCombate
