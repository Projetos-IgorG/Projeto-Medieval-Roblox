--!strict

--[[
	Script: GerenciadorNPC.luau
	Caminho: src/ServerScriptService/NPC/Gerenciamento
	Responsabilidade: Ciclo de vida dos NPCs (spawn, registro, morte, despawn)
	e integracao com o Scheduler e os Comportamentos.

	Correcoes em relacao ao codigo antigo:
	- Morte agora e tratada: ragdoll fisico + despawn automatico apos
	  NPC_TempoDespawnMorte segundos (configuravel por spawn; padrao 60s).
	- Desregistrar do GerenciadorEntidades e SEMPRE chamado no despawn
	  (antes era condicional ao modelo ainda ter Parent -> vazava registro).
	- comportamento.destruir e idempotente (flag interna), sem dupla chamada
	  entre morte e despawn.
	- armaId agora faz parte das opcoes de spawn (corrige a corrida em que o
	  Combate resolvia a arma antes do atributo ser setado).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local TiposNPC = require(ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC"):WaitForChild("Tipos"))
local RemotosNPC = require(ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC"):WaitForChild("RemotosNPC"))

local Comportamento = require(script.Parent.Parent:WaitForChild("Comportamentos"):WaitForChild("Comportamento"))
local ConstrutorModeloNPC = require(script.Parent:WaitForChild("ConstrutorModeloNPC"))
local Scheduler = require(script.Parent:WaitForChild("SchedulerServidor"))
local Ragdoll = require(ServerScriptService:WaitForChild("Combate"):WaitForChild("Servidor"):WaitForChild("Ragdoll"))

-- Auto-registram seus comportamentos ao serem required.
require(script.Parent.Parent:WaitForChild("Comportamentos"):WaitForChild("Animal"))
require(script.Parent.Parent:WaitForChild("Comportamentos"):WaitForChild("Dialogo"))
require(script.Parent.Parent:WaitForChild("Comportamentos"):WaitForChild("Combate"))

local GerenciadorEntidades = require(ServerScriptService:WaitForChild("Entidades"):WaitForChild("GerenciadorEntidades"))
local Especies = require(ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("Especies"))

local Gerenciador = {}

-- Tempo (em segundos) que o corpo do NPC fica no chao antes de despawnar.
local TEMPO_DESPAWN_MORTE_PADRAO = 60
local CHAVE_TEMPO_DESPAWN = "NPC_TempoDespawnMorte"

type Registro = {
	id: number,
	modelo: Model,
	ctx: Comportamento.ContextoNPC,
	comportamento: any,
	_morreu: boolean?,
	_comportamentoFinalizado: boolean?,
}

local registros: { [number]: Registro } = {}
local proximoId = 1

local DEBUG = false
local function dbg(...: any)
	if DEBUG then
		print("[GerenciadorNPC]", ...)
	end
end

-- =============================================================================
-- Helpers internos.
-- =============================================================================

local function obterTempoDespawn(modelo: Model): number
	local v = modelo:GetAttribute(CHAVE_TEMPO_DESPAWN)
	if typeof(v) == "number" and v > 0 then
		return v
	end
	return TEMPO_DESPAWN_MORTE_PADRAO
end

-- Finaliza o comportamento UMA unica vez (idempotente), independente de a
-- finalizacao vir da morte, do despawn manual ou do scheduler.
local function finalizarComportamento(registro: Registro)
	if registro._comportamentoFinalizado then
		return
	end
	registro._comportamentoFinalizado = true
	if registro.comportamento and registro.comportamento.destruir then
		local ok, err = pcall(registro.comportamento.destruir, registro.ctx)
		if not ok then
			warn("[GerenciadorNPC] Erro ao destruir comportamento:", err)
		end
	end
end

-- Morte do NPC: estado terminal + ragdoll + despawn agendado.
local function aoMorrer(registro: Registro)
	if registro._morreu then
		return
	end
	registro._morreu = true

	local modelo = registro.modelo
	dbg("NPC morreu:", registro.id, modelo.Name)

	-- Estado terminal (Sincronia nunca sobrescreve "Morto").
	modelo:SetAttribute(TiposNPC.Chaves.Estado, TiposNPC.Estado.Morto)

	-- Para a IA imediatamente e libera conexoes/maquina de combate.
	Scheduler.Cancelar(registro.id)
	finalizarComportamento(registro)

	-- Ragdoll fisico (conversao unica de joints; sem loops).
	Ragdoll.Ativar(modelo)

	-- Despawn automatico apos o tempo configurado.
	local id = registro.id
	task.delay(obterTempoDespawn(modelo), function()
		if registros[id] == registro then
			Gerenciador.DespawnNPC(id)
		end
	end)
end

-- =============================================================================
-- Spawn.
-- =============================================================================

function Gerenciador.SpawnNPC(opcoes: TiposNPC.OpcoesSpawn): Registro?
	local comportamento = Comportamento.Obter(opcoes.archetype)
	if not comportamento then
		warn("[GerenciadorNPC] Archetype sem comportamento registrado:", opcoes.archetype)
		return nil
	end

	local modelo = ConstrutorModeloNPC.Construir(opcoes)
	if not modelo then
		warn("[GerenciadorNPC] Falha ao construir modelo para archetype:", opcoes.archetype)
		return nil
	end

	local humanoide = modelo:FindFirstChildOfClass("Humanoid")
	if not humanoide then
		modelo:Destroy()
		warn("[GerenciadorNPC] Modelo sem Humanoid")
		return nil
	end

	local id = proximoId
	proximoId += 1

	-- Atributos base.
	modelo:SetAttribute(TiposNPC.Chaves.Id, id)
	modelo:SetAttribute(TiposNPC.Chaves.Archetype, opcoes.archetype)
	modelo:SetAttribute(TiposNPC.Chaves.Hostil, opcoes.hostil == true)
	modelo:SetAttribute(TiposNPC.Chaves.PodeAndar, opcoes.podeAndar ~= false)
	modelo:SetAttribute(TiposNPC.Chaves.PodeAtacar, opcoes.podeAtacar ~= false)
	modelo:SetAttribute(TiposNPC.Chaves.PodeDefender, opcoes.podeDefender == true)
	modelo:SetAttribute(TiposNPC.Chaves.PodeParry, opcoes.podeParry == true)
	modelo:SetAttribute(TiposNPC.Chaves.Estado, TiposNPC.Estado.Idle)

	-- FIX: arma definida ANTES do comportamento iniciar (sem corrida).
	local armaId = (opcoes :: any).armaId
	if typeof(armaId) == "string" and armaId ~= "" then
		modelo:SetAttribute(TiposNPC.Chaves.ArmaEquipadaId, armaId)
	end

	-- Tempo de despawn na morte (configuravel por spawn).
	local tempoDespawn = (opcoes :: any).tempoDespawnMorte
	if typeof(tempoDespawn) == "number" and tempoDespawn > 0 then
		modelo:SetAttribute(CHAVE_TEMPO_DESPAWN, tempoDespawn)
	else
		modelo:SetAttribute(CHAVE_TEMPO_DESPAWN, TEMPO_DESPAWN_MORTE_PADRAO)
	end

	modelo:PivotTo(opcoes.cframe)
	modelo.Parent = RemotosNPC.ObterPastaMundo() or Workspace

	local ctx: Comportamento.ContextoNPC = {
		id = id,
		archetype = opcoes.archetype,
		especie = opcoes.especie,
		modelo = modelo,
		humanoide = humanoide,
		hostil = opcoes.hostil == true,
		estado = {},
		conexoes = {},
		tracks = {},
	}

	local registro: Registro = {
		id = id,
		modelo = modelo,
		ctx = ctx,
		comportamento = comportamento,
	}
	registros[id] = registro

	-- Registro no GerenciadorEntidades (vida/atributos de entidade).
	if opcoes.registrarEntidade ~= false and opcoes.especie and Especies.Existe(opcoes.especie) then
		local okReg, entidade = pcall(GerenciadorEntidades.Registrar, modelo, opcoes.especie)
		if okReg and entidade then
			entidade:definirAtributo("Vida", humanoide.Health)
		end
	end

	-- Morte -> ragdoll + despawn agendado.
	local connDied = humanoide.Died:Connect(function()
		aoMorrer(registro)
	end)
	Comportamento.Helpers.RastrearConexao(ctx, connDied)

	-- Failsafe: modelo removido da arvore por fora (ex.: :Destroy() externo).
	local connAncestry = modelo.AncestryChanged:Connect(function(_, parent)
		if parent == nil and registros[id] == registro then
			Gerenciador.DespawnNPC(id)
		end
	end)
	Comportamento.Helpers.RastrearConexao(ctx, connAncestry)

	-- Inicia comportamento + agenda IA no scheduler.
	local okIniciar, errIniciar = pcall((comportamento :: any).iniciar, ctx)
	if not okIniciar then
		warn("[GerenciadorNPC] Erro ao iniciar comportamento:", errIniciar)
	end
	Scheduler.Agendar(registro)

	dbg("NPC spawnado:", id, modelo.Name, opcoes.archetype)
	return registro
end

-- =============================================================================
-- Despawn / consultas.
-- =============================================================================

function Gerenciador.DespawnNPC(id: number): boolean
	local registro = registros[id]
	if not registro then
		return false
	end
	registros[id] = nil

	Scheduler.Cancelar(id)
	finalizarComportamento(registro)

	-- FIX: Desregistrar SEMPRE (antes era condicional a modelo.Parent ~= nil,
	-- o que vazava o registro da entidade quando o modelo ja tinha sido
	-- destruido por fora).
	pcall(GerenciadorEntidades.Desregistrar, registro.modelo)

	if registro.modelo.Parent then
		registro.modelo:Destroy()
	end

	dbg("NPC despawnado:", id)
	return true
end

function Gerenciador.DespawnTodos()
	local ids = {}
	for id in registros do
		table.insert(ids, id)
	end
	for _, id in ids do
		Gerenciador.DespawnNPC(id)
	end
end

function Gerenciador.ObterRegistro(id: number): Registro?
	return registros[id]
end

function Gerenciador.ObterRegistroPorModelo(modelo: Model): Registro?
	local id = modelo:GetAttribute(TiposNPC.Chaves.Id)
	if typeof(id) == "number" then
		return registros[id]
	end
	return nil
end

-- Scheduler usa este callback para despawnar NPC "orfao" sem require ciclico.
Scheduler.DefinirCallbackDespawn(Gerenciador.DespawnNPC)

return Gerenciador
