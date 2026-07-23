--[[
Script: Material.luau
Caminho: src/ReplicatedStorage/Dados/Itens/CatalogoItens/Material
Responsabilidade: Catalogo dos itens do tipo Material (dados FIXOS).
Uso: ModuleScript filho; carregado automaticamente pelo CatalogoItens pai.
]]

return {
	["minerio_ferro"] = {
		-- 1) Padrao
		Nome = "Minerio de Ferro",
		Tipo = "Material",
		Peso = 1.2,
		ValorBase = 6,
		MaxQuantidade = 99,
		Arrastavel = false,
		Modelo = "MinerioFerro",

		-- 2) So deste tipo: (nenhum)
	},
}