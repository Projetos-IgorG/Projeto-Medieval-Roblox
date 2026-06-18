--[[
    Script: IniciarNPC.server.luau
    Caminho: src/ServerScriptService/NPC/Gerenciamento
    Responsabilidade: Inicializa a infraestrutura de NPC do servidor (cria pasta no mundo, garante remotes, e expoe um RemoteEvent de Dev para o painel disparar spawn).
    Uso: Script de servidor; roda automaticamente.
    Nao faz: Nao implementa IA; apenas inicializacao e bridge externo.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RemotosNPC = require(
	ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC"):WaitForChild("RemotosNPC")
)
local TiposNPC = require(
	ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC"):WaitForChild("Tipos")
)

local GerenciadorNPC = require(script.Parent:WaitForChild("GerenciadorNPC"))

local DEBUG = false
local function dbg(...)
	if DEBUG then
		print(...)
	end
end

-- Garante pasta /Workspace/NPCs e pasta de remotes.
RemotosNPC.ObterPastaMundo()
local SpawnDevRemote = RemotosNPC.ObterRemote("SpawnNPCDev", "RemoteEvent") :: RemoteEvent
local DespawnDevRemote = RemotosNPC.ObterRemote("DespawnNPCDev", "RemoteEvent") :: RemoteEvent
local FlagsDevRemote = RemotosNPC.ObterRemote("AtualizarFlagsNPCDev", "RemoteEvent") :: RemoteEvent

local function podeUsarDev(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return true
	end
	return player:GetAttribute("AdminDev") == true
end

local function obterCFrameNaFrente(player: Player, distancia: number): CFrame?
	local char = player.Character
	if not char then
		return nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return nil
	end
	local frente = hrp.CFrame.LookVector
	frente = Vector3.new(frente.X, 0, frente.Z)
	if frente.Magnitude < 0.01 then
		frente = Vector3.new(0, 0, -1)
	end
	frente = frente.Unit
	local pos = hrp.Position + frente * math.max(distancia, 3)
	return CFrame.lookAt(pos, pos + frente)
end

SpawnDevRemote.OnServerEvent:Connect(function(player: Player, payload: any)
	if not podeUsarDev(player) then
		return
	end
	if typeof(payload) ~= "table" then
		return
	end

	local archetype = payload.archetype
	if archetype ~= TiposNPC.Archetype.Dialogo
		and archetype ~= TiposNPC.Archetype.Combate
		and archetype ~= TiposNPC.Archetype.Animal then
		return
	end

	local cframe = obterCFrameNaFrente(player, 6)
	if not cframe then
		return
	end

	local opcoes: TiposNPC.OpcoesSpawn = {
		archetype = archetype,
		cframe = cframe,
		especie = type(payload.especie) == "string" and payload.especie or nil,
		aparenciaDe = if archetype ~= TiposNPC.Archetype.Animal then player else nil,
		nome = type(payload.nome) == "string" and payload.nome or nil,
		hostil = payload.hostil == true,
		podeAndar = if typeof(payload.podeAndar) == "boolean" then payload.podeAndar else nil,
		podeAtacar = if typeof(payload.podeAtacar) == "boolean" then payload.podeAtacar else nil,
		podeDefender = if typeof(payload.podeDefender) == "boolean" then payload.podeDefender else nil,
		podeParry = if typeof(payload.podeParry) == "boolean" then payload.podeParry else nil,
	}

	GerenciadorNPC.SpawnNPC(opcoes)
end)

DespawnDevRemote.OnServerEvent:Connect(function(player: Player, payload: any)
	if not podeUsarDev(player) then
		warn(string.format("[DevNPC] Player %s tentou usar DespawnNPCDev sem permissao", player.Name))
		return
	end
	dbg(string.format("[DevNPC] Recebido pedido de despawn por %s. Payload: %s", player.Name, game:GetService("HttpService"):JSONEncode(payload)))
	if typeof(payload) == "number" then
		local sucesso = GerenciadorNPC.DespawnNPC(payload)
		dbg(string.format("[DevNPC] Despawn de NPC unico (ID %d): sucesso = %s", payload, tostring(sucesso)) )
	elseif typeof(payload) == "table" and payload.todos == true then
		local lista = GerenciadorNPC.Listar()
		dbg(string.format("[DevNPC] Despawn de todos os NPCs. Quantidade listada: %d", #lista))
		for _, reg in lista do
			local sucesso = GerenciadorNPC.DespawnNPC(reg.id)
			dbg(string.format("[DevNPC] Despawning NPC ID %d (Archetype %s): sucesso = %s", reg.id, reg.archetype, tostring(sucesso)))
		end
	else
		warn(string.format("[DevNPC] Payload de despawn invalido ou nao suportado: %s", typeof(payload)))
	end
end)

-- Atualiza flags de capacidade em TODOS os NPCs hostis ja spawnados (real-time toggles).
FlagsDevRemote.OnServerEvent:Connect(function(player: Player, payload: any)
	if not podeUsarDev(player) then
		warn(string.format("[DevNPC] Player %s tentou usar AtualizarFlagsNPCDev sem permissao", player.Name))
		return
	end
	if typeof(payload) ~= "table" then
		warn("[DevNPC] Payload de atualizacao de flags invalido")
		return
	end
	dbg(string.format("[DevNPC] Atualizando flags para NPCs ja spawnados. Payload: %s", game:GetService("HttpService"):JSONEncode(payload)))
	local count = 0
	for _, reg in GerenciadorNPC.Listar() do
		local modelo = reg.modelo
		if not modelo or not modelo.Parent then
			continue
		end
		local hostil = modelo:GetAttribute(TiposNPC.Chaves.Hostil) == true
		if reg.archetype ~= TiposNPC.Archetype.Combate or not hostil then
			continue
		end
		
		count += 1
		if typeof(payload.podeAndar) == "boolean" then
			modelo:SetAttribute(TiposNPC.Chaves.PodeAndar, payload.podeAndar)
		end
		if typeof(payload.podeAtacar) == "boolean" then
			modelo:SetAttribute(TiposNPC.Chaves.PodeAtacar, payload.podeAtacar)
		end
		if typeof(payload.podeDefender) == "boolean" then
			modelo:SetAttribute(TiposNPC.Chaves.PodeDefender, payload.podeDefender)
			-- Parry exige defender ativo.
			if not payload.podeDefender then
				modelo:SetAttribute(TiposNPC.Chaves.PodeParry, false)
			end
		end
		if typeof(payload.podeParry) == "boolean" then
			local defenderAtivo = modelo:GetAttribute(TiposNPC.Chaves.PodeDefender) == true
			modelo:SetAttribute(TiposNPC.Chaves.PodeParry, payload.podeParry and defenderAtivo)
		end
	end
	dbg(string.format("[DevNPC] Atualizadas flags de %d NPCs hostis de combate", count))
end)

-- Limpeza ao encerrar (jogadores saindo nao removem NPCs; servidor encerrar sim, naturalmente).
Players.PlayerRemoving:Connect(function(_player)
	-- nada por enquanto: NPCs persistem na sessao.
end)
