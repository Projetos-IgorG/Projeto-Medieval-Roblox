--!strict

--[[
    Script: Animal.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/NPC/Views
    Responsabilidade: View de animal (toca Idle/Walk simples baseado na velocidade do Humanoid).
    Uso: ModuleScript; auto-registra em ViewBase.
    Nao faz: Nao implementa IA (server faz).
    Funcoes principais: iniciar, atualizar, aoLOD, destruir
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TiposNPC = require(ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC"):WaitForChild("Tipos"))
local IdsAnim =
	require(ReplicatedStorage:WaitForChild("Jogador"):WaitForChild("Animacoes"):WaitForChild("IdsAnimacoesGerais"))
local ViewBase = require(script.Parent:WaitForChild("ViewBase"))

type Ctx = ViewBase.ContextoView

-- Animais nao tem ids proprios ainda; reusamos as do "Base" como fallback
-- visual ate o usuario fornecer animacoes especificas por especie.
local IDLE_ID: string = (IdsAnim.Base and IdsAnim.Base.animacoes and IdsAnim.Base.animacoes.Idle) or ""
local WALK_ID: string = (IdsAnim.Base and IdsAnim.Base.animacoes and IdsAnim.Base.animacoes.Andando) or ""

local function tocar(ctx: Ctx, nome: string, assetId: string)
	local track = ViewBase.CarregarTrack(ctx, nome, assetId)
	if not track then
		return
	end
	if track.IsPlaying then
		return
	end
	-- Para outras tracks antes de tocar a nova.
	for outro, t in ctx.tracks do
		if outro ~= nome and t.IsPlaying then
			t:Stop(0.1)
		end
	end
	track.Looped = true
	track:Play(0.15)
end

local Animal: ViewBase.View = {
	id = TiposNPC.Archetype.Animal,

	iniciar = function(ctx: Ctx)
		tocar(ctx, "Idle", IDLE_ID)
	end,

	atualizar = function(ctx: Ctx, _dt: number, _distancia: number)
		local vel = ctx.humanoide.MoveDirection.Magnitude > 0.05 and ctx.humanoide.WalkSpeed or 0
		if vel > 0.5 then
			tocar(ctx, "Andando", WALK_ID)
		else
			tocar(ctx, "Idle", IDLE_ID)
		end
	end,

	aoLOD = function(ctx: Ctx, novo: string, _anterior: string)
		if novo == TiposNPC.LOD.Distante then
			ViewBase.PararTodasAsTracks(ctx, 0.1)
		end
	end,

	destruir = function(ctx: Ctx)
		ViewBase.LimparTudo(ctx)
	end,
}

ViewBase.RegistrarView(Animal)

return Animal
