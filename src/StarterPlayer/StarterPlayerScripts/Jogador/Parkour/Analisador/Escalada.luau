--[[
	Módulo: Escalada
	Pai: Analisador (Parkour)
	Responsabilidade: verificar se, a partir de uma borda agarrada, o personagem
		pode escalar (subir por cima da borda atual) com espaço livre no topo.

	Recebe `finalConfig` já resolvido nas funções internas. `CheckEscalar` é o
	ponto de entrada público e resolve o config sozinho.
]]

local Configs = require(script.Parent.Parent.Configuracoes.ConfigParkour)
local Utilidades = require(script.Parent.Parent.Utilidades)
local Debug = require(script.Parent.Parent.Depuracao.DepuracaoParkour)
local Geometria = require(script.Parent.Geometria)

local Escalada = {}

-- Scratch de clearance próprio do módulo (desacoplado de Espacos).
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

local function checkEscalarAtEdge(character, currentEdgePos, currentNormal, currentPart, finalConfig, debugContext)
	if not Geometria.isWallLikeNormal(currentNormal, finalConfig) then
		Debug.Verbose("  RESULTADO: InvalidCurrentNormalForEscalar | Normal:", currentNormal)
		return {
			CanEscalar = false,
			Reason = "InvalidCurrentNormalForEscalar",
		}
	end

	if debugContext then
		Debug.Verbose("═══ CheckEscalar [" .. debugContext .. "] ═══")
	else
		Debug.Verbose("═══ CheckEscalar ═══")
	end
	Debug.Verbose("  EdgePos:", currentEdgePos, "| Normal:", currentNormal)
	Debug.Verbose("  Part:", currentPart and currentPart.Name or "nil")

	local flatLook = Vector3.new(-currentNormal.X, 0, -currentNormal.Z)
	if flatLook.Magnitude < 0.01 then
		flatLook = Vector3.new(0, 0, -1)
	end
	flatLook = flatLook.Unit

	local center = currentEdgePos
		+ Vector3.yAxis * (finalConfig.EscalarClearanceUpOffset or finalConfig.EscalarUpOffset)
		+ flatLook * (finalConfig.EscalarClearanceForwardOffset or finalConfig.EscalarForwardOffset)

	local cf = CFrame.lookAt(center, center + flatLook, Vector3.yAxis)
	local clearanceSize = finalConfig.EscalarClearanceSize or finalConfig.VaultClearanceSize

	Debug.Verbose("  ClearanceCenter:", center, "| Size:", clearanceSize)

	activeMinPartHeight = finalConfig.MinPartHeight
	setClearanceIgnore(character, currentPart)
	local clear, blocker = Utilidades.firstBlockingPartInBox(cf, clearanceSize, clearanceIgnore, clearanceFilter)

	Debug.Verbose("  ClearanceResult: clear=", clear, "| blocker=", blocker and blocker.Name or "nil")

	local posFinal = currentEdgePos
		+ Vector3.yAxis * finalConfig.EscalarUpOffset
		+ flatLook * finalConfig.EscalarForwardOffset

	if not clear then
		Debug.Verbose("  RESULTADO: NoClearanceOnTop | Blocker:", blocker and blocker.Name or "nil")
		return {
			CanEscalar = false,
			Reason = "NoClearanceOnTop",
			Blocker = blocker,
			ClearanceCFrame = cf,
			ClearanceSize = clearanceSize,
		}
	end

	Debug.Verbose("  RESULTADO: CanEscalar=true | PosFinal:", posFinal)
	return {
		CanEscalar = true,
		PosFinal = posFinal,
		EdgePosition = currentEdgePos,
		Normal = currentNormal,
		Part = currentPart,
		ClearanceCFrame = cf,
		ClearanceSize = clearanceSize,
	}
end

Escalada.checkEscalarAtEdge = checkEscalarAtEdge

-- Ponto de entrada público (usado pela fachada Analisador).
function Escalada.CheckEscalar(character, currentEdgePos, currentNormal, currentPart, config)
	local finalConfig = Configs.mergeConfig(config)
	return checkEscalarAtEdge(character, currentEdgePos, currentNormal, currentPart, finalConfig, "CurrentGrab")
end

return Escalada
