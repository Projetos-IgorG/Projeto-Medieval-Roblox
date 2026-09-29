--!strict

--[[
    Script: SchedulerCliente.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/NPC
    Responsabilidade: Loop centralizado client-side; descobre NPCs via tag ou
        pasta, gerencia LOD por distancia com histerese, distribui atualizacoes
        e respeita o limite de ativos por archetype.
    Uso: ModuleScript; chame Iniciar() em IniciarNPC.client.luau.
    Nao faz: Nao toca animacoes nem cria models; orquestra controladores.
    Funcoes principais: Iniciar, Parar
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PastaNPC = ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC")
local TiposNPC = require(PastaNPC:WaitForChild("Tipos"))
local ConfigNPC = require(PastaNPC:WaitForChild("ConfigNPC"))
local RegistroNPC = require(PastaNPC:WaitForChild("RegistroNPC"))
local ControladorNPC = require(script.Parent:WaitForChild("ControladorNPC"))

local PLAYER_LOCAL = Players.LocalPlayer

-- Um NPC parado exatamente no limite de um raio ficava alternando de LOD todo
-- tick, destruindo e recriando tracks e WeaponModels. A histerese alarga o
-- raio de SAIDA do estado atual.
local MARGEM_HISTERESE = 1.12

local Scheduler = {}

type Registro = {
	ctrl: ControladorNPC.ControladorImpl,
	raiz: BasePart?,
	lod: string,
}

local registros: { [Model]: Registro } = {}
local pendentes: { [Model]: { RBXScriptConnection } } = {}
local conexoesGerais: { RBXScriptConnection } = {}
local heartbeatConn: RBXScriptConnection? = nil
local acumulador = 0
local rodando = false

-- =============================================================================
-- Distancia e LOD.
-- =============================================================================

local function obterRaiz(modelo: Model, registro: Registro): BasePart?
	local raiz = registro.raiz
	if raiz and raiz.Parent then
		return raiz
	end
	raiz = modelo.PrimaryPart or (modelo:FindFirstChild("HumanoidRootPart") :: BasePart?)
	registro.raiz = raiz
	return raiz
end

local function raizDoJogador(): BasePart?
	local char = PLAYER_LOCAL.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart? or nil
end

local function rotuloLOD(distancia: number, archetype: string, anterior: string): string
	local rProx = ConfigNPC.Obter(archetype, "RaioProximo")
	local rMed = ConfigNPC.Obter(archetype, "RaioMedio")
	local rDes = ConfigNPC.Obter(archetype, "RaioDesativacao")

	if anterior == TiposNPC.LOD.Proximo then
		rProx *= MARGEM_HISTERESE
	end
	if anterior ~= TiposNPC.LOD.Distante then
		rMed *= MARGEM_HISTERESE
		rDes *= MARGEM_HISTERESE
	end

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

-- =============================================================================
-- Registro de NPCs.
-- =============================================================================

local function limparPendente(modelo: Model)
	local conexoes = pendentes[modelo]
	if not conexoes then
		return
	end
	for _, conn in conexoes do
		if conn.Connected then
			conn:Disconnect()
		end
	end
	pendentes[modelo] = nil
end

local function adicionar(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	local modelo = inst :: Model
	if registros[modelo] then
		return
	end

	RegistroNPC.Adicionar(modelo)

	local function tentar(): boolean
		if not modelo.Parent then
			return false
		end
		if registros[modelo] then
			return true
		end
		if typeof(modelo:GetAttribute(TiposNPC.Chaves.Archetype)) ~= "string" then
			return false
		end
		if not modelo:FindFirstChildOfClass("Humanoid") then
			return false
		end

		local ctrl = ControladorNPC.novo(modelo)
		if not ctrl then
			return false
		end
		registros[modelo] = { ctrl = ctrl, raiz = nil, lod = TiposNPC.LOD.Distante }
		return true
	end

	if tentar() then
		return
	end

	-- Replicacao parcial: espera atributos e Humanoid chegarem.
	limparPendente(modelo)
	local conexoes: { RBXScriptConnection } = {}
	pendentes[modelo] = conexoes

	local function verificar()
		if tentar() then
			limparPendente(modelo)
		end
	end

	table.insert(conexoes, modelo:GetAttributeChangedSignal(TiposNPC.Chaves.Archetype):Connect(verificar))
	table.insert(
		conexoes,
		modelo.ChildAdded:Connect(function(child)
			if child:IsA("Humanoid") then
				verificar()
			end
		end)
	)
	table.insert(
		conexoes,
		modelo.Destroying:Connect(function()
			limparPendente(modelo)
		end)
	)
end

local function remover(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	local modelo = inst :: Model

	limparPendente(modelo)
	RegistroNPC.Remover(modelo)

	local registro = registros[modelo]
	if not registro then
		return
	end
	registros[modelo] = nil
	registro.ctrl:destruir()
end

-- =============================================================================
-- Tick. Buffers reciclados para nao pressionar o GC.
-- =============================================================================

type Item = { registro: Registro, distancia: number }

local porArchetype: { [string]: { Item } } = {}
local pool: { Item } = {}
local poolN = 0

local function obterItem(): Item
	if poolN > 0 then
		local it = pool[poolN]
		pool[poolN] = nil
		poolN -= 1
		return it
	end
	return { registro = nil :: any, distancia = 0 }
end

local function devolverLista(lista: { Item })
	for i = #lista, 1, -1 do
		local it = lista[i]
		it.registro = nil :: any
		it.distancia = 0
		poolN += 1
		pool[poolN] = it
		lista[i] = nil
	end
end

local function ordenarPorDistancia(a: Item, b: Item): boolean
	return a.distancia < b.distancia
end

local function tickGlobal(dt: number)
	acumulador += dt
	local intervalo = ConfigNPC.Padrao.IntervaloAtualizacao
	if acumulador < intervalo then
		return
	end

	local passo = acumulador
	-- Subtrai em vez de zerar para nao acumular drift de timing.
	acumulador -= intervalo
	if acumulador > intervalo then
		acumulador = 0
	end

	local raizJogador = raizDoJogador()

	for modelo, registro in registros do
		if not modelo.Parent then
			registros[modelo] = nil
			registro.ctrl:destruir()
			continue
		end

		local distancia = math.huge
		local raiz = obterRaiz(modelo, registro)
		if raiz and raizJogador then
			distancia = (raiz.Position - raizJogador.Position).Magnitude
		end

		local archetype = registro.ctrl.archetype
		local lista = porArchetype[archetype]
		if not lista then
			lista = {}
			porArchetype[archetype] = lista
		end

		local item = obterItem()
		item.registro = registro
		item.distancia = distancia
		lista[#lista + 1] = item
	end

	for archetype, lista in porArchetype do
		local total = #lista
		if total == 0 then
			continue
		end

		local max = ConfigNPC.Obter(archetype, "MaxAtivosPorArchetype") or 999
		-- So precisa ordenar quando ha mais NPCs do que vagas.
		if total > max then
			table.sort(lista, ordenarPorDistancia)
		end

		for indice, item in lista do
			local registro = item.registro
			local lod = if indice > max
				then TiposNPC.LOD.Distante
				else rotuloLOD(item.distancia, archetype, registro.lod)
			registro.lod = lod
			registro.ctrl:definirLOD(lod)
			registro.ctrl:atualizar(passo, item.distancia)
		end

		devolverLista(lista)
	end
end

-- =============================================================================
-- Ciclo de vida.
-- =============================================================================

function Scheduler.Iniciar()
	if rodando then
		return
	end
	rodando = true

	RegistroNPC.Iniciar()

	for _, inst in CollectionService:GetTagged("NPC") do
		adicionar(inst)
	end
	table.insert(conexoesGerais, CollectionService:GetInstanceAddedSignal("NPC"):Connect(adicionar))
	table.insert(conexoesGerais, CollectionService:GetInstanceRemovedSignal("NPC"):Connect(remover))

	-- Fallback para NPCs em Workspace/NPCs sem a tag.
	local function escutarPasta(pasta: Folder)
		for _, inst in pasta:GetChildren() do
			if inst:IsA("Model") and not inst:HasTag("NPC") then
				adicionar(inst)
			end
		end
		table.insert(
			conexoesGerais,
			pasta.ChildAdded:Connect(function(inst)
				task.defer(adicionar, inst)
			end)
		)
		table.insert(conexoesGerais, pasta.ChildRemoved:Connect(remover))
	end

	local pastaNPCs = workspace:FindFirstChild("NPCs")
	if pastaNPCs and pastaNPCs:IsA("Folder") then
		escutarPasta(pastaNPCs)
	else
		local conn: RBXScriptConnection
		conn = workspace.ChildAdded:Connect(function(child: Instance)
			if child.Name == "NPCs" and child:IsA("Folder") then
				conn:Disconnect()
				escutarPasta(child :: Folder)
			end
		end)
		table.insert(conexoesGerais, conn)
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

	for modelo in pendentes do
		limparPendente(modelo)
	end

	for modelo, registro in registros do
		registro.ctrl:destruir()
		registros[modelo] = nil
	end

	acumulador = 0
end

return Scheduler
