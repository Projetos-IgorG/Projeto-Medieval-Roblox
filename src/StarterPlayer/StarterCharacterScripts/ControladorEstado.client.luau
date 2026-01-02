--[[
    ControladorEstado.client.lua
    
    Script local responsável por:
    - Escutar estados sincronizados do servidor
    - Tocar animações localmente (com predição)
    - Gerenciar animações de movimento baseado em INPUT (não velocidade)
    - Detectar transições de estado via StateChanged
    
    NÃO gerencia inputs de combate (ver EntradaJogador.client.lua)
    NÃO valida ações (feito no servidor via ControladorCombate)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local animator = humanoid:WaitForChild("Animator")

local Modulos = ReplicatedStorage:WaitForChild("Modulos")
local ArmasTemplate = require(Modulos:WaitForChild("ArmasTemplate"))

-- ═══════════════════════════════════════════════════════════════════
-- CONFIGURAÇÕES LOCAIS (espelhando ArmasTemplate para responsividade)
-- ═══════════════════════════════════════════════════════════════════

local TIMINGS = {
	JumpHold = 0.28, -- Hold de animação de pulo antes de transitar para queda
	RunInAirSpeed = 0.4, -- Velocidade da animação de corrida no ar
	-- Fade times para movimento (mais suave)
	MoveFadeIn = 0.18,
	MoveFadeOut = 0.18,
	-- Fade times para ações (mais rápido)
	ActionFadeIn = 0.10,
	ActionFadeOut = 0.10,
	-- Fade suave para término de combos
	SoftEnd = 0.40,
}

-- ═══════════════════════════════════════════════════════════════════
-- DESATIVAR SCRIPT ANIMATE PADRÃO DO ROBLOX
-- ═══════════════════════════════════════════════════════════════════

local function DesativarScriptAnimate()
	local animate = character:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
		print("[ControladorEstado] Script Animate padrão desativado")
	end

	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		track:Stop(0)
	end
end

DesativarScriptAnimate()

-- ═══════════════════════════════════════════════════════════════════
-- REMOTE EVENTS
-- ═══════════════════════════════════════════════════════════════════

local Remotos = ReplicatedStorage:WaitForChild("Remotos")
local SincronizarEstado = Remotos:WaitForChild("SincronizarEstado")
local TocarAnimacao = Remotos:WaitForChild("TocarAnimacao")
local TentarAcao = Remotos:WaitForChild("TentarAcao") -- Para enviar sincronização de movimento

-- ═══════════════════════════════════════════════════════════════════
-- ESTADO LOCAL
-- ═══════════════════════════════════════════════════════════════════

local estadoAtual = {
	estadoMov = "Parado",
	estadoAcao = "Nenhuma",
	estadoAcaoAnterior = "Nenhuma", -- Para detectar mudanças
	modoAnimacao = "Base",
	bloqueando = false,
	agachado = false,
	correndo = false,
}

-- Estados de movimento local (input-based)
local movementFlags = {
	isRunning = false, -- LeftShift pressionado
	isJumping = false, -- Estado de pulo
	isFalling = false, -- Estado de queda
	isClimbing = false, -- Estado de escalada
	isSwimming = false, -- Estado de nado
}

-- Flag global para saber se Shift está sendo segurado (independente de estado)
local isShiftHeld = false

-- Controle de pulo
local jumpHoldUntil = 0

-- Cache de animações
local animacoesCarregadas = {}
local animacaoAtualMov = nil
local animacaoAtualAcao = nil

-- Forward declaration de funções usadas antes de serem definidas
local AtualizarAnimacaoMovimento

-- ═══════════════════════════════════════════════════════════════════
-- SISTEMA DE COMBO POR MARCADORES
-- ═══════════════════════════════════════════════════════════════════

--[[
	O sistema de combo funciona assim:
	1. Uma única animação "AtaqueLeve" contém todos os golpes do combo
	2. Marcadores na animação controlam o timing:
	   - "Attack" (params: "1", "2", "3", "4") - Momento de criar hitbox
	   - "ComboEnd1", "ComboEnd2", "ComboEnd3" - Início da janela de input
	3. Quando "ComboEndX" é atingido, a velocidade cai para 0.4
	4. Se o jogador clicar M1 durante a janela, velocidade volta para 1
	5. Se não clicar, a animação para e volta para Idle
]]

-- Estado local do combo
local comboState = {
	animacaoAtiva = nil, -- AnimationTrack atual do combo
	janelaAtiva = false, -- Se está na janela de input
	indiceAtual = 0, -- Índice do golpe atual
	conexoesMarkers = {}, -- Conexões dos markers para limpeza
	continuarCombo = false, -- Flag se deve continuar (set por input)
	pendingConsume = false, -- Clique antecipado (antes da janela abrir)
	janelaTimer = nil, -- Thread do timer da janela
	token = 0, -- Token para invalidar timers antigos
}

--- Limpa conexões de markers da animação atual
local function LimparConexoesMarkers()
	for _, conexao in ipairs(comboState.conexoesMarkers) do
		if conexao and conexao.Connected then
			conexao:Disconnect()
		end
	end
	comboState.conexoesMarkers = {}

	-- Cancela timer da janela se existir
	-- Usa pcall pois task.cancel pode falhar se o thread já terminou ou é inválido
	if comboState.janelaTimer then
		pcall(task.cancel, comboState.janelaTimer)
		comboState.janelaTimer = nil
	end
end

--- Chamado quando a animação de combo termina (naturalmente ou forçada)
local function OnComboAnimacaoTerminou()
	print("[ControladorEstado] Combo animação terminou")

	LimparConexoesMarkers()

	comboState.animacaoAtiva = nil
	comboState.janelaAtiva = false
	comboState.indiceAtual = 0
	comboState.continuarCombo = false
	comboState.pendingConsume = false
	comboState.token = 0

	-- Atualiza estado local
	estadoAtual.estadoAcao = "Nenhuma"

	-- Notifica servidor que combo terminou
	TentarAcao:FireServer("ComboTerminou")

	-- Se o jogador está segurando Shift, volta a correr
	if isShiftHeld then
		movementFlags.isRunning = true
		TentarAcao:FireServer("Correr")
		estadoAtual.estadoMov = "Correndo"
		estadoAtual.correndo = true
	end

	-- Volta para animação de movimento
	AtualizarAnimacaoMovimento()
end

--- Processa o marcador "ComboEndX" - início da janela de input
---@param indiceGolpe string Índice do golpe ("1", "2", "3")
local function OnMarkerJanelaCombo(indiceGolpe: string)
	if not comboState.animacaoAtiva then
		return
	end

	local indice = tonumber(indiceGolpe) or 0

	-- Incrementa token para invalidar timers antigos
	comboState.token = comboState.token + 1
	local myToken = comboState.token

	comboState.janelaAtiva = true
	comboState.indiceAtual = indice
	comboState.continuarCombo = false -- Reseta para aguardar novo input

	print(string.format("[ControladorEstado] Janela de combo ativada (golpe %d)", indice))

	-- Obtém configuração do combo
	local combo = ArmasTemplate.ObterCombo(estadoAtual.modoAnimacao)
	if not combo then
		return
	end

	-- Reduz velocidade da animação durante a janela
	comboState.animacaoAtiva:AdjustSpeed(combo.velocidadeJanela)

	-- Se o jogador já clicou antes da janela abrir (pending), consumir imediatamente
	if comboState.pendingConsume then
		print("[ControladorEstado] Consumo antecipado de combo (pending antes da janela)")
		comboState.pendingConsume = false
		comboState.continuarCombo = true
		comboState.janelaAtiva = false

		if comboState.animacaoAtiva and comboState.animacaoAtiva.IsPlaying then
			comboState.animacaoAtiva:AdjustSpeed(1)
		end

		TentarAcao:FireServer("ComboContinuado", comboState.indiceAtual + 1)
		return
	end

	-- Timer para expirar a janela
	comboState.janelaTimer = task.delay(combo.janelaCombo, function()
		-- Verifica se este timer ainda é válido
		if myToken ~= comboState.token then
			return -- Timer invalidado
		end

		if not comboState.janelaAtiva then
			return -- Janela já foi processada
		end

		-- Verifica se deve continuar
		if comboState.continuarCombo then
			-- Jogador clicou durante a janela - continua combo
			print("[ControladorEstado] Combo continuando - velocidade restaurada")
			comboState.janelaAtiva = false
			comboState.continuarCombo = false

			if comboState.animacaoAtiva and comboState.animacaoAtiva.IsPlaying then
				comboState.animacaoAtiva:AdjustSpeed(1)
			end

			-- Notifica servidor que combo continua
			TentarAcao:FireServer("ComboContinuado", comboState.indiceAtual + 1)
		else
			-- Jogador não clicou - termina combo
			print("[ControladorEstado] Janela expirou - combo terminando")
			comboState.janelaAtiva = false

			if comboState.animacaoAtiva then
				comboState.animacaoAtiva:Stop(0.4) -- Fade suave
			end

			OnComboAnimacaoTerminou()
		end
	end)
end

--- Processa o marcador "Attack" - momento de criar hitbox
---@param indiceGolpe string Parâmetro do marker ("1", "2", "3", "4")
local function OnMarkerAtaque(indiceGolpe: string)
	local indice = tonumber(indiceGolpe) or 0

	print(string.format("[ControladorEstado] Marker Attack - golpe %s (índice %d)", indiceGolpe, indice))

	-- Notifica servidor para criar hitbox
	TentarAcao:FireServer("ComboHitbox", indice)

	-- Se é o golpe 4 (final), aguarda animação terminar naturalmente
	if indice >= 4 then
		comboState.janelaAtiva = false -- Não tem mais janela após o final
		print("[ControladorEstado] Golpe final executado")
	end
end

--- Configura listeners de marcadores para uma animação de combo
---@param track AnimationTrack
local function ConfigurarMarkersCombo(track: AnimationTrack)
	LimparConexoesMarkers() -- Limpa anteriores

	local combo = ArmasTemplate.ObterCombo(estadoAtual.modoAnimacao)
	if not combo or not combo.marcadores then
		return
	end

	-- Conecta aos markers de janela de input (ComboEnd1, ComboEnd2, ComboEnd3)
	-- Cada marker é separado, não usa parâmetros
	if combo.marcadores.janelasCombo then
		for i, markerName in ipairs(combo.marcadores.janelasCombo) do
			local conexaoJanela = track:GetMarkerReachedSignal(markerName):Connect(function()
				OnMarkerJanelaCombo(tostring(i))
			end)
			table.insert(comboState.conexoesMarkers, conexaoJanela)
		end
	end

	-- Conecta ao marker de ataque/hitbox (Attack com parâmetro)
	local conexaoAtaque = track:GetMarkerReachedSignal(combo.marcadores.ataque):Connect(OnMarkerAtaque)
	table.insert(comboState.conexoesMarkers, conexaoAtaque)

	-- Conecta ao evento de término da animação
	local conexaoStopped = track.Stopped:Connect(function()
		-- Se terminou naturalmente (não foi parada manualmente)
		if comboState.animacaoAtiva == track then
			OnComboAnimacaoTerminou()
		end
	end)
	table.insert(comboState.conexoesMarkers, conexaoStopped)

	print("[ControladorEstado] Markers de combo configurados")
end

--- Marca que o jogador quer continuar o combo
--- Chamado por EntradaJogador quando M1 é pressionado
--- Retorna true se está em combo ativo (janela aberta ou animação rodando)
function _G.MarcarContinuarCombo()
	-- Se está na janela, marca para continuar
	if comboState.janelaAtiva then
		comboState.continuarCombo = true
		print("[ControladorEstado] Input de continuar combo registrado (janela ativa)")
		return true
	end

	-- Se combo está ativo mas ainda não chegou na janela, marca como pending
	if comboState.animacaoAtiva and comboState.animacaoAtiva.IsPlaying then
		comboState.pendingConsume = true
		print("[ControladorEstado] Input antecipado registrado (pending)")
		return true
	end

	return false
end

--- Verifica se está na janela de combo (para EntradaJogador)
function _G.EstaJanelaComboAtiva()
	return comboState.janelaAtiva
end

--- Verifica se há um combo ativo (animação tocando)
function _G.EstaComboAtivo()
	return comboState.animacaoAtiva and comboState.animacaoAtiva.IsPlaying
end

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES DE ANIMAÇÃO
-- ═══════════════════════════════════════════════════════════════════

--- Carrega ou obtém animação do cache
local function ObterAnimacao(animId: string): AnimationTrack?
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

--- Para animação atual de movimento
local function PararAnimacaoMov()
	if animacaoAtualMov then
		animacaoAtualMov:Stop(TIMINGS.MoveFadeOut)
		animacaoAtualMov = nil
	end
end

--- Para animação atual de ação
--- Também limpa estado de combo se estiver ativo
local function PararAnimacaoAcao()
	-- Limpa conexões de markers se houver combo ativo
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

--- Toca animação de movimento
local function TocarAnimacaoMov(nomeAnimacao: string, velocidade: number?)
	local animId = ArmasTemplate.ObterAnimacao(estadoAtual.modoAnimacao, nomeAnimacao)
	if not animId then
		return
	end

	local track = ObterAnimacao(animId)
	if not track then
		return
	end

	-- Não reinicia se já está tocando a mesma
	if animacaoAtualMov == track and track.IsPlaying then
		-- Apenas ajusta velocidade se necessário
		if velocidade then
			track:AdjustSpeed(velocidade)
		end
		return
	end

	PararAnimacaoMov()

	track.Priority = Enum.AnimationPriority.Core
	track.Looped = true
	track:Play(TIMINGS.MoveFadeIn)

	if velocidade then
		track:AdjustSpeed(velocidade)
	end

	animacaoAtualMov = track
end

--- Toca animação de ação
--- Para animações de combo (AtaqueLeve), configura sistema de marcadores
---@param animId string ID da animação
---@param loop boolean Se a animação deve loopar
---@param velocidade number Velocidade inicial da animação
---@param nomeAnimacao string? Nome da animação (opcional, usado para detectar combo)
local function TocarAnimacaoAcao(animId: string, loop: boolean, velocidade: number, nomeAnimacao: string?)
	local track = ObterAnimacao(animId)
	if not track then
		return
	end

	PararAnimacaoAcao()

	track.Priority = Enum.AnimationPriority.Action
	track.Looped = loop
	track:Play(0.1)
	track:AdjustSpeed(velocidade)

	animacaoAtualAcao = track

	-- Verifica se é uma animação de combo para configurar markers
	local ehCombo = nomeAnimacao and (nomeAnimacao == "AtaqueLeve" or nomeAnimacao:match("^AtaqueLeve"))
	local combo = ArmasTemplate.ObterCombo(estadoAtual.modoAnimacao)

	if ehCombo and combo and nomeAnimacao then
		-- Configura sistema de combo por marcadores
		comboState.animacaoAtiva = track
		comboState.janelaAtiva = false
		comboState.indiceAtual = 1
		comboState.continuarCombo = false

		ConfigurarMarkersCombo(track)

		print(
			string.format(
				"[ControladorEstado] Animação de combo iniciada: %s (velocidade %.1f)",
				nomeAnimacao :: string,
				velocidade
			)
		)
	end
end

--- Atualiza animação de movimento baseado no estado
AtualizarAnimacaoMovimento = function()
	local estado = estadoAtual.estadoMov
	local velocidade = nil

	-- Mapeia estado para nome de animação
	local mapaAnimacoes = {
		Parado = "Idle",
		Andando = "Andando",
		Correndo = "Correndo",
		Pulando = "Pulando",
		Caindo = "Caindo",
		Escalando = "Escalando",
		Nadando = "Nadando",
		Agachado = "Idle", -- TODO: Animação de agachado
	}

	-- Se está no ar correndo, usa velocidade reduzida
	if estado == "Correndo" and (movementFlags.isJumping or movementFlags.isFalling) then
		velocidade = TIMINGS.RunInAirSpeed
	end

	-- Se está atacando ou defendendo e andando, usa velocidades distintas
	if estado == "Andando" then
		local emDefendendo = (estadoAtual.estadoAcao == "Defendendo")
		local emAtacando = (
			estadoAtual.estadoAcao == "AtacandoLeve"
			or estadoAtual.estadoAcao == "CarregandoPesado"
			or estadoAtual.estadoAcao == "AtaquePesado"
		)

		if emDefendendo then
			-- Velocidade da animação enquanto defende
			velocidade = 0.55
		elseif emAtacando then
			-- Velocidade da animação enquanto ataca
			velocidade = 0.85
		end
	end

	-- Se está agachado, use animações específicas de agachado
	local nomeAnimacao
	if estadoAtual.agachado then
		if estado == "Andando" then
			nomeAnimacao = "AndandoAgachado"
			velocidade = 0.8
		else
			nomeAnimacao = "IdleAgachado"
		end
	else
		nomeAnimacao = mapaAnimacoes[estado] or "Idle"
	end

	TocarAnimacaoMov(nomeAnimacao, velocidade)
end

-- ═══════════════════════════════════════════════════════════════════
-- SINCRONIZAÇÃO DE ESTADO
-- ═══════════════════════════════════════════════════════════════════

--- Processa atualização de estado do servidor
local function ProcessarSincronizacao(entidade: Model, dados)
	if entidade ~= character then
		return
	end

	-- Guarda estado anterior para detectar mudanças
	local acaoAnterior = estadoAtual.estadoAcao

	-- Atualiza estado local
	estadoAtual.estadoMov = dados.estadoMov
	estadoAtual.estadoAcao = dados.estadoAcao
	estadoAtual.modoAnimacao = dados.modoAnimacao
	estadoAtual.bloqueando = dados.bloqueando
	estadoAtual.agachado = dados.agachado
	estadoAtual.correndo = dados.correndo

	-- Se entrou em ação de combate, preserva intenção de correr e força parar corrida local
	if
		estadoAtual.estadoAcao == "AtacandoLeve"
		or estadoAtual.estadoAcao == "CarregandoPesado"
		or estadoAtual.estadoAcao == "AtaquePesado"
		or estadoAtual.estadoAcao == "Defendendo"
	then
		-- Não precisamos mais salvar runIntentDuringAction pois usamos isShiftHeld
		movementFlags.isRunning = false
	end

	-- Se estadoAcao mudou para "Nenhuma", para animação de ação
	-- EXCEÇÃO: animações de Equipar/Desequipar devem terminar naturalmente
	if acaoAnterior ~= "Nenhuma" and estadoAtual.estadoAcao == "Nenhuma" then
		local foiEquipDesequip = (acaoAnterior == "Equipando" or acaoAnterior == "Desequipando")

		if foiEquipDesequip and animacaoAtualAcao and animacaoAtualAcao.IsPlaying then
			-- Deixa a animação terminar naturalmente - configura callback
			animacaoAtualAcao.Stopped:Once(function()
				animacaoAtualAcao = nil
				AtualizarAnimacaoMovimento()
			end)
		else
			-- Para outras ações, para imediatamente
			PararAnimacaoAcao()
		end
	end

	-- Se terminou uma ação de ataque (AtacandoLeve / CarregandoPesado / AtaquePesado)
	-- e o jogador está segurando Shift, solicitar correr ao servidor.
	if
		(acaoAnterior == "AtacandoLeve" or acaoAnterior == "CarregandoPesado" or acaoAnterior == "AtaquePesado")
		and estadoAtual.estadoAcao == "Nenhuma"
	then
		if isShiftHeld then
			movementFlags.isRunning = true -- Restaura flag local
			TentarAcao:FireServer("Correr")
			-- Forçar localmente estado de corrida para responsividade
			estadoAtual.estadoMov = "Correndo"
			estadoAtual.correndo = true
			AtualizarAnimacaoMovimento()
		end
	end

	-- NÃO atualiza animação de movimento se está correndo no ar (evita flick)
	if movementFlags.isRunning and (movementFlags.isJumping or movementFlags.isFalling) then
		-- Apenas ajusta velocidade
		if animacaoAtualMov then
			animacaoAtualMov:AdjustSpeed(TIMINGS.RunInAirSpeed)
		end
		return
	end

	-- Atualiza animação de movimento
	AtualizarAnimacaoMovimento()

	-- Se saiu de Defendendo e o jogador ainda está segurando Shift, pedir para correr
	if acaoAnterior == "Defendendo" and estadoAtual.estadoAcao == "Nenhuma" then
		if isShiftHeld then
			movementFlags.isRunning = true -- Restaura flag local
			TentarAcao:FireServer("Correr")
			-- Forçar localmente estado de corrida para responsividade
			estadoAtual.estadoMov = "Correndo"
			estadoAtual.correndo = true
			AtualizarAnimacaoMovimento()
		end
	end
end

--- Processa comando de tocar animação
--- Recebe comando do servidor para tocar uma animação específica
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

	-- Passa o nome da animação para detectar combo
	TocarAnimacaoAcao(animId, loop, velocidade, nomeAnimacao)
end

-- ═══════════════════════════════════════════════════════════════════
-- DETECÇÃO LOCAL DE MOVIMENTO (INPUT-BASED + HYBRID)
-- ═══════════════════════════════════════════════════════════════════

--- Atualiza estado de movimento baseado em inputs e estado do Humanoid
local function AtualizarEstadoMovimento()
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	-- Prioridade 1: Estados especiais (escalada, nado)
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

	-- Prioridade 2: Agachado
	-- Permitir 'andar' enquanto agachado: mapeamos para Andando/Parado localmente
	if estadoAtual.agachado then
		local isMoving = humanoid.MoveDirection.Magnitude > 0.1
		local novo = isMoving and "Andando" or "Parado"
		if estadoAtual.estadoMov ~= novo then
			estadoAtual.estadoMov = novo
			AtualizarAnimacaoMovimento()
		end
		return
	end

	-- Prioridade 3: No ar (pulo/queda)
	if movementFlags.isJumping or movementFlags.isFalling then
		local velocidadeY = hrp.AssemblyLinearVelocity.Y

		-- Verifica se está em ação de combate que impede correr
		local emCombate = (
			estadoAtual.estadoAcao == "AtacandoLeve"
			or estadoAtual.estadoAcao == "CarregandoPesado"
			or estadoAtual.estadoAcao == "AtaquePesado"
			or estadoAtual.estadoAcao == "Defendendo"
		)

		-- Se está com Shift pressionado (correndo) E não está em combate, mantém animação de corrida no ar
		-- NUNCA chama AtualizarAnimacaoMovimento aqui - apenas ajusta velocidade
		if movementFlags.isRunning and not emCombate then
			-- Atualiza estado sem tocar animação
			if estadoAtual.estadoMov ~= "Correndo" then
				estadoAtual.estadoMov = "Correndo"
			end
			-- Apenas ajusta velocidade da track atual
			if animacaoAtualMov then
				animacaoAtualMov:AdjustSpeed(TIMINGS.RunInAirSpeed)
			end
			return
		end

		-- Decidir entre Pulando e Caindo (se não está correndo no ar)
		local agora = tick()
		if movementFlags.isFalling or (movementFlags.isJumping and velocidadeY <= -1 and agora >= jumpHoldUntil) then
			if estadoAtual.estadoMov ~= "Caindo" then
				estadoAtual.estadoMov = "Caindo"
				AtualizarAnimacaoMovimento()
			end
		else
			if estadoAtual.estadoMov ~= "Pulando" then
				estadoAtual.estadoMov = "Pulando"
				AtualizarAnimacaoMovimento()
			end
		end
		return
	end

	-- Prioridade 4: No chão - INPUT-BASED
	-- Determinar estado: Idle, Andando ou Correndo (baseado em MoveDirection, não velocidade)
	local isMoving = humanoid.MoveDirection.Magnitude > 0.1

	-- Verifica se está em ação de combate que impede correr
	local emCombate = (
		estadoAtual.estadoAcao == "AtacandoLeve"
		or estadoAtual.estadoAcao == "CarregandoPesado"
		or estadoAtual.estadoAcao == "AtaquePesado"
		or estadoAtual.estadoAcao == "Defendendo"
	)

	-- Se está em combate, força parar de correr localmente
	local podeCorrer = movementFlags.isRunning and not emCombate

	local novoEstado
	if isMoving then
		novoEstado = podeCorrer and "Correndo" or "Andando"
	else
		novoEstado = "Parado"
	end

	-- Se estado mudou
	if estadoAtual.estadoMov ~= novoEstado then
		estadoAtual.estadoMov = novoEstado
		AtualizarAnimacaoMovimento()
		-- Sincroniza estado de movimento com servidor
		TentarAcao:FireServer("SincronizarMovimento", novoEstado)
	else
		-- Estado não mudou, apenas restaura velocidade normal se estava no ar
		if animacaoAtualMov then
			-- Não sobrescreve velocidade se estamos andando enquanto atacando/defendendo
			emCombate = (
				estadoAtual.estadoAcao == "AtacandoLeve"
				or estadoAtual.estadoAcao == "CarregandoPesado"
				or estadoAtual.estadoAcao == "AtaquePesado"
				or estadoAtual.estadoAcao == "Defendendo"
			)
			if not (estadoAtual.estadoMov == "Andando" and emCombate) then
				animacaoAtualMov:AdjustSpeed(1)
			end
		end
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- DETECÇÃO DE QUEDA POR MATERIAL (AIR)
-- ═══════════════════════════════════════════════════════════════════

--- Verifica material do chão após animação de pulo
local function VerificarMaterialQueda()
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	-- Verifica o material do FloorMaterial do Humanoid
	local material = humanoid.FloorMaterial

	-- Se material é Air, significa que ainda está no ar
	if material == Enum.Material.Air then
		if estadoAtual.estadoMov ~= "Caindo" and estadoAtual.estadoMov ~= "Correndo" then
			estadoAtual.estadoMov = "Caindo"
			movementFlags.isFalling = true
			AtualizarAnimacaoMovimento()
		end
	else
		-- Aterrissou
		if movementFlags.isFalling or movementFlags.isJumping then
			movementFlags.isFalling = false
			movementFlags.isJumping = false
			-- Estado será atualizado pelo AtualizarEstadoMovimento
		end
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- LISTENERS DE ESTADO DO HUMANOID
-- ═══════════════════════════════════════════════════════════════════

--- Listener para mudanças de estado do Humanoid
local function OnStateChanged(oldState, newState)
	-- Atualiza flags baseado no novo estado
	movementFlags.isClimbing = (newState == Enum.HumanoidStateType.Climbing)
	movementFlags.isSwimming = (newState == Enum.HumanoidStateType.Swimming)
	movementFlags.isJumping = (newState == Enum.HumanoidStateType.Jumping)
	movementFlags.isFalling = (newState == Enum.HumanoidStateType.Freefall)

	-- Configura hold de pulo
	if movementFlags.isJumping then
		jumpHoldUntil = tick() + TIMINGS.JumpHold

		-- Se estava correndo, mantém a animação de corrida com velocidade reduzida
		if movementFlags.isRunning and animacaoAtualMov then
			animacaoAtualMov:AdjustSpeed(TIMINGS.RunInAirSpeed)
			estadoAtual.estadoMov = "Correndo"
			return -- Não chama AtualizarEstadoMovimento
		end

		-- Agenda verificação de material após animação de pulo
		task.delay(TIMINGS.JumpHold + 0.05, function()
			VerificarMaterialQueda()
		end)
	end

	-- Se aterrissou (Running, Landed, GettingUp), reseta flags de ar
	if
		newState == Enum.HumanoidStateType.Running
		or newState == Enum.HumanoidStateType.Landed
		or newState == Enum.HumanoidStateType.RunningNoPhysics
		or newState == Enum.HumanoidStateType.GettingUp
	then
		-- Verifica se realmente aterrissou (material não é Air)
		if humanoid.FloorMaterial ~= Enum.Material.Air then
			movementFlags.isJumping = false
			movementFlags.isFalling = false

			-- Se está correndo, mantém Correndo e restaura velocidade normal
			if movementFlags.isRunning then
				estadoAtual.estadoMov = "Correndo"
				if animacaoAtualMov then
					-- Só restaura velocidade completa se não estiver em combate (para não sobrescrever 0.4)
					local emCombate = (
						estadoAtual.estadoAcao == "AtacandoLeve"
						or estadoAtual.estadoAcao == "CarregandoPesado"
						or estadoAtual.estadoAcao == "AtaquePesado"
						or estadoAtual.estadoAcao == "Defendendo"
					)
					if not emCombate then
						animacaoAtualMov:AdjustSpeed(1)
					end
				end
				-- Sincroniza com servidor sem mudar para Parado
				TentarAcao:FireServer("SincronizarMovimento", "Correndo")
				TentarAcao:FireServer("Correr")
				return -- Não chama AtualizarEstadoMovimento
			end

			-- Envia ação de aterrissar para o servidor
			TentarAcao:FireServer("Aterrissar")
		else
			-- Ainda está no ar, muda para Caindo
			movementFlags.isFalling = true
			estadoAtual.estadoMov = "Caindo"
			AtualizarAnimacaoMovimento()
		end
	end

	-- Atualiza movimento imediatamente (só se não retornou antes)
	AtualizarEstadoMovimento()
end

-- Conecta listener de StateChanged
humanoid.StateChanged:Connect(OnStateChanged)

-- ═══════════════════════════════════════════════════════════════════
-- INPUT LOCAL - LEFTSHIFT PARA CORRIDA
-- ═══════════════════════════════════════════════════════════════════

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.LeftShift then
		movementFlags.isRunning = true
		isShiftHeld = true
		AtualizarEstadoMovimento()
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		movementFlags.isRunning = false
		isShiftHeld = false
		AtualizarEstadoMovimento()
	end
end)

-- ═══════════════════════════════════════════════════════════════════
-- CONEXÕES
-- ═══════════════════════════════════════════════════════════════════

SincronizarEstado.OnClientEvent:Connect(ProcessarSincronizacao)
TocarAnimacao.OnClientEvent:Connect(ProcessarTocarAnimacao)

-- Loop híbrido de atualização (para input-based como MoveDirection)
RunService.Heartbeat:Connect(AtualizarEstadoMovimento)

-- ═══════════════════════════════════════════════════════════════════
-- PRÉ-CARREGAMENTO DE ANIMAÇÕES
-- ═══════════════════════════════════════════════════════════════════

--- Pré-carrega todas as animações para evitar lag na primeira execução
local function PreCarregarAnimacoes()
	local todasAnimacoes = ArmasTemplate.ObterTodasAnimacoes()
	local total = #todasAnimacoes
	local carregadas = 0

	print(string.format("[ControladorEstado] Pré-carregando %d animações...", total))

	for _, animId in ipairs(todasAnimacoes) do
		-- Carrega a animação no cache
		local track = ObterAnimacao(animId)
		if track then
			carregadas = carregadas + 1
		end
	end

	print(string.format("[ControladorEstado] %d/%d animações pré-carregadas!", carregadas, total))
end

-- ═══════════════════════════════════════════════════════════════════
-- RECONEXÃO AO RESPAWNAR
-- ═══════════════════════════════════════════════════════════════════

player.CharacterAdded:Connect(function(novoCharacter)
	character = novoCharacter
	humanoid = character:WaitForChild("Humanoid")
	animator = humanoid:WaitForChild("Animator")

	-- Reconecta StateChanged
	humanoid.StateChanged:Connect(OnStateChanged)

	-- Desativa script Animate do novo personagem
	DesativarScriptAnimate()

	-- Limpa cache de animações
	animacoesCarregadas = {}
	animacaoAtualMov = nil
	animacaoAtualAcao = nil

	-- Limpa estado de combo
	LimparConexoesMarkers()
	comboState.animacaoAtiva = nil
	comboState.janelaAtiva = false
	comboState.indiceAtual = 0
	comboState.continuarCombo = false
	comboState.pendingConsume = false
	comboState.token = 0

	-- Reseta flags
	movementFlags = {
		isRunning = false,
		isJumping = false,
		isFalling = false,
		isClimbing = false,
		isSwimming = false,
	}
	jumpHoldUntil = 0

	-- Reseta estado
	estadoAtual = {
		estadoMov = "Parado",
		estadoAcao = "Nenhuma",
		estadoAcaoAnterior = "Nenhuma",
		modoAnimacao = "Base",
		bloqueando = false,
		agachado = false,
		correndo = false,
	}

	-- Pré-carrega animações novamente (cache foi limpo)
	PreCarregarAnimacoes()

	-- Começa com Idle
	AtualizarAnimacaoMovimento()
end)

-- ═══════════════════════════════════════════════════════════════════
-- INICIALIZAÇÃO
-- ═══════════════════════════════════════════════════════════════════

-- Pré-carrega todas as animações ao iniciar
PreCarregarAnimacoes()

-- Começa com Idle
AtualizarAnimacaoMovimento()

print("[ControladorEstado] Inicializado - movimento input-based + StateChanged")
