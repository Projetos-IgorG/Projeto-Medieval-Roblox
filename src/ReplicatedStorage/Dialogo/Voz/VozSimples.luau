--[[
    Script: VozSimples.luau
    Caminho: src/ReplicatedStorage/Dialogo/Voz
    Responsabilidade: Fornece uma voz simples baseada em sons curtos para falas de NPC.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao roda sozinho nem cria fluxo de jogo por conta propria; depende dos scripts que importam este modulo.
    Funcoes principais: Iniciar, TocarTick, Parar, ObterVelocidade, ObterFrequenciaSom
]]
local VozSimples = {}

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modulos = ReplicatedStorage
local VozConfig = require(Modulos:WaitForChild("Dialogo"):WaitForChild("Voz"):WaitForChild("ConfigVoz"))

export type Handle = {
	TocarTick: (self: Handle) -> (),
	Parar: (self: Handle) -> (),
	ObterVelocidade: (self: Handle) -> number,
	ObterFrequenciaSom: (self: Handle) -> number,
}

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
