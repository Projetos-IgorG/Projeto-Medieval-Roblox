--[[
    Script: Movimento.luau
    Caminho: src/StarterPlayer/StarterCharacterScripts/Jogador/Estado/Modulos
    Responsabilidade: Controle de WalkSpeed, ramping gradual de velocidade, estados de locomocao e sincronizacao com o servidor.
    Uso: ModuleScript; inicializado pelo ControladorEstadoPersonagem via Inicializar(ctx).
    Nao faz: Nao gerencia animacoes diretamente; delega ao modulo Animacao.
    Funcoes principais: AtualizarVelocidadeLocal, SincronizarStatusLocal, AtualizarEstadoMovimento, OnStateChanged
]]

local RunService = game:GetService("RunService")

local Movimento = {}

local ctx
local Animacao -- referencia cruzada, preenchida em Inicializar

-- Estado de ramping
local velocidadeRampAlvo
local velocidadeRampAtual
local rampAtivo = true
local rampSnap = false

local function ObterVelocidadeInicial(): number
	return ctx.Modulo_Configuracoes.ObterConfiguracao("VelocidadeInicialMovimento") or 5
end

function Movimento.AtualizarVelocidadeLocal()
	local VelBloq = ctx.Modulo_Configuracoes.ObterConfiguracao("VelocidadeBloqueando")
	local VelAgachando = ctx.Modulo_Configuracoes.ObterConfiguracao("VelocidadeAgachando")
	local VelCorrendo = ctx.Modulo_Configuracoes.ObterConfiguracao("VelocidadeCorrendo")
	local VelAndando = ctx.Modulo_Configuracoes.ObterConfiguracao("VelocidadeAndando")

	local emCombate = (ctx.EstadoAtual.estadoAcao == "Atacando")

	if emCombate then
		local velBloq = VelBloq or 8
		velocidadeRampAlvo = velBloq * 1.5
		rampAtivo = false
		rampSnap = true
		return
	end

	if ctx.EstadoAtual.estadoAcao == "Defendendo" or ctx.EstadoAtual.bloqueando then
		velocidadeRampAlvo = VelBloq or 8
		rampAtivo = false
		rampSnap = true
		return
	end

	if ctx.EstadoAtual.agachado then
		velocidadeRampAlvo = VelAgachando or 12
		rampAtivo = false
		rampSnap = true
	elseif ctx.MovementFlags.isRunning then
		velocidadeRampAlvo = VelCorrendo or 20
		rampAtivo = true
	else
		velocidadeRampAlvo = VelAndando or 12
		rampAtivo = true
	end
end

local function HeartbeatRamping(dt: number)
	if not ctx.Humanoid or not ctx.Humanoid.Parent then
		return
	end

	Movimento.AtualizarVelocidadeLocal()

	if rampSnap then
		velocidadeRampAtual = velocidadeRampAlvo
		ctx.Humanoid.WalkSpeed = velocidadeRampAtual
		rampSnap = false
		return
	end

	if not rampAtivo then
		return
	end

	local velocidadeInicial = ObterVelocidadeInicial()

	if ctx.Humanoid.MoveDirection.Magnitude < 0.01 then
		local desaceleracao = ctx.Modulo_Configuracoes.ObterConfiguracao("DesaceleracaoMovimento") or 40
		if velocidadeRampAtual > velocidadeInicial then
			velocidadeRampAtual = math.max(velocidadeInicial, velocidadeRampAtual - desaceleracao * dt)
		else
			velocidadeRampAtual = velocidadeInicial
		end
		ctx.Humanoid.WalkSpeed = velocidadeRampAtual
		return
	end

	local aceleracao
	if ctx.MovementFlags.isRunning then
		aceleracao = ctx.Modulo_Configuracoes.ObterConfiguracao("AceleracaoCorrendo") or 25
	else
		aceleracao = ctx.Modulo_Configuracoes.ObterConfiguracao("AceleracaoAndando") or 30
	end

	local diff = velocidadeRampAlvo - velocidadeRampAtual
	if math.abs(diff) < 0.05 then
		velocidadeRampAtual = velocidadeRampAlvo
	else
		local sinal = (diff > 0) and 1 or -1
		local taxa = (diff > 0) and aceleracao
			or (ctx.Modulo_Configuracoes.ObterConfiguracao("DesaceleracaoMovimento") or 40)
		local passo = sinal * math.min(math.abs(diff), taxa * dt)
		velocidadeRampAtual = velocidadeRampAtual + passo
	end
	ctx.Humanoid.WalkSpeed = velocidadeRampAtual
end

function Movimento.SincronizarStatusLocal()
	local statusLocal = ctx.Character:FindFirstChild("StatusLocal")
	if not statusLocal then
		return
	end

	local function atualizarValor(nome, valor)
		local obj = statusLocal:FindFirstChild(nome)
		if obj and (obj:IsA("StringValue") or obj:IsA("BoolValue") or obj:IsA("NumberValue")) then
			(obj :: any).Value = valor
		end
	end

	atualizarValor("modoAnimacao", ctx.EstadoAtual.modoAnimacao)
	atualizarValor("estadoMov", ctx.EstadoAtual.estadoMov)
	atualizarValor("AgachadoOn", ctx.EstadoAtual.agachado)

	atualizarValor("CorrendoOn", ctx.EstadoAtual.estadoMov == "Correndo")

	atualizarValor("RollOn", ctx.MovementFlags.isRolling)
	atualizarValor("DashOn", ctx.MovementFlags.isDashing)
	atualizarValor("estadoAcao", ctx.EstadoAtual.estadoAcao)

	if ctx.DEBUG_ENABLED then
		local val = ctx.EstadoAtual.estadoMov == "Correndo"
		local obj = statusLocal:FindFirstChild("CorrendoOn")
		if obj and obj.Value ~= val then
			print(
				string.format(
					"[DEBUG] CorrendoOn mudou: %s -> %s | EstadoMov: %s",
					tostring(obj.Value),
					tostring(val),
					ctx.EstadoAtual.estadoMov
				)
			)
		end
	end
end

function Movimento.AtualizarEstadoMovimento()
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

	local hrp = ctx.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	if ctx.MovementFlags.isClimbing then
		if ctx.EstadoAtual.estadoMov ~= "Escalando" then
			ctx.EstadoAtual.estadoMov = "Escalando"
			Animacao.AtualizarAnimacaoMovimento()
		end
		return
	end

	if ctx.MovementFlags.isSwimming then
		if ctx.EstadoAtual.estadoMov ~= "Nadando" then
			ctx.EstadoAtual.estadoMov = "Nadando"
			Animacao.AtualizarAnimacaoMovimento()
		end
		return
	end

	if ctx.EstadoAtual.agachado then
		local isMoving = ctx.Humanoid.MoveDirection.Magnitude > 0.1
		local novo = isMoving and "Andando" or "Parado"
		if ctx.EstadoAtual.estadoMov ~= novo then
			ctx.EstadoAtual.estadoMov = novo
			Animacao.AtualizarAnimacaoMovimento()
		end
		return
	end

	if ctx.MovementFlags.isJumping or ctx.MovementFlags.isFalling then
		local emCombate = (ctx.EstadoAtual.estadoAcao == "Atacando" or ctx.EstadoAtual.estadoAcao == "Defendendo")

		if ctx.MovementFlags.isRunning and not emCombate then
			if ctx.EstadoAtual.estadoMov ~= "Correndo" then
				ctx.EstadoAtual.estadoMov = "Correndo"
			end

			Animacao.DefinirVelocidadeMovimento(ctx.TIMINGS.RunInAirSpeed)
			return
		end

		if ctx.MovementFlags.isFalling then
			if ctx.EstadoAtual.estadoMov ~= "Caindo" then
				ctx.EstadoAtual.estadoMov = "Caindo"
				Animacao.AtualizarAnimacaoMovimento()
			end
		elseif ctx.MovementFlags.isJumping then
			if ctx.EstadoAtual.estadoMov ~= "Pulando" then
				ctx.EstadoAtual.estadoMov = "Pulando"
				Animacao.AtualizarAnimacaoMovimento()
			end
		end
		return
	end

	local isMoving = ctx.Humanoid.MoveDirection.Magnitude > 0.1

	local emCombate = (ctx.EstadoAtual.estadoAcao == "Atacando" or ctx.EstadoAtual.estadoAcao == "Defendendo")

	local podeCorrer = ctx.MovementFlags.isRunning and not emCombate

	local novoEstado
	if isMoving then
		novoEstado = podeCorrer and "Correndo" or "Andando"
	else
		novoEstado = "Parado"
	end

	if ctx.EstadoAtual.estadoMov ~= novoEstado then
		if ctx.DEBUG_ENABLED then
			print(
				string.format(
					"[DEBUG] Heartbeat Change: %s -> %s | Jump: %s | Fall: %s | Floor: %s | MoveDir: %.2f",
					ctx.EstadoAtual.estadoMov,
					novoEstado,
					tostring(ctx.MovementFlags.isJumping),
					tostring(ctx.MovementFlags.isFalling),
					tostring(ctx.Humanoid.FloorMaterial),
					ctx.Humanoid.MoveDirection.Magnitude
				)
			)
		end

		ctx.EstadoAtual.estadoMov = novoEstado
		Animacao.AtualizarAnimacaoMovimento()

		ctx.TentarAcao:FireServer("SincronizarMovimento", novoEstado)
	else
		local animMov = Animacao.ObterAnimacaoAtualMov()
		if animMov then
			emCombate = (ctx.EstadoAtual.estadoAcao == "Atacando" or ctx.EstadoAtual.estadoAcao == "Defendendo")
			if not (ctx.EstadoAtual.estadoMov == "Andando" and emCombate) then
				Animacao.DefinirVelocidadeMovimento(1)
			end
		end
	end

	Movimento.SincronizarStatusLocal()
end

function Movimento.OnStateChanged(_oldState, newState)
	if ctx.DEBUG_ENABLED then
		print(
			string.format(
				"[DEBUG] StateChanged: %s -> %s | Material: %s | isRunning: %s | isJumping: %s | isFalling: %s",
				tostring(_oldState),
				tostring(newState),
				tostring(ctx.Humanoid.FloorMaterial),
				tostring(ctx.MovementFlags.isRunning),
				tostring(ctx.MovementFlags.isJumping),
				tostring(ctx.MovementFlags.isFalling)
			)
		)
	end

	if ctx.ParkourState.ativo then
		return
	end

	ctx.MovementFlags.isClimbing = (newState == Enum.HumanoidStateType.Climbing)
	ctx.MovementFlags.isSwimming = (newState == Enum.HumanoidStateType.Swimming)

	if newState == Enum.HumanoidStateType.Jumping then
		ctx.MovementFlags.isJumping = true
		ctx.MovementFlags.isFalling = false

		if ctx.MovementFlags.isRunning then
			ctx.EstadoAtual.estadoMov = "Correndo"

			local animMov = Animacao.ObterAnimacaoAtualMov()
			if animMov and animMov.IsPlaying then
				Animacao.DefinirVelocidadeMovimento(ctx.TIMINGS.RunInAirSpeed)
			else
				Animacao.AtualizarAnimacaoMovimento()
			end
			return
		end
	end

	if newState == Enum.HumanoidStateType.Freefall then
		if Animacao.EstaAguardandoTerminoPulo() then
			return
		end

		ctx.MovementFlags.isJumping = false
		ctx.MovementFlags.isFalling = true

		if ctx.MovementFlags.isRunning then
			ctx.EstadoAtual.estadoMov = "Correndo"
			local animMov = Animacao.ObterAnimacaoAtualMov()
			if animMov and animMov.IsPlaying then
				Animacao.DefinirVelocidadeMovimento(ctx.TIMINGS.RunInAirSpeed)
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
		ctx.MovementFlags.isJumping = false
		ctx.MovementFlags.isFalling = false

		Animacao.LimparJumpAnimState()

		if ctx.MovementFlags.isRunning then
			ctx.EstadoAtual.estadoMov = "Correndo"
			local animMov = Animacao.ObterAnimacaoAtualMov()
			if animMov then
				local emCombate = (
					ctx.EstadoAtual.estadoAcao == "Atacando" or ctx.EstadoAtual.estadoAcao == "Defendendo"
				)
				if not emCombate then
					Animacao.DefinirVelocidadeMovimento(1)
				end
			end

			ctx.TentarAcao:FireServer("SincronizarMovimento", "Correndo")
			return
		end

		ctx.TentarAcao:FireServer("Aterrissar")
	end

	Movimento.AtualizarEstadoMovimento()
end

function Movimento.Inicializar(contexto)
	ctx = contexto
	Animacao = ctx.Modulos.Animacao

	velocidadeRampAlvo = ObterVelocidadeInicial()
	velocidadeRampAtual = ObterVelocidadeInicial()
	ctx.Humanoid.WalkSpeed = velocidadeRampAtual

	-- Heartbeat de ramping de velocidade
	ctx.ConectarGlobal(RunService.Heartbeat, HeartbeatRamping)
end

return Movimento
