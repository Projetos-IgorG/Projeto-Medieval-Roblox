--[[
    Script: Esquiva.luau
    Caminho: src/StarterPlayer/StarterCharacterScripts/Jogador/Estado/Modulos
    Responsabilidade: Roll (esquiva rolando no chao), Dash (impulso rapido lateral/tras)
                      e Parkour (entrar/sair do estado de parkour).
    Uso: ModuleScript; inicializado pelo ControladorEstadoPersonagem via Inicializar(ctx).
    Nao faz: Nao reproduz animacoes diretamente; delega ao modulo Animacao.
    Funcoes principais: ProcessarRoll, ProcessarDash, CalcularDirecaoRoll,
                        EntrarParkour, SairParkour
]]

local RunService = game:GetService("RunService")

local Esquiva = {}

local ctx
local Animacao -- referencia cruzada
local Movimento -- referencia cruzada

-- ═══════════════════════════════════════════════════════════════════
-- Roll State
-- ═══════════════════════════════════════════════════════════════════

local rollState = {
	animacao = nil :: AnimationTrack?,
	direcao = "Frente",
	conexaoTermino = nil :: RBXScriptConnection?,
	velocityConnection = nil :: RBXScriptConnection?,
	earlyCancelTimer = nil :: thread?,
	earlyCancelExecutado = false,
}

-- ═══════════════════════════════════════════════════════════════════
-- Dash State
-- ═══════════════════════════════════════════════════════════════════

local dashState = {
	animacao = nil :: AnimationTrack?,
	direcao = "Tras",
	conexaoTermino = nil :: RBXScriptConnection?,
	velocityConnection = nil :: RBXScriptConnection?,
	earlyCancelTimer = nil :: thread?,
	earlyCancelExecutado = false,
	impulsoTimer = nil :: thread?,
}

-- ═══════════════════════════════════════════════════════════════════
-- Direção compartilhada (roll/dash)
-- ═══════════════════════════════════════════════════════════════════

local function CalcularDirecaoRollLocal(atualizarCFrame: boolean?): string
	local hrp = ctx.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return "Frente"
	end

	local moveDir = ctx.Humanoid.MoveDirection

	if moveDir.Magnitude < 0.1 then
		return "Frente"
	end

	local originalRotation = ctx.ClientBridge.CFrameRotacaoRoll or (hrp.CFrame - hrp.Position)
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
		if atualizarCFrame then
			ctx.ClientBridge.CFrameRotacaoRoll = ObterRotacaoXZ(moveXZ)
		end
		return "Frente"
	elseif angle > 67.5 and angle <= 112.5 then
		return "Direita"
	elseif angle > -112.5 and angle <= -67.5 then
		return "Esquerda"
	elseif math.abs(angle) > 112.5 and math.abs(angle) <= 157.5 then
		if atualizarCFrame then
			ctx.ClientBridge.CFrameRotacaoRoll = ObterRotacaoXZ(-moveXZ)
		end
		return "Tras"
	else
		return "Tras"
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- Roll impulso
-- ═══════════════════════════════════════════════════════════════════

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

local function PararImpulsoRoll()
	if rollState.velocityConnection then
		rollState.velocityConnection:Disconnect()
		rollState.velocityConnection = nil
	end
end

local function IniciarImpulsoRoll(direcao: string)
	local hrp = ctx.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local forcaRoll = ctx.Modulo_Configuracoes.ObterConfiguracao("ForcaRoll") or 45

	if rollState.velocityConnection then
		rollState.velocityConnection:Disconnect()
	end

	local startRotation = ctx.ClientBridge.CFrameRotacaoOriginalRoll or (hrp.CFrame - hrp.Position)
	local targetRotation = ctx.ClientBridge.CFrameRotacaoRoll or startRotation
	local lookVector = targetRotation.LookVector
	local rightVector = targetRotation.RightVector

	local dirVector = ctx.ClientBridge.DirecaoMovimentoRoll
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
	local tempoInicio = os.clock()

	rollState.velocityConnection = RunService.RenderStepped:Connect(function(_deltaTime)
		if not rollState.animacao or not rollState.animacao.IsPlaying then
			PararImpulsoRoll()
			return
		end

		if not hrp or not hrp.Parent then
			PararImpulsoRoll()
			return
		end

		if ctx.EstadoAtual.estadoAcao ~= "Nenhuma" and ctx.EstadoAtual.estadoAcao ~= "Rolando" then
			PararImpulsoRoll()
			return
		end

		local t = math.clamp((os.clock() - tempoInicio) / 0.15, 0, 1)
		local currentRotation = startRotation:Lerp(targetRotation, t)

		local velocidadeAtual = hrp.AssemblyLinearVelocity
		local velocidadeAlvo = dirVector * forcaRoll

		hrp.AssemblyLinearVelocity = Vector3.new(velocidadeAlvo.X, velocidadeAtual.Y, velocidadeAlvo.Z)

		hrp.CFrame = currentRotation + hrp.Position
	end)
end

local function OnRollAnimacaoTerminou()
	ctx.DebugPrint("[Esquiva] Roll animação terminou")

	PararImpulsoRoll()

	rollState.animacao = nil
	rollState.direcao = "Frente"
	ctx.MovementFlags.isRolling = false
	ctx.ClientBridge.CFrameRotacaoRoll = nil
	ctx.ClientBridge.CFrameRotacaoOriginalRoll = nil
	ctx.ClientBridge.PreRollActive = nil
	ctx.ClientBridge.DirecaoMovimentoRoll = nil

	if rollState.conexaoTermino then
		rollState.conexaoTermino:Disconnect()
		rollState.conexaoTermino = nil
	end

	if rollState.earlyCancelTimer then
		pcall(task.cancel, rollState.earlyCancelTimer)
		rollState.earlyCancelTimer = nil
	end

	rollState.earlyCancelExecutado = false

	ctx.TentarAcao:FireServer("RollTerminou")

	ctx.EstadoAtual.estadoAcao = "Nenhuma"

	RestaurarEstadoPosAcao()
	Movimento.AtualizarVelocidadeLocal()
	Animacao.AtualizarAnimacaoMovimento()
end

-- ═══════════════════════════════════════════════════════════════════
-- Dash impulso
-- ═══════════════════════════════════════════════════════════════════

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

local function IniciarImpulsoDash(direcao: string)
	local hrp = ctx.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local forcaDash, duracaoDash
	if direcao == "Tras" then
		forcaDash = ctx.Modulo_Configuracoes.ObterConfiguracao("ForcaDashTras") or 50
		duracaoDash = ctx.Modulo_Configuracoes.ObterConfiguracao("DuracaoDashTras") or 0.12
	else
		forcaDash = ctx.Modulo_Configuracoes.ObterConfiguracao("ForcaDashLateral") or 55
		duracaoDash = ctx.Modulo_Configuracoes.ObterConfiguracao("DuracaoDashLateral") or 0.22
	end

	if dashState.velocityConnection then
		dashState.velocityConnection:Disconnect()
	end

	local tempoInicio = os.clock()

	dashState.velocityConnection = RunService.RenderStepped:Connect(function(_deltaTime)
		if not dashState.animacao or not dashState.animacao.IsPlaying then
			PararImpulsoDash()
			return
		end

		if not hrp or not hrp.Parent then
			PararImpulsoDash()
			return
		end

		if ctx.EstadoAtual.estadoAcao ~= "Nenhuma" and ctx.EstadoAtual.estadoAcao ~= "Dashando" then
			PararImpulsoDash()
			return
		end

		if (os.clock() - tempoInicio) >= duracaoDash then
			PararImpulsoDash()
			return
		end

		-- Obter a orientação atual do corpo (CFrame sem posição)
		local currentRotation = hrp.CFrame - hrp.Position
		local lookVector = currentRotation.LookVector
		local rightVector = currentRotation.RightVector

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

		local velocidadeAtual = hrp.AssemblyLinearVelocity
		local velocidadeAlvo = dirVector * forcaDash

		hrp.AssemblyLinearVelocity = Vector3.new(velocidadeAlvo.X, velocidadeAtual.Y, velocidadeAlvo.Z)
	end)
end

local function OnDashAnimacaoTerminou()
	ctx.DebugPrint("[Esquiva] Dash animação terminou")

	PararImpulsoDash()

	dashState.animacao = nil
	dashState.direcao = "Tras"
	ctx.MovementFlags.isDashing = false
	ctx.ClientBridge.CFrameRotacaoDash = nil
	ctx.ClientBridge.PreDashActive = nil

	if dashState.conexaoTermino then
		dashState.conexaoTermino:Disconnect()
		dashState.conexaoTermino = nil
	end

	if dashState.earlyCancelTimer then
		pcall(task.cancel, dashState.earlyCancelTimer)
		dashState.earlyCancelTimer = nil
	end

	dashState.earlyCancelExecutado = false

	ctx.TentarAcao:FireServer("DashTerminou")

	ctx.EstadoAtual.estadoAcao = "Nenhuma"

	RestaurarEstadoPosAcao()
	Movimento.AtualizarVelocidadeLocal()
	Animacao.AtualizarAnimacaoMovimento()
end

-- ═══════════════════════════════════════════════════════════════════
-- Chamado por Animacao.TocarAnimacaoAcao quando é Roll
-- ═══════════════════════════════════════════════════════════════════

function Esquiva.ProcessarRoll(track: AnimationTrack, nomeAnimacao: string, _velocidade: number)
	ctx.ClientBridge.PreRollActive = nil
	ctx.ClientBridge.UltimoRollTime = os.clock()
	if rollState.conexaoTermino then
		rollState.conexaoTermino:Disconnect()
	end
	PararImpulsoRoll()
	Animacao.PararAnimacaoMov(true)

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
	ctx.MovementFlags.isRolling = true

	rollState.conexaoTermino = track.Stopped:Connect(function()
		OnRollAnimacaoTerminou()
	end)

	IniciarImpulsoRoll(direcao)

	ctx.DebugPrint("[Esquiva] Animação de Roll iniciada:", nomeAnimacao)

	if rollState.earlyCancelTimer then
		pcall(task.cancel, rollState.earlyCancelTimer)
		rollState.earlyCancelTimer = nil
	end
	rollState.earlyCancelExecutado = false

	local function SetupEarlyCancel()
		if not rollState.animacao or not rollState.animacao.IsPlaying then
			return
		end

		local rollTrack = rollState.animacao
		local length = rollTrack.Length

		if length == 0 then
			local connection
			connection = rollTrack:GetPropertyChangedSignal("Length"):Connect(function()
				connection:Disconnect()
				SetupEarlyCancel()
			end)
			task.delay(0.05, function()
				if connection.Connected then
					connection:Disconnect()
					SetupEarlyCancel()
				end
			end)
			return
		end

		local tempoRestante = (length - rollTrack.TimePosition) / rollTrack.Speed
		local janelaEarlyCancel = ctx.Modulo_Configuracoes.ObterConfiguracao("JanelaCancelamentoRoll") or 0.2

		if tempoRestante > janelaEarlyCancel and janelaEarlyCancel > 0 then
			local tempoParaEarlyCancel = tempoRestante - janelaEarlyCancel

			rollState.earlyCancelTimer = task.delay(tempoParaEarlyCancel, function()
				if rollState.animacao and rollState.animacao.IsPlaying and not rollState.earlyCancelExecutado then
					rollState.earlyCancelExecutado = true
					ctx.DebugPrint("[Esquiva] Roll early cancel/cross-fade executado")

					ctx.EstadoAtual.estadoAcao = "Nenhuma"

					ctx.TentarAcao:FireServer("RollEarlyCancel")

					RestaurarEstadoPosAcao()
					Movimento.AtualizarVelocidadeLocal()
					Animacao.AtualizarAnimacaoMovimento()
				end
			end)
		end
	end

	SetupEarlyCancel()
end

-- ═══════════════════════════════════════════════════════════════════
-- Chamado por Animacao.TocarAnimacaoAcao quando é Dash
-- ═══════════════════════════════════════════════════════════════════

function Esquiva.ProcessarDash(track: AnimationTrack, nomeAnimacao: string, _velocidade: number)
	ctx.ClientBridge.PreDashActive = nil
	ctx.ClientBridge.UltimoDashTime = os.clock()
	if dashState.conexaoTermino then
		dashState.conexaoTermino:Disconnect()
	end
	PararImpulsoDash()
	Animacao.PararAnimacaoMov(true)

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
	ctx.MovementFlags.isDashing = true

	dashState.conexaoTermino = track.Stopped:Connect(function()
		OnDashAnimacaoTerminou()
	end)

	IniciarImpulsoDash(direcao)

	ctx.DebugPrint("[Esquiva] Animação de Dash iniciada:", nomeAnimacao)

	if dashState.earlyCancelTimer then
		pcall(task.cancel, dashState.earlyCancelTimer)
		dashState.earlyCancelTimer = nil
	end
	dashState.earlyCancelExecutado = false

	local function SetupEarlyCancel()
		if not dashState.animacao or not dashState.animacao.IsPlaying then
			return
		end

		local dashTrack = dashState.animacao
		local length = dashTrack.Length

		if length == 0 then
			local connection
			connection = dashTrack:GetPropertyChangedSignal("Length"):Connect(function()
				connection:Disconnect()
				SetupEarlyCancel()
			end)
			task.delay(0.05, function()
				if connection.Connected then
					connection:Disconnect()
					SetupEarlyCancel()
				end
			end)
			return
		end

		local tempoRestante = (length - dashTrack.TimePosition) / dashTrack.Speed
		local janelaEarlyCancel = ctx.Modulo_Configuracoes.ObterConfiguracao("JanelaCancelamentoDash") or 0.2

		if tempoRestante > janelaEarlyCancel and janelaEarlyCancel > 0 then
			local tempoParaEarlyCancel = tempoRestante - janelaEarlyCancel

			dashState.earlyCancelTimer = task.delay(tempoParaEarlyCancel, function()
				if dashState.animacao and dashState.animacao.IsPlaying and not dashState.earlyCancelExecutado then
					dashState.earlyCancelExecutado = true
					ctx.DebugPrint("[Esquiva] Dash early cancel/cross-fade executado")

					ctx.MovementFlags.isDashing = false
					ctx.EstadoAtual.estadoAcao = "Nenhuma"

					ctx.TentarAcao:FireServer("DashEarlyCancel")

					RestaurarEstadoPosAcao()
					Movimento.AtualizarVelocidadeLocal()
					Animacao.AtualizarAnimacaoMovimento()
				end
			end)
		end
	end

	SetupEarlyCancel()
end

-- ═══════════════════════════════════════════════════════════════════
-- Parkour
-- ═══════════════════════════════════════════════════════════════════

function Esquiva.EstaEmParkour(): boolean
	return ctx.ParkourState.ativo
end

function Esquiva.EntrarParkour()
	if ctx.ParkourState.ativo then
		return
	end

	ctx.ParkourState.ativo = true
	ctx.ParkourState.estadoAcaoAnterior = ctx.EstadoAtual.estadoAcao

	Animacao.PararAnimacaoAcao()
	Animacao.PararAnimacaoMov(true)

	ctx.EstadoAtual.estadoAcao = "Parkour"
	ctx.EstadoAtual.estadoMov = "Parkour"
	ctx.EstadoAtual.correndo = false
	ctx.MovementFlags.isRunning = false
	Movimento.AtualizarVelocidadeLocal()
	Movimento.SincronizarStatusLocal()
end

function Esquiva.SairParkour()
	if not ctx.ParkourState.ativo then
		return
	end

	ctx.ParkourState.ativo = false

	if ctx.EstadoAtual.estadoAcao == "Parkour" then
		ctx.EstadoAtual.estadoAcao = "Nenhuma"
	end

	ctx.MovementFlags.isJumping = false
	ctx.MovementFlags.isFalling = false

	if ctx.Humanoid.FloorMaterial == Enum.Material.Air then
		ctx.MovementFlags.isFalling = true
		ctx.EstadoAtual.estadoMov = "Caindo"
	elseif ctx.EstadoAtual.estadoMov == "Parkour" then
		ctx.EstadoAtual.estadoMov = "Parado"
	end

	if ctx.IsShiftHeld() then
		ctx.MovementFlags.isRunning = true
		ctx.EstadoAtual.correndo = true

		if
			ctx.Humanoid.MoveDirection.Magnitude > 0.1
			and not ctx.MovementFlags.isJumping
			and not ctx.MovementFlags.isFalling
			and not ctx.MovementFlags.isClimbing
			and not ctx.MovementFlags.isSwimming
		then
			ctx.EstadoAtual.estadoMov = "Correndo"
		end
	else
		ctx.MovementFlags.isRunning = false
		ctx.EstadoAtual.correndo = false
	end

	Movimento.AtualizarVelocidadeLocal()
	Animacao.AtualizarBaseIdle()
	Animacao.AtualizarAnimacaoMovimento()
end

function Esquiva.EstaEmRoll(): boolean
	return ctx.MovementFlags.isRolling
end

function Esquiva.EstaEmDash(): boolean
	return ctx.MovementFlags.isDashing
end

-- ═══════════════════════════════════════════════════════════════════
-- Inicialização
-- ═══════════════════════════════════════════════════════════════════

function Esquiva.Inicializar(contexto)
	ctx = contexto
	Animacao = ctx.Modulos.Animacao
	Movimento = ctx.Modulos.Movimento

	-- Registrar funções no ClientBridge
	ctx.ClientBridge.CalcularDirecaoRoll = CalcularDirecaoRollLocal
	ctx.ClientBridge.CalcularDirecaoDash = CalcularDirecaoRollLocal
	ctx.ClientBridge.EstaEmRoll = Esquiva.EstaEmRoll
	ctx.ClientBridge.EstaEmDash = Esquiva.EstaEmDash
	ctx.ClientBridge.EstaEmParkour = Esquiva.EstaEmParkour
	ctx.ClientBridge.EntrarParkour = Esquiva.EntrarParkour
	ctx.ClientBridge.SairParkour = Esquiva.SairParkour
end

return Esquiva
