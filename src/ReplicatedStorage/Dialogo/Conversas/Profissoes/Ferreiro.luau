--[[
	Módulo de Diálogo: Ferreiro
	Contém a árvore de falas e escolhas do NPC Ferreiro.
	Requisitos progressivos: ConheceuGuarda → ConheceuFerreiro → ConheceuAmbos
]]
local DialogoFerreiro = {}

DialogoFerreiro.Dialogos = {

	Inicio = {
		-- Fala 3: Requer conhecer ambos (Guarda e Ferreiro)
		{
			IdFala = "VelhoAmigo",
			FalaNPC = "Ah, meu melhor cliente! Tenho uma encomenda especial para você. Venha ver isto.",
			Requisitos = {
				{ Tipo = "Tag", Valor = "ConheceuGuarda" },
				{ Tipo = "Tag", Valor = "ConheceuFerreiro" },
			},
			Escolhas = {
				{
					TextoMencionado = "O que você tem de novo?",
					LevaParaId = "EncomendaEspecial",
				},
				{
					TextoMencionado = "Talvez depois.",
					LevaParaId = "Despedida",
				},
			},
		},
		-- Fala 2: Requer conhecer o Guarda, mas NÃO o Ferreiro ainda
		{
			IdFala = "ConhecidoDoGuarda",
			FalaNPC = "O guarda me disse que um viajante novo estava na cidade. Deve ser você, não?",
			Requisitos = { { Tipo = "Tag", Valor = "ConheceuGuarda" } },
			IgnorarSe = { { Tipo = "Tag", Valor = "ConheceuFerreiro" } },
			Escolhas = {
				{
					TextoMencionado = "Sim, ele me indicou até aqui, Textos Textos Textos Textos Textos Textos Textos Textos Textos Textos Textos Textos.",
					LevaParaId = "BoasVindas",
					AcaoServidor = { Acao = "DarTag", Valor = "ConheceuFerreiro" },
				},
				{
					TextoMencionado = "Quem é você?",
					LevaParaId = "Apresentacao",
					AcaoServidor = { Acao = "DarTag", Valor = "ConheceuFerreiro" },
				},
			},
		},
		-- Fala 1: Fallback sem requisitos (não conhece o guarda)
		{
			IdFala = "Desconhecido",
			FalaNPC = "Hm? Não te conheço. Fale com o guarda primeiro, forasteiro. Ele define quem entra na forja.",
			Requisitos = {},
			IgnorarSe = { { Tipo = "Tag", Valor = "ConheceuGuarda" } },
			Escolhas = {
				{
					TextoMencionado = "Tudo bem, vou falar com ele.",
					LevaParaId = "Despedida",
				},
			},
		},
	},

	Ramificacoes = {
		["BoasVindas"] = {
			FalaNPC = "Muito bem! Sou o ferreiro desta cidade. Se precisar de uma espada afiada, sabe onde me encontrar.",
			Escolhas = {
				{
					TextoMencionado = "Obrigado, voltarei em breve.",
					LevaParaId = "Despedida",
				},
			},
		},
		["Apresentacao"] = {
			FalaNPC = "Sou o ferreiro da cidade. Forjo armas, armaduras e ferramentas. Se tiver grana, temos negócio.",
			Escolhas = {
				{
					TextoMencionado = "Interessante. Até mais.",
					LevaParaId = "Despedida",
				},
			},
		},
		["EncomendaEspecial"] = {
			FalaNPC = "Consegui um minério raro das montanhas. Com ele, posso forjar algo único. Mas vai custar caro...",
			Escolhas = {
				{
					TextoMencionado = "Quanto custa?",
					LevaParaId = "Preco",
				},
				{
					TextoMencionado = "Talvez outra hora.",
					LevaParaId = "Despedida",
				},
			},
		},
		["Preco"] = {
			FalaNPC = "Ainda estou calculando. Volte depois que eu tiver os números.",
			FimDeDialogo = true,
		},
		["Despedida"] = {
			FalaNPC = "Que as chamas da forja te guiem.",
			FimDeDialogo = true,
		},
	},
}

return DialogoFerreiro
