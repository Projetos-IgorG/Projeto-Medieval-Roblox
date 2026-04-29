--!nonstrict

--[[
    Script: VehicleCameraCore.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/PlayerModule/CameraModule/VehicleCamera
    Responsabilidade: Executa o comportamento principal da camera de veiculos.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao implementa regras de gameplay do projeto; apenas apoia camera, controle e compatibilidade do jogador.
    Funcoes principais: new, step, setGoal, getCFrame, setTransform, getYaw
]]
local CameraUtils = require(script.Parent.Parent.CameraUtils)
local VehicleCameraConfig = require(script.Parent.VehicleCameraConfig)

local map = CameraUtils.map
local mapClamp = CameraUtils.mapClamp
local sanitizeAngle = CameraUtils.sanitizeAngle

local function getYaw(cf)
	local _, yaw = cf:toEulerAnglesYXZ()
	return sanitizeAngle(yaw)
end

local function getPitch(cf)
	local pitch = cf:toEulerAnglesYXZ()
	return sanitizeAngle(pitch)
end

local function stepSpringAxis(dt, f, g, p, v)
	local offset = sanitizeAngle(p - g)
	local decay = math.exp(-f * dt)

	local p1 = sanitizeAngle((offset * (1 + f * dt) + v * dt) * decay + g)
	local v1 = (v * (1 - f * dt) - offset * (f * f * dt)) * decay

	return p1, v1
end

local VariableEdgeSpring = {}
do
	VariableEdgeSpring.__index = VariableEdgeSpring

	function VariableEdgeSpring.new(fRising, fFalling, position)
		return setmetatable({
			fRising = fRising,
			fFalling = fFalling,
			g = position,
			p = position,
			v = position * 0,
		}, VariableEdgeSpring)
	end

	function VariableEdgeSpring:step(dt)
		local fRising = self.fRising
		local fFalling = self.fFalling
		local g = self.g
		local p0 = self.p
		local v0 = self.v

		local f = 2 * math.pi * (v0 > 0 and fRising or fFalling)

		local offset = p0 - g
		local decay = math.exp(-f * dt)

		local p1 = (offset * (1 + f * dt) + v0 * dt) * decay + g
		local v1 = (v0 * (1 - f * dt) - offset * (f * f * dt)) * decay

		self.p = p1
		self.v = v1

		return p1
	end
end

local YawPitchSpring = {}
do
	YawPitchSpring.__index = YawPitchSpring

	function YawPitchSpring.new(cf)
		assert(typeof(cf) == "CFrame", "YawPitchSpring requires a CFrame")

		return setmetatable({
			yawG = getYaw(cf),
			yawP = getYaw(cf),
			yawV = 0,

			pitchG = getPitch(cf),
			pitchP = getPitch(cf),
			pitchV = 0,

			fSpringYaw = VariableEdgeSpring.new(
				VehicleCameraConfig.yawReponseDampingRising,
				VehicleCameraConfig.yawResponseDampingFalling,
				0
			),
			fSpringPitch = VariableEdgeSpring.new(
				VehicleCameraConfig.pitchReponseDampingRising,
				VehicleCameraConfig.pitchResponseDampingFalling,
				0
			),
		}, YawPitchSpring)
	end

	function YawPitchSpring:setGoal(goalCFrame)
		assert(typeof(goalCFrame) == "CFrame", "setGoal requires a CFrame")

		self.yawG = getYaw(goalCFrame)
		self.pitchG = getPitch(goalCFrame)
	end

	function YawPitchSpring:getCFrame()
		return CFrame.fromEulerAnglesYXZ(self.pitchP, self.yawP, 0)
	end

	function YawPitchSpring:step(dt, pitchVel, yawVel, firstPerson)
		assert(typeof(dt) == "number", "dt must be a number")
		assert(typeof(yawVel) == "number", "yawVel must be a number")
		assert(typeof(pitchVel) == "number", "pitchVel must be a number")
		assert(typeof(firstPerson) == "number", "firstPerson must be a number")

		local fSpringYaw = self.fSpringYaw
		local fSpringPitch = self.fSpringPitch

		fSpringYaw.g = mapClamp(
			map(firstPerson, 0, 1, yawVel, 0),
			math.rad(VehicleCameraConfig.cutoffMinAngularVelYaw),
			math.rad(VehicleCameraConfig.cutoffMaxAngularVelYaw),
			1,
			0
		)

		fSpringPitch.g = mapClamp(
			map(firstPerson, 0, 1, pitchVel, 0),
			math.rad(VehicleCameraConfig.cutoffMinAngularVelPitch),
			math.rad(VehicleCameraConfig.cutoffMaxAngularVelPitch),
			1,
			0
		)

		local fYaw = 2 * math.pi * VehicleCameraConfig.yawStiffness * fSpringYaw:step(dt)
		local fPitch = 2 * math.pi * VehicleCameraConfig.pitchStiffness * fSpringPitch:step(dt)

		fPitch *= map(firstPerson, 0, 1, 1, VehicleCameraConfig.firstPersonResponseMul)
		fYaw *= map(firstPerson, 0, 1, 1, VehicleCameraConfig.firstPersonResponseMul)

		self.yawP, self.yawV = stepSpringAxis(dt, fYaw, self.yawG, self.yawP, self.yawV)

		self.pitchP, self.pitchV = stepSpringAxis(dt, fPitch, self.pitchG, self.pitchP, self.pitchV)

		return self:getCFrame()
	end
end

local VehicleCameraCore = {}
do
	VehicleCameraCore.__index = VehicleCameraCore

	function VehicleCameraCore.new(transform)
		return setmetatable({
			vrs = YawPitchSpring.new(transform),
		}, VehicleCameraCore)
	end

	function VehicleCameraCore:step(dt, pitchVel, yawVel, firstPerson)
		return self.vrs:step(dt, pitchVel, yawVel, firstPerson)
	end

	function VehicleCameraCore:setTransform(transform)
		self.vrs:setGoal(transform)
	end
end

return VehicleCameraCore
