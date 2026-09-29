--[[
	Módulo: DeteccaoSaltoAbismo
	Pai: Analisador (Parkour)
	Responsabilidade: verifica com precisão geométrica se à frente e abaixo do jogador
		existe um vão livre, buraco, abismo ou queda grande para acionar o salto com impulso sobre abismo.
		Usa 4 linhas de sondagem para frente e gera dados visuais 3D para o sistema de depuração.
	Uso: ModuleScript; require(caminho) e chame CheckSaltoAbismo(character, finalConfig).
]]

local Workspace = game:GetService("Workspace")

local Configs = require(script.Parent.Parent.Configuracoes.ConfigParkour)
local Utilidades = require(script.Parent.Parent.Utilidades)
local Geometria = require(script.Parent.Geometria)

local DeteccaoSaltoAbismo = {}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

function DeteccaoSaltoAbismo.CheckSaltoAbismo(character: Model, config: any?)
	local finalConfig = Configs.mergeConfig(config)
	local hrp, head = Utilidades.getCharacterParts(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if not hrp or not head or not humanoid then
		return {
			Aprovado = false,
			Reason = "NoCharacterParts",
		}
	end

	-- 1. Determina direção horizontal do movimento/olhar
	local moveDir = humanoid.MoveDirection
	local lookXZ: Vector3?
	if moveDir.Magnitude > 0.1 then
		lookXZ = Vector3.new(moveDir.X, 0, moveDir.Z).Unit
	else
		lookXZ = Geometria.getHorizontalUnit(hrp.CFrame.LookVector)
	end

	if not lookXZ then
		return {
			Aprovado = false,
			Reason = "NoHorizontalLook",
		}
	end

	local rightXZ = Vector3.new(-lookXZ.Z, 0, lookXZ.X).Unit

	rayParams.FilterDescendantsInstances = { character }

	-- 2. Altura de referência do piso atual sob o jogador
	local floorProbeDist = finalConfig.FloorProbeDownwardDistance or 5.0
	local floorHit = Workspace:Raycast(hrp.Position, Vector3.new(0, -floorProbeDist, 0), rayParams)
	local pisoAtualY: number
	if floorHit and floorHit.Instance and not Utilidades.isParkourIgnoredPart(floorHit.Instance, finalConfig.MinPartHeight) then
		pisoAtualY = floorHit.Position.Y
	else
		local hipHeight = humanoid.HipHeight > 0 and humanoid.HipHeight or 2.0
		pisoAtualY = hrp.Position.Y - hipHeight - 1.0
	end

	-- 3. Definição da Caixa Visual de Abismo à Frente / Abaixo (cobre as 4 linhas até 11 studs)
	local boxDistanceForward = 7.0
	local boxCenterXZ = hrp.Position + lookXZ * boxDistanceForward
	local boxHeight = 7.0
	local boxCenterY = pisoAtualY - (boxHeight * 0.5)
	local boxCenter = Vector3.new(boxCenterXZ.X, boxCenterY, boxCenterXZ.Z)
	local boxSize = Vector3.new(3.8, boxHeight, 9.5)
	local boxCFrame = CFrame.lookAt(boxCenter, boxCenter + lookXZ)

	local debugRays = {}

	-- 4. Verificação de obstáculo frontal imediato (parede ou muro sólido bloqueando)
	local obstacleDist = finalConfig.SaltoAbismoObstacleCheckDistance or 3.5
	local chestOrigin = hrp.Position + Vector3.new(0, 0.5, 0)
	local chestHit = Workspace:Raycast(chestOrigin, lookXZ * obstacleDist, rayParams)
	if chestHit and chestHit.Instance and not Utilidades.isParkourIgnoredPart(chestHit.Instance, finalConfig.MinPartHeight) then
		table.insert(debugRays, {
			Origin = chestOrigin,
			HitPosition = chestHit.Position,
			Hit = true,
			IsAbyss = false,
		})
		return {
			Aprovado = false,
			Reason = "ObstaculoFrontal",
			Part = chestHit.Instance,
			SaltoAbismoBoxCFrame = boxCFrame,
			SaltoAbismoBoxSize = boxSize,
			SaltoAbismoRays = debugRays,
		}
	end

	-- 5. Sondagem do chão à frente em 4 distâncias e larguras laterais
	local downCheckDistance = finalConfig.SaltoAbismoDownCheckDistance or 20.0
	local minQueda = finalConfig.SaltoAbismoMinQueda or 5.0
	local chaoContinuoTolerance = 2.4 -- Se a diferença de altura for menor que isso, é piso contínuo normal

	-- 4 LINHAS para a frente (3.0, 5.5, 8.0, 11.0 studs)
	local distancias = finalConfig.SaltoAbismoDistancias or { 3.0, 5.5, 8.0, 11.0 }
	local offsetsLaterais = { -1.1, 0, 1.1 }

	local totalPontos = 0
	local pontosAbismo = 0
	local pontosChaoContinuoProximo = 0

	for _, d in ipairs(distancias) do
		for _, xOff in ipairs(offsetsLaterais) do
			totalPontos += 1
			local rayOrigin = hrp.Position + lookXZ * d + rightXZ * xOff + Vector3.new(0, 0.5, 0)
			local hit = Workspace:Raycast(rayOrigin, Vector3.new(0, -downCheckDistance, 0), rayParams)

			local isAbyss = false
			local hitPos = rayOrigin - Vector3.new(0, downCheckDistance, 0)

			if not hit then
				-- Vazio total (nada atingido por downCheckDistance studs para baixo)
				isAbyss = true
				pontosAbismo += 1
			else
				hitPos = hit.Position
				local deltaY = hitPos.Y - pisoAtualY

				if deltaY < -minQueda then
					-- Queda considerável / abismo
					isAbyss = true
					pontosAbismo += 1
				else
					-- Chão presente que não é queda profunda
					isAbyss = false
					if deltaY >= -chaoContinuoTolerance and deltaY <= chaoContinuoTolerance then
						-- Se o chão contínuo estiver nas distâncias 3.0, 5.5 ou 8.0, não é um vão que necessite salto longo
						if d <= 8.0 then
							pontosChaoContinuoProximo += 1
						end
					end
				end
			end

			table.insert(debugRays, {
				Origin = rayOrigin,
				HitPosition = hitPos,
				Hit = hit ~= nil,
				IsAbyss = isAbyss,
			})
		end
	end

	-- 6. Avaliação da condição de abismo:
	-- Se houver chão contínuo à frente, o jogador está em terreno ou piso normal -> REPROVADO!
	if pontosChaoContinuoProximo >= 1 then
		return {
			Aprovado = false,
			Reason = "ChaoContinuoNaFrente",
			SaltoAbismoBoxCFrame = boxCFrame,
			SaltoAbismoBoxSize = boxSize,
			SaltoAbismoRays = debugRays,
		}
	end

	-- Para ser aprovado como abismo que precisa de impulso, deve ter abismo confirmado em pelo menos metade dos pontos
	if pontosAbismo < 6 then
		return {
			Aprovado = false,
			Reason = "SemEspacoOuAbismoSuficiente",
			SaltoAbismoBoxCFrame = boxCFrame,
			SaltoAbismoBoxSize = boxSize,
			SaltoAbismoRays = debugRays,
		}
	end

	-- APROVADO: vão livre / abismo confirmado para o impulso!
	return {
		Aprovado = true,
		Acao = "SaltoAbismo",
		LookVector = lookXZ,
		Character = character,
		Hrp = hrp,
		Humanoid = humanoid,
		SaltoAbismoBoxCFrame = boxCFrame,
		SaltoAbismoBoxSize = boxSize,
		SaltoAbismoRays = debugRays,
	}
end

return DeteccaoSaltoAbismo
