--!strict

--[[
    Script: ConfigCombate.luau
    Caminho: src/ReplicatedStorage/Combate/Configuracoes
    Responsabilidade: Centraliza valores de alcance, dano, tempos, stamina e parametros gerais do combate.
    Uso: ModuleScript; use require(caminho) para ler as tabelas e valores exportados.
    Nao faz: Nao executa comportamento sozinho; apenas fornece dados para outros scripts.
    Funcoes principais: ValidarIdAnimacao, ModoExiste, ObterModoAnimacao, ObterAnimacao, ObterConfiguracao, AplicaImpulso
]]
export type ConfigCombo = {
	velocidadeJanela: number,
	janelaCombo: number?,
	divideDano: boolean?,
}

export type ModoAnimacao = {
	tipo: string,
	aplicaImpulso: boolean,
	aplicaKnockback: boolean,
	temCombo: boolean,
	configCombo: ConfigCombo?,
	animacoes: { [string]: string },
}

export type ConfiguracaoGlobal = {

	TempoStunLeve: number,
	TempoStunPesado: number,
	TempoStunAparado: number,
	TempoAparando: number,

	JanelaParry: number,
	CooldownParry: number,

	TempoCarregarPesado: number,
	JanelaCombo: number,
	VelocidadeComboEspera: number,
	TempoMinimoQueda: number,
	VelocidadeCorrendoNoAr: number,

	VelocidadeCarregandoPesado: number,
	VelocidadeSoltarPesado: number,

	JanelaCancelamentoComboFinal: number,
	JanelaCancelamentoAtaquePesado: number,
	JanelaCancelAtaque: number,
	JanelaCancelAtaquePesado: number,
	CooldownCancel: number,
	TempoSegurandoM2ParaDefesa: number,
	VelocidadeReversaoCancelamento: number,

	CooldownComboLeve: number,
	CooldownAtaquePesado: number,
	CooldownBloqueio: number,

	VelocidadeAndando: number,
	VelocidadeCorrendo: number,
	VelocidadeBloqueando: number,
	VelocidadeDefesaQuebrada: number,
	VelocidadeAgachando: number,
	VelocidadeAparando: number,
	VelocidadeEscalando: number,

	VelocidadeInicialMovimento: number,
	AceleracaoAndando: number,
	AceleracaoCorrendo: number,
	DesaceleracaoMovimento: number,

	VelocidadeBaseAnimAndando: number,
	VelocidadeBaseAnimCorrendo: number,
	VelocidadeBaseAnimAgachando: number,
	VelocidadeBaseAnimBloqueando: number,

	CooldownDash: number,
	ForcaDash: number,
	VelocidadeAnimacaoDash: number,

	MagnitudeImpulsoAtaqueLeve: number,
	MagnitudeImpulsoAtaquePesado: number,
	MagnitudeImpulsoParry: number,
	DuracaoImpulsoAtaqueLeve: number,
	DuracaoImpulsoAtaquePesado: number,

	MagnitudeKnockbackLeve: number,
	MagnitudeKnockbackPesado: number,
	VisualizarHitbox: boolean,
}

local REGEX_ASSET_ID = "^rbxassetid://(%d+)$"
local ASSET_ID_INVALIDO = "rbxassetid://0000000000"

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modulo_Configuracoes = {}
local Modulo_ModosAnimacao = require(ReplicatedStorage:WaitForChild("Jogador"):WaitForChild("Animacoes"):WaitForChild("ModosAnimacao"))

Modulo_Configuracoes.ConfiguracaoGlobal = {

	TempoStunLeve = 0.3,
	TempoStunPesado = 0.6,
	TempoStunAparado = 0.7,
	TempoAparando = 0.7,

	JanelaParry = 0.2,
	CooldownParry = 1.0,

	TempoCarregarPesado = 0.2,
	JanelaCombo = 0.2,
	VelocidadeComboEspera = 0.4,
	TempoMinimoQueda = 0.28,
	VelocidadeCorrendoNoAr = 0.4,

	VelocidadeCarregandoPesado = 1.1,
	VelocidadeSoltarPesado = 1.0,

	JanelaCancelamentoComboFinal = 0.6,
	JanelaCancelamentoAtaquePesado = 0.5,
	JanelaCancelAtaque = 0.3,
	JanelaCancelAtaquePesado = 0.7,
	CooldownCancel = 1.0,
	TempoSegurandoM2ParaDefesa = 0.13,
	VelocidadeReversaoCancelamento = -1.5,

	CooldownComboLeve = 0.5,
	CooldownAtaquePesado = 2.0,
	CooldownBloqueio = 0.5,

	VelocidadeAndando = 12,
	VelocidadeCorrendo = 20,
	VelocidadeBloqueando = 6,
	VelocidadeDefesaQuebrada = 3,
	VelocidadeAgachando = 7,
	VelocidadeAparando = 3,
	VelocidadeEscalando = 12,

	VelocidadeInicialMovimento = 5,
	AceleracaoAndando = 20,
	AceleracaoCorrendo = 20,
	DesaceleracaoMovimento = 35,

	VelocidadeBaseAnimAndando = 15,
	VelocidadeBaseAnimCorrendo = 21,
	VelocidadeBaseAnimAgachando = 11,
	VelocidadeBaseAnimBloqueando = 6,

	CooldownDash = 1.5,
	ForcaDash = 45,
	VelocidadeAnimacaoDash = 1.0,
	JanelaCancelamentoDash = 0.2,
	DashCameraFixarY = true,

	MagnitudeImpulsoAtaqueLeve = 20,
	MagnitudeImpulsoAtaquePesado = 50,
	MagnitudeImpulsoParry = 25,
	DuracaoImpulsoAtaqueLeve = 0.1,
	DuracaoImpulsoAtaquePesado = 0.2,

	MagnitudeKnockbackLeve = 15,
	MagnitudeKnockbackPesado = 150,
	VisualizarHitbox = true,
}

Modulo_Configuracoes.ModoAnimacoes = Modulo_ModosAnimacao

function Modulo_Configuracoes.ValidarIdAnimacao(animId: string): boolean
	if type(animId) ~= "string" then
		return false
	end
	if animId == ASSET_ID_INVALIDO then
		return false
	end
	return animId:match(REGEX_ASSET_ID) ~= nil
end

function Modulo_Configuracoes.ModoExiste(nomeModo: string): boolean
	if type(nomeModo) ~= "string" then
		return false
	end
	return Modulo_Configuracoes.ModoAnimacoes[nomeModo] ~= nil
end

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

function Modulo_Configuracoes.ObterAnimacao(nomeModo: string, nomeAnimacao: string): string?

	local modo = Modulo_Configuracoes.ModoAnimacoes[nomeModo]
	if modo and modo.animacoes and modo.animacoes[nomeAnimacao] then
		local animId = modo.animacoes[nomeAnimacao]
		if Modulo_Configuracoes.ValidarIdAnimacao(animId) then
			return animId
		end
	end

	local base = Modulo_Configuracoes.ModoAnimacoes.Base
	if base and base.animacoes and base.animacoes[nomeAnimacao] then
		local animId = base.animacoes[nomeAnimacao]
		if Modulo_Configuracoes.ValidarIdAnimacao(animId) then
			return animId
		end
	end

	return nil
end

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

function Modulo_Configuracoes.AplicaImpulso(nomeModo: string): boolean
	local modo = Modulo_Configuracoes.ObterModoAnimacao(nomeModo)
	return modo and modo.aplicaImpulso or false
end

function Modulo_Configuracoes.AplicaKnockback(nomeModo: string): boolean
	local modo = Modulo_Configuracoes.ObterModoAnimacao(nomeModo)
	return modo and modo.aplicaKnockback or false
end

function Modulo_Configuracoes.TemCombo(nomeModo: string): boolean
	local modo = Modulo_Configuracoes.ObterModoAnimacao(nomeModo)
	return modo and modo.temCombo or false
end

function Modulo_Configuracoes.EhCombate(nomeModo: string): boolean
	local modo = Modulo_Configuracoes.ObterModoAnimacao(nomeModo)
	return modo and modo.tipo == "Combate" or false
end

function Modulo_Configuracoes.EhInteracao(nomeModo: string): boolean
	local modo = Modulo_Configuracoes.ObterModoAnimacao(nomeModo)
	return modo and modo.tipo == "Interacao" or false
end

function Modulo_Configuracoes.BloqueiaInteracao(nomeModo: string): boolean
	local modo = Modulo_Configuracoes.ObterModoAnimacao(nomeModo)
	if not modo then
		return false
	end
	return modo.tipo == "Combate" or modo.tipo == "Interacao"
end

function Modulo_Configuracoes.ObterConfiguracaoCombo(nomeModo: string): any?
	local modo = Modulo_Configuracoes.ObterModoAnimacao(nomeModo)
	if not modo or not modo.configCombo then
		return nil
	end

	local config = table.clone(modo.configCombo)
	config.janelaCombo = Modulo_Configuracoes.ObterConfiguracao("JanelaCombo") or 0.2

	return config
end

function Modulo_Configuracoes.ObterTipoAtaquePorIndice(_nomeModo: string, indice: number): string

	if indice >= 4 then
		return "AtaqueLeveFinal"
	end
	return "AtaqueLeve"
end

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

function Modulo_Configuracoes.PreCarregarAnimacoes(animator: Animator): { AnimationTrack }
	if not animator then
		warn("[Modulo_Configuracoes] Animator inválido para pré-carregamento")
		return {}
	end

	local tracks = {}
	local animacoes = Modulo_Configuracoes.ObterTodasAnimacoes()
	local animationInstance = Instance.new("Animation")

	for _, animId in ipairs(animacoes) do
		local sucesso, resultado = pcall(function()
			animationInstance.AnimationId = animId
			return animator:LoadAnimation(animationInstance)
		end)

		if sucesso and resultado then
			table.insert(tracks, resultado)
		else
			warn("[Modulo_Configuracoes] Falha ao pré-carregar animação: " .. animId)
		end
	end

	animationInstance:Destroy()
	return tracks
end

function Modulo_Configuracoes.ObterIdAnimacao(nomeModo: string, nomeAnimacao: string): string?
	local modo = Modulo_Configuracoes.ObterModoAnimacao(nomeModo)
	if not modo or not modo.animacoes then
		return nil
	end
	return modo.animacoes[nomeAnimacao]
end

return Modulo_Configuracoes
