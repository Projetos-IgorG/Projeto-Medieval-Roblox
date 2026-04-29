--!strict
--!native
--!optimize 2

--[[
    Script: Attachment.luau
    Caminho: src/ReplicatedStorage/Combate/Hitbox/Shapecast/Solvers
    Responsabilidade: Resolve Shapecasts guiados por Attachments em partes ou modelos.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao decide regras de combate; apenas resolve a varredura fisica solicitada.
    Funcoes principais: ToPosition, ToDirection, ToVisual
]]
local Settings = require(script.Parent.Parent.HitboxConfig)
local Types = require(script.Parent.Parent.Types)

local Solver = {}

function Solver:ToPosition(segment: Types.Segment): Vector3
	return segment.Position or segment.Instance.WorldPosition
end

function Solver:ToDirection(segment: Types.Segment): Vector3
	local direction: Vector3 = segment.Instance.WorldPosition - Solver:ToPosition(segment)

	if direction.Magnitude == 0 then
		direction = segment.LastDirection.Unit * Settings.Minimum_Stationary_Length
	end

	return direction
end

function Solver:ToVisual(segment: Types.Segment): CFrame
	return CFrame.lookAt(Solver:ToPosition(segment), segment.Instance.WorldPosition)
end

return Solver
