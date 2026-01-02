--[[═══════════════════════════════════════════════════════════════════════════
    StateController - Sistema de Animações e Combate
    ──────────────────────────────────────────────────────────────────────────
    Local: StarterPlayer > StarterCharacterScripts > StateController
    
    (!!!NÃO ALTERAR ESTE COMENTÁRIO EM HIPÓTESE ALGUMA!!!)
    
    ARQUITETURA:
    ────────────
    • Máquina de estados separada: Movimento (estadoMovi) + Ação (estadoAcao)
    • Modo de combate (modoCombate): Base, UmaMaoEscudo, Punhos
    • Integração com ShiftLockController via PlayerScripts.ShiftlockStatus
    • Sistema de animações modular baseado em AnimationIDs
    
    ESTADOS PUBLICADOS NO CHARACTER:
    ────────────────────────────────
    • StringValue "modoCombate": modo atual de combate
    • StringValue "estadoMovi": estado de movimento atual
    • StringValue "estadoAcao": estado de ação/combate atual
    
    CONTROLES:
    ──────────
    • M1 (clique): Combo leve (4 hits com janelas de timing)
    • M1 (segurar): Carrega ataque pesado
    • M2 (segurar + ShiftLock): Defesa
    • G (durante defesa): Defesa quebrada
    • E: Equipar/Desequipar UmaMaoEscudo
    • R: Equipar/Desequipar Punhos
    • LeftShift: Corrida
    • LeftControl: Toggle ShiftLock
    
═══════════════════════════════════════════════════════════════════════════]]

--═══════════════════════════════════════════════════════════════════════════
-- SEÇÃO 1: SERVIÇOS E REFERÊNCIAS
--═══════════════════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Debug helper
local DEBUG = false
local function dprint(...) if DEBUG then print("[StateController]", ...) end end

-- Player e Character
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
local hrp = character:WaitForChild("HumanoidRootPart")

-- Desabilitar script Animate padrão
local animateScript = character:FindFirstChild("Animate")
if animateScript and animateScript:IsA("Script") then
	animateScript.Disabled = true
end

-- Módulos externos
local AnimationIDs = require(ReplicatedStorage.Modules:WaitForChild("AnimationIDs"))
local HitboxClient = require(ReplicatedStorage.Modules:WaitForChild("HitboxClient"))
local CombatCore = require(ReplicatedStorage.Modules:WaitForChild("CombatCore"))

-- RemoteEvents
local PlayerTryHit = ReplicatedStorage:WaitForChild("PlayerTryHit")
local SetBlockingRemote = ReplicatedStorage:WaitForChild("SetBlocking")
local SyncEstadoAcaoRemote = ReplicatedStorage:WaitForChild("SyncEstadoAcao")

-- Estados publicados
local statusFolder = character:WaitForChild("Status")
local modoCombateValue = statusFolder:WaitForChild("modoAnimacao")
local estadoMovi = statusFolder:WaitForChild("estadoMov")
local estadoAcao = statusFolder:WaitForChild("estadoAcao")

--═══════════════════════════════════════════════════════════════════════════
-- SEÇÃO 2: CONFIGURAÇÕES CONSTANTES
--═══════════════════════════════════════════════════════════════════════════

-- Velocidades de movimento
local SPEEDS = {
	Walk = 16,
	Run = 25,
	Block = 8,
	BrokenDefense = 3,
	Stun = 4,
	Climb = 12,
}

-- Tempos e delays
local TIMINGS = {
	ChargeDelay = 0.2,          -- Tempo para iniciar carga de ataque pesado
	ComboWindow = 0.2,          -- Janela de timing para continuar combo
	ComboSlowdown = 0.4,        -- Velocidade da animação na janela de combo
	JumpHold = 0.28,            -- Hold de animação de pulo antes de transitar para queda
	ClimbExitJumpHold = 0.08,   -- Hold reduzido ao pular de escada
	StunDuration = 0.7,         -- Duração mínima de stun visual
	RunInAirSpeed = 0.4,        -- Velocidade da animação de corrida no ar
	ParryReadyDelay = 0.2,      -- Tempo para entrar em estado ProntoAparar
}

-- Cooldowns por ação
local COOLDOWNS = {
	LightCombo = 0.5,
	HeavyAttack = 2.0,
	Block = 0.5,
	ParryReady = 2.0,
}

-- Fade times para transições de animação
local FADE = {
	MoveIn = 0.18,
	MoveOut = 0.18,
	ActionIn = 0.10,
	ActionOut = 0.10,
	SoftEnd = 0.40,
}

-- Configurações de escalada
local CLIMB_DEADZONE = 0.05  -- Movimento mínimo para considerar "andando" na escada

-- Preview de hitbox (debug)
local HITBOX_PREVIEW = true

-- Modo de combate que o E irá equipar para testes (futuro: pegar do item)
local modoAnimacaoCombatEquip_Test = "UmaMaoEscudo"

--═══════════════════════════════════════════════════════════════════════════
-- SEÇÃO 3: ESTADO RUNTIME
--═══════════════════════════════════════════════════════════════════════════

-- Estados de movimento
local movementState = {
	isRunning = false,
	isJumping = false,
	isFalling = false,
	isClimbing = false,
	isSwimming = false,
}

-- Estados de input
local inputState = {
	m1Down = false,
	m1Held = false,
	shiftlockOn = false,
}

-- Sistema de cooldown
local cooldownTimers = {
	lightCombo = 0,
	heavyAttack = 0,
	block = 0,
	parryReady = 0,
}

-- Sistema de combo leve
local comboSystem = {
	track = nil,
	connections = {},
	windowOpen = false,
	consumed = false,
	pendingConsume = false,
	token = 0,
}

-- Sistema de ataque pesado
local heavySystem = {
	track = nil,
	connections = {},
	pressToken = 0,
	released = false,
	reachedMarker = false,
}

-- Cache de animações e trilhas atuais
local animCache = {}  -- [setName][animName] = AnimationTrack
local currentTracks = {
	movement = nil,
	action = nil,
}

-- Controle de pulo
local jumpHoldUntil = 0

-- Animação de nado (fallback)
local swimTrack = nil
local SWIM_FALLBACK_ID = "rbxassetid://180426354"

-- Stun
local stunActive = false

-- JumpPower original
local DEFAULT_JUMP_POWER = humanoid.JumpPower

--═══════════════════════════════════════════════════════════════════════════
-- SEÇÃO 4: UTILITÁRIOS GERAIS
--═══════════════════════════════════════════════════════════════════════════

--- Retorna o tempo atual em segundos
local function now()
	return os.clock()
end

--- Verifica se pode executar ação (cooldown expirou)
local function canPerformAction(actionKey)
	return now() >= cooldownTimers[actionKey]
end

--- Define cooldown para uma ação
local function setCooldown(actionKey, duration)
	cooldownTimers[actionKey] = now() + duration
end

--- Verifica se está em ShiftLock ou Primeira Pessoa
local function isShiftlockOrFirstPerson()
	-- Usa a flag moderna criada por Setup.lua: Status.ShiftLockOn dentro do Character
	local status = character:FindFirstChild("Status")
	if not status then return false end
	local v = status:FindFirstChild("ShiftLockOn")
	return v and v.Value
end

--- Verifica se o jogador está stunado
local function isStunned()
	local stunadoOn = statusFolder:FindFirstChild("StunadoOn")
	return stunadoOn and stunadoOn:IsA("BoolValue") and stunadoOn.Value == true
end

--- Limpa conexões de uma lista
local function disconnectAll(connections)
	for _, conn in ipairs(connections) do
		if conn and conn.Disconnect then
			conn:Disconnect()
		end
	end
	table.clear(connections)
end

--═══════════════════════════════════════════════════════════════════════════
-- SEÇÃO 5: SISTEMA DE ANIMAÇÕES
--═══════════════════════════════════════════════════════════════════════════

--- Resolve nome do set (fallback para Base se não existir)
local function resolveSetName(requestedSet)
	if requestedSet and AnimationIDs[requestedSet] then
		return requestedSet
	end
	return "Base"
end

--- Carrega todas as animações de um set
local function loadAnimationSet(setName)
	setName = resolveSetName(setName)

	if animCache[setName] then
		return setName
	end

	animCache[setName] = {}
	local setTable = AnimationIDs[setName]

	if setTable then
		for animName, animId in pairs(setTable) do
			-- Validar ID válido
			if type(animId) == "string" and animId:match("^rbxassetid://(%d+)$") and animId ~= "rbxassetid://0000000000" then
				local anim = Instance.new("Animation")
				anim.Name = animName
				anim.AnimationId = animId
				animCache[setName][animName] = animator:LoadAnimation(anim)
			end
		end
	end

	return setName
end

--- Obtém trilha de animação (com fallback para Base)
local function getAnimationTrack(animName, setName)
	setName = setName or modoCombateValue.Value
	setName = resolveSetName(setName)
	loadAnimationSet(setName)

	local track = animCache[setName] and animCache[setName][animName]

	-- Fallback para Base se não encontrar no set atual
	if not track and setName ~= "Base" then
		loadAnimationSet("Base")
		track = animCache["Base"] and animCache["Base"][animName]
	end

	return track
end

--- Para trilha de ação atual
local function stopCurrentAction(fadeTime)
	if currentTracks.action then
		currentTracks.action:Stop(fadeTime or FADE.ActionOut)
		currentTracks.action = nil
	end
end

--- Para trilha de movimento atual
local function stopCurrentMovement(fadeTime)
	if currentTracks.movement then
		currentTracks.movement:Stop(fadeTime or FADE.MoveOut)
		currentTracks.movement = nil
	end
end

--- Reproduz animação de movimento (com crossfade)
local function playMovementAnimation(animName, speedMultiplier)
	if movementState.isSwimming then
		return nil  -- Nado usa lógica separada
	end

	local track = getAnimationTrack(animName)
	if not track then
		return nil
	end

	local previous = currentTracks.movement

	track.Looped = true
	track.Priority = Enum.AnimationPriority.Core
	track:Play(FADE.MoveIn, 1, speedMultiplier or 1)

	if previous and previous ~= track then
		previous:Stop(FADE.MoveOut)
	end

	currentTracks.movement = track
	return track
end

--- Reproduz animação de ação
local function playActionAnimation(animName)
	local track = getAnimationTrack(animName)
	if not track then
		return nil
	end

	stopCurrentAction(FADE.ActionOut)

	track.Looped = false
	track.Priority = Enum.AnimationPriority.Action
	track:Play(FADE.ActionIn, 1, 1)

	currentTracks.action = track
	return track
end

--═══════════════════════════════════════════════════════════════════════════
-- SEÇÃO 6: SISTEMA DE ESTADOS DE MOVIMENTO
--═══════════════════════════════════════════════════════════════════════════

--- Atualiza estado de movimento baseado em condições atuais
local function updateMovementState()
	-- PRIORIDADE 1: Nadando
	if movementState.isSwimming then
		estadoMovi.Value = "Nadando"
		humanoid.WalkSpeed = SPEEDS.Walk

		-- Parar animação de movimento normal
		stopCurrentMovement(FADE.MoveOut)

		-- Iniciar animação de nado
		if not swimTrack then
			local anim = Instance.new("Animation")
			anim.AnimationId = SWIM_FALLBACK_ID
			anim.Name = "SwimFallback"
			swimTrack = animator:LoadAnimation(anim)
			swimTrack.Priority = Enum.AnimationPriority.Core
			swimTrack.Looped = true
		end

		if swimTrack and not swimTrack.IsPlaying then
			swimTrack:Play(FADE.MoveIn)
		end
		return
	else
		if swimTrack and swimTrack.IsPlaying then
			swimTrack:Stop(FADE.MoveOut)
		end
	end

	-- PRIORIDADE 2: Escalando
	if movementState.isClimbing then
		estadoMovi.Value = "Escalando"
		humanoid.WalkSpeed = SPEEDS.Climb

		-- Ajustar velocidade da animação baseado no movimento
		local isMoving = humanoid.MoveDirection.Magnitude > CLIMB_DEADZONE
		if currentTracks.movement then
			currentTracks.movement:AdjustSpeed(isMoving and 0.7 or 0)
		end
		return
	end

	-- PRIORIDADE 3: No ar (Pulando/Caindo)
	if movementState.isJumping or movementState.isFalling then
		-- Se está correndo no ar com input horizontal, manter animação de corrida
		local hasHorizontalMovement = humanoid.MoveDirection.Magnitude > 0.05
		if movementState.isRunning and hasHorizontalMovement then
			if estadoMovi.Value ~= "Correndo" then
				estadoMovi.Value = "Correndo"
			end
			if currentTracks.movement then
				currentTracks.movement:AdjustSpeed(TIMINGS.RunInAirSpeed)
			end
			return
		end

		-- Decidir entre Pulando e Caindo
		local velocityY = (hrp.AssemblyLinearVelocity and hrp.AssemblyLinearVelocity.Y) or hrp.Velocity.Y
		if movementState.isFalling or (movementState.isJumping and velocityY <= -1 and now() >= jumpHoldUntil) then
			if estadoMovi.Value ~= "Caindo" then
				estadoMovi.Value = "Caindo"
			end
		else
			if estadoMovi.Value ~= "Pulando" then
				estadoMovi.Value = "Pulando"
			end
		end
		return
	end

	-- PRIORIDADE 4: No chão - ajustar velocidade baseado no estado de ação
	if estadoAcao.Value == "DefesaQuebrada" or estadoAcao.Value == "Aparado" then
		humanoid.WalkSpeed = SPEEDS.BrokenDefense
		movementState.isRunning = false
	elseif estadoAcao.Value == "Defendendo" then
		humanoid.WalkSpeed = SPEEDS.Block
		movementState.isRunning = false
	elseif estadoAcao.Value == "CarregandoPesado" or estadoAcao.Value == "AtaquePesado" or estadoAcao.Value == "AtacandoLeve" then
		-- No modo Base, permite movimento durante ataque
		if modoCombateValue.Value == "Base" then
			humanoid.WalkSpeed = movementState.isRunning and SPEEDS.Run or SPEEDS.Walk
		else
			humanoid.WalkSpeed = SPEEDS.Walk
			movementState.isRunning = false
		end
	else
		humanoid.WalkSpeed = movementState.isRunning and SPEEDS.Run or SPEEDS.Walk
	end

	-- Determinar estado: Idle, Andando ou Correndo
	local isMoving = humanoid.MoveDirection.Magnitude > 0
	local desiredState

	if isMoving then
		desiredState = movementState.isRunning and "Correndo" or "Andando"
	else
		desiredState = "Idle"
	end

	if estadoMovi.Value ~= desiredState then
		estadoMovi.Value = desiredState
	else
		-- Ajustar velocidade de animação se necessário
		if currentTracks.movement then
			if estadoMovi.Value == "Andando" then
				local speedMult = (humanoid.WalkSpeed < SPEEDS.Walk) and 0.3 or 1
				currentTracks.movement:AdjustSpeed(speedMult)
			elseif estadoMovi.Value == "Correndo" then
				-- Se estamos no ar, aplicar slowdown; se no chão, garantir velocidade normal
				local speedMult = (movementState.isJumping or movementState.isFalling) and TIMINGS.RunInAirSpeed or 1
				currentTracks.movement:AdjustSpeed(speedMult)
			end
		end
	end
end

--- Aplica lógica imediata de escalada
local function applyClimbingLogic()
	humanoid.WalkSpeed = SPEEDS.Climb
	estadoMovi.Value = "Escalando"

	local isMoving = humanoid.MoveDirection.Magnitude > CLIMB_DEADZONE
	if currentTracks.movement then
		currentTracks.movement:AdjustSpeed(isMoving and 0.7 or 0)
	end
end

--═══════════════════════════════════════════════════════════════════════════
-- SEÇÃO 7: SISTEMA DE COMBATE - COMBO LEVE
--═══════════════════════════════════════════════════════════════════════════

--- Finaliza combo leve
local function finishLightCombo(useSoftFade)
	if comboSystem.track and comboSystem.track.IsPlaying then
		comboSystem.track:Stop(useSoftFade and FADE.SoftEnd or FADE.ActionOut)
	end

	disconnectAll(comboSystem.connections)
	comboSystem.track = nil
	comboSystem.windowOpen = false
	comboSystem.consumed = false
	comboSystem.pendingConsume = false

	estadoAcao.Value = "Nenhuma"
	humanoid.JumpPower = DEFAULT_JUMP_POWER

	setCooldown("lightCombo", COOLDOWNS.LightCombo)
	updateMovementState()
end

--- Inicia combo leve
local function startLightCombo()
	if isStunned() then return end
	if not canPerformAction("lightCombo") then return end
	if not (estadoAcao.Value == "Nenhuma" or estadoAcao.Value == "Aparando") then return end
	if movementState.isClimbing or movementState.isSwimming then return end

	local prevState = estadoAcao.Value
	estadoAcao.Value = "AtacandoLeve"
	-- Se veio de Aparando, sincroniza transição riposte no servidor
	if prevState == "Aparando" and SyncEstadoAcaoRemote then
		SyncEstadoAcaoRemote:FireServer("AtacandoLeve", "Riposte")
		dprint("SyncEstadoAcao Riposte enviado ao servidor")
	end

	-- No modo Base, permite movimento durante ataque leve
	if modoCombateValue.Value ~= "Base" then
		movementState.isRunning = false
		humanoid.JumpPower = 0
	end

	comboSystem.windowOpen = false
	comboSystem.consumed = false
	comboSystem.token = comboSystem.token + 1

	-- Carregar animação
	local animName = getAnimationTrack("AtaqueLeve") and "AtaqueLeve" or "AtaqueLeve1"
	comboSystem.track = playActionAnimation(animName)

	if not comboSystem.track then
		estadoAcao.Value = "Nenhuma"
		humanoid.JumpPower = DEFAULT_JUMP_POWER
		updateMovementState()
		return
	end

	disconnectAll(comboSystem.connections)

	-- Evento de hit (marker "Attack")
	table.insert(comboSystem.connections, comboSystem.track:GetMarkerReachedSignal("Attack"):Connect(function(param)
		local hitNumber = tonumber(param) or 1
		local hitboxType = (hitNumber == 4) and "HitboxAtaqueLeveFinal" or "HitboxAtaqueLeve"

		HitboxClient:Spawn(hitboxType, { preview = HITBOX_PREVIEW })

		if hitboxType == "HitboxAtaqueLeveFinal" then
			CombatCore.ApplyKnockbackLocal(hrp, hitboxType)
		end

		PlayerTryHit:FireServer(hitboxType, { modoCombate = modoCombateValue.Value })
	end))

	-- Função para abrir janela de combo
	local function openComboWindow()
		if not comboSystem.track or not comboSystem.track.IsPlaying then return end

		comboSystem.token = comboSystem.token + 1
		local myToken = comboSystem.token

		comboSystem.consumed = false
		comboSystem.windowOpen = true
		comboSystem.track:AdjustSpeed(TIMINGS.ComboSlowdown)

		-- Se o jogador já clicou antes da janela abrir, consumir imediatamente
		if comboSystem.pendingConsume then
			print("[StateController] Consumo antecipado de combo leve (pending antes da janela)")
			comboSystem.pendingConsume = false
			comboSystem.consumed = true
			comboSystem.windowOpen = false
			if comboSystem.track.IsPlaying then
				comboSystem.track:AdjustSpeed(1)
			end
		end

		task.delay(TIMINGS.ComboWindow, function()
			if myToken ~= comboSystem.token then return end
			if not comboSystem.track or not comboSystem.track.IsPlaying then return end

			comboSystem.windowOpen = false

			if comboSystem.consumed then
				if comboSystem.track.IsPlaying then
					comboSystem.track:AdjustSpeed(1)
				end
			else
				finishLightCombo(true)
			end
		end)
	end

	-- Conectar janelas de combo (markers ComboEnd1, 2, 3)
	for _, markerName in ipairs({"ComboEnd1", "ComboEnd2", "ComboEnd3"}) do
		table.insert(comboSystem.connections, comboSystem.track:GetMarkerReachedSignal(markerName):Connect(openComboWindow))
	end

	-- Evento de fim da animação
	table.insert(comboSystem.connections, comboSystem.track.Stopped:Connect(function()
		if estadoAcao.Value ~= "Nenhuma" then
			finishLightCombo(false)
		end
	end))
end

--═══════════════════════════════════════════════════════════════════════════
-- SEÇÃO 8: SISTEMA DE COMBATE - ATAQUE PESADO
--═══════════════════════════════════════════════════════════════════════════

--- Inicia carregamento de ataque pesado
local function startHeavyCharge()
	if isStunned() then return end
	if not (estadoAcao.Value == "Nenhuma" or estadoAcao.Value == "Aparando") then return end
	if movementState.isClimbing or movementState.isSwimming then return end
	if not canPerformAction("heavyAttack") then return end

	estadoAcao.Value = "CarregandoPesado"
	movementState.isRunning = false
	humanoid.JumpPower = 0

	heavySystem.pressToken = heavySystem.pressToken + 1
	local myPress = heavySystem.pressToken
	heavySystem.released = false
	heavySystem.reachedMarker = false

	heavySystem.track = playActionAnimation("AtaquePesado")

	if not heavySystem.track then
		estadoAcao.Value = "Nenhuma"
		humanoid.JumpPower = DEFAULT_JUMP_POWER
		updateMovementState()
		return
	end

	disconnectAll(heavySystem.connections)

	-- Marker "AttackRelease" - pausa a animação até soltar M1
	table.insert(heavySystem.connections, heavySystem.track:GetMarkerReachedSignal("AttackRelease"):Connect(function()
		heavySystem.reachedMarker = true

		if myPress == heavySystem.pressToken and not heavySystem.released and inputState.m1Down and inputState.m1Held then
			heavySystem.track:AdjustSpeed(0)  -- PAUSA
		else
			if estadoAcao.Value == "CarregandoPesado" then
				estadoAcao.Value = "AtaquePesado"
			end
			heavySystem.track:AdjustSpeed(1)
		end
	end))

	-- Marker "HeavyAttack" - executa hitbox
	table.insert(heavySystem.connections, heavySystem.track:GetMarkerReachedSignal("HeavyAttack"):Connect(function()
		HitboxClient:Spawn("HitboxAtaquePesado", { preview = HITBOX_PREVIEW })
		CombatCore.ApplyKnockbackLocal(hrp, "HitboxAtaquePesado")
		PlayerTryHit:FireServer("HitboxAtaquePesado", { modoCombate = modoCombateValue.Value })
	end))

	-- Evento de fim da animação
	table.insert(heavySystem.connections, heavySystem.track.Stopped:Connect(function()
		disconnectAll(heavySystem.connections)
		heavySystem.track = nil

		setCooldown("heavyAttack", COOLDOWNS.HeavyAttack)
		estadoAcao.Value = "Nenhuma"
		humanoid.JumpPower = DEFAULT_JUMP_POWER
		updateMovementState()
	end))
end

--- Solta ataque pesado (continua animação pausada)
local function releaseHeavyAttack()
	if estadoAcao.Value ~= "CarregandoPesado" then return end

	heavySystem.released = true

	if not heavySystem.track then
		estadoAcao.Value = "Nenhuma"
		startLightCombo()
		return
	end

	estadoAcao.Value = "AtaquePesado"
	heavySystem.track:AdjustSpeed(1)  -- Continua
end

--═══════════════════════════════════════════════════════════════════════════
-- SEÇÃO 9: SISTEMA DE DEFESA
--═══════════════════════════════════════════════════════════════════════════

--- Verifica se o modo atual permite bloqueio
local function canUseBlock()
	local mode = resolveSetName(modoCombateValue.Value)
	return mode == "UmaMaoEscudo" or mode == "Punhos"
end

--- Finaliza defesa e aplica cooldown
local function endBlockingState()
	if estadoAcao.Value == "Defendendo" then
		stopCurrentAction(FADE.ActionOut)
		estadoAcao.Value = "Nenhuma"

		SetBlockingRemote:FireServer(false)
		humanoid.JumpPower = DEFAULT_JUMP_POWER

		setCooldown("block", COOLDOWNS.Block)
		updateMovementState()

		RunService:UnbindFromRenderStep("BlockGuard")
		return
	end

	-- Se estiver apenas no estágio de ProntoAparar (cancelou antes de entrar em Defendendo)
	if estadoAcao.Value == "ProntoAparar" then
		stopCurrentAction(FADE.ActionOut)
		estadoAcao.Value = "Nenhuma"
		-- Informar servidor que cancelou o bloqueio/ProntoAparar
		SetBlockingRemote:FireServer(false)
		humanoid.JumpPower = DEFAULT_JUMP_POWER
		updateMovementState()
		RunService:UnbindFromRenderStep("BlockGuard")
		return
	end
end

--- Inicia estado de defesa
local function startBlockingState()
	if not isShiftlockOrFirstPerson() then return end
	if not canUseBlock() then return end
	if not canPerformAction("block") then return end
	if isStunned() then return end
	if movementState.isClimbing or movementState.isSwimming then return end
	if estadoAcao.Value ~= "Nenhuma" then return end

	-- Consumir/parar cooldown para ParryReady se entrar no ProntoAparar
	local enteredParryReady = false

	if canPerformAction("parryReady") then
		enteredParryReady = true
		estadoAcao.Value = "ProntoAparar"
		movementState.isRunning = false
		humanoid.JumpPower = 0

		-- Consumir cooldown imediatamente
		setCooldown("parryReady", COOLDOWNS.ParryReady)

		-- Tocar animação de preparação (usar "Defesa")
		local guardTrack = playActionAnimation("Defesa")

		-- Informar servidor que iniciou bloqueio; indica se entrou em ProntoAparar
		SetBlockingRemote:FireServer(true, enteredParryReady)

		updateMovementState()

		-- Após delay, se ainda em ProntoAparar, entrar em Defendendo
		task.delay(TIMINGS.ParryReadyDelay, function()
			if estadoAcao.Value ~= "ProntoAparar" then return end

			estadoAcao.Value = "Defendendo"

			-- Informar servidor que ProntoAparar acabou (mantendo BloqueandoOn = true)
			SetBlockingRemote:FireServer(true, false)

			-- Garantir que a animação 'Defesa' fique em loop
			if guardTrack then
				if guardTrack.IsPlaying then
					guardTrack.Looped = true
				else
					guardTrack = playActionAnimation("Defesa")
					if guardTrack then guardTrack.Looped = true end
				end
			else
				local t2 = playActionAnimation("Defesa")
				if t2 then t2.Looped = true end
			end

			updateMovementState()
		end)
	else
		-- Está em cooldown -> entra direto em Defendendo
		estadoAcao.Value = "Defendendo"
		-- informar servidor que iniciou bloqueio (sem ProntoAparar)
		SetBlockingRemote:FireServer(true, false)

		movementState.isRunning = false
		humanoid.JumpPower = 0

		local track = playActionAnimation("Defesa")
		if track then track.Looped = true end

		updateMovementState()
	end

	-- Bind de verificação contínua (faz nada se já estiver bindado)
	RunService:UnbindFromRenderStep("BlockGuard")
	RunService:BindToRenderStep("BlockGuard", Enum.RenderPriority.Input.Value, function()
		if estadoAcao.Value ~= "Defendendo" and estadoAcao.Value ~= "ProntoAparar" then
			RunService:UnbindFromRenderStep("BlockGuard")
			return
		end

		local isHoldingM2 = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)

		if not isHoldingM2 or not isShiftlockOrFirstPerson() or not canUseBlock() or movementState.isClimbing or movementState.isSwimming then
			endBlockingState()
		end
	end)
end

--═══════════════════════════════════════════════════════════════════════════
-- Função auxiliar: Força a atualização da animação baseada em estado
--═══════════════════════════════════════════════════════════════════════════

local function forceUpdateMovementAnimation()
	if movementState.isSwimming then return end

	local speedMultiplier = nil

	if estadoMovi.Value == "Andando" then
		speedMultiplier = (humanoid.WalkSpeed < SPEEDS.Walk) and 0.3 or 1
	elseif estadoMovi.Value == "Correndo" then
		speedMultiplier = (movementState.isJumping or movementState.isFalling) and TIMINGS.RunInAirSpeed or 1
	elseif estadoMovi.Value == "Pulando" then
		speedMultiplier = 1
	elseif estadoMovi.Value == "Caindo" then
		speedMultiplier = 1
	elseif estadoMovi.Value == "Escalando" then
		speedMultiplier = 1
	end

	playMovementAnimation(estadoMovi.Value, speedMultiplier)

	-- Reforço de ajuste em tempo real
	if currentTracks.movement then
		if estadoMovi.Value == "Correndo" and (movementState.isJumping or movementState.isFalling) then
			currentTracks.movement:AdjustSpeed(TIMINGS.RunInAirSpeed)
		elseif estadoMovi.Value == "Andando" and humanoid.WalkSpeed < SPEEDS.Walk then
			currentTracks.movement:AdjustSpeed(0.3)
		end
	end
end

--═══════════════════════════════════════════════════════════════════════════
-- SEÇÃO 10: SISTEMA DE EQUIPAR/DESEQUIPAR
--═══════════════════════════════════════════════════════════════════════════

local equipBusy = false

--- Alterna modo de combate (equipar/desequipar)
local function toggleCombatMode(targetMode)
	if equipBusy or estadoAcao.Value ~= "Nenhuma" then return end

	local currentMode = modoCombateValue.Value

	-- Se pressionar o mesmo modo novamente, dessequipa (volta para Base)
	if targetMode ~= "Base" and currentMode == targetMode then
		equipBusy = true
		estadoAcao.Value = "Desequipando"

		local savedRunning = movementState.isRunning
		local savedJumpPower = humanoid.JumpPower
		humanoid.JumpPower = 0

		local track = playActionAnimation("Desequipar")
		if track then
			track.Stopped:Wait()
		else
			task.wait(0.2)
		end

		modoCombateValue.Value = "Base"
		estadoAcao.Value = "Nenhuma"
		humanoid.JumpPower = savedJumpPower
		equipBusy = false

		movementState.isRunning = savedRunning
		updateMovementState()
		forceUpdateMovementAnimation()  -- Força atualização de animação
		return
	end

	-- Só permite equipar se estiver em Base
	if targetMode ~= "Base" and currentMode ~= "Base" then
		return
	end

	-- Equipar a partir de Base
	if targetMode ~= "Base" and currentMode == "Base" then
		equipBusy = true
		estadoAcao.Value = "Equipando"

		local savedRunning = movementState.isRunning
		local savedJumpPower = humanoid.JumpPower
		humanoid.JumpPower = 0

		modoCombateValue.Value = targetMode

		local track = playActionAnimation("Equipar")
		if track then
			track.Stopped:Wait()
		else
			task.wait(0.2)
		end

		estadoAcao.Value = "Nenhuma"
		humanoid.JumpPower = savedJumpPower
		equipBusy = false

		movementState.isRunning = savedRunning
		updateMovementState()
		forceUpdateMovementAnimation()  -- Força atualização de animação
	end
end

--═══════════════════════════════════════════════════════════════════════════
-- SEÇÃO 11: SISTEMA DE STUN
--═══════════════════════════════════════════════════════════════════════════

--- Monitora sistema de stun usando StunadoOn
local stunadoOnValue = statusFolder:FindFirstChild("StunadoOn")
if stunadoOnValue and stunadoOnValue:IsA("BoolValue") then
	stunadoOnValue.Changed:Connect(function(newValue)
		if newValue and not stunActive then
			stunActive = true
			stopCurrentAction(0)
			estadoAcao.Value = "Nenhuma"
			humanoid.WalkSpeed = SPEEDS.Stun

			print("[CLIENT] Player stunado, WalkSpeed=" .. SPEEDS.Stun)

			task.delay(TIMINGS.StunDuration, function()
				stunActive = false
				if not isStunned() then
					humanoid.WalkSpeed = SPEEDS.Walk
					print("[CLIENT] Stun finalizado, WalkSpeed restaurado")
				end
			end)
		elseif not newValue and stunActive then
			humanoid.WalkSpeed = SPEEDS.Walk
			stunActive = false
			print("[CLIENT] Stun finalizado (fallback), WalkSpeed restaurado")
		end
	end)
end

--- Monitora interrupções forçadas
estadoAcao:GetAttributeChangedSignal("Interrompido"):Connect(function()
	if estadoAcao:GetAttribute("Interrompido") then
		if estadoAcao.Value == "AtacandoLeve" or estadoAcao.Value == "CarregandoPesado" then
			stopCurrentAction(0)
			estadoAcao.Value = "Nenhuma"
			estadoAcao:SetAttribute("Interrompido", nil)
		end
	end
end)

--═══════════════════════════════════════════════════════════════════════════
-- SEÇÃO 12: SISTEMA DE SHIFTLOCK
--═══════════════════════════════════════════════════════════════════════════

--- Define estado de ShiftLock
local function setShiftLock(enabled)
	inputState.shiftlockOn = enabled

	-- Atualiza a flag moderna criada pelo Setup (Status.ShiftLockOn)
	local status = statusFolder
	if status then
		local flag = status:FindFirstChild("ShiftLockOn")
		if flag then
			flag.Value = enabled
		end
	end

	if movementState.isSwimming then
		humanoid.AutoRotate = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		RunService:UnbindFromRenderStep("ShiftLockFace")
		return
	end

	humanoid.AutoRotate = not enabled
	UserInputService.MouseBehavior = enabled and Enum.MouseBehavior.LockCenter or Enum.MouseBehavior.Default

	if enabled then
		RunService:BindToRenderStep("ShiftLockFace", Enum.RenderPriority.Character.Value, function()
			local cam = workspace.CurrentCamera
			local look = cam and cam.CFrame.LookVector or hrp.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)

			if flat.Magnitude > 1e-3 then
				hrp.CFrame = CFrame.new(hrp.Position, hrp.Position + flat.Unit)
			end
		end)
	else
		RunService:UnbindFromRenderStep("ShiftLockFace")
	end
end


--═══════════════════════════════════════════════════════════════════════════
-- SEÇÃO 13: EVENTOS DE ESTADO DO HUMANOID
--═══════════════════════════════════════════════════════════════════════════

humanoid.StateChanged:Connect(function(oldState, newState)
	local wasSwimming = movementState.isSwimming

	-- Atualizar flags de estado
	movementState.isClimbing = (newState == Enum.HumanoidStateType.Climbing)
	movementState.isSwimming = (newState == Enum.HumanoidStateType.Swimming)
	movementState.isJumping = (newState == Enum.HumanoidStateType.Jumping)
	movementState.isFalling = (newState == Enum.HumanoidStateType.Freefall)

	-- Configurar hold de pulo
	if movementState.isJumping then
		if oldState == Enum.HumanoidStateType.Climbing then
			jumpHoldUntil = now() + TIMINGS.ClimbExitJumpHold

			-- Verificação imediata de queda após pular de escada
			task.spawn(function()
				local deadline = now() + 0.25
				while now() < deadline do
					if humanoid:GetState() == Enum.HumanoidStateType.Jumping then
						local vy = (hrp.AssemblyLinearVelocity and hrp.AssemblyLinearVelocity.Y) or hrp.Velocity.Y
						if humanoid.FloorMaterial == Enum.Material.Air and vy <= -1 then
							jumpHoldUntil = 0
							estadoMovi.Value = "Caindo"
							break
						end
					else
						break
					end
					RunService.Heartbeat:Wait()
				end
			end)
		else
			jumpHoldUntil = now() + TIMINGS.JumpHold
		end
	end

	-- Respostas imediatas
	if movementState.isSwimming and not wasSwimming then
		stopCurrentAction(FADE.SoftEnd)
	end

	if movementState.isClimbing then
		applyClimbingLogic()
		return
	end

	updateMovementState()
end)

--═══════════════════════════════════════════════════════════════════════════
-- SEÇÃO 14: EVENTOS DE MUDANÇA DE ESTADO
--═══════════════════════════════════════════════════════════════════════════

--- Atualiza animação quando estado de movimento muda
estadoMovi.Changed:Connect(forceUpdateMovementAnimation)

--- Atualiza estado quando ação muda
estadoAcao.Changed:Connect(function()
	if estadoAcao.Value ~= "Nenhuma" and estadoAcao.Value ~= "Equipando" then
		movementState.isRunning = false
	end

	-- Tratamento local das animações para Aparado / Aparando
	if estadoAcao.Value == "Aparado" then
		-- Tocar animação de Aparado e garantir velocidade reduzida
		movementState.isRunning = false
		humanoid.JumpPower = 0
		stopCurrentAction(FADE.ActionOut)
		print("[StateController] Entrou em Aparado")
		local track = playActionAnimation("Aparado")
		if track then
			dprint("Playing Aparado animation")
			track.Stopped:Once(function()
				print("[StateController] Aparado animation ended")
				-- Só restaura se ainda estiver em Aparado (pode ter iniciado outra ação)
				if estadoAcao.Value == "Aparado" then
					estadoAcao.Value = "Nenhuma"
					humanoid.JumpPower = DEFAULT_JUMP_POWER
					updateMovementState()
				end
			end)
		else
			print("[StateController] No Aparado animation found; restoring state immediately")
			estadoAcao.Value = "Nenhuma"
			humanoid.JumpPower = DEFAULT_JUMP_POWER
			updateMovementState()
		end
		return
	elseif estadoAcao.Value == "Aparando" then
		-- Quem aparou: tocar animação de Aparar e garantir que defesa foi desativada
		stopCurrentAction(FADE.ActionOut)
		print("[StateController] Entrou em Aparando")
		local track = playActionAnimation("Aparar")
		-- Forçar flag local de Bloqueando = false (servidor já sincroniza, mas garantir localmente)
		pcall(function()
			local s = character:FindFirstChild("Status")
			if s then
				local b = s:FindFirstChild("BloqueandoOn")
				if b and b:IsA("BoolValue") then b.Value = false end
				local p = s:FindFirstChild("ProntoAparar")
				if p and p:IsA("BoolValue") then p.Value = false end
			end
		end)
		if track then
			dprint("Playing Aparar animation")
			track.Stopped:Once(function()
				print("[StateController] Aparar animation ended")
				-- Só restaura se ainda estiver em Aparando (player pode ter iniciado ataque)
				if estadoAcao.Value == "Aparando" then
					estadoAcao.Value = "Nenhuma"
					humanoid.JumpPower = DEFAULT_JUMP_POWER
					updateMovementState()
				end
			end)
		else
			-- Sem animação de Aparar: usar delay fixo para permitir contra-ataque
			print("[StateController] No Aparar animation found; using fixed delay")
			task.delay(0.4, function()
				if estadoAcao.Value == "Aparando" then
					estadoAcao.Value = "Nenhuma"
					humanoid.JumpPower = DEFAULT_JUMP_POWER
					updateMovementState()
				end
			end)
		end
		return
	end

	updateMovementState()
end)

--- Monitora mudança de direção de movimento
humanoid:GetPropertyChangedSignal("MoveDirection"):Connect(function()
	if movementState.isClimbing then
		applyClimbingLogic()
		return
	end
	updateMovementState()
end)


--═══════════════════════════════════════════════════════════════════════════
-- SEÇÃO 15: SISTEMA DE INPUT
--═══════════════════════════════════════════════════════════════════════════

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	-- LeftShift: Corrida
	if input.KeyCode == Enum.KeyCode.LeftShift and estadoAcao.Value == "Nenhuma" then
		movementState.isRunning = true
		updateMovementState()
		return
	end

	-- LeftControl: Toggle ShiftLock
	if input.KeyCode == Enum.KeyCode.LeftControl then
		setShiftLock(not inputState.shiftlockOn)
		if movementState.isSwimming and estadoAcao.Value == "Defendendo" then
			endBlockingState()
		end
		return
	end

	-- E: Equipar/Desequipar UmaMaoEscudo
	if input.KeyCode == Enum.KeyCode.E then
		-- Sempre chama com o modo configurado para teste; o toggleInterno trata equipar/dessequipar
		toggleCombatMode(modoAnimacaoCombatEquip_Test)
		return
	end


	-- M2: Defesa
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		startBlockingState()
		return
	end

	-- M1: Ataque leve ou pesado
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		-- Riposte imediato: se ainda em Aparando ao pressionar, iniciar combo leve já para garantir troca de estado antes do restore do servidor
		if estadoAcao.Value == "Aparando" then
			print("[StateController] Riposte imediato: iniciando combo leve durante Aparando")
			startLightCombo()
			return
		end
		-- Se já está em combo, tenta consumir janela
		if estadoAcao.Value == "AtacandoLeve" and comboSystem.track and comboSystem.track.IsPlaying then
			if comboSystem.windowOpen and not comboSystem.consumed then
				comboSystem.consumed = true
				comboSystem.windowOpen = false
				if comboSystem.track.IsPlaying then
					comboSystem.track:AdjustSpeed(1)
				end
			else
				-- Clicou cedo: marcar para consumo assim que janela abrir
				comboSystem.pendingConsume = true
				print("[StateController] Clique antecipado registrado para próximo estágio do combo leve")
			end
			return
		end

		inputState.m1Down = true
		inputState.m1Held = true

		-- Delay para detectar se é ataque pesado (segurar)
		local pressId = os.clock()
		task.delay(TIMINGS.ChargeDelay, function()
			if not inputState.m1Down or not inputState.m1Held then return end
			-- Permite carregar ataque pesado se estiver em Nenhuma (Aparando já teria virado riposte se o jogador quis atacar)
			if estadoAcao.Value ~= "Nenhuma" then return end
			if not canPerformAction("heavyAttack") then return end

			startHeavyCharge()
		end)
		return
	end

	-- G: Defesa quebrada (durante defesa)
	if input.KeyCode == Enum.KeyCode.G then
		if estadoAcao.Value == "Defendendo" then
			estadoAcao.Value = "DefesaQuebrada"
			SetBlockingRemote:FireServer(false)
			movementState.isRunning = false
			stopCurrentAction(FADE.ActionOut)

			local track = playActionAnimation("DefesaQuebrada")
			if track then
				track.Stopped:Once(function()
					estadoAcao.Value = "Nenhuma"
					humanoid.JumpPower = DEFAULT_JUMP_POWER
					updateMovementState()
				end)
			else
				estadoAcao.Value = "Nenhuma"
				humanoid.JumpPower = DEFAULT_JUMP_POWER
				updateMovementState()
			end
		end
		return
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	-- LeftShift: Parar corrida
	if input.KeyCode == Enum.KeyCode.LeftShift then
		movementState.isRunning = false
		updateMovementState()
		return
	end

	-- M2: Parar defesa
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		endBlockingState()
		return
	end

	-- M1: Soltar ataque
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		inputState.m1Down = false
		inputState.m1Held = false

		local wasCharging = (estadoAcao.Value == "CarregandoAtaque")

		if wasCharging then
			releaseHeavyAttack()
		else
			-- Permite atacar se estiver em Nenhuma ou Aparando
			if estadoAcao.Value == "Nenhuma" or estadoAcao.Value == "Aparando" then
				startLightCombo()
			end
		end
		return
	end
end)

--═══════════════════════════════════════════════════════════════════════════
-- SEÇÃO 16: INICIALIZAÇÃO
--═══════════════════════════════════════════════════════════════════════════

-- Pré-carregar sets de animação
loadAnimationSet("Base")
loadAnimationSet("UmaMaoEscudo")
loadAnimationSet("Punhos")

-- Configurar estado inicial
humanoid.WalkSpeed = SPEEDS.Walk
setShiftLock(false)
updateMovementState()
forceUpdateMovementAnimation()  -- Força reprodução inicial de animação

print("[StateController] Sistema inicializado com sucesso!")
