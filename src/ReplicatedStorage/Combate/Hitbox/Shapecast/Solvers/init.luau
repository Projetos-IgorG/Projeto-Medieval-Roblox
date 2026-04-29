--[[
    Script: init.luau
    Caminho: src/ReplicatedStorage/Combate/Hitbox/Shapecast/Solvers
    Responsabilidade: Agrupa e exporta os solvers disponiveis para o pacote Shapecast.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao decide regras de combate; apenas resolve a varredura fisica solicitada.
]]
local Solvers = {}

for _, solver in script:GetChildren() do
	local load = require(solver)
	load.Solvers = Solvers
	Solvers[solver.Name] = load
end

return Solvers
