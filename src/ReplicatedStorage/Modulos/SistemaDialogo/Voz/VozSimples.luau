--[[
	VozSimples — Sistema legado de voz: toca um som de "tick" a cada N letras.
	Extraído do DialogoClient para modularidade.
]]

local VozSimples = {}

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modulos = ReplicatedStorage:WaitForChild("Modulos")
local VozConfig = require(Modulos:WaitForChild("SistemaDialogo"):WaitForChild("Voz"):WaitForChild("VozConfig"))

-- ==========================================
-- Handle (instância por frase)
-- ==========================================

export type Handle = {
	TocarTick: (self: Handle) -> (),
	Parar: (self: Handle) -> (),
	ObterVelocidade: (self: Handle) -> number,
	ObterFrequenciaSom: (self: Handle) -> number,
}

--- Cria um handle de voz simples para uma frase.
--- @param head — Part "Head" do NPC (onde o som será criado)
--- @param tipoVoz — Tipo de voz do NPC (ex: "NeutralMale", "StrongFemale")
function VozSimples.Iniciar(head: BasePart, tipoVoz: string): Handle
	local chaveSimples = VozConfig.ResolverSimpleVoice(tipoVoz)
	local cfg = VozConfig.SimpleVoiceConfigs[chaveSimples]

	local handle = {} :: Handle
	handle._ativo = true
	handle._head = head
	handle._pitch = cfg.Pitch
	handle._velocidade = cfg.Velocidade
	handle._frequenciaSom = cfg.FrequenciaSom
	handle._soundId = VozConfig.SimpleVoiceTickSoundId

	function handle:TocarTick()
		if not self._ativo or not self._head then
			return
		end

		-- Variação aleatória do pitch (entre -0.05 e +0.05)
		local variacaoPitch = (math.random() * 0.1) - 0.05

		local sound = Instance.new("Sound")
		sound.Name = "DialogoTick"
		sound.SoundId = self._soundId
		sound.Volume = 0.1
		sound.Pitch = self._pitch + variacaoPitch
		sound.Parent = self._head
		sound:Play()

		Debris:AddItem(sound, 2)
	end

	function handle:Parar()
		self._ativo = false
	end

	function handle:ObterVelocidade(): number
		return self._velocidade
	end

	function handle:ObterFrequenciaSom(): number
		return self._frequenciaSom
	end

	return handle
end

return VozSimples
