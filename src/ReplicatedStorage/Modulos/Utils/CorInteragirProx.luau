-- ReplicatedStorage/Modulos/CorInteragirProx.luau
local CorPorTipo = {}

local MAP = {
	Ferramenta = Color3.fromRGB(149, 149, 149), -- Cinza
	Recurso = Color3.fromRGB(186, 134, 104), -- Marrom
	Interagir = Color3.fromRGB(218, 218, 218), -- Cinza claro
	NPC = Color3.fromRGB(218, 218, 218), -- Cinza claro
}

function CorPorTipo.GetColor(tipo)
	if typeof(tipo) ~= "string" then
		return Color3.fromRGB(218, 218, 218) -- cor padrão
	end
	return MAP[tipo] or Color3.fromRGB(218, 218, 218)
end

return CorPorTipo
