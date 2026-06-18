--[[
    Script: init.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/PlayerModule/CameraModule/ZoomController
    Responsabilidade: Gerencia zoom da camera e limites de distancia do jogador.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao implementa regras de gameplay do projeto; apenas apoia camera, controle e compatibilidade do jogador.
    Funcoes principais: new, Step, Update, GetZoomRadius, SetZoomParameters, ReleaseSpring
]]
local ZOOM_STIFFNESS = 4.5
local ZOOM_DEFAULT = 12.5
local ZOOM_ACCELERATION = 0.0375

local MIN_FOCUS_DIST = 0.5
local DIST_OPAQUE = 1

local Popper = require(script:WaitForChild("Popper"))

local clamp = math.clamp
local exp = math.exp
local min = math.min
local max = math.max
local pi = math.pi

local cameraMinZoomDistance, cameraMaxZoomDistance
do
	local Player = game:GetService("Players").LocalPlayer
	assert(Player, "ZoomController requires a valid LocalPlayer")

	local function updateBounds()
		cameraMinZoomDistance = Player.CameraMinZoomDistance
		cameraMaxZoomDistance = Player.CameraMaxZoomDistance
	end

	updateBounds()

	Player:GetPropertyChangedSignal("CameraMinZoomDistance"):Connect(updateBounds)
	Player:GetPropertyChangedSignal("CameraMaxZoomDistance"):Connect(updateBounds)
end

local ConstrainedSpring = {}
do
	ConstrainedSpring.__index = ConstrainedSpring

	function ConstrainedSpring.new(freq: number, x: number, minValue: number, maxValue: number)
		x = clamp(x, minValue, maxValue)
		return setmetatable({
			freq = freq,
			x = x,
			v = 0,
			minValue = minValue,
			maxValue = maxValue,
			goal = x,
		}, ConstrainedSpring)
	end

	function ConstrainedSpring:Step(dt: number)
		local freq = self.freq :: number * 2 * pi
		local x: number = self.x
		local v: number = self.v
		local minValue: number = self.minValue
		local maxValue: number = self.maxValue
		local goal: number = self.goal

		local offset = goal - x
		local step = freq * dt
		local decay = exp(-step)

		local x1 = goal + (v * dt - offset * (step + 1)) * decay
		local v1 = ((offset * freq - v) * step + v) * decay

		if x1 < minValue then
			x1 = minValue
			v1 = 0
		elseif x1 > maxValue then
			x1 = maxValue
			v1 = 0
		end

		self.x = x1
		self.v = v1

		return x1
	end
end

local zoomSpring = ConstrainedSpring.new(ZOOM_STIFFNESS, ZOOM_DEFAULT, MIN_FOCUS_DIST, cameraMaxZoomDistance)

local function stepTargetZoom(z: number, dz: number, zoomMin: number, zoomMax: number)
	z = clamp(z + dz * (1 + z * ZOOM_ACCELERATION), zoomMin, zoomMax)
	if z < DIST_OPAQUE then
		z = dz <= 0 and zoomMin or DIST_OPAQUE
	end
	return z
end

local zoomDelta = 0

local Zoom = {}
do
	function Zoom.Update(renderDt: number, focus: CFrame, extrapolation)
		local poppedZoom = math.huge

		if zoomSpring.goal > DIST_OPAQUE then

			local maxPossibleZoom = max(
				zoomSpring.x,
				stepTargetZoom(zoomSpring.goal, zoomDelta, cameraMinZoomDistance, cameraMaxZoomDistance)
			)

			poppedZoom = Popper(
				focus * CFrame.new(0, 0, MIN_FOCUS_DIST),
				maxPossibleZoom - MIN_FOCUS_DIST,
				extrapolation
			) + MIN_FOCUS_DIST
		end

		zoomSpring.minValue = MIN_FOCUS_DIST
		zoomSpring.maxValue = min(cameraMaxZoomDistance, poppedZoom)

		return zoomSpring:Step(renderDt)
	end

	function Zoom.GetZoomRadius()
		return zoomSpring.x
	end

	function Zoom.SetZoomParameters(targetZoom, newZoomDelta)
		zoomSpring.goal = targetZoom
		zoomDelta = newZoomDelta
	end

	function Zoom.SetZoomRadius(radius: number)
		zoomSpring.x = radius
		zoomSpring.goal = radius
		zoomSpring.v = 0
	end

	function Zoom.ReleaseSpring()
		zoomSpring.x = zoomSpring.goal
		zoomSpring.v = 0
	end
end

return Zoom
