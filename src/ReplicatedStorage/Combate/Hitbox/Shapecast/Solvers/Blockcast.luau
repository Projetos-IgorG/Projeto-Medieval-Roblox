--!strict
--!native
--!optimize 2

--[[
    Script: Blockcast.luau
    Caminho: src/ReplicatedStorage/Combate/Hitbox/Shapecast/Solvers
    Responsabilidade: Executa varreduras de caixa para hitboxes com volume retangular.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao decide regras de combate; apenas resolve a varredura fisica solicitada.
    Funcoes principais: Cast
]]
local Types = require(script.Parent.Parent.Types)
local Solver = { Solvers = {} }

function Solver:Cast(segment: Types.Segment, raycastParams: RaycastParams?): RaycastResult?
	local direction: Vector3 = Solver.Solvers[segment.Instance.ClassName]:ToDirection(segment)
	local lastCFrame: CFrame? = segment.CastData._LastCFrameBlockCast

	local result: RaycastResult = workspace:Blockcast(
		(lastCFrame or segment.Instance.WorldCFrame) * segment.CastData.CFrame,
		segment.CastData.Size,
		direction,
		raycastParams
	)

	task.defer(function()
		lastCFrame = segment.Instance.WorldCFrame
	end)

	return result, direction
end

return Solver
