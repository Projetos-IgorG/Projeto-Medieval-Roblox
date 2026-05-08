--!strict

--[[
	Script: Combate.luau
	Caminho: src/StarterPlayer/StarterPlayerScripts/NPC/Views
	Responsabilidade: View do NPC de combate - toca SOMENTE animacoes de reacao
	    cliente-side (Aparado, Stunado, Aparando, DefesaQuebrada, Defendendo).
	    As demais animacoes (Idle, Andando, Correndo, Equipar, Desequipar,
	    AtaqueLeve) sao tocadas direto no Animator do servidor pelo
	    ControladorCombateNPC e replicadas para todos os clientes pelo Roblox.
	Uso: ModuleScript; auto-registra em ViewBase.
	Nao faz: Nao decide comportamento, nao toca locomocao.
	Funcoes principais: iniciar, atualizar, aoLOD, destruir
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TiposNPC = require(
	ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC"):WaitForChild("Tipos")
)
local IdsCombate = require(
	ReplicatedStorage:WaitForChild("Combate"):WaitForChild("Animacoes"):WaitForChild("IdsAnimacoesCombate")
)
local ViewBase = require(script.Parent:WaitForChild("ViewBase"))

type Ctx = ViewBase.ContextoView

local Punhos = (IdsCombate :: any).Punhos and (IdsCombate :: any).Punhos.animacoes or {}

local FADE_REACAO_IN = 0.14
local FADE_REACAO_OUT = 0.18
local FADE_REACAO_PARA_ATAQUE = 0.16

type Entry = { nome: string, id: string, looped: boolean }

-- Apenas reacoes cliente-side. Locomocao/equip/ataque vem do server Animator.
local function entryFor(estado: string): Entry?
	if estado == TiposNPC.Estado.Aparando then
		return { nome = "Aparando", id = Punhos.Aparar or Punhos.Defesa or "", looped = false }
	elseif estado == TiposNPC.Estado.Aparado then
		return { nome = "Aparado", id = Punhos.Aparado or Punhos.Stunado or "", looped = false }
	elseif estado == TiposNPC.Estado.DefesaQuebrada then
		return { nome = "DefesaQuebrada", id = Punhos.DefesaQuebrada or Punhos.Stunado or "", looped = false }
	elseif estado == TiposNPC.Estado.Stunado then
		return { nome = "Stunado", id = Punhos.Stunado or "", looped = false }
	elseif estado == TiposNPC.Estado.Defendendo then
		return { nome = "Defendendo", id = Punhos.Defesa or "", looped = true }
	end
	return nil
end

local function tocarEstado(ctx: Ctx)
	local estado = ctx.modelo:GetAttribute(TiposNPC.Chaves.Estado) or TiposNPC.Estado.Idle
	local entry = entryFor(estado :: string)
	if not entry then
		local tocando = ctx.estado.estadoTocando
		local trackAtual = tocando and ctx.tracks[tocando]
		local indoAtacar = estado == TiposNPC.Estado.Atacando
		if trackAtual and trackAtual.IsPlaying and not trackAtual.Looped and not indoAtacar then
			return
		end
		if ctx.estado.estadoTocando ~= nil then
			ctx.estado.estadoTocando = nil
			for _, t in ctx.tracks do
				if t.IsPlaying then
					t:Stop(if indoAtacar then FADE_REACAO_PARA_ATAQUE else FADE_REACAO_OUT)
				end
			end
		end
		return
	end
	if ctx.estado.estadoTocando == entry.nome then
		return
	end
	ctx.estado.estadoTocando = entry.nome

	local track = ViewBase.CarregarTrack(ctx, entry.nome, entry.id)
	if not track then
		return
	end
	for outro, t in ctx.tracks do
		if outro ~= entry.nome and t.IsPlaying then
			t:Stop(FADE_REACAO_OUT)
		end
	end
	track.Looped = entry.looped
	track:Play(FADE_REACAO_IN)
end

local Combate: ViewBase.View = {
	id = TiposNPC.Archetype.Combate,

	iniciar = function(ctx: Ctx)
		tocarEstado(ctx)
		ViewBase.RastrearConexao(
			ctx,
			ctx.modelo:GetAttributeChangedSignal(TiposNPC.Chaves.Estado):Connect(function()
				if ctx.lod == TiposNPC.LOD.Distante then
					return
				end
				tocarEstado(ctx)
			end)
		)
	end,

	atualizar = function(_ctx: Ctx, _dt: number, _distancia: number)
	end,

	aoLOD = function(ctx: Ctx, novo: string, _anterior: string)
		if novo == TiposNPC.LOD.Distante then
			ViewBase.PararTodasAsTracks(ctx, FADE_REACAO_OUT)
			ctx.estado.estadoTocando = nil
		else
			tocarEstado(ctx)
		end
	end,

	destruir = function(ctx: Ctx)
		ViewBase.LimparTudo(ctx)
	end,
}

ViewBase.RegistrarView(Combate)

return Combate
