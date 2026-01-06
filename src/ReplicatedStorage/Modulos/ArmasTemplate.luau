--[[
    ArmasTemplate.luau
    
    Módulo central que contém todos os dados de armas/modos de combate.
    Inclui: dano, hitbox, impulso, cooldowns, animações, combos.
    
    Estrutura:
    - Cada arma/modo tem uma entrada única
    - Campo 'categoria' para agrupar (Punhos, UmaMao, DuasMaos, etc.)
    - Combos são definidos por arma, permitindo variação de sequência e timing
]]

local ArmasTemplate = {}

-- ═══════════════════════════════════════════════════════════════════
-- CONFIGURAÇÕES GLOBAIS
-- ═══════════════════════════════════════════════════════════════════

ArmasTemplate.ConfiguracaoGlobal = {
	-- Multiplicadores de dano crítico
	ChanceCritico = 0.1, -- 10% de chance
	MultiplicadorCritico = 1.5, -- 150% do dano

	-- Tempos de stun
	TempoStunLeve = 0.3,
	TempoStunPesado = 0.6,
	TempoStunAparado = 0.7,

	-- Janela de parry
	JanelaParry = 0.2, -- segundos (tempo que pode aparar após iniciar bloqueio)
	CooldownParry = 2.4, -- segundos (cooldown antes de poder aparar novamente)

	-- Tempos e delays
	TempoCarregarPesado = 0.2, -- Tempo para iniciar carga de ataque pesado
	JanelaCombo = 0.2, -- Janela de timing para continuar combo
	VelocidadeComboEspera = 0.4, -- Velocidade da animação na janela de combo
	TempoMinimoQueda = 0.28, -- Hold de animação de pulo antes de transitar para queda
	VelocidadeCorrendoNoAr = 0.4, -- Velocidade da animação de corrida no ar

	-- Cooldowns por ação
	CooldownComboLeve = 0.5,
	CooldownAtaquePesado = 2.0,
	CooldownBloqueio = 0.5,

	-- Velocidades de movimento
	VelocidadeNormal = 16,
	VelocidadeCorrendo = 25,
	VelocidadeBloqueando = 8,
	VelocidadeDefesaQuebrada = 3,
	VelocidadeAgachado = 12,
	VelocidadeAparado = 3,
	VelocidadeEscalando = 12,

	-- Dash/Roll
	CooldownDash = 1.5, -- Cooldown entre dashes (segundos)
	ForcaDash = 45, -- Força do impulso sustentado
	VelocidadeAnimacaoDash = 1.0, -- Velocidade da animação de dash (0-3)
}

-- ═══════════════════════════════════════════════════════════════════
-- TEMPLATE DE ARMAS
-- ═══════════════════════════════════════════════════════════════════

ArmasTemplate.Armas = {

	-- ───────────────────────────────────────────────────────────────
	-- BASE (Sem combate - apenas movimentação)
	-- Usado quando o player não tem nenhuma arma equipada
	-- ───────────────────────────────────────────────────────────────
	Base = {
		nome = "Base",
		categoria = "Nenhum",
		descricao = "Modo base sem habilidades de combate - nenhuma arma equipada",

		ataques = {}, -- Sem ataques
		combo = nil, -- Sem combo

		animacoes = {
			-- Movimento Normal
			Idle = "rbxassetid://82165471407920",
			Andando = "rbxassetid://104395502422213",
			Correndo = "rbxassetid://84638257154650",
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
	-- Modo de combate com punhos, sem arma física
	-- ───────────────────────────────────────────────────────────────
	Punhos = {
		nome = "Punhos",
		categoria = "Desarmado",
		descricao = "Combate corpo a corpo com os punhos",

		-- Ataques disponíveis
		ataques = {
			AtaqueLeve = {
				danoBase = 9,
				tempoRecarga = 0.5,
				podeCombo = true,
				hitbox = {
					tamanho = Vector3.new(3.8, 3.5, 4.0),
					offset = CFrame.new(0, 0, -2.6),
					duracao = 0.10,
				},
				impulsoAtacante = {
					forca = 40,
					elevacao = 2,
				},
				impulsoAlvo = nil, -- Sem knockback
			},

			AtaqueLeveFinal = {
				danoBase = 14,
				tempoRecarga = 0.5,
				bonusDano = 0.05, -- +5% para Punhos
				hitbox = {
					tamanho = Vector3.new(4.5, 4.0, 5.0),
					offset = CFrame.new(0, 0, -3.0),
					duracao = 0.12,
				},
				impulsoAtacante = {
					forca = 60,
					elevacao = 2,
				},
				impulsoAlvo = {
					distancia = 18,
					altura = 4,
					duracao = 0.4,
				},
			},

			AtaquePesado = {
				danoBase = 22,
				tempoRecarga = 2.0,
				tempoCarregar = 0.2, -- Tempo mínimo segurando
				hitbox = {
					tamanho = Vector3.new(5.0, 4.5, 6.0),
					offset = CFrame.new(0, 0, -3.5),
					duracao = 0.14,
				},
				impulsoAtacante = {
					forca = 100,
					elevacao = 2,
				},
				impulsoAlvo = {
					distancia = 22,
					altura = 5,
					duracao = 0.5,
				},
			},
		},

		--[[
			Sistema de Combo
			
			A animação de AtaqueLeve é uma única animação contínua que contém todos os golpes.
			Usa marcadores (KeyframeMarker) para sincronizar:
			
			Marcadores na animação:
			- "Attack" (params: "1", "2", "3", "4") - Momento de criar hitbox para cada golpe
			- "ComboEnd1", "ComboEnd2", "ComboEnd3" - Início da janela de input após cada golpe
			
			Fluxo:
			1. Player clica M1 → animação inicia velocidade 1
			2. Ao chegar em "ComboEndX", velocidade vai para 0.4 (janela de input)
			3. Se player clica M1 durante janela → velocidade volta para 1, continua animação
			4. Se não clica → animação para suavemente, volta para Idle
			5. Marcador "Attack" dispara hitbox no servidor
		]]
		combo = {
			-- Sequência de golpes (para referência, mas animação é uma só)
			sequencia = { "AtaqueLeve", "AtaqueLeve", "AtaqueLeve", "AtaqueLeveFinal" },

			-- Tempo da janela de input (em segundos reais)
			janelaCombo = 0.2,

			-- Velocidade da animação durante janela de input
			velocidadeJanela = 0.4,

			-- Nomes dos marcadores na animação
			marcadores = {
				ataque = "Attack", -- Marcador de hitbox (params: "1", "2", "3", "4")
				janelasCombo = { "ComboEnd1", "ComboEnd2", "ComboEnd3" }, -- Marcadores de janela
			},

			-- Total de golpes no combo (incluindo final)
			totalGolpes = 4,
		},

		-- IDs de animação
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
			Correndo = "rbxassetid://128600831352375",
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
	-- Arma de uma mão com escudo para defesa
	-- ───────────────────────────────────────────────────────────────
	UmaMaoEscudo = {
		nome = "Uma Mão + Escudo",
		categoria = "UmaMao",
		descricao = "Arma de uma mão com escudo para defesa",

		ataques = {
			AtaqueLeve = {
				danoBase = 12,
				tempoRecarga = 0.5,
				podeCombo = true,
				hitbox = {
					tamanho = Vector3.new(5.0, 4.0, 6.0),
					offset = CFrame.new(0, 0, -3.5),
					duracao = 0.10,
				},
				impulsoAtacante = {
					forca = 40,
					elevacao = 2,
				},
				impulsoAlvo = nil,
			},

			AtaqueLeveFinal = {
				danoBase = 18,
				tempoRecarga = 0.5,
				hitbox = {
					tamanho = Vector3.new(6.0, 4.0, 7.5),
					offset = CFrame.new(0, 0, -4.2),
					duracao = 0.12,
				},
				impulsoAtacante = {
					forca = 60,
					elevacao = 2,
				},
				impulsoAlvo = {
					distancia = 18,
					altura = 4,
					duracao = 0.4,
				},
			},

			AtaquePesado = {
				danoBase = 28,
				tempoRecarga = 2.0,
				tempoCarregar = 0.2,
				hitbox = {
					tamanho = Vector3.new(7.5, 5.0, 9.0),
					offset = CFrame.new(0, 0, -5.0),
					duracao = 0.14,
				},
				impulsoAtacante = {
					forca = 100,
					elevacao = 2,
				},
				impulsoAlvo = {
					distancia = 22,
					altura = 5,
					duracao = 0.5,
				},
			},
		},

		--[[
			Sistema de Combo
			
			A animação de AtaqueLeve é uma única animação contínua que contém todos os golpes.
			Usa marcadores (KeyframeMarker) para sincronizar:
			
			Marcadores na animação:
			- "Attack" (params: "1", "2", "3", "4") - Momento de criar hitbox para cada golpe
			- "ComboEnd1", "ComboEnd2", "ComboEnd3" - Início da janela de input após cada golpe
			
			Fluxo:
			1. Player clica M1 → animação inicia velocidade 1
			2. Ao chegar em "ComboEndX", velocidade vai para 0.4 (janela de input)
			3. Se player clica M1 durante janela → velocidade volta para 1, continua animação
			4. Se não clica → animação para suavemente, volta para Idle
			5. Marcador "Attack" dispara hitbox no servidor
		]]
		combo = {
			-- Sequência de golpes (para referência, mas animação é uma só)
			sequencia = { "AtaqueLeve", "AtaqueLeve", "AtaqueLeve", "AtaqueLeveFinal" },

			-- Tempo da janela de input (em segundos reais)
			janelaCombo = 0.2,

			-- Velocidade da animação durante janela de input
			velocidadeJanela = 0.4,

			-- Nomes dos marcadores na animação
			marcadores = {
				ataque = "Attack", -- Marcador de hitbox (params: "1", "2", "3", "4")
				janelasCombo = { "ComboEnd1", "ComboEnd2", "ComboEnd3" }, -- Marcadores de janela
			},

			-- Total de golpes no combo (incluindo final)
			totalGolpes = 4,
		},

		animacoes = {
			-- Combate
			AtaqueLeve = "rbxassetid://12228094425458",
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
			Correndo = "rbxassetid://105489781294318",
			Pulando = "rbxassetid://126513416555386", -- Igual ao Base
			Caindo = "rbxassetid://120023331153028", -- Igual ao Base
			Escalando = "rbxassetid://128601601033320", -- Igual ao Base

			-- Movimento Agachado
			IdleAgachado = "rbxassetid://0000000000", -- TODO: Adicionar ID
			AndandoAgachado = "rbxassetid://0000000000", -- TODO: Adicionar ID

			-- Dash
			DashFrente = "rbxassetid://0000000000", -- TODO: Adicionar ID
			DashTras = "rbxassetid://0000000000", -- TODO: Adicionar ID
			DashEsquerda = "rbxassetid://0000000000", -- TODO: Adicionar ID
			DashDireita = "rbxassetid://0000000000", -- TODO: Adicionar ID

			-- Estado
			Stunado = "rbxassetid://111940476196229",
		},
	},
}

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES UTILITÁRIAS
-- ═══════════════════════════════════════════════════════════════════

--- Obtém template de arma pelo nome/modo
---@param nomeArma string
---@return table|nil
function ArmasTemplate.ObterArma(nomeArma: string)
	return ArmasTemplate.Armas[nomeArma]
end

--- Obtém dados de ataque específico de uma arma
---@param nomeArma string
---@param tipoAtaque string
---@return table|nil
function ArmasTemplate.ObterAtaque(nomeArma: string, tipoAtaque: string)
	local arma = ArmasTemplate.Armas[nomeArma]
	if arma and arma.ataques then
		return arma.ataques[tipoAtaque]
	end
	return nil
end

--- Obtém ID de animação, com fallback para Base
---@param nomeArma string
---@param nomeAnimacao string
---@return string|nil
function ArmasTemplate.ObterAnimacao(nomeArma: string, nomeAnimacao: string)
	local arma = ArmasTemplate.Armas[nomeArma]

	-- Tenta encontrar na arma específica
	if arma and arma.animacoes and arma.animacoes[nomeAnimacao] then
		return arma.animacoes[nomeAnimacao]
	end

	-- Fallback para Base
	local base = ArmasTemplate.Armas.Base
	if base and base.animacoes and base.animacoes[nomeAnimacao] then
		return base.animacoes[nomeAnimacao]
	end

	return nil
end

--- Obtém todas as armas de uma categoria
---@param categoria string
---@return table
function ArmasTemplate.ObterArmasPorCategoria(categoria: string)
	local resultado = {}
	for nome, arma in pairs(ArmasTemplate.Armas) do
		if arma.categoria == categoria then
			resultado[nome] = arma
		end
	end
	return resultado
end

--- Verifica se uma arma tem capacidade de combate
---@param nomeArma string
---@return boolean
function ArmasTemplate.PodeCombater(nomeArma: string)
	local arma = ArmasTemplate.Armas[nomeArma]
	if not arma then
		return false
	end
	return arma.ataques and next(arma.ataques) ~= nil
end

--- Obtém o próximo ataque do combo
---@param nomeArma string
---@param indiceAtual number
---@return string|nil, number
function ArmasTemplate.ObterProximoCombo(nomeArma: string, indiceAtual: number)
	local arma = ArmasTemplate.Armas[nomeArma]
	if not arma or not arma.combo then
		return nil, 0
	end

	local sequencia = arma.combo.sequencia
	local proximoIndice = indiceAtual + 1

	if proximoIndice > #sequencia then
		return nil, 0 -- Combo terminou
	end

	return sequencia[proximoIndice], proximoIndice
end

--- Reseta combo para o início
---@param nomeArma string
---@return string|nil, number
function ArmasTemplate.IniciarCombo(nomeArma: string)
	local arma = ArmasTemplate.Armas[nomeArma]
	if not arma or not arma.combo then
		return nil, 0
	end

	return arma.combo.sequencia[1], 1
end

--- Calcula dano final com stats
---@param danoBase number
---@param forca number
---@param critico boolean
---@return number
function ArmasTemplate.CalcularDano(danoBase: number, forca: number, critico: boolean)
	local config = ArmasTemplate.ConfiguracaoGlobal
	local multiplicadorCrit = critico and config.MultiplicadorCritico or 1.0

	return danoBase * (1 + (forca or 0) / 100) * multiplicadorCrit
end

--- Verifica se é crítico
---@param chanceExtra number|nil
---@return boolean
function ArmasTemplate.RolarCritico(chanceExtra: number?)
	local config = ArmasTemplate.ConfiguracaoGlobal
	local chanceTotal = config.ChanceCritico + (chanceExtra or 0)
	return math.random() < chanceTotal
end

--- Obtém configuração do combo de uma arma
---@param nomeArma string
---@return table|nil Dados do combo ou nil se não tiver combo
function ArmasTemplate.ObterCombo(nomeArma: string)
	local arma = ArmasTemplate.Armas[nomeArma]
	if arma and arma.combo then
		return arma.combo
	end
	return nil
end

--- Obtém o tipo de ataque baseado no índice do combo
--- Índice 1, 2, 3 = AtaqueLeve, índice 4 (ou último) = AtaqueLeveFinal
---@param nomeArma string
---@param indiceCombo number Índice do golpe atual (1, 2, 3, 4)
---@return string Tipo do ataque ("AtaqueLeve" ou "AtaqueLeveFinal")
function ArmasTemplate.ObterTipoAtaquePorIndice(nomeArma: string, indiceCombo: number)
	local combo = ArmasTemplate.ObterCombo(nomeArma)
	if not combo then
		return "AtaqueLeve"
	end

	-- Se é o último golpe, retorna AtaqueLeveFinal
	if indiceCombo >= combo.totalGolpes then
		return "AtaqueLeveFinal"
	end

	return "AtaqueLeve"
end

--- Verifica se o índice é o golpe final do combo
---@param nomeArma string
---@param indiceCombo number
---@return boolean
function ArmasTemplate.EhGolpeFinal(nomeArma: string, indiceCombo: number)
	local combo = ArmasTemplate.ObterCombo(nomeArma)
	if not combo then
		return true -- Sem combo = sempre final
	end
	return indiceCombo >= combo.totalGolpes
end

--- Obtém todas as animações de todos os modos (para pré-carregamento)
---@return table Lista de IDs de animação únicos
function ArmasTemplate.ObterTodasAnimacoes()
	local animacoes = {}
	local jaAdicionado = {}

	for nomeArma, arma in pairs(ArmasTemplate.Armas) do
		if arma.animacoes then
			for nomeAnimacao, animId in pairs(arma.animacoes) do
				-- Só adiciona se for um ID válido e não duplicado
				if
					type(animId) == "string"
					and animId:match("^rbxassetid://(%d+)$")
					and animId ~= "rbxassetid://0000000000"
					and not jaAdicionado[animId]
				then
					table.insert(animacoes, animId)
					jaAdicionado[animId] = true
				end
			end
		end
	end

	return animacoes
end

return ArmasTemplate
