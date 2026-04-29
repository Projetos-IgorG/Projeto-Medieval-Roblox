--[[
    Script: Leonard.luau
    Caminho: src/ReplicatedStorage/Dialogo/Conversas/Unicos
    Responsabilidade: Define a conversa unica do NPC Leonard.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao concede recompensas nem altera estado do jogador; isso fica nos servicos do servidor.
]]
local DialogoGuarda = {}

DialogoGuarda.Dialogos = {

	Inicio = {
		{
			IdFala = "Apresentacao",
			FalaNPC = "Alto lá! Quem é você e o que faz na cidade?",
			Requisitos = {},

			IgnorarSe = { { Tipo = "Tag", Valor = "ConheceuGuarda" } },
			Escolhas = {
				{
					TextoMencionado = "Sou um viajante.",
					LevaParaId = "Acolhimento",
					AcaoServidor = { Acao = "DarTag", Valor = "ConheceuGuarda" },
				},
				{
					TextoMencionado = "Não te interessa.",
					LevaParaId = "Hostil",
					AcaoServidor = { Acao = "DarTag", Valor = "ConheceuGuarda" },
				},
			},
		},
		{
			IdFala = "BoasVindasFrequente",
			FalaNPC = "Ah, você de novo! Mantenha a espada embainhada e não teremos problemas.",
			Requisitos = { { Tipo = "Tag", Valor = "ConheceuGuarda" } },
			Escolhas = {
				{
					TextoMencionado = "Tudo tranquilo pela cidade?",
					LevaParaId = "Informacoes",
				},
				{
					TextoMencionado = "Preciso ir.",
					LevaParaId = "Despedida",
				},
			},
		},
	},

	Ramificacoes = {
		["Acolhimento"] = {
			FalaNPC = "Muito bem, viajante. Bem-vindo. Procure o Ferreiro se precisar de equipamentos.",
			Escolhas = {
				{
					TextoMencionado = "Obrigado.",
					LevaParaId = "Despedida",
				},
			},
		},
		["Hostil"] = {
			FalaNPC = "Cuidado com o tom, forasteiro. Não quebre as leis.",
			Escolhas = {
				{
					TextoMencionado = "[Sair]",
					LevaParaId = "Despedida",
				},
			},
		},
		["Informacoes"] = {
			FalaNPC = "A cidade está segura, mas há rumores de lobos nas florestas ao sul.",
			Escolhas = {
				{
					TextoMencionado = "Lobos? Boa caçada. Até mais.",
					LevaParaId = "Despedida",
				},
			},
		},
		["Despedida"] = {
			FalaNPC = "Que os deuses te protejam.",
			FimDeDialogo = true,
		},
	},
}

return DialogoGuarda
