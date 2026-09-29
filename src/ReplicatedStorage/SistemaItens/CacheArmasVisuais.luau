--!strict

--[[
	Script: CacheArmasVisuais.luau
	Caminho: src/ReplicatedStorage/SistemaItens
	Responsabilidade: Constroi uma unica vez por item o Model visual limpo da
	    arma (sem scripts, sem colisao, partes ja normalizadas) e entrega clones
	    baratos para as Views de NPC e para efeitos locais.
	Uso: ModuleScript; CacheArmasVisuais.Clonar(idItem) devolve um Model novo
	    pronto para ancorar, ou nil se o item nao tiver visual.
	Nao faz: Nao ancora, nao cria Motor6D e nao decide qual mao usa a arma.
	Funcoes principais: Clonar, Obter, Limpar
]]

local ConstrutorTools = require(script.Parent:WaitForChild("ConstrutorTools"))

local CacheArmasVisuais = {}

local templates: { [string]: Model } = {}
local semVisual: { [string]: boolean } = {}

local function ehDescartavel(inst: Instance): boolean
	return inst:IsA("BaseScript") or inst:IsA("ProximityPrompt") or inst:IsA("Configuration")
end

local function normalizarPartes(raiz: Model)
	for _, d in raiz:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = if d.Name == "HitboxPart" then 1 else 0
			d.Anchored = false
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
		elseif ehDescartavel(d) then
			d:Destroy()
		end
	end
end

local function construir(id: string): Model?
	local tool = ConstrutorTools.CriarTool(id)
	if not tool then
		return nil
	end

	local visual = Instance.new("Model")
	visual.Name = "WeaponVisual"

	local temWeaponModel = tool:FindFirstChild("WeaponModel") ~= nil

	-- GetChildren devolve um snapshot, entao reparentar aqui e seguro.
	for _, filho in tool:GetChildren() do
		if ehDescartavel(filho) then
			continue
		end

		if filho:IsA("Model") and filho.Name == "WeaponModel" then
			for _, sub in filho:GetChildren() do
				if not ehDescartavel(sub) then
					sub.Parent = visual
				end
			end
		elseif temWeaponModel and filho.Name == "Handle" then
			-- O Handle do WeaponModel manda; o da Tool e descartado.
			continue
		else
			filho.Parent = visual
		end
	end

	tool:Destroy()

	if not visual:FindFirstChild("Handle") then
		visual:Destroy()
		return nil
	end

	-- Normaliza no template: os clones ja nascem prontos.
	normalizarPartes(visual)
	return visual
end

-- Template compartilhado. NAO modifique nem destrua o retorno.
function CacheArmasVisuais.Obter(id: string?): Model?
	if not id or id == "" or semVisual[id] then
		return nil
	end

	local existente = templates[id]
	if existente then
		return existente
	end

	local novo = construir(id)
	if not novo then
		semVisual[id] = true
		return nil
	end

	templates[id] = novo
	return novo
end

function CacheArmasVisuais.Clonar(id: string?): Model?
	local template = CacheArmasVisuais.Obter(id)
	return template and template:Clone() or nil
end

-- Use apos hot reload do catalogo de itens.
function CacheArmasVisuais.Limpar()
	for id, template in templates do
		template:Destroy()
		templates[id] = nil
	end
	table.clear(semVisual)
end

return CacheArmasVisuais
