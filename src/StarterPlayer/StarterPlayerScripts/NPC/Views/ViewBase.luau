--!strict

--[[
    Script: ViewBase.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/NPC/Views
    Responsabilidade: Define o contrato comum de uma View (renderizador client-side por archetype) e helpers de animacao/limpeza compartilhados.
    Uso: ModuleScript; cada view concreta implementa esta interface e se registra em RegistrarView.
    Nao faz: Nao implementa archetype especifico.
    Funcoes principais: RegistrarView, ObterView, CarregarTrack, PararTodasAsTracks, RastrearConexao, LimparConexoes
]]

export type LOD = string

export type ContextoView = {
	id: number,
	archetype: string,
	especie: string?,
	modelo: Model,
	humanoide: Humanoid,
	animator: Animator,
	tracks: { [string]: AnimationTrack },
	conexoes: { RBXScriptConnection },
	lod: LOD,
	estado: { [string]: any },
	destruido: boolean?,
}

export type View = {
	id: string,
	-- Chamado uma vez quando o NPC entra no escopo do cliente.
	iniciar: (ctx: ContextoView) -> (),
	-- Chamado pelo SchedulerCliente em intervalo configurado.
	atualizar: (ctx: ContextoView, dt: number, distancia: number) -> (),
	-- Chamado quando o LOD muda (Distante/Medio/Proximo).
	aoLOD: (ctx: ContextoView, novo: LOD, anterior: LOD) -> (),
	-- Chamado uma vez antes de remover; deve liberar todos os recursos.
	destruir: (ctx: ContextoView) -> (),
}

local Registry: { [string]: View } = {}

local Modulo = {}

function Modulo.RegistrarView(view: View)
	assert(type(view.id) == "string" and view.id ~= "", "View sem id")
	assert(type(view.iniciar) == "function", "View sem 'iniciar'")
	assert(type(view.atualizar) == "function", "View sem 'atualizar'")
	assert(type(view.aoLOD) == "function", "View sem 'aoLOD'")
	assert(type(view.destruir) == "function", "View sem 'destruir'")
	Registry[view.id] = view
end

function Modulo.ObterView(archetype: string): View?
	return Registry[archetype]
end

function Modulo.CarregarTrack(ctx: ContextoView, nome: string, assetId: string): AnimationTrack?
	if ctx.tracks[nome] then
		return ctx.tracks[nome]
	end
	if not assetId or assetId == "" or assetId == "rbxassetid://0000000000" then
		return nil
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = assetId
	local sucesso, track = pcall(function()
		return ctx.animator:LoadAnimation(anim)
	end)
	if not sucesso or not track then
		return nil
	end
	ctx.tracks[nome] = track
	return track
end

function Modulo.PararTodasAsTracks(ctx: ContextoView, fade: number?)
	local f = fade or 0.1
	for _, t in ctx.tracks do
		pcall(function()
			t:Stop(f)
		end)
	end
end

function Modulo.RastrearConexao(ctx: ContextoView, conn: RBXScriptConnection)
	table.insert(ctx.conexoes, conn)
end

function Modulo.LimparConexoes(ctx: ContextoView)
	for _, c in ctx.conexoes do
		if c.Connected then
			c:Disconnect()
		end
	end
	table.clear(ctx.conexoes)
end

function Modulo.LimparTudo(ctx: ContextoView)
	Modulo.PararTodasAsTracks(ctx, 0)
	for _, t in ctx.tracks do
		pcall(function()
			t:Destroy()
		end)
	end
	table.clear(ctx.tracks)
	Modulo.LimparConexoes(ctx)
end

return Modulo
