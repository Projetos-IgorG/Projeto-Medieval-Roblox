--!strict

--[[
    Script: GerenciadorEntidades.luau
    Caminho: src/ServerScriptService/Entidades
    Responsabilidade: Registry global das entidades vivas no servidor; aplica tick periodico (regen/dreno) e oferece consultas.
    Uso: ModuleScript; require para Registrar/Desregistrar/ObterPorModelo/ObterPorPlayer.
    Nao faz: Nao cria personagens nem decide quando spawnar entidades.
    Funcoes principais: Registrar, Desregistrar, ObterPorModelo, ObterPorPlayer, Listar, Iniciar
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Entidade = require(
	ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("Entidade")
)

type EntidadeImpl = Entidade.EntidadeImpl

local INTERVALO_TICK = 1.0 -- segundos; granularidade do drain/regen

local Gerenciador = {}

local entidadesPorModelo: { [Model]: EntidadeImpl } = {}
local entidades: { EntidadeImpl } = {}

local heartbeatConn: RBXScriptConnection? = nil
local acumulador = 0

local function garantirTick()
	if heartbeatConn then
		return
	end
	heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		acumulador += dt
		if acumulador < INTERVALO_TICK then
			return
		end
		local passo = acumulador
		acumulador = 0

		for i = #entidades, 1, -1 do
			local ent = entidades[i]
			if (ent :: any)._destruido or not ent.modelo or not ent.modelo.Parent then
				-- limpeza preguicosa
				table.remove(entidades, i)
				if ent.modelo then
					entidadesPorModelo[ent.modelo] = nil
				end
				if not (ent :: any)._destruido then
					ent:destruir()
				end
			else
				ent:tick(passo)
			end
		end

		if #entidades == 0 and heartbeatConn then
			heartbeatConn:Disconnect()
			heartbeatConn = nil
		end
	end)
end

function Gerenciador.Registrar(modelo: Model, especieId: string): EntidadeImpl
	local existente = entidadesPorModelo[modelo]
	if existente and not (existente :: any)._destruido then
		return existente
	end

	local ent = Entidade.novo(modelo, especieId)
	entidadesPorModelo[modelo] = ent
	table.insert(entidades, ent)
	garantirTick()
	return ent
end

function Gerenciador.Desregistrar(modelo: Model)
	local ent = entidadesPorModelo[modelo]
	if not ent then
		return
	end
	entidadesPorModelo[modelo] = nil
	for i, e in entidades do
		if e == ent then
			table.remove(entidades, i)
			break
		end
	end
	if not (ent :: any)._destruido then
		ent:destruir()
	end
end

function Gerenciador.ObterPorModelo(modelo: Model?): EntidadeImpl?
	if not modelo then
		return nil
	end
	return entidadesPorModelo[modelo]
end

function Gerenciador.ObterPorPlayer(player: Player): EntidadeImpl?
	local char = player.Character
	if not char then
		return nil
	end
	return entidadesPorModelo[char]
end

function Gerenciador.Listar(): { EntidadeImpl }
	return table.clone(entidades)
end

return Gerenciador
