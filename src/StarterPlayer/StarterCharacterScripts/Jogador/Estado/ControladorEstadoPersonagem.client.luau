--[[
    Script: ControladorEstadoPersonagem.client.luau
    Caminho: src/StarterPlayer/StarterCharacterScripts/Jogador/Estado
    Responsabilidade: Coordena estados locais do personagem, animacoes e respostas de movimento.
    Uso: LocalScript; roda automaticamente para o jogador local em src/StarterPlayer/StarterCharacterScripts/Jogador/Estado.
    Nao faz: Nao valida autoridade do servidor, nao salva dados persistentes e nao substitui regras server-side.
    Funcoes principais: MarcarContinuarCombo, EstaJanelaComboAtiva, EstaComboAtivo, ContinuarAtaquePesado, EstaAtaquePesadoAtivo, EstaAguardandoSoltarPesado
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
local Modulo_Configuracoes = require(Modulos:WaitForChild("Combate"):WaitForChild("Configuracoes"):WaitForChild("ConfigCombate"))
local Modulo_Combo = require(Modulos:WaitForChild("Combate"):WaitForChild("Dominio"):WaitForChild("ComboCombate"))
local GerenciadorHitboxCliente = require(Modulos:WaitForChild("Combate"):WaitForChild("Hitbox"):WaitForChild("GerenciadorHitboxCliente"))

local ClientBridge = require(Modulos:WaitForChild("Jogador"):WaitForChild("ComunicacaoCliente"):WaitForChild("PonteCliente"))

local TIMINGS = {
	JumpHold = 0.28,
	RunInAirSpeed = 0.4,

	MoveFadeIn = 0.18,
	MoveFadeOut = 0.18,

	ActionFadeIn = 0.10,
	ActionFadeOut = 0.10,

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
	isDashing = false,
}
local parkourState = {
	ativo = false,
	estadoAcaoAnterior = "Nenhuma",
}

local isShiftHeld = false

local heavyAttackState = {
	animacao = nil,
	aguardandoSoltar = false,
	conexoesMarkers = {},
	conexaoTermino = nil,
	earlyCancelTimer = nil,
	earlyCancelExecutado = false,
	tempoInicio = 0,
	conexaoMonitorReversao = nil :: RBXScriptConnection?,
}

local function ObterVelocidadeInicial()
	return Modulo_Configuracoes.ObterConfiguracao("VelocidadeInicialMovimento") or 5
end

local velocidadeRampAlvo = ObterVelocidadeInicial()
local velocidadeRampAtual = ObterVelocidadeInicial()
local rampAtivo = true
local rampSnap = false -- forca aplicar alvo sem interpolar (estados nao-locomocao)

humanoid.WalkSpeed = velocidadeRampAtual

local AtualizarVelocidadeLocal

AtualizarVelocidadeLocal = function()
	local VelBloq = Modulo_Configuracoes.ObterConfiguracao("VelocidadeBloqueando")
	local VelAgachando = Modulo_Configuracoes.ObterConfiguracao("VelocidadeAgachando")
	local VelCorrendo = Modulo_Configuracoes.ObterConfiguracao("VelocidadeCorrendo")
	local VelAndando = Modulo_Configuracoes.ObterConfiguracao("VelocidadeAndando")

	local emCombate = (
		estadoAtual.estadoAcao == "AtacandoLeve"
		or estadoAtual.estadoAcao == "CarregandoPesado"
		or estadoAtual.estadoAcao == "SoltandoPesado"
		or estadoAtual.estadoAcao == "AtaquePesado"
	)

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

RunService.Heartbeat:Connect(function(dt)
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

local jumpAnimState = {
	animacao = nil,
	conexaoTermino = nil,
	aguardandoTermino = false,
}

local AtualizarAnimacaoMovimento
local AtualizarBaseIdle
local ObterAnimacao
local PararAnimacaoMov

AtualizarBaseIdle = function()
	local nomeIdle = estadoAtual.agachado and "IdleAgachado" or "Idle"
	local animId = Modulo_Configuracoes.ObterIdAnimacao(estadoAtual.modoAnimacao, nomeIdle)

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
		animacaoBaseIdle.Priority = Enum.AnimationPriority.Core
		animacaoBaseIdle.Looped = true
		animacaoBaseIdle:Play(TIMINGS.MoveFadeIn)
		DebugPrint(string.format("[ControladorEstado] BaseIdle atualizado para: %s (%s)", nomeIdle, animId))
	end
end

local comboState = {
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
	conexaoMonitorReversao = nil :: RBXScriptConnection?,
}

local defenseCancelState = {
	ultimoCancelamento = 0,
	cancelPendente = false,
}

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

	GerenciadorHitboxCliente.PararTodas()

	comboState.animacaoAtiva = nil
	comboState.janelaAtiva = false
	comboState.indiceAtual = 0
	comboState.continuarCombo = false
	comboState.pendingConsume = false
	comboState.token = 0
	comboState.earlyCancelExecutado = false
	comboState.tempoInicio = 0

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

local function OnMarkerJanelaCombo(ehFinal: boolean)
	if not comboState.animacaoAtiva then
		return
	end

	comboState.indiceAtual = comboState.indiceAtual + 1

	comboState.token = comboState.token + 1
	local myToken = comboState.token

	comboState.janelaAtiva = true
	comboState.continuarCombo = false

	DebugPrint(string.format("[ControladorEstado] Janela de combo ativada (golpe %d, final=%s)",
		comboState.indiceAtual, tostring(ehFinal)))

	local combo = Modulo_Configuracoes.ObterConfiguracaoCombo(estadoAtual.modoAnimacao)
	if not combo then
		return
	end

	comboState.animacaoAtiva:AdjustSpeed(combo.velocidadeJanela)

	if comboState.pendingConsume then
		DebugPrint("[ControladorEstado] Consumo antecipado de combo (pending antes da janela)")
		comboState.pendingConsume = false
		comboState.continuarCombo = true
		comboState.janelaAtiva = false

		if comboState.animacaoAtiva and comboState.animacaoAtiva.IsPlaying then
			comboState.animacaoAtiva:AdjustSpeed(1)
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
				comboState.animacaoAtiva:AdjustSpeed(1)
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

local function OnMarkerHeavyAtaquePorMao(tipoMarcador: string)
	DebugPrint(string.format("[ControladorEstado] Marker %s - heavy attack", tipoMarcador))

	local tipoAtaque = "AtaquePesado"

	if ClientBridge.AplicarImpulsoAtaque then
		ClientBridge.AplicarImpulsoAtaque(tipoAtaque)
	end

	if tipoMarcador == "HeavyAttackRight" then
		GerenciadorHitboxCliente.OnMarkerAttackRight()
	elseif tipoMarcador == "HeavyAttackLeft" then
		GerenciadorHitboxCliente.OnMarkerAttackLeft()
	elseif tipoMarcador == "HeavyAttackBoth" then
		GerenciadorHitboxCliente.OnMarkerAttackBoth()
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	local dados = {
		tipoMarcador = tipoMarcador,
		cframe = hrp and hrp.CFrame or nil,
	}
	TentarAcao:FireServer("HeavyAttackHitbox", dados)

	if heavyAttackState.animacao and heavyAttackState.animacao.IsPlaying then
		local track = heavyAttackState.animacao
		local janelaEarlyCancel = Modulo_Configuracoes.ObterConfiguracao("JanelaCancelamentoAtaquePesado") or 0.2
		local speed = math.max(track.Speed, 0.1)
		local tempoRestante = (track.Length - track.TimePosition) / speed

		if tempoRestante > janelaEarlyCancel and janelaEarlyCancel > 0 then
			local tempoParaEarlyCancel = tempoRestante - janelaEarlyCancel
			DebugPrint(
				string.format(
					"[ControladorEstado] Heavy attack early cancel agendado: %.2fs restante, early cancel em %.2fs",
					tempoRestante,
					tempoParaEarlyCancel
				)
			)

			heavyAttackState.earlyCancelTimer = task.delay(tempoParaEarlyCancel, function()

				if
					heavyAttackState.animacao
					and heavyAttackState.animacao.IsPlaying
					and not heavyAttackState.earlyCancelExecutado
				then
					heavyAttackState.earlyCancelExecutado = true
					DebugPrint("[ControladorEstado] Heavy attack early cancel executado - mudando estado para Normal")

					GerenciadorHitboxCliente.PararTodas()

					estadoAtual.estadoAcao = "Nenhuma"

					TentarAcao:FireServer("HeavyAttackEarlyCancel")

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

local function OnMarkerHeavyAtaqueFim()
	DebugPrint("[ControladorEstado] Marker HeavyAttackEnd - parando hitboxes")
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

		onHeavyAtaqueDireita = function()
			OnMarkerHeavyAtaquePorMao("HeavyAttackRight")
		end,
		onHeavyAtaqueEsquerda = function()
			OnMarkerHeavyAtaquePorMao("HeavyAttackLeft")
		end,
		onHeavyAtaqueAmbos = function()
			OnMarkerHeavyAtaquePorMao("HeavyAttackBoth")
		end,

		onHeavyAtaqueFim = OnMarkerHeavyAtaqueFim,
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

local function LimparConexoesHeavyAttack()
	for _, conexao in ipairs(heavyAttackState.conexoesMarkers) do
		if conexao and conexao.Connected then
			conexao:Disconnect()
		end
	end
	heavyAttackState.conexoesMarkers = {}

	if heavyAttackState.conexaoTermino then
		heavyAttackState.conexaoTermino:Disconnect()
		heavyAttackState.conexaoTermino = nil
	end

	if heavyAttackState.earlyCancelTimer then
		pcall(task.cancel, heavyAttackState.earlyCancelTimer)
		heavyAttackState.earlyCancelTimer = nil
	end

	if heavyAttackState.conexaoMonitorReversao then
		heavyAttackState.conexaoMonitorReversao:Disconnect()
		heavyAttackState.conexaoMonitorReversao = nil
	end
end

local function OnHeavyAttackTerminou()
	DebugPrint("[ControladorEstado] Animação de ataque pesado terminou")
	GerenciadorHitboxCliente.PararTodas()

	local earlyCancelJaExecutado = heavyAttackState.earlyCancelExecutado

	LimparConexoesHeavyAttack()
	heavyAttackState.animacao = nil
	heavyAttackState.aguardandoSoltar = false
	heavyAttackState.earlyCancelExecutado = false

	if earlyCancelJaExecutado then
		DebugPrint("[ControladorEstado] Early cancel já executado, ignorando término normal")
		return
	end

	estadoAtual.estadoAcao = "Nenhuma"

	if isShiftHeld then
		movementFlags.isRunning = true
		estadoAtual.estadoMov = "Correndo"
		estadoAtual.correndo = true
	end

	AtualizarVelocidadeLocal()

	AtualizarAnimacaoMovimento()

	local acaoNome = "AtaquePesado"
	local ok, err = pcall(function()
		local rem = ReplicatedStorage:FindFirstChild("Remotos")
		if rem and rem:FindFirstChild("AcaoAnimacaoTerminou") then
			rem:FindFirstChild("AcaoAnimacaoTerminou"):FireServer(acaoNome)
		end
	end)
	if not ok then
		DebugPrint("[ControladorEstado] Falha ao notificar servidor do término da ação:", err)
	end
end

local function OnMarkerAttackRelease()
	DebugPrint("[ControladorEstado] Marcador AttackRelease atingido")

	if not heavyAttackState.animacao or not heavyAttackState.animacao.IsPlaying then
		return
	end

	local aindaSegurando = ClientBridge.EstaSegurandoM1 and ClientBridge.EstaSegurandoM1()

	if aindaSegurando then

		heavyAttackState.animacao:AdjustSpeed(0)
		heavyAttackState.aguardandoSoltar = true
		DebugPrint("[ControladorEstado] Animação pausada - aguardando soltar M1")
	else

		if ClientBridge.AplicarImpulsoAtaque then
			ClientBridge.AplicarImpulsoAtaque("AtaquePesado")
		end
		DebugPrint("[ControladorEstado] M1 já foi solto - animação continua, impulso aplicado")
	end
end

local function OnMarkerHeavyAttack()
	DebugPrint("[ControladorEstado] Marcador HeavyAttack atingido - ativando hitbox")

	GerenciadorHitboxCliente.OnMarkerAttackRight()

	local hrp = character:FindFirstChild("HumanoidRootPart")
	local dados = {
		cframe = hrp and hrp.CFrame or nil,
		tipoMarcador = "AttackRight",
	}
	TentarAcao:FireServer("HeavyAttackHitbox", dados)

	if heavyAttackState.animacao and heavyAttackState.animacao.IsPlaying then
		local track = heavyAttackState.animacao
		local janelaEarlyCancel = Modulo_Configuracoes.ObterConfiguracao("JanelaCancelamentoAtaquePesado") or 0.2
		local speed = math.max(track.Speed, 0.1)
		local tempoRestante = (track.Length - track.TimePosition) / speed

		if tempoRestante > janelaEarlyCancel and janelaEarlyCancel > 0 then
			local tempoParaEarlyCancel = tempoRestante - janelaEarlyCancel
			DebugPrint(
				string.format(
					"[ControladorEstado] Heavy attack early cancel agendado: %.2fs restante, early cancel em %.2fs",
					tempoRestante,
					tempoParaEarlyCancel
				)
			)

			heavyAttackState.earlyCancelTimer = task.delay(tempoParaEarlyCancel, function()

				if
					heavyAttackState.animacao
					and heavyAttackState.animacao.IsPlaying
					and not heavyAttackState.earlyCancelExecutado
				then
					heavyAttackState.earlyCancelExecutado = true
					DebugPrint("[ControladorEstado] Heavy attack early cancel executado - mudando estado para Normal")

					GerenciadorHitboxCliente.PararTodas()

					estadoAtual.estadoAcao = "Nenhuma"

					TentarAcao:FireServer("HeavyAttackEarlyCancel")

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

local function ConfigurarMarkersHeavyAttack(track: AnimationTrack)
	LimparConexoesHeavyAttack()

	heavyAttackState.animacao = track
	heavyAttackState.aguardandoSoltar = false

	local limpezaListeners = Modulo_Combo.ConfigurarListenersMarcadores(track, {

		onAttackRelease = OnMarkerAttackRelease,

		onHeavyAtaqueDireita = function()
			OnMarkerHeavyAtaquePorMao("HeavyAttackRight")
		end,
		onHeavyAtaqueEsquerda = function()
			OnMarkerHeavyAtaquePorMao("HeavyAttackLeft")
		end,
		onHeavyAtaqueAmbos = function()
			OnMarkerHeavyAtaquePorMao("HeavyAttackBoth")
		end,

		onHeavyAtaqueFim = OnMarkerHeavyAtaqueFim,

		onHeavyAttack = OnMarkerHeavyAttack,
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
	table.insert(heavyAttackState.conexoesMarkers, mockConexao :: any)

	heavyAttackState.conexaoTermino = track.Stopped:Connect(function()
		OnHeavyAttackTerminou()
	end)

	DebugPrint("[ControladorEstado] Markers de ataque pesado configurados")
end

function ClientBridge.ContinuarAtaquePesado()
	if not heavyAttackState.animacao or not heavyAttackState.animacao.IsPlaying then
		DebugPrint("[ControladorEstado] ContinuarAtaquePesado - sem animação ativa")
		return false
	end

	local velocidadeSoltar = Modulo_Configuracoes.ObterConfiguracao("VelocidadeSoltarPesado") or 1.0

	if heavyAttackState.aguardandoSoltar then

		heavyAttackState.animacao:AdjustSpeed(velocidadeSoltar)
		heavyAttackState.aguardandoSoltar = false

		if ClientBridge.AplicarImpulsoAtaque then
			ClientBridge.AplicarImpulsoAtaque("AtaquePesado")
		end

		DebugPrint(
			"[ControladorEstado] Animação de ataque pesado retomada com impulso (velocidade:",
			velocidadeSoltar,
			")"
		)
		return true
	end

	heavyAttackState.animacao:AdjustSpeed(velocidadeSoltar)
	DebugPrint("[ControladorEstado] Velocidade ajustada para soltar (velocidade:", velocidadeSoltar, ")")
	return true
end

function ClientBridge.EstaAtaquePesadoAtivo()
	return heavyAttackState.animacao and heavyAttackState.animacao.IsPlaying
end

function ClientBridge.EstaAguardandoSoltarPesado()
	return heavyAttackState.aguardandoSoltar
end

function ClientBridge.TentarCancelarAtaquePorDefesa()
	local agora = tick()

	local cooldown = Modulo_Configuracoes.ObterConfiguracao("CooldownCancel") or 1.0
	if (agora - defenseCancelState.ultimoCancelamento) < cooldown then
		DebugPrint("[ControladorEstado] Defense cancel em cooldown")
		return false, nil
	end

	if comboState.animacaoAtiva and comboState.animacaoAtiva.IsPlaying then
		local tempoDecorrido = agora - comboState.tempoInicio
		local janelaAtaque = Modulo_Configuracoes.ObterConfiguracao("JanelaCancelAtaque") or 0.15

		if comboState.indiceAtual <= 1 and tempoDecorrido <= janelaAtaque then
			DebugPrint(
				string.format(
					"[ControladorEstado] Defense cancel: Cancelando ataque leve (%.3fs dentro da janela de %.3fs)",
					tempoDecorrido,
					janelaAtaque
				)
			)

			local track = comboState.animacaoAtiva
			local velReversao = Modulo_Configuracoes.ObterConfiguracao("VelocidadeReversaoCancelamento") or -1.5
			track:AdjustSpeed(velReversao)

			comboState.conexaoMonitorReversao = RunService.RenderStepped:Connect(function()
				if not track or not track.IsPlaying or track.TimePosition <= 0.01 then
					if comboState.conexaoMonitorReversao then
						comboState.conexaoMonitorReversao:Disconnect()
						comboState.conexaoMonitorReversao = nil
					end
					if track and track.IsPlaying then
						track:Stop(0.1)
					end
				end
			end)

			LimparConexoesMarkers()
			comboState.animacaoAtiva = nil
			comboState.janelaAtiva = false
			comboState.indiceAtual = 0
			comboState.continuarCombo = false
			comboState.pendingConsume = false
			comboState.token = 0
			comboState.earlyCancelExecutado = false
			comboState.tempoInicio = 0

			estadoAtual.estadoAcao = "Nenhuma"

			defenseCancelState.ultimoCancelamento = agora

			defenseCancelState.cancelPendente = true

			return true, "AtaqueLeve"
		end
	end

	if heavyAttackState.animacao and heavyAttackState.animacao.IsPlaying then
		local tempoDecorrido = agora - heavyAttackState.tempoInicio
		local janelaCarregar = Modulo_Configuracoes.ObterConfiguracao("JanelaCancelAtaquePesado") or 0.92

		if tempoDecorrido <= janelaCarregar then
			DebugPrint(
				string.format(
					"[ControladorEstado] Defense cancel: Cancelando carregamento pesado (%.3fs dentro da janela de %.3fs)",
					tempoDecorrido,
					janelaCarregar
				)
			)

			local track = heavyAttackState.animacao
			local velReversao = Modulo_Configuracoes.ObterConfiguracao("VelocidadeReversaoCancelamento") or -1.5
			track:AdjustSpeed(velReversao)

			heavyAttackState.conexaoMonitorReversao = RunService.RenderStepped:Connect(function()
				if not track or not track.IsPlaying or track.TimePosition <= 0.01 then
					if heavyAttackState.conexaoMonitorReversao then
						heavyAttackState.conexaoMonitorReversao:Disconnect()
						heavyAttackState.conexaoMonitorReversao = nil
					end
					if track and track.IsPlaying then
						track:Stop(0.1)
					end
				end
			end)

			LimparConexoesHeavyAttack()
			heavyAttackState.animacao = nil
			heavyAttackState.aguardandoSoltar = false
			heavyAttackState.earlyCancelExecutado = false
			heavyAttackState.tempoInicio = 0

			estadoAtual.estadoAcao = "Nenhuma"

			defenseCancelState.ultimoCancelamento = agora

			defenseCancelState.cancelPendente = true

			return true, "CarregandoPesado"
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

local equipAnimState = {
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

local function ObterToolEquipado(): Tool?
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Tool")
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

local dashState = {
	animacao = nil,
	direcao = "Frente",
	conexaoTermino = nil,
	velocityConnection = nil,
	earlyCancelTimer = nil,
	earlyCancelExecutado = false,
}

local function CalcularDirecaoDashLocal(): string
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return "Frente"
	end

	local moveDir = humanoid.MoveDirection

	if moveDir.Magnitude < 0.1 then
		return "Frente"
	end

	local lookVector = hrp.CFrame.LookVector
	local rightVector = hrp.CFrame.RightVector

	local lookXZ = Vector3.new(lookVector.X, 0, lookVector.Z).Unit
	local rightXZ = Vector3.new(rightVector.X, 0, rightVector.Z).Unit
	local moveXZ = Vector3.new(moveDir.X, 0, moveDir.Z).Unit

	local dotForward = lookXZ:Dot(moveXZ)
	local dotRight = rightXZ:Dot(moveXZ)

	if math.abs(dotForward) >= math.abs(dotRight) then

		if dotForward >= 0 then
			return "Frente"
		else
			return "Tras"
		end
	else

		if dotRight >= 0 then
			return "Direita"
		else
			return "Esquerda"
		end
	end
end

ClientBridge.CalcularDirecaoDash = CalcularDirecaoDashLocal

function ClientBridge.EstaEmDash()
	return movementFlags.isDashing
end

local function IniciarImpulsoDash(direcao: string)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local forcaDash = Modulo_Configuracoes.ObterConfiguracao("ForcaDash") or 50

	if dashState.velocityConnection then
		dashState.velocityConnection:Disconnect()
	end

	dashState.velocityConnection = RunService.RenderStepped:Connect(function(_deltaTime)
		if not dashState.animacao or not dashState.animacao.IsPlaying then
			if dashState.velocityConnection then
				dashState.velocityConnection:Disconnect()
				dashState.velocityConnection = nil
			end
			return
		end

		local lookVector = hrp.CFrame.LookVector
		local rightVector = hrp.CFrame.RightVector

		local dirVector = lookVector
		if direcao == "Tras" then
			dirVector = -lookVector
		elseif direcao == "Esquerda" then
			dirVector = -rightVector
		elseif direcao == "Direita" then
			dirVector = rightVector
		end

		dirVector = Vector3.new(dirVector.X, 0, dirVector.Z).Unit

		local velocidadeAtual = hrp.AssemblyLinearVelocity
		local velocidadeAlvo = dirVector * forcaDash

		hrp.AssemblyLinearVelocity = Vector3.new(velocidadeAlvo.X, velocidadeAtual.Y, velocidadeAlvo.Z)
	end)
end

local function PararImpulsoDash()
	if dashState.velocityConnection then
		dashState.velocityConnection:Disconnect()
		dashState.velocityConnection = nil
	end
end

local function OnDashAnimacaoTerminou()
	DebugPrint("[ControladorEstado] Dash animação terminou")

	PararImpulsoDash()

	dashState.animacao = nil
	dashState.direcao = "Frente"
	movementFlags.isDashing = false

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

local attackImpulseState = {
	connection = nil :: RBXScriptConnection?,
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

	if tipoAtaque == "AtaquePesado" or tipoAtaque == "AtaqueLeveFinal" then
		magnitude = Modulo_Configuracoes.ObterConfiguracao("MagnitudeImpulsoAtaquePesado") or 25
		duracao = Modulo_Configuracoes.ObterConfiguracao("DuracaoImpulsoAtaquePesado") or 0.1
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
	hrp.AssemblyLinearVelocity = Vector3.new(
		direcao.X * magnitude,
		velocidadeAtual.Y + 5,
		direcao.Z * magnitude
	)

	DebugPrint(string.format("[ControladorEstado] Knockback recebido: magnitude=%.1f", magnitude))
end

local AplicarKnockbackRemote = Remotos:FindFirstChild("AplicarKnockback")
if AplicarKnockbackRemote then
	AplicarKnockbackRemote.OnClientEvent:Connect(function(direcao, magnitude)
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
		or estadoAtual.estadoAcao == "CarregandoPesado"
		or estadoAtual.estadoAcao == "SoltandoPesado"
		or estadoAtual.estadoAcao == "AtaquePesado"
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

local function TocarAnimacaoAcao(animId: string, loop: boolean, velocidade: number, nomeAnimacao: string?)
	if parkourState.ativo then
		return
	end

	local track = ObterAnimacao(animId)
	if not track then
		return
	end

	local ehEquipar = nomeAnimacao and (nomeAnimacao == "Equipar" or nomeAnimacao == "Desequipar")

	local ehDash = nomeAnimacao and (nomeAnimacao:match("^Dash"))

	if ehEquipar and equipAnimState.animacao and equipAnimState.animacao.IsPlaying then
		DebugPrint("[ControladorEstado] Já há animação de equip tocando, ignorando")
		return
	end

	PararAnimacaoAcao()

	track.Priority = Enum.AnimationPriority.Action
	track.Looped = loop
	track:Play(0.1)
	track:AdjustSpeed(velocidade)

	animacaoAtualAcao = track

	if ehDash then

		if dashState.conexaoTermino then
			dashState.conexaoTermino:Disconnect()
		end
		PararImpulsoDash()

		local direcao = "Frente"
		if nomeAnimacao == "DashFrente" then
			direcao = "Frente"
		elseif nomeAnimacao == "DashTras" then
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
			local janelaEarlyCancel = Modulo_Configuracoes.ObterConfiguracao("JanelaCancelamentoDash") or 0.12
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

		comboState.animacaoAtiva = track
		comboState.janelaAtiva = false
		comboState.indiceAtual = 1
		comboState.continuarCombo = false
		comboState.tempoInicio = tick()

		ConfigurarMarkersCombo(track)

		DebugPrint(
			string.format(
				"[ControladorEstado] Animação de combo iniciada: %s (velocidade %.1f)",
				nomeAnimacao :: string,
				velocidade
			)
		)
		return
	end

	local ehAtaquePesado = nomeAnimacao and nomeAnimacao == "AtaquePesado"

	if ehAtaquePesado then

		heavyAttackState.tempoInicio = tick()
		ConfigurarMarkersHeavyAttack(track)

		DebugPrint(
			string.format("[ControladorEstado] Animação de ataque pesado iniciada (velocidade %.1f)", velocidade)
		)
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
		local emAtacando = (
			estadoAtual.estadoAcao == "AtacandoLeve"
			or estadoAtual.estadoAcao == "CarregandoPesado"
			or estadoAtual.estadoAcao == "SoltandoPesado"
			or estadoAtual.estadoAcao == "AtaquePesado"
		)

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

	local movimentoMudou =
		estadoMovAnterior ~= estadoAtual.estadoMov
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

	if
		estadoAtual.estadoAcao == "AtacandoLeve"
		or estadoAtual.estadoAcao == "CarregandoPesado"
		or estadoAtual.estadoAcao == "SoltandoPesado"
		or estadoAtual.estadoAcao == "AtaquePesado"
		or estadoAtual.estadoAcao == "Defendendo"
	then

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

	if
		(
			acaoAnterior == "AtacandoLeve"
			or acaoAnterior == "CarregandoPesado"
			or acaoAnterior == "SoltandoPesado"
			or acaoAnterior == "AtaquePesado"
		) and estadoAtual.estadoAcao == "Nenhuma"
	then
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

		local emCombate = (
			estadoAtual.estadoAcao == "AtacandoLeve"
			or estadoAtual.estadoAcao == "CarregandoPesado"
			or estadoAtual.estadoAcao == "SoltandoPesado"
			or estadoAtual.estadoAcao == "AtaquePesado"
			or estadoAtual.estadoAcao == "Defendendo"
		)

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

	local emCombate = (
		estadoAtual.estadoAcao == "AtacandoLeve"
		or estadoAtual.estadoAcao == "CarregandoPesado"
		or estadoAtual.estadoAcao == "SoltandoPesado"
		or estadoAtual.estadoAcao == "AtaquePesado"
		or estadoAtual.estadoAcao == "Defendendo"
	)

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

			emCombate = (
				estadoAtual.estadoAcao == "AtacandoLeve"
				or estadoAtual.estadoAcao == "CarregandoPesado"
				or estadoAtual.estadoAcao == "SoltandoPesado"
				or estadoAtual.estadoAcao == "AtaquePesado"
				or estadoAtual.estadoAcao == "Defendendo"
			)
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

				local emCombate = (
					estadoAtual.estadoAcao == "AtacandoLeve"
					or estadoAtual.estadoAcao == "CarregandoPesado"
					or estadoAtual.estadoAcao == "SoltandoPesado"
					or estadoAtual.estadoAcao == "AtaquePesado"
					or estadoAtual.estadoAcao == "Defendendo"
				)
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

UserInputService.InputBegan:Connect(function(input, gameProcessed)
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

UserInputService.InputEnded:Connect(function(input, _gameProcessed)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		movementFlags.isRunning = false
		isShiftHeld = false
		estadoAtual.correndo = false
		AtualizarVelocidadeLocal()
		AtualizarEstadoMovimento()
	end
end)

SincronizarEstado.OnClientEvent:Connect(ProcessarSincronizacao)
TocarAnimacao.OnClientEvent:Connect(ProcessarTocarAnimacao)

RunService.Heartbeat:Connect(AtualizarEstadoMovimento)

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

RunService.RenderStepped:Connect(AtualizarDirecaoAnimacao)

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

player.CharacterAdded:Connect(function(novoCharacter)
	character = novoCharacter
	humanoid = character:WaitForChild("Humanoid")
	animator = humanoid:WaitForChild("Animator")

	GerenciadorHitboxCliente.DestruirTodas()
	GerenciadorHitboxCliente.DefinirCharacter(novoCharacter)

	humanoid.StateChanged:Connect(OnStateChanged)

	DesativarScriptAnimate()

	animacoesCarregadas = {}
	animacaoAtualMov = nil
	animacaoAtualAcao = nil
	animacaoBaseIdle = nil
	idBaseIdleAtual = nil

	LimparConexoesMarkers()
	comboState.animacaoAtiva = nil
	comboState.janelaAtiva = false
	comboState.indiceAtual = 0
	comboState.continuarCombo = false
	comboState.pendingConsume = false
	comboState.token = 0

	LimparConexoesMarkersEquip()
	if equipAnimState.conexaoTermino then
		equipAnimState.conexaoTermino:Disconnect()
		equipAnimState.conexaoTermino = nil
	end

	equipAnimState.animacao = nil
	equipAnimState.direcao = 0
	equipAnimState.modoAlvo = nil
	equipAnimState.armaClonada = nil
	equipAnimState.acessorioJaClonado = false

	movementFlags = {
		isRunning = false,
		isJumping = false,
		isFalling = false,
		isClimbing = false,
		isSwimming = false,
		isDashing = false,
	}

	parkourState = {
		ativo = false,
		estadoAcaoAnterior = "Nenhuma",
	}

	LimparJumpAnimState()

	direcaoAtual = 1
	velocidadeAnimacaoAlvo = 1
	velocidadeAnimacaoAtual = 1
	animacaoUsaDirecao = false
	animacaoMovPausada = false
	ultimaAnimacaoMovNome = nil
	if timerPararAnimacao then
		pcall(task.cancel, timerPararAnimacao)
		timerPararAnimacao = nil
	end

	estadoAtual = {
		estadoMov = "Parado",
		estadoAcao = "Nenhuma",
		estadoAcaoAnterior = "Nenhuma",
		modoAnimacao = "Base",
		bloqueando = false,
		agachado = false,
		correndo = false,
	}

	PreCarregarAnimacoes()

	AtualizarBaseIdle()
	AtualizarAnimacaoMovimento()
end)

PreCarregarAnimacoes()

GerenciadorHitboxCliente.DefinirCharacter(character)
GerenciadorHitboxCliente.DefinirCallbackHit(function(alvo, mao)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	TentarAcao:FireServer("HitboxAcerto", {
		mao = mao,
		alvo = alvo,
		cframe = hrp and hrp.CFrame or nil,
	})
end)

AtualizarBaseIdle()
AtualizarAnimacaoMovimento()

DebugPrint("[ControladorEstado] Inicializado - movimento input-based + StateChanged")
