--!strict

--[[
    Script: DynamicCamFX.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/PlayerModule/CameraModule
    Responsabilidade: Aplica efeitos dinamicos de camera customizados sobre o PlayerModule.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao implementa regras de gameplay do projeto; apenas apoia camera, controle e compatibilidade do jogador.
    Funcoes principais: Update, Cleanup, lerp, lerpDt, getHorizontalSpeed, getHumanoid
]]
local UserInputService = game:GetService("UserInputService")

local sin = math.sin
local rad = math.rad
local abs = math.abs
local clamp = math.clamp
local clock = os.clock
local pi2 = math.pi * 2

local Settings = {

	BobbingFrequencia = 11,
	BobbingIntensidade = 0.09,

	DivisorEfeitos = 12,

	WalkSpeedBase = 14,
	WalkSpeedMultMin = 0.9,
	WalkSpeedMultMax = 1.05,
	WalkSpeedSuavizacao = 4,

	VelocidadeSuavizacao = 5,

	DriftMinimo = -3,
	DriftMaximo = 1,
	DriftSuavizacao = 12,

	RespiracaoFrequencia = 0.2,
	RespiracaoIntensidade = 0.04,

	LeanIntensidade = 1,
	LeanSuavizacao = 3,

	DashFadeSuavizacao = 8,

	AnguloExtremoFadeInicio = 0.8,
	AnguloExtremoFadeFim = 0.95,
}

local currentVel = 0
local drift = 0
local bobbingPhase = 0
local currentSpeedMult = 1.0
local currentLean = 0
local dashFade = 1.0
local wasActive = false

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function lerpDt(a: number, b: number, speed: number, dt: number): number
	return lerp(a, b, clamp(speed * dt, 0, 1))
end

local function getHorizontalSpeed(hrp: BasePart): number
	local v = hrp.AssemblyLinearVelocity
	return Vector3.new(v.X, 0, v.Z).Magnitude
end

local function getHumanoid(hrp: BasePart): Humanoid?
	local char = hrp.Parent
	return char and (char :: Model):FindFirstChildOfClass("Humanoid") or nil
end

local function getLateralDot(hrp: BasePart, hum: Humanoid): number
	local move = hum.MoveDirection
	if move.Magnitude < 0.1 then
		return 0
	end
	local right = hrp.CFrame.RightVector
	local rightXZ = Vector3.new(right.X, 0, right.Z).Unit
	local moveXZ = Vector3.new(move.X, 0, move.Z).Unit
	return rightXZ:Dot(moveXZ)
end

local function calcAngleFade(cframe: CFrame): number
	local y = abs(cframe.LookVector.Y)
	if y <= Settings.AnguloExtremoFadeInicio then
		return 1
	elseif y >= Settings.AnguloExtremoFadeFim then
		return 0
	end
	return 1
		- (y - Settings.AnguloExtremoFadeInicio)
			/ (Settings.AnguloExtremoFadeFim - Settings.AnguloExtremoFadeInicio)
end

local DynamicCamFX = {}

function DynamicCamFX.Update(
	dt: number,
	camCF: CFrame,
	isFirstPerson: boolean,
	isDashing: boolean,
	hrp: BasePart
): CFrame
	if not isFirstPerson then
		if wasActive then
			currentVel, drift, bobbingPhase = 0, 0, 0
			currentSpeedMult, currentLean, dashFade = 1, 0, 1
			wasActive = false
		end
		return camCF
	end

	local hum = getHumanoid(hrp)
	if not hum then
		return camCF
	end

	local isOnGround = hum.FloorMaterial ~= Enum.Material.Air
	if not isOnGround then

		currentVel = lerpDt(currentVel, 0, Settings.VelocidadeSuavizacao, dt)
		currentLean = lerpDt(currentLean, 0, Settings.LeanSuavizacao, dt)
		drift = lerpDt(drift, 0, Settings.DriftSuavizacao, dt)
		return camCF
	end

	wasActive = true

	dashFade = lerpDt(dashFade, isDashing and 0 or 1, Settings.DashFadeSuavizacao, dt)
	if dashFade < 0.001 then
		return camCF
	end

	currentVel = lerpDt(currentVel, getHorizontalSpeed(hrp), Settings.VelocidadeSuavizacao, dt)
	local velFactor = currentVel / Settings.DivisorEfeitos

	local rawMult = clamp(hum.WalkSpeed / Settings.WalkSpeedBase, Settings.WalkSpeedMultMin, Settings.WalkSpeedMultMax)
	currentSpeedMult = lerpDt(currentSpeedMult, rawMult, Settings.WalkSpeedSuavizacao, dt)

	bobbingPhase += dt * Settings.BobbingFrequencia * currentSpeedMult * velFactor
	if bobbingPhase > 1e6 then
		bobbingPhase %= (pi2 * 100)
	end

	local mx = UserInputService:GetMouseDelta().X
	drift = lerpDt(drift, clamp(mx, Settings.DriftMinimo, Settings.DriftMaximo), Settings.DriftSuavizacao, dt)

	local targetLean = -getLateralDot(hrp, hum) * Settings.LeanIntensidade
	currentLean = lerpDt(currentLean, targetLean, Settings.LeanSuavizacao, dt)

	local breathing = sin(clock() * Settings.RespiracaoFrequencia * pi2) * Settings.RespiracaoIntensidade
	local bobbing = sin(bobbingPhase) * Settings.BobbingIntensidade * velFactor

	local fade = calcAngleFade(camCF) * dashFade
	local yOffset = (bobbing + breathing) * fade
	local zAngle = (rad(drift) + rad(currentLean)) * fade

	return camCF * CFrame.new(0, yOffset, 0) * CFrame.Angles(0, 0, zAngle)
end

function DynamicCamFX.Cleanup() end

return DynamicCamFX
