--[[
    Script: init.luau
    Caminho: src/ReplicatedStorage/Combate/Hitbox/Shapecast/Visualizers
    Responsabilidade: Agrupa visualizadores de depuracao do pacote Shapecast.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao detecta dano nem aplica hits; apenas mostra formas para depuracao visual.
]]
local Visualizers = {}

for _, visualizer in script:GetChildren() do
	local load = require(visualizer)
	Visualizers[visualizer.Name] = load
end

return Visualizers
