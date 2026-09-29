--!strict
--[[
	Módulo: InclinacaoTorso (TorsoTilt)
	Caminho: src/StarterPlayer/StarterCharacterScripts/Jogador/Camera
	Responsabilidade: Inclina o tronco conforme a câmera, pivotando na cintura.
	NÃO mexe no Neck — a cabeça é controlada por MovimentoCabeca.
	Uso: ModuleScript; importado pelo init.client.luau da Camera.

	A rotação é aplicada no RootJoint com pivot deslocado para a base do Torso
	(cintura), de modo que o corpo inclina naturalmente sem "flutuar" pra frente/trás.
	Os Hips recebem contra-rotação para manter as pernas paradas.

	Uso:
		local InclinacaoTorso = require(caminho.InclinacaoTorso)
		local tilt = InclinacaoTorso.new(character)
		tilt:Enable()
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserGameSettings = UserSettings():GetService("UserGameSettings")

assert(RunService:IsClient(), "InclinacaoTorso deve rodar no client (LocalScript).")

local PonteCliente: any = nil
task.spawn(function()
	local jogador = ReplicatedStorage:WaitForChild("Jogador", 5)
	if jogador then
		local com = jogador:WaitForChild("ComunicacaoCliente", 5)
		if com then
			local ponte = com:WaitForChild("PonteCliente", 5)
			if ponte then
				PonteCliente = require(ponte)
			end
		end
	end
end)

-- ── Tipos ──────────────────────────────────────────────────────────────

type Config = {
	MaxAngle: number, -- inclinação máxima do torso (rad)
	TiltFraction: number, -- fração do pitch da câmera aplicada ao torso (0–1)
	Smoothing: number, -- fator de lerp por segundo
	Invert: boolean,
	RequireShiftLockInThirdPerson: boolean,
	FirstPersonThreshold: number,
	ThirdPersonPitchThreshold: number, -- deadzone da câmera em 3ª pessoa para cima/baixo (rad)
	ThirdPersonMaxPitch: number, -- pitch da câmera em 3ª pessoa onde atinge inclinação máxima (rad)
}

export type TorsoTiltConfig = {
	MaxAngle: number?,
	TiltFraction: number?,
	Smoothing: number?,
	Invert: boolean?,
	RequireShiftLockInThirdPerson: boolean?,
	FirstPersonThreshold: number?,
	ThirdPersonPitchThreshold: number?,
	ThirdPersonMaxPitch: number?,
}

-- ── Defaults ───────────────────────────────────────────────────────────

local DEFAULT_CONFIG: Config = {
	MaxAngle = math.rad(45),
	TiltFraction = 0.6,
	Smoothing = 12,
	Invert = false,
	RequireShiftLockInThirdPerson = true,
	FirstPersonThreshold = 1.5,
	ThirdPersonPitchThreshold = math.rad(40),
	ThirdPersonMaxPitch = math.rad(70),
}

-- ── Classe ─────────────────────────────────────────────────────────────

local RENDER_NAME = "TorsoTilt_Update"

type TorsoTiltSelf = {
	config: Config,
	player: Player,
	character: Model,
	head: BasePart?,
	currentAngle: number,
	enabled: boolean,
	_conns: { RBXScriptConnection },

	-- Motor6Ds (R6)
	rootJoint: Motor6D?,
	leftHip: Motor6D?,
	rightHip: Motor6D?,

	-- CFrames originais
	rootJointBase: CFrame?,
	rootJointC1Rot: CFrame?, -- rotação do C1 do RootJoint (para transformar contra-rotação)
	leftHipBase: CFrame?,
	rightHipBase: CFrame?,

	-- Offset da cintura em relação ao ponto do joint, no espaço local de C0.
	-- Usado para pivotar a rotação na base do torso (cintura).
	waistPivot: CFrame?,
}

local InclinacaoTorso = {}
InclinacaoTorso.__index = InclinacaoTorso

type InclinacaoTorsoClass = typeof(setmetatable({} :: TorsoTiltSelf, InclinacaoTorso))
export type TorsoTiltInstance = InclinacaoTorsoClass

-- ── Constructor ────────────────────────────────────────────────────────

function InclinacaoTorso.new(character: Model, config: TorsoTiltConfig?): InclinacaoTorsoClass
	local self = setmetatable({} :: TorsoTiltSelf, InclinacaoTorso)
	self.config = table.clone(DEFAULT_CONFIG)
	if config then
		for k, v in pairs(config) do
			(self.config :: any)[k] = v
		end
	end

	self.player = Players.LocalPlayer
	self.currentAngle = 0
	self.enabled = false
	self._conns = {}

	self:_bindCharacter(character)
	return self
end

-- ── Bind (R6) ──────────────────────────────────────────────────────────

function InclinacaoTorso._bindCharacter(self: InclinacaoTorsoClass, character: Model)
	self.character = character
	self.head = character:WaitForChild("Head", 10) :: BasePart?
	self.currentAngle = 0

	local torso = character:WaitForChild("Torso", 5) :: BasePart?
	local rootPart = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?

	-- RootJoint: HumanoidRootPart → Torso
	if rootPart then
		self.rootJoint = rootPart:WaitForChild("RootJoint", 5) :: Motor6D?
	end

	-- Hips: Torso → Legs
	if torso then
		self.leftHip = torso:WaitForChild("Left Hip", 5) :: Motor6D?
		self.rightHip = torso:WaitForChild("Right Hip", 5) :: Motor6D?
	end

	-- Salva C0 originais
	if self.rootJoint then
		self.rootJointBase = self.rootJoint.C0
		-- Salva a rotação do C1 do RootJoint (usada para transformar a contra-rotação
		-- do espaço do C0 para o espaço local do Torso, levando em conta animações).
		local c1 = self.rootJoint.C1
		self.rootJointC1Rot = c1.Rotation
	end
	if self.leftHip then
		self.leftHipBase = self.leftHip.C0
	end
	if self.rightHip then
		self.rightHipBase = self.rightHip.C0
	end

	-- ── Calcula o pivot da cintura no espaço local do C0 ──
	-- No R6, o Torso tem 2 studs de altura. O RootJoint fica no centro do Torso.
	-- A cintura (base do Torso) fica 1 stud abaixo desse centro.
	--
	-- Para pivotar na cintura, precisamos saber o offset da cintura no espaço
	-- local do C0 do RootJoint. Como o C0 base já inclui a rotação que rearranja
	-- os eixos, usamos a orientação do C0 para transformar o offset mundo → local.
	if self.rootJointBase and torso then
		local torsoHalfHeight = torso.Size.Y * 0.5

		-- O offset da cintura relativo ao centro do joint é (0, -torsoHalfHeight, 0) no mundo.
		-- Transformamos para o espaço local do C0 usando apenas a rotação do C0 base.
		local c0Rot = self.rootJointBase.Rotation -- só rotação
		local localOffset = c0Rot:Inverse() * CFrame.new(0, -torsoHalfHeight, 0)

		self.waistPivot = CFrame.new(localOffset.Position)
	end
end

-- ── Condições ──────────────────────────────────────────────────────────

function InclinacaoTorso._isFirstPerson(self: InclinacaoTorsoClass): boolean
	if PonteCliente and type(PonteCliente.EstaEmPrimeiraPessoa) == "function" then
		local ok, inFP = pcall(PonteCliente.EstaEmPrimeiraPessoa)
		if ok and type(inFP) == "boolean" then
			return inFP
		end
	end
	if not self.head then
		return false
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return false
	end
	return (cam.CFrame.Position - self.head.Position).Magnitude <= self.config.FirstPersonThreshold
end

function InclinacaoTorso._isShiftLock(_self: InclinacaoTorsoClass): boolean
	return UserGameSettings.RotationType == Enum.RotationType.CameraRelative
end

function InclinacaoTorso._isParkour(self: InclinacaoTorsoClass): boolean
	if PonteCliente and type(PonteCliente.EstaEmParkour) == "function" then
		local ok, active = pcall(PonteCliente.EstaEmParkour)
		if ok and active == true then
			return true
		end
	end
	if self.character then
		if self.character:GetAttribute("EmParkour") == true or self.character:GetAttribute("Parkour") == true then
			return true
		end
	end
	return false
end

function InclinacaoTorso._isCrouched(self: InclinacaoTorsoClass): boolean
	if PonteCliente and type(PonteCliente.LerStatusLocal) == "function" then
		local ok, val = pcall(PonteCliente.LerStatusLocal, "AgachadoOn")
		if ok and val == true then
			return true
		end
	end
	if self.character then
		local statusLocal = self.character:FindFirstChild("StatusLocal")
		if statusLocal then
			local agachadoVal = statusLocal:FindFirstChild("AgachadoOn")
			if agachadoVal and agachadoVal:IsA("BoolValue") and agachadoVal.Value == true then
				return true
			end
		end

		local status = self.character:FindFirstChild("Status")
		if status then
			local agachadoVal = status:FindFirstChild("Agachado")
			if agachadoVal and agachadoVal:IsA("BoolValue") and agachadoVal.Value == true then
				return true
			end
		end

		if self.character:GetAttribute("Agachado") == true or self.character:GetAttribute("AgachadoOn") == true then
			return true
		end
	end
	return false
end

function InclinacaoTorso._shouldTilt(self: InclinacaoTorsoClass): boolean
	if self:_isParkour() then
		return false
	end
	if self:_isCrouched() then
		return false
	end
	if self:_isFirstPerson() then
		return true
	end
	if self.config.RequireShiftLockInThirdPerson then
		return self:_isShiftLock()
	end
	return true
end

function InclinacaoTorso.ShouldTilt(self: InclinacaoTorsoClass): boolean
	return self:_shouldTilt()
end

-- ── Update ─────────────────────────────────────────────────────────────

function InclinacaoTorso._update(self: InclinacaoTorsoClass, dt: number)
	if not self.character or not self.character.Parent then
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end

	-- Calcula ângulo alvo
	local targetAngle = 0
	local active = self:_shouldTilt()
	if active then
		local pitch = math.asin(math.clamp(cam.CFrame.LookVector.Y, -1, 1))
		local isFirstPerson = self:_isFirstPerson()

		if isFirstPerson then
			-- 1ª pessoa: inclinação fluida proporcional ao pitch da câmera
			targetAngle = -math.clamp(pitch, -self.config.MaxAngle, self.config.MaxAngle) * self.config.TiltFraction
		else
			-- 3ª pessoa: deadzone simétrica para cima e para baixo.
			-- Câmera levemente inclinada (até ~45°) não mexe no torso.
			-- Quando estiver olhando bem para cima ou bem para baixo (acima do threshold), inclina suavemente até o limite.
			local absPitch = math.abs(pitch)
			local threshold = self.config.ThirdPersonPitchThreshold
			local maxPitch = self.config.ThirdPersonMaxPitch

			if absPitch <= threshold then
				targetAngle = 0
			else
				local span = math.max(maxPitch - threshold, 0.0001)
				local progress = math.clamp((absPitch - threshold) / span, 0, 1)
				local maxTilt = self.config.MaxAngle * self.config.TiltFraction
				targetAngle = -math.sign(pitch) * maxTilt * progress
			end
		end

		if self.config.Invert then
			targetAngle = -targetAngle
		end
	end

	-- Suaviza
	local alpha = math.clamp(dt * self.config.Smoothing, 0, 1)
	self.currentAngle += (targetAngle - self.currentAngle) * alpha

	local angle = self.currentAngle

	-- ── RootJoint: inclina o torso pivotando na cintura ──
	-- A rotação é aplicada no espaço local do C0 do RootJoint.
	-- Deslocamos para o pivot (cintura), rotacionamos, e voltamos.
	if self.rootJoint and self.rootJointBase and self.rootJointC1Rot and self.waistPivot then
		local pivot = self.waistPivot
		local rotation = CFrame.Angles(angle, 0, 0)
		-- Pivot: translada ao pivot, rotaciona, volta, e aplica sobre o C0 base.
		local targetCFrame = self.rootJointBase * pivot * rotation * pivot:Inverse()
		self.rootJoint.C0 = self.rootJoint.C0:Lerp(targetCFrame, alpha)

		-- CFrames do Torso em relação ao HRP sem tilt (0) e com tilt atual
		local C1 = self.rootJoint.C1
		local Transform = self.rootJoint.Transform
		local Torso_CF_0 = self.rootJointBase * Transform * C1:Inverse()
		local Torso_CF_tilt = self.rootJoint.C0 * Transform * C1:Inverse()

		-- Contra-rotação e ancoragem de posição nos Hips
		local C1_rot = self.rootJointC1Rot
		local T_rot = Transform.Rotation -- só rotação
		local R_tilt_inv = CFrame.Angles(-angle, 0, 0)
		local counterInTorso = C1_rot * T_rot:Inverse() * R_tilt_inv * T_rot * C1_rot:Inverse()

		if self.leftHip and self.leftHipBase then
			local basePos = self.leftHipBase.Position
			local baseRot = self.leftHipBase.Rotation
			-- Ancoragem de posição: trava o joint do quadril na posição 3D original em relação ao HRP
			local targetHRP = Torso_CF_0 * basePos
			local localPos = Torso_CF_tilt:PointToObjectSpace(targetHRP)

			local counterCF = CFrame.new(localPos) * counterInTorso * baseRot
			self.leftHip.C0 = self.leftHip.C0:Lerp(counterCF, alpha)
		end
		if self.rightHip and self.rightHipBase then
			local basePos = self.rightHipBase.Position
			local baseRot = self.rightHipBase.Rotation
			-- Ancoragem de posição: trava o joint do quadril na posição 3D original em relação ao HRP
			local targetHRP = Torso_CF_0 * basePos
			local localPos = Torso_CF_tilt:PointToObjectSpace(targetHRP)

			local counterCF = CFrame.new(localPos) * counterInTorso * baseRot
			self.rightHip.C0 = self.rightHip.C0:Lerp(counterCF, alpha)
		end
	end
end

-- ── Enable / Disable / Destroy ─────────────────────────────────────────

function InclinacaoTorso.Enable(self: InclinacaoTorsoClass)
	if self.enabled then
		return
	end
	self.enabled = true
	local renderName = RENDER_NAME .. "_" .. self.character.Name
	RunService:BindToRenderStep(renderName, Enum.RenderPriority.Character.Value + 1, function(dt)
		self:_update(dt)
	end)
end

function InclinacaoTorso.Disable(self: InclinacaoTorsoClass)
	if not self.enabled then
		return
	end
	self.enabled = false
	RunService:UnbindFromRenderStep(RENDER_NAME .. "_" .. self.character.Name)
	self.currentAngle = 0

	-- Restaura C0 originais
	if self.rootJoint and self.rootJointBase then
		self.rootJoint.C0 = self.rootJointBase
	end
	if self.leftHip and self.leftHipBase then
		self.leftHip.C0 = self.leftHipBase
	end
	if self.rightHip and self.rightHipBase then
		self.rightHip.C0 = self.rightHipBase
	end
end

function InclinacaoTorso.Destroy(self: InclinacaoTorsoClass)
	self:Disable()
	for _, c in ipairs(self._conns) do
		c:Disconnect()
	end
	table.clear(self._conns)
end

return InclinacaoTorso
