--!strict

--[[
	Script: PingServer.server.luau
	Caminho: src/ServerScriptService/Latencia
	Responsabilidade: Mede a latencia (RTT) de cada jogador e publica o valor
	    saneado no atributo "RTT" do Player, em segundos. O valor e usado pela
	    compensacao de latencia do combate, entao precisa ser resistente a
	    manipulacao pelo cliente.
	Uso: Script de servidor; roda sozinho.
	Nao faz: Nao expoe o RTT para o cliente escrever e nao aplica o RTT em
	    nenhuma regra de gameplay.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DEBUG_ENABLED = false

-- Teto absoluto aceito pelo combate. Acima disso a compensacao viraria abuso.
local MAX_RTT = 0.25
-- Intervalo entre pings.
local INTERVALO_PING = 1.0
-- Quantas amostras entram no minimo movel.
local TAMANHO_JANELA = 5
-- Pings sem resposta sao descartados depois disso.
local VALIDADE_PING = 5.0
-- Converte GetNetworkPing() em RTT. Use 1 se a engine ja devolver ida e volta.
local FATOR_PING_ENGINE = 2
-- Folga sobre o teto da engine, para nao punir jitter legitimo.
local MARGEM_TETO = 0.05

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
	local novo = Instance.new("RemoteEvent")
	novo.Name = "PingEvent"
	novo.Parent = Remotos
	PingEvent = novo
end

type DadosJogador = {
	pendentes: { [number]: number },
	amostras: { number },
	seq: number,
}

local jogadores: { [Player]: DadosJogador } = {}

-- Teto que o cliente nao consegue inflar: vem da medicao da propria engine.
local function tetoDaEngine(player: Player): number
	local ok, ping = pcall(function()
		return player:GetNetworkPing()
	end)
	if not ok or typeof(ping) ~= "number" or ping <= 0 then
		return MAX_RTT
	end
	return math.min(ping * FATOR_PING_ENGINE + MARGEM_TETO, MAX_RTT)
end

local function publicarRTT(player: Player, dados: DadosJogador)
	local amostras = dados.amostras
	if #amostras == 0 then
		return
	end

	-- Minimo movel: atrasar uma resposta isolada nao muda nada.
	local menor = amostras[1]
	for i = 2, #amostras do
		if amostras[i] < menor then
			menor = amostras[i]
		end
	end

	local final = math.clamp(math.min(menor, tetoDaEngine(player)), 0, MAX_RTT)
	player:SetAttribute("RTT", final)

	DebugPrint(
		string.format(
			"%s: bruto=%.1fms minimo=%.1fms tetoEngine=%.1fms final=%.1fms",
			player.Name,
			amostras[#amostras] * 1000,
			menor * 1000,
			tetoDaEngine(player) * 1000,
			final * 1000
		)
	)
end

PingEvent.OnServerEvent:Connect(function(player, seq)
	if typeof(seq) ~= "number" then
		return
	end
	local dados = jogadores[player]
	if not dados then
		return
	end

	local t0 = dados.pendentes[seq]
	if not t0 then
		return
	end
	dados.pendentes[seq] = nil

	local rtt = os.clock() - t0
	if rtt < 0 then
		return
	end

	table.insert(dados.amostras, rtt)
	while #dados.amostras > TAMANHO_JANELA do
		table.remove(dados.amostras, 1)
	end

	publicarRTT(player, dados)
end)

local function configurarJogador(player: Player)
	jogadores[player] = { pendentes = {}, amostras = {}, seq = 0 }
	player:SetAttribute("RTT", 0.0)
end

local function removerJogador(player: Player)
	jogadores[player] = nil
end

Players.PlayerAdded:Connect(configurarJogador)
Players.PlayerRemoving:Connect(removerJogador)
for _, player in Players:GetPlayers() do
	configurarJogador(player)
end

task.spawn(function()
	while true do
		local agora = os.clock()
		for player, dados in jogadores do
			-- Expira pings sem resposta para a tabela nao crescer.
			for seq, t0 in dados.pendentes do
				if agora - t0 > VALIDADE_PING then
					dados.pendentes[seq] = nil
				end
			end

			dados.seq = (dados.seq + 1) % 1000
			dados.pendentes[dados.seq] = agora
			PingEvent:FireClient(player, dados.seq)

			-- Republica mesmo sem resposta nova: o teto da engine pode ter caido.
			publicarRTT(player, dados)
		end
		task.wait(INTERVALO_PING)
	end
end)
