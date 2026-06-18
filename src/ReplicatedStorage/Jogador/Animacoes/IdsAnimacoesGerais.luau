--!strict

--[[
    Script: IdsAnimacoesGerais.luau
    Caminho: src/ReplicatedStorage/Jogador/Animacoes
    Responsabilidade: Centraliza asset ids de animacoes gerais do jogador.
    Uso: ModuleScript; use require(caminho) para ler as tabelas e valores exportados.
    Nao faz: Nao executa comportamento sozinho; apenas fornece dados para outros scripts.
]]
local GeneralAnimations = {
	Base = {
		tipo = "Nenhum",
		aplicaImpulso = false,
		aplicaKnockback = false,
		temCombo = false,
		animacoes = {

			Idle = "rbxassetid://82165471407920",
			Andando = "rbxassetid://104395502422213",
			AndandoDireita = "rbxassetid://109982570649734",
			AndandoEsquerda = "rbxassetid://99089536362364",
			Correndo = "rbxassetid://84638257154650",
			CorrendoDireita = "rbxassetid://125396593531220",
			CorrendoEsquerda = "rbxassetid://87283295811902",

			Pulando = "rbxassetid://117966230491995",
			Caindo = "rbxassetid://139130630712682",
			Escalando = "rbxassetid://114123577974317",

			IdleAgachado = "rbxassetid://129640837531159",
			AndandoAgachado = "rbxassetid://87797732262383",

			RollFrente = "rbxassetid://77731344105069",
			RollTras = "rbxassetid://116512808764487",
			RollEsquerda = "rbxassetid://80802499324784",
			RollDireita = "rbxassetid://114879502782228",

			DashTras = "rbxassetid://0000000000",
			DashEsquerda = "rbxassetid://0000000000",
			DashDireita = "rbxassetid://0000000000",

			Stunado = "rbxassetid://104947799689111",

			InteragindoAlto = "rbxassetid://139881462472225",
			InteragindoBaixo = "rbxassetid://111940476196229",
			InteragindoChao = "rbxassetid://105611406813057",
			InteragindoMedio = "rbxassetid://111460345852039",
		},
	},

	Parkour = {
		tipo = "Parkour",
		aplicaImpulso = false,
		aplicaKnockback = false,
		temCombo = false,
		animacoes = {

			IdleSuporte = "rbxassetid://101405606853852",
			IdleSuspenso = "rbxassetid://97506647521728",

			SubirDireitaSuporte = "rbxassetid://104976161284084",
			SubirEsquerdaSuporte = "rbxassetid://139049880951103",

			SubirDireitaSuspenso = "rbxassetid://95244325439627",
			SubirEsquerdaSuspenso = "rbxassetid://120023331153028",

			SubirSaltoSuporte = "rbxassetid://94588265013910",
			SubirSaltoSuspenso = "rbxassetid://128601601033320",

			Descer = "rbxassetid://104309277302018",
			PuloTras = "rbxassetid://122280944254589",

			DireitaSuporte = "rbxassetid://85351814023097",
			EsquerdaSuporte = "rbxassetid://119300191293903",

			DireitaSuspenso = "rbxassetid://125243003105031",
			EsquerdaSuspenso = "rbxassetid://115099251307406",

			DireitaSaltoSuporte = "rbxassetid://128153530690566",
			EsquerdaSaltoSuporte = "rbxassetid://84480325767002",

			DireitaSaltoSuspenso = "rbxassetid://80372639586330",
			EsquerdaSaltoSuspenso = "rbxassetid://95842068830831",

			EscalarSuporte = "rbxassetid://127751906771957",
			EscalarSuspenso = "rbxassetid://126513416555386",

			VaultMedio = "rbxassetid://139979993022198",
			VaultBaixo = "rbxassetid://105489781294318",
		},
		eventos = {
			SubirDireitaSuporte = "SubirParkour",
			SubirEsquerdaSuporte = "SubirParkour",
			SubirDireitaSuspenso = "SubirParkour",
			SubirEsquerdaSuspenso = "SubirParkour",
			SubirSaltoSuporte = "SubirSaltoParkour",
			SubirSaltoSuspenso = "SubirSaltoParkour",
			DireitaSuporte = "DireitaParkour",
			EsquerdaSuporte = "EsquerdaParkour",
			DireitaSuspenso = "DireitaParkour",
			EsquerdaSuspenso = "EsquerdaParkour",
			DireitaSaltoSuporte = "DireitaParkourSalto",
			EsquerdaSaltoSuporte = "EsquerdaParkourSalto",
			DireitaSaltoSuspenso = "DireitaParkourSalto",
			EsquerdaSaltoSuspenso = "EsquerdaParkourSalto",
		},
		configAnimacao = {
			FadeInAcao = 0.08,
			FadeOutAcao = 0.12,
			FadeInIdle = 0.08,
			FadeOutIdle = 0.18,
			VelocidadePadrao = 1.0,
		},
	},
}

return GeneralAnimations
