--!strict

--[[
    Script: ControladorNPC.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/NPC
    Responsabilidade: Encapsula 1 NPC no cliente (cria contexto da View, troca LOD, faz teardown sem leak).
    Uso: ModuleScript; SchedulerCliente cria/destroi instancias.
    Nao faz: Nao decide comportamento; apenas roda View.
    Funcoes principais: novo, atualizar, definirLOD, destruir
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TiposNPC = require(ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC"):WaitForChild("Tipos"))
local ViewBase = require(script.Parent:WaitForChild("Views"):WaitForChild("ViewBase"))

local Controlador = {}
Controlador.__index = Controlador

export type ControladorImpl = {
	id: number,
	modelo: Model,
	archetype: string,
	view: ViewBase.View,
	ctx: ViewBase.ContextoView,
	destruido: boolean,

	atualizar: (self: ControladorImpl, dt: number, distancia: number) -> (),
	definirLOD: (self: ControladorImpl, lod: string) -> (),
	destruir: (self: ControladorImpl) -> (),
}

local function obterAnimator(humanoide: Humanoid): Animator
	local existente = humanoide:FindFirstChildOfClass("Animator")
	if existente then
		return existente
	end
	local novo = Instance.new("Animator")
	novo.Parent = humanoide
	return novo
end

function Controlador.novo(modelo: Model): ControladorImpl?
	local archetype = modelo:GetAttribute(TiposNPC.Chaves.Archetype)
	if typeof(archetype) ~= "string" then
		return nil
	end
	local view = ViewBase.ObterView(archetype)
	if not view then
		return nil
	end
	local humanoide = modelo:FindFirstChildOfClass("Humanoid")
	if not humanoide then
		return nil
	end
	local animator = obterAnimator(humanoide)

	local id = modelo:GetAttribute(TiposNPC.Chaves.Id)
	if typeof(id) ~= "number" then
		id = 0
	end

	local ctx: ViewBase.ContextoView = {
		id = id :: number,
		archetype = archetype,
		especie = modelo:GetAttribute("NPC_Especie") :: string?,
		modelo = modelo,
		humanoide = humanoide,
		animator = animator,
		tracks = {},
		conexoes = {},
		lod = TiposNPC.LOD.Distante,
		estado = {},
		destruido = false,
	}

	local self = setmetatable({
		id = ctx.id,
		modelo = modelo,
		archetype = archetype,
		view = view,
		ctx = ctx,
		destruido = false,
	}, Controlador) :: any

	-- Inicializa view ja em LOD distante (sem trabalho); SchedulerCliente promovera depois.
	do
		local resultado = { pcall(view.iniciar, ctx) }
		if not resultado[1] then
			warn(string.format("[NPC/Cliente] Erro em iniciar() de view '%s': %s", archetype, tostring(resultado[2])))
		end
	end

	return self :: ControladorImpl
end

function Controlador:atualizar(dt: number, distancia: number)
	if self.destruido then
		return
	end
	if self.ctx.lod == TiposNPC.LOD.Distante then
		return
	end
	do
		local resultado = { pcall(self.view.atualizar, self.ctx, dt, distancia) }
		if not resultado[1] then
			warn(string.format("[NPC/Cliente] Erro em atualizar() '%s': %s", self.archetype, tostring(resultado[2])))
		end
	end
end

function Controlador:definirLOD(lod: string)
	if self.destruido then
		return
	end
	if self.ctx.lod == lod then
		return
	end
	local anterior = self.ctx.lod
	self.ctx.lod = lod
	do
		local resultado = { pcall(self.view.aoLOD, self.ctx, lod, anterior) }
		if not resultado[1] then
			warn(string.format("[NPC/Cliente] Erro em aoLOD() '%s': %s", self.archetype, tostring(resultado[2])))
		end
	end
end

function Controlador:destruir()
	if self.destruido then
		return
	end
	self.destruido = true
	self.ctx.destruido = true
	pcall(self.view.destruir, self.ctx)
	-- Garante limpeza mesmo se a view esquecer.
	ViewBase.LimparTudo(self.ctx)
end

return Controlador
