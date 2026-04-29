--[[
    Script: CameraUtils.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/PlayerModule/CameraModule
    Responsabilidade: Fornece funcoes matematicas e auxiliares usadas pelos controladores de camera.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao implementa regras de gameplay do projeto; apenas apoia camera, controle e compatibilidade do jogador.
    Funcoes principais: new, step, map, mapClamp, getLooseBoundingSphere, sanitizeAngle
]]
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local UserGameSettings = UserSettings():GetService("UserGameSettings")

local CameraUtils = {}

local function round(num: number)
	return math.floor(num + 0.5)
end

local Spring = {}
do
	Spring.__index = Spring

	function Spring.new(freq, pos)
		return setmetatable({
			freq = freq,
			goal = pos,
			pos = pos,
			vel = 0,
		}, Spring)
	end

	function Spring:step(dt: number)
		local f: number = self.freq :: number * 2.0 * math.pi
		local g: Vector3 = self.goal
		local p0: Vector3 = self.pos
		local v0: Vector3 = self.vel

		local offset = p0 - g
		local decay = math.exp(-f * dt)

		local p1 = (offset * (1 + f * dt) + v0 * dt) * decay + g
		local v1 = (v0 * (1 - f * dt) - offset * (f * f * dt)) * decay

		self.pos = p1
		self.vel = v1

		return p1
	end
end

CameraUtils.Spring = Spring

function CameraUtils.map(x: number, inMin: number, inMax: number, outMin: number, outMax: number): number
	return (x - inMin) * (outMax - outMin) / (inMax - inMin) + outMin
end

function CameraUtils.mapClamp(x: number, inMin: number, inMax: number, outMin: number, outMax: number): number
	return math.clamp(
		(x - inMin) * (outMax - outMin) / (inMax - inMin) + outMin,
		math.min(outMin, outMax),
		math.max(outMin, outMax)
	)
end

function CameraUtils.getLooseBoundingSphere(parts: { BasePart })
	local points = table.create(#parts)
	for idx, part in pairs(parts) do
		points[idx] = part.Position
	end

	local x = points[1]

	local y = x
	local yDist = 0

	for _, p in ipairs(points) do
		local pDist = (p - x).Magnitude

		if pDist > yDist then
			y = p
			yDist = pDist
		end
	end

	local z = y
	local zDist = 0

	for _, p in ipairs(points) do
		local pDist = (p - y).Magnitude

		if pDist > zDist then
			z = p
			zDist = pDist
		end
	end

	local sc = (y + z) * 0.5
	local sr = (y - z).Magnitude * 0.5

	for _, p in ipairs(points) do
		local pDist = (p - sc).Magnitude

		if pDist > sr then

			sc = sc + (pDist - sr) * 0.5 * (p - sc).Unit

			sr = (pDist + sr) * 0.5
		end
	end

	return sc, sr
end

function CameraUtils.sanitizeAngle(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

function CameraUtils.Round(num: number, places: number): number
	local decimalPivot = 10 ^ places
	return math.floor(num * decimalPivot + 0.5) / decimalPivot
end

function CameraUtils.IsFinite(val: number): boolean
	return val == val and val ~= math.huge and val ~= -math.huge
end

function CameraUtils.IsFiniteVector3(vec3: Vector3): boolean
	return CameraUtils.IsFinite(vec3.X) and CameraUtils.IsFinite(vec3.Y) and CameraUtils.IsFinite(vec3.Z)
end

function CameraUtils.GetAngleBetweenXZVectors(v1: Vector3, v2: Vector3): number
	return math.atan2(v2.X * v1.Z - v2.Z * v1.X, v2.X * v1.X + v2.Z * v1.Z)
end

function CameraUtils.RotateVectorByAngleAndRound(camLook: Vector3, rotateAngle: number, roundAmount: number): number
	if camLook.Magnitude > 0 then
		camLook = camLook.Unit
		local currAngle = math.atan2(camLook.Z, camLook.X)
		local newAngle = round((math.atan2(camLook.Z, camLook.X) + rotateAngle) / roundAmount) * roundAmount
		return newAngle - currAngle
	end
	return 0
end

local k = 0.35
local lowerK = 0.8
local function SCurveTranform(t: number)
	t = math.clamp(t, -1, 1)
	if t >= 0 then
		return (k * t) / (k - t + 1)
	end
	return -((lowerK * -t) / (lowerK + t + 1))
end

local DEADZONE = 0.1
local function toSCurveSpace(t: number)
	return (1 + DEADZONE) * (2 * math.abs(t) - 1) - DEADZONE
end

local function fromSCurveSpace(t: number)
	return t / 2 + 0.5
end

function CameraUtils.GamepadLinearToCurve(thumbstickPosition: Vector2)
	local function onAxis(axisValue)
		local sign = 1
		if axisValue < 0 then
			sign = -1
		end
		local point = fromSCurveSpace(SCurveTranform(toSCurveSpace(math.abs(axisValue))))
		point = point * sign
		return math.clamp(point, -1, 1)
	end
	return Vector2.new(onAxis(thumbstickPosition.X), onAxis(thumbstickPosition.Y))
end

function CameraUtils.ConvertCameraModeEnumToStandard(
	enumValue: Enum.TouchCameraMovementMode | Enum.ComputerCameraMovementMode | Enum.DevTouchCameraMovementMode | Enum.DevComputerCameraMovementMode
): Enum.ComputerCameraMovementMode | Enum.DevComputerCameraMovementMode
	if enumValue == Enum.TouchCameraMovementMode.Default then
		return Enum.ComputerCameraMovementMode.Follow
	end

	if enumValue == Enum.ComputerCameraMovementMode.Default then
		return Enum.ComputerCameraMovementMode.Classic
	end

	if
		enumValue == Enum.TouchCameraMovementMode.Classic
		or enumValue == Enum.DevTouchCameraMovementMode.Classic
		or enumValue == Enum.DevComputerCameraMovementMode.Classic
		or enumValue == Enum.ComputerCameraMovementMode.Classic
	then
		return Enum.ComputerCameraMovementMode.Classic
	end

	if
		enumValue == Enum.TouchCameraMovementMode.Follow
		or enumValue == Enum.DevTouchCameraMovementMode.Follow
		or enumValue == Enum.DevComputerCameraMovementMode.Follow
		or enumValue == Enum.ComputerCameraMovementMode.Follow
	then
		return Enum.ComputerCameraMovementMode.Follow
	end

	if
		enumValue == Enum.TouchCameraMovementMode.Orbital
		or enumValue == Enum.DevTouchCameraMovementMode.Orbital
		or enumValue == Enum.DevComputerCameraMovementMode.Orbital
		or enumValue == Enum.ComputerCameraMovementMode.Orbital
	then
		return Enum.ComputerCameraMovementMode.Orbital
	end

	if
		enumValue == Enum.ComputerCameraMovementMode.CameraToggle
		or enumValue == Enum.DevComputerCameraMovementMode.CameraToggle
	then
		return Enum.ComputerCameraMovementMode.CameraToggle
	end

	if
		enumValue == Enum.DevTouchCameraMovementMode.UserChoice
		or enumValue == Enum.DevComputerCameraMovementMode.UserChoice
	then
		return Enum.DevComputerCameraMovementMode.UserChoice
	end

	return Enum.ComputerCameraMovementMode.Classic
end

local function getMouse()
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
		localPlayer = Players.LocalPlayer
	end
	assert(localPlayer, "CameraUtils requires a valid LocalPlayer")
	return localPlayer:GetMouse()
end

local savedMouseIcon: string = ""
local lastMouseIconOverride: string? = nil
function CameraUtils.setMouseIconOverride(icon: string)
	local mouse = getMouse()

	if mouse.Icon ~= lastMouseIconOverride then
		savedMouseIcon = mouse.Icon
	end

	mouse.Icon = icon
	lastMouseIconOverride = icon
end

function CameraUtils.restoreMouseIcon()
	local mouse = getMouse()

	if mouse.Icon == lastMouseIconOverride then
		mouse.Icon = savedMouseIcon
	end
	lastMouseIconOverride = nil
end

local savedMouseBehavior: Enum.MouseBehavior = Enum.MouseBehavior.Default
local lastMouseBehaviorOverride: Enum.MouseBehavior? = nil
function CameraUtils.setMouseBehaviorOverride(value: Enum.MouseBehavior)
	if UserInputService.MouseBehavior ~= lastMouseBehaviorOverride then
		savedMouseBehavior = UserInputService.MouseBehavior
	end

	UserInputService.MouseBehavior = value
	lastMouseBehaviorOverride = value
end

function CameraUtils.restoreMouseBehavior()
	if UserInputService.MouseBehavior == lastMouseBehaviorOverride then
		UserInputService.MouseBehavior = savedMouseBehavior
	end
	lastMouseBehaviorOverride = nil
end

local savedRotationType: Enum.RotationType = Enum.RotationType.MovementRelative
local lastRotationTypeOverride: Enum.RotationType? = nil
function CameraUtils.setRotationTypeOverride(value: Enum.RotationType)
	if UserGameSettings.RotationType ~= lastRotationTypeOverride then
		savedRotationType = UserGameSettings.RotationType
	end

	UserGameSettings.RotationType = value
	lastRotationTypeOverride = value
end

function CameraUtils.restoreRotationType()
	if UserGameSettings.RotationType == lastRotationTypeOverride then
		UserGameSettings.RotationType = savedRotationType
	end
	lastRotationTypeOverride = nil
end

return CameraUtils
