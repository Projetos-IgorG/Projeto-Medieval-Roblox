--!strict
--[[
	Módulo: MovimentoCabeca
	Caminho: src/StarterPlayer/StarterCharacterScripts/Jogador/Camera
	Responsabilidade: Controla a rotação da cabeça do personagem local para acompanhar a câmera.
	Uso: ModuleScript; importado pelo init.client.luau da Camera.
	Não faz: Não controla o torso (InclinacaoTorso cuida disso).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserGameSettings = UserSettings():GetService("UserGameSettings")

local RotacaoCabeca = require(
	ReplicatedStorage:WaitForChild("Jogador")
		:WaitForChild("Camera")
		:WaitForChild("Cabeca")
		:WaitForChild("RotacaoCabeca")
)

-- ── Tipos ──────────────────────────────────────────────────────────────

export type TorsoTiltInstance = {
	Enable: (self: TorsoTiltInstance) -> (),
	Disable: (self: TorsoTiltInstance) -> (),
	Destroy: (self: TorsoTiltInstance) -> (),
	ShouldTilt: (self: TorsoTiltInstance) -> boolean,
}

-- ── Configuração de ângulos máximos da cabeça ──────────────────────────
-- Ajuste esses valores para controlar quanto a cabeça pode girar.

-- Sem ShiftLock (câmera livre)
local HEAD_MAX_SIDE_FREE = math.rad(55) -- rotação lateral máx
local HEAD_MAX_UPDOWN_FREE = math.rad(30) -- rotação cima/baixo máx

-- Com ShiftLock ativado
local HEAD_MAX_SIDE_SHIFTLOCK = math.rad(25) -- rotação lateral máx (menor pois o torso já gira)
local HEAD_MAX_UPDOWN_SHIFTLOCK = math.rad(20) -- rotação cima/baixo máx (menor pois o torso já inclina)

-- ── Módulo ─────────────────────────────────────────────────────────────

local MovimentoCabeca = {}

function MovimentoCabeca.isShiftLock(): boolean
	return UserGameSettings.RotationType == Enum.RotationType.CameraRelative
end

--[[
	Atualiza a rotação do pescoço a cada frame.
	Deve ser chamado dentro de um RenderStepped.
	
	@param root — HumanoidRootPart do character
	@param neck — Motor6D Neck do character
	@param targetC0 — CFrame alvo atual (mutado por lerp)
	@param yOffset — offset Y original do Neck.C0
	@return CFrame — novo targetC0 (após lerp)
]]
function MovimentoCabeca.AtualizarNeck(
	root: BasePart,
	neck: Motor6D,
	targetC0: CFrame,
	yOffset: number
): CFrame
	local cam = workspace.CurrentCamera
	if not cam then
		return targetC0
	end

	-- Escolhe limites de ângulo da cabeça com base no estado do ShiftLock
	local maxSide, maxUpDown
	if MovimentoCabeca.isShiftLock() then
		maxSide = HEAD_MAX_SIDE_SHIFTLOCK
		maxUpDown = HEAD_MAX_UPDOWN_SHIFTLOCK
	else
		maxSide = HEAD_MAX_SIDE_FREE
		maxUpDown = HEAD_MAX_UPDOWN_FREE
	end

	local cameraDirection = root.CFrame:ToObjectSpace(cam.CFrame).LookVector
	local desiredC0 = RotacaoCabeca.CalcularTargetC0(cameraDirection, yOffset, maxSide, maxUpDown)
	targetC0 = targetC0:Lerp(desiredC0, 0.2)
	neck.C0 = targetC0

	return targetC0
end

return MovimentoCabeca
