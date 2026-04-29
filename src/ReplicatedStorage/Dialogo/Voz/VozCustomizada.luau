--[[
    Script: VozCustomizada.luau
    Caminho: src/ReplicatedStorage/Dialogo/Voz
    Responsabilidade: Reproduz vozes customizadas usando assets de audio configurados.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao roda sozinho nem cria fluxo de jogo por conta propria; depende dos scripts que importam este modulo.
    Funcoes principais: Iniciar, IniciarLoop, Parar, SortearElemento, SortearPontoDeInicio, CriarSound
]]
local VozCustom = {}

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modulos = ReplicatedStorage
local VozConfig = require(Modulos:WaitForChild("Dialogo"):WaitForChild("Voz"):WaitForChild("ConfigVoz"))

local function SortearElemento(tabela)
	return tabela[math.random(1, #tabela)]
end

export type Handle = {
	IniciarLoop: (self: Handle) -> (),
	Parar: (self: Handle) -> (),
}

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
	handle._ultimoPonto = -1

	handle._pitch = SortearElemento(VozConfig.CustomVoicePitchOptions)
	handle._emFadeOut = false

	local function SortearPontoDeInicio(): number
		local pontos = VozConfig.CustomVoicePontosDeInicio
		local ultimoPonto = handle._ultimoPonto

		local pontoMax = 0
		for _, p in ipairs(pontos) do
			if p > pontoMax then
				pontoMax = p
			end
		end
		local metade = pontoMax / 2

		local ultimoNaSegundaMetade = (ultimoPonto >= metade)

		local candidatos = {}
		for _, p in ipairs(pontos) do
			if p ~= ultimoPonto then
				local naSegundaMetade = (p >= metade)

				if ultimoPonto < 0 or naSegundaMetade ~= ultimoNaSegundaMetade then
					table.insert(candidatos, p)
				end
			end
		end

		if #candidatos == 0 then
			for _, p in ipairs(pontos) do
				if p ~= ultimoPonto then
					table.insert(candidatos, p)
				end
			end
		end

		if #candidatos == 0 then
			candidatos = pontos
		end

		local escolhido = SortearElemento(candidatos)
		handle._ultimoPonto = escolhido
		return escolhido
	end

	local function CriarSound(pontoInicio: number): Sound
		local sound = handle._sound

		if not sound then
			sound = Instance.new("Sound")
			sound.Name = "DialogoMurmur"
			sound.SoundId = cfg.AudioId
			sound.Looped = false
			sound.Parent = head
			handle._sound = sound
		end

		sound.PlaybackSpeed = handle._pitch
		sound.Volume = 0
		sound.TimePosition = pontoInicio

		return sound
	end

	local function FadeIn(sound: Sound)
		local tweenInfo = TweenInfo.new(handle._fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tween = TweenService:Create(sound, tweenInfo, { Volume = handle._volumeAlvo })
		tween:Play()
	end

	local function FadeOut(sound: Sound): Tween
		local tweenInfo = TweenInfo.new(handle._fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local tween = TweenService:Create(sound, tweenInfo, { Volume = 0 })
		tween:Play()
		return tween
	end

	local function IniciarMonitorDeLoop()

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

			if not sound.IsPlaying and handle._ativo then

				local novoPonto = SortearPontoDeInicio()
				sound.TimePosition = novoPonto
				sound.Volume = 0
				handle._emFadeOut = false
				sound:Play()
				FadeIn(sound)
			end
		end)
	end

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

	function handle:Parar()
		if not self._ativo then
			return
		end
		self._ativo = false

		if self._conexaoMonitor then
			self._conexaoMonitor:Disconnect()
			self._conexaoMonitor = nil
		end

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
