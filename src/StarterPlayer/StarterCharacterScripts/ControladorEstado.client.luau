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
	isDashing = false, -- Estado de dash
}

-- Flag global para saber se Shift está sendo segurado (independente de estado)
local isShiftHeld = false

-- Controle de pulo
local jumpHoldUntil = 0

-- Cache de animações
local animacoesCarregadas = {}
local animacaoAtualMov = nil
local animacaoAtualAcao = nil

-- Sistema de direção reversa para andar/correr para trás
local direcaoAtual = 1 -- 1 = frente, -1 = trás
local velocidadeAnimacaoAlvo = 1 -- Velocidade alvo (para interpolação suave)
local velocidadeAnimacaoAtual = 1 -- Velocidade atual (interpolada)
local animacaoUsaDirecao = false -- Se a animação atual usa sistema de direção reversa
local SUAVIDADE_TRANSICAO_DIRECAO = 10 -- Quanto maior, mais rápida a transição
local SUAVIDADE_TRANSICAO_CORRENDO = SUAVIDADE_TRANSICAO_DIRECAO * 2 -- Transição 2x mais rápida quando correndo

-- Sistema de pausa suave de animação (evita reset ao tocar rapidamente)
local animacaoMovPausada = false -- Se a animação está pausada (parado)
local ultimaAnimacaoMovNome = nil -- Nome da última animação de movimento
local TEMPO_MANTER_ANIMACAO = 0.27 -- Tempo para manter animação pausada antes de realmente parar
local VELOCIDADE_PAUSA = 0.2 -- Velocidade durante pausa (mantém movimento sutil)
local timerPararAnimacao = nil -- Timer para parar a animação após tempo

-- Animações que usam sistema de direção reversa
local ANIMACOES_COM_DIRECAO = {
	Andando = true,
	Correndo = true,
	AndandoAgachado = true,
}

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
-- SISTEMA DE ANIMAÇÃO DE EQUIPAR/DESEQUIPAR REVERSÍVEL
-- ═══════════════════════════════════════════════════════════════════

-- Estado da animação de equipar/desequipar
local equipAnimState = {
	animacao = nil, -- AnimationTrack atual
	direcao = 0, -- 1 = equipando, -1 = desequipando
	modoAlvo = nil, -- Modo para o qual está equipando
	conexaoTermino = nil, -- Conexão para detectar término
	conexaoMonitor = nil, -- Conexão para monitorar TimePosition (quando velocidade negativa)
	tempoInicio = 0, -- Tempo quando a animação iniciou (para calcular progresso)
}

--- Callback para quando a animação de equipar/desequipar termina
local function OnEquipAnimacaoTerminou()
	local direcaoFinal = equipAnimState.direcao

	-- Limpa estado
	if equipAnimState.conexaoTermino then
		equipAnimState.conexaoTermino:Disconnect()
		equipAnimState.conexaoTermino = nil
	end
	if equipAnimState.conexaoMonitor then
		equipAnimState.conexaoMonitor:Disconnect()
		equipAnimState.conexaoMonitor = nil
	end
	equipAnimState.animacao = nil
	equipAnimState.direcao = 0
	equipAnimState.modoAlvo = nil

	-- Notifica EntradaJogador que a animação terminou
	if _G.OnEquipAnimacaoTerminou then
		_G.OnEquipAnimacaoTerminou(direcaoFinal)
	end

	-- Atualiza animação de movimento
	AtualizarAnimacaoMovimento()

	print("[ControladorEstado] Animação de equipar/desequipar terminou (direção:", direcaoFinal, ")")
end

--- Monitora o TimePosition da animação quando está tocando em velocidade negativa
--- Detecta quando chega ao início (TimePosition <= 0) para parar a animação
local function IniciarMonitoramentoReversao()
	-- Remove monitor anterior se existir
	if equipAnimState.conexaoMonitor then
		equipAnimState.conexaoMonitor:Disconnect()
	end

	equipAnimState.conexaoMonitor = RunService.RenderStepped:Connect(function()
		if not equipAnimState.animacao or not equipAnimState.animacao.IsPlaying then
			-- Animação parou, limpa monitor
			if equipAnimState.conexaoMonitor then
				equipAnimState.conexaoMonitor:Disconnect()
				equipAnimState.conexaoMonitor = nil
			end
			return
		end

		-- Se está tocando em velocidade negativa e chegou ao início
		if equipAnimState.direcao == -1 and equipAnimState.animacao.TimePosition <= 0.01 then
			-- Para a animação manualmente
			equipAnimState.animacao:Stop(0.1)
			-- O callback OnEquipAnimacaoTerminou será chamado pelo Stopped event
		end
	end)
end

--- Inverte a direção da animação de equipar/desequipar
--- A inversão reverte a animação atual - se estava tocando pra frente, toca pra trás e vice-versa
--- @param novaDirecao number 1 para equipar, -1 para desequipar
function _G.InverterEquipAnimacao(novaDirecao: number)
	if not equipAnimState.animacao or not equipAnimState.animacao.IsPlaying then
		print("[ControladorEstado] Não há animação de equip ativa para inverter")
		return false
	end

	local direcaoAnterior = equipAnimState.direcao
	equipAnimState.direcao = novaDirecao

	-- A velocidade da animação é invertida (negativa do que era)
	-- Se estava em 1, vai para -1. Se estava em -1, vai para 1.
	local velocidadeAtual = equipAnimState.animacao.Speed
	local novaVelocidade = -velocidadeAtual
	equipAnimState.animacao:AdjustSpeed(novaVelocidade)

	-- Se a nova velocidade é negativa, inicia monitoramento para detectar quando chegar ao início
	if novaVelocidade < 0 then
		IniciarMonitoramentoReversao()
	else
		-- Se voltou para positivo, remove o monitor
		if equipAnimState.conexaoMonitor then
			equipAnimState.conexaoMonitor:Disconnect()
			equipAnimState.conexaoMonitor = nil
		end
	end

	print(
		"[ControladorEstado] Animação de equip invertida:",
		direcaoAnterior,
		"->",
		novaDirecao,
		"velocidade:",
		novaVelocidade
	)
	return true
end

--- Verifica se está em animação de equipar/desequipar
function _G.EstaEmAnimacaoEquip()
	return equipAnimState.animacao ~= nil and equipAnimState.animacao.IsPlaying
end

--- Obtém a direção atual da animação de equip (1, -1 ou 0)
function _G.ObterDirecaoEquip()
	return equipAnimState.direcao
end

-- ═══════════════════════════════════════════════════════════════════
-- SISTEMA DE DASH
-- ═══════════════════════════════════════════════════════════════════

-- Estado do dash local
local dashState = {
	animacao = nil, -- AnimationTrack atual do dash
	direcao = "Frente", -- Direção do dash atual
	conexaoTermino = nil, -- Conexão do evento Stopped
	velocityConnection = nil, -- Conexão do RenderStepped para impulso sustentado
}

--- Calcula a direção do dash baseado no input de movimento
--- Retorna a direção relativa ao LookVector do personagem
---@return string "Frente", "Tras", "Esquerda", "Direita"
local function CalcularDirecaoDashLocal(): string
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return "Frente"
	end

	local moveDir = humanoid.MoveDirection

	-- Se não está se movendo, dash para frente
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

	-- Determina direção primária baseada em qual dot product é maior
	if math.abs(dotForward) >= math.abs(dotRight) then
		-- Mais para frente/trás do que esquerda/direita
		if dotForward >= 0 then
			return "Frente"
		else
			return "Tras"
		end
	else
		-- Mais para esquerda/direita do que frente/trás
		if dotRight >= 0 then
			return "Direita"
		else
			return "Esquerda"
		end
	end
end

-- Expõe a função para EntradaJogador.client.lua usar
_G.CalcularDirecaoDash = CalcularDirecaoDashLocal

--- Inicia aplicação de impulso sustentado durante o dash
--- A direção é recalculada a cada frame baseado na orientação atual do personagem
local function IniciarImpulsoDash(direcao: string)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local config = ArmasTemplate.ConfiguracaoGlobal
	local forcaDash = config.ForcaDash or 50

	-- Cria conexão para aplicar velocidade sustentada durante o dash
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

		-- Recalcula direção a cada frame baseado na orientação ATUAL do personagem
		local lookVector = hrp.CFrame.LookVector
		local rightVector = hrp.CFrame.RightVector

		local dirVector
		if direcao == "Frente" then
			dirVector = lookVector
		elseif direcao == "Tras" then
			dirVector = -lookVector
		elseif direcao == "Esquerda" then
			dirVector = -rightVector
		elseif direcao == "Direita" then
			dirVector = rightVector
		else
			dirVector = lookVector
		end

		-- Normaliza para XZ (horizontal apenas)
		dirVector = Vector3.new(dirVector.X, 0, dirVector.Z).Unit

		-- Aplica velocidade sustentada (não impulso instantâneo)
		local velocidadeAtual = hrp.AssemblyLinearVelocity
		local velocidadeAlvo = dirVector * forcaDash

		-- Mantém componente Y (gravidade) e substitui XZ
		hrp.AssemblyLinearVelocity = Vector3.new(velocidadeAlvo.X, velocidadeAtual.Y, velocidadeAlvo.Z)
	end)
end

--- Para o impulso do dash
local function PararImpulsoDash()
	if dashState.velocityConnection then
		dashState.velocityConnection:Disconnect()
		dashState.velocityConnection = nil
	end
end

--- Callback quando animação de dash termina
local function OnDashAnimacaoTerminou()
	print("[ControladorEstado] Dash animação terminou")

	-- Para impulso
	PararImpulsoDash()

	-- Limpa estado
	dashState.animacao = nil
	dashState.direcao = "Frente"
	movementFlags.isDashing = false

	if dashState.conexaoTermino then
		dashState.conexaoTermino:Disconnect()
		dashState.conexaoTermino = nil
	end

	-- Notifica servidor que dash terminou
	TentarAcao:FireServer("DashTerminou")

	-- Atualiza animação de movimento
	AtualizarAnimacaoMovimento()
end

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES DE ANIMAÇÃO
-- ═══════════════════════════════════════════════════════════════════

--- Calcula o multiplicador de direção baseado na direção de movimento
--- Retorna 1 para frente, -1 para trás, com base no ângulo entre MoveDirection e LookVector
---@return number Multiplicador de direção (-1 a 1)
local function CalcularMultiplicadorDirecao(): number
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return 1
	end

	local moveDir = humanoid.MoveDirection
	if moveDir.Magnitude < 0.1 then
		return direcaoAtual -- Parado, mantém direção atual
	end

	-- Obtém apenas componentes XZ (ignora Y)
	local lookVector = hrp.CFrame.LookVector
	local lookXZ = Vector3.new(lookVector.X, 0, lookVector.Z).Unit
	local moveXZ = Vector3.new(moveDir.X, 0, moveDir.Z).Unit

	-- Calcula dot product para determinar se está indo para frente ou para trás
	local dot = lookXZ:Dot(moveXZ)

	-- dot > 0 = frente, dot < 0 = trás
	-- Usamos threshold de 0 para transição suave
	if dot < -0.1 then
		return -1 -- Andando para trás
	elseif dot > 0.1 then
		return 1 -- Andando para frente
	else
		-- Zona de transição (andando de lado), mantém direção atual
		return direcaoAtual
	end
end

--- Define a velocidade base da animação de movimento respeitando o sistema de direção
--- Se a animação usa direção reversa, atualiza velocidadeAnimacaoAlvo para interpolação suave
---@param velocidadeBase number Velocidade base (positiva)
local function DefinirVelocidadeMovimento(velocidadeBase: number)
	if not animacaoAtualMov or not animacaoAtualMov.IsPlaying then
		return
	end

	if animacaoUsaDirecao then
		-- Atualiza apenas a velocidade alvo, a interpolação faz o resto
		local mult = CalcularMultiplicadorDirecao()
		velocidadeAnimacaoAlvo = velocidadeBase * mult
	else
		-- Animação sem direção, aplica diretamente
		animacaoAtualMov:AdjustSpeed(velocidadeBase)
	end
end

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
--- Se forcarParar = false, pausa suavemente (para retomar depois)
--- Se forcarParar = true, para imediatamente
local function PararAnimacaoMov(forcarParar: boolean?)
	if animacaoAtualMov then
		-- Cancela timer anterior se existir
		if timerPararAnimacao then
			pcall(task.cancel, timerPararAnimacao)
			timerPararAnimacao = nil
		end

		if forcarParar then
			-- Para imediatamente
			animacaoAtualMov:Stop(TIMINGS.MoveFadeOut)
			animacaoAtualMov = nil
			animacaoMovPausada = false
			ultimaAnimacaoMovNome = nil
		else
			-- Pausa suavemente (velocidade vai para 0)
			animacaoMovPausada = true
			velocidadeAnimacaoAlvo = 0

			-- Agenda parada real após tempo
			timerPararAnimacao = task.delay(TEMPO_MANTER_ANIMACAO, function()
				if animacaoMovPausada and animacaoAtualMov then
					animacaoAtualMov:Stop(TIMINGS.MoveFadeOut)
					animacaoAtualMov = nil
					animacaoMovPausada = false
					ultimaAnimacaoMovNome = nil

					-- Toca a animação de Idle do modo atual
					AtualizarAnimacaoMovimento()
				end
				timerPararAnimacao = nil
			end)
		end
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
---@param nomeAnimacao string Nome da animação
---@param velocidadeBase number? Velocidade base (será multiplicada pela direção se aplicável)
local function TocarAnimacaoMov(nomeAnimacao: string, velocidadeBase: number?)
	local animId = ArmasTemplate.ObterAnimacao(estadoAtual.modoAnimacao, nomeAnimacao)
	if not animId then
		return
	end

	local track = ObterAnimacao(animId)
	if not track then
		return
	end

	-- Verifica se esta animação usa sistema de direção reversa
	local usaDirecao = ANIMACOES_COM_DIRECAO[nomeAnimacao] == true
	local velocidade = velocidadeBase or 1

	-- Cancela timer de parada se existir (estamos retomando)
	if timerPararAnimacao then
		pcall(task.cancel, timerPararAnimacao)
		timerPararAnimacao = nil
	end

	-- Verifica se é a mesma animação que estava pausada ou tocando
	local mesmaAnimacao = (animacaoAtualMov == track)
		or (ultimaAnimacaoMovNome == nomeAnimacao and animacaoAtualMov and animacaoAtualMov.IsPlaying)

	if mesmaAnimacao and animacaoAtualMov and animacaoAtualMov.IsPlaying then
		-- Retoma ou continua a animação existente
		animacaoMovPausada = false
		animacaoUsaDirecao = usaDirecao

		if not usaDirecao then
			-- Se não usa direção, aplica velocidade diretamente
			velocidadeAnimacaoAlvo = velocidade
		else
			-- A velocidade será ajustada no loop de Heartbeat
			velocidadeAnimacaoAlvo = velocidade * CalcularMultiplicadorDirecao()
		end
		return
	end

	-- Verifica se é uma animação diferente da atual
	if animacaoAtualMov and animacaoAtualMov ~= track then
		-- Para a animação anterior (forçado, pois é diferente)
		-- Mas preserva a direção atual para continuidade
		PararAnimacaoMov(true)
	end

	-- Se não tinha animação ou era diferente, inicia nova
	if not animacaoAtualMov or not animacaoAtualMov.IsPlaying then
		track.Priority = Enum.AnimationPriority.Core
		track.Looped = true
		track:Play(TIMINGS.MoveFadeIn)

		-- Aplica velocidade inicial imediatamente com direção preservada
		if usaDirecao then
			local mult = CalcularMultiplicadorDirecao()
			-- Se já tínhamos uma direção, preserva ela
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
	end

	-- Configura sistema de direção
	animacaoUsaDirecao = usaDirecao
	animacaoMovPausada = false
	ultimaAnimacaoMovNome = nomeAnimacao

	if usaDirecao then
		-- Calcula velocidade alvo com direção
		local mult = CalcularMultiplicadorDirecao()
		velocidadeAnimacaoAlvo = velocidade * mult
		-- velocidadeAnimacaoAtual já foi definida acima, interpolação fará a transição
	else
		-- Animação normal sem sistema de direção
		velocidadeAnimacaoAlvo = velocidade
	end

	animacaoAtualMov = track
end

--- Toca animação de ação
--- Para animações de combo (AtaqueLeve), configura sistema de marcadores
--- Para animações de equipar/desequipar, configura sistema de animação reversível
---@param animId string ID da animação
---@param loop boolean Se a animação deve loopar
---@param velocidade number Velocidade inicial da animação
---@param nomeAnimacao string? Nome da animação (opcional, usado para detectar combo)
local function TocarAnimacaoAcao(animId: string, loop: boolean, velocidade: number, nomeAnimacao: string?)
	local track = ObterAnimacao(animId)
	if not track then
		return
	end

	-- Verifica se é animação de equipar/desequipar
	local ehEquipar = nomeAnimacao and (nomeAnimacao == "Equipar" or nomeAnimacao == "Desequipar")

	-- Verifica se é animação de dash
	local ehDash = nomeAnimacao and (nomeAnimacao:match("^Dash"))

	-- Se é equipar/desequipar e já tem uma animação de equip tocando, não para - vai inverter depois
	if ehEquipar and equipAnimState.animacao and equipAnimState.animacao.IsPlaying then
		-- A inversão será feita pelo sistema de InverterEquipAnimacao
		-- Não inicia nova animação
		return
	end

	PararAnimacaoAcao()

	track.Priority = Enum.AnimationPriority.Action
	track.Looped = loop
	track:Play(0.1)
	track:AdjustSpeed(velocidade)

	animacaoAtualAcao = track

	-- Configura sistema de dash
	if ehDash then
		-- Limpa estado anterior
		if dashState.conexaoTermino then
			dashState.conexaoTermino:Disconnect()
		end
		PararImpulsoDash()

		-- Extrai direção do nome da animação (DashFrente, DashTras, etc.)
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

		-- Conecta callback de término
		dashState.conexaoTermino = track.Stopped:Connect(function()
			OnDashAnimacaoTerminou()
		end)

		-- Inicia impulso sustentado
		IniciarImpulsoDash(direcao)

		print("[ControladorEstado] Animação de Dash iniciada:", nomeAnimacao)
		return
	end

	-- Configura sistema de equipar/desequipar reversível
	if ehEquipar then
		-- Limpa conexão anterior se existir
		if equipAnimState.conexaoTermino then
			equipAnimState.conexaoTermino:Disconnect()
		end
		if equipAnimState.conexaoMonitor then
			equipAnimState.conexaoMonitor:Disconnect()
			equipAnimState.conexaoMonitor = nil
		end

		equipAnimState.animacao = track
		-- Direção: 1 para equipar, -1 para desequipar
		-- IMPORTANTE: Isso determina o que o callback final vai reportar
		equipAnimState.direcao = (nomeAnimacao == "Equipar") and 1 or -1
		equipAnimState.tempoInicio = tick()

		-- Conecta callback de término
		equipAnimState.conexaoTermino = track.Stopped:Connect(function()
			OnEquipAnimacaoTerminou()
		end)

		print("[ControladorEstado] Animação de", nomeAnimacao, "iniciada (direção:", equipAnimState.direcao, ")")
		return
	end

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

	-- Verifica se está parando de andar/correr para usar sistema de pausa
	local animacaoQueUsaDirecao = ANIMACOES_COM_DIRECAO[ultimaAnimacaoMovNome]
	local querIdle = (nomeAnimacao == "Idle" or nomeAnimacao == "IdleAgachado")

	if querIdle and animacaoQueUsaDirecao and animacaoAtualMov and animacaoAtualMov.IsPlaying then
		-- Ao invés de trocar para Idle, pausa a animação atual
		-- Isso permite retomar suavemente se o jogador voltar a andar rapidamente
		PararAnimacaoMov(false) -- Pausa suave
		return
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
	local modoAnterior = estadoAtual.modoAnimacao

	-- Atualiza estado local
	estadoAtual.estadoMov = dados.estadoMov
	estadoAtual.estadoAcao = dados.estadoAcao
	estadoAtual.modoAnimacao = dados.modoAnimacao
	estadoAtual.bloqueando = dados.bloqueando
	estadoAtual.agachado = dados.agachado
	estadoAtual.correndo = dados.correndo

	-- Se o modo de animação mudou, força atualização da animação de movimento
	-- Isso garante que ao equipar/desequipar, as animações troquem para o novo modo
	local modoMudou = modoAnterior ~= estadoAtual.modoAnimacao
	if modoMudou and animacaoAtualMov then
		-- Evita forçar parada de movimento se o jogador estiver no ar correndo,
		-- pois queremos que a animação de corrida no ar continue a tocar.
		if movementFlags.isJumping or movementFlags.isFalling then
			-- Se estiver no ar, apenas atualiza nome da última animação para evitar
			-- conflitos posteriores, mas não para a track atual.
			ultimaAnimacaoMovNome = nil
		else
			-- Para a animação atual forçadamente para garantir que a nova seja do modo correto
			PararAnimacaoMov(true)
		end
	end

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
		-- Apenas ajusta velocidade respeitando direção
		DefinirVelocidadeMovimento(TIMINGS.RunInAirSpeed)
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
			-- Apenas ajusta velocidade da track atual respeitando direção
			DefinirVelocidadeMovimento(TIMINGS.RunInAirSpeed)
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
				DefinirVelocidadeMovimento(1)
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
			DefinirVelocidadeMovimento(TIMINGS.RunInAirSpeed)
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
						DefinirVelocidadeMovimento(1)
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
-- INTERPOLAÇÃO SUAVE DE DIREÇÃO DA ANIMAÇÃO
-- ═══════════════════════════════════════════════════════════════════

--- Atualiza a velocidade da animação de movimento com interpolação suave
--- Permite transição suave entre andar para frente (velocidade +1) e para trás (-1)
--- Também permite pausar suavemente (velocidade 0) quando parado
local function AtualizarDirecaoAnimacao(deltaTime: number)
	-- Só processa se há animação de movimento ativa
	if not animacaoAtualMov or not animacaoAtualMov.IsPlaying then
		return
	end

	-- Se está pausado, interpola para velocidade reduzida (mantém direção)
	if animacaoMovPausada then
		-- Velocidade alvo é VELOCIDADE_PAUSA com direção preservada
		local velocidadePausaComDirecao = VELOCIDADE_PAUSA * direcaoAtual
		local diferenca = velocidadePausaComDirecao - velocidadeAnimacaoAtual
		if math.abs(diferenca) > 0.01 then
			-- Usa transição rápida para pausar
			velocidadeAnimacaoAtual = velocidadeAnimacaoAtual
				+ diferenca * math.min(1, deltaTime * SUAVIDADE_TRANSICAO_CORRENDO)
			animacaoAtualMov:AdjustSpeed(velocidadeAnimacaoAtual)
		elseif velocidadeAnimacaoAtual ~= velocidadePausaComDirecao then
			velocidadeAnimacaoAtual = velocidadePausaComDirecao
			animacaoAtualMov:AdjustSpeed(velocidadePausaComDirecao)
		end
		return
	end

	-- Se não usa sistema de direção, apenas interpola para a velocidade alvo
	if not animacaoUsaDirecao then
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

	-- Calcula nova direção baseada no movimento atual
	local novaDirecao = CalcularMultiplicadorDirecao()

	-- Atualiza direção atual se mudou
	if novaDirecao ~= direcaoAtual then
		direcaoAtual = novaDirecao
	end

	-- Calcula velocidade alvo (velocidade base * direção)
	-- A velocidade base é o valor absoluto da velocidade alvo anterior
	local velocidadeBase = math.abs(velocidadeAnimacaoAlvo)
	if velocidadeBase == 0 then
		velocidadeBase = 1
	end
	velocidadeAnimacaoAlvo = velocidadeBase * direcaoAtual

	-- Determina a suavidade da transição
	-- Usa transição mais rápida quando está correndo
	local suavidade = SUAVIDADE_TRANSICAO_DIRECAO
	if estadoAtual.estadoMov == "Correndo" then
		suavidade = SUAVIDADE_TRANSICAO_CORRENDO
	end

	-- Interpolação suave (lerp) da velocidade atual para a alvo
	local diferenca = velocidadeAnimacaoAlvo - velocidadeAnimacaoAtual
	if math.abs(diferenca) > 0.01 then
		velocidadeAnimacaoAtual = velocidadeAnimacaoAtual + diferenca * math.min(1, deltaTime * suavidade)
		animacaoAtualMov:AdjustSpeed(velocidadeAnimacaoAtual)
	elseif velocidadeAnimacaoAtual ~= velocidadeAnimacaoAlvo then
		-- Snap para valor final quando muito próximo
		velocidadeAnimacaoAtual = velocidadeAnimacaoAlvo
		animacaoAtualMov:AdjustSpeed(velocidadeAnimacaoAtual)
	end
end

-- Loop de interpolação de direção (RenderStepped para suavidade visual)
RunService.RenderStepped:Connect(AtualizarDirecaoAnimacao)

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

	-- Reseta sistema de direção reversa
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
