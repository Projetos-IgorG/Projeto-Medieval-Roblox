--[[
	GerenciadorVoz — Orquestrador do sistema de voz.
	
	Lê as flags SimpleVoice / CustomVoice de VozConfig e despacha
	para os módulos corretos. Retorna um handle unificado que
	o DialogoClient usa sem se preocupar com qual sistema está ativo.
]]

local GerenciadorVoz = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modulos = ReplicatedStorage:WaitForChild("Modulos")
local PastaVoz = Modulos:WaitForChild("SistemaDialogo"):WaitForChild("Voz")

local VozConfig = require(PastaVoz:WaitForChild("VozConfig"))
local VozSimples = require(PastaVoz:WaitForChild("VozSimples"))
local VozCustom = require(PastaVoz:WaitForChild("VozCustom"))

-- ==========================================
-- Handle Unificado
-- ==========================================

export type HandleVoz = {
	TocarTick: (self: HandleVoz) -> (),
	IniciarLoop: (self: HandleVoz) -> (),
	Parar: (self: HandleVoz) -> (),
	ObterVelocidade: (self: HandleVoz) -> number,
	ObterFrequenciaSom: (self: HandleVoz) -> number,
}

--- Cria um handle de voz unificado para uma frase.
--- @param head — Part "Head" do NPC
--- @param tipoVoz — Tipo de voz do NPC (ex: "NeutralMale", "StrongFemale")
function GerenciadorVoz.IniciarVoz(head: BasePart, tipoVoz: string): HandleVoz
	local handleSimples = nil
	local handleCustom = nil

	-- Inicializa os sistemas conforme as flags
	if VozConfig.SimpleVoice then
		handleSimples = VozSimples.Iniciar(head, tipoVoz)
	end

	if VozConfig.CustomVoice then
		handleCustom = VozCustom.Iniciar(head, tipoVoz)
	end

	-- Handle unificado
	local handle = {} :: HandleVoz

	--- Toca um tick de voz simples (chamado pelo typewriter a cada N letras).
	function handle:TocarTick()
		if handleSimples then
			handleSimples:TocarTick()
		end
	end

	--- Inicia o loop de murmúrio do CustomVoice.
	function handle:IniciarLoop()
		if handleCustom then
			handleCustom:IniciarLoop()
		end
	end

	--- Para todos os sistemas de voz ativos.
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

	--- Retorna a velocidade do typewriter (vem do SimpleVoice, ou padrão).
	function handle:ObterVelocidade(): number
		if handleSimples then
			return handleSimples:ObterVelocidade()
		end
		-- Fallback se só CustomVoice estiver ativo
		return 0.04
	end

	--- Retorna a frequência do som (vem do SimpleVoice, ou padrão).
	function handle:ObterFrequenciaSom(): number
		if handleSimples then
			return handleSimples:ObterFrequenciaSom()
		end
		-- Fallback se só CustomVoice estiver ativo
		return 2
	end

	return handle
end

return GerenciadorVoz
