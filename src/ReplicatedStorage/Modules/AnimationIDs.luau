--[[
    ReplicatedStorage > AnimationIDs

    Armazena todos os IDs de animações organizados por modo de animação.
    Este módulo centraliza os dados de animação para fácil acesso por cliente e servidor.
]]

local AnimationIDs = {}

--=============================================================================
-- CONFIG: Animation IDs por Modo de Animação
-- NOTA: Estes IDs serão substituídos futuramente por dados do item equipado
--=============================================================================

-- Modo Base: Apenas estado Stunado disponível
AnimationIDs.Base = {
	-- Movimento
	Idle = "rbxassetid://95842068830831",
	IdleAgachado = "rbxassetid://0000000000",
	Andando = "rbxassetid://80372639586330",
	AndandoAgachado = "rbxassetid://0000000000",
	Correndo = "rbxassetid://84480325767002",
	Escalando = "rbxassetid://128601601033320",
	DashFrente = "rbxassetid://0000000000",
	DashTras = "rbxassetid://0000000000",
	DashEsquerda = "rbxassetid://0000000000",
	DashDireita = "rbxassetid://0000000000",
	Pulando = "rbxassetid://126513416555386",
	Caindo = "rbxassetid://120023331153028",
	Stunado = "rbxassetid://111940476196229",
}

-- Modo Punhos: Combate corpo a corpo desarmado
AnimationIDs.Punhos = {
	-- Combate
	AtaqueLeve = "rbxassetid://99089536362364",
	AtaquePesado = "rbxassetid://109982570649734",
	Defesa = "rbxassetid://111460345852039",
	DefesaQuebrada = "rbxassetid://105611406813057",
	Aparar = "rbxassetid://0000000000",
	Aparado = "rbxassetid://94588265013910",
	Equipar = "rbxassetid://87283295811902",
	Desequipar = "rbxassetid://125396593531220",

	-- Movimento
	Idle = "rbxassetid://139049880951103",
	IdleAgachado = "rbxassetid://0000000000",
	Andando = "rbxassetid://104976161284084",
	AndandoAgachado = "rbxassetid://0000000000",
	Correndo = "rbxassetid://84480325767002",
	Escalando = "rbxassetid://128601601033320",
	DashFrente = "rbxassetid://0000000000",
	DashTras = "rbxassetid://0000000000",
	DashEsquerda = "rbxassetid://0000000000",
	DashDireita = "rbxassetid://0000000000",
	Pulando = "rbxassetid://126513416555386",
	Caindo = "rbxassetid://120023331153028",
	Stunado = "rbxassetid://0000000000",
}

-- Modo UmaMaoEscudo: Combate com arma de uma mão e escudo
AnimationIDs.UmaMaoEscudo = {
	-- Combate
	AtaqueLeve = "rbxassetid://122280944254589",
	AtaquePesado = "rbxassetid://125243003105031",
	Defesa = "rbxassetid://127751906771957",
	DefesaQuebrada = "rbxassetid://94588265013910",
	Aparar = "rbxassetid://139881462472225",
	Aparado = "rbxassetid://94588265013910",
	Equipar = "rbxassetid://115099251307406",
	Desequipar = "rbxassetid://119300191293903",

	-- Movimento
	Idle = "rbxassetid://97506647521728",
	IdleAgachado = "rbxassetid://0000000000",
	Andando = "rbxassetid://101405606853852",
	AndandoAgachado = "rbxassetid://0000000000",
	Correndo = "rbxassetid://105489781294318",
	Escalando = "rbxassetid://128601601033320", -- Igual ao Base
	DashFrente = "rbxassetid://0000000000",
	DashTras = "rbxassetid://0000000000",
	DashEsquerda = "rbxassetid://0000000000",
	DashDireita = "rbxassetid://0000000000",
	Pulando = "rbxassetid://126513416555386", -- Igual ao Base
	Caindo = "rbxassetid://120023331153028", -- Igual ao Base
	Stunado = "rbxassetid://111940476196229",
}

return AnimationIDs
