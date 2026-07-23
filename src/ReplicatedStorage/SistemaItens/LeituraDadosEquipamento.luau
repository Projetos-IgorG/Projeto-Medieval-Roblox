local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CatalogoItens = require(ReplicatedStorage:WaitForChild("Dados"):WaitForChild("Itens"):WaitForChild("CatalogoItens"))

local EquipmentHelpers = {}

function EquipmentHelpers.LerTipo(tool: Tool): string?
	local id = tool:GetAttribute("Id")
	local dados = id and CatalogoItens.Get(id)
	if dados then
		-- Mapeia os tipos do catálogo novo para os esperados pelo jogo
		if dados.Tipo == "Tool" then
			if dados.Subtipo == "Arma" then
				return "Armas"
			elseif dados.Subtipo == "Ferramenta" then
				return "Ferramentas"
			end
		elseif dados.Tipo == "Equipment" then
			return "Armaduras"
		end
		return dados.Tipo
	end
	return tool:GetAttribute("Tipo") :: string?
end

function EquipmentHelpers.LerNome(tool: Tool): string
	local id = tool:GetAttribute("Id")
	local dados = id and CatalogoItens.Get(id)
	if dados then
		return dados.Nome or tool.Name
	end
	return tool.Name
end

function EquipmentHelpers.DeveInterceptar(tool: Tool): boolean
	local tipo = EquipmentHelpers.LerTipo(tool)
	return tipo == "Armas" or tipo == "Armaduras"
end

return EquipmentHelpers
