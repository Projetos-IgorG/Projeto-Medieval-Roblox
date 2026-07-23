--!strict

--[[
    Script: Dialogo.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/NPC/Views
    Responsabilidade: View de NPC de dialogo (idle + head tracking quando jogador esta proximo).
    Uso: ModuleScript; auto-registra em ViewBase.
    Nao faz: Nao implementa arvore de dialogo (sera feito por outro sistema).
    Funcoes principais: iniciar, atualizar, aoLOD, destruir
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TiposNPC = require(ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC"):WaitForChild("Tipos"))
local IdsAnim =
	require(ReplicatedStorage:WaitForChild("Jogador"):WaitForChild("Animacoes"):WaitForChild("IdsAnimacoesGerais"))
local ViewBase = require(script.Parent:WaitForChild("ViewBase"))

type Ctx = ViewBase.ContextoView

local PLAYER_LOCAL = Players.LocalPlayer
local IDLE_ID: string = (IdsAnim.Base and IdsAnim.Base.animacoes and IdsAnim.Base.animacoes.Idle) or ""

local function tocarIdle(ctx: Ctx)
	local idle = ViewBase.CarregarTrack(ctx, "Idle", IDLE_ID)
	if idle and not idle.IsPlaying then
		idle:Play(0.2)
		idle.Looped = true
	end
end

local function aplicarHeadTracking(ctx: Ctx)
	local head = ctx.modelo:FindFirstChild("Head") :: BasePart?
	local char = PLAYER_LOCAL.Character
	local hrpJogador = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not head or not hrpJogador then
		return
	end
	local pp = ctx.modelo.PrimaryPart
	if not pp then
		return
	end
	-- R6: nao ha fisica de pescoco; aproximamos rotacionando o HRP suavemente
	-- so quando proximo. Implementacao simples (yaw apenas).
	local diff = hrpJogador.Position - pp.Position
	local plano = Vector3.new(diff.X, 0, diff.Z)
	if plano.Magnitude < 0.1 then
		return
	end
	local alvo = CFrame.lookAt(pp.Position, pp.Position + plano.Unit)
	-- Suaviza para evitar snap.
	pp.CFrame = pp.CFrame:Lerp(alvo, 0.08)
end

local Dialogo: ViewBase.View = {
	id = TiposNPC.Archetype.Dialogo,

	iniciar = function(ctx: Ctx)
		tocarIdle(ctx)
	end,

	atualizar = function(ctx: Ctx, _dt: number, distancia: number)
		if distancia < 12 then
			aplicarHeadTracking(ctx)
		end
	end,

	aoLOD = function(ctx: Ctx, novo: string, _anterior: string)
		if novo == TiposNPC.LOD.Distante then
			ViewBase.PararTodasAsTracks(ctx, 0.1)
		else
			tocarIdle(ctx)
		end
	end,

	destruir = function(ctx: Ctx)
		ViewBase.LimparTudo(ctx)
	end,
}

ViewBase.RegistrarView(Dialogo)

return Dialogo
