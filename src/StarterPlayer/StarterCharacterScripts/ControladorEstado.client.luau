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

-- ═══════════════════════════════════════════════════════════════════
-- CONFIGURAÇÃO DE DEBUG
-- ═══════════════════════════════════════════════════════════════════
local DEBUG_ENABLED = true -- Altere para true para habilitar prints de debug

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

local Modulos = ReplicatedStorage:WaitForChild("Modulos")
local Modulo_Configuracoes = require(Modulos:WaitForChild("Combate"):WaitForChild("Modulo_Configuracoes"))

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
		DebugPrint("[ControladorEstado] Script Animate padrão desativado")
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

-- ═══════════════════════════════════════════════════════════════════
-- SISTEMA DE VELOCIDADE CLIENT-SIDE
-- A corrida é 100% client-side para evitar lag e spam de requests
-- ═══════════════════════════════════════════════════════════════════

-- Forward declaration
local AtualizarVelocidadeLocal

--- Atualiza a velocidade de movimento localmente baseado no estado atual
--- Chamada sempre que o estado muda (correndo, parado, etc)
AtualizarVelocidadeLocal = function()
	-- Acessa via ObterConfiguracao para cada valor, ou faz um cache local se necessário
	-- Para velocidade, vamos puxar direto
	local VelBloq = Modulo_Configuracoes.ObterConfiguracao("VelocidadeBloqueando")
	local VelAgachado = Modulo_Configuracoes.ObterConfiguracao("VelocidadeAgachado")
	local VelCorrendo = Modulo_Configuracoes.ObterConfiguracao("VelocidadeCorrendo")
	local VelNormal = Modulo_Configuracoes.ObterConfiguracao("VelocidadeNormal")

	-- Se está em ação de combate, usa velocidade de combate
	local emCombate = (
		estadoAtual.estadoAcao == "AtacandoLeve"
		or estadoAtual.estadoAcao == "CarregandoPesado"
		or estadoAtual.estadoAcao == "SoltandoPesado"
		or estadoAtual.estadoAcao == "AtaquePesado"
	)

	if emCombate then
		-- Velocidade de ataque: VelocidadeBloqueando * 1.5
		local velBloq = VelBloq or 8
		humanoid.WalkSpeed = velBloq * 1.5
		return
	end

	-- Se está defendendo, usa velocidade de defesa
	if estadoAtual.estadoAcao == "Defendendo" or estadoAtual.bloqueando then
		humanoid.WalkSpeed = VelBloq or 8
		return
	end

	-- Determina velocidade baseado no estado de corrida (client-side)
	if estadoAtual.agachado then
		humanoid.WalkSpeed = VelAgachado or 12
	elseif movementFlags.isRunning then
		humanoid.WalkSpeed = VelCorrendo or 25
	else
		humanoid.WalkSpeed = VelNormal or 16
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- SINCRONIZAÇÃO COM STATUSLOCAL FOLDER
-- Atualiza a pasta StatusLocal (client-side) para DebugUI e outros scripts
-- ═══════════════════════════════════════════════════════════════════

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

	-- Sincroniza estados de movimento (client-side)
	atualizarValor("modoAnimacao", estadoAtual.modoAnimacao)
	atualizarValor("estadoMov", estadoAtual.estadoMov)
	atualizarValor("AgachadoOn", estadoAtual.agachado)
	-- CorrendoOn é baseado em estadoMov para manter consistência visual
	atualizarValor("CorrendoOn", estadoAtual.estadoMov == "Correndo")

	-- Debug específico para CorrendoOn
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
	-- NOTA: ShiftLockOn é atualizado pelo CameraModule, não aqui
end

-- Cache de animações
local animacoesCarregadas = {}
local animacaoAtualMov = nil
local animacaoAtualAcao = nil

-- Base Idle (camada de fundo contínua para manter postura)
local animacaoBaseIdle = nil
local idBaseIdleAtual = nil

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

local DEBOUNCE_TROCA_LATERAL = 0.1 -- Tempo mínimo entre trocas de animação lateral
local ultimaTrocaLateralTime = 0 -- Timestamp da última troca de animação lateral (debounce)

-- Estado persistente do ciclo de caminhada (para preservação entre pulos/pausas)
local walkCycleState = {
	time = 0,
	speed = 1,
	lastWalkAnimName = nil,
}

-- Animações que usam sistema de direção reversa
local ANIMACOES_COM_DIRECAO = {
	Andando = true,
	Correndo = true,
	AndandoAgachado = true,
	AndandoDireita = true,
	AndandoEsquerda = true,
	CorrendoDireita = true,
	CorrendoEsquerda = true,
}

-- Animações que NÃO devem loopar (tocam uma vez e param)
local ANIMACOES_SEM_LOOP = {
	Pulando = true,
	-- Caindo é loop pois não sabemos quanto tempo vai durar a queda
}

-- Estado da animação de pulo (para controlar transição para Caindo)
local jumpAnimState = {
	animacao = nil, -- AnimationTrack da animação de pulo
	conexaoTermino = nil, -- Conexão ao Stopped para detectar término
	aguardandoTermino = false, -- Se estamos aguardando a animação terminar
}

-- Forward declaration de funções usadas antes de serem definidas
local AtualizarAnimacaoMovimento
local AtualizarBaseIdle
local ObterAnimacao
local PararAnimacaoMov

--- Atualiza a animação de Idle base (camada de fundo de prioridade Core)
--- Isso garante que o personagem mantenha a postura do modo atual mesmo durante transições de movimento
AtualizarBaseIdle = function()
	local nomeIdle = estadoAtual.agachado and "IdleAgachado" or "Idle"
	local animId = Modulo_Configuracoes.ObterIdAnimacao(estadoAtual.modoAnimacao, nomeIdle)

	if not animId then
		-- Fallback para Base Idle se o modo não tiver
		animId = Modulo_Configuracoes.ObterIdAnimacao("Base", nomeIdle)
	end

	if not animId or animId == idBaseIdleAtual then
		return
	end

	idBaseIdleAtual = animId
	local novaTrack = ObterAnimacao(animId)

	if novaTrack then
		-- Para o idle anterior suavemente
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
	earlyCancelTimer = nil, -- Timer para cancelamento antecipado
	earlyCancelExecutado = false, -- Se o cancelamento antecipado já foi executado
	tempoInicio = 0, -- Momento em que o combo iniciou (para defense cancel)
	conexaoMonitorReversao = nil :: RBXScriptConnection?, -- Conexão para monitorar reversão
}

-- Estado global para cancelamento por defesa
local defenseCancelState = {
	ultimoCancelamento = 0, -- Tempo do último cancelamento (para cooldown)
	cancelPendente = false, -- Se há um cancel que ainda não resolveu a animação
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

	-- Cancela timer de early cancel se existir
	if comboState.earlyCancelTimer then
		pcall(task.cancel, comboState.earlyCancelTimer)
		comboState.earlyCancelTimer = nil
	end

	-- Limpa monitor de reversão se existir
	if comboState.conexaoMonitorReversao then
		comboState.conexaoMonitorReversao:Disconnect()
		comboState.conexaoMonitorReversao = nil
	end
end

--- Chamado quando a animação de combo termina (naturalmente ou forçada)
local function OnComboAnimacaoTerminou()
	DebugPrint("[ControladorEstado] Combo animação terminou")

	LimparConexoesMarkers()

	comboState.animacaoAtiva = nil
	comboState.janelaAtiva = false
	comboState.indiceAtual = 0
	comboState.continuarCombo = false
	comboState.pendingConsume = false
	comboState.token = 0
	comboState.earlyCancelExecutado = false
	comboState.tempoInicio = 0

	-- Atualiza estado local
	estadoAtual.estadoAcao = "Nenhuma"

	-- Notifica servidor que combo terminou
	TentarAcao:FireServer("ComboTerminou")

	-- Se o jogador está segurando Shift, volta a correr LOCALMENTE
	-- Não envia para servidor - corrida é 100% client-side
	if isShiftHeld then
		movementFlags.isRunning = true
		estadoAtual.estadoMov = "Correndo"
		estadoAtual.correndo = true
	end

	-- Atualiza velocidade ao sair de combate (client-side)
	AtualizarVelocidadeLocal()

	-- Atualiza Base Idle imediatamente
	AtualizarBaseIdle()

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

	DebugPrint(string.format("[ControladorEstado] Janela de combo ativada (golpe %d)", indice))

	-- Obtém configuração do combo
	local combo = Modulo_Configuracoes.ObterConfiguracaoCombo(estadoAtual.modoAnimacao)
	if not combo then
		return
	end

	-- Reduz velocidade da animação durante a janela
	comboState.animacaoAtiva:AdjustSpeed(combo.velocidadeJanela)

	-- Se o jogador já clicou antes da janela abrir (pending), consumir imediatamente
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
			DebugPrint("[ControladorEstado] Combo continuando - velocidade restaurada")
			comboState.janelaAtiva = false
			comboState.continuarCombo = false

			if comboState.animacaoAtiva and comboState.animacaoAtiva.IsPlaying then
				comboState.animacaoAtiva:AdjustSpeed(1)
			end

			-- Notifica servidor que combo continua
			TentarAcao:FireServer("ComboContinuado", comboState.indiceAtual + 1)
		else
			-- Jogador não clicou - termina combo
			DebugPrint("[ControladorEstado] Janela expirou - combo terminando")
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

	DebugPrint(string.format("[ControladorEstado] Marker Attack - golpe %s (índice %d)", indiceGolpe, indice))

	-- Determina tipo de ataque baseado no índice do combo
	local tipoAtaque = Modulo_Configuracoes.ObterTipoAtaquePorIndice(estadoAtual.modoAnimacao, indice)

	-- Aplica impulso de ataque no cliente (feedback imediato)
	if _G.AplicarImpulsoAtaque then
		_G.AplicarImpulsoAtaque(tipoAtaque)
	end

	-- Notifica servidor para criar hitbox - envia CFrame atual para sincronia fina
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local dados = {
		indice = indice,
		cframe = hrp and hrp.CFrame or nil,
	}
	TentarAcao:FireServer("ComboHitbox", dados)

	-- Se é o golpe 4 (final), configura early cancel e aguarda animação terminar
	if indice >= 4 then
		comboState.janelaAtiva = false -- Não tem mais janela após o final
		DebugPrint("[ControladorEstado] Golpe final executado")

		-- Configura timer de early cancel baseado no tempo restante da animação
		if comboState.animacaoAtiva and comboState.animacaoAtiva.IsPlaying then
			local track = comboState.animacaoAtiva
			local janelaEarlyCancel = Modulo_Configuracoes.ObterConfiguracao("JanelaCancelamentoComboFinal") or 0.15
			local tempoRestante = (track.Length - track.TimePosition) / track.Speed

			-- Só agenda early cancel se houver tempo suficiente
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
					-- Verifica se ainda está no mesmo combo e não foi cancelado
					if
						comboState.animacaoAtiva
						and comboState.animacaoAtiva.IsPlaying
						and not comboState.earlyCancelExecutado
					then
						comboState.earlyCancelExecutado = true
						DebugPrint("[ControladorEstado] Early cancel executado - mudando estado para Normal")

						-- Atualiza estado local imediatamente
						estadoAtual.estadoAcao = "Nenhuma"

						-- Notifica servidor para mudar estado antecipadamente
						TentarAcao:FireServer("ComboEarlyCancel")

						-- Se o jogador está segurando Shift, volta a correr LOCALMENTE
						-- Não envia para servidor - corrida é 100% client-side
						if isShiftHeld then
							movementFlags.isRunning = true
							estadoAtual.estadoMov = "Correndo"
							estadoAtual.correndo = true
						end

						-- Atualiza velocidade ao sair de combate (client-side)
						AtualizarVelocidadeLocal()

						-- Atualiza animação de movimento (a animação de combo vai terminar naturalmente em background)
						AtualizarAnimacaoMovimento()
					end
				end)
			end
		end
	end
end

--- Configura listeners de marcadores para uma animação de combo
---@param track AnimationTrack
local function ConfigurarMarkersCombo(track: AnimationTrack)
	LimparConexoesMarkers() -- Limpa anteriores

	local combo = Modulo_Configuracoes.ObterConfiguracaoCombo(estadoAtual.modoAnimacao)
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

	DebugPrint("[ControladorEstado] Markers de combo configurados")
end

--- Marca que o jogador quer continuar o combo
--- Chamado por EntradaJogador quando M1 é pressionado
--- Retorna true se está em combo ativo (janela aberta ou animação rodando)
function _G.MarcarContinuarCombo()
	-- Se está na janela, marca para continuar
	if comboState.janelaAtiva then
		comboState.continuarCombo = true
		DebugPrint("[ControladorEstado] Input de continuar combo registrado (janela ativa)")
		return true
	end

	-- Se combo está ativo mas ainda não chegou na janela, marca como pending
	if comboState.animacaoAtiva and comboState.animacaoAtiva.IsPlaying then
		comboState.pendingConsume = true
		DebugPrint("[ControladorEstado] Input antecipado registrado (pending)")
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
-- SISTEMA DE ATAQUE PESADO POR MARCADORES
-- ═══════════════════════════════════════════════════════════════════

--[[
	O sistema de ataque pesado funciona assim:
	1. Player segura M1 por mais de 0.2s → Cliente envia "CarregarPesado"
	2. Servidor envia animação "AtaquePesado" com velocidade 0.3 (lenta)
	3. Quando a animação chega no marcador "AttackRelease":
	   - Se ainda está segurando M1 → pausa animação (velocidade 0)
	   - Se já soltou M1 → continua normalmente
	4. Quando solta M1 → Cliente envia "SoltarPesado" → animação continua (velocidade 1)
	5. Quando chega no marcador "HeavyAttack" → hitbox é criada pelo servidor
	
	Marcadores na animação:
	- "AttackRelease" - Ponto onde a animação pausa se ainda segurando M1
	- "HeavyAttack" - Momento de criar hitbox (parâmetro opcional)
]]

-- Estado local do ataque pesado
local heavyAttackState = {
	animacao = nil, -- AnimationTrack atual
	aguardandoSoltar = false, -- Se está pausado esperando soltar M1
	conexoesMarkers = {}, -- Conexões dos markers
	conexaoTermino = nil, -- Conexão para detectar término
	earlyCancelTimer = nil, -- Timer para cancelamento antecipado
	earlyCancelExecutado = false, -- Se o cancelamento antecipado já foi executado
	tempoInicio = 0, -- Momento em que o carregamento iniciou (para defense cancel)
	conexaoMonitorReversao = nil :: RBXScriptConnection?, -- Conexão para monitorar reversão
}

--- Limpa conexões de markers do ataque pesado
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

	-- Cancela timer de early cancel se existir
	if heavyAttackState.earlyCancelTimer then
		pcall(task.cancel, heavyAttackState.earlyCancelTimer)
		heavyAttackState.earlyCancelTimer = nil
	end

	-- Limpa monitor de reversão se existir
	if heavyAttackState.conexaoMonitorReversao then
		heavyAttackState.conexaoMonitorReversao:Disconnect()
		heavyAttackState.conexaoMonitorReversao = nil
	end
end

--- Chamado quando a animação de ataque pesado termina
local function OnHeavyAttackTerminou()
	DebugPrint("[ControladorEstado] Animação de ataque pesado terminou")
	LimparConexoesHeavyAttack()
	heavyAttackState.animacao = nil
	heavyAttackState.aguardandoSoltar = false
	heavyAttackState.earlyCancelExecutado = false

	-- Atualiza estado local
	estadoAtual.estadoAcao = "Nenhuma"

	-- Se o jogador está segurando Shift, volta a correr LOCALMENTE
	if isShiftHeld then
		movementFlags.isRunning = true
		estadoAtual.estadoMov = "Correndo"
		estadoAtual.correndo = true
	end

	-- Atualiza velocidade ao sair de combate (client-side)
	AtualizarVelocidadeLocal()

	AtualizarAnimacaoMovimento()

	-- Notifica o servidor que a animação de ação terminou (para completar estado e resetar velocidade)
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

--- Processa o marcador "AttackRelease" - ponto de pausa
local function OnMarkerAttackRelease()
	DebugPrint("[ControladorEstado] Marcador AttackRelease atingido")

	if not heavyAttackState.animacao or not heavyAttackState.animacao.IsPlaying then
		return
	end

	-- Verifica se o jogador ainda está segurando M1
	-- Usa função global exposta pelo EntradaJogador
	local aindaSegurando = _G.EstaSegurandoM1 and _G.EstaSegurandoM1()

	if aindaSegurando then
		-- Pausa a animação - aguarda soltar M1
		heavyAttackState.animacao:AdjustSpeed(0)
		heavyAttackState.aguardandoSoltar = true
		DebugPrint("[ControladorEstado] Animação pausada - aguardando soltar M1")
	else
		-- Já soltou M1, continua a animação normalmente
		-- A velocidade já foi ajustada para 1 pelo SoltarPesado do servidor
		DebugPrint("[ControladorEstado] M1 já foi solto - animação continua")
	end
end

--- Processa o marcador "HeavyAttack" - momento de criar hitbox
local function OnMarkerHeavyAttack()
	DebugPrint("[ControladorEstado] Marcador HeavyAttack atingido - notificando servidor para criar hitbox")

	-- Aplica impulso de ataque pesado no cliente (feedback imediato)
	if _G.AplicarImpulsoAtaque then
		_G.AplicarImpulsoAtaque("AtaquePesado")
	end

	-- Notifica o servidor para criar o hitbox do ataque pesado - envia CFrame para sincronia
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local dados = {
		cframe = hrp and hrp.CFrame or nil,
	}
	TentarAcao:FireServer("HeavyAttackHitbox", dados)

	-- Configura timer de early cancel baseado no tempo restante da animação
	if heavyAttackState.animacao and heavyAttackState.animacao.IsPlaying then
		local track = heavyAttackState.animacao
		local janelaEarlyCancel = Modulo_Configuracoes.ObterConfiguracao("JanelaCancelamentoAtaquePesado") or 0.2
		local speed = math.max(track.Speed, 0.1) -- Evita divisão por zero
		local tempoRestante = (track.Length - track.TimePosition) / speed

		-- Só agenda early cancel se houver tempo suficiente
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
				-- Verifica se ainda está no ataque pesado e não foi cancelado
				if
					heavyAttackState.animacao
					and heavyAttackState.animacao.IsPlaying
					and not heavyAttackState.earlyCancelExecutado
				then
					heavyAttackState.earlyCancelExecutado = true
					DebugPrint("[ControladorEstado] Heavy attack early cancel executado - mudando estado para Normal")

					-- Atualiza estado local imediatamente
					estadoAtual.estadoAcao = "Nenhuma"

					-- Notifica servidor para mudar estado antecipadamente
					TentarAcao:FireServer("HeavyAttackEarlyCancel")

					-- Se o jogador está segurando Shift, volta a correr LOCALMENTE
					-- Não envia para servidor - corrida é 100% client-side
					if isShiftHeld then
						movementFlags.isRunning = true
						estadoAtual.estadoMov = "Correndo"
						estadoAtual.correndo = true
					end

					-- Atualiza velocidade ao sair de combate (client-side)
					AtualizarVelocidadeLocal()

					-- Atualiza animação de movimento (a animação de ataque pesado vai terminar naturalmente em background)
					AtualizarAnimacaoMovimento()
				end
			end)
		end
	end
end

--- Configura listeners de marcadores para uma animação de ataque pesado
---@param track AnimationTrack
local function ConfigurarMarkersHeavyAttack(track: AnimationTrack)
	LimparConexoesHeavyAttack()

	heavyAttackState.animacao = track
	heavyAttackState.aguardandoSoltar = false

	-- Marcador de pausa (AttackRelease)
	local conexaoRelease = track:GetMarkerReachedSignal("AttackRelease"):Connect(function()
		OnMarkerAttackRelease()
	end)
	table.insert(heavyAttackState.conexoesMarkers, conexaoRelease)

	-- Marcador de hitbox (HeavyAttack)
	local conexaoHit = track:GetMarkerReachedSignal("HeavyAttack"):Connect(function()
		OnMarkerHeavyAttack()
	end)
	table.insert(heavyAttackState.conexoesMarkers, conexaoHit)

	-- Conexão de término
	heavyAttackState.conexaoTermino = track.Stopped:Connect(function()
		OnHeavyAttackTerminou()
	end)

	DebugPrint("[ControladorEstado] Markers de ataque pesado configurados")
end

--- Continua a animação de ataque pesado (chamado quando M1 é solto)
--- Chamado por EntradaJogador via _G quando SoltarPesado é enviado
--- Apenas ajusta a velocidade da animação - NÃO reinicia
function _G.ContinuarAtaquePesado()
	if not heavyAttackState.animacao or not heavyAttackState.animacao.IsPlaying then
		DebugPrint("[ControladorEstado] ContinuarAtaquePesado - sem animação ativa")
		return false
	end

	-- Obtém velocidade configurável para quando solta M1
	local velocidadeSoltar = Modulo_Configuracoes.ObterConfiguracao("VelocidadeSoltarPesado") or 1.0

	if heavyAttackState.aguardandoSoltar then
		-- Estava pausado (velocidade 0), continua a animação com velocidade de soltar
		heavyAttackState.animacao:AdjustSpeed(velocidadeSoltar)
		heavyAttackState.aguardandoSoltar = false
		DebugPrint("[ControladorEstado] Animação de ataque pesado retomada (velocidade:", velocidadeSoltar, ")")
		return true
	end

	-- Não estava pausado, mas ainda assim ajusta velocidade para a de soltar
	-- Isso garante que a animação tenha a velocidade correta após soltar M1
	heavyAttackState.animacao:AdjustSpeed(velocidadeSoltar)
	DebugPrint("[ControladorEstado] Velocidade ajustada para soltar (velocidade:", velocidadeSoltar, ")")
	return true
end

--- Verifica se está em ataque pesado ativo
function _G.EstaAtaquePesadoAtivo()
	return heavyAttackState.animacao and heavyAttackState.animacao.IsPlaying
end

--- Verifica se está aguardando soltar M1 no ataque pesado
function _G.EstaAguardandoSoltarPesado()
	return heavyAttackState.aguardandoSoltar
end

-- ═══════════════════════════════════════════════════════════════════
-- SISTEMA DE CANCELAMENTO POR DEFESA
-- ═══════════════════════════════════════════════════════════════════

--- Tenta cancelar ataque por defesa
--- Retorna true se cancelou com sucesso, false caso contrário
--- @return boolean sucesso
--- @return string? tipoAtaque O tipo de ataque que foi cancelado ("AtaqueLeve" ou "CarregandoPesado")
function _G.TentarCancelarAtaquePorDefesa()
	local agora = tick()

	-- Verifica cooldown de cancelamento
	local cooldown = Modulo_Configuracoes.ObterConfiguracao("CooldownCancelamentoPorDefesa") or 1.0
	if (agora - defenseCancelState.ultimoCancelamento) < cooldown then
		DebugPrint("[ControladorEstado] Defense cancel em cooldown")
		return false, nil
	end

	-- Verifica se está em ataque leve (combo) dentro da janela
	if comboState.animacaoAtiva and comboState.animacaoAtiva.IsPlaying then
		local tempoDecorrido = agora - comboState.tempoInicio
		local janelaAtaque = Modulo_Configuracoes.ObterConfiguracao("JanelaCancelamentoAtaquePorDefesa") or 0.15

		-- Só permite cancelar no primeiro golpe do combo (índice 1) e dentro da janela
		if comboState.indiceAtual <= 1 and tempoDecorrido <= janelaAtaque then
			DebugPrint(
				string.format(
					"[ControladorEstado] Defense cancel: Cancelando ataque leve (%.3fs dentro da janela de %.3fs)",
					tempoDecorrido,
					janelaAtaque
				)
			)

			-- Reverte a animação gradualmente para evitar que o braço "dê uma volta" ao voltar pro Idle
			local track = comboState.animacaoAtiva
			local velReversao = Modulo_Configuracoes.ObterConfiguracao("VelocidadeReversaoCancelamento") or -1.5
			track:AdjustSpeed(velReversao)

			-- Monitora para parar quando chegar ao início
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

			-- Limpa estado
			LimparConexoesMarkers()
			comboState.animacaoAtiva = nil
			comboState.janelaAtiva = false
			comboState.indiceAtual = 0
			comboState.continuarCombo = false
			comboState.pendingConsume = false
			comboState.token = 0
			comboState.earlyCancelExecutado = false
			comboState.tempoInicio = 0

			-- Atualiza estado local
			estadoAtual.estadoAcao = "Nenhuma"

			-- Registra cooldown
			defenseCancelState.ultimoCancelamento = agora

			-- Marca que há um cancel pendente (não atualiza animação ainda)
			-- O EntradaJogador vai decidir se deve voltar ao Idle ou ir para defesa
			defenseCancelState.cancelPendente = true

			return true, "AtaqueLeve"
		end
	end

	-- Verifica se está carregando ataque pesado dentro da janela
	if heavyAttackState.animacao and heavyAttackState.animacao.IsPlaying then
		local tempoDecorrido = agora - heavyAttackState.tempoInicio
		local janelaCarregar = Modulo_Configuracoes.ObterConfiguracao("JanelaCancelamentoCarregamentoPorDefesa") or 0.92

		-- Só permite cancelar se ainda não passou do marcador AttackRelease (ainda carregando)
		-- E se estiver dentro da janela
		if tempoDecorrido <= janelaCarregar then
			DebugPrint(
				string.format(
					"[ControladorEstado] Defense cancel: Cancelando carregamento pesado (%.3fs dentro da janela de %.3fs)",
					tempoDecorrido,
					janelaCarregar
				)
			)

			-- Reverte a animação gradualmente
			local track = heavyAttackState.animacao
			local velReversao = Modulo_Configuracoes.ObterConfiguracao("VelocidadeReversaoCancelamento") or -1.5
			track:AdjustSpeed(velReversao)

			-- Monitora para parar quando chegar ao início
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

			-- Limpa estado
			LimparConexoesHeavyAttack()
			heavyAttackState.animacao = nil
			heavyAttackState.aguardandoSoltar = false
			heavyAttackState.earlyCancelExecutado = false
			heavyAttackState.tempoInicio = 0

			-- Atualiza estado local
			estadoAtual.estadoAcao = "Nenhuma"

			-- Registra cooldown
			defenseCancelState.ultimoCancelamento = agora

			-- Marca que há um cancel pendente (não atualiza animação ainda)
			-- O EntradaJogador vai decidir se deve voltar ao Idle ou ir para defesa
			defenseCancelState.cancelPendente = true

			return true, "CarregandoPesado"
		end
	end

	return false, nil
end

--- Resolve o cancel pendente - volta para animação de movimento (Idle)
--- Chamado pelo EntradaJogador quando o jogador solta M2 sem defender
function _G.ResolverCancelPendente()
	if defenseCancelState.cancelPendente then
		defenseCancelState.cancelPendente = false
		DebugPrint("[ControladorEstado] Cancel pendente resolvido - voltando ao Idle")
		AtualizarAnimacaoMovimento()
	end
end

--- Cancela o cancel pendente - não volta ao Idle pois vai defender
--- Chamado pelo EntradaJogador quando o jogador vai iniciar defesa
function _G.CancelarCancelPendente()
	if defenseCancelState.cancelPendente then
		defenseCancelState.cancelPendente = false
		DebugPrint("[ControladorEstado] Cancel pendente cancelado - indo para defesa")
		-- Não chama AtualizarAnimacaoMovimento(), a animação de defesa vai tomar conta
	end
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
	-- Sistema de acessório de arma
	acessorioClonado = nil, -- Referência ao Accessory clonado no character
	conexaoMarkerEquip = nil, -- Conexão do marker "Equip" na animação
	conexaoMarkerDesequip = nil, -- Conexão do marker "Desequip" na animação
	acessorioJaClonado = false, -- Flag para evitar clonagens duplicadas
}

-- ═══════════════════════════════════════════════════════════════════
-- SISTEMA DE ACESSÓRIO DE ARMA (CLONAGEM/REMOÇÃO)
-- ═══════════════════════════════════════════════════════════════════

--- Obtém o Tool atualmente equipado no character
---@return Tool? O Tool equipado ou nil
local function ObterToolEquipado(): Tool?
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Tool")
end

--- Clona o acessório "AcessorioMaoDireita" do Tool para o character do jogador
--- Usa Humanoid:AddAccessory() para posicionamento automático
local function ClonarAcessorioParaJogador()
	-- Evita clonagem duplicada
	if equipAnimState.acessorioJaClonado then
		-- Robustez: Verifica se o acessório ainda existe e está no personagem
		if equipAnimState.acessorioClonado and equipAnimState.acessorioClonado.Parent == character then
			DebugPrint("[ControladorEstado] Acessório já foi clonado e existe, ignorando")
			return
		else
			-- Estado inconsistente: diz que está clonado mas objeto sumiu
			DebugPrint("[ControladorEstado] AVISO: acessorioJaClonado=true mas objeto sumiu. Resetando flag.")
			equipAnimState.acessorioJaClonado = false
			equipAnimState.acessorioClonado = nil
		end
	end

	local tool = ObterToolEquipado()
	if not tool then
		DebugPrint("[ControladorEstado] Nenhum Tool equipado para clonar acessório")
		return
	end

	-- Busca o acessório dentro do Tool
	local acessorioOriginal = tool:FindFirstChild("AcessorioMaoDireita")
	if not acessorioOriginal or not acessorioOriginal:IsA("Accessory") then
		DebugPrint("[ControladorEstado] AcessorioMaoDireita não encontrado no Tool:", tool.Name)
		return
	end

	-- Verifica se a mão existe para garantir que o AddAccessory terá onde prender
	local hand = character:FindFirstChild("Right Arm") or character:FindFirstChild("RightHand")
	if not hand then
		DebugPrint("[ControladorEstado] Mão (Right Arm/RightHand) não encontrada no character")
		return
	end

	-- Verifica se já existe um acessório clonado no character (limpeza de segurança)
	local acessorioExistente = character:FindFirstChild("AcessorioMaoDireita")
	if acessorioExistente then
		acessorioExistente:Destroy()
	end

	-- Clona o acessório (não destrói o original dentro do Tool)
	local acessorioClone = acessorioOriginal:Clone()
	local handle = acessorioClone:FindFirstChild("Handle")

	if not handle then
		DebugPrint("[ControladorEstado] Erro: Acessório clonado não possui um 'Handle'")
		acessorioClone:Destroy()
		return
	end

	-- Limpeza e Configuração Física
	-- Importante: Peças ancoradas ou com colisão ativa podem impedir o grip correto ou causar problemas de física
	for _, part in ipairs(acessorioClone:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.Massless = true
		elseif (part:IsA("Weld") or part:IsA("ManualWeld")) and part.Name == "AccessoryWeld" then
			-- Remove AccessoryWeld antigo/sujo se existir para o AddAccessory criar um novo limpo
			part:Destroy()
		elseif part:IsA("ProximityPrompt") then
			part:Destroy()
		end
	end

	-- Adiciona o acessório ao Humanoid (posicionamento automático via AttachmentPoints)
	humanoid:AddAccessory(acessorioClone)

	-- Sistema de Grip Robusto:
	-- Se o Roblox não criar o 'AccessoryWeld' automaticamente (pode ocorrer no cliente), fazemos manualmente.
	local accessoryWeld = handle:FindFirstChild("AccessoryWeld")
	if not accessoryWeld then
		local bodyAttachment = hand:FindFirstChild("RightGripAttachment")
		local handleAttachment = handle:FindFirstChild("RightGripAttachment")

		if bodyAttachment and handleAttachment then
			local newWeld = Instance.new("Weld")
			newWeld.Name = "AccessoryWeld"
			newWeld.Part0 = handle
			newWeld.Part1 = hand
			newWeld.C0 = handleAttachment.CFrame
			newWeld.C1 = bodyAttachment.CFrame
			newWeld.Parent = handle
			DebugPrint("[ControladorEstado] Grip manual aplicado (Weld criado manualmente)")
		else
			DebugPrint("[ControladorEstado] Falha ao criar Grip: Attachments não encontrados na mão ou na arma")
		end
	end

	-- Salva referência no estado
	equipAnimState.acessorioClonado = acessorioClone
	equipAnimState.acessorioJaClonado = true

	DebugPrint("[ControladorEstado] Acessório clonado para o jogador:", acessorioClone.Name)
end

--- Remove o acessório "AcessorioMaoDireita" do character do jogador
local function RemoverAcessorioDoJogador()
	-- Primeiro tenta usar a referência salva
	if equipAnimState.acessorioClonado then
		if equipAnimState.acessorioClonado.Parent then
			equipAnimState.acessorioClonado:Destroy()
			DebugPrint("[ControladorEstado] Acessório removido via referência salva")
		end
		equipAnimState.acessorioClonado = nil
		equipAnimState.acessorioJaClonado = false
		return
	end

	-- Fallback: busca diretamente no character
	if character then
		local acessorio = character:FindFirstChild("AcessorioMaoDireita")
		if acessorio then
			acessorio:Destroy()
			DebugPrint("[ControladorEstado] Acessório removido via busca no character")
		end
	end

	equipAnimState.acessorioJaClonado = false
end

--- Limpa todas as conexões de markers de equip/desequip
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

--- Configura os listeners de markers para animação de equipar/desequipar
--- @param track AnimationTrack A animação a ser monitorada
--- @param ehEquipar boolean true se é animação de equipar, false se é desequipar
local function ConfigurarMarkersEquip(track: AnimationTrack, ehEquipar: boolean)
	-- Limpa conexões anteriores
	LimparConexoesMarkersEquip()

	if ehEquipar then
		-- Animação de Equipar: conecta ao marker "Equip" para clonar acessório
		equipAnimState.conexaoMarkerEquip = track:GetMarkerReachedSignal("Equip"):Connect(function()
			-- Verifica se ainda está na direção de equipar (pode ter invertido)
			if equipAnimState.direcao == 1 then
				ClonarAcessorioParaJogador()
				DebugPrint("[ControladorEstado] Marker 'Equip' atingido - acessório clonado")
			end
		end)
	else
		-- Animação de Desequipar: conecta ao marker "Desequip" para remover acessório
		equipAnimState.conexaoMarkerDesequip = track:GetMarkerReachedSignal("Desequip"):Connect(function()
			-- Verifica se ainda está na direção de desequipar (pode ter invertido)
			if equipAnimState.direcao == -1 then
				RemoverAcessorioDoJogador()
				DebugPrint("[ControladorEstado] Marker 'Desequip' atingido - acessório removido")
			end
		end)
	end
end

--- Callback para quando a animação de equipar/desequipar termina
local function OnEquipAnimacaoTerminou()
	local direcaoFinal = equipAnimState.direcao

	-- Limpa conexões de markers
	LimparConexoesMarkersEquip()

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

	-- Garante estado final correto do acessório
	if direcaoFinal == 1 then
		-- Terminou equipando: garante que acessório está clonado
		if not equipAnimState.acessorioJaClonado then
			ClonarAcessorioParaJogador()
		end
	elseif direcaoFinal == -1 then
		-- Terminou desequipando: garante que acessório foi removido
		RemoverAcessorioDoJogador()
	end

	-- Notifica EntradaJogador que a animação terminou
	if _G.OnEquipAnimacaoTerminou then
		_G.OnEquipAnimacaoTerminou(direcaoFinal)
	end

	-- Atualiza animação de movimento
	AtualizarAnimacaoMovimento()

	DebugPrint("[ControladorEstado] Animação de equipar/desequipar terminou (direção:", direcaoFinal, ")")
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
		DebugPrint("[ControladorEstado] Não há animação de equip ativa para inverter")
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

	-- Reconfigura markers para a nova direção
	-- Os markers "Equip" e "Desequip" são diferentes, então reconectamos
	local ehEquiparAgora = (novaDirecao == 1)
	ConfigurarMarkersEquip(equipAnimState.animacao, ehEquiparAgora)

	-- Se inverteu de equipar para desequipar e já tinha clonado o acessório,
	-- o marker "Desequip" vai removê-lo quando for atingido
	-- Se inverteu de desequipar para equipar e o acessório ainda existe,
	-- o marker "Equip" vai cloná-lo quando for atingido (evita duplicatas via flag)

	DebugPrint(
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

--- Verifica se o personagem está fazendo dash
function _G.EstaEmDash()
	return movementFlags.isDashing
end

--- Inicia aplicação de impulso sustentado durante o dash
--- A direção é recalculada a cada frame baseado na orientação atual do personagem
local function IniciarImpulsoDash(direcao: string)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local forcaDash = Modulo_Configuracoes.ObterConfiguracao("ForcaDash") or 50

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
	DebugPrint("[ControladorEstado] Dash animação terminou")

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
-- SISTEMA DE IMPULSO DE ATAQUE
-- ═══════════════════════════════════════════════════════════════════

--[[
	Sistema de impulso único aplicado ao atacante durante ataques.
	Diferente do Dash (contínuo), este aplica velocidade uma única vez.
	A direção é baseada na orientação do personagem (LookVector).
]]

--- Aplica impulso único ao atacante na direção que está virado
--- @param tipoAtaque string Tipo do ataque ("AtaqueLeve", "AtaqueLeveFinal", "AtaquePesado")
local function AplicarImpulsoAtaque(tipoAtaque: string)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	-- Determina magnitude baseada no tipo de ataque
	local magnitude
	if tipoAtaque == "AtaquePesado" or tipoAtaque == "AtaqueLeveFinal" then
		magnitude = Modulo_Configuracoes.ObterConfiguracao("MagnitudeImpulsoAtaquePesado") or 25
	else
		magnitude = Modulo_Configuracoes.ObterConfiguracao("MagnitudeImpulsoAtaqueLeve") or 15
	end

	-- Direção que o atacante está virado (LookVector)
	local direcao = hrp.CFrame.LookVector
	direcao = Vector3.new(direcao.X, 0, direcao.Z).Unit

	-- Aplica velocidade única (substitui XZ, mantém Y)
	local velocidadeAtual = hrp.AssemblyLinearVelocity
	local impulso = direcao * magnitude
	hrp.AssemblyLinearVelocity = Vector3.new(impulso.X, velocidadeAtual.Y, impulso.Z)

	DebugPrint(
		string.format("[ControladorEstado] Impulso de ataque aplicado: %s (magnitude: %.1f)", tipoAtaque, magnitude)
	)
end

-- Expõe para uso interno
_G.AplicarImpulsoAtaque = AplicarImpulsoAtaque

-- ═══════════════════════════════════════════════════════════════════
-- SISTEMA DE KNOCKBACK (RECEPTOR)
-- ═══════════════════════════════════════════════════════════════════

--[[
	Sistema de knockback físico recebido do servidor.
	Aplica impulso na direção enviada pelo servidor (baseada no atacante).
	Substitui o sistema antigo de animação de posição por Bezier.
]]

--- Aplica knockback recebido do servidor usando impulso físico
--- @param direcao Vector3 Direção normalizada do knockback
--- @param magnitude number Força do impulso
local function AplicarKnockbackRecebido(direcao: Vector3, magnitude: number)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	-- Normaliza para XZ
	direcao = Vector3.new(direcao.X, 0, direcao.Z).Unit

	-- Aplica impulso com leve elevação
	local velocidadeAtual = hrp.AssemblyLinearVelocity
	hrp.AssemblyLinearVelocity = Vector3.new(
		direcao.X * magnitude,
		velocidadeAtual.Y + 5, -- Leve elevação para feedback visual
		direcao.Z * magnitude
	)

	DebugPrint(string.format("[ControladorEstado] Knockback recebido: magnitude=%.1f", magnitude))
end

-- Conecta ao RemoteEvent de knockback (será criado se não existir)
local AplicarKnockbackRemote = Remotos:FindFirstChild("AplicarKnockback")
if AplicarKnockbackRemote then
	AplicarKnockbackRemote.OnClientEvent:Connect(function(direcao, magnitude)
		AplicarKnockbackRecebido(direcao, magnitude)
	end)
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

--- Calcula se o jogador está em movimento lateral (ShiftLock/FirstPerson)
--- Retorna o nome da animação lateral e a velocidade (1 ou -1)
--- Só ativa se tiver componente lateral E frontal/traseiro ao mesmo tempo
---@return string Nome da animação ("Nenhum", "AndandoDireita", "AndandoEsquerda")
---@return number Velocidade da animação (1 = frente, -1 = trás/reverso)
local function CalcularMovimentoLateral(): (string, number)
	-- Verifica se está em ShiftLock ou FirstPerson
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

	-- Thresholds para considerar movimento
	local thresholdLateral = 0.3
	local thresholdFrontal = 0.3

	local temComponenteLateral = math.abs(dotRight) > thresholdLateral
	local temComponenteFrontal = math.abs(dotForward) > thresholdFrontal

	-- Precisa ter componente lateral para ativar animação lateral
	if not temComponenteLateral then
		return "Nenhum", 1
	end

	-- Lógica de animação:
	-- Se tem componente lateral + frontal/traseiro:
	--   Direita + Frente = AndandoDireita (speed 1)
	--   Direita + Trás = AndandoEsquerda (speed -1)
	--   Esquerda + Frente = AndandoEsquerda (speed 1)
	--   Esquerda + Trás = AndandoDireita (speed -1)
	-- Se tem APENAS componente lateral (sem frontal/traseiro):
	--   Direita = AndandoDireita (speed 1, como se estivesse indo pra frente+direita)
	--   Esquerda = AndandoEsquerda (speed 1, como se estivesse indo pra frente+esquerda)
	local indoParaDireita = dotRight > 0
	local indoParaFrente = dotForward > 0

	-- Verifica se está em ação de combate que impede correr (mesma lógica de AtualizarEstadoMovimento)
	local emCombate = (
		estadoAtual.estadoAcao == "AtacandoLeve"
		or estadoAtual.estadoAcao == "CarregandoPesado"
		or estadoAtual.estadoAcao == "SoltandoPesado"
		or estadoAtual.estadoAcao == "AtaquePesado"
		or estadoAtual.estadoAcao == "Defendendo"
		or estadoAtual.bloqueando
	)

	-- Determina prefixo baseado no estado de corrida E combate
	local podeCorrer = movementFlags.isRunning and not emCombate
	local prefixo = podeCorrer and "Correndo" or "Andando"

	if temComponenteFrontal then
		-- Tem componente frontal/traseiro, usa lógica completa
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
		-- APENAS movimento lateral, sempre velocidade 1 (como se estivesse indo pra frente)
		if indoParaDireita then
			return prefixo .. "Direita", 1
		else
			return prefixo .. "Esquerda", 1
		end
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

--- Para animação atual de movimento
--- Se forcarParar = false, pausa suavemente (para retomar depois)
--- Se forcarParar = true, para imediatamente
PararAnimacaoMov = function(forcarParar: boolean?)
	if animacaoAtualMov then
		-- Cancela timer anterior se existir
		if timerPararAnimacao then
			pcall(task.cancel, timerPararAnimacao)
			timerPararAnimacao = nil
		end

		if forcarParar then
			-- Salva ciclo antes de parar se for uma animação de movimento direcional
			if ANIMACOES_COM_DIRECAO[ultimaAnimacaoMovNome] then
				walkCycleState.time = animacaoAtualMov.TimePosition
				walkCycleState.speed = velocidadeAnimacaoAtual
				walkCycleState.lastWalkAnimName = ultimaAnimacaoMovNome
			end

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
					-- Salva ciclo antes de parar definitivamente
					if ANIMACOES_COM_DIRECAO[ultimaAnimacaoMovNome] then
						walkCycleState.time = animacaoAtualMov.TimePosition
						walkCycleState.speed = velocidadeAnimacaoAtual
						walkCycleState.lastWalkAnimName = ultimaAnimacaoMovNome
					end

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

--- Limpa estado da animação de pulo
local function LimparJumpAnimState()
	if jumpAnimState.conexaoTermino then
		jumpAnimState.conexaoTermino:Disconnect()
		jumpAnimState.conexaoTermino = nil
	end
	jumpAnimState.animacao = nil
	jumpAnimState.aguardandoTermino = false
end

--- Callback quando animação de pulo termina
local function OnJumpAnimacaoTerminou()
	DebugPrint("[ControladorEstado] Animação de Pulando terminou completamente")

	-- Limpa estado do pulo
	LimparJumpAnimState()

	-- Só transita para Caindo se ainda está no ar
	if movementFlags.isJumping or movementFlags.isFalling then
		-- Marca que agora está caindo (animação de pulo terminou)
		movementFlags.isJumping = false
		movementFlags.isFalling = true
		estadoAtual.estadoMov = "Caindo"
		-- Notifica o servidor para atualizar o estado autoritativo também
		pcall(function()
			TentarAcao:FireServer("SincronizarMovimento", "Caindo")
		end)
		AtualizarAnimacaoMovimento()
		DebugPrint("[ControladorEstado] Transitando para Caindo após animação de pulo")
	end
end

--- Toca animação de movimento
---@param nomeAnimacao string Nome da animação
---@param velocidadeBase number? Velocidade base (será multiplicada pela direção se aplicável)
local function TocarAnimacaoMov(nomeAnimacao: string, velocidadeBase: number?)
	local animId = Modulo_Configuracoes.ObterIdAnimacao(estadoAtual.modoAnimacao, nomeAnimacao)
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

	-- Verifica se esta animação deve loopar ou não
	local deveLoop = not ANIMACOES_SEM_LOOP[nomeAnimacao]

	-- Cancela timer de parada se existir (estamos retomando)
	if timerPararAnimacao then
		pcall(task.cancel, timerPararAnimacao)
		timerPararAnimacao = nil
	end

	-- Se estamos tocando uma animação diferente de Pulando, limpa estado do pulo
	if nomeAnimacao ~= "Pulando" then
		LimparJumpAnimState()
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
		-- Tenta restaurar ciclo de caminhada se for uma animação direcional
		local tempoParaRestaurar = 0
		if usaDirecao then
			-- Prioridade: Se a animação ANTERIOR era direcional, usa o tempo dela
			-- Se não (ex: pulando, caindo), usa o walkCycleState salvo

			-- Verifica se havia uma animação rodando e se ela era direcional
			-- Precisamos saber o nome da animação anterior para saber se é direcional
			-- Como animacaoAtualMov está mudando, o 'track' não é mais o anterior
			-- Mas ainda não trocamos `animacaoAtualMov` aqui dentro do if... espere!
			-- Este bloco roda quando `animacaoAtualMov` é nil ou != track.
			-- Se fosse != track, nós chamamos PararAnimacaoMov(true) acima.
			-- PararAnimacaoMov(true) salva o state e zera animacaoAtualMov.
			-- PORTANTO: animacaoAtualMov aqui SEMPRE SERÁ NIL na prática (ou parado).
			-- Então sempre devemos confiar no walkCycleState.

			if walkCycleState.time > 0 then
				tempoParaRestaurar = walkCycleState.time
				-- Inverte tempo se mudou de direção principal (frente/trás) desde o save
				local multAtual = CalcularMultiplicadorDirecao()
				local multAntigo = walkCycleState.speed > 0 and 1 or -1
				if multAtual ~= multAntigo then
					tempoParaRestaurar = track.Length - (tempoParaRestaurar % track.Length)
				end
			end
		end

		track.Priority = Enum.AnimationPriority.Movement
		track.Looped = deveLoop
		track:Play(TIMINGS.MoveFadeIn)

		-- Restaura tempo se disponível
		if tempoParaRestaurar > 0 then
			track.TimePosition = tempoParaRestaurar % track.Length
			walkCycleState.time = 0 -- Consome o tempo salvo
		end

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

		-- Se é animação de pulo, configura callback de término
		if nomeAnimacao == "Pulando" then
			LimparJumpAnimState() -- Limpa estado anterior se houver
			jumpAnimState.animacao = track
			jumpAnimState.aguardandoTermino = true
			jumpAnimState.conexaoTermino = track.Stopped:Connect(OnJumpAnimacaoTerminou)
			DebugPrint("[ControladorEstado] Animação de Pulando iniciada (sem loop, aguardando término)")
		end

		animacaoAtualMov = track
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

		DebugPrint("[ControladorEstado] Animação de Dash iniciada:", nomeAnimacao)
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

		-- Determina se é animação de equipar ou desequipar
		local ehEquiparDirecao = (nomeAnimacao == "Equipar")

		equipAnimState.animacao = track
		-- Direção: 1 para equipar, -1 para desequipar
		-- IMPORTANTE: Isso determina o que o callback final vai reportar
		equipAnimState.direcao = ehEquiparDirecao and 1 or -1
		equipAnimState.tempoInicio = tick()

		-- Reseta flag de clonagem ao iniciar nova animação de equipar
		if ehEquiparDirecao then
			equipAnimState.acessorioJaClonado = false
		end

		-- Configura markers para controlar visibilidade do acessório
		ConfigurarMarkersEquip(track, ehEquiparDirecao)

		-- Conecta callback de término
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

	-- Verifica se é uma animação de combo para configurar markers
	local ehCombo = nomeAnimacao and (nomeAnimacao == "AtaqueLeve" or nomeAnimacao:match("^AtaqueLeve"))
	local combo = Modulo_Configuracoes.ObterConfiguracaoCombo(estadoAtual.modoAnimacao)

	if ehCombo and combo and nomeAnimacao then
		-- Configura sistema de combo por marcadores
		comboState.animacaoAtiva = track
		comboState.janelaAtiva = false
		comboState.indiceAtual = 1
		comboState.continuarCombo = false
		comboState.tempoInicio = tick() -- Marca início para defense cancel

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

	-- Verifica se é animação de ataque pesado para configurar markers
	local ehAtaquePesado = nomeAnimacao and nomeAnimacao == "AtaquePesado"

	if ehAtaquePesado then
		-- Configura sistema de ataque pesado por marcadores
		heavyAttackState.tempoInicio = tick() -- Marca início para defense cancel
		ConfigurarMarkersHeavyAttack(track)

		DebugPrint(
			string.format("[ControladorEstado] Animação de ataque pesado iniciada (velocidade %.1f)", velocidade)
		)
	end
end

--- Calcula o multiplicador de velocidade da animação baseado no estado atual
---@return number O multiplicador (0.55 para defesa, 0.85 para ataque, etc.)
local function ObterMultiplicadorVelocidadeAnimacao(): number
	local estado = estadoAtual.estadoMov
	local multiplicador = 1

	-- Se está no ar correndo, usa velocidade reduzida
	if estado == "Correndo" and (movementFlags.isJumping or movementFlags.isFalling) then
		multiplicador = TIMINGS.RunInAirSpeed
	end

	-- Se está atacando ou defendendo e andando, usa multiplicadores distintos
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

	-- Se está agachado andando
	if estadoAtual.agachado and estado == "Andando" then
		multiplicador = 0.8
	end

	return multiplicador
end

--- Atualiza animação de movimento baseado no estado
AtualizarAnimacaoMovimento = function()
	-- Sincroniza estado com pasta StatusLocal (para DebugUI e outros scripts)
	SincronizarStatusLocal()

	local estado = estadoAtual.estadoMov
	local velocidade = ObterMultiplicadorVelocidadeAnimacao()

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

	-- Se está agachado, use animações específicas de agachado
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

	-- ═══════════════════════════════════════════════════════════════════
	-- FIX DEFINITIVO: Guarda defensiva para corrida no ar
	-- Se isRunning = true, NUNCA toca animação de pulo/queda
	-- Isso captura qualquer edge case que os handlers de evento possam ter perdido
	-- ═══════════════════════════════════════════════════════════════════
	if movementFlags.isRunning and (nomeAnimacao == "Pulando" or nomeAnimacao == "Caindo") then
		if DEBUG_ENABLED then
			print(string.format("[DEBUG] GUARD: Bloqueando %s enquanto corre -> forçando Correndo", nomeAnimacao))
		end
		nomeAnimacao = "Correndo"
		estadoAtual.estadoMov = "Correndo"
		velocidade = TIMINGS.RunInAirSpeed
	end

	-- Verifica se está parando de andar/correr para usar sistema de pausa
	local animacaoQueUsaDirecao = ANIMACOES_COM_DIRECAO[ultimaAnimacaoMovNome]
	local querIdle = (nomeAnimacao == "Idle" or nomeAnimacao == "IdleAgachado")

	-- Se quer Idle, apenas para qualquer animação de movimento ativa
	-- A camada BaseIdle (Core) aparecerá automaticamente
	if querIdle then
		if animacaoQueUsaDirecao and animacaoAtualMov and animacaoAtualMov.IsPlaying and not animacaoMovPausada then
			-- Inicia pausa suave para permitir retorno rápido
			PararAnimacaoMov(false)
		elseif not animacaoMovPausada then
			-- Para imediatamente se não for caso de pausa suave ou se já passou do tempo
			PararAnimacaoMov(true)
		end
		return
	end

	-- Verifica se precisa tocar animação lateral (ShiftLock/FirstPerson + andando/correndo para o lado)
	-- Só verifica se está andando ou correndo (não agachado)
	if (nomeAnimacao == "Andando" or nomeAnimacao == "Correndo") and not estadoAtual.agachado then
		local tipoLateral, velocidadeLateral = CalcularMovimentoLateral()
		if tipoLateral ~= "Nenhum" then
			-- Se já está na animação lateral correta, não precisa trocar
			if ultimaAnimacaoMovNome == tipoLateral and animacaoAtualMov and animacaoAtualMov.IsPlaying then
				-- Apenas atualiza a velocidade alvo
				velocidadeAnimacaoAlvo = velocidadeLateral * velocidade
				return
			end

			-- Debounce: evita trocas de animação lateral muito rápidas
			local tempoDesdeUltimaTroca = tick() - ultimaTrocaLateralTime
			if tempoDesdeUltimaTroca < DEBOUNCE_TROCA_LATERAL then
				-- Ainda em período de debounce, apenas atualiza velocidade se já está em lateral
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

			-- Preservar ciclo da animação atual antes de trocar (ou usar salvo se veio de Caindo)
			local tempoAtual = 0
			local velocidadeAnterior = velocidadeAnimacaoAtual

			-- Só herda tempo da animação atual se ela for DIRECIONAL (Andando/Correndo)
			-- Se for Pulando/Caindo, devemos ignorar e usar o state salvo
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

			-- Toca a animação lateral
			local animId = Modulo_Configuracoes.ObterIdAnimacao(estadoAtual.modoAnimacao, tipoLateral)
			if animId then
				local track = ObterAnimacao(animId)
				if track then
					-- Para animação anterior (forçado)
					if animacaoAtualMov and animacaoAtualMov ~= track then
						PararAnimacaoMov(true)
					end

					-- Inicia nova animação
					track.Priority = Enum.AnimationPriority.Movement
					track.Looped = true
					track:Play(TIMINGS.MoveFadeIn)

					-- Restaura tempo para continuidade
					if tempoAtual > 0 then
						local tempoAlvo = tempoAtual
						-- Inverte tempo se mudou de direção (frente -> trás ou vice-versa)
						local estaEmReverso = velocidadeLateral < 0
						local estavaEmReverso = velocidadeAnterior < 0

						if estaEmReverso ~= estavaEmReverso then
							tempoAlvo = track.Length - (tempoAtual % track.Length)
						end
						track.TimePosition = tempoAlvo % track.Length
						walkCycleState.time = 0 -- Consome
					end

					local velocidadeFinalScale = velocidadeLateral * velocidade
					track:AdjustSpeed(velocidadeFinalScale)
					velocidadeAnimacaoAtual = velocidadeFinalScale
					velocidadeAnimacaoAlvo = velocidadeFinalScale

					animacaoAtualMov = track
					animacaoUsaDirecao = true
					animacaoMovPausada = false
					ultimaAnimacaoMovNome = tipoLateral

					-- Atualiza direção atual baseada na velocidade
					direcaoAtual = velocidadeLateral > 0 and 1 or -1
					ultimaTrocaLateralTime = tick()
				end
			end
			return
		else
			-- Não está em movimento lateral MAS pode estar saindo de uma animação lateral
			local emAnimacaoLateral = (
				ultimaAnimacaoMovNome == "AndandoDireita"
				or ultimaAnimacaoMovNome == "AndandoEsquerda"
				or ultimaAnimacaoMovNome == "CorrendoDireita"
				or ultimaAnimacaoMovNome == "CorrendoEsquerda"
			)
			if emAnimacaoLateral then
				-- Preservar ciclo
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

				-- Toca Andando normal
				TocarAnimacaoMov(nomeAnimacao, velocidade)

				-- Aplica tempo preservado
				if animacaoAtualMov and tempoAtual > 0 then
					local tempoAlvo = tempoAtual
					local estaEmReverso = velocidadeAnimacaoAtual < 0
					local estavaEmReverso = velocidadeAnterior < 0
					if estaEmReverso ~= estavaEmReverso then
						tempoAlvo = animacaoAtualMov.Length - (tempoAtual % animacaoAtualMov.Length)
					end
					animacaoAtualMov.TimePosition = tempoAlvo % animacaoAtualMov.Length
					walkCycleState.time = 0 -- Consome
				end
				return
			end
		end
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

	-- Atualiza Base Idle se necessário (mudança de modo ou agachado)
	AtualizarBaseIdle()

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
		or estadoAtual.estadoAcao == "SoltandoPesado"
		or estadoAtual.estadoAcao == "AtaquePesado"
		or estadoAtual.estadoAcao == "Defendendo"
	then
		-- Não precisamos mais salvar runIntentDuringAction pois usamos isShiftHeld
		movementFlags.isRunning = false
		-- Atualiza velocidade para velocidade de combate (client-side)
		AtualizarVelocidadeLocal()
		-- Atualiza animação de movimento para refletir que não está mais correndo
		AtualizarAnimacaoMovimento()
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

	-- Se terminou uma ação de ataque (AtacandoLeve / CarregandoPesado / SoltandoPesado / AtaquePesado)
	-- e o jogador está segurando Shift, restaura corrida LOCALMENTE.
	-- NÃO envia para servidor - corrida é 100% client-side
	if
		(
			acaoAnterior == "AtacandoLeve"
			or acaoAnterior == "CarregandoPesado"
			or acaoAnterior == "SoltandoPesado"
			or acaoAnterior == "AtaquePesado"
		) and estadoAtual.estadoAcao == "Nenhuma"
	then
		if isShiftHeld then
			movementFlags.isRunning = true -- Restaura flag local
			-- Forçar localmente estado de corrida para responsividade
			estadoAtual.estadoMov = "Correndo"
			estadoAtual.correndo = true
		end
		-- Sempre atualiza velocidade ao sair de combate (seja correndo ou não)
		AtualizarVelocidadeLocal()
		AtualizarAnimacaoMovimento()
	end

	-- NÃO atualiza animação de movimento se está correndo no ar (evita flick)
	if movementFlags.isRunning and (movementFlags.isJumping or movementFlags.isFalling) then
		-- Apenas ajusta velocidade respeitando direção
		DefinirVelocidadeMovimento(TIMINGS.RunInAirSpeed)
		return
	end

	-- Atualiza animação de movimento
	AtualizarAnimacaoMovimento()

	-- Se saiu de Defendendo e o jogador ainda está segurando Shift, restaura corrida LOCALMENTE
	-- NÃO envia para servidor - corrida é 100% client-side
	if acaoAnterior == "Defendendo" and estadoAtual.estadoAcao == "Nenhuma" then
		if isShiftHeld then
			movementFlags.isRunning = true -- Restaura flag local
			-- Forçar localmente estado de corrida para responsividade
			estadoAtual.estadoMov = "Correndo"
			estadoAtual.correndo = true
		end
		-- Sempre atualiza velocidade ao sair de defesa (seja correndo ou não)
		AtualizarVelocidadeLocal()
		AtualizarAnimacaoMovimento()
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
		-- Verifica se está em ação de combate que impede correr
		local emCombate = (
			estadoAtual.estadoAcao == "AtacandoLeve"
			or estadoAtual.estadoAcao == "CarregandoPesado"
			or estadoAtual.estadoAcao == "SoltandoPesado"
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
		-- IMPORTANTE: Só muda para Caindo quando a animação de Pulando terminar completamente
		-- OU se isFalling foi setado diretamente (queda sem pulo)
		if movementFlags.isFalling then
			-- Está caindo (seja após pulo ou queda direta)
			if estadoAtual.estadoMov ~= "Caindo" then
				estadoAtual.estadoMov = "Caindo"
				AtualizarAnimacaoMovimento()
			end
		elseif movementFlags.isJumping then
			-- Ainda está na fase de pulo - mantém animação de Pulando
			-- A transição para Caindo será feita quando a animação terminar (OnJumpAnimacaoTerminou)
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
		or estadoAtual.estadoAcao == "SoltandoPesado"
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
		-- Sincroniza estado de movimento com servidor
		TentarAcao:FireServer("SincronizarMovimento", novoEstado)
	else
		-- Estado não mudou, apenas restaura velocidade normal se estava no ar
		if animacaoAtualMov then
			-- Não sobrescreve velocidade se estamos andando enquanto atacando/defendendo
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
end

-- ═══════════════════════════════════════════════════════════════════
-- DETECÇÃO DE QUEDA POR MATERIAL (AIR)
-- ═══════════════════════════════════════════════════════════════════

--- Verifica material do chão após animação de pulo (reservado para uso futuro)
local function _VerificarMaterialQueda()
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

	-- Atualiza flags de estados especiais
	movementFlags.isClimbing = (newState == Enum.HumanoidStateType.Climbing)
	movementFlags.isSwimming = (newState == Enum.HumanoidStateType.Swimming)

	-- Trata estado de pulo
	if newState == Enum.HumanoidStateType.Jumping then
		movementFlags.isJumping = true
		movementFlags.isFalling = false

		-- FIX: Se está correndo, SEMPRE mantém estado de corrida (remove dependência de animacaoAtualMov)
		if movementFlags.isRunning then
			estadoAtual.estadoMov = "Correndo"
			-- Garante que animação de corrida está tocando
			if animacaoAtualMov and animacaoAtualMov.IsPlaying then
				DefinirVelocidadeMovimento(TIMINGS.RunInAirSpeed)
			else
				-- Animação não está tocando, inicia ela
				AtualizarAnimacaoMovimento()
			end
			return -- SEMPRE retorna, nunca cai no AtualizarEstadoMovimento
		end
		-- A transição para Caindo será controlada pelo callback OnJumpAnimacaoTerminou
		-- quando a animação de Pulando terminar completamente
	end

	-- Trata estado de queda (Freefall)
	if newState == Enum.HumanoidStateType.Freefall then
		-- Se está aguardando a animação de pulo terminar, ignora completamente
		-- O callback OnJumpAnimacaoTerminou cuidará da transição quando a animação terminar
		if jumpAnimState.aguardandoTermino then
			-- Não faz nada - mantém isJumping = true, isFalling = false
			-- Não chama AtualizarEstadoMovimento
			return
		end

		-- Queda direta (sem pulo ou após animação de pulo terminar)
		movementFlags.isJumping = false
		movementFlags.isFalling = true

		-- FIX: Se está correndo no ar, mantém estado Correndo e retorna
		if movementFlags.isRunning then
			estadoAtual.estadoMov = "Correndo"
			if animacaoAtualMov and animacaoAtualMov.IsPlaying then
				DefinirVelocidadeMovimento(TIMINGS.RunInAirSpeed)
			end
			return
		end
	end

	-- Se aterrissou (Running, Landed, GettingUp), reseta flags de ar
	if
		newState == Enum.HumanoidStateType.Running
		or newState == Enum.HumanoidStateType.Landed
		or newState == Enum.HumanoidStateType.RunningNoPhysics
		or newState == Enum.HumanoidStateType.GettingUp
	then
		-- FIX: Aterrissagem definitiva.
		-- Removemos a verificação de FloorMaterial ~= Air aqui pois gera race condition
		-- onde o evento Landed dispara mas o Material ainda não atualizou (flick de estado).
		-- Se o Humanoid diz que está Running/Landed, confiamos no estado físico.

		movementFlags.isJumping = false
		movementFlags.isFalling = false

		-- Limpa estado da animação de pulo (pode ter aterrissado antes de terminar)
		LimparJumpAnimState()

		-- Se está correndo, mantém Correndo e restaura velocidade normal
		if movementFlags.isRunning then
			estadoAtual.estadoMov = "Correndo"
			if animacaoAtualMov then
				-- Só restaura velocidade completa se não estiver em combate (para não sobrescrever 0.4)
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
			-- Sincroniza com servidor sem mudar para Parado
			-- NÃO envia Correr para servidor - corrida é 100% client-side
			TentarAcao:FireServer("SincronizarMovimento", "Correndo")
			return -- Não chama AtualizarEstadoMovimento
		end

		-- Envia ação de aterrissar para o servidor
		TentarAcao:FireServer("Aterrissar")
	end

	-- Atualiza movimento imediatamente (só se não retornou antes)
	AtualizarEstadoMovimento()
end

-- Conecta listener de StateChanged
humanoid.StateChanged:Connect(OnStateChanged)

-- ═══════════════════════════════��═══════════════════════════════════
-- INPUT LOCAL - LEFTSHIFT PARA CORRIDA
-- ═══════════════════════════════════════════════════════════════════

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.LeftShift then
		movementFlags.isRunning = true
		isShiftHeld = true
		estadoAtual.correndo = true -- Sync para StatusLocal
		AtualizarVelocidadeLocal() -- Atualiza velocidade imediatamente (client-side)
		AtualizarEstadoMovimento()
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		movementFlags.isRunning = false
		isShiftHeld = false
		estadoAtual.correndo = false -- Sync para StatusLocal
		AtualizarVelocidadeLocal() -- Atualiza velocidade imediatamente (client-side)
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

	-- Verifica continuamente se precisa atualizar animação lateral
	-- Isso garante transições suaves quando o input muda durante o movimento
	if (estadoAtual.estadoMov == "Andando" or estadoAtual.estadoMov == "Correndo") and not estadoAtual.agachado then
		local tipoLateral, velocidadeLateral = CalcularMovimentoLateral()
		local emAnimacaoLateral = (
			ultimaAnimacaoMovNome == "AndandoDireita"
			or ultimaAnimacaoMovNome == "AndandoEsquerda"
			or ultimaAnimacaoMovNome == "CorrendoDireita"
			or ultimaAnimacaoMovNome == "CorrendoEsquerda"
		)

		if tipoLateral ~= "Nenhum" then
			-- Verifica se precisa trocar de animação lateral (ex: Direita -> Esquerda)
			if emAnimacaoLateral and ultimaAnimacaoMovNome ~= tipoLateral then
				AtualizarAnimacaoMovimento()
				return
			elseif emAnimacaoLateral then
				-- Mesma animação lateral, apenas atualiza velocidade alvo
				velocidadeAnimacaoAlvo = velocidadeLateral * ObterMultiplicadorVelocidadeAnimacao()
				direcaoAtual = velocidadeLateral > 0 and 1 or -1
			elseif not emAnimacaoLateral then
				AtualizarAnimacaoMovimento()
				return
			end
		elseif emAnimacaoLateral then
			AtualizarAnimacaoMovimento()
			return
		end
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
	local todasAnimacoes = Modulo_Configuracoes.ObterTodasAnimacoes()
	local total = #todasAnimacoes
	local carregadas = 0

	DebugPrint(string.format("[ControladorEstado] Pré-carregando %d animações...", total))

	for _, animId in ipairs(todasAnimacoes) do
		-- Carrega a animação no cache
		local track = ObterAnimacao(animId)
		if track then
			carregadas = carregadas + 1
		end
	end

	DebugPrint(string.format("[ControladorEstado] %d/%d animações pré-carregadas!", carregadas, total))
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
	animacaoBaseIdle = nil
	idBaseIdleAtual = nil

	-- Limpa estado de combo
	LimparConexoesMarkers()
	comboState.animacaoAtiva = nil
	comboState.janelaAtiva = false
	comboState.indiceAtual = 0
	comboState.continuarCombo = false
	comboState.pendingConsume = false
	comboState.token = 0

	-- Limpa estado de equipar/desequipar e remove acessório ao respawnar
	LimparConexoesMarkersEquip()
	if equipAnimState.conexaoTermino then
		equipAnimState.conexaoTermino:Disconnect()
		equipAnimState.conexaoTermino = nil
	end
	if equipAnimState.conexaoMonitor then
		equipAnimState.conexaoMonitor:Disconnect()
		equipAnimState.conexaoMonitor = nil
	end
	-- O acessório clonado será destruído junto com o character antigo
	-- Apenas resetamos as referências
	equipAnimState.animacao = nil
	equipAnimState.direcao = 0
	equipAnimState.modoAlvo = nil
	equipAnimState.acessorioClonado = nil
	equipAnimState.acessorioJaClonado = false

	-- Reseta flags
	movementFlags = {
		isRunning = false,
		isJumping = false,
		isFalling = false,
		isClimbing = false,
		isSwimming = false,
	}

	-- Limpa estado da animação de pulo
	LimparJumpAnimState()

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
	AtualizarBaseIdle()
	AtualizarAnimacaoMovimento()
end)

-- ═══════════════════════════════════════════════════════════════════
-- INICIALIZAÇÃO
-- ════════════════�������══════════════════════════════════════════════════

-- Pré-carrega todas as animações ao iniciar
PreCarregarAnimacoes()

-- Começa com Idle
AtualizarBaseIdle()
AtualizarAnimacaoMovimento()

DebugPrint("[ControladorEstado] Inicializado - movimento input-based + StateChanged")
