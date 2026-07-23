--[[
	Módulo: Espacos (Clearances)
	Pai: Analisador (Parkour)
	Responsabilidade: verificar espaço livre (clearance) em torno de bordas para
		Agarrar (topo/frente) e Vault (corpo/borda).

	IMPORTANTE (otimização): todas as funções recebem `finalConfig` JÁ resolvido
	(Configs.mergeConfig). O merge acontece uma única vez no ponto de entrada
	(fachada Analisador ou início de cada CheckXxx), evitando re-merge por
	candidato a cada frame - que era o comportamento original.

	Estado compartilhado: `clearanceIgnore` e `activeMinPartHeight` são scratch
	reutilizados. São definidos imediatamente antes de cada consulta síncrona
	(firstBlockingPartInBox não dá yield), então não há reentrância.
]]

local Utilidades = require(script.Parent.Parent.Utilidades)

local Espacos = {}

local clearanceIgnore = table.create(2)
local activeMinPartHeight = 0.6

local function clearanceFilter(part)
	return Utilidades.isParkourIgnoredPart(part, activeMinPartHeight)
end

local function setClearanceIgnore(a, b)
	clearanceIgnore[1] = a
	clearanceIgnore[2] = b
	for i = 3, #clearanceIgnore do
		clearanceIgnore[i] = nil
	end
end

local function flatNormalOrDefault(normal)
	local flat = Vector3.new(normal.X, 0, normal.Z)
	if flat.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

function Espacos.HasTopClearance(data, finalConfig)
	local normal = data.Normal.Unit
	local flatNormal = flatNormalOrDefault(normal)

	local center = data.EdgePosition
		+ Vector3.yAxis * finalConfig.TopClearanceUpOffset
		+ flatNormal * finalConfig.TopClearanceNormalOffset

	local cf = CFrame.lookAt(center, center - flatNormal, Vector3.yAxis)
	activeMinPartHeight = finalConfig.MinPartHeight
	setClearanceIgnore(data.Character, data.Part)
	local clear, blocker =
		Utilidades.firstBlockingPartInBox(cf, finalConfig.TopClearanceSize, clearanceIgnore, clearanceFilter)

	return clear, blocker, cf, finalConfig.TopClearanceSize
end

function Espacos.HasFrontClearance(data, finalConfig)
	local normal = data.Normal.Unit
	local flatNormal = flatNormalOrDefault(normal)

	local center = data.EdgePosition
		+ Vector3.yAxis * finalConfig.FrontClearanceUpOffset
		+ flatNormal * finalConfig.FrontClearanceNormalOffset

	local cf = CFrame.lookAt(center, center - flatNormal, Vector3.yAxis)
	activeMinPartHeight = finalConfig.MinPartHeight
	setClearanceIgnore(data.Character, data.Part)
	local clear, blocker =
		Utilidades.firstBlockingPartInBox(cf, finalConfig.FrontClearanceSize, clearanceIgnore, clearanceFilter)

	return clear, blocker, cf, finalConfig.FrontClearanceSize
end

function Espacos.HasVaultClearance(data, finalConfig)
	local look = data.LookVector
	local bordaReal = data.EdgePosition

	local margin = 0.05
	local clearanceCenter = bordaReal
		+ Vector3.yAxis * (finalConfig.VaultClearanceUpOffset + margin)
		+ look * finalConfig.VaultClearanceForwardOffset

	local cf = CFrame.lookAt(clearanceCenter, clearanceCenter + look, Vector3.yAxis)
	activeMinPartHeight = finalConfig.MinPartHeight
	setClearanceIgnore(data.Character, data.Part)
	local clear, blocker =
		Utilidades.firstBlockingPartInBox(cf, finalConfig.VaultClearanceSize, clearanceIgnore, clearanceFilter)

	local posFinal = bordaReal + Vector3.yAxis * finalConfig.VaultMoveUpOffset

	return clear, blocker, cf, finalConfig.VaultClearanceSize, posFinal
end

function Espacos.HasVaultEdgeClearance(data, finalConfig)
	local bordaReal = data.EdgePosition
	local look = data.LookVector

	local center = bordaReal
		+ Vector3.yAxis * (finalConfig.VaultEdgeClearanceUpOffset or (finalConfig.VaultClearanceSize.Y / 2))

	local cf = CFrame.lookAt(center, center + look, Vector3.yAxis)
	activeMinPartHeight = finalConfig.MinPartHeight
	setClearanceIgnore(data.Character, data.Part)
	local clear, blocker =
		Utilidades.firstBlockingPartInBox(cf, finalConfig.VaultClearanceSize, clearanceIgnore, clearanceFilter)

	return clear, blocker, cf, finalConfig.VaultClearanceSize
end

-- Retorna (hasTopClearance, hasFrontClearance). Faz curto-circuito: se não há
-- topo, nem testa a frente (retorna false, false).
function Espacos.hasBothClearances(character, part, edgePosition, normal, finalConfig)
	local data = {
		Character = character,
		Part = part,
		EdgePosition = edgePosition,
		Normal = normal,
	}

	local hasTopClearance = Espacos.HasTopClearance(data, finalConfig)
	if not hasTopClearance then
		return false, false
	end

	local hasFrontClearance = Espacos.HasFrontClearance(data, finalConfig)
	return hasTopClearance, hasFrontClearance
end

return Espacos
