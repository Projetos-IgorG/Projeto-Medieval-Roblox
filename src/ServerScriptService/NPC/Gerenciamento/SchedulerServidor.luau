--!strict

--[[
	Script: SchedulerServidor.luau
	Caminho: src/ServerScriptService/NPC/Gerenciamento
	Responsabilidade: Um unico Heartbeat que atualiza a IA de todos os NPCs em
	intervalos configuraveis por archetype, e gerencia network ownership.

	Correcoes em relacao ao codigo antigo:
	- Removido o require lazy fragil de GerenciadorNPC dentro do tick
	  (dependencia circular implicita). Agora o GerenciadorNPC injeta um
	  callback de despawn via DefinirCallbackDespawn.
	- NPC com modelo fora da arvore e removido do scheduler e despawnado via
	  callback (sem vazar registro).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ConfigNPC = require(ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC"):WaitForChild("ConfigNPC"))

local Scheduler = {}

type Agendado = {
	registro: any,
	proximaIA: number,
	proximoOwnership: number,
}

local agendados: { [number]: Agendado } = {}
local heartbeatConn: RBXScriptConnection? = nil

-- Callback injetado pelo GerenciadorNPC (evita require circular).
local callbackDespawn: ((id: number) -> boolean)? = nil

function Scheduler.DefinirCallbackDespawn(fn: (id: number) -> boolean)
	callbackDespawn = fn
end

-- =============================================================================
-- Ownership.
-- =============================================================================

local function definirOwnership(modelo: Model, archetype: string)
	local hrp = modelo:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp or hrp.Anchored then
		return
	end

	local alvoOwnership: Player? = nil
	if archetype == "Dialogo" then
		-- Dialogo: jogador mais proximo simula a fisica (movimento suave perto).
		local pos = hrp.Position
		local melhor = math.huge
		for _, player in Players:GetPlayers() do
			local char = player.Character
			local charHRP = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if charHRP then
				local d = (charHRP.Position - pos).Magnitude
				if d < melhor and d < 150 then
					melhor = d
					alvoOwnership = player
				end
			end
		end
	end
	-- Animal/Combate: servidor (nil) — IA de combate precisa de fisica server-side.

	pcall(function()
		hrp:SetNetworkOwner(alvoOwnership)
	end)
end

-- =============================================================================
-- Tick global.
-- =============================================================================

local function tickGlobal()
	local agora = os.clock()
	for id, item in agendados do
		local registro = item.registro
		local modelo: Model = registro.modelo

		-- Modelo fora da arvore: remove do scheduler e despawna via callback.
		if not modelo.Parent then
			agendados[id] = nil
			if callbackDespawn then
				local fn = callbackDespawn
				task.spawn(function()
					fn(id)
				end)
			elseif registro.comportamento and registro.comportamento.destruir then
				pcall(registro.comportamento.destruir, registro.ctx)
			end
			continue
		end

		local archetype: string = registro.ctx.archetype

		if agora >= item.proximaIA then
			local intervaloIA = ConfigNPC.Obter(archetype, "IntervaloIA") or ConfigNPC.Padrao.IntervaloIA
			local dt = math.max(agora - (item.proximaIA - intervaloIA), intervaloIA)
			item.proximaIA = agora + intervaloIA
			if registro.comportamento and registro.comportamento.atualizar then
				local ok, err = pcall(registro.comportamento.atualizar, registro.ctx, dt)
				if not ok then
					warn("[SchedulerServidor] Erro no atualizar do NPC " .. tostring(id) .. ": " .. tostring(err))
				end
			end
		end

		if agora >= item.proximoOwnership then
			local intervaloOwnership = ConfigNPC.Obter(archetype, "IntervaloOwnership")
				or ConfigNPC.Padrao.IntervaloOwnership
			item.proximoOwnership = agora + intervaloOwnership
			definirOwnership(modelo, archetype)
		end
	end

	-- Sem NPCs: desliga o Heartbeat (zero custo com mundo vazio).
	if next(agendados) == nil and heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
end

local function garantirHeartbeat()
	if heartbeatConn then
		return
	end
	heartbeatConn = RunService.Heartbeat:Connect(tickGlobal)
end

-- =============================================================================
-- API.
-- =============================================================================

function Scheduler.Agendar(registro: any)
	local agora = os.clock()
	agendados[registro.id] = {
		registro = registro,
		proximaIA = agora,
		proximoOwnership = agora,
	}
	garantirHeartbeat()
end

function Scheduler.Cancelar(id: number)
	agendados[id] = nil
end

return Scheduler
