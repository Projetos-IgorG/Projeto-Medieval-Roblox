--[[
    Script: ControladorEstadoPersonagem.client.luau
    Caminho: src/StarterPlayer/StarterCharacterScripts/Jogador/Estado
    Responsabilidade: Coordena estados locais do personagem, animacoes e respostas de movimento.
    Uso: LocalScript; roda automaticamente para o jogador local em src/StarterPlayer/StarterCharacterScripts/Jogador/Estado.
    Nao faz: Nao valida autoridade do servidor, nao salva dados persistentes e nao substitui regras server-side.
    Funcoes principais: MarcarContinuarCombo, EstaJanelaComboAtiva, EstaComboAtivo
]]
local DEBUG_ENABLED = false

local function DebugPrint(...)
	if DEBUG_ENABLED then
		print(...)
	end
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local animator = humanoid:WaitForChild("Animator")

local Modulos = ReplicatedStorage
local Modulo_Configuracoes =
	require(Modulos:WaitForChild("Combate"):WaitForChild("Configuracoes"):WaitForChild("ConfigCombate"))
local Modulo_Combo = require(Modulos:WaitForChild("Combate"):WaitForChild("Dominio"):WaitForChild("ComboCombate"))
local GerenciadorHitboxCliente =
	require(Modulos:WaitForChild("Combate"):WaitForChild("Hitbox"):WaitForChild("GerenciadorHitboxCliente"))

local ClientBridge =
	require(Modulos:WaitForChild("Jogador"):WaitForChild("ComunicacaoCliente"):WaitForChild("PonteCliente"))

local TIMINGS = {
	JumpHold = 0.28,
	RunInAirSpeed = 0.4,

	MoveFadeIn = 0.18,
	MoveFadeOut = 0.18,

	ActionFadeIn = 0.20,
	ActionFadeOut = 0.20,

	SoftEnd = 0.40,
}

local function DesativarScriptAnimate()
	local animate = character:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
		DebugPrint("[ControladorEstado] Script Animate padrão desativado")
	end

	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		track:Stop(0)
	end
end

DesativarScriptAnimate()

local Remotos = ReplicatedStorage:WaitForChild("Remotos")
local SincronizarEstado = Remotos:WaitForChild("SincronizarEstado")
local TocarAnimacao = Remotos:WaitForChild("TocarAnimacao")
local TentarAcao = Remotos:WaitForChild("TentarAcao")
local EquipamentoAcao = Remotos:WaitForChild("EquipamentoAcao")

local estadoAtual = {
	estadoMov = "Parado",
	estadoAcao = "Nenhuma",
	estadoAcaoAnterior = "Nenhuma",
	modoAnimacao = "Base",
	bloqueando = false,
	agachado = false,
	correndo = false,
}

local movementFlags = {
	isRunning = false,
	isJumping = false,
	isFalling = false,
	isClimbing = false,
	isSwimming = false,
	isRolling = false,
	isDashing = false,
}
export type ParkourState = {
	ativo: boolean,
	estadoAcaoAnterior: string,
}
local parkourState: ParkourState = {
	ativo = false,
	estadoAcaoAnterior = "Nenhuma",
}

local isShiftHeld = false

local conexoesGlobais: { RBXScriptConnection } = {}

local function ConectarGlobal(signal: RBXScriptSignal, callback: (...any) -> ...any): RBXScriptConnection
	local conexao = signal:Connect(callback)
	table.insert(conexoesGlobais, conexao)
	return conexao
end

local function DesconectarTudoGlobal()
	for _, conexao in ipairs(conexoesGlobais) do
		if conexao.Connected then
			conexao:Disconnect()
		end
	end
	table.clear(conexoesGlobais)
end

script.Destroying:Connect(DesconectarTudoGlobal)
humanoid.Died:Connect(DesconectarTudoGlobal)

local function ObterVelocidadeInicial()
	return Modulo_Configuracoes.ObterConfiguracao("VelocidadeInicialMovimento") or 5
end

local velocidadeRampAlvo = ObterVelocidadeInicial()
local velocidadeRampAtual = ObterVelocidadeInicial()
local rampAtivo = true
local rampSnap = false -- forca aplicar alvo sem interpolar (estados nao-locomocao)

export type HitFreezeState = {
	ativo: boolean,
	velocidadeOriginal: number,
	timer: thread?,
}
local hitFreezeState: HitFreezeState = {
	ativo = false,
	velocidadeOriginal = 1,
	timer = nil,
}

export type SolidHitRewindState = {
	ativo: boolean,
	conexaoMonitor: RBXScriptConnection?,
	tempoAlvoRetorno: number,
}
local solidHitRewindState: SolidHitRewindState = {
	ativo = false,
	conexaoMonitor = nil,
	tempoAlvoRetorno = 0,
}

local ultimoTempoHitboxAtivou = 0

humanoid.WalkSpeed = velocidadeRampAtual

local AtualizarVelocidadeLocal

AtualizarVelocidadeLocal = function()
	local VelBloq = Modulo_Configuracoes.ObterConfiguracao("VelocidadeBloqueando")
	local VelAgachando = Modulo_Configuracoes.ObterConfiguracao("VelocidadeAgachando")
	local VelCorrendo = Modulo_Configuracoes.ObterConfiguracao("VelocidadeCorrendo")
	local VelAndando = Modulo_Configuracoes.ObterConfiguracao("VelocidadeAndando")

	local emCombate = (estadoAtual.estadoAcao == "AtacandoLeve")

	if emCombate then
		local velBloq = VelBloq or 8
		velocidadeRampAlvo = velBloq * 1.5
		rampAtivo = false
		rampSnap = true
		return
	end

	if estadoAtual.estadoAcao == "Defendendo" or estadoAtual.bloqueando then
		velocidadeRampAlvo = VelBloq or 8
		rampAtivo = false
		rampSnap = true
		return
	end

	if estadoAtual.agachado then
		velocidadeRampAlvo = VelAgachando or 12
		rampAtivo = false
		rampSnap = true
	elseif movementFlags.isRunning then
		velocidadeRampAlvo = VelCorrendo or 20
		rampAtivo = true
	else
		velocidadeRampAlvo = VelAndando or 12
		rampAtivo = true
	end
end

ConectarGlobal(RunService.Heartbeat, function(dt)
	if not humanoid or not humanoid.Parent then
		return
	end

	-- Reavalia o alvo todo frame para captar inicio de movimento sem precisar
	-- de evento (caso contrario, andar do zero deixaria a velocidade travada).
	AtualizarVelocidadeLocal()

	if rampSnap then
		velocidadeRampAtual = velocidadeRampAlvo
		humanoid.WalkSpeed = velocidadeRampAtual
		rampSnap = false
		return
	end

	if not rampAtivo then
		return
	end

	local velocidadeInicial = ObterVelocidadeInicial()

	-- Se nao ha input de movimento, volta para a velocidade inicial para que
	-- o proximo passo comece rampando do zero novamente.
	if humanoid.MoveDirection.Magnitude < 0.01 then
		local desaceleracao = Modulo_Configuracoes.ObterConfiguracao("DesaceleracaoMovimento") or 40
		if velocidadeRampAtual > velocidadeInicial then
			velocidadeRampAtual = math.max(velocidadeInicial, velocidadeRampAtual - desaceleracao * dt)
		else
			velocidadeRampAtual = velocidadeInicial
		end
		humanoid.WalkSpeed = velocidadeRampAtual
		return
	end

	local aceleracao
	if movementFlags.isRunning then
		aceleracao = Modulo_Configuracoes.ObterConfiguracao("AceleracaoCorrendo") or 25
	else
		aceleracao = Modulo_Configuracoes.ObterConfiguracao("AceleracaoAndando") or 30
	end

	local diff = velocidadeRampAlvo - velocidadeRampAtual
	if math.abs(diff) < 0.05 then
		velocidadeRampAtual = velocidadeRampAlvo
	else
		local sinal = (diff > 0) and 1 or -1
		local taxa = (diff > 0) and aceleracao
			or (Modulo_Configuracoes.ObterConfiguracao("DesaceleracaoMovimento") or 40)
		local passo = sinal * math.min(math.abs(diff), taxa * dt)
		velocidadeRampAtual = velocidadeRampAtual + passo
	end
	humanoid.WalkSpeed = velocidadeRampAtual
end)

local function SincronizarStatusLocal()
	local statusLocal = character:FindFirstChild("StatusLocal")
	if not statusLocal then
		return
	end

	local function atualizarValor(nome, valor)
		local obj = statusLocal:FindFirstChild(nome)
		if obj and (obj:IsA("StringValue") or obj:IsA("BoolValue") or obj:IsA("NumberValue")) then
			(obj :: any).Value = valor
		end
	end

	atualizarValor("modoAnimacao", estadoAtual.modoAnimacao)
	atualizarValor("estadoMov", estadoAtual.estadoMov)
	atualizarValor("AgachadoOn", estadoAtual.agachado)

	atualizarValor("CorrendoOn", estadoAtual.estadoMov == "Correndo")

	atualizarValor("RollOn", movementFlags.isRolling)
	atualizarValor("DashOn", movementFlags.isDashing)

	if DEBUG_ENABLED then
		local val = estadoAtual.estadoMov == "Correndo"
		local obj = statusLocal:FindFirstChild("CorrendoOn")
		if obj and obj.Value ~= val then
			print(
				string.format(
					"[DEBUG] CorrendoOn mudou: %s -> %s | EstadoMov: %s",
					tostring(obj.Value),
					tostring(val),
					estadoAtual.estadoMov
				)
			)
		end
	end
end

local animacoesCarregadas = {}
local animacaoAtualMov = nil
local animacaoAtualAcao = nil

local animacaoBaseIdle = nil
local idBaseIdleAtual = nil

local direcaoAtual = 1
local velocidadeAnimacaoAlvo = 1
local velocidadeAnimacaoAtual = 1
local animacaoUsaDirecao = false
local SUAVIDADE_TRANSICAO_DIRECAO = 10
local SUAVIDADE_TRANSICAO_CORRENDO = SUAVIDADE_TRANSICAO_DIRECAO * 2

local animacaoMovPausada = false
local ultimaAnimacaoMovNome = nil
local TEMPO_MANTER_ANIMACAO = 0.27
local VELOCIDADE_PAUSA = 0.2
local timerPararAnimacao = nil

local DEBOUNCE_TROCA_LATERAL = 0.1
local ultimaTrocaLateralTime = 0

local walkCycleState = {
	time = 0,
	speed = 1,
	lastWalkAnimName = nil,
}

local ANIMACOES_COM_DIRECAO = {
	Andando = true,
	Correndo = true,
	AndandoAgachado = true,
	AndandoDireita = true,
	AndandoEsquerda = true,
	CorrendoDireita = true,
	CorrendoEsquerda = true,
}

local ANIMACOES_SEM_LOOP = {
	Pulando = true,
}

export type JumpAnimState = {
	animacao: AnimationTrack?,
	conexaoTermino: RBXScriptConnection?,
	aguardandoTermino: boolean,
}
local jumpAnimState: JumpAnimState = {
	animacao = nil,
	conexaoTermino = nil,
	aguardandoTermino = false,
}

local AtualizarAnimacaoMovimento: () -> ()
local AtualizarBaseIdle: () -> ()
local ObterAnimacao: (animId: string) -> AnimationTrack?
local ObterToolEquipado: () -> Tool?
local PararAnimacaoMov: (forcarParar: boolean?) -> ()

local function obterModoAnimacaoEfetivoParaIdle(): string
	if estadoAtual.modoAnimacao ~= "Base" then
		return estadoAtual.modoAnimacao
	end
	if estadoAtual.estadoAcao == "Desequipando" then
		return estadoAtual.modoAnimacao
	end
	if not ObterToolEquipado then
		return estadoAtual.modoAnimacao
	end
	local tool = ObterToolEquipado()
	local dados = tool and tool:FindFirstChild("Dados")
	if not dados then
		return estadoAtual.modoAnimacao
	end
	local tipoValue = dados:FindFirstChild("Tipo")
	if not tipoValue or not tipoValue:IsA("StringValue") or tipoValue.Value ~= "ArmasEquipadas" then
		return estadoAtual.modoAnimacao
	end
	local modoValue = dados:FindFirstChild("modoAnimacao") or dados:FindFirstChild("Modo")
	if modoValue and modoValue:IsA("StringValue") and modoValue.Value ~= "" then
		return modoValue.Value
	end
	return estadoAtual.modoAnimacao
end

AtualizarBaseIdle = function()
	local nomeIdle = estadoAtual.agachado and "IdleAgachado" or "Idle"
	local modoIdle = obterModoAnimacaoEfetivoParaIdle()
	local animId = Modulo_Configuracoes.ObterIdAnimacao(modoIdle, nomeIdle)

	if not animId then
		animId = Modulo_Configuracoes.ObterIdAnimacao("Base", nomeIdle)
	end

	if not animId or animId == idBaseIdleAtual then
		return
	end

	idBaseIdleAtual = animId
	local novaTrack = ObterAnimacao(animId)

	if novaTrack then
		if animacaoBaseIdle then
			animacaoBaseIdle:Stop(TIMINGS.MoveFadeOut)
		end

		animacaoBaseIdle = novaTrack
		animacaoBaseIdle.Priority = Enum.AnimationPriority.Idle
		animacaoBaseIdle.Looped = true
		animacaoBaseIdle:Play(TIMINGS.MoveFadeIn)
		DebugPrint(string.format("[ControladorEstado] BaseIdle atualizado para: %s (%s)", nomeIdle, animId))
	end
end

export type ComboState = {
	animacaoAtiva: AnimationTrack?,
	janelaAtiva: boolean,
	indiceAtual: number,
	conexoesMarkers: { any },
	continuarCombo: boolean,
	pendingConsume: boolean,
	janelaTimer: thread?,
	token: number,
	earlyCancelTimer: thread?,
	earlyCancelExecutado: boolean,
	tempoInicio: number,
	conexaoMonitorReversao: RBXScriptConnection?,
	carregando: boolean,
	multiplicadorDano: number,
	conexaoCarga: RBXScriptConnection?,
	tempoInicioCarga: number?,
	ultimoComboTerminou: number?,
}
local comboState: ComboState = {
	animacaoAtiva = nil,
	janelaAtiva = false,
	indiceAtual = 0,
	conexoesMarkers = {},
	continuarCombo = false,
	pendingConsume = false,
	janelaTimer = nil,
	token = 0,
	earlyCancelTimer = nil,
	earlyCancelExecutado = false,
	tempoInicio = 0,
	conexaoMonitorReversao = nil,
	carregando = false,
	multiplicadorDano = 1.0,
	conexaoCarga = nil,
	tempoInicioCarga = nil,
	ultimoComboTerminou = nil,
}

local defenseCancelState = {
	ultimoCancelamento = 0,
	cancelPendente = false,
}

local function LimparConexaoCarga()
	if comboState.conexaoCarga then
		comboState.conexaoCarga:Disconnect()
		comboState.conexaoCarga = nil
	end
end

local function IniciarMonitorCarga(track: AnimationTrack)
	LimparConexaoCarga()
	local janelaCarga = Modulo_Configuracoes.ObterConfiguracao("JanelaCargaLeve") or 0.25

	comboState.conexaoCarga = RunService.RenderStepped:Connect(function()
		if not track or not track.IsPlaying or not comboState.carregando then
			LimparConexaoCarga()
			return
		end

		local tempoCargaDecorrido = track.TimePosition - (comboState.tempoInicioCarga or 0)
		if tempoCargaDecorrido >= janelaCarga then
			comboState.carregando = false
			track:AdjustSpeed(1.0)
			comboState.multiplicadorDano = Modulo_Configuracoes.ObterConfiguracao("MultiplicadorDanoMaximoCarga") or 1.2
			LimparConexaoCarga()
			TentarAcao:FireServer("AjustarVelocidadeAnimacao", { velocidade = 1.0 })
			DebugPrint("[ControladorEstado] Carga máxima atingida - auto release")
		end
	end)
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

local function OnComboAnimacaoTerminou()
	DebugPrint("[ControladorEstado] Combo animação terminou")

	LimparConexoesMarkers()
	LimparConexaoCarga()

	GerenciadorHitboxCliente.PararTodas()

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
	comboState.ultimoComboTerminou = tick()

	estadoAtual.estadoAcao = "Nenhuma"

	TentarAcao:FireServer("ComboTerminou")

	if isShiftHeld then
		movementFlags.isRunning = true
		estadoAtual.estadoMov = "Correndo"
		estadoAtual.correndo = true
	end

	AtualizarVelocidadeLocal()

	AtualizarBaseIdle()

	AtualizarAnimacaoMovimento()
end

local function ContinuarComboEVerificarCarga(track: AnimationTrack)
	comboState.tempoInicioCarga = track.TimePosition
	comboState.carregando = false
	comboState.multiplicadorDano = 1.0
	LimparConexaoCarga()

	comboState.token = comboState.token + 1
	local myToken = comboState.token

	track:AdjustSpeed(1.0)
	TentarAcao:FireServer("AjustarVelocidadeAnimacao", { velocidade = 1.0 })
	DebugPrint("[ControladorEstado] Combo continuado: golpe normal")

	task.delay(0.12, function()
		if comboState.token ~= myToken or not track or not track.IsPlaying then
			return
		end
		local aindaSegurando = ClientBridge.EstaSegurandoM1 and ClientBridge.EstaSegurandoM1()
		if aindaSegurando then
			comboState.carregando = true
			comboState.tempoInicioCarga = track.TimePosition
			local velCarga = Modulo_Configuracoes.ObterConfiguracao("VelocidadeCargaAtaque") or 0.4
			track:AdjustSpeed(velCarga)
			IniciarMonitorCarga(track)
			TentarAcao:FireServer("AjustarVelocidadeAnimacao", { velocidade = velCarga })
			DebugPrint("[ControladorEstado] Combo continuado: carregando próximo golpe")
		end
	end)
end

local function OnMarkerJanelaCombo(ehFinal: boolean)
	if not comboState.animacaoAtiva then
		return
	end

	comboState.indiceAtual = comboState.indiceAtual + 1

	comboState.token = comboState.token + 1
	local myToken = comboState.token

	comboState.janelaAtiva = true
	comboState.continuarCombo = false

	DebugPrint(
		string.format(
			"[ControladorEstado] Janela de combo ativada (golpe %d, final=%s)",
			comboState.indiceAtual,
			tostring(ehFinal)
		)
	)

	local combo = Modulo_Configuracoes.ObterConfiguracaoCombo(estadoAtual.modoAnimacao)
	if not combo then
		return
	end

	comboState.animacaoAtiva:AdjustSpeed(combo.velocidadeJanela)
	TentarAcao:FireServer("AjustarVelocidadeAnimacao", { velocidade = combo.velocidadeJanela })

	if comboState.pendingConsume then
		DebugPrint("[ControladorEstado] Consumo antecipado de combo (pending antes da janela)")
		comboState.pendingConsume = false
		comboState.continuarCombo = true
		comboState.janelaAtiva = false

		if comboState.animacaoAtiva and comboState.animacaoAtiva.IsPlaying then
			ContinuarComboEVerificarCarga(comboState.animacaoAtiva)
		end

		TentarAcao:FireServer("ComboContinuado", comboState.indiceAtual + 1)
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
			DebugPrint("[ControladorEstado] Combo continuando - velocidade restaurada")
			comboState.janelaAtiva = false
			comboState.continuarCombo = false

			if comboState.animacaoAtiva and comboState.animacaoAtiva.IsPlaying then
				ContinuarComboEVerificarCarga(comboState.animacaoAtiva)
			end

			TentarAcao:FireServer("ComboContinuado", comboState.indiceAtual + 1)
		else
			DebugPrint("[ControladorEstado] Janela expirou - combo terminando")
			comboState.janelaAtiva = false

			if comboState.animacaoAtiva then
				comboState.animacaoAtiva:Stop(0.4)
			end

			OnComboAnimacaoTerminou()
		end
	end)
end

local function OnMarkerAtaquePorMao(indiceGolpe: number, tipoMarcador: string)
	DebugPrint(string.format("[ControladorEstado] Marker %s - golpe %d", tipoMarcador, indiceGolpe))

	if comboState.carregando then
		comboState.carregando = false
		LimparConexaoCarga()
		if comboState.animacaoAtiva then
			comboState.animacaoAtiva:AdjustSpeed(1.0)
		end
		comboState.multiplicadorDano = Modulo_Configuracoes.ObterConfiguracao("MultiplicadorDanoMaximoCarga") or 1.2
		DebugPrint("[ControladorEstado] Marker de ataque atingido durante carga - auto release total")
	end

	if comboState.animacaoAtiva then
		ultimoTempoHitboxAtivou = comboState.animacaoAtiva.TimePosition
	end

	local tipoAtaque = Modulo_Configuracoes.ObterTipoAtaquePorIndice(estadoAtual.modoAnimacao, indiceGolpe)

	if ClientBridge.AplicarImpulsoAtaque then
		ClientBridge.AplicarImpulsoAtaque(tipoAtaque)
	end

	if tipoMarcador == "AttackRight" then
		GerenciadorHitboxCliente.OnMarkerAttackRight()
	elseif tipoMarcador == "AttackLeft" then
		GerenciadorHitboxCliente.OnMarkerAttackLeft()
	elseif tipoMarcador == "AttackBoth" then
		GerenciadorHitboxCliente.OnMarkerAttackBoth()
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	local dados = {
		indice = indiceGolpe,
		cframe = hrp and hrp.CFrame or nil,
		tipoMarcador = tipoMarcador,
	}
	TentarAcao:FireServer("ComboHitbox", dados)

	if indiceGolpe >= 4 then
		comboState.janelaAtiva = false
		DebugPrint("[ControladorEstado] Golpe final executado")

		if comboState.animacaoAtiva and comboState.animacaoAtiva.IsPlaying then
			local track = comboState.animacaoAtiva
			local janelaEarlyCancel = Modulo_Configuracoes.ObterConfiguracao("JanelaCancelamentoComboFinal") or 0.15
			local tempoRestante = (track.Length - track.TimePosition) / track.Speed

			if tempoRestante > janelaEarlyCancel and janelaEarlyCancel > 0 then
				local tempoParaEarlyCancel = tempoRestante - janelaEarlyCancel
				DebugPrint(
					string.format(
						"[ControladorEstado] Early cancel agendado: %.2fs restante, early cancel em %.2fs",
						tempoRestante,
						tempoParaEarlyCancel
					)
				)

				comboState.earlyCancelTimer = task.delay(tempoParaEarlyCancel, function()
					if
						comboState.animacaoAtiva
						and comboState.animacaoAtiva.IsPlaying
						and not comboState.earlyCancelExecutado
					then
						comboState.earlyCancelExecutado = true
						comboState.ultimoComboTerminou = tick()
						comboState.tempoInicioCarga = nil
						DebugPrint("[ControladorEstado] Early cancel executado - mudando estado para Normal")

						GerenciadorHitboxCliente.PararTodas()

						estadoAtual.estadoAcao = "Nenhuma"

						TentarAcao:FireServer("ComboEarlyCancel")

						if isShiftHeld then
							movementFlags.isRunning = true
							estadoAtual.estadoMov = "Correndo"
							estadoAtual.correndo = true
						end

						AtualizarVelocidadeLocal()

						AtualizarAnimacaoMovimento()
					end
				end)
			end
		end
	end
end

local function OnMarkerAtaqueFim()
	DebugPrint("[ControladorEstado] Marker AttackEnd - parando hitboxes")
	GerenciadorHitboxCliente.PararTodas()
end

local function ConfigurarMarkersCombo(track: AnimationTrack)
	LimparConexoesMarkers()

	comboState.indiceAtual = 0

	local limpezaListeners = Modulo_Combo.ConfigurarListenersMarcadores(track, {

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

	DebugPrint("[ControladorEstado] Markers de combo configurados")
end

function ClientBridge.MarcarContinuarCombo()
	if comboState.janelaAtiva then
		comboState.continuarCombo = true
		DebugPrint("[ControladorEstado] Input de continuar combo registrado (janela ativa)")
		return true
	end

	if comboState.animacaoAtiva and comboState.animacaoAtiva.IsPlaying then
		comboState.pendingConsume = true
		DebugPrint("[ControladorEstado] Input antecipado registrado (pending)")
		return true
	end

	return false
end

function ClientBridge.EstaJanelaComboAtiva()
	return comboState.janelaAtiva
end

function ClientBridge.EstaComboAtivo()
	return comboState.animacaoAtiva and comboState.animacaoAtiva.IsPlaying
end

function ClientBridge.PodeAtacarLeve(): boolean
	if parkourState.ativo then
		return false
	end
	local agora = tick()
	local ultimoTerminou = comboState.ultimoComboTerminou or 0
	local cooldown = Modulo_Configuracoes.ObterConfiguracao("CooldownComboLeve") or 0.8
	return (agora - ultimoTerminou) >= cooldown
end

-- ═══════════════════════════════════════════════════════════════════
-- Hit Freeze: micro-pausa ao acertar entidade
-- ═══════════════════════════════════════════════════════════════════

local function LimparHitFreeze()
	if hitFreezeState.timer then
		pcall(task.cancel, hitFreezeState.timer)
		hitFreezeState.timer = nil
	end
	hitFreezeState.ativo = false
end

local function AplicarHitFreeze()
	local track = comboState.animacaoAtiva
	if not track or not track.IsPlaying then
		return
	end
	if hitFreezeState.ativo or solidHitRewindState.ativo then
		return
	end

	local velFreeze = Modulo_Configuracoes.ObterConfiguracao("VelocidadeHitFreeze") or 0.2
	local durFreeze = Modulo_Configuracoes.ObterConfiguracao("DuracaoHitFreeze") or 0.1

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
-- Rewind em parte sólida: reverte animação até o marker de hitbox
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

	GerenciadorHitboxCliente.PararTodas()

	if ehCombo then
		LimparConexoesMarkers()
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

		TentarAcao:FireServer("ComboTerminou")
	end

	estadoAtual.estadoAcao = "Nenhuma"

	if isShiftHeld then
		movementFlags.isRunning = true
		estadoAtual.estadoMov = "Correndo"
		estadoAtual.correndo = true
	end

	AtualizarVelocidadeLocal()
	AtualizarBaseIdle()
	AtualizarAnimacaoMovimento()
end

local function AplicarRewindParteSolida()
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

	-- Liberar estado de ação do jogador imediatamente ao acertar a parede
	estadoAtual.estadoAcao = "Nenhuma"

	-- Parar hitboxes imediatamente
	GerenciadorHitboxCliente.PararTodas()

	-- Desconectar listeners para evitar interferência
	LimparConexoesMarkers()
	comboState.animacaoAtiva = nil

	-- Transição suave: para → micro delay → reverte
	track:AdjustSpeed(0)

	task.delay(0.02, function()
		if not track or not track.IsPlaying then
			FinalizarRewindSolido(true)
			return
		end

		local velRewind = Modulo_Configuracoes.ObterConfiguracao("VelocidadeRewindSolido") or -0.5
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
				local fadeOut = Modulo_Configuracoes.ObterConfiguracao("FadeOutRewindSolido") or 0.25
				if track and track.IsPlaying then
					track:AdjustSpeed(0)
					-- Remover o snap manual de TimePosition para evitar flick visual nas articulações
					track:Stop(fadeOut)
				end
				FinalizarRewindSolido(true)
			end
		end)
	end)
end

function ClientBridge.TentarCancelarAtaquePorDefesa()
	local agora = tick()

	local cooldown = Modulo_Configuracoes.ObterConfiguracao("CooldownCancel") or 1.0
	if (agora - defenseCancelState.ultimoCancelamento) < cooldown then
		DebugPrint("[ControladorEstado] Defense cancel em cooldown")
		return false, nil
	end

	if comboState.animacaoAtiva and comboState.animacaoAtiva.IsPlaying then
		local tempoCarga = comboState.tempoInicioCarga or 0
		local trackTime = comboState.animacaoAtiva.TimePosition
		local tempoAnimacao = trackTime - tempoCarga
		local janelaAtaque = Modulo_Configuracoes.ObterConfiguracao("JanelaCancelAtaque") or 0.15

		local podeCancelar = (tempoAnimacao <= janelaAtaque) or comboState.carregando
		if podeCancelar then
			DebugPrint(
				string.format(
					"[ControladorEstado] Defense cancel: Cancelando ataque leve (%.3fs dentro da janela de %.3fs ou carregando=%s)",
					tempoAnimacao,
					janelaAtaque,
					tostring(comboState.carregando)
				)
			)

			local track = comboState.animacaoAtiva
			local tempoInicioCurrentStrike = comboState.tempoInicioCarga or 0
			local velReversao = Modulo_Configuracoes.ObterConfiguracao("VelocidadeReversaoCancelamento") or -1.5

			-- Desconectar listeners e cargas ANTES de criar o monitor de reversão,
			-- para evitar que LimparConexoesMarkers() desconecte a nova conexaoMonitorReversao!
			LimparConexoesMarkers()
			LimparConexaoCarga()

			track:AdjustSpeed(velReversao)

			comboState.conexaoMonitorReversao = RunService.RenderStepped:Connect(function()
				if not track or not track.IsPlaying or track.TimePosition <= tempoInicioCurrentStrike + 0.01 then
					local conn = comboState.conexaoMonitorReversao
					if conn then
						conn:Disconnect()
						comboState.conexaoMonitorReversao = nil
					end
					if track and track.IsPlaying then
						track:AdjustSpeed(0)
						track.TimePosition = tempoInicioCurrentStrike
						track:Stop(0.1)
					end
				end
			end)

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

			local cooldownCompleto = Modulo_Configuracoes.ObterConfiguracao("CooldownComboLeve") or 0.4
			local cooldownCancel = 0.1
			comboState.ultimoComboTerminou = agora - cooldownCompleto + cooldownCancel

			estadoAtual.estadoAcao = "Nenhuma"

			defenseCancelState.ultimoCancelamento = agora

			defenseCancelState.cancelPendente = true

			return true, "AtaqueLeve"
		end
	end

	return false, nil
end

function ClientBridge.ResolverCancelPendente()
	if defenseCancelState.cancelPendente then
		defenseCancelState.cancelPendente = false
		DebugPrint("[ControladorEstado] Cancel pendente resolvido - voltando ao Idle")
		AtualizarAnimacaoMovimento()
	end
end

function ClientBridge.CancelarCancelPendente()
	if defenseCancelState.cancelPendente then
		defenseCancelState.cancelPendente = false
		DebugPrint("[ControladorEstado] Cancel pendente cancelado - indo para defesa")
	end
end

export type EquipAnimState = {
	animacao: AnimationTrack?,
	direcao: number,
	modoAlvo: string?,
	conexaoTermino: RBXScriptConnection?,
	tempoInicio: number,
	armaClonada: Tool?,
	conexaoMarkerEquip: RBXScriptConnection?,
	conexaoMarkerDesequip: RBXScriptConnection?,
	acessorioJaClonado: boolean,
}
local equipAnimState: EquipAnimState = {
	animacao = nil,
	direcao = 0,
	modoAlvo = nil,
	conexaoTermino = nil,
	tempoInicio = 0,
	armaClonada = nil,
	conexaoMarkerEquip = nil,
	conexaoMarkerDesequip = nil,
	acessorioJaClonado = false,
}

ObterToolEquipado = function(): Tool?
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Tool") :: Tool?
end

local function ClonarAcessorioParaJogador()
	if equipAnimState.acessorioJaClonado then
		if equipAnimState.armaClonada and equipAnimState.armaClonada.Parent then
			DebugPrint("[ControladorEstado] Arma já existe, ignorando")
			return
		end

		equipAnimState.acessorioJaClonado = false
		equipAnimState.armaClonada = nil
	end

	local tool = ObterToolEquipado()
	if not tool then
		DebugPrint("[ControladorEstado] Nenhum Tool equipado para criar joint de arma")
		return
	end

	local dadosFolder = tool:FindFirstChild("Dados")
	if dadosFolder then
		local tipoValue = dadosFolder:FindFirstChild("Tipo")
		if not tipoValue or tipoValue.Value ~= "ArmasEquipadas" then
			DebugPrint("[ControladorEstado] Tool não é ArmasEquipadas, ignorando:", tool.Name)
			return
		end
	else
		DebugPrint("[ControladorEstado] Tool sem Dados, ignorando:", tool.Name)
		return
	end

	EquipamentoAcao:FireServer("ClonarAcessorio", "RightArm")

	equipAnimState.acessorioJaClonado = true

	task.defer(function()
		local tentativas = 0
		while tentativas < 20 do
			if not character then
				break
			end

			local rightArm = character:FindFirstChild("Right Arm")
			if rightArm then
				local joint = rightArm:FindFirstChild("RightArm_WeaponJoint")
				if joint then
					equipAnimState.armaClonada = joint
					DebugPrint("[ControladorEstado] WeaponJoint server-side detectado:", joint.Name)
					break
				end
			end
			task.wait(0.05)
			tentativas += 1
		end
	end)

	DebugPrint("[ControladorEstado] Solicitação de criação de joint de arma enviada ao servidor")
end

local function RemoverAcessorioDoJogador()
	GerenciadorHitboxCliente.DestruirTodas()

	EquipamentoAcao:FireServer("RemoverAcessorio", "RightArm")

	equipAnimState.armaClonada = nil
	equipAnimState.acessorioJaClonado = false

	DebugPrint("[ControladorEstado] Solicitação de remoção de joint de arma enviada ao servidor")
end

local function LimparConexoesMarkersEquip()
	if equipAnimState.conexaoMarkerEquip then
		equipAnimState.conexaoMarkerEquip:Disconnect()
		equipAnimState.conexaoMarkerEquip = nil
	end
	if equipAnimState.conexaoMarkerDesequip then
		equipAnimState.conexaoMarkerDesequip:Disconnect()
		equipAnimState.conexaoMarkerDesequip = nil
	end
end

local function ConfigurarMarkersEquip(track: AnimationTrack, ehEquipar: boolean)
	LimparConexoesMarkersEquip()

	if ehEquipar then
		equipAnimState.conexaoMarkerEquip = track:GetMarkerReachedSignal("Equip"):Connect(function()
			if equipAnimState.direcao == 1 then
				ClonarAcessorioParaJogador()
				DebugPrint("[ControladorEstado] Marker 'Equip' atingido - acessório clonado")
			end
		end)
	else
		equipAnimState.conexaoMarkerDesequip = track:GetMarkerReachedSignal("Desequip"):Connect(function()
			if equipAnimState.direcao == -1 then
				RemoverAcessorioDoJogador()
				DebugPrint("[ControladorEstado] Marker 'Desequip' atingido - acessório removido")
			end
		end)
	end
end

local function OnEquipAnimacaoTerminou()
	local direcaoFinal = equipAnimState.direcao

	LimparConexoesMarkersEquip()

	if equipAnimState.conexaoTermino then
		equipAnimState.conexaoTermino:Disconnect()
		equipAnimState.conexaoTermino = nil
	end
	equipAnimState.animacao = nil
	equipAnimState.direcao = 0
	equipAnimState.modoAlvo = nil

	if direcaoFinal == 1 then
		if not equipAnimState.acessorioJaClonado then
			ClonarAcessorioParaJogador()
		end
	elseif direcaoFinal == -1 then
		RemoverAcessorioDoJogador()
	end

	if ClientBridge.OnEquipAnimacaoTerminou then
		ClientBridge.OnEquipAnimacaoTerminou(direcaoFinal)
	end

	AtualizarAnimacaoMovimento()

	DebugPrint("[ControladorEstado] Animação de equipar/desequipar terminou (direção:", direcaoFinal, ")")
end

function ClientBridge.EstaEmAnimacaoEquip()
	return equipAnimState.animacao ~= nil and equipAnimState.animacao.IsPlaying
end

function ClientBridge.PodeAlterarTool()
	if estadoAtual.estadoAcao ~= "Nenhuma" then
		return false
	end

	if equipAnimState.animacao ~= nil and equipAnimState.animacao.IsPlaying then
		return false
	end

	return true
end

-- ═══════════════════════════════════════════════════════════════════
-- Roll (esquiva rolando no chão, tecla Q)
-- ═══════════════════════════════════════════════════════════════════

export type RollState = {
	animacao: AnimationTrack?,
	direcao: string,
	conexaoTermino: RBXScriptConnection?,
	velocityConnection: RBXScriptConnection?,
	earlyCancelTimer: thread?,
	earlyCancelExecutado: boolean,
}
local rollState: RollState = {
	animacao = nil,
	direcao = "Frente",
	conexaoTermino = nil,
	velocityConnection = nil,
	earlyCancelTimer = nil,
	earlyCancelExecutado = false,
}

local function CalcularDirecaoRollLocal(atualizarCFrame: boolean?): string
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return "Frente"
	end

	local moveDir = humanoid.MoveDirection

	if moveDir.Magnitude < 0.1 then
		return "Frente"
	end

	local originalRotation = ClientBridge.CFrameRotacaoRoll or (hrp.CFrame - hrp.Position)
	local lookVector = originalRotation.LookVector
	local rightVector = originalRotation.RightVector

	local lookXZ = Vector3.new(lookVector.X, 0, lookVector.Z)
	lookXZ = if lookXZ.Magnitude > 0.001 then lookXZ.Unit else Vector3.new(0, 0, -1)

	local rightXZ = Vector3.new(rightVector.X, 0, rightVector.Z)
	rightXZ = if rightXZ.Magnitude > 0.001 then rightXZ.Unit else Vector3.new(1, 0, 0)

	local moveXZ = Vector3.new(moveDir.X, 0, moveDir.Z).Unit

	local dotForward = lookXZ:Dot(moveXZ)
	local dotRight = rightXZ:Dot(moveXZ)

	local angle = math.atan2(dotRight, dotForward) * (180 / math.pi)

	local function ObterRotacaoXZ(direcaoVector: Vector3): CFrame
		return CFrame.lookAt(Vector3.zero, Vector3.new(direcaoVector.X, 0, direcaoVector.Z).Unit)
	end

	if angle >= -22.5 and angle <= 22.5 then
		return "Frente"
	elseif math.abs(angle) > 22.5 and math.abs(angle) <= 67.5 then
		-- Diagonal Frente-Direita ou Frente-Esquerda
		if atualizarCFrame then
			ClientBridge.CFrameRotacaoRoll = ObterRotacaoXZ(moveXZ)
		end
		return "Frente"
	elseif angle > 67.5 and angle <= 112.5 then
		return "Direita"
	elseif angle > -112.5 and angle <= -67.5 then
		return "Esquerda"
	elseif math.abs(angle) > 112.5 and math.abs(angle) <= 157.5 then
		-- Diagonal Trás-Direita ou Trás-Esquerda
		if atualizarCFrame then
			ClientBridge.CFrameRotacaoRoll = ObterRotacaoXZ(-moveXZ)
		end
		return "Tras"
	else -- angle > 157.5 or angle <= -157.5
		return "Tras"
	end
end

ClientBridge.CalcularDirecaoRoll = CalcularDirecaoRollLocal

function ClientBridge.EstaEmRoll()
	return movementFlags.isRolling
end

local function IniciarImpulsoRoll(direcao: string)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local forcaRoll = Modulo_Configuracoes.ObterConfiguracao("ForcaRoll") or 45

	if rollState.velocityConnection then
		rollState.velocityConnection:Disconnect()
	end

	local startRotation = ClientBridge.CFrameRotacaoOriginalRoll or (hrp.CFrame - hrp.Position)
	local targetRotation = ClientBridge.CFrameRotacaoRoll or startRotation
	local lookVector = targetRotation.LookVector
	local rightVector = targetRotation.RightVector

	local dirVector = ClientBridge.DirecaoMovimentoRoll
	if not dirVector then
		dirVector = lookVector
		if direcao == "Tras" then
			dirVector = -lookVector
		elseif direcao == "Esquerda" then
			dirVector = -rightVector
		elseif direcao == "Direita" then
			dirVector = rightVector
		end
	end

	dirVector = Vector3.new(dirVector.X, 0, dirVector.Z).Unit
	local tempoInicio = tick()

	rollState.velocityConnection = RunService.RenderStepped:Connect(function(_deltaTime)
		if not rollState.animacao or not rollState.animacao.IsPlaying then
			if rollState.velocityConnection then
				rollState.velocityConnection:Disconnect()
				rollState.velocityConnection = nil
			end
			return
		end

		if not hrp or not hrp.Parent then
			if rollState.velocityConnection then
				rollState.velocityConnection:Disconnect()
				rollState.velocityConnection = nil
			end
			return
		end

		local t = math.clamp((tick() - tempoInicio) / 0.15, 0, 1)
		local currentRotation = startRotation:Lerp(targetRotation, t)

		local velocidadeAtual = hrp.AssemblyLinearVelocity
		local velocidadeAlvo = dirVector * forcaRoll

		hrp.AssemblyLinearVelocity = Vector3.new(velocidadeAlvo.X, velocidadeAtual.Y, velocidadeAlvo.Z)

		hrp.CFrame = currentRotation + hrp.Position
	end)
end

local function PararImpulsoRoll()
	if rollState.velocityConnection then
		rollState.velocityConnection:Disconnect()
		rollState.velocityConnection = nil
	end
end

local function OnRollAnimacaoTerminou()
	DebugPrint("[ControladorEstado] Roll animação terminou")

	PararImpulsoRoll()

	rollState.animacao = nil
	rollState.direcao = "Frente"
	movementFlags.isRolling = false
	ClientBridge.CFrameRotacaoRoll = nil
	ClientBridge.CFrameRotacaoOriginalRoll = nil
	ClientBridge.PreRollActive = nil
	ClientBridge.DirecaoMovimentoRoll = nil

	if rollState.conexaoTermino then
		rollState.conexaoTermino:Disconnect()
		rollState.conexaoTermino = nil
	end

	if rollState.earlyCancelTimer then
		pcall(task.cancel, rollState.earlyCancelTimer)
		rollState.earlyCancelTimer = nil
	end

	rollState.earlyCancelExecutado = false

	TentarAcao:FireServer("RollTerminou")

	estadoAtual.estadoAcao = "Nenhuma"

	if isShiftHeld then
		movementFlags.isRunning = true
		estadoAtual.estadoMov = "Correndo"
		estadoAtual.correndo = true
	end

	AtualizarVelocidadeLocal()

	AtualizarAnimacaoMovimento()
end

-- ═══════════════════════════════════════════════════════════════════
-- Dash (impulso rápido lateral/trás, tecla Space)
-- ═══════════════════════════════════════════════════════════════════

export type DashState = {
	animacao: AnimationTrack?,
	direcao: string,
	conexaoTermino: RBXScriptConnection?,
	velocityConnection: RBXScriptConnection?,
	earlyCancelTimer: thread?,
	earlyCancelExecutado: boolean,
	impulsoTimer: thread?,
}
local dashState: DashState = {
	animacao = nil,
	direcao = "Tras",
	conexaoTermino = nil,
	velocityConnection = nil,
	earlyCancelTimer = nil,
	earlyCancelExecutado = false,
	impulsoTimer = nil,
}

ClientBridge.CalcularDirecaoDash = CalcularDirecaoRollLocal

function ClientBridge.EstaEmDash()
	return movementFlags.isDashing
end

local function IniciarImpulsoDash(direcao: string)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local forcaDash, duracaoDash
	if direcao == "Tras" then
		forcaDash = Modulo_Configuracoes.ObterConfiguracao("ForcaDashTras") or 50
		duracaoDash = Modulo_Configuracoes.ObterConfiguracao("DuracaoDashTras") or 0.12
	else
		forcaDash = Modulo_Configuracoes.ObterConfiguracao("ForcaDashLateral") or 55
		duracaoDash = Modulo_Configuracoes.ObterConfiguracao("DuracaoDashLateral") or 0.22
	end

	if dashState.velocityConnection then
		dashState.velocityConnection:Disconnect()
	end

	local startRotation = ClientBridge.CFrameRotacaoDash or (hrp.CFrame - hrp.Position)
	local lookVector = startRotation.LookVector
	local rightVector = startRotation.RightVector

	local dirVector
	if direcao == "Tras" then
		dirVector = -lookVector
	elseif direcao == "Esquerda" then
		dirVector = -rightVector
	elseif direcao == "Direita" then
		dirVector = rightVector
	else
		dirVector = lookVector
	end

	dirVector = Vector3.new(dirVector.X, 0, dirVector.Z).Unit
	local tempoInicio = tick()

	dashState.velocityConnection = RunService.RenderStepped:Connect(function(_deltaTime)
		if not dashState.animacao or not dashState.animacao.IsPlaying then
			if dashState.velocityConnection then
				dashState.velocityConnection:Disconnect()
				dashState.velocityConnection = nil
			end
			return
		end

		if not hrp or not hrp.Parent then
			if dashState.velocityConnection then
				dashState.velocityConnection:Disconnect()
				dashState.velocityConnection = nil
			end
			return
		end

		-- Limitar a duração do impulso físico
		if (tick() - tempoInicio) >= duracaoDash then
			if dashState.velocityConnection then
				dashState.velocityConnection:Disconnect()
				dashState.velocityConnection = nil
			end
			return
		end

		local velocidadeAtual = hrp.AssemblyLinearVelocity
		local velocidadeAlvo = dirVector * forcaDash

		hrp.AssemblyLinearVelocity = Vector3.new(velocidadeAlvo.X, velocidadeAtual.Y, velocidadeAlvo.Z)

		if direcao == "Tras" then
			hrp.CFrame = startRotation + hrp.Position
		end
	end)
end

local function PararImpulsoDash()
	if dashState.velocityConnection then
		dashState.velocityConnection:Disconnect()
		dashState.velocityConnection = nil
	end
	if dashState.impulsoTimer then
		pcall(task.cancel, dashState.impulsoTimer)
		dashState.impulsoTimer = nil
	end
end

local function OnDashAnimacaoTerminou()
	DebugPrint("[ControladorEstado] Dash animação terminou")

	PararImpulsoDash()

	dashState.animacao = nil
	dashState.direcao = "Tras"
	movementFlags.isDashing = false
	ClientBridge.CFrameRotacaoDash = nil
	ClientBridge.PreDashActive = nil

	if dashState.conexaoTermino then
		dashState.conexaoTermino:Disconnect()
		dashState.conexaoTermino = nil
	end

	if dashState.earlyCancelTimer then
		pcall(task.cancel, dashState.earlyCancelTimer)
		dashState.earlyCancelTimer = nil
	end

	dashState.earlyCancelExecutado = false

	TentarAcao:FireServer("DashTerminou")

	estadoAtual.estadoAcao = "Nenhuma"

	if isShiftHeld then
		movementFlags.isRunning = true
		estadoAtual.estadoMov = "Correndo"
		estadoAtual.correndo = true
	end

	AtualizarVelocidadeLocal()

	AtualizarAnimacaoMovimento()
end

export type AttackImpulseState = {
	connection: RBXScriptConnection?,
	endTime: number,
}
local attackImpulseState: AttackImpulseState = {
	connection = nil,
	endTime = 0,
}

local function PararImpulsoAtaque()
	if attackImpulseState.connection then
		attackImpulseState.connection:Disconnect()
		attackImpulseState.connection = nil
	end
end

local function AplicarImpulsoAtaque(tipoAtaque: string)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	PararImpulsoAtaque()

	local magnitude
	local duracao

	if tipoAtaque == "AtaqueLeveFinal" then
		magnitude = Modulo_Configuracoes.ObterConfiguracao("MagnitudeImpulsoAtaqueFinal") or 25
		duracao = Modulo_Configuracoes.ObterConfiguracao("DuracaoImpulsoAtaqueFinal") or 0.1
	else
		magnitude = Modulo_Configuracoes.ObterConfiguracao("MagnitudeImpulsoAtaqueLeve") or 15
		duracao = Modulo_Configuracoes.ObterConfiguracao("DuracaoImpulsoAtaqueLeve") or 0.1
	end

	attackImpulseState.endTime = tick() + duracao

	local direcaoAtaque = hrp.CFrame.LookVector
	direcaoAtaque = Vector3.new(direcaoAtaque.X, 0, direcaoAtaque.Z).Unit

	attackImpulseState.connection = RunService.RenderStepped:Connect(function(_deltaTime)
		if tick() >= attackImpulseState.endTime then
			PararImpulsoAtaque()
			return
		end

		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not rootPart then
			PararImpulsoAtaque()
			return
		end

		local velocidadeAtual = rootPart.AssemblyLinearVelocity
		local velocidadeAlvo = direcaoAtaque * magnitude

		rootPart.AssemblyLinearVelocity = Vector3.new(velocidadeAlvo.X, velocidadeAtual.Y, velocidadeAlvo.Z)
	end)

	DebugPrint(
		string.format(
			"[ControladorEstado] Impulso de ataque iniciado: %s (magnitude: %.1f, duração: %.2fs)",
			tipoAtaque,
			magnitude,
			duracao
		)
	)
end

ClientBridge.AplicarImpulsoAtaque = AplicarImpulsoAtaque

local function AplicarKnockbackRecebido(direcao: Vector3, magnitude: number)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	direcao = Vector3.new(direcao.X, 0, direcao.Z).Unit

	local velocidadeAtual = hrp.AssemblyLinearVelocity
	-- Knockback puramente horizontal: sem elevacao Y para evitar pulinhos.
	hrp.AssemblyLinearVelocity = Vector3.new(direcao.X * magnitude, velocidadeAtual.Y, direcao.Z * magnitude)

	DebugPrint(string.format("[ControladorEstado] Knockback recebido: magnitude=%.1f", magnitude))
end

local AplicarKnockbackRemote = Remotos:FindFirstChild("AplicarKnockback")
if AplicarKnockbackRemote then
	ConectarGlobal(AplicarKnockbackRemote.OnClientEvent, function(direcao, magnitude)
		AplicarKnockbackRecebido(direcao, magnitude)
	end)
end

local function CalcularMultiplicadorDirecao(): number
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return 1
	end

	local moveDir = humanoid.MoveDirection
	if moveDir.Magnitude < 0.1 then
		return direcaoAtual
	end

	local lookVector = hrp.CFrame.LookVector
	local lookXZ = Vector3.new(lookVector.X, 0, lookVector.Z).Unit
	local moveXZ = Vector3.new(moveDir.X, 0, moveDir.Z).Unit

	local dot = lookXZ:Dot(moveXZ)

	if dot < -0.1 then
		return -1
	elseif dot > 0.1 then
		return 1
	else
		return direcaoAtual
	end
end

local function CalcularMovimentoLateral(): (string, number)
	local shiftLockOnOuFirstPerson = (
		UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
		or player.CameraMode == Enum.CameraMode.LockFirstPerson
	)

	if not shiftLockOnOuFirstPerson then
		return "Nenhum", 1
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return "Nenhum", 1
	end

	local moveDir = humanoid.MoveDirection
	if moveDir.Magnitude < 0.1 then
		return "Nenhum", 1
	end

	local lookVector = hrp.CFrame.LookVector
	local rightVector = hrp.CFrame.RightVector
	local lookXZ = Vector3.new(lookVector.X, 0, lookVector.Z).Unit
	local rightXZ = Vector3.new(rightVector.X, 0, rightVector.Z).Unit
	local moveXZ = Vector3.new(moveDir.X, 0, moveDir.Z).Unit

	local dotForward = lookXZ:Dot(moveXZ)
	local dotRight = rightXZ:Dot(moveXZ)

	local thresholdLateral = 0.3
	local thresholdFrontal = 0.3

	local temComponenteLateral = math.abs(dotRight) > thresholdLateral
	local temComponenteFrontal = math.abs(dotForward) > thresholdFrontal

	if not temComponenteLateral then
		return "Nenhum", 1
	end

	local indoParaDireita = dotRight > 0
	local indoParaFrente = dotForward > 0

	local emCombate = (
		estadoAtual.estadoAcao == "AtacandoLeve"
		or estadoAtual.estadoAcao == "Defendendo"
		or estadoAtual.bloqueando
	)

	local podeCorrer = movementFlags.isRunning and not emCombate
	local prefixo = podeCorrer and "Correndo" or "Andando"

	if temComponenteFrontal then
		if indoParaDireita then
			if indoParaFrente then
				return prefixo .. "Direita", 1
			else
				return prefixo .. "Esquerda", -1
			end
		else
			if indoParaFrente then
				return prefixo .. "Esquerda", 1
			else
				return prefixo .. "Direita", -1
			end
		end
	else
		if indoParaDireita then
			return prefixo .. "Direita", 1
		else
			return prefixo .. "Esquerda", 1
		end
	end
end

local function DefinirVelocidadeMovimento(velocidadeBase: number)
	if not animacaoAtualMov or not animacaoAtualMov.IsPlaying then
		return
	end

	if animacaoUsaDirecao then
		local mult = CalcularMultiplicadorDirecao()
		velocidadeAnimacaoAlvo = velocidadeBase * mult
	else
		animacaoAtualMov:AdjustSpeed(velocidadeBase)
	end
end

ObterAnimacao = function(animId: string): AnimationTrack?
	if animacoesCarregadas[animId] then
		return animacoesCarregadas[animId]
	end

	local animacao = Instance.new("Animation")
	animacao.AnimationId = animId

	local sucesso, track = pcall(function()
		return animator:LoadAnimation(animacao)
	end)

	if sucesso and track then
		animacoesCarregadas[animId] = track
		return track
	end

	return nil
end

PararAnimacaoMov = function(forcarParar: boolean?)
	if animacaoAtualMov then
		if timerPararAnimacao then
			pcall(task.cancel, timerPararAnimacao)
			timerPararAnimacao = nil
		end

		if forcarParar then
			if ANIMACOES_COM_DIRECAO[ultimaAnimacaoMovNome] then
				walkCycleState.time = animacaoAtualMov.TimePosition
				walkCycleState.speed = velocidadeAnimacaoAtual
				walkCycleState.lastWalkAnimName = ultimaAnimacaoMovNome
			end

			animacaoAtualMov:Stop(TIMINGS.MoveFadeOut)
			animacaoAtualMov = nil
			animacaoMovPausada = false
			ultimaAnimacaoMovNome = nil
		else
			animacaoMovPausada = true
			velocidadeAnimacaoAlvo = 0

			timerPararAnimacao = task.delay(TEMPO_MANTER_ANIMACAO, function()
				if animacaoMovPausada and animacaoAtualMov then
					if ANIMACOES_COM_DIRECAO[ultimaAnimacaoMovNome] then
						walkCycleState.time = animacaoAtualMov.TimePosition
						walkCycleState.speed = velocidadeAnimacaoAtual
						walkCycleState.lastWalkAnimName = ultimaAnimacaoMovNome
					end

					animacaoAtualMov:Stop(TIMINGS.MoveFadeOut)
					animacaoAtualMov = nil
					animacaoMovPausada = false
					ultimaAnimacaoMovNome = nil

					AtualizarAnimacaoMovimento()
				end
				timerPararAnimacao = nil
			end)
		end
	end
end

local function PararAnimacaoAcao()
	GerenciadorHitboxCliente.PararTodas()

	if comboState.animacaoAtiva then
		LimparConexoesMarkers()
		comboState.animacaoAtiva = nil
		comboState.janelaAtiva = false
		comboState.indiceAtual = 0
		comboState.continuarCombo = false
		comboState.pendingConsume = false
		comboState.token = 0
	end

	if animacaoAtualAcao then
		if animacaoAtualAcao.IsPlaying then
			animacaoAtualAcao:AdjustSpeed(0)
		end
		animacaoAtualAcao:Stop(TIMINGS.ActionFadeOut)
		animacaoAtualAcao = nil
	end
end

local function LimparJumpAnimState()
	if jumpAnimState.conexaoTermino then
		jumpAnimState.conexaoTermino:Disconnect()
		jumpAnimState.conexaoTermino = nil
	end
	jumpAnimState.animacao = nil
	jumpAnimState.aguardandoTermino = false
end

local function OnJumpAnimacaoTerminou()
	DebugPrint("[ControladorEstado] Animação de Pulando terminou completamente")

	LimparJumpAnimState()

	if parkourState.ativo then
		movementFlags.isJumping = false
		DebugPrint("[ControladorEstado] OnJumpAnimacaoTerminou ignorado: parkour ativo")
		return
	end

	if movementFlags.isJumping or movementFlags.isFalling then
		movementFlags.isJumping = false
		movementFlags.isFalling = true
		estadoAtual.estadoMov = "Caindo"

		pcall(function()
			TentarAcao:FireServer("SincronizarMovimento", "Caindo")
		end)
		AtualizarAnimacaoMovimento()
		DebugPrint("[ControladorEstado] Transitando para Caindo após animação de pulo")
	end
end

local function TocarAnimacaoMov(nomeAnimacao: string, velocidadeBase: number?)
	local animId = Modulo_Configuracoes.ObterIdAnimacao(estadoAtual.modoAnimacao, nomeAnimacao)
	if not animId then
		return
	end

	local track = ObterAnimacao(animId)
	if not track then
		return
	end

	local usaDirecao = ANIMACOES_COM_DIRECAO[nomeAnimacao] == true
	local velocidade = velocidadeBase or 1

	local deveLoop = not ANIMACOES_SEM_LOOP[nomeAnimacao]

	if timerPararAnimacao then
		pcall(task.cancel, timerPararAnimacao)
		timerPararAnimacao = nil
	end

	if nomeAnimacao ~= "Pulando" then
		LimparJumpAnimState()
	end

	local mesmaAnimacao = (animacaoAtualMov == track)
		or (ultimaAnimacaoMovNome == nomeAnimacao and animacaoAtualMov and animacaoAtualMov.IsPlaying)

	if mesmaAnimacao and animacaoAtualMov and animacaoAtualMov.IsPlaying then
		animacaoMovPausada = false
		animacaoUsaDirecao = usaDirecao

		if not usaDirecao then
			velocidadeAnimacaoAlvo = velocidade
		else
			velocidadeAnimacaoAlvo = velocidade * CalcularMultiplicadorDirecao()
		end
		return
	end

	if animacaoAtualMov and animacaoAtualMov ~= track then
		PararAnimacaoMov(true)
	end

	if not animacaoAtualMov or not animacaoAtualMov.IsPlaying then
		local tempoParaRestaurar = 0
		if usaDirecao then
			if walkCycleState.time > 0 then
				tempoParaRestaurar = walkCycleState.time

				local multAtual = CalcularMultiplicadorDirecao()
				local multAntigo = walkCycleState.speed > 0 and 1 or -1
				if multAtual ~= multAntigo then
					tempoParaRestaurar = track.Length - (tempoParaRestaurar % track.Length)
				end
			end
		end

		track.Priority = Enum.AnimationPriority.Movement
		track.Looped = deveLoop

		local fadeIn = TIMINGS.MoveFadeIn
		local eraAndando = ultimaAnimacaoMovNome == "Andando"
		if eraAndando and nomeAnimacao == "Correndo" then
			fadeIn = 0.55
		elseif ultimaAnimacaoMovNome == "Correndo" and nomeAnimacao == "Andando" then
			fadeIn = 0.35
		end
		track:Play(fadeIn)

		if tempoParaRestaurar > 0 then
			track.TimePosition = tempoParaRestaurar % track.Length
			walkCycleState.time = 0
		end

		if usaDirecao then
			local mult = CalcularMultiplicadorDirecao()

			if direcaoAtual ~= 0 then
				mult = direcaoAtual
			end
			local velocidadeInicial = velocidade * mult
			track:AdjustSpeed(velocidadeInicial)
			velocidadeAnimacaoAtual = velocidadeInicial
		else
			track:AdjustSpeed(velocidade)
			velocidadeAnimacaoAtual = velocidade
		end

		if nomeAnimacao == "Pulando" then
			LimparJumpAnimState()
			jumpAnimState.animacao = track
			jumpAnimState.aguardandoTermino = true
			jumpAnimState.conexaoTermino = track.Stopped:Connect(OnJumpAnimacaoTerminou)
			DebugPrint("[ControladorEstado] Animação de Pulando iniciada (sem loop, aguardando término)")
		end

		animacaoAtualMov = track
	end

	animacaoUsaDirecao = usaDirecao
	animacaoMovPausada = false
	ultimaAnimacaoMovNome = nomeAnimacao

	if usaDirecao then
		local mult = CalcularMultiplicadorDirecao()
		velocidadeAnimacaoAlvo = velocidade * mult
	else
		velocidadeAnimacaoAlvo = velocidade
	end
end

function ClientBridge.SoltouM1()
	if comboState.animacaoAtiva and comboState.carregando then
		comboState.carregando = false
		LimparConexaoCarga()

		local track = comboState.animacaoAtiva
		local janelaCarga = Modulo_Configuracoes.ObterConfiguracao("JanelaCargaLeve") or 0.25
		local multMax = Modulo_Configuracoes.ObterConfiguracao("MultiplicadorDanoMaximoCarga") or 1.2

		-- Calcula proporção da carga
		local tempoCargaDecorrido = track.TimePosition - (comboState.tempoInicioCarga or 0)
		local ratio = math.clamp(tempoCargaDecorrido / janelaCarga, 0, 1)
		comboState.multiplicadorDano = 1.0 + ratio * (multMax - 1.0)

		track:AdjustSpeed(1.0)
		TentarAcao:FireServer("AjustarVelocidadeAnimacao", { velocidade = 1.0 })

		DebugPrint(
			string.format(
				"[ControladorEstado] M1 solto - Carga finalizada: ratio=%.2f, mult=%.2f",
				ratio,
				comboState.multiplicadorDano
			)
		)
	end
end

local function TocarAnimacaoAcao(animId: string, loop: boolean, velocidade: number, nomeAnimacao: string?)
	if parkourState.ativo then
		return
	end

	local track = ObterAnimacao(animId)
	if not track then
		return
	end

	local ehEquipar = nomeAnimacao and (nomeAnimacao == "Equipar" or nomeAnimacao == "Desequipar")

	local ehRoll = nomeAnimacao and (nomeAnimacao:match("^Roll"))
	local ehDash = nomeAnimacao and (nomeAnimacao:match("^Dash"))

	if ehEquipar and equipAnimState.animacao and equipAnimState.animacao.IsPlaying then
		DebugPrint("[ControladorEstado] Já há animação de equip tocando, ignorando")
		return
	end

	PararAnimacaoAcao()

	track.Priority = if nomeAnimacao == "DefesaQuebrada"
		then Enum.AnimationPriority.Movement
		else Enum.AnimationPriority.Action
	track.Looped = loop
	local fadeTime = if ehRoll then 0.2 else 0.1
	track:Play(fadeTime)
	track:AdjustSpeed(velocidade)

	animacaoAtualAcao = track

	-- ======== ROLL (esquiva rolando no chão) ========
	if ehRoll then
		ClientBridge.PreRollActive = nil
		ClientBridge.UltimoRollTime = tick()
		if rollState.conexaoTermino then
			rollState.conexaoTermino:Disconnect()
		end
		PararImpulsoRoll()
		PararAnimacaoMov(true)

		local direcao = "Frente"
		if nomeAnimacao == "RollFrente" then
			direcao = "Frente"
		elseif nomeAnimacao == "RollTras" then
			direcao = "Tras"
		elseif nomeAnimacao == "RollEsquerda" then
			direcao = "Esquerda"
		elseif nomeAnimacao == "RollDireita" then
			direcao = "Direita"
		end

		rollState.animacao = track
		rollState.direcao = direcao
		movementFlags.isRolling = true

		rollState.conexaoTermino = track.Stopped:Connect(function()
			OnRollAnimacaoTerminou()
		end)

		IniciarImpulsoRoll(direcao)

		DebugPrint("[ControladorEstado] Animação de Roll iniciada:", nomeAnimacao)

		if rollState.earlyCancelTimer then
			pcall(task.cancel, rollState.earlyCancelTimer)
			rollState.earlyCancelTimer = nil
		end
		rollState.earlyCancelExecutado = false

		if rollState.animacao and rollState.animacao.IsPlaying then
			local rollTrack = rollState.animacao
			local janelaEarlyCancel = Modulo_Configuracoes.ObterConfiguracao("JanelaCancelamentoRoll") or 0.2
			local tempoRestante = (rollTrack.Length - rollTrack.TimePosition) / rollTrack.Speed

			if tempoRestante > janelaEarlyCancel and janelaEarlyCancel > 0 then
				local tempoParaEarlyCancel = tempoRestante - janelaEarlyCancel
				DebugPrint(
					string.format(
						"[ControladorEstado] Roll early cancel agendado: %.2fs restante, early cancel em %.2fs",
						tempoRestante,
						tempoParaEarlyCancel
					)
				)

				rollState.earlyCancelTimer = task.delay(tempoParaEarlyCancel, function()
					if rollState.animacao and rollState.animacao.IsPlaying and not rollState.earlyCancelExecutado then
						rollState.earlyCancelExecutado = true
						DebugPrint("[ControladorEstado] Roll early cancel executado - mudando estado para Normal")

						estadoAtual.estadoAcao = "Nenhuma"

						TentarAcao:FireServer("RollEarlyCancel")

						if isShiftHeld then
							movementFlags.isRunning = true
							estadoAtual.estadoMov = "Correndo"
							estadoAtual.correndo = true
						end

						AtualizarVelocidadeLocal()

						AtualizarAnimacaoMovimento()
					end
				end)
			end
		end
		return
	end

	-- ======== DASH (impulso rápido lateral/trás) ========
	if ehDash then
		ClientBridge.PreDashActive = nil
		ClientBridge.UltimoDashTime = tick()
		if dashState.conexaoTermino then
			dashState.conexaoTermino:Disconnect()
		end
		PararImpulsoDash()
		PararAnimacaoMov(true)

		local direcao = "Tras"
		if nomeAnimacao == "DashTras" then
			direcao = "Tras"
		elseif nomeAnimacao == "DashEsquerda" then
			direcao = "Esquerda"
		elseif nomeAnimacao == "DashDireita" then
			direcao = "Direita"
		end

		dashState.animacao = track
		dashState.direcao = direcao
		movementFlags.isDashing = true

		dashState.conexaoTermino = track.Stopped:Connect(function()
			OnDashAnimacaoTerminou()
		end)

		IniciarImpulsoDash(direcao)

		DebugPrint("[ControladorEstado] Animação de Dash iniciada:", nomeAnimacao)

		if dashState.earlyCancelTimer then
			pcall(task.cancel, dashState.earlyCancelTimer)
			dashState.earlyCancelTimer = nil
		end
		dashState.earlyCancelExecutado = false

		if dashState.animacao and dashState.animacao.IsPlaying then
			local dashTrack = dashState.animacao
			local janelaEarlyCancel = Modulo_Configuracoes.ObterConfiguracao("JanelaCancelamentoDash") or 0.1
			local tempoRestante = (dashTrack.Length - dashTrack.TimePosition) / dashTrack.Speed

			if tempoRestante > janelaEarlyCancel and janelaEarlyCancel > 0 then
				local tempoParaEarlyCancel = tempoRestante - janelaEarlyCancel
				DebugPrint(
					string.format(
						"[ControladorEstado] Dash early cancel agendado: %.2fs restante, early cancel em %.2fs",
						tempoRestante,
						tempoParaEarlyCancel
					)
				)

				dashState.earlyCancelTimer = task.delay(tempoParaEarlyCancel, function()
					if dashState.animacao and dashState.animacao.IsPlaying and not dashState.earlyCancelExecutado then
						dashState.earlyCancelExecutado = true
						DebugPrint("[ControladorEstado] Dash early cancel executado - mudando estado para Normal")

						estadoAtual.estadoAcao = "Nenhuma"

						TentarAcao:FireServer("DashEarlyCancel")

						if isShiftHeld then
							movementFlags.isRunning = true
							estadoAtual.estadoMov = "Correndo"
							estadoAtual.correndo = true
						end

						AtualizarVelocidadeLocal()

						AtualizarAnimacaoMovimento()
					end
				end)
			end
		end
		return
	end

	if ehEquipar then
		if equipAnimState.conexaoTermino then
			equipAnimState.conexaoTermino:Disconnect()
		end

		local ehEquiparDirecao = (nomeAnimacao == "Equipar")

		equipAnimState.animacao = track

		equipAnimState.direcao = ehEquiparDirecao and 1 or -1
		equipAnimState.tempoInicio = tick()

		if ehEquiparDirecao then
			equipAnimState.acessorioJaClonado = false
		end

		ConfigurarMarkersEquip(track, ehEquiparDirecao)

		equipAnimState.conexaoTermino = track.Stopped:Connect(function()
			OnEquipAnimacaoTerminou()
		end)

		DebugPrint(
			"[ControladorEstado] Animação de",
			nomeAnimacao,
			"iniciada (direção:",
			equipAnimState.direcao,
			")"
		)
		return
	end

	local ehCombo = nomeAnimacao and (nomeAnimacao == "AtaqueLeve" or nomeAnimacao:match("^AtaqueLeve"))
	local combo = Modulo_Configuracoes.ObterConfiguracaoCombo(estadoAtual.modoAnimacao)

	if ehCombo and combo and nomeAnimacao then
		ultimoTempoHitboxAtivou = 0
		comboState.animacaoAtiva = track
		comboState.janelaAtiva = false
		comboState.indiceAtual = 1
		comboState.continuarCombo = false
		comboState.tempoInicio = tick()

		comboState.tempoInicioCarga = 0
		comboState.carregando = false
		comboState.multiplicadorDano = 1.0
		LimparConexaoCarga()

		comboState.token = comboState.token + 1
		local myToken = comboState.token

		track:AdjustSpeed(velocidade)
		DebugPrint("[ControladorEstado] Animação de combo iniciada (NORMAL)")

		task.delay(0.12, function()
			if comboState.token ~= myToken or not track or not track.IsPlaying then
				return
			end
			local aindaSegurando = ClientBridge.EstaSegurandoM1 and ClientBridge.EstaSegurandoM1()
			if aindaSegurando then
				comboState.carregando = true
				comboState.tempoInicioCarga = track.TimePosition
				local velCarga = Modulo_Configuracoes.ObterConfiguracao("VelocidadeCargaAtaque") or 0.4
				track:AdjustSpeed(velCarga)
				IniciarMonitorCarga(track)
				TentarAcao:FireServer("AjustarVelocidadeAnimacao", { velocidade = velCarga })
				DebugPrint("[ControladorEstado] Carga de combo ativada após hold")
			end
		end)

		ConfigurarMarkersCombo(track)
		return
	end
end

local function ObterMultiplicadorVelocidadeAnimacao(): number
	local estado = estadoAtual.estadoMov
	local multiplicador = 1

	if estado == "Correndo" and (movementFlags.isJumping or movementFlags.isFalling) then
		multiplicador = TIMINGS.RunInAirSpeed
	end

	if estado == "Andando" then
		local emDefendendo = (estadoAtual.estadoAcao == "Defendendo")
		local emAtacando = (estadoAtual.estadoAcao == "AtacandoLeve")

		if emDefendendo then
			multiplicador = 0.55
		elseif emAtacando then
			multiplicador = 0.85
		end
	end

	if estadoAtual.agachado and estado == "Andando" then
		multiplicador = 0.8
	end

	local walkSpeed = humanoid.WalkSpeed
	local baseAnim: number? = nil

	if estadoAtual.agachado and (estado == "Andando" or estado == "Parado") then
		baseAnim = Modulo_Configuracoes.ObterConfiguracao("VelocidadeBaseAnimAgachando") or 9
	elseif estadoAtual.bloqueando or estadoAtual.estadoAcao == "Defendendo" then
		baseAnim = Modulo_Configuracoes.ObterConfiguracao("VelocidadeBaseAnimBloqueando") or 6
	elseif estado == "Correndo" then
		baseAnim = Modulo_Configuracoes.ObterConfiguracao("VelocidadeBaseAnimCorrendo") or 21
	elseif estado == "Andando" then
		baseAnim = Modulo_Configuracoes.ObterConfiguracao("VelocidadeBaseAnimAndando") or 14
	end

	if baseAnim and baseAnim > 0 then
		local ratio = walkSpeed / baseAnim
		local delta = ratio - 1
		local adjustedRatio = 1 + delta * 1.05
		multiplicador = multiplicador * math.max(0.3, adjustedRatio)
	end

	return multiplicador
end

AtualizarAnimacaoMovimento = function()
	if movementFlags.isRolling or movementFlags.isDashing then
		return
	end

	if parkourState.ativo then
		if estadoAtual.estadoAcao ~= "Parkour" then
			estadoAtual.estadoAcao = "Parkour"
		end
		if estadoAtual.estadoMov ~= "Parkour" then
			estadoAtual.estadoMov = "Parkour"
		end
		SincronizarStatusLocal()
		return
	end

	SincronizarStatusLocal()

	local estado = estadoAtual.estadoMov
	local velocidade = ObterMultiplicadorVelocidadeAnimacao()

	local mapaAnimacoes = {
		Parado = "Idle",
		Andando = "Andando",
		Correndo = "Correndo",
		Pulando = "Pulando",
		Caindo = "Caindo",
		Escalando = "Escalando",
		Nadando = "Nadando",
		Agachado = "Idle",
	}

	local nomeAnimacao
	if estadoAtual.agachado then
		if estado == "Andando" then
			nomeAnimacao = "AndandoAgachado"
		else
			nomeAnimacao = "IdleAgachado"
		end
	else
		nomeAnimacao = mapaAnimacoes[estado] or "Idle"
	end

	if movementFlags.isRunning and (nomeAnimacao == "Pulando" or nomeAnimacao == "Caindo") then
		if DEBUG_ENABLED then
			print(string.format("[DEBUG] GUARD: Bloqueando %s enquanto corre -> forçando Correndo", nomeAnimacao))
		end
		nomeAnimacao = "Correndo"
		estadoAtual.estadoMov = "Correndo"
		velocidade = TIMINGS.RunInAirSpeed
	end

	local animacaoQueUsaDirecao = ANIMACOES_COM_DIRECAO[ultimaAnimacaoMovNome]
	local querIdle = (nomeAnimacao == "Idle" or nomeAnimacao == "IdleAgachado")

	if querIdle then
		if animacaoQueUsaDirecao and animacaoAtualMov and animacaoAtualMov.IsPlaying and not animacaoMovPausada then
			PararAnimacaoMov(false)
		elseif not animacaoMovPausada then
			PararAnimacaoMov(true)
		end
		return
	end

	if (nomeAnimacao == "Andando" or nomeAnimacao == "Correndo") and not estadoAtual.agachado then
		local tipoLateral, velocidadeLateral = CalcularMovimentoLateral()
		if tipoLateral ~= "Nenhum" then
			if ultimaAnimacaoMovNome == tipoLateral and animacaoAtualMov and animacaoAtualMov.IsPlaying then
				velocidadeAnimacaoAlvo = velocidadeLateral * velocidade
				return
			end

			local tempoDesdeUltimaTroca = tick() - ultimaTrocaLateralTime
			if tempoDesdeUltimaTroca < DEBOUNCE_TROCA_LATERAL then
				if
					ultimaAnimacaoMovNome == "AndandoDireita"
					or ultimaAnimacaoMovNome == "AndandoEsquerda"
					or ultimaAnimacaoMovNome == "CorrendoDireita"
					or ultimaAnimacaoMovNome == "CorrendoEsquerda"
				then
					velocidadeAnimacaoAlvo = velocidadeLateral * velocidade
				end
				return
			end

			local tempoAtual = 0
			local velocidadeAnterior = velocidadeAnimacaoAtual

			local animacaoAtualEhDirecional = animacaoAtualMov
				and animacaoAtualMov.IsPlaying
				and ultimaAnimacaoMovNome
				and ANIMACOES_COM_DIRECAO[ultimaAnimacaoMovNome]

			if animacaoAtualEhDirecional then
				tempoAtual = animacaoAtualMov.TimePosition
				velocidadeAnterior = animacaoAtualMov.Speed
			elseif walkCycleState.time > 0 then
				tempoAtual = walkCycleState.time
				velocidadeAnterior = walkCycleState.speed
			end

			local animId = Modulo_Configuracoes.ObterIdAnimacao(estadoAtual.modoAnimacao, tipoLateral)
			if animId then
				local track = ObterAnimacao(animId)
				if track then
					if animacaoAtualMov and animacaoAtualMov ~= track then
						PararAnimacaoMov(true)
					end

					track.Priority = Enum.AnimationPriority.Movement
					track.Looped = true
					track:Play(TIMINGS.MoveFadeIn)

					if tempoAtual > 0 then
						local tempoAlvo = tempoAtual

						local estaEmReverso = velocidadeLateral < 0
						local estavaEmReverso = velocidadeAnterior < 0

						if estaEmReverso ~= estavaEmReverso then
							tempoAlvo = track.Length - (tempoAtual % track.Length)
						end
						track.TimePosition = tempoAlvo % track.Length
						walkCycleState.time = 0
					end

					local velocidadeFinalScale = velocidadeLateral * velocidade
					track:AdjustSpeed(velocidadeFinalScale)
					velocidadeAnimacaoAtual = velocidadeFinalScale
					velocidadeAnimacaoAlvo = velocidadeFinalScale

					animacaoAtualMov = track
					animacaoUsaDirecao = true
					animacaoMovPausada = false
					ultimaAnimacaoMovNome = tipoLateral

					direcaoAtual = velocidadeLateral > 0 and 1 or -1
					ultimaTrocaLateralTime = tick()
				end
			end
			return
		else
			local emAnimacaoLateral = (
				ultimaAnimacaoMovNome == "AndandoDireita"
				or ultimaAnimacaoMovNome == "AndandoEsquerda"
				or ultimaAnimacaoMovNome == "CorrendoDireita"
				or ultimaAnimacaoMovNome == "CorrendoEsquerda"
			)
			if emAnimacaoLateral then
				local tempoAtual = 0
				local velocidadeAnterior = velocidadeAnimacaoAtual

				local animacaoAtualEhDirecional = animacaoAtualMov
					and animacaoAtualMov.IsPlaying
					and ultimaAnimacaoMovNome
					and ANIMACOES_COM_DIRECAO[ultimaAnimacaoMovNome]

				if animacaoAtualEhDirecional then
					tempoAtual = animacaoAtualMov.TimePosition
					velocidadeAnterior = animacaoAtualMov.Speed
				elseif walkCycleState.time > 0 then
					tempoAtual = walkCycleState.time
					velocidadeAnterior = walkCycleState.speed
				end

				TocarAnimacaoMov(nomeAnimacao, velocidade)

				if animacaoAtualMov and tempoAtual > 0 then
					local tempoAlvo = tempoAtual
					local estaEmReverso = velocidadeAnimacaoAtual < 0
					local estavaEmReverso = velocidadeAnterior < 0
					if estaEmReverso ~= estavaEmReverso then
						tempoAlvo = animacaoAtualMov.Length - (tempoAtual % animacaoAtualMov.Length)
					end
					animacaoAtualMov.TimePosition = tempoAlvo % animacaoAtualMov.Length
					walkCycleState.time = 0
				end
				return
			end
		end
	end

	TocarAnimacaoMov(nomeAnimacao, velocidade)
end

local function ProcessarSincronizacao(entidade: Model, dados)
	if entidade ~= character then
		return
	end

	local acaoAnterior = estadoAtual.estadoAcao
	local modoAnterior = estadoAtual.modoAnimacao
	local estadoMovAnterior = estadoAtual.estadoMov
	local bloqueandoAnterior = estadoAtual.bloqueando
	local agachadoAnterior = estadoAtual.agachado
	local correndoAnterior = estadoAtual.correndo

	estadoAtual.estadoMov = dados.estadoMov
	estadoAtual.estadoAcao = dados.estadoAcao
	estadoAtual.modoAnimacao = dados.modoAnimacao
	estadoAtual.bloqueando = dados.bloqueando
	estadoAtual.agachado = dados.agachado
	estadoAtual.correndo = dados.correndo

	if parkourState.ativo then
		estadoAtual.estadoAcao = "Parkour"
		estadoAtual.estadoMov = "Parkour"
		SincronizarStatusLocal()
		return
	end

	local movimentoMudou = estadoMovAnterior ~= estadoAtual.estadoMov
		or bloqueandoAnterior ~= estadoAtual.bloqueando
		or agachadoAnterior ~= estadoAtual.agachado
		or correndoAnterior ~= estadoAtual.correndo
		or acaoAnterior ~= estadoAtual.estadoAcao

	if movimentoMudou then
		AtualizarVelocidadeLocal()
	end

	AtualizarBaseIdle()

	local modoMudou = modoAnterior ~= estadoAtual.modoAnimacao
	if modoMudou and animacaoAtualMov then
		if movementFlags.isJumping or movementFlags.isFalling then
			ultimaAnimacaoMovNome = nil
		else
			PararAnimacaoMov(true)
		end
	end

	if estadoAtual.estadoAcao == "AtacandoLeve" or estadoAtual.estadoAcao == "Defendendo" then
		movementFlags.isRunning = false

		AtualizarVelocidadeLocal()

		AtualizarAnimacaoMovimento()
	end

	if acaoAnterior ~= "Nenhuma" and estadoAtual.estadoAcao == "Nenhuma" then
		local foiEquipDesequip = (acaoAnterior == "Equipando" or acaoAnterior == "Desequipando")

		if foiEquipDesequip and animacaoAtualAcao and animacaoAtualAcao.IsPlaying then
			animacaoAtualAcao.Stopped:Once(function()
				animacaoAtualAcao = nil
				AtualizarAnimacaoMovimento()
			end)
		else
			PararAnimacaoAcao()
		end
	end

	if acaoAnterior == "AtacandoLeve" and estadoAtual.estadoAcao == "Nenhuma" then
		if isShiftHeld then
			movementFlags.isRunning = true

			estadoAtual.estadoMov = "Correndo"
			estadoAtual.correndo = true
		end

		AtualizarVelocidadeLocal()
		AtualizarAnimacaoMovimento()
	end

	if movementFlags.isRunning and (movementFlags.isJumping or movementFlags.isFalling) then
		DefinirVelocidadeMovimento(TIMINGS.RunInAirSpeed)
		return
	end

	AtualizarAnimacaoMovimento()

	if acaoAnterior == "Defendendo" and estadoAtual.estadoAcao == "Nenhuma" then
		if isShiftHeld then
			movementFlags.isRunning = true

			estadoAtual.estadoMov = "Correndo"
			estadoAtual.correndo = true
		end

		AtualizarVelocidadeLocal()
		AtualizarAnimacaoMovimento()
	end
end

function ClientBridge.EstaEmParkour()
	return parkourState.ativo
end

function ClientBridge.EntrarParkour()
	if parkourState.ativo then
		return
	end

	parkourState.ativo = true
	parkourState.estadoAcaoAnterior = estadoAtual.estadoAcao

	PararAnimacaoAcao()
	PararAnimacaoMov(true)

	estadoAtual.estadoAcao = "Parkour"
	estadoAtual.estadoMov = "Parkour"
	estadoAtual.correndo = false
	movementFlags.isRunning = false
	AtualizarVelocidadeLocal()
	SincronizarStatusLocal()
end

function ClientBridge.SairParkour()
	if not parkourState.ativo then
		return
	end

	parkourState.ativo = false

	if estadoAtual.estadoAcao == "Parkour" then
		estadoAtual.estadoAcao = "Nenhuma"
	end

	movementFlags.isJumping = false
	movementFlags.isFalling = false

	if humanoid.FloorMaterial == Enum.Material.Air then
		movementFlags.isFalling = true
		estadoAtual.estadoMov = "Caindo"
	elseif estadoAtual.estadoMov == "Parkour" then
		estadoAtual.estadoMov = "Parado"
	end

	if isShiftHeld then
		movementFlags.isRunning = true
		estadoAtual.correndo = true

		if
			humanoid.MoveDirection.Magnitude > 0.1
			and not movementFlags.isJumping
			and not movementFlags.isFalling
			and not movementFlags.isClimbing
			and not movementFlags.isSwimming
		then
			estadoAtual.estadoMov = "Correndo"
		end
	else
		movementFlags.isRunning = false
		estadoAtual.correndo = false
	end

	AtualizarVelocidadeLocal()
	AtualizarBaseIdle()
	AtualizarAnimacaoMovimento()
end

local function ProcessarTocarAnimacao(
	entidade: Model,
	animId: string,
	nomeAnimacao: string,
	loop: boolean,
	velocidade: number
)
	if entidade ~= character then
		return
	end

	TocarAnimacaoAcao(animId, loop, velocidade, nomeAnimacao)
end

local function AtualizarEstadoMovimento()
	if parkourState.ativo then
		if estadoAtual.estadoAcao ~= "Parkour" then
			estadoAtual.estadoAcao = "Parkour"
		end
		if estadoAtual.estadoMov ~= "Parkour" then
			estadoAtual.estadoMov = "Parkour"
		end
		SincronizarStatusLocal()
		return
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	if movementFlags.isClimbing then
		if estadoAtual.estadoMov ~= "Escalando" then
			estadoAtual.estadoMov = "Escalando"
			AtualizarAnimacaoMovimento()
		end
		return
	end

	if movementFlags.isSwimming then
		if estadoAtual.estadoMov ~= "Nadando" then
			estadoAtual.estadoMov = "Nadando"
			AtualizarAnimacaoMovimento()
		end
		return
	end

	if estadoAtual.agachado then
		local isMoving = humanoid.MoveDirection.Magnitude > 0.1
		local novo = isMoving and "Andando" or "Parado"
		if estadoAtual.estadoMov ~= novo then
			estadoAtual.estadoMov = novo
			AtualizarAnimacaoMovimento()
		end
		return
	end

	if movementFlags.isJumping or movementFlags.isFalling then
		local emCombate = (estadoAtual.estadoAcao == "AtacandoLeve" or estadoAtual.estadoAcao == "Defendendo")

		if movementFlags.isRunning and not emCombate then
			if estadoAtual.estadoMov ~= "Correndo" then
				estadoAtual.estadoMov = "Correndo"
			end

			DefinirVelocidadeMovimento(TIMINGS.RunInAirSpeed)
			return
		end

		if movementFlags.isFalling then
			if estadoAtual.estadoMov ~= "Caindo" then
				estadoAtual.estadoMov = "Caindo"
				AtualizarAnimacaoMovimento()
			end
		elseif movementFlags.isJumping then
			if estadoAtual.estadoMov ~= "Pulando" then
				estadoAtual.estadoMov = "Pulando"
				AtualizarAnimacaoMovimento()
			end
		end
		return
	end

	local isMoving = humanoid.MoveDirection.Magnitude > 0.1

	local emCombate = (estadoAtual.estadoAcao == "AtacandoLeve" or estadoAtual.estadoAcao == "Defendendo")

	local podeCorrer = movementFlags.isRunning and not emCombate

	local novoEstado
	if isMoving then
		novoEstado = podeCorrer and "Correndo" or "Andando"
	else
		novoEstado = "Parado"
	end

	if estadoAtual.estadoMov ~= novoEstado then
		if DEBUG_ENABLED then
			print(
				string.format(
					"[DEBUG] Heartbeat Change: %s -> %s | Jump: %s | Fall: %s | Floor: %s | MoveDir: %.2f",
					estadoAtual.estadoMov,
					novoEstado,
					tostring(movementFlags.isJumping),
					tostring(movementFlags.isFalling),
					tostring(humanoid.FloorMaterial),
					humanoid.MoveDirection.Magnitude
				)
			)
		end

		estadoAtual.estadoMov = novoEstado
		AtualizarAnimacaoMovimento()

		TentarAcao:FireServer("SincronizarMovimento", novoEstado)
	else
		if animacaoAtualMov then
			emCombate = (estadoAtual.estadoAcao == "AtacandoLeve" or estadoAtual.estadoAcao == "Defendendo")
			if not (estadoAtual.estadoMov == "Andando" and emCombate) then
				DefinirVelocidadeMovimento(1)
			end
		end
	end

	SincronizarStatusLocal()
end

local function _VerificarMaterialQueda()
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local material = humanoid.FloorMaterial

	if material == Enum.Material.Air then
		if estadoAtual.estadoMov ~= "Caindo" and estadoAtual.estadoMov ~= "Correndo" then
			estadoAtual.estadoMov = "Caindo"
			movementFlags.isFalling = true
			AtualizarAnimacaoMovimento()
		end
	else
		if movementFlags.isFalling or movementFlags.isJumping then
			movementFlags.isFalling = false
			movementFlags.isJumping = false
		end
	end
end

local function OnStateChanged(oldState, newState)
	if DEBUG_ENABLED then
		print(
			string.format(
				"[DEBUG] StateChanged: %s -> %s | Material: %s | isRunning: %s | isJumping: %s | isFalling: %s",
				tostring(oldState),
				tostring(newState),
				tostring(humanoid.FloorMaterial),
				tostring(movementFlags.isRunning),
				tostring(movementFlags.isJumping),
				tostring(movementFlags.isFalling)
			)
		)
	end

	if parkourState.ativo then
		return
	end

	movementFlags.isClimbing = (newState == Enum.HumanoidStateType.Climbing)
	movementFlags.isSwimming = (newState == Enum.HumanoidStateType.Swimming)

	if newState == Enum.HumanoidStateType.Jumping then
		movementFlags.isJumping = true
		movementFlags.isFalling = false

		if movementFlags.isRunning then
			estadoAtual.estadoMov = "Correndo"

			if animacaoAtualMov and animacaoAtualMov.IsPlaying then
				DefinirVelocidadeMovimento(TIMINGS.RunInAirSpeed)
			else
				AtualizarAnimacaoMovimento()
			end
			return
		end
	end

	if newState == Enum.HumanoidStateType.Freefall then
		if jumpAnimState.aguardandoTermino then
			return
		end

		movementFlags.isJumping = false
		movementFlags.isFalling = true

		if movementFlags.isRunning then
			estadoAtual.estadoMov = "Correndo"
			if animacaoAtualMov and animacaoAtualMov.IsPlaying then
				DefinirVelocidadeMovimento(TIMINGS.RunInAirSpeed)
			end
			return
		end
	end

	if
		newState == Enum.HumanoidStateType.Running
		or newState == Enum.HumanoidStateType.Landed
		or newState == Enum.HumanoidStateType.RunningNoPhysics
		or newState == Enum.HumanoidStateType.GettingUp
	then
		movementFlags.isJumping = false
		movementFlags.isFalling = false

		LimparJumpAnimState()

		if movementFlags.isRunning then
			estadoAtual.estadoMov = "Correndo"
			if animacaoAtualMov then
				local emCombate = (estadoAtual.estadoAcao == "AtacandoLeve" or estadoAtual.estadoAcao == "Defendendo")
				if not emCombate then
					DefinirVelocidadeMovimento(1)
				end
			end

			TentarAcao:FireServer("SincronizarMovimento", "Correndo")
			return
		end

		TentarAcao:FireServer("Aterrissar")
	end

	AtualizarEstadoMovimento()
end

humanoid.StateChanged:Connect(OnStateChanged)

ConectarGlobal(UserInputService.InputBegan, function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.LeftShift then
		movementFlags.isRunning = true
		isShiftHeld = true
		estadoAtual.correndo = true
		AtualizarVelocidadeLocal()
		AtualizarEstadoMovimento()
	end
end)

ConectarGlobal(UserInputService.InputEnded, function(input, _gameProcessed)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		movementFlags.isRunning = false
		isShiftHeld = false
		estadoAtual.correndo = false
		AtualizarVelocidadeLocal()
		AtualizarEstadoMovimento()
	end
end)

ConectarGlobal(SincronizarEstado.OnClientEvent, ProcessarSincronizacao)
ConectarGlobal(TocarAnimacao.OnClientEvent, ProcessarTocarAnimacao)

ConectarGlobal(RunService.Heartbeat, AtualizarEstadoMovimento)

local function AtualizarDirecaoAnimacao(deltaTime: number)
	if not animacaoAtualMov or not animacaoAtualMov.IsPlaying then
		return
	end

	if animacaoMovPausada then
		local velocidadePausaComDirecao = VELOCIDADE_PAUSA * direcaoAtual
		local diferenca = velocidadePausaComDirecao - velocidadeAnimacaoAtual
		if math.abs(diferenca) > 0.01 then
			velocidadeAnimacaoAtual = velocidadeAnimacaoAtual
				+ diferenca * math.min(1, deltaTime * SUAVIDADE_TRANSICAO_CORRENDO)
			animacaoAtualMov:AdjustSpeed(velocidadeAnimacaoAtual)
		elseif velocidadeAnimacaoAtual ~= velocidadePausaComDirecao then
			velocidadeAnimacaoAtual = velocidadePausaComDirecao
			animacaoAtualMov:AdjustSpeed(velocidadePausaComDirecao)
		end
		return
	end

	if not animacaoUsaDirecao then
		velocidadeAnimacaoAlvo = ObterMultiplicadorVelocidadeAnimacao()
		local diferenca = velocidadeAnimacaoAlvo - velocidadeAnimacaoAtual
		if math.abs(diferenca) > 0.01 then
			velocidadeAnimacaoAtual = velocidadeAnimacaoAtual
				+ diferenca * math.min(1, deltaTime * SUAVIDADE_TRANSICAO_DIRECAO)
			animacaoAtualMov:AdjustSpeed(velocidadeAnimacaoAtual)
		elseif velocidadeAnimacaoAtual ~= velocidadeAnimacaoAlvo then
			velocidadeAnimacaoAtual = velocidadeAnimacaoAlvo
			animacaoAtualMov:AdjustSpeed(velocidadeAnimacaoAtual)
		end
		return
	end

	if (estadoAtual.estadoMov == "Andando" or estadoAtual.estadoMov == "Correndo") and not estadoAtual.agachado then
		local tipoLateral, velocidadeLateral = CalcularMovimentoLateral()
		local emAnimacaoLateral = (
			ultimaAnimacaoMovNome == "AndandoDireita"
			or ultimaAnimacaoMovNome == "AndandoEsquerda"
			or ultimaAnimacaoMovNome == "CorrendoDireita"
			or ultimaAnimacaoMovNome == "CorrendoEsquerda"
		)

		if tipoLateral ~= "Nenhum" then
			if not emAnimacaoLateral or ultimaAnimacaoMovNome ~= tipoLateral then
				AtualizarAnimacaoMovimento()
				return
			else
				velocidadeAnimacaoAlvo = velocidadeLateral * ObterMultiplicadorVelocidadeAnimacao()
				direcaoAtual = velocidadeLateral > 0 and 1 or -1
			end
		elseif emAnimacaoLateral then
			AtualizarAnimacaoMovimento()
			return
		end
	end

	local novaDirecao = CalcularMultiplicadorDirecao()

	if novaDirecao ~= direcaoAtual then
		direcaoAtual = novaDirecao
	end

	local velocidadeBase = ObterMultiplicadorVelocidadeAnimacao()
	velocidadeAnimacaoAlvo = velocidadeBase * direcaoAtual

	local suavidade = SUAVIDADE_TRANSICAO_DIRECAO
	if estadoAtual.estadoMov == "Correndo" then
		suavidade = SUAVIDADE_TRANSICAO_CORRENDO
	end

	local diferenca = velocidadeAnimacaoAlvo - velocidadeAnimacaoAtual
	if math.abs(diferenca) > 0.01 then
		velocidadeAnimacaoAtual = velocidadeAnimacaoAtual + diferenca * math.min(1, deltaTime * suavidade)
		animacaoAtualMov:AdjustSpeed(velocidadeAnimacaoAtual)
	elseif velocidadeAnimacaoAtual ~= velocidadeAnimacaoAlvo then
		velocidadeAnimacaoAtual = velocidadeAnimacaoAlvo
		animacaoAtualMov:AdjustSpeed(velocidadeAnimacaoAtual)
	end
end

ConectarGlobal(RunService.RenderStepped, AtualizarDirecaoAnimacao)

local function PreCarregarAnimacoes()
	local todasAnimacoes = Modulo_Configuracoes.ObterTodasAnimacoes()
	local total = #todasAnimacoes
	local carregadas = 0

	DebugPrint(string.format("[ControladorEstado] Pré-carregando %d animações...", total))

	for _, animId in ipairs(todasAnimacoes) do
		local track = ObterAnimacao(animId)
		if track then
			carregadas = carregadas + 1
		end
	end

	DebugPrint(string.format("[ControladorEstado] %d/%d animações pré-carregadas!", carregadas, total))
end

-- player.CharacterAdded connection removed because the script is inside StarterCharacterScripts and runs fresh on spawn.

PreCarregarAnimacoes()

GerenciadorHitboxCliente.DefinirCharacter(character)
GerenciadorHitboxCliente.DefinirCallbackHit(function(alvo, mao, raycastResult)
	AplicarHitFreeze()
	local hrp = character:FindFirstChild("HumanoidRootPart")
	TentarAcao:FireServer("HitboxAcerto", {
		mao = mao,
		alvo = alvo,
		cframe = hrp and hrp.CFrame or nil,
		multiplicadorDano = comboState.multiplicadorDano,
		parteAtingida = raycastResult and raycastResult.Instance.Name or nil,
	})
end)

GerenciadorHitboxCliente.DefinirCallbackSolidHit(function(_raycastResult, _mao)
	AplicarRewindParteSolida()
end)

-- Monitorar e destruir Animate se adicionado tardiamente pelo Roblox no client
ConectarGlobal(character.ChildAdded, function(child)
	if (child:IsA("Script") or child:IsA("LocalScript")) and child.Name == "Animate" then
		task.defer(function()
			if child.Parent then
				child:Destroy()
				DebugPrint("[ControladorEstado] Script Animate tardio desativado no cliente")
				for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
					track:Stop(0)
				end
				AtualizarBaseIdle()
				AtualizarAnimacaoMovimento()
			end
		end)
	end
end)

AtualizarBaseIdle()
AtualizarAnimacaoMovimento()

DebugPrint("[ControladorEstado] Inicializado - movimento input-based + StateChanged")
