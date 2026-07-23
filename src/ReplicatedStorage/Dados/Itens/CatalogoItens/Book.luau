--[[
Script: Book.luau
Caminho: src/ReplicatedStorage/Dados/Itens/CatalogoItens/Book
Responsabilidade: Catalogo dos itens do tipo Book (dados FIXOS).
Uso: ModuleScript filho; carregado automaticamente pelo CatalogoItens pai.
]]

return {
	["manual_espada_aco"] = {
		-- 1) Padrao
		Nome = "Manual: Espada de Aco",
		Tipo = "Book",
		Peso = 0.5,
		ValorBase = 60,
		MaxQuantidade = 99,
		Arrastavel = false,
		Modelo = "Livro",

		-- 2) So deste tipo (Book)
		Efeito = "EnsinarReceita",
		Alvo = "espada_aco",
	},
}