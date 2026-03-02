--[[
	Módulo de Diálogo de Exemplo: Guarda
	Contém a árvore de falas e escolhas do NPC Guarda, totalmente estruturada através de dicionários.
]]
local DialogoGuarda = {}

-- Chaves principais usadas pelas referências no script
DialogoGuarda.Dialogos = {

	-- Falas iniciais dependendo do estado global ou lembranças (Requisitos)
	Inicio = {
		{
			IdFala = "Apresentacao",
			FalaNPC = "Alto lá! Quem é você e o que faz na cidade?",
			Requisitos = {}, -- Sem requisitos, é o fallback caso não caia nos outros
			-- Se o jogador tiver essa tag, essa fala será ignorada (pulada) na triagem
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
			Requisitos = { { Tipo = "Tag", Valor = "ConheceuGuarda" } }, -- Só diz isso se já o conheceu
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

	-- Ramificações de conversas
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
