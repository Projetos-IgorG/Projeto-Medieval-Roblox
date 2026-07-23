--[[
    Script: CoresProximidade.luau
    Caminho: src/ReplicatedStorage/Interacao/Proximidade/Configuracoes
    Responsabilidade: Centraliza cores e estados visuais usados por interacoes de proximidade.
    Uso: ModuleScript; use require(caminho) para ler as tabelas e valores exportados.
    Nao faz: Nao executa comportamento sozinho; apenas fornece dados para outros scripts.
    Funcoes principais: GetColorByType, GetDefaultColor
]]
local ProximityColors = {}

local COLOR_MAP = {
	Ferramentas = Color3.fromRGB(149, 149, 149),
	Armas = Color3.fromRGB(149, 149, 149),
	Armaduras = Color3.fromRGB(149, 149, 149),
	Materiais = Color3.fromRGB(167, 116, 96),
	Comidas = Color3.fromRGB(186, 174, 104),
	Bebidas = Color3.fromRGB(104, 186, 159),
	Pocoes = Color3.fromRGB(162, 104, 186),
	Ingredientes = Color3.fromRGB(111, 186, 104),
	Interagir = Color3.fromRGB(218, 218, 218),
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
