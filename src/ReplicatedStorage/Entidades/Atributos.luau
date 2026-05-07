--!strict

--[[
    Script: Atributos.luau
    Caminho: src/ReplicatedStorage/Entidades
    Responsabilidade: Catalogo central de atributos vitais utilizados por entidades vivas (Vida, Energia, Fome, Sede, Higiene, Idade, Temperatura).
    Uso: ModuleScript; require para obter defaults, limites e taxas de regen/dreno por segundo.
    Nao faz: Nao mantem estado nem aplica logica; apenas descreve atributos.
    Funcoes principais: Existe, Obter, Listar
]]

local Atributos = {}

export type DefinicaoAtributo = {
	id: string,
	nome: string,
	descricao: string,
	padrao: number,
	min: number,
	max: number,
	-- delta por segundo aplicado pelo gerenciador (positivo = aumenta, negativo = diminui)
	deltaPorSegundo: number,
	-- formatacao para UI: "porcentagem" mostra como X / max, "numero" mostra cru
	formato: string,
	cor: Color3,
}

local function def(t: DefinicaoAtributo): DefinicaoAtributo
	return t
end

Atributos.Catalogo = {
	Vida = def({
		id = "Vida",
		nome = "Vida",
		descricao = "Pontos de vida da entidade. Zera ao morrer.",
		padrao = 100,
		min = 0,
		max = 100,
		deltaPorSegundo = 0,
		formato = "porcentagem",
		cor = Color3.fromRGB(220, 70, 70),
	}),
	Energia = def({
		id = "Energia",
		nome = "Energia",
		descricao = "Stamina geral; consumida por correr/atacar e regenerada em repouso.",
		padrao = 100,
		min = 0,
		max = 100,
		deltaPorSegundo = 4,
		formato = "porcentagem",
		cor = Color3.fromRGB(240, 200, 60),
	}),
	Fome = def({
		id = "Fome",
		nome = "Fome",
		descricao = "100 = saciado, 0 = faminto. Diminui com o tempo.",
		padrao = 100,
		min = 0,
		max = 100,
		deltaPorSegundo = -0.05,
		formato = "porcentagem",
		cor = Color3.fromRGB(220, 140, 60),
	}),
	Sede = def({
		id = "Sede",
		nome = "Sede",
		descricao = "100 = hidratado, 0 = desidratado. Diminui mais rapido que fome.",
		padrao = 100,
		min = 0,
		max = 100,
		deltaPorSegundo = -0.08,
		formato = "porcentagem",
		cor = Color3.fromRGB(80, 170, 230),
	}),
	Higiene = def({
		id = "Higiene",
		nome = "Higiene",
		descricao = "Limpeza pessoal. 100 = limpo, 0 = imundo.",
		padrao = 100,
		min = 0,
		max = 100,
		deltaPorSegundo = -0.02,
		formato = "porcentagem",
		cor = Color3.fromRGB(160, 220, 200),
	}),
	Idade = def({
		id = "Idade",
		nome = "Idade",
		descricao = "Idade em anos. Avanca lentamente.",
		padrao = 18,
		min = 0,
		max = 120,
		deltaPorSegundo = 0,
		formato = "numero",
		cor = Color3.fromRGB(180, 160, 220),
	}),
	Temperatura = def({
		id = "Temperatura",
		nome = "Temperatura",
		descricao = "Temperatura corporal em graus Celsius.",
		padrao = 36.5,
		min = 25,
		max = 45,
		deltaPorSegundo = 0,
		formato = "numero",
		cor = Color3.fromRGB(255, 130, 100),
	}),
} :: { [string]: DefinicaoAtributo }

function Atributos.Existe(id: string): boolean
	return Atributos.Catalogo[id] ~= nil
end

function Atributos.Obter(id: string): DefinicaoAtributo?
	return Atributos.Catalogo[id]
end

function Atributos.Listar(): { DefinicaoAtributo }
	local lista: { DefinicaoAtributo } = {}
	for _, v: DefinicaoAtributo in Atributos.Catalogo do
		table.insert(lista, v)
	end
	return lista
end

return Atributos
