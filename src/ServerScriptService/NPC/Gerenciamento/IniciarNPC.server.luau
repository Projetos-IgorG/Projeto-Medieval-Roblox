--!strict

--[[
	Script: IniciarNPC.server.luau
	Caminho: src/ServerScriptService/NPC/Gerenciamento
	Responsabilidade: Bootstrap do sistema de NPC + remotes de dev
	(SpawnNPCDev, DespawnNPCDev, AtualizarFlagsNPCDev).

	Novidade: o payload de spawn dev aceita `tempoDespawnMorte` (segundos que o
	corpo fica no chao apos a morte antes de despawnar; padrao 60).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local TiposNPC = require(ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC"):WaitForChild("Tipos"))
local RemotosNPC = require(ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC"):WaitForChild("RemotosNPC"))

local Gerenciamento = ServerScriptService:WaitForChild("NPC"):WaitForChild("Gerenciamento")
local GerenciadorNPC = require(Gerenciamento:WaitForChild("GerenciadorNPC"))

local DEBUG = false
local function dbg(...: any)
	if DEBUG then
		print("[IniciarNPC]", ...)
	end
end

local function podeUsarDev(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return true
	end
	if player:GetAttribute("AdminDev") == true then
		return true
	end
	return false
end

local function obterCFrameNaFrente(player: Player, distancia: number): CFrame?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return nil
	end
	local frente = hrp.CFrame.LookVector
	local pos = hrp.Position + frente * distancia
	return CFrame.lookAt(pos, Vector3.new(hrp.Position.X, pos.Y, hrp.Position.Z))
end

-- =============================================================================
-- Remotes de dev.
-- =============================================================================

local SpawnDevRemote = RemotosNPC.ObterRemote("SpawnNPCDev", "RemoteEvent") :: RemoteEvent
local DespawnDevRemote = RemotosNPC.ObterRemote("DespawnNPCDev", "RemoteEvent") :: RemoteEvent
local FlagsDevRemote = RemotosNPC.ObterRemote("AtualizarFlagsNPCDev", "RemoteEvent") :: RemoteEvent

SpawnDevRemote.OnServerEvent:Connect(function(player: Player, payload: any)
	if not podeUsarDev(player) then
		return
	end
	if typeof(payload) ~= "table" then
		return
	end

	local archetype = payload.archetype
	if
		archetype ~= TiposNPC.Archetype.Dialogo
		and archetype ~= TiposNPC.Archetype.Combate
		and archetype ~= TiposNPC.Archetype.Animal
	then
		return
	end

	local cframe = obterCFrameNaFrente(player, 6)
	if not cframe then
		return
	end

	local especieVal = if typeof(payload.especie) == "string" and payload.especie ~= "" then payload.especie else nil

	local opcoes: TiposNPC.OpcoesSpawn = {
		archetype = archetype,
		cframe = cframe,
		especie = especieVal,
		nome = if typeof(payload.nome) == "string" and payload.nome ~= "" then payload.nome else nil,
		hostil = payload.hostil == true,
		podeAndar = payload.podeAndar ~= false,
		podeAtacar = payload.podeAtacar ~= false,
		podeDefender = payload.podeDefender == true,
		podeParry = payload.podeParry == true,
		armaId = if typeof(payload.armaId) == "string" and payload.armaId ~= "" then payload.armaId else nil,
		tempoDespawnMorte = if typeof(payload.tempoDespawnMorte) == "number" and payload.tempoDespawnMorte > 0 then payload.tempoDespawnMorte else nil,
		registrarEntidade = if typeof(payload.registrarEntidade) == "boolean" then payload.registrarEntidade else nil,
		aparenciaDe = if (not especieVal or especieVal == "__Player__") and archetype ~= TiposNPC.Archetype.Animal then player else nil,
	}

	local registro = GerenciadorNPC.SpawnNPC(opcoes)
	if registro then
		dbg("Spawn dev por", player.Name, "->", registro.id)
	end
end)

DespawnDevRemote.OnServerEvent:Connect(function(player: Player, alvo: any)
	if not podeUsarDev(player) then
		return
	end
	if typeof(alvo) == "number" then
		GerenciadorNPC.DespawnNPC(alvo)
	elseif typeof(alvo) == "table" and alvo.todos == true then
		GerenciadorNPC.DespawnTodos()
	end
end)

FlagsDevRemote.OnServerEvent:Connect(function(player: Player, idNPC: any, flags: any)
	if not podeUsarDev(player) then
		return
	end
	if typeof(idNPC) ~= "number" or typeof(flags) ~= "table" then
		return
	end
	local registro = GerenciadorNPC.ObterRegistro(idNPC)
	if not registro then
		return
	end
	local modelo = registro.modelo

	-- Flags so fazem sentido em NPC de combate hostil.
	if modelo:GetAttribute(TiposNPC.Chaves.Archetype) ~= TiposNPC.Archetype.Combate then
		return
	end
	if modelo:GetAttribute(TiposNPC.Chaves.Hostil) ~= true then
		return
	end

	if typeof(flags.podeAndar) == "boolean" then
		modelo:SetAttribute(TiposNPC.Chaves.PodeAndar, flags.podeAndar)
	end
	if typeof(flags.podeAtacar) == "boolean" then
		modelo:SetAttribute(TiposNPC.Chaves.PodeAtacar, flags.podeAtacar)
	end
	if typeof(flags.podeDefender) == "boolean" then
		modelo:SetAttribute(TiposNPC.Chaves.PodeDefender, flags.podeDefender)
	end
	if typeof(flags.podeParry) == "boolean" then
		-- Parry exige defesa habilitada.
		local podeDefender = modelo:GetAttribute(TiposNPC.Chaves.PodeDefender) == true
		modelo:SetAttribute(TiposNPC.Chaves.PodeParry, flags.podeParry and podeDefender)
	end
end)

dbg("Sistema de NPC iniciado.")
