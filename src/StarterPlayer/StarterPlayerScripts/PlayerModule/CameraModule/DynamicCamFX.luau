--!strict
--[[
	DynamicCamFX - Efeitos dinâmicos de câmera (apenas em 1ª pessoa)
	
	Baseado no FPV_DynamicCam por @isPauI (YT: @Paul1Rb)
	Adaptado para funcionar condicionalmente com o CameraModule existente.
	
	Efeitos aplicados (todos via CFrame direto):
	- Head Bobbing: oscilação vertical proporcional à velocidade
	- Respiração: oscilação vertical sutil quando parado
	- Mouse Drift: inclinação ao mover o mouse rapidamente
	- Lean Direcional: inclinação na direção do movimento lateral
	
	Frequência escala automaticamente com WalkSpeed do Humanoid.
	Efeitos desvanecem ao olhar pra cima/baixo e durante dash.
]]

local UserInputService = game:GetService("UserInputService")

local sin = math.sin
local rad = math.rad
local abs = math.abs
local clamp = math.clamp
local clock = os.clock
local pi2 = math.pi * 2

-- ═══════════════════════════════════════════════════════════════════
-- CONFIGURAÇÕES
-- ═══════════════════════════════════════════════════════════════════

local Settings = {
	-- Bobbing (oscilação vertical ao andar)
	BobbingFrequencia = 11,
	BobbingIntensidade = 0.09,

	-- Divisor geral (maior = efeitos mais suaves)
	DivisorEfeitos = 12,

	-- Multiplicador de WalkSpeed
	-- Frequência escala com WalkSpeed / WalkSpeedBase:
	--   WalkSpeed  8 (bloqueando)  → 0.9x (clamped pelo Min)
	--   WalkSpeed 14 (andando)     → 1.0x
	--   WalkSpeed 25 (correndo)    → 1.2x (clamped pelo Max)
	WalkSpeedBase = 14,
	WalkSpeedMultMin = 0.9,
	WalkSpeedMultMax = 1.05,
	WalkSpeedSuavizacao = 4,

	-- Suavização da velocidade
	VelocidadeSuavizacao = 5,

	-- Drift do mouse
	DriftMinimo = -3,
	DriftMaximo = 1,
	DriftSuavizacao = 12,

	-- Respiração (idle breathing)
	RespiracaoFrequencia = 0.2,
	RespiracaoIntensidade = 0.04,

	-- Lean direcional (ao andar pro lado)
	LeanIntensidade = 1,
	LeanSuavizacao = 3,

	-- Transição suave de dash
	DashFadeSuavizacao = 8,

	-- Fade ao olhar muito pra cima/baixo
	AnguloExtremoFadeInicio = 0.8,
	AnguloExtremoFadeFim = 0.95,
}

-- ═══════════════════════════════════════════════════════════════════
-- ESTADO INTERNO
-- ═══════════════════════════════════════════════════════════════════

local currentVel = 0
local drift = 0
local bobbingPhase = 0
local currentSpeedMult = 1.0
local currentLean = 0
local dashFade = 1.0
local wasActive = false

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES UTILITÁRIAS
-- ═══════════════════════════════════════════════════════════════════

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

-- ═══════════════════════════════════════════════════════════════════
-- API PÚBLICA
-- ═══════════════════════════════════════════════════════════════════

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

	-- Só aplicar efeitos de bobbing quando no chão
	local isOnGround = hum.FloorMaterial ~= Enum.Material.Air
	if not isOnGround then
		-- No ar: resetar estados suavemente para evitar corte brusco
		currentVel = lerpDt(currentVel, 0, Settings.VelocidadeSuavizacao, dt)
		currentLean = lerpDt(currentLean, 0, Settings.LeanSuavizacao, dt)
		drift = lerpDt(drift, 0, Settings.DriftSuavizacao, dt)
		return camCF
	end

	wasActive = true

	-- Dash fade (transição suave)
	dashFade = lerpDt(dashFade, isDashing and 0 or 1, Settings.DashFadeSuavizacao, dt)
	if dashFade < 0.001 then
		return camCF
	end

	-- Velocidade suavizada
	currentVel = lerpDt(currentVel, getHorizontalSpeed(hrp), Settings.VelocidadeSuavizacao, dt)
	local velFactor = currentVel / Settings.DivisorEfeitos

	-- Multiplicador de WalkSpeed suavizado
	local rawMult = clamp(hum.WalkSpeed / Settings.WalkSpeedBase, Settings.WalkSpeedMultMin, Settings.WalkSpeedMultMax)
	currentSpeedMult = lerpDt(currentSpeedMult, rawMult, Settings.WalkSpeedSuavizacao, dt)

	-- Avança fase do bobbing
	bobbingPhase += dt * Settings.BobbingFrequencia * currentSpeedMult * velFactor
	if bobbingPhase > 1e6 then
		bobbingPhase %= (pi2 * 100)
	end

	-- Mouse drift
	local mx = UserInputService:GetMouseDelta().X
	drift = lerpDt(drift, clamp(mx, Settings.DriftMinimo, Settings.DriftMaximo), Settings.DriftSuavizacao, dt)

	-- Lean direcional
	local targetLean = -getLateralDot(hrp, hum) * Settings.LeanIntensidade
	currentLean = lerpDt(currentLean, targetLean, Settings.LeanSuavizacao, dt)

	-- Calcula efeitos
	local breathing = sin(clock() * Settings.RespiracaoFrequencia * pi2) * Settings.RespiracaoIntensidade
	local bobbing = sin(bobbingPhase) * Settings.BobbingIntensidade * velFactor

	-- Aplica fades
	local fade = calcAngleFade(camCF) * dashFade
	local yOffset = (bobbing + breathing) * fade
	local zAngle = (rad(drift) + rad(currentLean)) * fade

	return camCF * CFrame.new(0, yOffset, 0) * CFrame.Angles(0, 0, zAngle)
end

function DynamicCamFX.Cleanup() end

return DynamicCamFX
