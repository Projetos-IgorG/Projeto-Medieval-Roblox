--!strict

--[[
	Script: RegistroNPC.luau
	Caminho: src/ReplicatedStorage/Entidades/NPC
	Responsabilidade: Indice O(1) de NPC_Id para Model, valido no cliente e no
	    servidor. Elimina varreduras com GetDescendants() para resolver alvos.
	Uso: ModuleScript; chame RegistroNPC.Iniciar() uma vez por contexto e depois
	    use RegistroNPC.Obter(id).
	Nao faz: Nao cria, move nem destroi NPCs; apenas indexa os existentes.
	Funcoes principais: Iniciar, Obter, Adicionar, Remover
]]

local CollectionService = game:GetService("CollectionService")

local TAG_NPC = "NPC"
local CHAVE_ID = "NPC_Id"

local RegistroNPC = {}

local porId: { [number]: Model } = {}
local idDoModelo: { [Model]: number } = {}
local conexoes: { [Model]: { RBXScriptConnection } } = {}
local iniciado = false

local function desindexar(modelo: Model)
	local id = idDoModelo[modelo]
	if id ~= nil and porId[id] == modelo then
		porId[id] = nil
	end
	idDoModelo[modelo] = nil
end

local function indexar(modelo: Model)
	local id = modelo:GetAttribute(CHAVE_ID)
	if typeof(id) ~= "number" then
		desindexar(modelo)
		return
	end

	local anterior = idDoModelo[modelo]
	if anterior ~= nil and anterior ~= id and porId[anterior] == modelo then
		porId[anterior] = nil
	end

	idDoModelo[modelo] = id
	porId[id] = modelo
end

-- Seguro chamar varias vezes com o mesmo modelo.
function RegistroNPC.Adicionar(inst: Instance)
	if not inst:IsA("Model") or conexoes[inst] then
		return
	end

	local modelo = inst :: Model
	local lista: { RBXScriptConnection } = {}
	conexoes[modelo] = lista

	table.insert(
		lista,
		modelo:GetAttributeChangedSignal(CHAVE_ID):Connect(function()
			indexar(modelo)
		end)
	)
	table.insert(
		lista,
		modelo.Destroying:Connect(function()
			RegistroNPC.Remover(modelo)
		end)
	)

	indexar(modelo)
end

function RegistroNPC.Remover(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	local modelo = inst :: Model

	local lista = conexoes[modelo]
	if lista then
		for _, c in lista do
			if c.Connected then
				c:Disconnect()
			end
		end
		conexoes[modelo] = nil
	end

	desindexar(modelo)
end

function RegistroNPC.Obter(id: number): Model?
	local modelo = porId[id]
	if modelo and modelo.Parent then
		return modelo
	end
	if modelo then
		desindexar(modelo)
	end
	return nil
end

function RegistroNPC.Iniciar()
	if iniciado then
		return
	end
	iniciado = true

	for _, inst in CollectionService:GetTagged(TAG_NPC) do
		RegistroNPC.Adicionar(inst)
	end
	CollectionService:GetInstanceAddedSignal(TAG_NPC):Connect(RegistroNPC.Adicionar)
	CollectionService:GetInstanceRemovedSignal(TAG_NPC):Connect(RegistroNPC.Remover)
end

return RegistroNPC
