--!strict

--[[
    Script: Especies.luau
    Caminho: src/ReplicatedStorage/Entidades
    Responsabilidade: Define quais atributos e perfil de movimento cada especie de entidade possui (Humano, Galinha, Ovelha, Vaca).
    Uso: ModuleScript; require para obter defaults usados ao instanciar entidades.
    Nao faz: Nao executa logica viva; apenas descreve dados.
    Funcoes principais: Existe, Obter, Listar
]]

local Atributos = require(script.Parent:WaitForChild("Atributos"))

export type PerfilMovimento = {
	andar: number,
	correr: number,
	pulo: number,
}

export type DefinicaoEspecie = {
	id: string,
	nome: string,
	atributos: { string },
	-- overrides opcionais por atributo: { Vida = { padrao = 80, max = 80 } }
	overrides: { [string]: { padrao: number?, min: number?, max: number?, deltaPorSegundo: number? } }?,
	movimento: PerfilMovimento,
	temCombate: boolean,
}

local Especies = {}

Especies.Catalogo = {
	Humano = {
		id = "Humano",
		nome = "Humano",
		atributos = { "Vida", "Energia", "Fome", "Sede", "Higiene", "Idade", "Temperatura" },
		overrides = nil,
		movimento = { andar = 12, correr = 20, pulo = 7.2 },
		temCombate = true,
	} :: DefinicaoEspecie,

	Galinha = {
		id = "Galinha",
		nome = "Galinha",
		atributos = { "Vida" },
		overrides = {
			Vida = { padrao = 20, max = 20 },
		},
		movimento = { andar = 4, correr = 7, pulo = 4 },
		temCombate = false,
	} :: DefinicaoEspecie,

	Ovelha = {
		id = "Ovelha",
		nome = "Ovelha",
		atributos = { "Vida", "Fome", "Sede" },
		overrides = {
			Vida = { padrao = 60, max = 60 },
		},
		movimento = { andar = 6, correr = 10, pulo = 5 },
		temCombate = false,
	} :: DefinicaoEspecie,

	Vaca = {
		id = "Vaca",
		nome = "Vaca",
		atributos = { "Vida", "Fome", "Sede" },
		overrides = {
			Vida = { padrao = 120, max = 120 },
		},
		movimento = { andar = 5, correr = 8, pulo = 4 },
		temCombate = false,
	} :: DefinicaoEspecie,
}

-- Sanity-check em desenvolvimento: garante que todo atributo referenciado existe.
do
	for nomeEspecie, especie in Especies.Catalogo do
		for _, idAtributo in especie.atributos do
			if not Atributos.Existe(idAtributo) then
				warn(string.format(
					"[Especies] Especie '%s' referencia atributo desconhecido '%s'.",
					nomeEspecie, idAtributo
				))
			end
		end
	end
end

function Especies.Existe(id: string): boolean
	return Especies.Catalogo[id] ~= nil
end

function Especies.Obter(id: string): DefinicaoEspecie?
	return Especies.Catalogo[id]
end

function Especies.Listar(): { DefinicaoEspecie }
	local lista: { DefinicaoEspecie } = {}
	for _, v in Especies.Catalogo do
		table.insert(lista, v)
	end
	return lista
end

return Especies
