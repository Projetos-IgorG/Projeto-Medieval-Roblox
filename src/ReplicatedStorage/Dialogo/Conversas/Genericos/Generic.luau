--[[
	Módulo de Diálogo: Genérico (Generic)
	Contém a árvore de falas e escolhas para NPCs sem profissão específica ou "NPCs de Fundo".
]]
local DialogoGenerico = {}

DialogoGenerico.Dialogos = {

	Inicio = {
		-- Fala inicial para NPCs que o jogador ainda não interagiu muito
		{
			IdFala = "SaudacaoPadrao",
			FalaNPC = "Olá, viajante! Belo dia para estar na vila, não acha?",
			Requisitos = {},
			Escolhas = {
				{
					TextoMencionado = "Realmente, o dia está bonito.",
					LevaParaId = "ConversaVila",
				},
				{
					TextoMencionado = "O que há de novo por aqui?",
					LevaParaId = "Novidades",
				},
				{
					TextoMencionado = "Posso te perguntar algo específico?",
					LevaParaId = "PermissaoChatIA",
					RequerCanChatAI = true,
				},
				{
					TextoMencionado = "Com licença, preciso ir.",
					LevaParaId = "Despedida",
				},
			},
		},
	},

	Ramificacoes = {
		["ConversaVila"] = {
			FalaNPC = "Pois é! Nada como o ar fresco do campo e a tranquilidade de nossa vila. Sinta-se em casa.",
			Escolhas = {
				{
					TextoMencionado = "Obrigado, até mais.",
					LevaParaId = "Despedida",
				},
			},
		},
		["Novidades"] = {
			FalaNPC = "Ah, as coisas por aqui são bem calmas. O ferreiro Leonard está sempre ocupado na forja, e os guardas estão sempre alertas. Fora isso, apenas o dia a dia de sempre.",
			Escolhas = {
				{
					TextoMencionado = "Entendo. Vou dar uma volta.",
					LevaParaId = "Despedida",
				},
			},
		},
		["PermissaoChatIA"] = {
			FalaNPC = "Se estiver ao alcance de meu entendimento, podes perguntar.",
			Escolhas = {
				{
					Tipo = "AIChatInput",
					PlaceholderText = "Escreva tua pergunta...",
					RetornarParaId = "AposRespostaIA",
				},
				{
					TextoMencionado = "Pensando bem, deixemos isso para depois.",
					LevaParaId = "Despedida",
				},
			},
		},
		["AposRespostaIA"] = {
			FalaNPC = "Se ainda tiver algo a dizer, fala sem receio.",
			Escolhas = {
				{
					TextoMencionado = "Tenho outra pergunta específica.",
					LevaParaId = "PermissaoChatIA",
					RequerCanChatAI = true,
				},
				{
					TextoMencionado = "Agradeço. Agora vou seguir meu caminho.",
					LevaParaId = "Despedida",
				},
			},
		},
		["Despedida"] = {
			FalaNPC = "Vá com cuidado, forasteiro.",
			FimDeDialogo = true,
		},
	},
}

return DialogoGenerico
