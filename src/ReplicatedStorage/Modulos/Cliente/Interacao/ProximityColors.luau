local ProximityColors = {}

local COLOR_MAP = {
	Ferramentas = Color3.fromRGB(149, 149, 149), -- Cinza
	Armas = Color3.fromRGB(149, 149, 149), -- Cinza
	ArmasEquipadas = Color3.fromRGB(149, 149, 149), -- Cinza
	Armaduras = Color3.fromRGB(149, 149, 149), -- Cinza
	Materiais = Color3.fromRGB(167, 116, 96), -- Marrom
	Comidas = Color3.fromRGB(186, 174, 104), -- Amarelo
	Bebidas = Color3.fromRGB(104, 186, 159), -- Azul Claro
	Pocoes = Color3.fromRGB(162, 104, 186), -- Roxo
	Ingredientes = Color3.fromRGB(111, 186, 104), -- Verde
	Interagir = Color3.fromRGB(218, 218, 218), -- Cinza claro
	NPC = Color3.fromRGB(218, 218, 218), -- Cinza claro
}

local DEFAULT_COLOR = Color3.fromRGB(218, 218, 218)

function ProximityColors.GetColorByType(tipo)
	if typeof(tipo) ~= "string" then
		return DEFAULT_COLOR
	end
	return COLOR_MAP[tipo] or DEFAULT_COLOR
end

function ProximityColors.GetDefaultColor()
	return DEFAULT_COLOR
end

return ProximityColors
