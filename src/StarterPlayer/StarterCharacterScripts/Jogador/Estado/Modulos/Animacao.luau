--[[
    Script: Animacao.luau
    Caminho: src/StarterPlayer/StarterCharacterScripts/Jogador/Estado/Modulos
    Responsabilidade: Cache de animacoes, reproducao e parada de tracks de movimento e acao,
                      calculos de direcao e velocidade, base idle e pre-carregamento.
    Uso: ModuleScript; inicializado pelo ControladorEstadoPersonagem via Inicializar(ctx).
    Nao faz: Nao decide quando iniciar combos ou habilidades; apenas reproduz animacoes sob demanda.
    Funcoes principais: ObterAnimacao, TocarAnimacaoMov, PararAnimacaoMov, TocarAnimacaoAcao,
                        PararAnimacaoAcao, AtualizarAnimacaoMovimento, AtualizarBaseIdle,
                        DefinirVelocidadeMovimento, PreCarregarAnimacoes
]]

local RunService = game:GetService("RunService")

local Animacao = {}

local ctx
local Movimento -- referencia cruzada
local Combo -- referencia cruzada
local Equipamento -- referencia cruzada
local Esquiva -- referencia cruzada

-- Cache de animações
local animacoesCarregadas = {}
local animacaoAtualMov: AnimationTrack? = nil
local animacaoAtualAcao: AnimationTrack? = nil

local animacaoBaseIdle: AnimationTrack? = nil
local idBaseIdleAtual: string? = nil

-- Estado de direção e velocidade de animação
local direcaoAtual = 1
local velocidadeAnimacaoAlvo = 1
local velocidadeAnimacaoAtual = 1
local animacaoUsaDirecao = false
local SUAVIDADE_TRANSICAO_DIRECAO = 10
local SUAVIDADE_TRANSICAO_CORRENDO = SUAVIDADE_TRANSICAO_DIRECAO * 2

local animacaoMovPausada = false
local ultimaAnimacaoMovNome: string? = nil
local TEMPO_MANTER_ANIMACAO = 0.27
local VELOCIDADE_PAUSA = 0.2
local timerPararAnimacao: thread? = nil

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

-- Estado de pulo
local jumpAnimState = {
	animacao = nil :: AnimationTrack?,
	conexaoTermino = nil :: RBXScriptConnection?,
	aguardandoTermino = false,
}

-- ═══════════════════════════════════════════════════════════════════
-- Acessores públicos para estado interno
-- ═══════════════════════════════════════════════════════════════════

function Animacao.ObterAnimacaoAtualMov(): AnimationTrack?
	return animacaoAtualMov
end

function Animacao.ObterAnimacaoAtualAcao(): AnimationTrack?
	return animacaoAtualAcao
end

function Animacao.EstaAguardandoTerminoPulo(): boolean
	return jumpAnimState.aguardandoTermino
end

function Animacao.ObterUltimaAnimacaoMovNome(): string?
	return ultimaAnimacaoMovNome
end

-- ═══════════════════════════════════════════════════════════════════
-- Cache e carregamento
-- ═══════════════════════════════════════════════════════════════════

function Animacao.ObterAnimacao(animId: string): AnimationTrack?
	if animacoesCarregadas[animId] then
		return animacoesCarregadas[animId]
	end

	local animacao = Instance.new("Animation")
	animacao.AnimationId = animId

	local sucesso, track = pcall(function()
		return ctx.Animator:LoadAnimation(animacao)
	end)

	if sucesso and track then
		animacoesCarregadas[animId] = track
		return track
	end

	return nil
end

function Animacao.PreCarregarAnimacoes()
	local todasAnimacoes = ctx.Modulo_Configuracoes.ObterTodasAnimacoes()
	local total = #todasAnimacoes
	local carregadas = 0

	ctx.DebugPrint(string.format("[Animacao] Pré-carregando %d animações...", total))

	for _, animId in ipairs(todasAnimacoes) do
		local track = Animacao.ObterAnimacao(animId)
		if track then
			carregadas = carregadas + 1
		end
	end

	ctx.DebugPrint(string.format("[Animacao] %d/%d animações pré-carregadas!", carregadas, total))
end

-- ═══════════════════════════════════════════════════════════════════
-- Base Idle
-- ═══════════════════════════════════════════════════════════════════

local function obterModoAnimacaoEfetivoParaIdle(): string
	if ctx.EstadoAtual.modoAnimacao ~= "Base" then
		return ctx.EstadoAtual.modoAnimacao
	end
	if ctx.EstadoAtual.estadoAcao == "Desequipando" then
		return ctx.EstadoAtual.modoAnimacao
	end
	local ObterToolEquipado = Equipamento and Equipamento.ObterToolEquipado
	if not ObterToolEquipado then
		return ctx.EstadoAtual.modoAnimacao
	end
	local tool = ObterToolEquipado()
	local dados = tool and tool:FindFirstChild("Dados")
	if not dados then
		return ctx.EstadoAtual.modoAnimacao
	end
	local tipoValue = dados:FindFirstChild("Tipo")
	if not tipoValue or not tipoValue:IsA("StringValue") or tipoValue.Value ~= "ArmasEquipadas" then
		return ctx.EstadoAtual.modoAnimacao
	end
	local modoValue = dados:FindFirstChild("modoAnimacao") or dados:FindFirstChild("Modo")
	if modoValue and modoValue:IsA("StringValue") and modoValue.Value ~= "" then
		return modoValue.Value
	end
	return ctx.EstadoAtual.modoAnimacao
end

function Animacao.AtualizarBaseIdle()
	local nomeIdle = ctx.EstadoAtual.agachado and "IdleAgachado" or "Idle"
	local modoIdle = obterModoAnimacaoEfetivoParaIdle()
	local animId = ctx.Modulo_Configuracoes.ObterIdAnimacao(modoIdle, nomeIdle)

	if not animId then
		animId = ctx.Modulo_Configuracoes.ObterIdAnimacao("Base", nomeIdle)
	end

	if not animId or animId == idBaseIdleAtual then
		return
	end

	idBaseIdleAtual = animId
	local novaTrack = Animacao.ObterAnimacao(animId)

	if novaTrack then
		if animacaoBaseIdle then
			animacaoBaseIdle:Stop(ctx.TIMINGS.MoveFadeOut)
		end

		novaTrack.Priority = Enum.AnimationPriority.Idle
		novaTrack.Looped = true
		novaTrack:Play(ctx.TIMINGS.MoveFadeIn)
		animacaoBaseIdle = novaTrack
		ctx.DebugPrint(string.format("[Animacao] BaseIdle atualizado para: %s (%s)", nomeIdle, animId))
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- Jump Animation
-- ═══════════════════════════════════════════════════════════════════

function Animacao.LimparJumpAnimState()
	if jumpAnimState.conexaoTermino then
		jumpAnimState.conexaoTermino:Disconnect()
		jumpAnimState.conexaoTermino = nil
	end
	jumpAnimState.animacao = nil
	jumpAnimState.aguardandoTermino = false
end

local function OnJumpAnimacaoTerminou()
	ctx.DebugPrint("[Animacao] Animação de Pulando terminou completamente")

	Animacao.LimparJumpAnimState()

	if ctx.ParkourState.ativo then
		ctx.MovementFlags.isJumping = false
		ctx.DebugPrint("[Animacao] OnJumpAnimacaoTerminou ignorado: parkour ativo")
		return
	end

	if ctx.MovementFlags.isJumping or ctx.MovementFlags.isFalling then
		ctx.MovementFlags.isJumping = false
		ctx.MovementFlags.isFalling = true
		ctx.EstadoAtual.estadoMov = "Caindo"

		pcall(function()
			ctx.TentarAcao:FireServer("SincronizarMovimento", "Caindo")
		end)
		Animacao.AtualizarAnimacaoMovimento()
		ctx.DebugPrint("[Animacao] Transitando para Caindo após animação de pulo")
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- Cálculos de direção
-- ═══════════════════════════════════════════════════════════════════

local function CalcularMultiplicadorDirecao(): number
	local hrp = ctx.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return 1
	end

	local moveDir = ctx.Humanoid.MoveDirection
	if moveDir.Magnitude < 0.1 then
		return direcaoAtual
	end

	local player = ctx.Player
	local shiftLockOnOuFirstPerson = (
		(ctx.ClientBridge.LerStatusLocal and ctx.ClientBridge.LerStatusLocal("ShiftLockOn") == true)
		or player.CameraMode == Enum.CameraMode.LockFirstPerson
	)

	local lookVector = hrp.CFrame.LookVector
	if shiftLockOnOuFirstPerson then
		local camera = workspace.CurrentCamera
		if camera then
			lookVector = camera.CFrame.LookVector
		end
	end

	local lookXZ = Vector3.new(lookVector.X, 0, lookVector.Z)
	if lookXZ.Magnitude > 0.001 then
		lookXZ = lookXZ.Unit
	else
		lookXZ = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z).Unit
	end

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
	local player = ctx.Player
	local shiftLockOnOuFirstPerson = (
		(ctx.ClientBridge.LerStatusLocal and ctx.ClientBridge.LerStatusLocal("ShiftLockOn") == true)
		or player.CameraMode == Enum.CameraMode.LockFirstPerson
	)

	if not shiftLockOnOuFirstPerson then
		return "Nenhum", 1
	end

	local hrp = ctx.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return "Nenhum", 1
	end

	local moveDir = ctx.Humanoid.MoveDirection
	if moveDir.Magnitude < 0.1 then
		return "Nenhum", 1
	end

	local lookVector = hrp.CFrame.LookVector
	local rightVector = hrp.CFrame.RightVector

	local camera = workspace.CurrentCamera
	if camera then
		lookVector = camera.CFrame.LookVector
		rightVector = camera.CFrame.RightVector
	end

	local lookXZ = Vector3.new(lookVector.X, 0, lookVector.Z)
	if lookXZ.Magnitude > 0.001 then
		lookXZ = lookXZ.Unit
	else
		lookXZ = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z).Unit
	end

	local rightXZ = Vector3.new(rightVector.X, 0, rightVector.Z)
	if rightXZ.Magnitude > 0.001 then
		rightXZ = rightXZ.Unit
	else
		rightXZ = Vector3.new(hrp.CFrame.RightVector.X, 0, hrp.CFrame.RightVector.Z).Unit
	end

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
		ctx.EstadoAtual.estadoAcao == "Atacando"
		or ctx.EstadoAtual.estadoAcao == "Defendendo"
		or ctx.EstadoAtual.bloqueando
	)

	local podeCorrer = ctx.MovementFlags.isRunning and not emCombate
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

-- ═══════════════════════════════════════════════════════════════════
-- Velocidade de animação
-- ═══════════════════════════════════════════════════════════════════

local function ObterMultiplicadorVelocidadeAnimacao(): number
	local estado = ctx.EstadoAtual.estadoMov
	local multiplicador = 1

	if estado == "Correndo" and (ctx.MovementFlags.isJumping or ctx.MovementFlags.isFalling) then
		multiplicador = ctx.TIMINGS.RunInAirSpeed
	end

	if estado == "Andando" then
		local emDefendendo = (ctx.EstadoAtual.estadoAcao == "Defendendo")
		local emAtacando = (ctx.EstadoAtual.estadoAcao == "Atacando")

		if emDefendendo then
			multiplicador = 0.55
		elseif emAtacando then
			multiplicador = 0.85
		end
	end

	if ctx.EstadoAtual.agachado and estado == "Andando" then
		multiplicador = 0.8
	end

	local walkSpeed = ctx.Humanoid.WalkSpeed
	local baseAnim: number? = nil

	if ctx.EstadoAtual.agachado and (estado == "Andando" or estado == "Parado") then
		baseAnim = ctx.Modulo_Configuracoes.ObterConfiguracao("VelocidadeBaseAnimAgachando") or 9
	elseif ctx.EstadoAtual.bloqueando or ctx.EstadoAtual.estadoAcao == "Defendendo" then
		baseAnim = ctx.Modulo_Configuracoes.ObterConfiguracao("VelocidadeBaseAnimBloqueando") or 6
	elseif estado == "Correndo" then
		baseAnim = ctx.Modulo_Configuracoes.ObterConfiguracao("VelocidadeBaseAnimCorrendo") or 21
	elseif estado == "Andando" then
		baseAnim = ctx.Modulo_Configuracoes.ObterConfiguracao("VelocidadeBaseAnimAndando") or 14
	end

	if baseAnim and baseAnim > 0 then
		local ratio = walkSpeed / baseAnim
		local delta = ratio - 1
		local adjustedRatio = 1 + delta * 1.05
		multiplicador = multiplicador * math.max(0.3, adjustedRatio)
	end

	return multiplicador
end

function Animacao.DefinirVelocidadeMovimento(velocidadeBase: number)
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

-- ═══════════════════════════════════════════════════════════════════
-- Parar animações
-- ═══════════════════════════════════════════════════════════════════

function Animacao.PararAnimacaoMov(forcarParar: boolean?)
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

			animacaoAtualMov:Stop(ctx.TIMINGS.MoveFadeOut)
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

					animacaoAtualMov:Stop(ctx.TIMINGS.MoveFadeOut)
					animacaoAtualMov = nil
					animacaoMovPausada = false
					ultimaAnimacaoMovNome = nil

					Animacao.AtualizarAnimacaoMovimento()
				end
				timerPararAnimacao = nil
			end)
		end
	end
end

function Animacao.PararAnimacaoAcao()
	ctx.GerenciadorHitboxCliente.PararTodas()

	-- Delegar limpeza de combo ao módulo Combo
	if Combo then
		Combo.LimparParaParadaAcao()
	end

	if animacaoAtualAcao then
		-- Corrigido: removido AdjustSpeed(0) antes de Stop() para evitar flick visual
		animacaoAtualAcao:Stop(ctx.TIMINGS.ActionFadeOut)
		animacaoAtualAcao = nil
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- Tocar animação de movimento
-- ═══════════════════════════════════════════════════════════════════

function Animacao.TocarAnimacaoMov(nomeAnimacao: string, velocidadeBase: number?)
	local animId = ctx.Modulo_Configuracoes.ObterIdAnimacao(ctx.EstadoAtual.modoAnimacao, nomeAnimacao)
	if not animId then
		return
	end

	local track = Animacao.ObterAnimacao(animId)
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
		Animacao.LimparJumpAnimState()
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
		Animacao.PararAnimacaoMov(true)
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

		local fadeIn = ctx.TIMINGS.MoveFadeIn
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
			Animacao.LimparJumpAnimState()
			jumpAnimState.animacao = track
			jumpAnimState.aguardandoTermino = true
			jumpAnimState.conexaoTermino = track.Stopped:Connect(OnJumpAnimacaoTerminou)
			ctx.DebugPrint("[Animacao] Animação de Pulando iniciada (sem loop, aguardando término)")
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

-- ═══════════════════════════════════════════════════════════════════
-- Tocar animação de ação (combo, roll, dash, equip, defesa, etc.)
-- ═══════════════════════════════════════════════════════════════════

function Animacao.TocarAnimacaoAcao(animId: string, loop: boolean, velocidade: number, nomeAnimacao: string?)
	if ctx.ParkourState.ativo then
		return
	end

	local track = Animacao.ObterAnimacao(animId)
	if not track then
		return
	end

	local ehEquipar = nomeAnimacao and (nomeAnimacao == "Equipar" or nomeAnimacao == "Desequipar")
	local ehRoll = nomeAnimacao and (nomeAnimacao:match("^Roll"))
	local ehDash = nomeAnimacao and (nomeAnimacao:match("^Dash"))

	if ehEquipar and Equipamento then
		local equipAnim = Equipamento.ObterAnimacaoEquip()
		if equipAnim and equipAnim.IsPlaying then
			ctx.DebugPrint("[Animacao] Já há animação de equip tocando, ignorando")
			return
		end
	end

	Animacao.PararAnimacaoAcao()

	track.Priority = if nomeAnimacao == "DefesaQuebrada"
		then Enum.AnimationPriority.Movement
		else Enum.AnimationPriority.Action
	track.Looped = loop
	local fadeTime = if ehRoll then 0.2 else 0.1
	track:Play(fadeTime)
	track:AdjustSpeed(velocidade)

	animacaoAtualAcao = track

	-- Parar qualquer outra track com prioridade Action no animator para evitar sobreposição
	for _, t in ipairs(ctx.Animator:GetPlayingAnimationTracks()) do
		if t.Priority == Enum.AnimationPriority.Action and t ~= track then
			t:Stop(0.1)
		end
	end

	-- ======== ROLL ========
	if ehRoll and Esquiva then
		Esquiva.ProcessarRoll(track, nomeAnimacao, velocidade)
		return
	end

	-- ======== DASH ========
	if ehDash and Esquiva then
		Esquiva.ProcessarDash(track, nomeAnimacao, velocidade)
		return
	end

	-- ======== EQUIP ========
	if ehEquipar and Equipamento then
		Equipamento.ProcessarEquip(track, nomeAnimacao)
		return
	end

	-- ======== COMBO ========
	local ehCombo = nomeAnimacao and (nomeAnimacao == "Ataque" or nomeAnimacao:match("^Ataque"))
	if ehCombo and Combo then
		Combo.ProcessarCombo(track, nomeAnimacao, velocidade)
		return
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- Atualizar animação de movimento (estado → animação)
-- ═══════════════════════════════════════════════════════════════════

function Animacao.AtualizarAnimacaoMovimento()
	if ctx.MovementFlags.isRolling or ctx.MovementFlags.isDashing then
		return
	end

	if ctx.ParkourState.ativo then
		if ctx.EstadoAtual.estadoAcao ~= "Parkour" then
			ctx.EstadoAtual.estadoAcao = "Parkour"
		end
		if ctx.EstadoAtual.estadoMov ~= "Parkour" then
			ctx.EstadoAtual.estadoMov = "Parkour"
		end
		Movimento.SincronizarStatusLocal()
		return
	end

	Movimento.SincronizarStatusLocal()

	local estado = ctx.EstadoAtual.estadoMov
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
	if ctx.EstadoAtual.agachado then
		if estado == "Andando" then
			nomeAnimacao = "AndandoAgachado"
		else
			nomeAnimacao = "IdleAgachado"
		end
	else
		nomeAnimacao = mapaAnimacoes[estado] or "Idle"
	end

	if ctx.MovementFlags.isRunning and (nomeAnimacao == "Pulando" or nomeAnimacao == "Caindo") then
		if ctx.DEBUG_ENABLED then
			print(string.format("[DEBUG] GUARD: Bloqueando %s enquanto corre -> forçando Correndo", nomeAnimacao))
		end
		nomeAnimacao = "Correndo"
		ctx.EstadoAtual.estadoMov = "Correndo"
		velocidade = ctx.TIMINGS.RunInAirSpeed
	end

	local animacaoQueUsaDirecao = ANIMACOES_COM_DIRECAO[ultimaAnimacaoMovNome]
	local querIdle = (nomeAnimacao == "Idle" or nomeAnimacao == "IdleAgachado")

	if querIdle then
		if animacaoQueUsaDirecao and animacaoAtualMov and animacaoAtualMov.IsPlaying and not animacaoMovPausada then
			Animacao.PararAnimacaoMov(false)
		elseif not animacaoMovPausada then
			Animacao.PararAnimacaoMov(true)
		end
		return
	end

	if (nomeAnimacao == "Andando" or nomeAnimacao == "Correndo") and not ctx.EstadoAtual.agachado then
		local tipoLateral, velocidadeLateral = CalcularMovimentoLateral()
		if tipoLateral ~= "Nenhum" then
			if ultimaAnimacaoMovNome == tipoLateral and animacaoAtualMov and animacaoAtualMov.IsPlaying then
				velocidadeAnimacaoAlvo = velocidadeLateral * velocidade
				return
			end

			local tempoDesdeUltimaTroca = os.clock() - ultimaTrocaLateralTime
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

			if animacaoAtualEhDirecional and animacaoAtualMov then
				tempoAtual = animacaoAtualMov.TimePosition
				velocidadeAnterior = animacaoAtualMov.Speed
			elseif walkCycleState.time > 0 then
				tempoAtual = walkCycleState.time
				velocidadeAnterior = walkCycleState.speed
			end

			local lateralAnimId = ctx.Modulo_Configuracoes.ObterIdAnimacao(ctx.EstadoAtual.modoAnimacao, tipoLateral)
			if lateralAnimId then
				local lateralTrack = Animacao.ObterAnimacao(lateralAnimId)
				if lateralTrack then
					if animacaoAtualMov and animacaoAtualMov ~= lateralTrack then
						Animacao.PararAnimacaoMov(true)
					end

					lateralTrack.Priority = Enum.AnimationPriority.Movement
					lateralTrack.Looped = true
					lateralTrack:Play(ctx.TIMINGS.MoveFadeIn)

					if tempoAtual > 0 then
						local tempoAlvo = tempoAtual

						local estaEmReverso = velocidadeLateral < 0
						local estavaEmReverso = velocidadeAnterior < 0

						if estaEmReverso ~= estavaEmReverso then
							tempoAlvo = lateralTrack.Length - (tempoAtual % lateralTrack.Length)
						end
						lateralTrack.TimePosition = tempoAlvo % lateralTrack.Length
						walkCycleState.time = 0
					end

					local velocidadeFinalScale = velocidadeLateral * velocidade
					lateralTrack:AdjustSpeed(velocidadeFinalScale)
					velocidadeAnimacaoAtual = velocidadeFinalScale
					velocidadeAnimacaoAlvo = velocidadeFinalScale

					animacaoAtualMov = lateralTrack
					animacaoUsaDirecao = true
					animacaoMovPausada = false
					ultimaAnimacaoMovNome = tipoLateral

					direcaoAtual = velocidadeLateral > 0 and 1 or -1
					ultimaTrocaLateralTime = os.clock()
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

				if animacaoAtualEhDirecional and animacaoAtualMov then
					tempoAtual = animacaoAtualMov.TimePosition
					velocidadeAnterior = animacaoAtualMov.Speed
				elseif walkCycleState.time > 0 then
					tempoAtual = walkCycleState.time
					velocidadeAnterior = walkCycleState.speed
				end

				Animacao.TocarAnimacaoMov(nomeAnimacao, velocidade)

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

	Animacao.TocarAnimacaoMov(nomeAnimacao, velocidade)
end

-- ═══════════════════════════════════════════════════════════════════
-- RenderStepped: suavização de direção de animação
-- ═══════════════════════════════════════════════════════════════════

function Animacao.AtualizarDirecaoAnimacao(deltaTime: number)
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

	if (ctx.EstadoAtual.estadoMov == "Andando" or ctx.EstadoAtual.estadoMov == "Correndo") and not ctx.EstadoAtual.agachado then
		local tipoLateral, velocidadeLateral = CalcularMovimentoLateral()
		local emAnimacaoLateral = (
			ultimaAnimacaoMovNome == "AndandoDireita"
			or ultimaAnimacaoMovNome == "AndandoEsquerda"
			or ultimaAnimacaoMovNome == "CorrendoDireita"
			or ultimaAnimacaoMovNome == "CorrendoEsquerda"
		)

		if tipoLateral ~= "Nenhum" then
			if not emAnimacaoLateral or ultimaAnimacaoMovNome ~= tipoLateral then
				Animacao.AtualizarAnimacaoMovimento()
				return
			else
				velocidadeAnimacaoAlvo = velocidadeLateral * ObterMultiplicadorVelocidadeAnimacao()
				direcaoAtual = velocidadeLateral > 0 and 1 or -1
			end
		elseif emAnimacaoLateral then
			Animacao.AtualizarAnimacaoMovimento()
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
	if ctx.EstadoAtual.estadoMov == "Correndo" then
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

-- ═══════════════════════════════════════════════════════════════════
-- Inicialização
-- ═══════════════════════════════════════════════════════════════════

function Animacao.Inicializar(contexto)
	ctx = contexto
	Movimento = ctx.Modulos.Movimento
	Combo = ctx.Modulos.Combo
	Equipamento = ctx.Modulos.Equipamento
	Esquiva = ctx.Modulos.Esquiva

	-- RenderStepped de suavização de direção
	ctx.ConectarGlobal(RunService.RenderStepped, Animacao.AtualizarDirecaoAnimacao)
end

return Animacao
