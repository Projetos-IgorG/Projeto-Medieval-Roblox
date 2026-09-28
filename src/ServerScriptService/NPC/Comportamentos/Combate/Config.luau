--!strict

--[[
	Script: Config.luau (filho de Combate)
	Responsabilidade: Centraliza TODAS as constantes tunaveis do combate de NPC.
	Ajuste valores aqui; nenhum outro modulo define numeros magicos.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConfigCombate =
	require(ReplicatedStorage:WaitForChild("Combate"):WaitForChild("Configuracoes"):WaitForChild("ConfigCombate"))

local Global = ConfigCombate.ConfiguracaoGlobal

local Config = {
	-- ========================= Percepcao / alvo =========================
	RAIO_AGGRO = 35,
	-- Raio UNICO de desengajamento. (Antes havia RAIO_DESAGGRO=60 e
	-- RAIO_DESEQUIPAR=50 conflitando: o NPC mantinha o alvo mas desequipava.)
	RAIO_DESENGAJAR = 60,
	HITS_PARA_TROCAR_ALVO = 2,
	JANELA_MEMORIA_AGRESSOR = 6,

	-- ========================= Movimento ================================
	VELOCIDADE_ANDANDO = (Global.VelocidadeAndando or 12) :: number,
	VELOCIDADE_CORRENDO = (Global.VelocidadeCorrendo or 16) :: number,
	VELOCIDADE_BLOQUEANDO = (Global.VelocidadeBloqueando or 6) :: number,
	VELOCIDADE_APARANDO = (Global.VelocidadeAparando or 3) :: number,
	VELOCIDADE_BASE_ANIM_BLOQUEANDO = (Global.VelocidadeBaseAnimBloqueando or 6) :: number,
	VELOCIDADE_BASE_ANIM_ANDANDO = (Global.VelocidadeBaseAnimAndando or 15) :: number,
	VELOCIDADE_BASE_ANIM_CORRENDO = (Global.VelocidadeBaseAnimCorrendo or 21) :: number,
	DISTANCIA_CORRER_PADRAO = 20,
	TOLERANCIA_ALCANCE = 0.7,

	-- ========================= Orbita ===================================
	INTERVALO_ROLAGEM_ORBITA = 7,
	CHANCE_ORBITA = 0.45,
	DURACAO_ORBITA = 1.2,

	-- ========================= Bloqueio / parry =========================
	DURACAO_BLOQUEIO_MIN = 1.1,
	DURACAO_BLOQUEIO_MAX = 2.0,
	CHANCE_BLOQUEIO_POR_TICK = 0.18,
	COOLDOWN_BLOQUEIO = ((Global.CooldownBloqueio or 0.5) :: number) + 1.5,
	COOLDOWN_PREDICAO_BLOQUEIO = 0.4,
	ATRASO_BLOQUEIO_PREDITIVO = 0.28,
	JANELA_PREPARO_APOS_APARADO = 2.0,

	-- ========================= Ataque / combo ===========================
	INDICE_COMBO_MAX = 4,
	ESPERA_BAITING_MIN = 1.0,
	ESPERA_BAITING_MAX = 2.5,
	ESPERA_APOS_ACERTO_MIN = 0.2,
	ESPERA_APOS_ACERTO_MAX = 0.5,
	ATRASO_ATAQUE_APOS_PARRY = 0.4,
	-- Multiplicador do alcance para MANTER um combo ja iniciado.
	TOLERANCIA_COMBO_ALCANCE = 1.5,

	-- ========================= Validacao de hit =========================
	-- O tick do swing agora e estavel (unico escritor), entao a tolerancia
	-- cobre apenas imprecisao de float na replicacao do atributo.
	TOLERANCIA_TICK = 0.001,
	TOLERANCIA_DISTANCIA = 4,
	JANELA_HIT_EXTRA = 0.80,
	RTT_MAX = 1.5,
	COMPENSACAO_DISTANCIA_POR_RTT = 16,
	COMPENSACAO_DISTANCIA_MAX = 12,
	-- Segundos que um swing permanece no historico (hits atrasados de players lagados).
	RETENCAO_HISTORICO = 5,

	-- ========================= Arma =====================================
	DADOS_PUNHOS = {
		Nome = "Punhos",
		Dano = 4,
		Alcance = 4,
		ModoAnimacao = "Punhos",
	},
}

return Config
