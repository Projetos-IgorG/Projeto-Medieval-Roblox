--!strict

--[[
	Script: RateLimitAcoes.luau
	Caminho: src/ServerScriptService/Combate/Servidor
	Responsabilidade: Limita a taxa de acoes de combate por jogador, separando
	    por categoria para que trafego de sincronizacao nunca consuma o orcamento
	    de uma acao de intencao (ataque, bloqueio, esquiva).
	Uso: ModuleScript; RateLimitAcoes.Permitir(player, acao) antes de processar.
	Nao faz: Nao pune nem avisa o jogador; apenas descarta silenciosamente.
	Funcoes principais: Permitir, Limpar, DefinirCategoria
]]

local Players = game:GetService("Players")

local RateLimitAcoes = {}

type Orcamento = { max: number, janela: number }

-- Intencao: input direto do jogador. Baixo e rigido.
-- Fluxo: callbacks de fim de animacao e hitbox. Medio.
-- Sincronia: telemetria de movimento. Alto, nunca deve bloquear as outras.
local ORCAMENTOS: { [string]: Orcamento } = {
	Intencao = { max = 14, janela = 1.0 },
	Fluxo = { max = 45, janela = 1.0 },
	Sincronia = { max = 90, janela = 1.0 },
}

local CATEGORIA_PADRAO = "Intencao"

local CATEGORIA_POR_ACAO: { [string]: string } = {
	AtacarEmPe = "Intencao",
	AtacarAgachado = "Intencao",
	Bloquear = "Intencao",
	PararBloqueio = "Intencao",
	Agachar = "Intencao",
	Levantar = "Intencao",
	Pular = "Intencao",
	Correr = "Intencao",
	PararCorrer = "Intencao",
	Roll = "Intencao",
	Dash = "Intencao",
	Equipar = "Intencao",
	Desequipar = "Intencao",
	Fintar = "Intencao",

	QuebrarDefesa = "Fluxo",
	Aterrissar = "Fluxo",
	RollTerminou = "Fluxo",
	RollEarlyCancel = "Fluxo",
	DashTerminou = "Fluxo",
	DashEarlyCancel = "Fluxo",
	ComboHitbox = "Fluxo",
	ComboContinuado = "Fluxo",
	ComboTerminou = "Fluxo",
	ComboEarlyCancel = "Fluxo",
	HitboxAcerto = "Fluxo",

	SincronizarMovimento = "Sincronia",
	AjustarVelocidadeAnimacao = "Sincronia",
}

type Balde = { contagem: number, reset: number }

local dados: { [Player]: { [string]: Balde } } = {}

local function obterBalde(player: Player, categoria: string): Balde
	local porJogador = dados[player]
	if not porJogador then
		porJogador = {}
		dados[player] = porJogador
	end

	local balde = porJogador[categoria]
	if not balde then
		balde = { contagem = 0, reset = os.clock() }
		porJogador[categoria] = balde
	end

	return balde
end

-- Retorna false quando a acao deve ser descartada.
function RateLimitAcoes.Permitir(player: Player, acao: string): boolean
	local categoria = CATEGORIA_POR_ACAO[acao] or CATEGORIA_PADRAO
	local orcamento = ORCAMENTOS[categoria] or ORCAMENTOS[CATEGORIA_PADRAO]
	local balde = obterBalde(player, categoria)
	local agora = os.clock()

	if agora - balde.reset >= orcamento.janela then
		balde.contagem = 0
		balde.reset = agora
	end

	balde.contagem += 1
	return balde.contagem <= orcamento.max
end

function RateLimitAcoes.DefinirCategoria(acao: string, categoria: string)
	CATEGORIA_POR_ACAO[acao] = categoria
end

function RateLimitAcoes.Limpar(player: Player)
	dados[player] = nil
end

Players.PlayerRemoving:Connect(RateLimitAcoes.Limpar)

return RateLimitAcoes
