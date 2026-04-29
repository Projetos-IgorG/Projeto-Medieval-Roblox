--!strict
--!native
--!optimize 2

--[[
    Script: Raycast.luau
    Caminho: src/ReplicatedStorage/Combate/Hitbox/Shapecast/Solvers
    Responsabilidade: Executa varreduras lineares para hitboxes baseadas em Raycast.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao decide regras de combate; apenas resolve a varredura fisica solicitada.
    Funcoes principais: Cast
]]
local Types = require(script.Parent.Parent.Types)
local Solver = { Solvers = {} }

function Solver:Cast(segment: Types.Segment, raycastParams: RaycastParams?): RaycastResult?
	local solver = Solver.Solvers[segment.Instance.ClassName]
	local origin: Vector3 = solver:ToPosition(segment)
	local direction: Vector3 = solver:ToDirection(segment)

	return workspace:Raycast(origin, direction, raycastParams), direction
end

return Solver
