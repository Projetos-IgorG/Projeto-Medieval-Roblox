--[[
Script: Tool.luau
Caminho: src/ReplicatedStorage/Dados/Itens/CatalogoItens/Tool
Responsabilidade: Catalogo dos itens do tipo Tool - armas e ferramentas (dados FIXOS).
Uso: ModuleScript filho; carregado automaticamente pelo CatalogoItens pai.
]]

return {
	["picareta_ferro"] = {
		-- 1) Padrao
		Nome = "Picareta de Ferro",
		Tipo = "Tool",
		Subtipo = "Ferramenta",
		Peso = 2.8,
		ValorBase = 45,
		MaxQuantidade = 99,
		Arrastavel = false,
		Modelo = "PicaretaFerro",

		-- 2) So deste tipo (Tool)
		StatBase = 5,
		Dano = 5,
		Alcance = 4,
		DurabilidadeMax = 150,
		MaterialBase = "Lingote de Ferro",
		QualidadeNumBase = 10,
		ModoAnimacao = "Picareta",
	},

	["punhos"] = {
		-- 1) Padrao
		Nome = "Punhos",
		Tipo = "Tool",
		Subtipo = "Arma",
		Peso = 0.0,
		MaxQuantidade = 1,
		Arrastavel = false,
		Modelo = "Punhos",

		-- 2) So deste tipo (Tool)
		Dano = 12,
		Alcance = 5,
		ModoAnimacao = "Punhos",
	},

	["espada_ferro"] = {
		-- 1) Padrao
		Nome = "Espada de Ferro",
		Tipo = "Tool",
		Subtipo = "Arma",
		Peso = 1.0,
		ValorBase = 80,
		MaxQuantidade = 99,
		Arrastavel = false,
		Modelo = "EspadaFerro",

		-- 2) So deste tipo (Tool)
		StatBase = 12,
		Dano = 12,
		Alcance = 5,
		DurabilidadeMax = 200,
		MaterialBase = "Lingote de Ferro",
		QualidadeNumBase = 20,
		ModoAnimacao = "UmaMao",
	},

	["lampada1"] = {
		-- 1) Padrao
		Nome = "Lampada",
		Tipo = "Tool",
		Subtipo = "Ferramenta",
		Peso = 1,
		ValorBase = 80,
		MaxQuantidade = 99,
		Arrastavel = false,
		Modelo = "Lampada",

		-- 2) So deste tipo (Tool)
		MaterialBase = "Lingote de Ferro",
		ModoAnimacao = "UmaMao",
	},
}
