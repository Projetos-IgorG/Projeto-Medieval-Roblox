--!strict

--[[
    Script: AnimacaoParkour.luau
    Caminho: src/ReplicatedStorage/Jogador/Parkour/Animacoes
    Responsabilidade: Carrega e controla animacoes usadas pelas acoes de parkour.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao roda sozinho nem cria fluxo de jogo por conta propria; depende dos scripts que importam este modulo.
    Funcoes principais: Inicializar, TocarIdle, TocarAcao, TocarAcaoPausadaNoMarker, ConfirmarAcaoPausada, CancelarAcaoPausada
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modulos = ReplicatedStorage
local AnimacoesGerais = require(Modulos:WaitForChild("Jogador"):WaitForChild("Animacoes"):WaitForChild("IdsAnimacoesGerais"))

type Callback = (() -> ())?
type PreAcaoState = {
	Token: number,
	Track: AnimationTrack,
	MarkerName: string,
	CongeladoNoMarker: boolean,
	Confirmado: boolean,
	EventoConfirmadoExecutado: boolean,
	OnConfirmEvento: Callback,
	OnConfirmCompleto: Callback,
}
type ParkourModo = {
	animacoes: { [string]: string },
	eventos: { [string]: string }?,
	configAnimacao: {
		FadeInAcao: number,
		FadeOutAcao: number,
		FadeInIdle: number,
		FadeOutIdle: number,
		VelocidadePadrao: number,
	}?,
}

local AnimacaoParkour = {}

local parkourModo = (AnimacoesGerais :: any).Parkour :: ParkourModo
local configAnim = parkourModo and parkourModo.configAnimacao or {
	FadeInAcao = 0.08,
	FadeOutAcao = 0.12,
	FadeInIdle = 0.04,
	FadeOutIdle = 0.18,
	VelocidadePadrao = 1.0,
}

local currentCharacter: Model? = nil
local currentAnimator: Animator? = nil
local trackCache: { [string]: AnimationTrack } = {}
local idleAtual: string? = nil
local idleTrackAtual: AnimationTrack? = nil
local acaoTrackAtual: AnimationTrack? = nil
local conexoesAcao: { RBXScriptConnection } = {}
local tokenAcao = 0
local proximoBraco = "Direita"
local preAcaoAtual: PreAcaoState? = nil
local speedMultiplier: number = 1.0

local function obterPrioridade(nomeAnimacao: string, looped: boolean): Enum.AnimationPriority
	if looped or nomeAnimacao == "IdleSuporte" or nomeAnimacao == "IdleSuspenso" then
		return Enum.AnimationPriority.Action
	end

	return Enum.AnimationPriority.Action3
end

local function obterFadeOutIdleParaAcao(nomeAnimacao: string): number
	if nomeAnimacao == "SubirSaltoSuporte" or nomeAnimacao == "SubirSaltoSuspenso" then
		return 0.08
	end

	return configAnim.FadeOutIdle
end

local function isLateralAnimation(nome: string): boolean
	return string.find(nome, "Direita", 1, true) ~= nil
		or string.find(nome, "Esquerda", 1, true) ~= nil
end

local function obterFadeInAcaoPara(nomeAnimacao: string): number
	if nomeAnimacao == "SubirSaltoSuporte" or nomeAnimacao == "SubirSaltoSuspenso" then
		return 0.05
	end
	return configAnim.FadeInAcao
end

local function obterVelocidadeTrack(nomeAnimacao: string, looped: boolean): number
	if looped then
		return configAnim.VelocidadePadrao
	end

	if nomeAnimacao == "Descer" then
		return 1.3
	end

	return configAnim.VelocidadePadrao * speedMultiplier
end

local function limparConexoesAcao()
	for _, conexao in ipairs(conexoesAcao) do
		if conexao and conexao.Connected then
			conexao:Disconnect()
		end
	end
	table.clear(conexoesAcao)
end

local function pararTrack(track: AnimationTrack?, fadeOut: number)
	if not track then
		return
	end

	if track.IsPlaying then
		track:Stop(fadeOut)
	end
end

local function obterTrack(nomeAnimacao: string): AnimationTrack?
	if not currentAnimator or not parkourModo or not parkourModo.animacoes then
		return nil
	end

	if trackCache[nomeAnimacao] then
		return trackCache[nomeAnimacao]
	end

	local animId = parkourModo.animacoes[nomeAnimacao]
	if not animId or animId == "" then
		warn("[AnimacaoParkour] ID ausente para animacao:", nomeAnimacao)
		return nil
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = animId

	local ok, track = pcall(function()
		return (currentAnimator :: Animator):LoadAnimation(animation)
	end)

	animation:Destroy()

	if not ok or not track then
		warn("[AnimacaoParkour] Falha ao carregar animacao:", nomeAnimacao, animId)
		return nil
	end

	trackCache[nomeAnimacao] = track
	return track
end

local function tocarTrack(track: AnimationTrack, nomeAnimacao: string, fadeIn: number, looped: boolean, velMultiplicador: number?)
	track.Looped = looped
	track.Priority = obterPrioridade(nomeAnimacao, looped)
	track:Play(fadeIn)
	track:AdjustSpeed(obterVelocidadeTrack(nomeAnimacao, looped) * (velMultiplicador or 1.0))
end

function AnimacaoParkour.Inicializar(character: Model): boolean
	if currentCharacter == character and currentAnimator then
		return true
	end

	AnimacaoParkour.Destruir()

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then
		return false
	end

	local animator = humanoid:FindFirstChild("Animator")
	if not animator or not animator:IsA("Animator") then
		return false
	end

	currentCharacter = character
	currentAnimator = animator

	if parkourModo and parkourModo.animacoes then
		for nome, _ in pairs(parkourModo.animacoes) do
			obterTrack(nome)
		end
	end

	return true
end

function AnimacaoParkour.TocarIdle(idleMode: string, fadeTime: number?)
	if not currentAnimator then
		return
	end

	local nomeIdle = if idleMode == "IdleSuspenso" then "IdleSuspenso" else "IdleSuporte"
	if idleAtual == nomeIdle and idleTrackAtual and idleTrackAtual.IsPlaying then
		return
	end

	local track = obterTrack(nomeIdle)
	if not track then
		return
	end

	if idleTrackAtual and idleTrackAtual ~= track then
		pararTrack(idleTrackAtual, configAnim.FadeOutIdle)
	end

	idleAtual = nomeIdle
	idleTrackAtual = track
	tocarTrack(track, nomeIdle, fadeTime or configAnim.FadeInIdle, true)
end

function AnimacaoParkour.TocarAcao(nomeAnimacao: string, onEvento: Callback, onCompleto: Callback, ignorarMarker: boolean?, reverso: boolean?, velMultiplicador: number?): boolean
	if not currentAnimator then
		return false
	end

	local track = obterTrack(nomeAnimacao)
	if not track then
		return false
	end

	local isLateral = isLateralAnimation(nomeAnimacao)
	local skipPlay = isLateral and acaoTrackAtual == track and track.IsPlaying

	tokenAcao += 1
	local tokenLocal = tokenAcao
	local eventoExecutado = false
	preAcaoAtual = nil

	limparConexoesAcao()

	if acaoTrackAtual and acaoTrackAtual ~= track then
		pararTrack(acaoTrackAtual, configAnim.FadeOutAcao)
	end

	if idleTrackAtual then
		pararTrack(idleTrackAtual, obterFadeOutIdleParaAcao(nomeAnimacao))
		idleTrackAtual = nil
		idleAtual = nil
	end

	acaoTrackAtual = track

	local function executarEventoUmaVez()
		if eventoExecutado then
			return
		end
		eventoExecutado = true
		if onEvento then
			onEvento()
		end
	end

	local markerName = (not ignorarMarker) and (parkourModo.eventos and parkourModo.eventos[nomeAnimacao] or nil) or nil
	if markerName then
		local markerConn = track:GetMarkerReachedSignal(markerName):Connect(function()
			if tokenLocal ~= tokenAcao then
				return
			end
			executarEventoUmaVez()
		end)
		table.insert(conexoesAcao, markerConn)
	end

	if reverso then
		local speed = obterVelocidadeTrack(nomeAnimacao, false) * (velMultiplicador or 1.0)
		if not skipPlay then
			track.Looped = false
			track.Priority = obterPrioridade(nomeAnimacao, false)
			track:Play(obterFadeInAcaoPara(nomeAnimacao))

			local length = track.Length
			if length == 0 or length == nil then
				length = 1.0
			end
			track.TimePosition = length
			track:AdjustSpeed(-speed)
		end

		local length = track.Length
		if length == 0 or length == nil then
			length = 1.0
		end
		local duracao = math.max(length / speed, 0.06)

		task.delay(duracao, function()
			if tokenLocal ~= tokenAcao then
				return
			end

			limparConexoesAcao()
			if acaoTrackAtual == track then
				pararTrack(track, configAnim.FadeOutAcao)
				acaoTrackAtual = nil
			end

			if markerName and not eventoExecutado then
				executarEventoUmaVez()
			end

			if onCompleto then
				onCompleto()
			end
		end)
	else
		local stoppedConn = track.Stopped:Connect(function()
			if tokenLocal ~= tokenAcao then
				return
			end

			if markerName and not eventoExecutado then
				executarEventoUmaVez()
			end

			limparConexoesAcao()
			if acaoTrackAtual == track then
				acaoTrackAtual = nil
			end

			if onCompleto then
				onCompleto()
			end
		end)
		table.insert(conexoesAcao, stoppedConn)

		if not skipPlay then
			tocarTrack(track, nomeAnimacao, obterFadeInAcaoPara(nomeAnimacao), false, velMultiplicador)
		end
	end

	if not markerName then
		executarEventoUmaVez()
	end

	return true
end

function AnimacaoParkour.TocarAcaoPausadaNoMarker(nomeAnimacao: string, onCongelado: Callback): boolean
	if not currentAnimator then
		return false
	end

	local track = obterTrack(nomeAnimacao)
	if not track then
		return false
	end

	local markerName = parkourModo.eventos and parkourModo.eventos[nomeAnimacao] or nil
	if not markerName then
		warn("[AnimacaoParkour] Marker ausente para pre-acao:", nomeAnimacao)
		return false
	end

	tokenAcao += 1
	local tokenLocal = tokenAcao
	preAcaoAtual = {
		Token = tokenLocal,
		Track = track,
		MarkerName = markerName,
		CongeladoNoMarker = false,
		Confirmado = false,
		EventoConfirmadoExecutado = false,
		OnConfirmEvento = nil,
		OnConfirmCompleto = nil,
	}

	limparConexoesAcao()

	if acaoTrackAtual and acaoTrackAtual ~= track then
		pararTrack(acaoTrackAtual, configAnim.FadeOutAcao)
	end

	if idleTrackAtual then
		pararTrack(idleTrackAtual, obterFadeOutIdleParaAcao(nomeAnimacao))
		idleTrackAtual = nil
		idleAtual = nil
	end

	acaoTrackAtual = track

	local function onMarkerReached()
		if tokenLocal ~= tokenAcao then
			return
		end

		if not preAcaoAtual or preAcaoAtual.Token ~= tokenLocal then
			return
		end

		if preAcaoAtual.Confirmado then
			if not preAcaoAtual.EventoConfirmadoExecutado then
				preAcaoAtual.EventoConfirmadoExecutado = true
				if preAcaoAtual.OnConfirmEvento then
					preAcaoAtual.OnConfirmEvento()
				end
			end

			if preAcaoAtual.CongeladoNoMarker then
				track:AdjustSpeed(configAnim.VelocidadePadrao * speedMultiplier)
			end

			return
		end

		if preAcaoAtual.CongeladoNoMarker then
			return
		end

		preAcaoAtual.CongeladoNoMarker = true
		track:AdjustSpeed(0)

		if onCongelado then
			onCongelado()
		end
	end

	local markerConn = track:GetMarkerReachedSignal(markerName):Connect(onMarkerReached)
	table.insert(conexoesAcao, markerConn)

	if nomeAnimacao == "SubirSaltoSuporte" or nomeAnimacao == "SubirSaltoSuspenso" then
		local legacyMarker = if markerName == "SubirSaltoParkour" then "SubirParkour" else "SubirSaltoParkour"
		local legacyConn = track:GetMarkerReachedSignal(legacyMarker):Connect(onMarkerReached)
		table.insert(conexoesAcao, legacyConn)
	end

	local stoppedConn = track.Stopped:Connect(function()
		if tokenLocal ~= tokenAcao then
			return
		end

		local preAcao = preAcaoAtual
		if preAcao and preAcao.Token == tokenLocal then
			preAcaoAtual = nil
		end

		limparConexoesAcao()
		if acaoTrackAtual == track then
			acaoTrackAtual = nil
		end

		if preAcao and preAcao.Confirmado and not preAcao.EventoConfirmadoExecutado and preAcao.OnConfirmEvento then
			preAcao.EventoConfirmadoExecutado = true
			preAcao.OnConfirmEvento()
		end

		if preAcao and preAcao.Confirmado and preAcao.OnConfirmCompleto then
			preAcao.OnConfirmCompleto()
		end
	end)
	table.insert(conexoesAcao, stoppedConn)

	tocarTrack(track, nomeAnimacao, obterFadeInAcaoPara(nomeAnimacao), false)
	return true
end

function AnimacaoParkour.ConfirmarAcaoPausada(onEvento: Callback, onCompleto: Callback): boolean
	if not preAcaoAtual then
		return false
	end

	if preAcaoAtual.Confirmado then
		return false
	end

	preAcaoAtual.Confirmado = true
	preAcaoAtual.OnConfirmEvento = onEvento
	preAcaoAtual.OnConfirmCompleto = onCompleto

	if preAcaoAtual.CongeladoNoMarker then
		if onEvento then
			onEvento()
		end
		preAcaoAtual.EventoConfirmadoExecutado = true
		preAcaoAtual.Track:AdjustSpeed(configAnim.VelocidadePadrao * speedMultiplier)
	end

	return true
end

function AnimacaoParkour.CancelarAcaoPausada(fadeTime: number?)
	if not preAcaoAtual then
		return false
	end

	local fade = fadeTime or configAnim.FadeOutAcao
	local track = preAcaoAtual.Track
	preAcaoAtual = nil

	limparConexoesAcao()
	pararTrack(track, fade)
	if acaoTrackAtual == track then
		acaoTrackAtual = nil
	end

	return true
end

function AnimacaoParkour.RecuarAcaoPausada(velocidadeAbs: number, onCompleto: Callback): boolean
	if not preAcaoAtual then
		return false
	end

	local preAcao = preAcaoAtual
	preAcaoAtual = nil
	limparConexoesAcao()

	local track = preAcao.Track
	local speed = math.max(math.abs(velocidadeAbs), 0.1)
	local duracao = math.max(track.TimePosition / speed, 0.06)

	if not track.IsPlaying then
		track:Play(0.03)
	end

	track:AdjustSpeed(-speed)

	task.delay(duracao, function()
		if acaoTrackAtual == track then
			pararTrack(track, 0.03)
			acaoTrackAtual = nil
		end

		if onCompleto then
			onCompleto()
		end
	end)

	return true
end

function AnimacaoParkour.EstaAcaoPausadaCongelada(): boolean
	return preAcaoAtual ~= nil and preAcaoAtual.CongeladoNoMarker and not preAcaoAtual.Confirmado
end

function AnimacaoParkour.PararTudo(fadeTime: number?)
	local fade = fadeTime or configAnim.FadeOutAcao
	tokenAcao += 1
	preAcaoAtual = nil
	limparConexoesAcao()
	pararTrack(acaoTrackAtual, fade)
	pararTrack(idleTrackAtual, configAnim.FadeOutIdle)
	acaoTrackAtual = nil
	idleTrackAtual = nil
	idleAtual = nil
end

function AnimacaoParkour.EncerrarAcaoAtual(fadeTime: number?)
	local fade = fadeTime or configAnim.FadeOutAcao
	tokenAcao += 1
	preAcaoAtual = nil
	limparConexoesAcao()
	pararTrack(acaoTrackAtual, fade)
	acaoTrackAtual = nil
end

function AnimacaoParkour.ObterAnimacaoSubir(idleMode: string?): string
	local sufixo = if idleMode == "IdleSuspenso" then "Suspenso" else "Suporte"
	local nome = if proximoBraco == "Direita"
		then "SubirDireita" .. sufixo
		else "SubirEsquerda" .. sufixo
	proximoBraco = if proximoBraco == "Direita" then "Esquerda" else "Direita"
	return nome
end

function AnimacaoParkour.ObterAnimacaoSubirSalto(idleMode: string?): string
	if idleMode == "IdleSuspenso" then
		return "SubirSaltoSuspenso"
	end

	return "SubirSaltoSuporte"
end

function AnimacaoParkour.ObterAnimacaoEscalar(idleMode: string?): string
	if idleMode == "IdleSuspenso" then
		return "EscalarSuspenso"
	end

	return "EscalarSuporte"
end

function AnimacaoParkour.ObterAnimacaoLateralSalto(direcao: string, idleMode: string?): string
	local sufixo = if idleMode == "IdleSuspenso" then "Suspenso" else "Suporte"
	if direcao == "Esquerda" then
		return "EsquerdaSalto" .. sufixo
	end

	return "DireitaSalto" .. sufixo
end

function AnimacaoParkour.SetSpeedMultiplier(multiplier: number)
	speedMultiplier = math.clamp(multiplier, 0.1, 5.0)
end

function AnimacaoParkour.ResetarBraco()
	proximoBraco = "Direita"
end

function AnimacaoParkour.Destruir()
	AnimacaoParkour.PararTudo(configAnim.FadeOutAcao)
	table.clear(trackCache)
	currentCharacter = nil
	currentAnimator = nil
	speedMultiplier = 1.0
end

return AnimacaoParkour
