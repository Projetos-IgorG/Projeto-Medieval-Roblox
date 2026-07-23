--[[
Script: Equipment.luau
Caminho: src/ReplicatedStorage/Dados/Itens/CatalogoItens/Equipment
Responsabilidade: Catalogo dos itens do tipo Equipment - vestiveis (dados FIXOS).
Uso: ModuleScript filho; carregado automaticamente pelo CatalogoItens pai.
]]

return {
	["peitoral_ferro"] = {
		-- 1) Padrao
		Nome = "Peitoral de Ferro",
		Tipo = "Equipment",
		Subtipo = "Roupa",
		Peso = 8,
		ValorBase = 90,
		MaxQuantidade = 99,
		Arrastavel = false,
		Modelo = "PeitoralFerro",

		-- 2) So deste tipo (Equipment)
		Slot = "Torso",
		StatBase = 10,
		DurabilidadeMax = 200,
		MaterialBase = "Lingote de Ferro",
		QualidadeNumBase = 15,
	},

	["calca_la"] = {
		-- 1) Padrao
		Nome = "Calça de Lã",
		Tipo = "Equipment",
		Subtipo = "Roupa",
		Peso = 1.0,
		ValorBase = 20,
		MaxQuantidade = 99,
		Arrastavel = false,
		Modelo = "calca_la",

		-- 2) So deste tipo (Equipment)
		Slot = "Legs",
		StatBase = 2,
		DurabilidadeMax = 100,
		MaterialBase = "Lã",
		QualidadeNumBase = 10,
	},

	["casaco_la"] = {
		-- 1) Padrao
		Nome = "Casaco de Lã",
		Tipo = "Equipment",
		Subtipo = "Roupa",
		Peso = 1.0,
		ValorBase = 25,
		MaxQuantidade = 99,
		Arrastavel = false,
		Modelo = "casaco_la",

		-- 2) So deste tipo (Equipment)
		Slot = "Torso",
		StatBase = 2,
		DurabilidadeMax = 100,
		MaterialBase = "Lã",
		QualidadeNumBase = 10,
	},
}