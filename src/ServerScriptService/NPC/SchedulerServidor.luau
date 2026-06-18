--!strict

--[[
    Script: SchedulerServidor.luau
    Caminho: src/ServerScriptService/NPC
    Responsabilidade: Loop centralizado que invoca atualizar() de todos os NPCs server-side, com fatia de tempo por archetype e re-avaliacao periodica de NetworkOwnership.
    Uso: ModuleScript; require em GerenciadorNPC; chamar Inscrever/Cancelar; iniciado automaticamente.
    Nao faz: Nao decide IA; apenas distribui chamadas.
    Funcoes principais: Inscrever, Cancelar, Iniciar, Parar
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TiposNPC = require(
	ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC"):WaitForChild("Tipos")
)
local ConfigNPC = require(
	ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC"):WaitForChild("ConfigNPC")
)
local Comportamento = require(script.Parent:WaitForChild("Comportamentos"):WaitForChild("Comportamento"))

type Ctx = Comportamento.ContextoNPC

type Inscricao = {
	ctx: Ctx,
	intervaloIA: number,
	proximaIA: number,
	proximaOwnership: number,
}

local Scheduler = {}

local inscricoes: { [number]: Inscricao } = {}
local heartbeatConn: RBXScriptConnection? = nil

local function jogadorMaisProximo(pos: Vector3): Player?
	local melhor: Player? = nil
	local melhorD = math.huge
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then
			local d = (hrp.Position - pos).Magnitude
			if d < melhorD then
				melhorD = d
				melhor = player
			end
		end
	end
	return melhor
end

local function ajustarOwnership(insc: Inscricao)
	local modelo = insc.ctx.modelo
	if not modelo or not modelo.Parent then
		return
	end
	local pp = modelo.PrimaryPart
	if not pp then
		return
	end
	local archetype = insc.ctx.archetype
	-- Animal e Combate: o servidor cuida. Combate no servidor evita exploit e desyncs/teleportes de física no knockback.
	if archetype == TiposNPC.Archetype.Animal or archetype == TiposNPC.Archetype.Combate then
		pcall(function()
			pp:SetNetworkOwner(nil)
		end)
		return
	end
	local alvoPlayer = jogadorMaisProximo(pp.Position)
	if alvoPlayer then
		pcall(function()
			pp:SetNetworkOwner(alvoPlayer)
		end)
	else
		pcall(function()
			pp:SetNetworkOwner(nil)
		end)
	end
end

local function tickGlobal(_dt: number)
	local agora = os.clock()
	for id, insc in inscricoes do
		local ctx = insc.ctx
		if not ctx.modelo or not ctx.modelo.Parent or not ctx.humanoide or ctx.humanoide.Parent == nil then
			inscricoes[id] = nil
			task.spawn(function()
				local gerNPC = script.Parent:FindFirstChild("GerenciadorNPC")
				if gerNPC and gerNPC:IsA("ModuleScript") then
					local ok, GerenciadorNPC = pcall(require, gerNPC)
					if ok and GerenciadorNPC and GerenciadorNPC.DespawnNPC then
						GerenciadorNPC.DespawnNPC(id)
						return
					end
				end
				local comp = Comportamento.Obter(ctx.archetype)
				if comp then
					pcall(comp.destruir, ctx)
				end
			end)
			continue
		end

		if agora >= insc.proximaOwnership then
			ajustarOwnership(insc)
			insc.proximaOwnership = agora + ConfigNPC.Padrao.IntervaloOwnership
		end

		if agora >= insc.proximaIA then
			local dt = insc.intervaloIA
			insc.proximaIA = agora + insc.intervaloIA
			local comp = Comportamento.Obter(ctx.archetype)
			if comp then
				local ok, err = pcall(comp.atualizar :: any, ctx, dt)
				if not ok then
					warn(string.format("[NPC] Erro no comportamento '%s' (id=%d): %s", ctx.archetype, id, tostring(err)))
				end
			end
		end
	end
end

local function garantirLoop()
	if heartbeatConn then
		return
	end
	heartbeatConn = RunService.Heartbeat:Connect(tickGlobal)
end

function Scheduler.Inscrever(ctx: Ctx)
	local intervalo = ConfigNPC.Obter(ctx.archetype, "IntervaloIA") or ConfigNPC.Padrao.IntervaloIA
	inscricoes[ctx.id] = {
		ctx = ctx,
		intervaloIA = intervalo,
		proximaIA = os.clock() + math.random() * intervalo, -- desfasa para evitar pico
		proximaOwnership = 0,
	}
	garantirLoop()
end

function Scheduler.Cancelar(id: number)
	inscricoes[id] = nil
end

function Scheduler.Listar(): { number }
	local ids: { number } = {}
	for id in inscricoes do
		table.insert(ids, id)
	end
	return ids
end

function Scheduler.Parar()
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
	table.clear(inscricoes)
end

return Scheduler
