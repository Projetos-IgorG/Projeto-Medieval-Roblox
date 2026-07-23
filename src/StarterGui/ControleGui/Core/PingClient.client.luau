--!strict
--[[
    Script: PingClient.client.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/Latencia
    Responsabilidade: Responde imediatamente aos pings do servidor e exibe um painel visual se DEBUG_ENABLED for true.
    Uso: Roda automaticamente no cliente.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DEBUG_ENABLED = true -- Mude para true para exibir o painel visual de ping

local player = Players.LocalPlayer
local Remotos = ReplicatedStorage:WaitForChild("Remotos")
local PingEvent = Remotos:WaitForChild("PingEvent") :: RemoteEvent

-- Resposta automática ao servidor
PingEvent.OnClientEvent:Connect(function(seq)
	PingEvent:FireServer(seq)
end)

-- Painel visual de depuração de RTT
if DEBUG_ENABLED then
	local gui = Instance.new("ScreenGui")
	gui.Name = "PingGui"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(200, 50)
	frame.Position = UDim2.new(1, -210, 0, 12)
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -12, 1, -8)
	label.Position = UDim2.fromOffset(6, 4)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Text = "RTT: medindo..."
	label.Parent = frame

	local function getColor(ms: number)
		if ms <= 80 then
			return Color3.fromRGB(80, 220, 120) -- Verde
		elseif ms <= 150 then
			return Color3.fromRGB(255, 210, 70) -- Amarelo
		else
			return Color3.fromRGB(255, 95, 95) -- Vermelho
		end
	end

	local function atualizarDisplay()
		local rtt = player:GetAttribute("RTT") or 0.0
		local ms = math.round(rtt * 1000)
		label.Text = string.format("RTT: %d ms", ms)
		label.TextColor3 = getColor(ms)
	end

	player:GetAttributeChangedSignal("RTT"):Connect(atualizarDisplay)
	atualizarDisplay()
end
