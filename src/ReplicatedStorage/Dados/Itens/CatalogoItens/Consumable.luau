--[[
Script: Consumable.luau
Caminho: src/ReplicatedStorage/Dados/Itens/CatalogoItens/Consumable
Responsabilidade: Catalogo dos itens do tipo Consumable (dados FIXOS).
Uso: ModuleScript filho; carregado automaticamente pelo CatalogoItens pai.
]]

return {
	["pao"] = {
		-- 1) Padrao
		Nome = "Pao",
		Tipo = "Consumable",
		Peso = 0.3,
		ValorBase = 3,
		MaxQuantidade = 99,
		Arrastavel = false,
		Modelo = "Pao",

		-- 2) So deste tipo (Consumable)
		Efeito = "RestaurarFome",
		Potencia = 25,
	},
}