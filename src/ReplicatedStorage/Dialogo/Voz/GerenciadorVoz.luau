--[[
    Script: GerenciadorVoz.luau
    Caminho: src/ReplicatedStorage/Dialogo/Voz
    Responsabilidade: Orquestra reproducao de voz, fallback e limpeza de audio dos dialogos.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao roda sozinho nem cria fluxo de jogo por conta propria; depende dos scripts que importam este modulo.
    Funcoes principais: IniciarVoz, TocarTick, IniciarLoop, Parar, ObterVelocidade, ObterFrequenciaSom
]]
local GerenciadorVoz = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PastaVoz = ReplicatedStorage:WaitForChild("Dialogo"):WaitForChild("Voz")

local VozConfig = require(PastaVoz:WaitForChild("ConfigVoz"))
local VozSimples = require(PastaVoz:WaitForChild("VozSimples"))
local VozCustom = require(PastaVoz:WaitForChild("VozCustomizada"))

export type HandleVoz = {
	TocarTick: (self: HandleVoz) -> (),
	IniciarLoop: (self: HandleVoz) -> (),
	Parar: (self: HandleVoz) -> (),
	ObterVelocidade: (self: HandleVoz) -> number,
	ObterFrequenciaSom: (self: HandleVoz) -> number,
}

function GerenciadorVoz.IniciarVoz(head: BasePart, tipoVoz: string): HandleVoz
	local handleSimples = nil
	local handleCustom = nil

	if VozConfig.SimpleVoice then
		handleSimples = VozSimples.Iniciar(head, tipoVoz)
	end

	if VozConfig.CustomVoice then
		handleCustom = VozCustom.Iniciar(head, tipoVoz)
	end

	local handle = {} :: HandleVoz

	function handle:TocarTick()
		if handleSimples then
			handleSimples:TocarTick()
		end
	end

	function handle:IniciarLoop()
		if handleCustom then
			handleCustom:IniciarLoop()
		end
	end

	function handle:Parar()
		if handleSimples then
			handleSimples:Parar()
			handleSimples = nil
		end
		if handleCustom then
			handleCustom:Parar()
			handleCustom = nil
		end
	end

	function handle:ObterVelocidade(): number
		if handleSimples then
			return handleSimples:ObterVelocidade()
		end

		return 0.04
	end

	function handle:ObterFrequenciaSom(): number
		if handleSimples then
			return handleSimples:ObterFrequenciaSom()
		end

		return 2
	end

	return handle
end

return GerenciadorVoz
