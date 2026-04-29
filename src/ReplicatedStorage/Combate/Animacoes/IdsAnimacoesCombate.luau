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
			velocidadeJanela = 0.4,
			divideDano = true,
		},
		animacoes = {

			AtaqueLeve = "rbxassetid://80851426931067",
			AtaquePesado = "rbxassetid://117244978564325",
			Defesa = "rbxassetid://106963330997976",
			DefesaQuebrada = "rbxassetid://103742519902549",
			Aparar = "rbxassetid://129329167930963",
			Aparado = "rbxassetid://140567046809161",

			Equipar = "rbxassetid://140710454719042",
			Desequipar = "rbxassetid://79693751210844",

			Idle = "rbxassetid://140496395460979",
			Andando = "rbxassetid://105404528392497",
			AndandoDireita = "rbxassetid://98995854513998",
			AndandoEsquerda = "rbxassetid://122813374537229",
			Correndo = "rbxassetid://84638257154650",
			CorrendoDireita = "rbxassetid://125396593531220",
			CorrendoEsquerda = "rbxassetid://87283295811902",

			Pulando = "rbxassetid://93655898591525",
			Caindo = "rbxassetid://110317645536592",
			Escalando = "rbxassetid://112833263522484",

			IdleAgachado = "rbxassetid://113336055232894",
			AndandoAgachado = "rbxassetid://110248727392186",

			DashFrente = "rbxassetid://110380195030160",
			DashTras = "rbxassetid://137774822058926",
			DashEsquerda = "rbxassetid://134473715541120",
			DashDireita = "rbxassetid://118967040484648",

			Stunado = "rbxassetid://119175260965936",
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

			AtaqueLeve = "rbxassetid://122280944254589",
			AtaquePesado = "rbxassetid://125243003105031",
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

			DashFrente = "rbxassetid://0000000000",
			DashTras = "rbxassetid://0000000000",
			DashEsquerda = "rbxassetid://0000000000",
			DashDireita = "rbxassetid://0000000000",

			Stunado = "rbxassetid://111940476196229",
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

	UmaMao = {
		tipo = "Combate",
		aplicaImpulso = true,
		aplicaKnockback = true,
		temCombo = true,
		configCombo = {
			velocidadeJanela = 0.4,
		},
		animacoes = {

			AtaqueLeve = "rbxassetid://122280944254589",
			AtaquePesado = "rbxassetid://125243003105031",
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

			AtaqueLeve = "rbxassetid://122280944254589",
			AtaquePesado = "rbxassetid://125243003105031",
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

			AtaqueLeve = "rbxassetid://0000000000",
			AtaquePesado = "rbxassetid://0000000000",
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

			AtaqueLeve = "rbxassetid://0000000000",
			AtaquePesado = "rbxassetid://0000000000",
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
		},
	},
}

return ActionModes
