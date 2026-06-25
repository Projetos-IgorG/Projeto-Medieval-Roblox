--[[
    Script: Combo.luau
    Caminho: src/StarterPlayer/StarterCharacterScripts/Jogador/Estado/Modulos
    Responsabilidade: Estado de combo (M1), marcadores de animacao, janela de carga,
                      hit freeze, rewind solido, cancel por defesa e impulso de ataque.
    Uso: ModuleScript; inicializado pelo ControladorEstadoPersonagem via Inicializar(ctx).
    Nao faz: Nao reproduz animacoes diretamente; delega ao modulo Animacao.
    Funcoes principais: ProcessarCombo, ResetarComboState, MarcarContinuarCombo,
                        AplicarHitFreeze, AplicarRewindParteSolida, TentarFintar,
                        AplicarImpulsoAtaque, SoltouM1
]]

local RunService = game:GetService("RunService")

local Combo = {}

local ctx
local Animacao -- referencia cruzada

-- ═══════════════════════════════════════════════════════════════════
-- Estado
-- ═══════════════════════════════════════════════════════════════════

local comboState = {
	animacaoAtiva = nil :: AnimationTrack?,
	janelaAtiva = false,
	indiceAtual = 0,
	conexoesMarkers = {} :: { any },
	continuarCombo = false,
	pendingConsume = false,
	janelaTimer = nil :: thread?,
	token = 0,
	earlyCancelTimer = nil :: thread?,
	earlyCancelExecutado = false,
	tempoInicio = 0,
	conexaoMonitorReversao = nil :: RBXScriptConnection?,
	carregando = false,
	multiplicadorDano = 1.0,
	conexaoCarga = nil :: RBXScriptConnection?,
	tempoInicioCarga = nil :: number?,
	ultimoComboTerminou = nil :: number?,
	entrouEmCarga = false,
}

local fintaState = {
	ultimaFinta = 0,
	fintaPendente = false,
}

local hitFreezeState = {
	ativo = false,
	velocidadeOriginal = 1,
	timer = nil :: thread?,
}

local solidHitRewindState = {
	ativo = false,
	conexaoMonitor = nil :: RBXScriptConnection?,
	tempoAlvoRetorno = 0,
}

local ultimoTempoHitboxAtivou = 0
local tempoUltimoInputContinuacao = 0

local attackImpulseState = {
	connection = nil :: RBXScriptConnection?,
	endTime = 0,
}

-- ═══════════════════════════════════════════════════════════════════
-- Acessores
-- ═══════════════════════════════════════════════════════════════════

function Combo.ObterComboState()
	return comboState
end

function Combo.ObterMultiplicadorDano(): number
	return comboState.multiplicadorDano
end

-- ═══════════════════════════════════════════════════════════════════
-- Helpers internos
-- ═══════════════════════════════════════════════════════════════════

local function LimparConexaoCarga()
	if comboState.conexaoCarga then
		comboState.conexaoCarga:Disconnect()
		comboState.conexaoCarga = nil
	end
end

local function LimparConexoesMarkers()
	for _, conexao in ipairs(comboState.conexoesMarkers) do
		if conexao and conexao.Connected then
			conexao:Disconnect()
		end
	end
	comboState.conexoesMarkers = {}

	if comboState.janelaTimer then
		pcall(task.cancel, comboState.janelaTimer)
		comboState.janelaTimer = nil
	end

	if comboState.earlyCancelTimer then
		pcall(task.cancel, comboState.earlyCancelTimer)
		comboState.earlyCancelTimer = nil
	end

	if comboState.conexaoMonitorReversao then
		comboState.conexaoMonitorReversao:Disconnect()
		comboState.conexaoMonitorReversao = nil
	end
end

local function RestaurarEstadoPosAcao()
	if ctx.IsShiftHeld() then
		ctx.MovementFlags.isRunning = true
		ctx.EstadoAtual.correndo = true
	else
		ctx.MovementFlags.isRunning = false
		ctx.EstadoAtual.correndo = false
	end

	local isMoving = ctx.Humanoid.MoveDirection.Magnitude > 0.1
	local emCombate = (ctx.EstadoAtual.estadoAcao == "Atacando" or ctx.EstadoAtual.estadoAcao == "Defendendo")
	local podeCorrer = ctx.MovementFlags.isRunning and not emCombate

	if isMoving then
		ctx.EstadoAtual.estadoMov = podeCorrer and "Correndo" or "Andando"
	else
		ctx.EstadoAtual.estadoMov = "Parado"
	end
end

-- Reset unificado de comboState (corrige problema #8 - duplicação em 4 pontos)
local function ResetarComboState()
	LimparConexoesMarkers()
	LimparConexaoCarga()

	comboState.animacaoAtiva = nil
	comboState.janelaAtiva = false
	comboState.indiceAtual = 0
	comboState.continuarCombo = false
	comboState.pendingConsume = false
	comboState.token = 0
	comboState.earlyCancelExecutado = false
	comboState.tempoInicio = 0
	comboState.carregando = false
	comboState.multiplicadorDano = 1.0
	comboState.tempoInicioCarga = nil
end

-- Chamado por Animacao.PararAnimacaoAcao()
function Combo.LimparParaParadaAcao()
	if comboState.conexaoMonitorReversao then
		comboState.conexaoMonitorReversao:Disconnect()
		comboState.conexaoMonitorReversao = nil
	end

	if comboState.animacaoAtiva then
		LimparConexoesMarkers()
		comboState.animacaoAtiva = nil
		comboState.janelaAtiva = false
		comboState.indiceAtual = 0
		comboState.continuarCombo = false
		comboState.pendingConsume = false
		comboState.token = 0
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- Combo: término e continuação
-- ═══════════════════════════════════════════════════════════════════

local function OnComboAnimacaoTerminou()
	ctx.DebugPrint("[Combo] Combo animação terminou")

	ResetarComboState()
	ctx.GerenciadorHitboxCliente.PararTodas()

	comboState.ultimoComboTerminou = os.clock()

	ctx.EstadoAtual.estadoAcao = "Nenhuma"

	ctx.TentarAcao:FireServer("ComboTerminou")

	RestaurarEstadoPosAcao()

	local Movimento = ctx.Modulos.Movimento
	Movimento.AtualizarVelocidadeLocal()

	Animacao.AtualizarBaseIdle()
	Animacao.AtualizarAnimacaoMovimento()
end

local function IniciarMonitorCarga(track: AnimationTrack)
	LimparConexaoCarga()
	local janelaCarga = ctx.Modulo_Configuracoes.ObterConfiguracao("JanelaCargaLeve") or 0.25

	comboState.conexaoCarga = RunService.RenderStepped:Connect(function()
		if not track or not track.IsPlaying or not comboState.carregando then
			LimparConexaoCarga()
			return
		end

		local tempoCargaDecorrido = track.TimePosition - (comboState.tempoInicioCarga or 0)
		if tempoCargaDecorrido >= janelaCarga then
			comboState.carregando = false
			track:AdjustSpeed(1.0)
			comboState.multiplicadorDano = ctx.Modulo_Configuracoes.ObterConfiguracao("MultiplicadorDanoMaximoCarga") or 1.2
			LimparConexaoCarga()
			ctx.TentarAcao:FireServer("AjustarVelocidadeAnimacao", { velocidade = 1.0 })
			ctx.DebugPrint("[Combo] Carga máxima atingida - auto release")
		end
	end)
end

local function ContinuarComboEVerificarCarga(track: AnimationTrack)
	ultimoTempoHitboxAtivou = 0
	comboState.tempoInicioCarga = track.TimePosition
	comboState.carregando = false
	comboState.entrouEmCarga = false
	comboState.multiplicadorDano = 1.0
	LimparConexaoCarga()

	comboState.token = comboState.token + 1
	local myToken = comboState.token

	local tempoDecorrido = os.clock() - tempoUltimoInputContinuacao
	local threshold = 0.12
	local aindaSegurando = ctx.ClientBridge.EstaSegurandoM1 and ctx.ClientBridge.EstaSegurandoM1()

	if aindaSegurando and tempoDecorrido >= threshold then
		-- Se já passou tempo de hold check, começa carregando direto sem pulo de velocidade
		comboState.carregando = true
		comboState.entrouEmCarga = true
		comboState.tempoInicioCarga = track.TimePosition
		local velCarga = ctx.Modulo_Configuracoes.ObterConfiguracao("VelocidadeCargaAtaque") or 0.4
		track:AdjustSpeed(velCarga)
		IniciarMonitorCarga(track)
		ctx.TentarAcao:FireServer("AjustarVelocidadeAnimacao", { velocidade = velCarga })
		ctx.DebugPrint("[Combo] Combo continuado: carregando próximo golpe direto (hold detectado)")
	else
		-- Inicia normal e agenda hold check com o tempo restante
		track:AdjustSpeed(1.0)
		ctx.TentarAcao:FireServer("AjustarVelocidadeAnimacao", { velocidade = 1.0 })
		ctx.DebugPrint("[Combo] Combo continuado: golpe normal")

		local tempoRestante = math.max(0, threshold - tempoDecorrido)
		task.delay(tempoRestante, function()
			if comboState.token ~= myToken or not track or not track.IsPlaying then
				return
			end
			local aindaSegurandoDepois = ctx.ClientBridge.EstaSegurandoM1 and ctx.ClientBridge.EstaSegurandoM1()
			if aindaSegurandoDepois then
				comboState.carregando = true
				comboState.entrouEmCarga = true
				comboState.tempoInicioCarga = track.TimePosition
				local velCarga = ctx.Modulo_Configuracoes.ObterConfiguracao("VelocidadeCargaAtaque") or 0.4
				track:AdjustSpeed(velCarga)
				IniciarMonitorCarga(track)
				ctx.TentarAcao:FireServer("AjustarVelocidadeAnimacao", { velocidade = velCarga })
				ctx.DebugPrint("[Combo] Combo continuado: carregando próximo golpe após delay restante")
			end
		end)
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- Markers de combo
-- ═══════════════════════════════════════════════════════════════════

local function OnMarkerJanelaCombo(ehFinal: boolean)
	if not comboState.animacaoAtiva then
		return
	end

	comboState.indiceAtual = comboState.indiceAtual + 1

	comboState.token = comboState.token + 1
	local myToken = comboState.token

	comboState.janelaAtiva = true
	comboState.continuarCombo = false

	ctx.DebugPrint(
		string.format(
			"[Combo] Janela de combo ativada (golpe %d, final=%s)",
			comboState.indiceAtual,
			tostring(ehFinal)
		)
	)

	local combo = ctx.Modulo_Configuracoes.ObterConfiguracaoCombo(ctx.EstadoAtual.modoAnimacao)
	if not combo then
		return
	end

	comboState.animacaoAtiva:AdjustSpeed(combo.velocidadeJanela)
	ctx.TentarAcao:FireServer("AjustarVelocidadeAnimacao", { velocidade = combo.velocidadeJanela })

	if comboState.pendingConsume then
		ctx.DebugPrint("[Combo] Consumo antecipado de combo (pending antes da janela)")
		comboState.pendingConsume = false
		comboState.continuarCombo = true
		comboState.janelaAtiva = false

		if comboState.animacaoAtiva and comboState.animacaoAtiva.IsPlaying then
			ContinuarComboEVerificarCarga(comboState.animacaoAtiva)
		end

		ctx.TentarAcao:FireServer("ComboContinuado", comboState.indiceAtual + 1)
		return
	end

	comboState.janelaTimer = task.delay(combo.janelaCombo, function()
		if myToken ~= comboState.token then
			return
		end

		if not comboState.janelaAtiva then
			return
		end

		if comboState.continuarCombo then
			ctx.DebugPrint("[Combo] Combo continuando - velocidade restaurada")
			comboState.janelaAtiva = false
			comboState.continuarCombo = false

			if comboState.animacaoAtiva and comboState.animacaoAtiva.IsPlaying then
				ContinuarComboEVerificarCarga(comboState.animacaoAtiva)
			end

			ctx.TentarAcao:FireServer("ComboContinuado", comboState.indiceAtual + 1)
		else
			ctx.DebugPrint("[Combo] Janela expirou - combo terminando")
			comboState.janelaAtiva = false

			if comboState.animacaoAtiva then
				comboState.animacaoAtiva:Stop(0.4)
			end

			OnComboAnimacaoTerminou()
		end
	end)
end

local function OnMarkerAtaquePorMao(indiceGolpe: number, tipoMarcador: string)
	ctx.DebugPrint(string.format("[Combo] Marker %s - golpe %d", tipoMarcador, indiceGolpe))

	if comboState.carregando then
		comboState.carregando = false
		LimparConexaoCarga()
		if comboState.animacaoAtiva then
			comboState.animacaoAtiva:AdjustSpeed(1.0)
		end
		comboState.multiplicadorDano = ctx.Modulo_Configuracoes.ObterConfiguracao("MultiplicadorDanoMaximoCarga") or 1.2
		ctx.DebugPrint("[Combo] Marker de ataque atingido durante carga - auto release total")
	end

	if comboState.animacaoAtiva then
		ultimoTempoHitboxAtivou = comboState.animacaoAtiva.TimePosition
	end

	local tipoAtaque = ctx.Modulo_Configuracoes.ObterTipoAtaquePorIndice(ctx.EstadoAtual.modoAnimacao, indiceGolpe)

	if ctx.ClientBridge.AplicarImpulsoAtaque then
		ctx.ClientBridge.AplicarImpulsoAtaque(tipoAtaque)
	end

	if tipoMarcador == "AttackRight" then
		ctx.GerenciadorHitboxCliente.OnMarkerAttackRight()
	elseif tipoMarcador == "AttackLeft" then
		ctx.GerenciadorHitboxCliente.OnMarkerAttackLeft()
	elseif tipoMarcador == "AttackBoth" then
		ctx.GerenciadorHitboxCliente.OnMarkerAttackBoth()
	end

	local hrp = ctx.Character:FindFirstChild("HumanoidRootPart")
	local dados = {
		indice = indiceGolpe,
		cframe = hrp and hrp.CFrame or nil,
		tipoMarcador = tipoMarcador,
	}
	ctx.TentarAcao:FireServer("ComboHitbox", dados)

	if indiceGolpe >= 4 then
		comboState.janelaAtiva = false
		ctx.DebugPrint("[Combo] Golpe final executado")

		if comboState.animacaoAtiva and comboState.animacaoAtiva.IsPlaying then
			local track = comboState.animacaoAtiva
			local janelaEarlyCancel = ctx.Modulo_Configuracoes.ObterConfiguracao("JanelaCancelamentoComboFinal") or 0.15
			local tempoRestante = (track.Length - track.TimePosition) / track.Speed

			if tempoRestante > janelaEarlyCancel and janelaEarlyCancel > 0 then
				local tempoParaEarlyCancel = tempoRestante - janelaEarlyCancel

				comboState.earlyCancelTimer = task.delay(tempoParaEarlyCancel, function()
					if
						comboState.animacaoAtiva
						and comboState.animacaoAtiva.IsPlaying
						and not comboState.earlyCancelExecutado
					then
						comboState.earlyCancelExecutado = true
						comboState.ultimoComboTerminou = os.clock()
						comboState.tempoInicioCarga = nil

						ctx.GerenciadorHitboxCliente.PararTodas()

						ctx.EstadoAtual.estadoAcao = "Nenhuma"

						ctx.TentarAcao:FireServer("ComboEarlyCancel")

						RestaurarEstadoPosAcao()

						local Movimento = ctx.Modulos.Movimento
						Movimento.AtualizarVelocidadeLocal()
						Animacao.AtualizarAnimacaoMovimento()
					end
				end)
			end
		end
	end
end

local function OnMarkerAtaqueFim()
	ctx.DebugPrint("[Combo] Marker AttackEnd - parando hitboxes")
	ctx.GerenciadorHitboxCliente.PararTodas()
end

local function ConfigurarMarkersCombo(track: AnimationTrack)
	LimparConexoesMarkers()

	comboState.indiceAtual = 0

	local limpezaListeners = ctx.Modulo_Combo.ConfigurarListenersMarcadores(track, {
		onAtaqueDireita = function(indice)
			OnMarkerAtaquePorMao(indice, "AttackRight")
		end,
		onAtaqueEsquerda = function(indice)
			OnMarkerAtaquePorMao(indice, "AttackLeft")
		end,
		onAtaqueAmbos = function(indice)
			OnMarkerAtaquePorMao(indice, "AttackBoth")
		end,
		onAtaqueFim = OnMarkerAtaqueFim,
		onJanelaCombo = OnMarkerJanelaCombo,
	})

	local mockConexao = {
		Connected = true,
		Disconnect = function(self)
			if self.Connected then
				self.Connected = false
				limpezaListeners()
			end
		end,
	}
	table.insert(comboState.conexoesMarkers, mockConexao :: any)

	local conexaoStopped = track.Stopped:Connect(function()
		if comboState.animacaoAtiva == track then
			OnComboAnimacaoTerminou()
		end
	end)
	table.insert(comboState.conexoesMarkers, conexaoStopped)

	ctx.DebugPrint("[Combo] Markers de combo configurados")
end

-- ═══════════════════════════════════════════════════════════════════
-- Hit Freeze
-- ═══════════════════════════════════════════════════════════════════

local function LimparHitFreeze()
	if hitFreezeState.timer then
		pcall(task.cancel, hitFreezeState.timer)
		hitFreezeState.timer = nil
	end
	hitFreezeState.ativo = false
end

function Combo.AplicarHitFreeze()
	local track = comboState.animacaoAtiva
	if not track or not track.IsPlaying then
		return
	end
	if hitFreezeState.ativo or solidHitRewindState.ativo then
		return
	end

	local velFreeze = ctx.Modulo_Configuracoes.ObterConfiguracao("VelocidadeHitFreeze") or 0.2
	local durFreeze = ctx.Modulo_Configuracoes.ObterConfiguracao("DuracaoHitFreeze") or 0.1

	hitFreezeState.ativo = true
	hitFreezeState.velocidadeOriginal = track.Speed
	track:AdjustSpeed(velFreeze)

	hitFreezeState.timer = task.delay(durFreeze, function()
		if track and track.IsPlaying and hitFreezeState.ativo then
			track:AdjustSpeed(hitFreezeState.velocidadeOriginal)
		end
		hitFreezeState.ativo = false
		hitFreezeState.timer = nil
	end)
end

-- ═══════════════════════════════════════════════════════════════════
-- Rewind sólido
-- ═══════════════════════════════════════════════════════════════════

local function LimparRewindSolido()
	if solidHitRewindState.conexaoMonitor then
		solidHitRewindState.conexaoMonitor:Disconnect()
		solidHitRewindState.conexaoMonitor = nil
	end
	solidHitRewindState.ativo = false
	solidHitRewindState.tempoAlvoRetorno = 0
end

local function FinalizarRewindSolido(ehCombo: boolean)
	LimparRewindSolido()
	LimparConexaoCarga()

	ctx.GerenciadorHitboxCliente.PararTodas()

	if ehCombo then
		ResetarComboState()
		ctx.TentarAcao:FireServer("ComboTerminou")
	end

	ctx.EstadoAtual.estadoAcao = "Nenhuma"

	if ctx.IsShiftHeld() then
		ctx.MovementFlags.isRunning = true
		ctx.EstadoAtual.estadoMov = "Correndo"
		ctx.EstadoAtual.correndo = true
	end

	local Movimento = ctx.Modulos.Movimento
	Movimento.AtualizarVelocidadeLocal()
	Animacao.AtualizarBaseIdle()
	Animacao.AtualizarAnimacaoMovimento()
end

function Combo.AplicarRewindParteSolida()
	if solidHitRewindState.ativo then
		return
	end

	local track = comboState.animacaoAtiva
	if not track or not track.IsPlaying then
		return
	end

	LimparHitFreeze()

	solidHitRewindState.ativo = true
	solidHitRewindState.tempoAlvoRetorno = ultimoTempoHitboxAtivou

	ctx.EstadoAtual.estadoAcao = "Nenhuma"

	ctx.GerenciadorHitboxCliente.PararTodas()

	LimparConexoesMarkers()
	comboState.animacaoAtiva = nil

	track:AdjustSpeed(0)

	task.delay(0.02, function()
		if not track or not track.IsPlaying then
			FinalizarRewindSolido(true)
			return
		end

		local velRewind = ctx.Modulo_Configuracoes.ObterConfiguracao("VelocidadeRewindSolido") or -0.5
		track:AdjustSpeed(velRewind)

		if solidHitRewindState.conexaoMonitor then
			solidHitRewindState.conexaoMonitor:Disconnect()
		end

		local tempoInicioRewind = os.clock()
		local tempoAlvo = ultimoTempoHitboxAtivou > 0 and ultimoTempoHitboxAtivou or 0

		solidHitRewindState.conexaoMonitor = RunService.RenderStepped:Connect(function()
			if not track or not track.IsPlaying then
				FinalizarRewindSolido(true)
				return
			end

			local completo = false
			if track.TimePosition <= tempoAlvo + 0.015 or os.clock() - tempoInicioRewind >= 0.15 then
				completo = true
			end

			if completo or track.TimePosition <= 0 then
				local fadeOut = ctx.Modulo_Configuracoes.ObterConfiguracao("FadeOutRewindSolido") or 0.25
				if track and track.IsPlaying then
					track:AdjustSpeed(0)
					track:Stop(fadeOut)
				end
				FinalizarRewindSolido(true)
			end
		end)
	end)
end

-- ═══════════════════════════════════════════════════════════════════
-- Defense cancel
-- ═══════════════════════════════════════════════════════════════════

function Combo.TentarFintar(): (boolean, string?)
	local agora = os.clock()

	local cooldown = ctx.Modulo_Configuracoes.ObterConfiguracao("CooldownCancel") or 1.0
	if (agora - fintaState.ultimaFinta) < cooldown then
		ctx.DebugPrint("[Combo] Finta em cooldown")
		return false, nil
	end

	if comboState.animacaoAtiva and comboState.animacaoAtiva.IsPlaying then
		local isHitboxAtiva = ctx.GerenciadorHitboxCliente.MaoAtiva("Right") or ctx.GerenciadorHitboxCliente.MaoAtiva("Left")
		
		-- Simplificação: Permite cancelar a qualquer momento enquanto o golpe não saiu (hitbox inativa e marker não disparou)
		local podeCancelar = (ultimoTempoHitboxAtivou == 0)
			and not isHitboxAtiva
		if podeCancelar then
			local track = comboState.animacaoAtiva
			local tempoInicioCurrentStrike = comboState.tempoInicioCarga or 0
			local velReversao = ctx.Modulo_Configuracoes.ObterConfiguracao("VelocidadeReversaoCancelamento") or -1.5

			LimparConexoesMarkers()
			LimparConexaoCarga()

			track:AdjustSpeed(velReversao)

			if comboState.conexaoMonitorReversao then
				comboState.conexaoMonitorReversao:Disconnect()
				comboState.conexaoMonitorReversao = nil
			end

			local connection
			connection = RunService.RenderStepped:Connect(function()
				if not track or not track.IsPlaying or track.TimePosition <= tempoInicioCurrentStrike + 0.01 then
					if connection then
						connection:Disconnect()
						if comboState.conexaoMonitorReversao == connection then
							comboState.conexaoMonitorReversao = nil
						end
					end
					if track and track.IsPlaying then
						track:AdjustSpeed(0)
						track.TimePosition = tempoInicioCurrentStrike
						track:Stop(0.1)
					end

					local aindaDefendendo = ctx.ClientBridge.EstaSegurandoM2 and ctx.ClientBridge.EstaSegurandoM2()
					local shiftLockAtivo = ctx.ClientBridge.LerStatusLocal and ctx.ClientBridge.LerStatusLocal("ShiftLockOn") or false
					if aindaDefendendo and shiftLockAtivo then
						ctx.DebugPrint("[Combo] Finta concluída - Jogador segurando M2 e ShiftLock ativo, transição para Defesa")
						Combo.CancelarFintaPendente()
						if ctx.ClientBridge.PredictAnimation then
							ctx.ClientBridge.PredictAnimation("Defesa", true, 1.0)
						end
						ctx.TentarAcao:FireServer("Bloquear", { shiftLock = shiftLockAtivo, timestamp = workspace:GetServerTimeNow() })
					else
						ctx.DebugPrint("[Combo] Finta concluída - sem M2 ou sem ShiftLock, voltando ao Idle")
						Combo.ResolverFintaPendente()
					end
				end
			end)
			comboState.conexaoMonitorReversao = connection

			-- Reset via função unificada (preservando conexaoMonitorReversao)
			comboState.animacaoAtiva = nil
			comboState.janelaAtiva = false
			comboState.indiceAtual = 0
			comboState.continuarCombo = false
			comboState.pendingConsume = false
			comboState.token = 0
			comboState.earlyCancelExecutado = false
			comboState.tempoInicio = 0
			comboState.carregando = false
			comboState.entrouEmCarga = false
			comboState.multiplicadorDano = 1.0
			comboState.tempoInicioCarga = nil

			local cooldownCompleto = ctx.Modulo_Configuracoes.ObterConfiguracao("CooldownComboLeve") or 0.4
			local cooldownFinta = 0.1
			comboState.ultimoComboTerminou = agora - cooldownCompleto + cooldownFinta

			ctx.EstadoAtual.estadoAcao = "Nenhuma"

			fintaState.ultimaFinta = agora
			fintaState.fintaPendente = true

			if ctx.ClientBridge.PredictCancel then
				ctx.ClientBridge.PredictCancel()
			end

			return true, "Ataque"
		end
	end

	return false, nil
end

function Combo.ResolverFintaPendente()
	if fintaState.fintaPendente then
		fintaState.fintaPendente = false
		ctx.DebugPrint("[Combo] Finta pendente resolvida - voltando ao Idle")
		Animacao.AtualizarAnimacaoMovimento()
	end
end

function Combo.CancelarFintaPendente()
	if fintaState.fintaPendente then
		fintaState.fintaPendente = false
		ctx.DebugPrint("[Combo] Finta pendente cancelada - indo para defesa")
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- Impulso de ataque
-- ═══════════════════════════════════════════════════════════════════

local function PararImpulsoAtaque()
	if attackImpulseState.connection then
		attackImpulseState.connection:Disconnect()
		attackImpulseState.connection = nil
	end
end

function Combo.AplicarImpulsoAtaque(tipoAtaque: string)
	local hrp = ctx.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	PararImpulsoAtaque()

	local magnitude
	local duracao

	if tipoAtaque == "AtaqueFinal" then
		magnitude = ctx.Modulo_Configuracoes.ObterConfiguracao("MagnitudeImpulsoAtaqueFinal") or 25
		duracao = ctx.Modulo_Configuracoes.ObterConfiguracao("DuracaoImpulsoAtaqueFinal") or 0.1
	else
		magnitude = ctx.Modulo_Configuracoes.ObterConfiguracao("MagnitudeImpulsoAtaque") or 15
		duracao = ctx.Modulo_Configuracoes.ObterConfiguracao("DuracaoImpulsoAtaque") or 0.1
	end

	attackImpulseState.endTime = os.clock() + duracao

	local direcaoAtaque = hrp.CFrame.LookVector
	direcaoAtaque = Vector3.new(direcaoAtaque.X, 0, direcaoAtaque.Z).Unit

	attackImpulseState.connection = RunService.RenderStepped:Connect(function(_deltaTime)
		if os.clock() >= attackImpulseState.endTime then
			PararImpulsoAtaque()
			return
		end

		local rootPart = ctx.Character:FindFirstChild("HumanoidRootPart")
		if not rootPart then
			PararImpulsoAtaque()
			return
		end

		local velocidadeAtual = rootPart.AssemblyLinearVelocity
		local velocidadeAlvo = direcaoAtaque * magnitude

		rootPart.AssemblyLinearVelocity = Vector3.new(velocidadeAlvo.X, velocidadeAtual.Y, velocidadeAlvo.Z)
	end)

	ctx.DebugPrint(
		string.format(
			"[Combo] Impulso de ataque iniciado: %s (magnitude: %.1f, duração: %.2fs)",
			tipoAtaque,
			magnitude,
			duracao
		)
	)
end

-- ═══════════════════════════════════════════════════════════════════
-- ClientBridge: SoltouM1
-- ═══════════════════════════════════════════════════════════════════

function Combo.SoltouM1()
	if comboState.animacaoAtiva and comboState.carregando then
		comboState.carregando = false
		LimparConexaoCarga()

		local track = comboState.animacaoAtiva
		local janelaCarga = ctx.Modulo_Configuracoes.ObterConfiguracao("JanelaCargaLeve") or 0.25
		local multMax = ctx.Modulo_Configuracoes.ObterConfiguracao("MultiplicadorDanoMaximoCarga") or 1.2

		local tempoCargaDecorrido = track.TimePosition - (comboState.tempoInicioCarga or 0)
		local ratio = math.clamp(tempoCargaDecorrido / janelaCarga, 0, 1)
		comboState.multiplicadorDano = 1.0 + ratio * (multMax - 1.0)

		track:AdjustSpeed(1.0)
		ctx.TentarAcao:FireServer("AjustarVelocidadeAnimacao", { velocidade = 1.0 })

		ctx.DebugPrint(
			string.format(
				"[Combo] M1 solto - Carga finalizada: ratio=%.2f, mult=%.2f",
				ratio,
				comboState.multiplicadorDano
			)
		)
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- ClientBridge: Queries de estado
-- ═══════════════════════════════════════════════════════════════════

function Combo.MarcarContinuarCombo(): boolean
	tempoUltimoInputContinuacao = os.clock()

	if comboState.janelaAtiva then
		comboState.janelaAtiva = false
		comboState.continuarCombo = false

		if comboState.janelaTimer then
			pcall(task.cancel, comboState.janelaTimer)
			comboState.janelaTimer = nil
		end

		if comboState.animacaoAtiva and comboState.animacaoAtiva.IsPlaying then
			ContinuarComboEVerificarCarga(comboState.animacaoAtiva)
		end

		ctx.TentarAcao:FireServer("ComboContinuado", comboState.indiceAtual + 1)
		return true
	end

	if comboState.animacaoAtiva and comboState.animacaoAtiva.IsPlaying then
		comboState.pendingConsume = true
		ctx.DebugPrint("[Combo] Input antecipado registrado (pending)")
		return true
	end

	return false
end

function Combo.EstaJanelaComboAtiva(): boolean
	return comboState.janelaAtiva
end

function Combo.EstaComboAtivo(): boolean
	return comboState.animacaoAtiva ~= nil and comboState.animacaoAtiva.IsPlaying == true
end

function Combo.PodeAtacar(): boolean
	if ctx.ParkourState.ativo then
		return false
	end
	if ctx.MovementFlags.isRolling or ctx.MovementFlags.isDashing then
		return false
	end
	if ctx.EstadoAtual.estadoAcao == "Rolando" or ctx.EstadoAtual.estadoAcao == "Dashando" then
		return false
	end
	if comboState.conexaoMonitorReversao ~= nil then
		return false
	end
	if solidHitRewindState.ativo then
		return false
	end
	local agora = os.clock()
	local ultimoTerminou = comboState.ultimoComboTerminou or 0
	local cooldownVal = ctx.Modulo_Configuracoes.ObterConfiguracao("CooldownComboLeve") or 0.8
	return (agora - ultimoTerminou) >= cooldownVal
end

-- ═══════════════════════════════════════════════════════════════════
-- Chamado pelo Animacao.TocarAnimacaoAcao quando é combo
-- ═══════════════════════════════════════════════════════════════════

function Combo.ProcessarCombo(track: AnimationTrack, _nomeAnimacao: string, velocidade: number)
	if comboState.conexaoMonitorReversao then
		comboState.conexaoMonitorReversao:Disconnect()
		comboState.conexaoMonitorReversao = nil
	end
	ultimoTempoHitboxAtivou = 0
	comboState.animacaoAtiva = track
	comboState.janelaAtiva = false
	comboState.indiceAtual = 1
	comboState.continuarCombo = false
	comboState.tempoInicio = os.clock()

	comboState.tempoInicioCarga = 0
	comboState.carregando = false
	comboState.entrouEmCarga = false
	comboState.multiplicadorDano = 1.0
	LimparConexaoCarga()

	comboState.token = comboState.token + 1
	local myToken = comboState.token

	track:AdjustSpeed(velocidade)
	ctx.DebugPrint("[Combo] Animação de combo iniciada (NORMAL)")

	task.delay(0.12, function()
		if comboState.token ~= myToken or not track or not track.IsPlaying then
			return
		end
		local aindaSegurando = ctx.ClientBridge.EstaSegurandoM1 and ctx.ClientBridge.EstaSegurandoM1()
		if aindaSegurando then
			comboState.carregando = true
			comboState.entrouEmCarga = true
			comboState.tempoInicioCarga = track.TimePosition
			local velCarga = ctx.Modulo_Configuracoes.ObterConfiguracao("VelocidadeCargaAtaque") or 0.4
			track:AdjustSpeed(velCarga)
			IniciarMonitorCarga(track)
			ctx.TentarAcao:FireServer("AjustarVelocidadeAnimacao", { velocidade = velCarga })
			ctx.DebugPrint("[Combo] Carga de combo ativada após hold")
		end
	end)

	ConfigurarMarkersCombo(track)
end

-- ═══════════════════════════════════════════════════════════════════
-- Inicialização
-- ═══════════════════════════════════════════════════════════════════

function Combo.Inicializar(contexto)
	ctx = contexto
	Animacao = ctx.Modulos.Animacao

	-- Registrar funções no ClientBridge
	ctx.ClientBridge.MarcarContinuarCombo = Combo.MarcarContinuarCombo
	ctx.ClientBridge.EstaJanelaComboAtiva = Combo.EstaJanelaComboAtiva
	ctx.ClientBridge.EstaComboAtivo = Combo.EstaComboAtivo
	ctx.ClientBridge.PodeAtacar = Combo.PodeAtacar
	ctx.ClientBridge.SoltouM1 = Combo.SoltouM1
	ctx.ClientBridge.TentarFintar = Combo.TentarFintar
	ctx.ClientBridge.ResolverFintaPendente = Combo.ResolverFintaPendente
	ctx.ClientBridge.CancelarFintaPendente = Combo.CancelarFintaPendente
	ctx.ClientBridge.AplicarImpulsoAtaque = Combo.AplicarImpulsoAtaque
end

return Combo
