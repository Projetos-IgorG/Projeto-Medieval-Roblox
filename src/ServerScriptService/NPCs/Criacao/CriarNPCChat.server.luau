-- ServerScriptService/ChatNPCSpawner.server.lua
-- Comandos:
--   /npc
--   /npc <vida> <nome> <modoCombate>
-- Ex.: /npc 50 Lutador UmaMaoEscudo
-- Requisitos: ReplicatedStorage/SpawnNPC (BindableEvent) criado pelo NPC_SimpleAI

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SPAWN_BINDABLE_NAME = "SpawnNPC"
local bindablesFolder = ReplicatedStorage:WaitForChild("Bindables")
local spawnBindable = bindablesFolder:WaitForChild(SPAWN_BINDABLE_NAME)

-- Permissões simples: permitir no Studio ou ao(s) usuário(s) especificado(s)
local ALLOW_IN_STUDIO = true
local ALLOWED_USER_IDS = {
	-- [12345678] = true,
}

local function canUse(plr)
	if ALLOW_IN_STUDIO and RunService:IsStudio() then return true end
	if ALLOWED_USER_IDS[plr.UserId] then return true end
	if game.CreatorId ~= 0 and plr.UserId == game.CreatorId then return true end
	return false
end

local function parseAndSpawn(plr, msg)
	msg = msg or ""
	if not msg:lower():match("^/npc") then return end
	if not canUse(plr) then return end

	local tokens = string.split(msg, " ")
	-- Defaults
	local vida = 50
	local nome = "Lutador"
	local modo = "Punhos"

	-- /npc <vida> <nome> <modo>
	if tokens[2] and tonumber(tokens[2]) then
		vida = tonumber(tokens[2]) or vida
	end
	if tokens[3] then
		nome = tokens[3]
	end
	if tokens[4] then
		modo = tokens[4]
	end

	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local ahead = 6
	local pos = hrp.Position + hrp.CFrame.LookVector * ahead
	local look = hrp.CFrame.LookVector
	local cf = CFrame.new(pos, pos + look)

	spawnBindable:Fire({
		vida = vida,
		nome = nome,
		modo = modo,
		cframe = cf,
	})
end

local connectedPlayers: { [Player]: RBXScriptConnection } = {}

local function connectPlayer(plr: Player)
	if connectedPlayers[plr] then return end
	connectedPlayers[plr] = plr.Chatted:Connect(function(msg)
		parseAndSpawn(plr, msg)
	end)
end

Players.PlayerAdded:Connect(connectPlayer)
Players.PlayerRemoving:Connect(function(plr)
	local conn = connectedPlayers[plr]
	if conn then
		conn:Disconnect()
		connectedPlayers[plr] = nil
	end
end)

-- Para jogadores já presentes (em reinícios parciais)
for _, plr in ipairs(Players:GetPlayers()) do
	connectPlayer(plr)
end
