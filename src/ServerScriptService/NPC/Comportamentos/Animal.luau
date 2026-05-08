--!strict

--[[
    Script: Animal.luau
    Caminho: src/ServerScriptService/NPC/Comportamentos
    Responsabilidade: IA simples de animal (vagar aleatorio; fugir se levar dano).
    Uso: ModuleScript; auto-registra ao ser required.
    Nao faz: Nao decide rotas complexas (sem pathfinding); apenas usa Humanoid:MoveTo.
    Funcoes principais: iniciar, atualizar, destruir
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TiposNPC = require(
	ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC"):WaitForChild("Tipos")
)
local Especies = require(
	ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("Especies")
)
local Comportamento = require(script.Parent:WaitForChild("Comportamento"))

type Ctx = Comportamento.ContextoNPC

local RAIO_VAGAR = 12
local INTERVALO_NOVO_DESTINO_MIN = 3
local INTERVALO_NOVO_DESTINO_MAX = 8
local DURACAO_FUGA = 4

local function escolherDestinoAleatorio(origem: Vector3): Vector3
	local angulo = math.random() * math.pi * 2
	local raio = math.random() * RAIO_VAGAR
	return origem + Vector3.new(math.cos(angulo) * raio, 0, math.sin(angulo) * raio)
end

local Animal: Comportamento.Comportamento = {
	id = TiposNPC.Archetype.Animal,

	iniciar = function(ctx: Ctx)
		local especieId = ctx.especie or "Galinha"
		local especie = Especies.Obter(especieId)
		if especie then
			ctx.humanoide.WalkSpeed = especie.movimento.andar
			ctx.humanoide.JumpHeight = especie.movimento.pulo
			ctx.estado.velocidadeCorrer = especie.movimento.correr
		else
			ctx.humanoide.WalkSpeed = 5
			ctx.estado.velocidadeCorrer = 9
		end

		ctx.estado.origem = ctx.modelo:GetPivot().Position
		ctx.estado.proximoDestino = 0
		ctx.estado.fugindoAte = 0
		ctx.modelo:SetAttribute(TiposNPC.Chaves.Estado, TiposNPC.Estado.Idle)

		-- Reage a dano: foge na direcao oposta do atacante mais recente.
		Comportamento.Helpers.RastrearConexao(
			ctx,
			ctx.humanoide.HealthChanged:Connect(function(novaSaude)
				if novaSaude <= 0 then
					return
				end
				if novaSaude < (ctx.estado.ultimaSaude or ctx.humanoide.MaxHealth) then
					ctx.estado.fugindoAte = os.clock() + DURACAO_FUGA
				end
				ctx.estado.ultimaSaude = novaSaude
			end)
		)
		ctx.estado.ultimaSaude = ctx.humanoide.Health
	end,

	atualizar = function(ctx: Ctx, _dt: number)
		if ctx.humanoide.Health <= 0 then
			ctx.modelo:SetAttribute(TiposNPC.Chaves.Estado, TiposNPC.Estado.Morto)
			return
		end

		local agora = os.clock()
		local fugindo = agora < (ctx.estado.fugindoAte or 0)

		if fugindo then
			ctx.humanoide.WalkSpeed = ctx.estado.velocidadeCorrer or 9
			ctx.modelo:SetAttribute(TiposNPC.Chaves.Estado, TiposNPC.Estado.Fugindo)
			-- Direcao de fuga: oposto da origem (afastando do ponto de spawn = simples).
			local pos = ctx.modelo:GetPivot().Position
			local origem: Vector3 = ctx.estado.origem
			local dir = (pos - origem)
			if dir.Magnitude < 0.1 then
				dir = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
			end
			dir = Vector3.new(dir.X, 0, dir.Z).Unit
			ctx.humanoide:MoveTo(pos + dir * 8)
			return
		end

		ctx.humanoide.WalkSpeed = (ctx.estado.velocidadeCorrer and ctx.estado.velocidadeCorrer * 0.5) or 5

		if agora >= (ctx.estado.proximoDestino or 0) then
			local destino = escolherDestinoAleatorio(ctx.estado.origem :: Vector3)
			ctx.humanoide:MoveTo(destino)
			ctx.modelo:SetAttribute(TiposNPC.Chaves.Estado, TiposNPC.Estado.Andando)
			ctx.estado.proximoDestino = agora
				+ INTERVALO_NOVO_DESTINO_MIN
				+ math.random() * (INTERVALO_NOVO_DESTINO_MAX - INTERVALO_NOVO_DESTINO_MIN)
		end
	end,

	destruir = function(ctx: Ctx)
		Comportamento.Helpers.LimparConexoes(ctx)
	end,
}

Comportamento.Registrar(Animal)

return Animal
