--!strict

--[[
	Script: Combate (init.luau) — modulo PAI do combate de NPC.
	Caminho: src/ServerScriptService/NPC/Comportamentos/Combate

	Filhos (ModuleScripts):
	- Config     -> constantes tunaveis
	- Estado     -> estado por NPC + acesso lazy ao CombateServidor
	- Arma       -> resolucao de arma (tool/atributo/punhos)
	- Sincronia  -> UNICO escritor dos atributos NPC_*
	- Acoes      -> equipar/desequipar/atacar/combo/bloqueio
	- HitReport  -> validacao anti-cheat do NPC_HitReport
	- Movimento  -> orientacao, faixa de alcance, orbita, anim direcional
	- Decisao    -> IA (alvo, aggro, bloqueio preditivo, riposte, baiting)

	Uso: ModuleScript; auto-registra o comportamento "Combate" ao ser required.
	Tambem expoe a API publica de combate para codigo externo (quests, devpanel),
	equivalente ao antigo ControladorCombateNPC.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TiposNPC = require(ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC"):WaitForChild("Tipos"))

local Comportamento = require(script.Parent:WaitForChild("Comportamento"))
local Acoes = require(script:WaitForChild("Acoes"))
local Decisao = require(script:WaitForChild("Decisao"))

type Ctx = Comportamento.ContextoNPC

local Combate = {
	-- ============ Contrato de Comportamento ============
	id = TiposNPC.Archetype.Combate,

	iniciar = function(ctx: Ctx)
		Decisao.Iniciar(ctx)
	end,

	atualizar = function(ctx: Ctx, dt: number)
		Decisao.Tick(ctx, dt)
	end,

	destruir = function(ctx: Ctx)
		Decisao.Destruir(ctx)
	end,

	-- ============ API publica (ex-ControladorCombateNPC) ============
	EquiparArma = Acoes.EquiparArma,
	DesequiparArma = Acoes.DesequiparArma,
	Atacar = Acoes.Atacar,
	PararAtaque = Acoes.PararAtaque,
	Bloquear = Acoes.Bloquear,
	PararBloqueio = Acoes.PararBloqueio,
	TocarLocomocao = Acoes.TocarLocomocao,
	EstaArmaPronta = Acoes.EstaArmaPronta,
	EstaAtacando = Acoes.EstaAtacando,
	EstaEquipando = Acoes.EstaEquipando,
	EstaBloqueando = Acoes.EstaBloqueando,
	ObterAlcanceArmaEquipada = Acoes.ObterAlcanceArma,
	ObterModoAnimacao = Acoes.ObterModoAnimacao,
}

Comportamento.Registrar(Combate :: any)

return Combate
