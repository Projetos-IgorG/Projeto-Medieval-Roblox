--!strict
--!native
--!optimize 2

--[[
    Script: Bone.luau
    Caminho: src/ReplicatedStorage/Combate/Hitbox/Shapecast/Solvers
    Responsabilidade: Resolve Shapecasts presos a Bones de rigs animados.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao decide regras de combate; apenas resolve a varredura fisica solicitada.
    Funcoes principais: ToPosition, ToDirection, ToVisual
]]
local Types = require(script.Parent.Parent.Types)
local Solver = {}

function Solver:ToPosition(segment: Types.Segment): Vector3
	return segment.Instance.TransformedWorldCFrame.Position
end

function Solver:ToDirection(segment: Types.Segment): Vector3
	if segment.Position then
		return Solver:ToPosition(segment) - segment.Position
	end

	return Vector3.zero
end

function Solver:ToVisual(segment: Types.Segment): CFrame
	return CFrame.lookAt(Solver:ToPosition(segment), segment.Position or Vector3.zero)
end

return Solver
