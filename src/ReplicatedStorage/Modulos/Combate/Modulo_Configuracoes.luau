--[[
	Modulo_Configuracoes.luau
	
	Centraliza IDs de animações dos conjuntos "modoAnimacao" e todas as
	configurações globais do sistema de combate.
	
	Responsabilidades:
	- Definir configurações globais (tempos, velocidades, magnitudes)
	- Definir modos de animação (Punhos, UmaMaoEscudo, Arco, Ferramentas)
	- Validar IDs de animação
	- Pré-carregar animações
	
	Tipos de ataque: AtaqueLeve, AtaqueLeveFinal, AtaquePesado
	(Sem sistema de crítico - removido conforme especificação)
]]

--!strict

-- ═══════════════════════════════════════════════════════════════════
-- TYPES
-- ═══════════════════════════════════════════════════════════════════

export type ConfigCombo = {
	velocidadeJanela: number,
	janelaCombo: number?, -- Injetado globalmente
	marcadores: {
		janelasCombo: { string },
		ataque: string,
	},
}

export type ModoAnimacao = {
	tipo: string, -- "Combate" | "Interacao"
	aplicaImpulso: boolean,
	aplicaKnockback: boolean,
	temCombo: boolean,
	configCombo: ConfigCombo?,
	animacoes: { [string]: string },
}

export type ConfiguracaoGlobal = {
	-- Tempos de stun
	TempoStunLeve: number,
	TempoStunPesado: number,
	TempoStunAparado: number,

	-- Janela de parry
	JanelaParry: number,
	CooldownParry: number,

	-- Tempos e delays
	TempoCarregarPesado: number,
	JanelaCombo: number,
	VelocidadeComboEspera: number,
	TempoMinimoQueda: number,
	VelocidadeCorrendoNoAr: number,

	-- Ataque Pesado
	VelocidadeCarregandoPesado: number,
	VelocidadeSoltarPesado: number,

	-- Janela de Cancelamento
	JanelaCancelamentoComboFinal: number,
	JanelaCancelamentoAtaquePesado: number,
	JanelaCancelamentoAtaquePorDefesa: number,
	JanelaCancelamentoCarregamentoPorDefesa: number,
	CooldownCancelamentoPorDefesa: number,
	TempoSegurandoM2ParaDefesa: number,

	-- Cooldowns
	CooldownComboLeve: number,
	CooldownAtaquePesado: number,
	CooldownBloqueio: number,

	-- Velocidades de movimento
	VelocidadeNormal: number,
	VelocidadeCorrendo: number,
	VelocidadeBloqueando: number,
	VelocidadeDefesaQuebrada: number,
	VelocidadeAgachado: number,
	VelocidadeAparado: number,
	VelocidadeEscalando: number,

	-- Dash
	CooldownDash: number,
	ForcaDash: number,
	VelocidadeAnimacaoDash: number,

	-- Impulso de Ataque
	MagnitudeImpulsoAtaqueLeve: number,
	MagnitudeImpulsoAtaquePesado: number,

	-- Knockback
	MagnitudeKnockbackLeve: number,
	MagnitudeKnockbackPesado: number,
	VisualizarHitbox: boolean,
}

-- ═══════════════════════════════════════════════════════════════════
-- CONSTANTES
-- ═══════════════════════════════════════════════════════════════════

local REGEX_ASSET_ID = "^rbxassetid://(%d+)$"
local ASSET_ID_INVALIDO = "rbxassetid://0000000000"

-- ═══════════════════════════════════════════════════════════════════
-- MÓDULO
-- ═══════════════════════════════════════════════════════════════════

local Modulo_Configuracoes = {}

-- ═══════════════════════════════════════════════════════════════════
-- CONFIGURAÇÃO GLOBAL
-- ═══════════════════════════════════════════════════════════════════

Modulo_Configuracoes.ConfiguracaoGlobal = {
	-- Tempos de stun
	TempoStunLeve = 0.3,
	TempoStunPesado = 0.6,
	TempoStunAparado = 0.7,

	-- Janela de parry
	JanelaParry = 0.2,
	CooldownParry = 2.4,

	-- Tempos e delays
	TempoCarregarPesado = 0.2,
	JanelaCombo = 0.2,
	VelocidadeComboEspera = 0.4,
	TempoMinimoQueda = 0.28,
	VelocidadeCorrendoNoAr = 0.4,

	-- Ataque Pesado
	VelocidadeCarregandoPesado = 1.1,
	VelocidadeSoltarPesado = 1.0,

	-- Janela de Cancelamento
	JanelaCancelamentoComboFinal = 0.6,
	JanelaCancelamentoAtaquePesado = 0.5,
	JanelaCancelamentoAtaquePorDefesa = 0.3,
	JanelaCancelamentoCarregamentoPorDefesa = 0.9,
	CooldownCancelamentoPorDefesa = 1.0,
	TempoSegurandoM2ParaDefesa = 0.13,

	-- Cooldowns
	CooldownComboLeve = 0.5,
	CooldownAtaquePesado = 2.0,
	CooldownBloqueio = 0.5,

	-- Velocidades de movimento
	VelocidadeNormal = 14,
	VelocidadeCorrendo = 21,
	VelocidadeBloqueando = 6,
	VelocidadeDefesaQuebrada = 3,
	VelocidadeAgachado = 9,
	VelocidadeAparado = 3,
	VelocidadeEscalando = 12,

	-- Dash
	CooldownDash = 1.5,
	ForcaDash = 45,
	VelocidadeAnimacaoDash = 1.0,

	-- Impulso de Ataque (aplicado ao atacante)
	MagnitudeImpulsoAtaqueLeve = 20,
	MagnitudeImpulsoAtaquePesado = 50,

	-- Knockback (aplicado ao alvo)
	MagnitudeKnockbackLeve = 15,
	MagnitudeKnockbackPesado = 150,
	VisualizarHitbox = true, -- Altere para true para visualizar a área do hit no mundo
}

-- ═══════════════════════════════════════════════════════════════════
-- MODOS DE ANIMAÇÃO
-- ═══════════════════════════════════════════════════════════════════

Modulo_Configuracoes.ModoAnimacoes = {
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
			marcadores = {
				janelasCombo = { "ComboEnd1", "ComboEnd2", "ComboEnd3" },
				ataque = "Attack",
			},
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
			Correndo = "rbxassetid://128600831352375",
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
			marcadores = {
				janelasCombo = { "ComboEnd1", "ComboEnd2", "ComboEnd3" },
				ataque = "Attack",
			},
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
}

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES DE VALIDAÇÃO
-- ═══════════════════════════════════════════════════════════════════

--- Valida se um ID de animação é válido
---@param animId string
---@return boolean
function Modulo_Configuracoes.ValidarIdAnimacao(animId: string): boolean
	if type(animId) ~= "string" then
		return false
	end
	if animId == ASSET_ID_INVALIDO then
		return false
	end
	return animId:match(REGEX_ASSET_ID) ~= nil
end

--- Valida se um nome de modo existe
---@param nomeModo string
---@return boolean
function Modulo_Configuracoes.ModoExiste(nomeModo: string): boolean
	if type(nomeModo) ~= "string" then
		return false
	end
	return Modulo_Configuracoes.ModoAnimacoes[nomeModo] ~= nil
end

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES DE ACESSO
-- ═══════════════════════════════════════════════════════════════════

--- Obtém configuração de um modo de animação
---@param nomeModo string
---@return ModoAnimacao?
function Modulo_Configuracoes.ObterModoAnimacao(nomeModo: string): ModoAnimacao?
	if not nomeModo or type(nomeModo) ~= "string" then
		warn("[Modulo_Configuracoes] Nome de modo inválido: " .. tostring(nomeModo))
		return nil
	end

	local modo = Modulo_Configuracoes.ModoAnimacoes[nomeModo]
	if not modo then
		warn("[Modulo_Configuracoes] Modo de animação não encontrado: " .. nomeModo)
		return nil
	end

	return modo
end

--- Obtém ID de uma animação específica, com fallback para Base
---@param nomeModo string
---@param nomeAnimacao string
---@return string?
function Modulo_Configuracoes.ObterAnimacao(nomeModo: string, nomeAnimacao: string): string?
	-- Tenta encontrar no modo específico
	local modo = Modulo_Configuracoes.ModoAnimacoes[nomeModo]
	if modo and modo.animacoes and modo.animacoes[nomeAnimacao] then
		local animId = modo.animacoes[nomeAnimacao]
		if Modulo_Configuracoes.ValidarIdAnimacao(animId) then
			return animId
		end
	end

	-- Fallback para Base
	local base = Modulo_Configuracoes.ModoAnimacoes.Base
	if base and base.animacoes and base.animacoes[nomeAnimacao] then
		local animId = base.animacoes[nomeAnimacao]
		if Modulo_Configuracoes.ValidarIdAnimacao(animId) then
			return animId
		end
	end

	return nil
end

--- Obtém valor de configuração global
---@param chave string
---@return any
function Modulo_Configuracoes.ObterConfiguracao(chave: string): any
	if not chave or type(chave) ~= "string" then
		warn("[Modulo_Configuracoes] Chave de configuração inválida: " .. tostring(chave))
		return nil
	end

	local valor = Modulo_Configuracoes.ConfiguracaoGlobal[chave]
	if valor == nil then
		warn("[Modulo_Configuracoes] Configuração não encontrada: " .. chave)
	end

	return valor
end

--- Verifica se um modo aplica impulso no atacante
---@param nomeModo string
---@return boolean
function Modulo_Configuracoes.AplicaImpulso(nomeModo: string): boolean
	local modo = Modulo_Configuracoes.ObterModoAnimacao(nomeModo)
	return modo and modo.aplicaImpulso or false
end

--- Verifica se um modo aplica knockback no alvo
---@param nomeModo string
---@return boolean
function Modulo_Configuracoes.AplicaKnockback(nomeModo: string): boolean
	local modo = Modulo_Configuracoes.ObterModoAnimacao(nomeModo)
	return modo and modo.aplicaKnockback or false
end

--- Verifica se um modo tem sistema de combo
---@param nomeModo string
---@return boolean
function Modulo_Configuracoes.TemCombo(nomeModo: string): boolean
	local modo = Modulo_Configuracoes.ObterModoAnimacao(nomeModo)
	return modo and modo.temCombo or false
end

--- Verifica se um modo é de combate
---@param nomeModo string
---@return boolean
function Modulo_Configuracoes.EhCombate(nomeModo: string): boolean
	local modo = Modulo_Configuracoes.ObterModoAnimacao(nomeModo)
	return modo and modo.tipo == "Combate" or false
end

--- Verifica se um modo é de interação
---@param nomeModo string
---@return boolean
function Modulo_Configuracoes.EhInteracao(nomeModo: string): boolean
	local modo = Modulo_Configuracoes.ObterModoAnimacao(nomeModo)
	return modo and modo.tipo == "Interacao" or false
end

--- Obtém configuração de combo para um modo
---@param nomeModo string
---@return any?
function Modulo_Configuracoes.ObterConfiguracaoCombo(nomeModo: string): any?
	local modo = Modulo_Configuracoes.ObterModoAnimacao(nomeModo)
	if not modo or not modo.configCombo then
		return nil
	end

	-- Retorna uma cópia combinada com globais
	local config = table.clone(modo.configCombo)
	config.janelaCombo = Modulo_Configuracoes.ObterConfiguracao("JanelaCombo") or 0.2

	return config
end

--- Obtém o tipo de ataque baseado no índice do combo
---@param nomeModo string
---@param indice number
---@return string
function Modulo_Configuracoes.ObterTipoAtaquePorIndice(nomeModo: string, indice: number): string
	-- Lógica padrão simplificada: >= 4 é final, senão é leve
	if indice >= 4 then
		return "AtaqueLeveFinal"
	end
	return "AtaqueLeve"
end

-- ═══════════════════════════════════════════════════════════════════
-- PRÉ-CARREGAMENTO DE ANIMAÇÕES
-- ═══════════════════════════════════════════════════════════════════

--- Obtém todas as animações de todos os modos (para pré-carregamento)
---@return {string} Lista de IDs de animação únicos
function Modulo_Configuracoes.ObterTodasAnimacoes(): { string }
	local animacoes = {}
	local jaAdicionado = {}

	for _, modo in pairs(Modulo_Configuracoes.ModoAnimacoes) do
		if modo.animacoes then
			for _, animId in pairs(modo.animacoes) do
				if Modulo_Configuracoes.ValidarIdAnimacao(animId) and not jaAdicionado[animId] then
					table.insert(animacoes, animId)
					jaAdicionado[animId] = true
				end
			end
		end
	end

	return animacoes
end

--- Pré-carrega todas as animações em um Animator
---@param animator Animator
---@return {AnimationTrack}
function Modulo_Configuracoes.PreCarregarAnimacoes(animator: Animator): { AnimationTrack }
	if not animator then
		warn("[Modulo_Configuracoes] Animator inválido para pré-carregamento")
		return {}
	end

	local tracks = {}
	local animacoes = Modulo_Configuracoes.ObterTodasAnimacoes()

	for _, animId in ipairs(animacoes) do
		local sucesso, resultado = pcall(function()
			local animation = Instance.new("Animation")
			animation.AnimationId = animId
			local track = animator:LoadAnimation(animation)
			animation:Destroy()
			return track
		end)

		if sucesso and resultado then
			table.insert(tracks, resultado)
		else
			warn("[Modulo_Configuracoes] Falha ao pré-carregar animação: " .. animId)
		end
	end

	return tracks
end

--- Obtém o ID de uma animação específica de um modo
---@param nomeModo string
---@param nomeAnimacao string
---@return string?
function Modulo_Configuracoes.ObterIdAnimacao(nomeModo: string, nomeAnimacao: string): string?
	local modo = Modulo_Configuracoes.ObterModoAnimacao(nomeModo)
	if not modo or not modo.animacoes then
		return nil
	end
	return modo.animacoes[nomeAnimacao]
end

return Modulo_Configuracoes
