--!strict

--[[
    Script: GerenciadorNPC.luau
    Caminho: src/ServerScriptService/NPC/Gerenciamento
    Responsabilidade: API publica do sistema de NPC (SpawnNPC, DespawnNPC, Listar). Cria o Model, registra como Entidade e inscreve no SchedulerServidor.
    Uso: ModuleScript; require em qualquer codigo de servidor (DevPanel, quests, triggers).
    Nao faz: Nao implementa IA nem renderizacao; nao conhece UI.
    Funcoes principais: SpawnNPC, DespawnNPC, Listar, ObterPorId, ObterPorModelo
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TiposNPC = require(ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC"):WaitForChild("Tipos"))
local RemotosNPC = require(ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC"):WaitForChild("RemotosNPC"))
local Especies = require(ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("Especies"))

local Construtor = require(script.Parent:WaitForChild("ConstrutorModeloNPC"))
local Scheduler = require(script.Parent:WaitForChild("SchedulerServidor"))
local ComportamentosFolder = script.Parent.Parent:WaitForChild("Comportamentos")
local Comportamento = require(ComportamentosFolder:WaitForChild("Comportamento"))

-- Auto-carrega comportamentos para que se registrem.
require(ComportamentosFolder:WaitForChild("Dialogo"))
require(ComportamentosFolder:WaitForChild("Combate"))
require(ComportamentosFolder:WaitForChild("Animal"))

local Gerenciador_Entidades =
	require(script.Parent.Parent.Parent:WaitForChild("Entidades"):WaitForChild("GerenciadorEntidades"))

type OpcoesSpawn = TiposNPC.OpcoesSpawn
type Ctx = Comportamento.ContextoNPC

local Gerenciador = {}

local proximoId: number = 0
local registrosPorId: { [number]: Ctx } = {}
local registrosPorModelo: { [Model]: Ctx } = {}

local function gerarId(): number
	proximoId += 1
	return proximoId
end

local function escolherEspecie(opcoes: OpcoesSpawn): string
	if opcoes.archetype == TiposNPC.Archetype.Animal then
		return opcoes.especie or "Galinha"
	end
	-- Humanoides reusam a especie "Humano" do catalogo de Entidades.
	return "Humano"
end

local function inicializarHumanoide(modelo: Model): Humanoid?
	local hum = modelo:FindFirstChildOfClass("Humanoid")
	if not hum then
		return nil
	end
	return hum
end

function Gerenciador.SpawnNPC(opcoes: OpcoesSpawn): TiposNPC.RegistroNPC?
	assert(typeof(opcoes) == "table", "SpawnNPC espera uma tabela de opcoes")
	assert(typeof(opcoes.cframe) == "CFrame", "opcoes.cframe obrigatorio (CFrame)")
	assert(opcoes.archetype ~= nil, "opcoes.archetype obrigatorio")

	local comp = Comportamento.Obter(opcoes.archetype)
	if not comp then
		warn("[NPC] Archetype desconhecido: " .. tostring(opcoes.archetype))
		return nil
	end

	local modelo = Construtor.Construir(opcoes)
	if not modelo then
		warn("[NPC] Falha ao construir modelo para archetype " .. opcoes.archetype)
		return nil
	end

	local humanoide = inicializarHumanoide(modelo)
	if not humanoide then
		warn("[NPC] Modelo construido sem Humanoid; abortando spawn.")
		modelo:Destroy()
		return nil
	end

	local pasta = RemotosNPC.ObterPastaMundo()
	modelo.Parent = pasta

	-- Posiciona com seguranca (pivot pode falhar antes do parent).
	local sucessoPivot = pcall(function()
		modelo:PivotTo(opcoes.cframe)
	end)
	if not sucessoPivot then
		modelo:Destroy()
		return nil
	end

	local id = gerarId()
	local especieEnt = escolherEspecie(opcoes)
	-- Garante que a especie existe; se nao, ainda spawna mas avisa.
	if not Especies.Existe(especieEnt) then
		warn("[NPC] Especie '" .. especieEnt .. "' inexistente em Especies; entidade NAO sera registrada.")
	else
		Gerenciador_Entidades.Registrar(modelo, especieEnt)
	end

	-- Sincroniza Vida (Atributo) <-> Humanoid.Health para combate continuar funcionando.
	local conexoesEnt: { RBXScriptConnection } = {}
	table.insert(
		conexoesEnt,
		humanoide.HealthChanged:Connect(function(saude)
			local entidade = Gerenciador_Entidades.ObterPorModelo(modelo)
			if entidade then
				entidade:definirAtributo("Vida", saude)
			end
		end)
	)
	table.insert(
		conexoesEnt,
		humanoide.Died:Connect(function()
			modelo:SetAttribute(TiposNPC.Chaves.Estado, TiposNPC.Estado.Morto)
		end)
	)

	modelo:SetAttribute(TiposNPC.Chaves.Id, id)
	modelo:SetAttribute(TiposNPC.Chaves.Archetype, opcoes.archetype)
	modelo:SetAttribute(TiposNPC.Chaves.Estado, TiposNPC.Estado.Idle)
	modelo:SetAttribute(TiposNPC.Chaves.Hostil, opcoes.hostil == true)
	modelo:SetAttribute(TiposNPC.Chaves.AlvoRef, 0)
	-- Flags de capacidade. Default: andar e atacar SIM; defender e parry NAO.
	local podeAndar = if opcoes.podeAndar == nil then true else opcoes.podeAndar == true
	local podeAtacar = if opcoes.podeAtacar == nil then true else opcoes.podeAtacar == true
	local podeDefender = opcoes.podeDefender == true
	local podeParry = opcoes.podeParry == true and podeDefender
	modelo:SetAttribute(TiposNPC.Chaves.PodeAndar, podeAndar)
	modelo:SetAttribute(TiposNPC.Chaves.PodeAtacar, podeAtacar)
	modelo:SetAttribute(TiposNPC.Chaves.PodeDefender, podeDefender)
	modelo:SetAttribute(TiposNPC.Chaves.PodeParry, podeParry)
	modelo:AddTag("NPC")

	local ctx: Ctx = {
		id = id,
		archetype = opcoes.archetype,
		especie = opcoes.especie,
		modelo = modelo,
		humanoide = humanoide,
		hostil = opcoes.hostil == true,
		estado = {},
		conexoes = conexoesEnt,
		tracks = {},
	}

	registrosPorId[id] = ctx
	registrosPorModelo[modelo] = ctx

	-- Inicia comportamento e inscreve no scheduler.
	local ok, err = pcall(function()
		comp.iniciar(ctx)
	end)
	if not ok then
		warn(string.format("[NPC] Erro em iniciar() de '%s': %s", opcoes.archetype, tostring(err)))
	end
	Scheduler.Inscrever(ctx)

	-- Despawn automatico ao remover o modelo do mundo (ex: morte com cleanup externo).
	table.insert(
		conexoesEnt,
		modelo.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				Gerenciador.DespawnNPC(id)
			end
		end)
	)

	return {
		id = id,
		archetype = opcoes.archetype,
		especie = opcoes.especie,
		modelo = modelo,
	}
end

function Gerenciador.DespawnNPC(idOuModelo: number | Model): boolean
	local ctx: Ctx? = nil
	if typeof(idOuModelo) == "number" then
		ctx = registrosPorId[idOuModelo]
	elseif typeof(idOuModelo) == "Instance" and (idOuModelo :: Instance):IsA("Model") then
		ctx = registrosPorModelo[idOuModelo :: Model]
	end
	if not ctx then
		return false
	end

	Scheduler.Cancelar(ctx.id)

	local comp = Comportamento.Obter(ctx.archetype)
	if comp then
		pcall(function()
			comp.destruir(ctx)
		end)
	end

	for _, c in ctx.conexoes do
		if typeof(c) == "RBXScriptConnection" then
			if c.Connected then
				c:Disconnect()
			end
		elseif typeof(c) == "function" then
			pcall(c :: any)
		end
	end
	table.clear(ctx.conexoes)
	for _, t in ctx.tracks do
		pcall(function()
			t:Stop(0)
		end)
	end
	table.clear(ctx.tracks)

	registrosPorId[ctx.id] = nil
	registrosPorModelo[ctx.modelo] = nil

	if ctx.modelo and ctx.modelo.Parent then
		Gerenciador_Entidades.Desregistrar(ctx.modelo)
		ctx.modelo:Destroy()
	end

	return true
end

function Gerenciador.Listar(): { TiposNPC.RegistroNPC }
	local lista: { TiposNPC.RegistroNPC } = {}
	for id, ctx in registrosPorId do
		table.insert(lista, {
			id = id,
			archetype = ctx.archetype,
			especie = ctx.especie,
			modelo = ctx.modelo,
		})
	end
	return lista
end

function Gerenciador.ObterPorId(id: number): TiposNPC.RegistroNPC?
	local ctx = registrosPorId[id]
	if not ctx then
		return nil
	end
	return {
		id = ctx.id,
		archetype = ctx.archetype,
		especie = ctx.especie,
		modelo = ctx.modelo,
	}
end

function Gerenciador.ObterPorModelo(modelo: Model): TiposNPC.RegistroNPC?
	local ctx = registrosPorModelo[modelo]
	if not ctx then
		return nil
	end
	return {
		id = ctx.id,
		archetype = ctx.archetype,
		especie = ctx.especie,
		modelo = ctx.modelo,
	}
end

return Gerenciador
