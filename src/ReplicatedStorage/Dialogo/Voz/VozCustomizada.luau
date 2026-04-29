--[[
	VozCustom ââ‚¬â€ Sistema novo de voz: toca um áudio de murmúrio em loop
	enquanto o typewriter está ativo.
	
	Características:
	  ââ‚¬Â¢ Sorteia um ponto de início aleatório e um pitch por frase
	  ââ‚¬Â¢ Quando o áudio termina, sorteia OUTRO ponto de início para o próximo loop
	  ââ‚¬Â¢ Fade-in ao iniciar, fade-out ao chegar perto do final (crossfade suave)
	  ââ‚¬Â¢ Volume e AudioId configuráveis por tipo de voz
]]

local VozCustom = {}

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modulos = ReplicatedStorage
local VozConfig = require(Modulos:WaitForChild("Dialogo"):WaitForChild("Voz"):WaitForChild("ConfigVoz"))

-- ==========================================
-- Utilitários
-- ==========================================

--- Sorteia um elemento aleatório de uma tabela.
local function SortearElemento(tabela)
	return tabela[math.random(1, #tabela)]
end

-- ==========================================
-- Handle (instância por frase)
-- ==========================================

export type Handle = {
	IniciarLoop: (self: Handle) -> (),
	Parar: (self: Handle) -> (),
}

--- Cria um handle de voz custom para uma frase.
--- @param head ââ‚¬â€ Part "Head" do NPC
--- @param tipoVoz ââ‚¬â€ Tipo de voz do NPC (ex: "NeutralMale")
function VozCustom.Iniciar(head: BasePart, tipoVoz: string): Handle?
	local cfg = VozConfig.CustomVoiceConfigs[tipoVoz]
	if not cfg then
		warn("[VozCustom] Tipo de voz não encontrado no CustomVoiceConfigs: " .. tostring(tipoVoz))
		return nil
	end

	local handle = {} :: Handle
	handle._ativo = false
	handle._head = head
	handle._cfg = cfg
	handle._sound = nil :: Sound?
	handle._conexaoMonitor = nil
	handle._fadeDuration = VozConfig.CustomVoiceFadeDuration
	handle._volumeAlvo = cfg.Volume
	handle._ultimoPonto = -1 -- Å¡ltimo ponto usado (para evitar repetição)

	-- Sorteia pitch para esta frase inteira (muda a cada frase, não a cada loop)
	handle._pitch = SortearElemento(VozConfig.CustomVoicePitchOptions)
	handle._emFadeOut = false -- Evita disparar múltiplos fades no final

	-- ââ€â‚¬ââ€â‚¬ Métodos Internos ââ€â‚¬ââ€â‚¬

	--- Sorteia um ponto de início inteligente:
	--- 1) Nunca repete o ponto anterior
	--- 2) Se o anterior era na 2Ã‚Âª metade do áudio ââ€ â€™ sorteia da 1Ã‚Âª metade, e vice-versa
	local function SortearPontoDeInicio(): number
		local pontos = VozConfig.CustomVoicePontosDeInicio
		local ultimoPonto = handle._ultimoPonto

		-- Encontra o ponto máximo para calcular a "metade" do áudio
		local pontoMax = 0
		for _, p in ipairs(pontos) do
			if p > pontoMax then
				pontoMax = p
			end
		end
		local metade = pontoMax / 2

		-- Determina se o último ponto estava na 1Ã‚Âª ou 2Ã‚Âª metade
		local ultimoNaSegundaMetade = (ultimoPonto >= metade)

		-- Filtra candidatos: metade oposta + diferente do anterior
		local candidatos = {}
		for _, p in ipairs(pontos) do
			if p ~= ultimoPonto then
				local naSegundaMetade = (p >= metade)
				-- Se o último foi na 2Ã‚Âª metade, pega da 1Ã‚Âª, e vice-versa
				if ultimoPonto < 0 or naSegundaMetade ~= ultimoNaSegundaMetade then
					table.insert(candidatos, p)
				end
			end
		end

		-- Fallback: se não sobrou nenhum candidato (improvável), usa todos exceto o anterior
		if #candidatos == 0 then
			for _, p in ipairs(pontos) do
				if p ~= ultimoPonto then
					table.insert(candidatos, p)
				end
			end
		end

		-- Fallback final: se mesmo assim não tem (só 1 ponto na lista), usa qualquer um
		if #candidatos == 0 then
			candidatos = pontos
		end

		local escolhido = SortearElemento(candidatos)
		handle._ultimoPonto = escolhido
		return escolhido
	end

	--- Cria ou reconfigura o objeto Sound na Head.
	local function CriarSound(pontoInicio: number): Sound
		local sound = handle._sound

		if not sound then
			sound = Instance.new("Sound")
			sound.Name = "DialogoMurmur"
			sound.SoundId = cfg.AudioId
			sound.Looped = false -- Controle manual de loop
			sound.Parent = head
			handle._sound = sound
		end

		sound.PlaybackSpeed = handle._pitch
		sound.Volume = 0 -- Começa mudo para fade-in
		sound.TimePosition = pontoInicio

		return sound
	end

	--- Aplica fade-in suave até o volume alvo.
	local function FadeIn(sound: Sound)
		local tweenInfo = TweenInfo.new(handle._fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tween = TweenService:Create(sound, tweenInfo, { Volume = handle._volumeAlvo })
		tween:Play()
	end

	--- Aplica fade-out suave até 0.
	local function FadeOut(sound: Sound): Tween
		local tweenInfo = TweenInfo.new(handle._fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local tween = TweenService:Create(sound, tweenInfo, { Volume = 0 })
		tween:Play()
		return tween
	end

	--- Inicia o monitoramento de loop ââ‚¬â€ verifica a cada frame se precisa
	--- fazer crossfade para o próximo segmento.
	local function IniciarMonitorDeLoop()
		-- Limpa conexão anterior, se houver
		if handle._conexaoMonitor then
			handle._conexaoMonitor:Disconnect()
			handle._conexaoMonitor = nil
		end

		local sound = handle._sound
		if not sound then
			return
		end

		handle._conexaoMonitor = game:GetService("RunService").Heartbeat:Connect(function()
			if not handle._ativo or not sound or not sound.Parent then
				if handle._conexaoMonitor then
					handle._conexaoMonitor:Disconnect()
					handle._conexaoMonitor = nil
				end
				return
			end

			-- Quando o áudio está chegando perto do final,
			-- faz fade-out e resorteia ponto de início para o próximo loop
			local tempoRestante = sound.TimeLength - sound.TimePosition
			if
				tempoRestante > 0
				and tempoRestante <= handle._fadeDuration
				and sound.IsPlaying
				and not handle._emFadeOut
			then
				handle._emFadeOut = true
				FadeOut(sound)
			end

			-- Verifica se o áudio acabou (não está mais tocando e já estava ativo)
			if not sound.IsPlaying and handle._ativo then
				-- Sorteia novo ponto de início
				local novoPonto = SortearPontoDeInicio()
				sound.TimePosition = novoPonto
				sound.Volume = 0
				handle._emFadeOut = false -- Reset para o próximo fade-out
				sound:Play()
				FadeIn(sound)
			end
		end)
	end

	-- ââ€â‚¬ââ€â‚¬ Métodos Públicos ââ€â‚¬ââ€â‚¬

	--- Inicia o loop de murmúrio.
	function handle:IniciarLoop()
		if self._ativo then
			return
		end
		self._ativo = true

		local pontoInicial = SortearPontoDeInicio()
		local sound = CriarSound(pontoInicial)
		sound:Play()
		FadeIn(sound)

		IniciarMonitorDeLoop()
	end

	--- Para o murmúrio com fade-out suave e faz cleanup.
	function handle:Parar()
		if not self._ativo then
			return
		end
		self._ativo = false

		-- Desconecta o monitor
		if self._conexaoMonitor then
			self._conexaoMonitor:Disconnect()
			self._conexaoMonitor = nil
		end

		-- Fade-out e destruir
		if self._sound and self._sound.Parent then
			local tween = FadeOut(self._sound)
			local soundRef = self._sound
			tween.Completed:Connect(function()
				if soundRef and soundRef.Parent then
					soundRef:Stop()
					soundRef:Destroy()
				end
			end)
		end

		self._sound = nil
	end

	return handle
end

return VozCustom
