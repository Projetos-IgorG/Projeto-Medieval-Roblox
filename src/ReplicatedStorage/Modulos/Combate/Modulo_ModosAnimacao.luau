--[[
	Modulo_ModosAnimacao.luau

	Centraliza os conjuntos de animação por modo (Base, Punhos, UmaMao, etc.).
	Este módulo contém apenas dados para manter o Modulo_Configuracoes mais limpo.
]]

--!strict

local ModoAnimacoes = {
	-- ───────────────────────────────────────────────────────────────
	-- BASE (Sem combate - apenas movimentação)
	-- ───────────────────────────────────────────────────────────────
	Base = {
		tipo = "Nenhum",
		aplicaImpulso = false,
		aplicaKnockback = false,
		temCombo = false,
		animacoes = {
			-- Movimento Normal
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

			-- Movimento Agachado
			IdleAgachado = "rbxassetid://129640837531159",
			AndandoAgachado = "rbxassetid://87797732262383",

			-- Dash
			DashFrente = "rbxassetid://77731344105069",
			DashTras = "rbxassetid://116512808764487",
			DashEsquerda = "rbxassetid://80802499324784",
			DashDireita = "rbxassetid://114879502782228",

			-- Estado
			Stunado = "rbxassetid://104947799689111",

			-- Interagir com o Mundo (Exclusivo do Base)
			InteragindoAlto = "rbxassetid://139881462472225",
			InteragindoBaixo = "rbxassetid://111940476196229",
			InteragindoChao = "rbxassetid://105611406813057",
			InteragindoMedio = "rbxassetid://111460345852039",
		},
	},

	-- ───────────────────────────────────────────────────────────────
	-- PUNHOS (Combate corpo a corpo desarmado)
	-- ───────────────────────────────────────────────────────────────
	Punhos = {
		tipo = "Combate",
		aplicaImpulso = true,
		aplicaKnockback = true,
		temCombo = true,
		configCombo = {
			velocidadeJanela = 0.4,
			divideDano = true, -- AttackBoth: cada mão aplica metade
		},
		animacoes = {
			-- Combate
			AtaqueLeve = "rbxassetid://80851426931067",
			AtaquePesado = "rbxassetid://117244978564325",
			Defesa = "rbxassetid://106963330997976",
			DefesaQuebrada = "rbxassetid://103742519902549",
			Aparar = "rbxassetid://129329167930963",
			Aparado = "rbxassetid://140567046809161",
			Equipar = "rbxassetid://140710454719042",
			Desequipar = "rbxassetid://79693751210844",

			-- Movimento Normal
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

			-- Movimento Agachado
			IdleAgachado = "rbxassetid://113336055232894",
			AndandoAgachado = "rbxassetid://110248727392186",

			-- Dash
			DashFrente = "rbxassetid://110380195030160",
			DashTras = "rbxassetid://137774822058926",
			DashEsquerda = "rbxassetid://134473715541120",
			DashDireita = "rbxassetid://118967040484648",

			-- Estado
			Stunado = "rbxassetid://119175260965936",
		},
	},

	-- ───────────────────────────────────────────────────────────────
	-- UMA MÃO + ESCUDO
	-- ───────────────────────────────────────────────────────────────
	UmaMaoEscudo = {
		tipo = "Combate",
		aplicaImpulso = true,
		aplicaKnockback = true,
		temCombo = true,
		configCombo = {
			velocidadeJanela = 0.4,
		},
		animacoes = {
			-- Combate
			AtaqueLeve = "rbxassetid://122280944254589",
			AtaquePesado = "rbxassetid://125243003105031",
			Defesa = "rbxassetid://127751906771957",
			DefesaQuebrada = "rbxassetid://94588265013910",
			Aparar = "rbxassetid://139881462472225",
			Aparado = "rbxassetid://94588265013910",
			Equipar = "rbxassetid://115099251307406",
			Desequipar = "rbxassetid://119300191293903",

			-- Movimento Normal
			Idle = "rbxassetid://97506647521728",
			Andando = "rbxassetid://101405606853852",
			AndandoDireita = "rbxassetid://109982570649734",
			AndandoEsquerda = "rbxassetid://99089536362364",
			Correndo = "rbxassetid://105489781294318",
			Pulando = "rbxassetid://126513416555386",
			Caindo = "rbxassetid://120023331153028",
			Escalando = "rbxassetid://128601601033320",

			-- Movimento Agachado (TODO: Adicionar IDs)
			IdleAgachado = "rbxassetid://0000000000",
			AndandoAgachado = "rbxassetid://0000000000",

			-- Dash (TODO: Adicionar IDs)
			DashFrente = "rbxassetid://0000000000",
			DashTras = "rbxassetid://0000000000",
			DashEsquerda = "rbxassetid://0000000000",
			DashDireita = "rbxassetid://0000000000",

			-- Estado
			Stunado = "rbxassetid://111940476196229",
		},
	},

	-- ───────────────────────────────────────────────────────────────
	-- ARCO (Combate à distância)
	-- ───────────────────────────────────────────────────────────────
	Arco = {
		tipo = "Combate",
		aplicaImpulso = false, -- Arcos NÃO aplicam impulso no atacante
		aplicaKnockback = true,
		temCombo = false, -- Arcos não têm combo
		animacoes = {
			-- Combate (TODO: Adicionar IDs)
			AtaqueDistancia = "rbxassetid://0000000000", -- Animação única de mirar/atirar
			Equipar = "rbxassetid://0000000000",
			Desequipar = "rbxassetid://0000000000",

			-- Movimento Normal (TODO: Adicionar IDs ou usar fallback Base)
			Idle = "rbxassetid://0000000000",
			Andando = "rbxassetid://0000000000",
			AndandoDireita = "rbxassetid://0000000000",
			AndandoEsquerda = "rbxassetid://0000000000",
			Correndo = "rbxassetid://0000000000",
			Pulando = "rbxassetid://0000000000",
			Caindo = "rbxassetid://0000000000",
			Escalando = "rbxassetid://0000000000",

			-- Estado
			Stunado = "rbxassetid://0000000000",
		},
	},

	-- ───────────────────────────────────────────────────────────────
	-- PICARETA (Ferramenta de interação)
	-- ───────────────────────────────────────────────────────────────
	Picareta = {
		tipo = "Interacao",
		aplicaImpulso = false, -- Ferramentas NÃO aplicam impulso
		aplicaKnockback = false, -- Ferramentas NÃO aplicam knockback
		temCombo = false,
		animacoes = {
			-- Interação (TODO: Adicionar IDs)
			Interagir = "rbxassetid://0000000000", -- Animação de minerar
			Equipar = "rbxassetid://0000000000",
			Desequipar = "rbxassetid://0000000000",

			-- Movimento Normal (TODO: Adicionar IDs ou usar fallback Base)
			Idle = "rbxassetid://0000000000",
			Andando = "rbxassetid://0000000000",
			AndandoDireita = "rbxassetid://0000000000",
			AndandoEsquerda = "rbxassetid://0000000000",
			Correndo = "rbxassetid://0000000000",
			Pulando = "rbxassetid://0000000000",
			Caindo = "rbxassetid://0000000000",
			Escalando = "rbxassetid://0000000000",

			-- Estado
			Stunado = "rbxassetid://0000000000",
		},
	},

	-- ───────────────────────────────────────────────────────────────
	-- MARTELO (Ferramenta de interação)
	-- ───────────────────────────────────────────────────────────────
	Martelo = {
		tipo = "Interacao",
		aplicaImpulso = false,
		aplicaKnockback = false,
		temCombo = false,
		animacoes = {
			-- Interação (TODO: Adicionar IDs)
			Interagir = "rbxassetid://0000000000",
			Equipar = "rbxassetid://0000000000",
			Desequipar = "rbxassetid://0000000000",

			-- Movimento Normal (TODO: Usar fallback Base)
			Idle = "rbxassetid://0000000000",
			Andando = "rbxassetid://0000000000",
			AndandoDireita = "rbxassetid://0000000000",
			AndandoEsquerda = "rbxassetid://0000000000",
			Correndo = "rbxassetid://0000000000",
			Pulando = "rbxassetid://0000000000",
			Caindo = "rbxassetid://0000000000",
			Escalando = "rbxassetid://0000000000",

			-- Estado
			Stunado = "rbxassetid://0000000000",
		},
	},

	-- ───────────────────────────────────────────────────────────────
	-- UMA MÃO (Espada/Adaga sem escudo — mão esquerda vazia)
	-- Placeholder: usar animações do UmaMaoEscudo como fallback temporário
	-- ───────────────────────────────────────────────────────────────
	UmaMao = {
		tipo = "Combate",
		aplicaImpulso = true,
		aplicaKnockback = true,
		temCombo = true,
		configCombo = {
			velocidadeJanela = 0.4,
		},
		animacoes = {
			-- Combate (TODO: Substituir por animações específicas de UmaMao)
			AtaqueLeve = "rbxassetid://122280944254589",
			AtaquePesado = "rbxassetid://125243003105031",
			Defesa = "rbxassetid://127751906771957",
			DefesaQuebrada = "rbxassetid://94588265013910",
			Aparar = "rbxassetid://139881462472225",
			Aparado = "rbxassetid://94588265013910",
			Equipar = "rbxassetid://115099251307406",
			Desequipar = "rbxassetid://119300191293903",

			-- Movimento Normal
			Idle = "rbxassetid://97506647521728",
			Andando = "rbxassetid://101405606853852",
			AndandoDireita = "rbxassetid://109982570649734",
			AndandoEsquerda = "rbxassetid://99089536362364",
			Correndo = "rbxassetid://105489781294318",
			Pulando = "rbxassetid://126513416555386",
			Caindo = "rbxassetid://120023331153028",
			Escalando = "rbxassetid://128601601033320",

			-- Estado
			Stunado = "rbxassetid://111940476196229",
		},
	},

	-- ───────────────────────────────────────────────────────────────
	-- UMA MÃO DUPLA (Dual-Wield: duas armas de uma mão)
	-- Placeholder: animações zeroed até serem criadas
	-- ───────────────────────────────────────────────────────────────
	UmaMaoDupla = {
		tipo = "Combate",
		aplicaImpulso = true,
		aplicaKnockback = true,
		temCombo = true,
		configCombo = {
			velocidadeJanela = 0.35,
			divideDano = true, -- AttackBoth: cada mão aplica metade
		},
		animacoes = {
			-- Combate (TODO: Substituir por animações específicas de UmaMaoDupla)
			AtaqueLeve = "rbxassetid://122280944254589",
			AtaquePesado = "rbxassetid://125243003105031",
			Defesa = "rbxassetid://127751906771957",
			DefesaQuebrada = "rbxassetid://94588265013910",
			Aparar = "rbxassetid://139881462472225",
			Aparado = "rbxassetid://94588265013910",
			Equipar = "rbxassetid://115099251307406",
			Desequipar = "rbxassetid://119300191293903",

			-- Movimento Normal
			Idle = "rbxassetid://97506647521728",
			Andando = "rbxassetid://101405606853852",
			AndandoDireita = "rbxassetid://109982570649734",
			AndandoEsquerda = "rbxassetid://99089536362364",
			Correndo = "rbxassetid://105489781294318",
			Pulando = "rbxassetid://126513416555386",
			Caindo = "rbxassetid://120023331153028",
			Escalando = "rbxassetid://128601601033320",

			-- Estado
			Stunado = "rbxassetid://111940476196229",
		},
	},

	-- ───────────────────────────────────────────────────────────────
	-- DUAS MÃOS (Espada-longa, montante, etc.)
	-- Placeholder: animações zeroed até serem criadas
	-- ───────────────────────────────────────────────────────────────
	DuasMaos = {
		tipo = "Combate",
		aplicaImpulso = true,
		aplicaKnockback = true,
		temCombo = true,
		configCombo = {
			velocidadeJanela = 0.5,
		},
		animacoes = {
			-- Combate (TODO: Adicionar IDs de duas mãos)
			AtaqueLeve = "rbxassetid://0000000000",
			AtaquePesado = "rbxassetid://0000000000",
			Defesa = "rbxassetid://0000000000",
			DefesaQuebrada = "rbxassetid://0000000000",
			Aparar = "rbxassetid://0000000000",
			Aparado = "rbxassetid://0000000000",
			Equipar = "rbxassetid://0000000000",
			Desequipar = "rbxassetid://0000000000",

			-- Movimento Normal (TODO: Adicionar IDs)
			Idle = "rbxassetid://0000000000",
			Andando = "rbxassetid://0000000000",
			AndandoDireita = "rbxassetid://0000000000",
			AndandoEsquerda = "rbxassetid://0000000000",
			Correndo = "rbxassetid://0000000000",
			Pulando = "rbxassetid://0000000000",
			Caindo = "rbxassetid://0000000000",
			Escalando = "rbxassetid://0000000000",

			-- Estado
			Stunado = "rbxassetid://0000000000",
		},
	},

	-- ───────────────────────────────────────────────────────────────
	-- PUNHOS + ESCUDO (Sem arma na mão direita, escudo na esquerda)
	-- Placeholder: animações zeroed até serem criadas
	-- ───────────────────────────────────────────────────────────────
	PunhosEscudo = {
		tipo = "Combate",
		aplicaImpulso = true,
		aplicaKnockback = true,
		temCombo = true,
		configCombo = {
			velocidadeJanela = 0.4,
		},
		animacoes = {
			-- Combate (TODO: Adicionar IDs de punhos+escudo)
			AtaqueLeve = "rbxassetid://0000000000",
			AtaquePesado = "rbxassetid://0000000000",
			Defesa = "rbxassetid://0000000000",
			DefesaQuebrada = "rbxassetid://0000000000",
			Aparar = "rbxassetid://0000000000",
			Aparado = "rbxassetid://0000000000",
			Equipar = "rbxassetid://0000000000",
			Desequipar = "rbxassetid://0000000000",

			-- Movimento Normal (TODO: Adicionar IDs)
			Idle = "rbxassetid://0000000000",
			Andando = "rbxassetid://0000000000",
			AndandoDireita = "rbxassetid://0000000000",
			AndandoEsquerda = "rbxassetid://0000000000",
			Correndo = "rbxassetid://0000000000",
			Pulando = "rbxassetid://0000000000",
			Caindo = "rbxassetid://0000000000",
			Escalando = "rbxassetid://0000000000",

			-- Estado
			Stunado = "rbxassetid://0000000000",
		},
	},
}

return ModoAnimacoes
