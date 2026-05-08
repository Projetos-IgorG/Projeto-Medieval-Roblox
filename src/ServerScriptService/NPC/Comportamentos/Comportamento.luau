--!strict

--[[
    Script: Comportamento.luau
    Caminho: src/ServerScriptService/NPC/Comportamentos
    Responsabilidade: Define a interface comum dos comportamentos (IA server-side) e o registry para resolver por archetype.
    Uso: ModuleScript; require para tipos; cada comportamento concreto se registra via Registrar.
    Nao faz: Nao implementa logica especifica; apenas contrato + registry.
    Funcoes principais: Registrar, Obter
]]

export type ContextoNPC = {
	id: number,
	archetype: string,
	especie: string?,
	modelo: Model,
	humanoide: Humanoid,
	hostil: boolean,
	-- Estado livre por instancia, escrito pelo proprio comportamento.
	estado: { [string]: any },
	-- Conexoes RBXScript que o comportamento criou; usado para limpeza segura.
	conexoes: { RBXScriptConnection },
	-- Registro de tracks/animadores para limpeza.
	tracks: { AnimationTrack },
	-- Marcador opcional de "destruido" (usado por comportamentos com tasks pendentes).
	destruido: boolean?,
}

export type Comportamento = {
	id: string,
	-- Chamado uma vez quando o NPC nasce.
	iniciar: (ctx: ContextoNPC) -> (),
	-- Chamado pelo SchedulerServidor a cada IntervaloIA do archetype.
	-- nao deve agendar tasks; apenas decidir e aplicar via humanoide / atributos.
	atualizar: (ctx: ContextoNPC, dt: number) -> (),
	-- Chamado uma vez antes da remocao; deve liberar todos os recursos.
	destruir: (ctx: ContextoNPC) -> (),
}

local Registry: { [string]: Comportamento } = {}

local Modulo = {}

function Modulo.Registrar(comp: Comportamento)
	assert(type(comp.id) == "string" and comp.id ~= "", "Comportamento sem id")
	assert(type(comp.iniciar) == "function", "Comportamento sem 'iniciar'")
	assert(type(comp.atualizar) == "function", "Comportamento sem 'atualizar'")
	assert(type(comp.destruir) == "function", "Comportamento sem 'destruir'")
	Registry[comp.id] = comp
end

function Modulo.Obter(archetype: string): Comportamento?
	return Registry[archetype]
end

-- Helpers usados por todos os comportamentos para nao replicar codigo.
local Helpers = {}
Modulo.Helpers = Helpers

function Helpers.RastrearConexao(ctx: ContextoNPC, conn: RBXScriptConnection)
	table.insert(ctx.conexoes, conn)
end

function Helpers.LimparConexoes(ctx: ContextoNPC)
	for _, c in ctx.conexoes do
		if c.Connected then
			c:Disconnect()
		end
	end
	table.clear(ctx.conexoes)
end

function Helpers.PararTracks(ctx: ContextoNPC)
	for _, t in ctx.tracks do
		pcall(function()
			t:Stop(0.1)
		end)
	end
	table.clear(ctx.tracks)
end

return Modulo
