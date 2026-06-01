--!strict

--[[
    Script: TimingsAtaqueNPC.luau
    Caminho: src/ReplicatedStorage/Combate/Configuracoes
    Responsabilidade: Tabela estatica de timings (em segundos) para cada animacao
        de combate do NPC. O servidor usa estes valores para agendar hitbox e
        liberacao de combo SEM precisar de Animator nem MarkerReachedSignal
        (toda a animacao acontece no cliente; servidor so cuida da logica).
    Uso: ModuleScript; require(TimingsAtaqueNPC).Punhos.AtaqueLeve etc.
    Nao faz: Nao toca animacoes; somente fornece dados.
]]

local Timings = {}

-- Punhos: usado por NPCs sem arma especifica (default).
Timings.Punhos = {
	-- Equipar/desequipar: tempo total ate considerar arma "pronta" no servidor.
	-- O cliente sincroniza visual usando markers da propria animacao local.
	Equipar = {
		Duracao = 0.55,
	},
	Desequipar = {
		Duracao = 0.45,
	},
	-- AtaqueLeve: 1 swing.
	-- AtrasoHit = quando ativar hitbox apos inicio do swing.
	-- DuracaoHit = quanto tempo a hitbox fica ativa.
	-- Duracao = quando o swing termina (libera proximo combo).
	-- ContinuacaoCombo = janela apos Duracao em que outra chamada AtacarLeve
	--     conta como continuacao (incrementa indice).
	AtaqueLeve = {
		AtrasoHit = 0.20,
		DuracaoHit = 0.30,
		Duracao = 0.65,
		ContinuacaoCombo = 0.45,
	},
}

-- Espadas/UmaMao usam a mesma referencia por enquanto. Ajustar se necessario.
Timings.UmaMao = Timings.Punhos
Timings.UmaMaoEscudo = Timings.Punhos

function Timings.ObterPorArma(modoAnimacao: string?): typeof(Timings.Punhos)
	if modoAnimacao and (Timings :: any)[modoAnimacao] then
		return (Timings :: any)[modoAnimacao]
	end
	return Timings.Punhos
end

return Timings
