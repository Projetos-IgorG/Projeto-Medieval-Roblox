--[[
Script: CatalogoItens.luau
Caminho: src/ReplicatedStorage/Dados/Itens/CatalogoItens
Responsabilidade: Junta os catalogos por tipo (modulos filhos) numa tabela unica indexada por Id.
Uso: ModuleScript; require e use CatalogoItens.Get(id), .PorTipo(tipo) ou .Todos().
Nao faz: Nao guarda item direto; cada item vive no modulo filho do seu Tipo.
]]

local CatalogoItens = {}

local porId = {}
local porTipo = {}

-- Carrega automaticamente cada modulo filho (Material, Tool, Equipment, ...).
for _, modulo in ipairs(script:GetChildren()) do
	if modulo:IsA("ModuleScript") then
		local itens = require(modulo)
		for id, dados in pairs(itens) do
			if porId[id] then
				warn(("[CatalogoItens] Id duplicado: %q (modulo %s)"):format(id, modulo.Name))
			end
			dados.Id = id
			porId[id] = dados
			porTipo[dados.Tipo] = porTipo[dados.Tipo] or {}
			porTipo[dados.Tipo][id] = dados
		end
	end
end

-- Dados de um item pelo Id (ou nil).
function CatalogoItens.Get(id)
	return porId[id]
end

-- Todos os itens de um Tipo: { [id] = dados }.
function CatalogoItens.PorTipo(tipo)
	return porTipo[tipo] or {}
end

-- Tabela completa: { [id] = dados }.
function CatalogoItens.Todos()
	return porId
end

return CatalogoItens