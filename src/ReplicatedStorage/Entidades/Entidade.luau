--!strict

--[[
    Script: Entidade.luau
    Caminho: src/ReplicatedStorage/Entidades
	Responsabilidade: Classe base orientada a objetos para qualquer ser vivo do jogo (Player, humanos e animais como galinhas, ovelhas e vacas).
    Uso: ModuleScript; require e use Entidade.novo(model, especieId).
    Nao faz: Nao gerencia o tick global nem cria personagens; apenas representa uma entidade.
    Funcoes principais: novo, obterAtributo, definirAtributo, modificarAtributo, listarAtributos, tick, destruir
]]

local Atributos = require(script.Parent:WaitForChild("Atributos"))
local Especies = require(script.Parent:WaitForChild("Especies"))

type DefinicaoAtributo = Atributos.DefinicaoAtributo
type DefinicaoEspecie = Especies.DefinicaoEspecie

-- Prefixo de Attributes no Model (replica automaticamente para clientes).
local PREFIXO = "Ent_"
local CHAVE_ESPECIE = "Ent_Especie"

local Entidade = {}
Entidade.__index = Entidade

export type EstadoAtributo = {
	id: string,
	nome: string,
	valor: number,
	min: number,
	max: number,
	deltaPorSegundo: number,
	formato: string,
	cor: Color3,
}

export type EntidadeImpl = {
	modelo: Model,
	especie: DefinicaoEspecie,
	-- definicao efetiva por atributo (apos overrides da especie)
	_defs: { [string]: DefinicaoAtributo },
	_destruido: boolean,
	_conexoes: { RBXScriptConnection },

	obterAtributo: (self: EntidadeImpl, id: string) -> number?,
	definirAtributo: (self: EntidadeImpl, id: string, valor: number) -> (),
	modificarAtributo: (self: EntidadeImpl, id: string, delta: number) -> (),
	listarAtributos: (self: EntidadeImpl) -> { EstadoAtributo },
	temAtributo: (self: EntidadeImpl, id: string) -> boolean,
	tick: (self: EntidadeImpl, dt: number) -> (),
	estaVivo: (self: EntidadeImpl) -> boolean,
	destruir: (self: EntidadeImpl) -> (),
}

local function clonarComOverride(base: DefinicaoAtributo, override: any?): DefinicaoAtributo
	if not override then
		return base
	end
	return {
		id = base.id,
		nome = base.nome,
		descricao = base.descricao,
		padrao = override.padrao or base.padrao,
		min = override.min or base.min,
		max = override.max or base.max,
		deltaPorSegundo = if override.deltaPorSegundo ~= nil then override.deltaPorSegundo else base.deltaPorSegundo,
		formato = base.formato,
		cor = base.cor,
	}
end

local function chaveAtributo(id: string): string
	return PREFIXO .. id
end

function Entidade.novo(modelo: Model, especieId: string): EntidadeImpl
	assert(typeof(modelo) == "Instance" and modelo:IsA("Model"), "Entidade.novo espera um Model valido")
	local especie = Especies.Obter(especieId)
	assert(especie, string.format("Especie '%s' nao registrada em Especies.Catalogo", tostring(especieId)))

	local self = setmetatable({}, Entidade) :: any

	self.modelo = modelo
	self.especie = especie
	self._defs = {}
	self._destruido = false
	self._conexoes = {}

	-- Marca a especie no model para o cliente saber.
	modelo:SetAttribute(CHAVE_ESPECIE, especie.id)

	-- Resolve definicoes aplicando overrides.
	local overrides = especie.overrides
	for _, idAtributo in especie.atributos do
		local base = Atributos.Obter(idAtributo)
		if not base then
			warn("[Entidade] Atributo desconhecido para " .. especie.id .. ": " .. idAtributo)
			continue
		end
		local def = clonarComOverride(base, overrides and overrides[idAtributo])
		self._defs[idAtributo] = def

		-- Se o model ainda nao tem o atributo, inicializa com o padrao.
		if modelo:GetAttribute(chaveAtributo(idAtributo)) == nil then
			modelo:SetAttribute(chaveAtributo(idAtributo), def.padrao)
		end
	end

	return self :: EntidadeImpl
end

function Entidade:temAtributo(id: string): boolean
	return (self :: any)._defs[id] ~= nil
end

function Entidade:obterAtributo(id: string): number?
	local def = (self :: any)._defs[id]
	if not def then
		return nil
	end
	local valor = (self :: any).modelo:GetAttribute(chaveAtributo(id))
	if typeof(valor) == "number" then
		return valor
	end
	return def.padrao
end

function Entidade:definirAtributo(id: string, valor: number)
	local def = (self :: any)._defs[id]
	if not def then
		return
	end
	if typeof(valor) ~= "number" or valor ~= valor then -- nan
		return
	end
	local clamped = math.clamp(valor, def.min, def.max)
	;(self :: any).modelo:SetAttribute(chaveAtributo(id), clamped)
end

function Entidade:modificarAtributo(id: string, delta: number)
	local atual = self:obterAtributo(id)
	if atual == nil then
		return
	end
	self:definirAtributo(id, atual + delta)
end

function Entidade:listarAtributos(): { EstadoAtributo }
	local lista: { EstadoAtributo } = {}
	local modelo = (self :: any).modelo
	for id, def in (self :: any)._defs do
		local valor = modelo:GetAttribute(chaveAtributo(id))
		if typeof(valor) ~= "number" then
			valor = def.padrao
		end
		table.insert(lista, {
			id = id,
			nome = def.nome,
			valor = valor,
			min = def.min,
			max = def.max,
			deltaPorSegundo = def.deltaPorSegundo,
			formato = def.formato,
			cor = def.cor,
		})
	end
	-- ordena por nome para UI estavel
	table.sort(lista, function(a, b)
		return a.nome < b.nome
	end)
	return lista
end

function Entidade:tick(dt: number)
	if (self :: any)._destruido then
		return
	end
	-- Aplica delta por segundo de cada atributo.
	for id, def in (self :: any)._defs do
		if def.deltaPorSegundo ~= 0 then
			self:modificarAtributo(id, def.deltaPorSegundo * dt)
		end
	end
end

function Entidade:estaVivo(): boolean
	if (self :: any)._destruido then
		return false
	end
	if self:temAtributo("Vida") then
		local vida = self:obterAtributo("Vida")
		if vida and vida <= 0 then
			return false
		end
	end
	return true
end

function Entidade:destruir()
	if (self :: any)._destruido then
		return
	end
	(self :: any)._destruido = true
	for _, conn in (self :: any)._conexoes do
		if conn.Connected then
			conn:Disconnect()
		end
	end
	table.clear((self :: any)._conexoes)
	-- Mantemos os attributes no model: se ele for destruido, somem juntos.
end

-- Helpers expostos para uso externo (sem precisar conhecer o prefixo).
Entidade.PREFIXO_ATRIBUTO = PREFIXO
Entidade.CHAVE_ESPECIE = CHAVE_ESPECIE
Entidade.chaveAtributo = chaveAtributo

return Entidade
