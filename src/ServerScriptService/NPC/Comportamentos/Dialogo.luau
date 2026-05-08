--!strict

--[[
    Script: Dialogo.luau
    Caminho: src/ServerScriptService/NPC/Comportamentos
    Responsabilidade: Comportamento de NPC de dialogo (idle no lugar; head tracking e prompt sao responsabilidade da View no cliente).
    Uso: ModuleScript; auto-registra em Comportamento.Registrar quando required.
    Nao faz: Nao executa logica visual; apenas mantem estado replicado.
    Funcoes principais: iniciar, atualizar, destruir
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TiposNPC = require(
	ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC"):WaitForChild("Tipos")
)
local Comportamento = require(script.Parent:WaitForChild("Comportamento"))

type Ctx = Comportamento.ContextoNPC

local Dialogo: Comportamento.Comportamento = {
	id = TiposNPC.Archetype.Dialogo,

	iniciar = function(ctx: Ctx)
		ctx.modelo:SetAttribute(TiposNPC.Chaves.Estado, TiposNPC.Estado.Idle)
		ctx.humanoide.WalkSpeed = 0
		ctx.humanoide.JumpHeight = 0
	end,

	atualizar = function(_ctx: Ctx, _dt: number)
		-- NPC de dialogo nao decide nada por tick; permanece Idle.
	end,

	destruir = function(ctx: Ctx)
		Comportamento.Helpers.LimparConexoes(ctx)
	end,
}

Comportamento.Registrar(Dialogo)

return Dialogo
