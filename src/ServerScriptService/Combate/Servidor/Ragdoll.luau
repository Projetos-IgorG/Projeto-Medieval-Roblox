--!strict

--[[
	Script: Ragdoll.luau
	Caminho: src/ServerScriptService/Combate/Ragdoll  (ModuleScript - SERVIDOR)
	Responsabilidade: Transformar um modelo (NPC ou Player) em ragdoll, preservando
		momento linear e aplicando impulso direcional do atacante.
	Funcoes principais: Ativar, Desativar, RegistrarAtaque, MatarComRagdoll
]]

local Players = game:GetService("Players")

local Ragdoll = {}

-- Limites por junta. Se a junta nao estiver aqui, usa PADRAO.
local PADRAO = { angulo = 55, twistMin = -35, twistMax = 35 }
local LIMITES: { [string]: { angulo: number, twistMin: number, twistMax: number } } = {
	-- R6
	["Neck"] = { angulo = 35, twistMin = -30, twistMax = 30 },
	["Left Shoulder"] = { angulo = 80, twistMin = -45, twistMax = 45 },
	["Right Shoulder"] = { angulo = 80, twistMin = -45, twistMax = 45 },
	["Left Hip"] = { angulo = 60, twistMin = -20, twistMax = 40 },
	["Right Hip"] = { angulo = 60, twistMin = -20, twistMax = 40 },
	-- R15 (nomes principais)
	["Waist"] = { angulo = 25, twistMin = -20, twistMax = 20 },
	["LeftShoulder"] = { angulo = 80, twistMin = -45, twistMax = 45 },
	["RightShoulder"] = { angulo = 80, twistMin = -45, twistMax = 45 },
	["LeftElbow"] = { angulo = 45, twistMin = -5, twistMax = 5 },
	["RightElbow"] = { angulo = 45, twistMin = -5, twistMax = 5 },
	["LeftHip"] = { angulo = 60, twistMin = -20, twistMax = 40 },
	["RightHip"] = { angulo = 60, twistMin = -20, twistMax = 40 },
	["LeftKnee"] = { angulo = 45, twistMin = -5, twistMax = 5 },
	["RightKnee"] = { angulo = 45, twistMin = -5, twistMax = 5 },
}

local ATTR_RAGDOLL = "Ragdoll" -- flag replicada (clientes escutam)
local ATTR_DIR = "UltimaDirecaoAtaque" -- Vector3
local ATTR_TEMPO = "UltimoAtaqueTempo" -- os.clock() do servidor
local JANELA_ATAQUE = 5 -- s: depois disso a direcao guardada expira

-- =============================================================================
-- Helpers
-- =============================================================================

local function pararAnimacoesServidor(humanoide: Humanoid)
	local animator = humanoide:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	for _, track in animator:GetPlayingAnimationTracks() do
		track:Stop(0)
	end
end

-- O Animate padrao do Player continua tocando localmente durante Physics state.
local function desligarAnimateDoPlayer(modelo: Model)
	local animate = modelo:FindFirstChild("Animate")
	if animate and animate:IsA("LocalScript") then
		animate.Disabled = true
	end
end

local function converterJunta(motor: Motor6D): boolean
	local p0, p1 = motor.Part0, motor.Part1
	if not p0 or not p1 then
		return false
	end

	local cfg = LIMITES[motor.Name] or PADRAO

	local a0 = Instance.new("Attachment")
	a0.Name = "RagdollAtt0_" .. motor.Name
	a0.CFrame = motor.C0
	a0.Parent = p0

	local a1 = Instance.new("Attachment")
	a1.Name = "RagdollAtt1_" .. motor.Name
	a1.CFrame = motor.C1
	a1.Parent = p1

	local bs = Instance.new("BallSocketConstraint")
	bs.Name = "RagdollJoint_" .. motor.Name
	bs.Attachment0 = a0
	bs.Attachment1 = a1
	bs.LimitsEnabled = true
	bs.UpperAngle = cfg.angulo
	bs.TwistLimitsEnabled = true
	bs.TwistLowerAngle = cfg.twistMin
	bs.TwistUpperAngle = cfg.twistMax
	bs.Radius = 0.15
	bs.Parent = p0

	motor.Enabled = false
	return true
end

-- HRP nao virou constraint: fica soldado ao torso para o Humanoid continuar valido.
local function ancorarRootAoTorso(modelo: Model): ()
	local hrp = modelo:FindFirstChild("HumanoidRootPart") :: BasePart?
	local torso = (modelo:FindFirstChild("Torso") or modelo:FindFirstChild("UpperTorso")) :: BasePart?
	if not hrp or not torso then
		return
	end

	local root = hrp:FindFirstChild("RootJoint") :: Motor6D?
	if root and root:IsA("Motor6D") then
		root.Enabled = false
	end

	hrp.CanCollide = false
	hrp.Massless = true

	local weld = Instance.new("Weld")
	weld.Name = "RagdollRootWeld"
	weld.Part0 = torso
	weld.Part1 = hrp
	weld.C0 = torso.CFrame:ToObjectSpace(hrp.CFrame)
	weld.Parent = torso
end

-- =============================================================================
-- API
-- =============================================================================

--[[
	Guarda a direcao do olhar do atacante no momento do hit.
	Chame isso no seu pipeline de dano (ex: _ProcessarHit), ANTES de o alvo morrer.
]]
function Ragdoll.RegistrarAtaque(alvo: Model, atacante: Model?)
	if not atacante then
		return
	end
	local origem = (atacante:FindFirstChild("Head") or atacante:FindFirstChild("HumanoidRootPart")) :: BasePart?
	if not origem then
		return
	end
	local dir = origem.CFrame.LookVector
	alvo:SetAttribute(ATTR_DIR, Vector3.new(dir.X, dir.Y, dir.Z))
	alvo:SetAttribute(ATTR_TEMPO, os.clock())
end

export type OpcoesRagdoll = {
	direcao: Vector3?, -- direcao do impulso; default = direcao registrada no ultimo ataque
	forca: number?, -- studs/s aplicados via impulso (default 40)
	elevacao: number?, -- 0..1, quanto do impulso vai pra cima (default 0.35)
	giro: number?, -- torque angular aleatorio (default 12)
	limpar: number?, -- segundos ate destruir o modelo (nil = nao destroi)
}

--[[
	Ativa o ragdoll. Idempotente: chamadas repetidas sao ignoradas.
]]
function Ragdoll.Ativar(modelo: Model, opcoes: OpcoesRagdoll?): boolean
	if modelo:GetAttribute(ATTR_RAGDOLL) == true then
		return false
	end
	local humanoide = modelo:FindFirstChildOfClass("Humanoid")
	if not humanoide then
		return false
	end

	local o = opcoes or {} :: OpcoesRagdoll
	local forca = o.forca or 67
	local elevacao = o.elevacao or 0.45
	local giro = o.giro or 12

	modelo:SetAttribute(ATTR_RAGDOLL, true)

	-- 1) Snapshot do momento ANTES de soltar as juntas.
	local hrp = modelo:FindFirstChild("HumanoidRootPart") :: BasePart?
	local velBase = hrp and hrp.AssemblyLinearVelocity or Vector3.zero
	if velBase.Magnitude < 0.1 then
		-- Humanoid parado no chao pode ter velocidade quase zero mesmo andando;
		-- usa MoveDirection * WalkSpeed como fallback.
		velBase = humanoide.MoveDirection * humanoide.WalkSpeed
	end

	-- 2) Humanoid entra em modo fisico e para de se controlar.
	humanoide.RequiresNeck = false
	humanoide.AutoRotate = false
	humanoide.WalkSpeed = 0
	humanoide.JumpPower = 0
	humanoide:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
	humanoide:SetStateEnabled(Enum.HumanoidStateType.Running, false)
	humanoide:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	humanoide:ChangeState(Enum.HumanoidStateType.Physics)
	humanoide.PlatformStand = true

	pararAnimacoesServidor(humanoide)
	if Players:GetPlayerFromCharacter(modelo) then
		desligarAnimateDoPlayer(modelo)
	end

	-- 3) Converte todas as juntas (menos a root).
	for _, d in modelo:GetDescendants() do
		if d:IsA("Motor6D") and d.Enabled and d.Name ~= "RootJoint" then
			converterJunta(d)
		end
	end
	ancorarRootAoTorso(modelo)

	-- 4) Restaura o momento em cada parte (cada parte virou uma assembly propria).
	local partes: { BasePart } = {}
	for _, d in modelo:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(partes, d)
			if d.Name ~= "HumanoidRootPart" then
				d.CanCollide = true
			end
		end
	end
	for _, p in partes do
		p.AssemblyLinearVelocity = velBase
	end

	-- 5) Impulso direcional do atacante.
	local dir = o.direcao
	if not dir then
		local guardada = modelo:GetAttribute(ATTR_DIR)
		local tempo = modelo:GetAttribute(ATTR_TEMPO)
		if typeof(guardada) == "Vector3" and typeof(tempo) == "number" and (os.clock() - tempo) <= JANELA_ATAQUE then
			dir = guardada
		end
	end

	if dir and dir.Magnitude > 0.001 then
		local plano = Vector3.new(dir.X, 0, dir.Z)
		plano = if plano.Magnitude > 0.001 then plano.Unit else Vector3.zero
		local final = (plano * (1 - elevacao) + Vector3.yAxis * elevacao).Unit

		local alvoImpulso = (modelo:FindFirstChild("Torso") or modelo:FindFirstChild("UpperTorso")) :: BasePart?
		if alvoImpulso then
			alvoImpulso:ApplyImpulse(final * forca * alvoImpulso.AssemblyMass)
			alvoImpulso:ApplyAngularImpulse(
				Vector3.new(math.random(-giro, giro), math.random(-giro, giro), math.random(-giro, giro))
					* alvoImpulso.AssemblyMass
					* 0.1
			)
		end
		-- Um pouco no torso superior/cabeca pra leitura visual do golpe.
		local head = modelo:FindFirstChild("Head") :: BasePart?
		if head then
			head:ApplyImpulse(final * forca * 0.3 * head.AssemblyMass)
		end
	end

	if o.limpar then
		task.delay(o.limpar, function()
			if modelo.Parent then
				modelo:Destroy()
			end
		end)
	end

	return true
end

--[[
	Desfaz o ragdoll (util para NPCs derrubados sem morrer, ou revive).
]]
function Ragdoll.Desativar(modelo: Model): boolean
	if modelo:GetAttribute(ATTR_RAGDOLL) ~= true then
		return false
	end
	modelo:SetAttribute(ATTR_RAGDOLL, false)

	for _, d in modelo:GetDescendants() do
		if
			(d:IsA("BallSocketConstraint") and d.Name:match("^RagdollJoint_"))
			or (d:IsA("Attachment") and d.Name:match("^RagdollAtt"))
			or (d:IsA("Weld") and d.Name == "RagdollRootWeld")
		then
			d:Destroy()
		elseif d:IsA("Motor6D") then
			d.Enabled = true
		end
	end

	local hrp = modelo:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		hrp.Massless = false
	end

	local humanoide = modelo:FindFirstChildOfClass("Humanoid")
	if humanoide then
		humanoide.PlatformStand = false
		humanoide:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
		humanoide:SetStateEnabled(Enum.HumanoidStateType.Running, true)
		humanoide:SetStateEnabled(Enum.HumanoidStateType.Climbing, true)
		humanoide:ChangeState(Enum.HumanoidStateType.GettingUp)
		humanoide.AutoRotate = true
	end

	local animate = modelo:FindFirstChild("Animate")
	if animate and animate:IsA("LocalScript") then
		animate.Disabled = false
	end

	return true
end

--[[
	Atalho: mata o alvo e ragdolla com impulso na direcao do olhar do atacante.
]]
function Ragdoll.MatarComRagdoll(alvo: Model, atacante: Model?, forca: number?)
	Ragdoll.RegistrarAtaque(alvo, atacante)
	local humanoide = alvo:FindFirstChildOfClass("Humanoid")
	if humanoide and humanoide.Health > 0 then
		humanoide.Health = 0
	end
	Ragdoll.Ativar(alvo, { forca = forca })
end

return Ragdoll
