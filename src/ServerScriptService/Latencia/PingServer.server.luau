--!strict
--[[
    Script: PingServer.server.luau
    Caminho: src/ServerScriptService/Latencia
    Responsabilidade: Mede periodicamente a latência (RTT) de cada jogador conectado usando RemoteEvents bidirecionais.
    Uso: Roda automaticamente no servidor. Salva o RTT em segundos como atributo "RTT" no Player.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local DEBUG_ENABLED = false

local function DebugPrint(...)
	if DEBUG_ENABLED then
		print("[PingServer]", ...)
	end
end

local Remotos = ReplicatedStorage:WaitForChild("Remotos")
local PingEvent: RemoteEvent
local existente = Remotos:FindFirstChild("PingEvent")
if existente and existente:IsA("RemoteEvent") then
	PingEvent = existente
else
	local newEvent = Instance.new("RemoteEvent")
	newEvent.Name = "PingEvent"
	newEvent.Parent = Remotos
	PingEvent = newEvent
end

local pendingPings: { [Player]: { [number]: number } } = {}
local seqCounters: { [Player]: number } = {}

PingEvent.OnServerEvent:Connect(function(player, seq)
	if typeof(seq) ~= "number" then
		return
	end

	local playerPending = pendingPings[player]
	if playerPending and playerPending[seq] then
		local t0 = playerPending[seq]
		playerPending[seq] = nil -- Consome o ping

		local rtt = os.clock() - t0
		player:SetAttribute("RTT", rtt)
		DebugPrint(string.format("Player %s RTT: %.1f ms", player.Name, rtt * 1000))
	end
end)

local function ConfigurarJogador(player: Player)
	pendingPings[player] = {}
	seqCounters[player] = 0
	player:SetAttribute("RTT", 0.0) -- Inicializa com zero
end

local function RemoverJogador(player: Player)
	pendingPings[player] = nil
	seqCounters[player] = nil
end

Players.PlayerAdded:Connect(ConfigurarJogador)
Players.PlayerRemoving:Connect(RemoverJogador)

for _, player in ipairs(Players:GetPlayers()) do
	ConfigurarJogador(player)
end

task.spawn(function()
	while true do
		local agora = os.clock()
		for _, player in ipairs(Players:GetPlayers()) do
			local playerPending = pendingPings[player]
			local seqCounter = seqCounters[player]

			if playerPending and seqCounter ~= nil then
				local seq = (seqCounter + 1) % 1000
				seqCounters[player] = seq
				playerPending[seq] = agora

				PingEvent:FireClient(player, seq)
			end
		end
		task.wait(1.0)
	end
end)
