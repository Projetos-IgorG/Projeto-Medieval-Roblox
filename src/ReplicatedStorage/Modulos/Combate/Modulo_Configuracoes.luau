--[[
	Modulo_Configuracoes.luau
	
	Centraliza IDs de animações dos conjuntos "modoAnimacao" e todas as
	configurações globais do sistema de combate.
	
	Responsabilidades:
	- Definir configurações globais (tempos, velocidades, magnitudes)
	- Consumir modos de animação (Punhos, UmaMaoEscudo, Arco, Ferramentas)
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
	velocidadeJanela: number, -- Velocidade da animação durante janela de combo
	janelaCombo: number?,     -- Duração da janela (injetado globalmente se nil)
	divideDano: boolean?,     -- Se true, dano é dividido por mão (para AttackBoth)
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
	JanelaCancelAtaque: number,
	JanelaCancelAtaquePesado: number,
	CooldownCancel: number,
	TempoSegurandoM2ParaDefesa: number,
	VelocidadeReversaoCancelamento: number,

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
	DuracaoImpulsoAtaqueLeve: number,
	DuracaoImpulsoAtaquePesado: number,

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
local Modulo_ModosAnimacao = require(script.Parent:WaitForChild("Modulo_ModosAnimacao"))

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
	JanelaCancelAtaque = 0.3,
	JanelaCancelAtaquePesado = 0.7,
	CooldownCancel = 1.0,
	TempoSegurandoM2ParaDefesa = 0.13,
	VelocidadeReversaoCancelamento = -1.5,

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
	JanelaCancelamentoDash = 0.2, -- Tempo antes do fim da animação para early-cancel (segundos)

	-- Impulso de Ataque (aplicado ao atacante)
	MagnitudeImpulsoAtaqueLeve = 20,
	MagnitudeImpulsoAtaquePesado = 50,
	DuracaoImpulsoAtaqueLeve = 0.1,
	DuracaoImpulsoAtaquePesado = 0.2,

	-- Knockback (aplicado ao alvo)
	MagnitudeKnockbackLeve = 15,
	MagnitudeKnockbackPesado = 150,
	VisualizarHitbox = true, -- Altere para true para visualizar a área do hit no mundo
}

-- ═══════════════════════════════════════════════════════════════════
-- MODOS DE ANIMAÇÃO
-- ═══════════════════════════════════════════════════════════════════

Modulo_Configuracoes.ModoAnimacoes = Modulo_ModosAnimacao

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

--- Verifica se um modo bloqueia interações com o mundo (proximity prompts, arrastar itens)
--- Modos de Combate e Interação bloqueiam interações
---@param nomeModo string
---@return boolean
function Modulo_Configuracoes.BloqueiaInteracao(nomeModo: string): boolean
	local modo = Modulo_Configuracoes.ObterModoAnimacao(nomeModo)
	if not modo then
		return false
	end
	return modo.tipo == "Combate" or modo.tipo == "Interacao"
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
function Modulo_Configuracoes.ObterTipoAtaquePorIndice(_nomeModo: string, indice: number): string
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
