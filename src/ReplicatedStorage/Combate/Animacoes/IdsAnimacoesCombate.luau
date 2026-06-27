--!strict

--[[
    Script: IdsAnimacoesCombate.luau
    Caminho: src/ReplicatedStorage/Combate/Animacoes
    Responsabilidade: Centraliza os asset ids das animacoes de ataque, defesa e reacao usados pelo combate.
    Uso: ModuleScript; use require(caminho) para ler as tabelas e valores exportados.
    Nao faz: Nao executa comportamento sozinho; apenas fornece dados para outros scripts.
]]
local ActionModes = {
	Punhos = {
		tipo = "Combate",
		aplicaImpulso = true,
		aplicaKnockback = true,
		temCombo = true,
		configCombo = {
			velocidadeJanela = 0.3,
			divideDano = true,
		},
		animacoes = {

			Ataque = "rbxassetid://80851426931067", -- TESTE: 112281802538543", -- OFICIAL: 80851426931067",
			Defesa = "rbxassetid://106963330997976",
			DefesaQuebrada = "rbxassetid://103742519902549",
			Aparar = "rbxassetid://129329167930963",
			Aparado = "rbxassetid://140567046809161",

			Equipar = "rbxassetid://140710454719042",
			Desequipar = "rbxassetid://79693751210844",

			Idle = "rbxassetid://140496395460979", -- TESTE: 116110302448130", -- OFICIAL: 140496395460979",
			Andando = "rbxassetid://105404528392497",
			AndandoDireita = "rbxassetid://98995854513998",
			AndandoEsquerda = "rbxassetid://122813374537229",
			Correndo = "rbxassetid://84638257154650",
			CorrendoDireita = "rbxassetid://125396593531220",
			CorrendoEsquerda = "rbxassetid://87283295811902",

			Pulando = "rbxassetid://93655898591525", -- "rbxassetid://117966230491995",
			Caindo = "rbxassetid://110317645536592",
			Escalando = "rbxassetid://112833263522484",

			IdleAgachado = "rbxassetid://113336055232894",
			AndandoAgachado = "rbxassetid://110248727392186",

			RollFrente = "rbxassetid://110380195030160",
			RollTras = "rbxassetid://137774822058926",
			RollEsquerda = "rbxassetid://134473715541120",
			RollDireita = "rbxassetid://118967040484648",

			Stunado = "rbxassetid://119175260965936",

			DashTras = "rbxassetid://89889986391185",
			DashEsquerda = "rbxassetid://77549992713022",
			DashDireita = "rbxassetid://107316520923865",
		},
	},

	UmaMao = {
		tipo = "Combate",
		aplicaImpulso = true,
		aplicaKnockback = true,
		temCombo = true,
		configCombo = {
			velocidadeJanela = 0.3,
		},
		animacoes = {
			Idle = "rbxassetid://125678807327806",

			Ataque = "rbxassetid://138242317969760",
			Defesa = "rbxassetid://138088196754527",
			DefesaQuebrada = "rbxassetid://89152120854667",

			Aparado = "rbxassetid://134602112835194",
			Aparar = "rbxassetid://133339835837167",

			Equipar = "rbxassetid://73723335173069",
			Desequipar = "rbxassetid://106202687670633",

			Andando = "rbxassetid://94670431334990",
			AndandoDireita = "rbxassetid://124078628293368",
			AndandoEsquerda = "rbxassetid://130734863282142",

			IdleAgachado = "rbxassetid://138620494190683",
			AndandoAgachado = "rbxassetid://127158050424191",

			Correndo = "rbxassetid://70776871540661",
			CorrendoDireita = "rbxassetid://139536881251411",
			CorrendoEsquerda = "rbxassetid://109080276788972",

			Caindo = "rbxassetid://114581654373456",
			Escalando = "rbxassetid://116424715858047",

			RollFrente = "rbxassetid://133289254940850",
			RollTras = "rbxassetid://102891606646133",
			RollEsquerda = "rbxassetid://127498234485972",
			RollDireita = "rbxassetid://120023484068900",

			Stunado = "rbxassetid://133660024060305",

			DashTras = "rbxassetid://107632452205259",
			DashEsquerda = "rbxassetid://108531482425326",
			DashDireita = "rbxassetid://113598203992466",
		},
	},

	UmaMaoEscudo = {
		tipo = "Combate",
		aplicaImpulso = true,
		aplicaKnockback = true,
		temCombo = true,
		configCombo = {
			velocidadeJanela = 0.4,
		},
		animacoes = {

			Ataque = "rbxassetid://122280944254589",
			Defesa = "rbxassetid://127751906771957",
			DefesaQuebrada = "rbxassetid://94588265013910",
			Aparar = "rbxassetid://139881462472225",
			Aparado = "rbxassetid://94588265013910",

			Equipar = "rbxassetid://115099251307406",
			Desequipar = "rbxassetid://119300191293903",

			Idle = "rbxassetid://97506647521728",
			Andando = "rbxassetid://101405606853852",
			AndandoDireita = "rbxassetid://109982570649734",
			AndandoEsquerda = "rbxassetid://99089536362364",
			Correndo = "rbxassetid://105489781294318",

			Pulando = "rbxassetid://126513416555386",
			Caindo = "rbxassetid://120023331153028",
			Escalando = "rbxassetid://128601601033320",

			IdleAgachado = "rbxassetid://0000000000",
			AndandoAgachado = "rbxassetid://0000000000",

			RollFrente = "rbxassetid://0000000000",
			RollTras = "rbxassetid://0000000000",
			RollEsquerda = "rbxassetid://0000000000",
			RollDireita = "rbxassetid://0000000000",

			Stunado = "rbxassetid://111940476196229",

			DashTras = "rbxassetid://0000000000",
			DashEsquerda = "rbxassetid://0000000000",
			DashDireita = "rbxassetid://0000000000",
		},
	},

	Arco = {
		tipo = "Combate",
		aplicaImpulso = false,
		aplicaKnockback = true,
		temCombo = false,
		animacoes = {

			AtaqueDistancia = "rbxassetid://0000000000",

			Equipar = "rbxassetid://0000000000",
			Desequipar = "rbxassetid://0000000000",

			Idle = "rbxassetid://0000000000",
			Andando = "rbxassetid://0000000000",
			AndandoDireita = "rbxassetid://0000000000",
			AndandoEsquerda = "rbxassetid://0000000000",
			Correndo = "rbxassetid://0000000000",

			Pulando = "rbxassetid://0000000000",
			Caindo = "rbxassetid://0000000000",
			Escalando = "rbxassetid://0000000000",

			Stunado = "rbxassetid://0000000000",

			DashTras = "rbxassetid://0000000000",
			DashEsquerda = "rbxassetid://0000000000",
			DashDireita = "rbxassetid://0000000000",
		},
	},

	Picareta = {
		tipo = "Interacao",
		aplicaImpulso = false,
		aplicaKnockback = false,
		temCombo = false,
		animacoes = {

			Interagir = "rbxassetid://0000000000",

			Equipar = "rbxassetid://0000000000",
			Desequipar = "rbxassetid://0000000000",

			Idle = "rbxassetid://0000000000",
			Andando = "rbxassetid://0000000000",
			AndandoDireita = "rbxassetid://0000000000",
			AndandoEsquerda = "rbxassetid://0000000000",
			Correndo = "rbxassetid://0000000000",

			Pulando = "rbxassetid://0000000000",
			Caindo = "rbxassetid://0000000000",
			Escalando = "rbxassetid://0000000000",

			Stunado = "rbxassetid://0000000000",
		},
	},

	Martelo = {
		tipo = "Interacao",
		aplicaImpulso = false,
		aplicaKnockback = false,
		temCombo = false,
		animacoes = {

			Interagir = "rbxassetid://0000000000",

			Equipar = "rbxassetid://0000000000",
			Desequipar = "rbxassetid://0000000000",

			Idle = "rbxassetid://0000000000",
			Andando = "rbxassetid://0000000000",
			AndandoDireita = "rbxassetid://0000000000",
			AndandoEsquerda = "rbxassetid://0000000000",
			Correndo = "rbxassetid://0000000000",

			Pulando = "rbxassetid://0000000000",
			Caindo = "rbxassetid://0000000000",
			Escalando = "rbxassetid://0000000000",

			Stunado = "rbxassetid://0000000000",
		},
	},

	UmaMaoDupla = {
		tipo = "Combate",
		aplicaImpulso = true,
		aplicaKnockback = true,
		temCombo = true,
		configCombo = {
			velocidadeJanela = 0.35,
			divideDano = true,
		},
		animacoes = {

			Ataque = "rbxassetid://122280944254589",
			Defesa = "rbxassetid://127751906771957",
			DefesaQuebrada = "rbxassetid://94588265013910",
			Aparar = "rbxassetid://139881462472225",
			Aparado = "rbxassetid://94588265013910",

			Equipar = "rbxassetid://115099251307406",
			Desequipar = "rbxassetid://119300191293903",

			Idle = "rbxassetid://97506647521728",
			Andando = "rbxassetid://101405606853852",
			AndandoDireita = "rbxassetid://109982570649734",
			AndandoEsquerda = "rbxassetid://99089536362364",
			Correndo = "rbxassetid://105489781294318",

			Pulando = "rbxassetid://126513416555386",
			Caindo = "rbxassetid://120023331153028",
			Escalando = "rbxassetid://128601601033320",

			Stunado = "rbxassetid://111940476196229",

			DashTras = "rbxassetid://0000000000",
			DashEsquerda = "rbxassetid://0000000000",
			DashDireita = "rbxassetid://0000000000",
		},
	},

	DuasMaos = {
		tipo = "Combate",
		aplicaImpulso = true,
		aplicaKnockback = true,
		temCombo = true,
		configCombo = {
			velocidadeJanela = 0.5,
		},
		animacoes = {

			Ataque = "rbxassetid://0000000000",
			Defesa = "rbxassetid://0000000000",
			DefesaQuebrada = "rbxassetid://0000000000",
			Aparar = "rbxassetid://0000000000",
			Aparado = "rbxassetid://0000000000",

			Equipar = "rbxassetid://0000000000",
			Desequipar = "rbxassetid://0000000000",

			Idle = "rbxassetid://0000000000",
			Andando = "rbxassetid://0000000000",
			AndandoDireita = "rbxassetid://0000000000",
			AndandoEsquerda = "rbxassetid://0000000000",
			Correndo = "rbxassetid://0000000000",

			Pulando = "rbxassetid://0000000000",
			Caindo = "rbxassetid://0000000000",
			Escalando = "rbxassetid://0000000000",

			Stunado = "rbxassetid://0000000000",

			DashTras = "rbxassetid://0000000000",
			DashEsquerda = "rbxassetid://0000000000",
			DashDireita = "rbxassetid://0000000000",
		},
	},

	PunhosEscudo = {
		tipo = "Combate",
		aplicaImpulso = true,
		aplicaKnockback = true,
		temCombo = true,
		configCombo = {
			velocidadeJanela = 0.4,
		},
		animacoes = {

			Ataque = "rbxassetid://0000000000",
			Defesa = "rbxassetid://0000000000",
			DefesaQuebrada = "rbxassetid://0000000000",
			Aparar = "rbxassetid://0000000000",
			Aparado = "rbxassetid://0000000000",

			Equipar = "rbxassetid://0000000000",
			Desequipar = "rbxassetid://0000000000",

			Idle = "rbxassetid://0000000000",
			Andando = "rbxassetid://0000000000",
			AndandoDireita = "rbxassetid://0000000000",
			AndandoEsquerda = "rbxassetid://0000000000",
			Correndo = "rbxassetid://0000000000",

			Pulando = "rbxassetid://0000000000",
			Caindo = "rbxassetid://0000000000",
			Escalando = "rbxassetid://0000000000",

			Stunado = "rbxassetid://0000000000",

			DashTras = "rbxassetid://0000000000",
			DashEsquerda = "rbxassetid://0000000000",
			DashDireita = "rbxassetid://0000000000",
		},
	},
}

return ActionModes
