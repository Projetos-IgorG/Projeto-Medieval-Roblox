--!strict

--[[
    Script: SchedulerCliente.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/NPC
    Responsabilidade: Loop centralizado client-side; descobre NPCs via tag/pasta, gerencia LOD/distancia, distribui atualizacoes e respeita o limite de ativos por archetype.
    Uso: ModuleScript; chame Iniciar() em IniciarNPC.client.luau.
    Nao faz: Nao toca animacoes nem cria models; orquestra controladores.
    Funcoes principais: Iniciar, Parar
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TiposNPC = require(
	ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC"):WaitForChild("Tipos")
)
local ConfigNPC = require(
	ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC"):WaitForChild("ConfigNPC")
)
local ControladorNPC = require(script.Parent:WaitForChild("ControladorNPC"))

local PLAYER_LOCAL = Players.LocalPlayer

local Scheduler = {}

local controladores: { [Model]: ControladorNPC.ControladorImpl } = {}
local conexoesGerais: { RBXScriptConnection } = {}
local heartbeatConn: RBXScriptConnection? = nil
local acumulador = 0
local rodando = false

local function rotuloLOD(distancia: number, archetype: string): string
	local rProx = ConfigNPC.Obter(archetype, "RaioProximo")
	local rMed = ConfigNPC.Obter(archetype, "RaioMedio")
	local rDes = ConfigNPC.Obter(archetype, "RaioDesativacao")
	if distancia > rDes then
		return TiposNPC.LOD.Distante
	end
	if distancia <= rProx then
		return TiposNPC.LOD.Proximo
	end
	if distancia <= rMed then
		return TiposNPC.LOD.Medio
	end
	return TiposNPC.LOD.Distante
end

local function distanciaJogador(modelo: Model): number
	local pp = modelo.PrimaryPart
	if not pp then
		pp = modelo:FindFirstChild("HumanoidRootPart") :: BasePart?
	end
	if not pp then
		return math.huge
	end
	local char = PLAYER_LOCAL.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return math.huge
	end
	return (pp.Position - hrp.Position).Magnitude
end

local function adicionar(modelo: Instance)
	if not modelo:IsA("Model") then
		return
	end
	if controladores[modelo] then
		return
	end
	local ctrl = ControladorNPC.novo(modelo)
	if not ctrl then
		return
	end
	controladores[modelo] = ctrl
end

local function remover(modelo: Instance)
	if not modelo:IsA("Model") then
		return
	end
	local ctrl = controladores[modelo]
	if not ctrl then
		return
	end
	controladores[modelo] = nil
	ctrl:destruir()
end

local function tickGlobal(dt: number)
	acumulador += dt
	if acumulador < ConfigNPC.Padrao.IntervaloAtualizacao then
		return
	end
	local passo = acumulador
	acumulador = 0

	-- 1) Categoriza por archetype com (controlador, distancia).
	type Item = { ctrl: ControladorNPC.ControladorImpl, distancia: number }
	local porArchetype: { [string]: { Item } } = {}

	for modelo, ctrl in controladores do
		if not modelo.Parent then
			controladores[modelo] = nil
			ctrl:destruir()
			continue
		end
		local d = distanciaJogador(modelo)
		local lista = porArchetype[ctrl.archetype]
		if not lista then
			lista = {}
			porArchetype[ctrl.archetype] = lista
		end
		table.insert(lista, { ctrl = ctrl, distancia = d })
	end

	-- 2) Para cada archetype, ordena por distancia e ativa apenas os MaxAtivos primeiros.
	for archetype, lista in porArchetype do
		table.sort(lista, function(a, b)
			return a.distancia < b.distancia
		end)
		local max = ConfigNPC.Obter(archetype, "MaxAtivosPorArchetype") or 999
		for indice, item in lista do
			local lod
			if indice > max then
				lod = TiposNPC.LOD.Distante
			else
				lod = rotuloLOD(item.distancia, archetype)
			end
			item.ctrl:definirLOD(lod)
			item.ctrl:atualizar(passo, item.distancia)
		end
	end
end

function Scheduler.Iniciar()
	if rodando then
		return
	end
	rodando = true

	-- Adiciona NPCs ja existentes na tag.
	for _, inst in CollectionService:GetTagged("NPC") do
		adicionar(inst)
	end

	table.insert(conexoesGerais, CollectionService:GetInstanceAddedSignal("NPC"):Connect(adicionar))
	table.insert(conexoesGerais, CollectionService:GetInstanceRemovedSignal("NPC"):Connect(remover))

	-- Tambem observa Workspace/NPCs para o caso de o tag nao estar presente.
	local pasta = workspace:WaitForChild("NPCs", 5)
	if pasta then
		for _, inst in pasta:GetChildren() do
			if inst:HasTag("NPC") == false and inst:IsA("Model") then
				adicionar(inst)
			end
		end
		table.insert(conexoesGerais, pasta.ChildAdded:Connect(function(inst)
			task.defer(adicionar, inst)
		end))
		table.insert(conexoesGerais, pasta.ChildRemoved:Connect(remover))
	end

	heartbeatConn = RunService.Heartbeat:Connect(tickGlobal)
end

function Scheduler.Parar()
	rodando = false
	for _, c in conexoesGerais do
		if c.Connected then
			c:Disconnect()
		end
	end
	table.clear(conexoesGerais)
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
	for modelo, ctrl in controladores do
		ctrl:destruir()
		controladores[modelo] = nil
	end
end

return Scheduler
