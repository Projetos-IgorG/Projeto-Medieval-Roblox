--!strict

--[[
	Script: Movimento.luau (filho de Combate)
	Responsabilidade: Movimento e orientacao do NPC em combate: olhar para o
	alvo (AlignOrientation), manter faixa de alcance da arma, orbitar o alvo e
	escolher a animacao direcional de locomocao.
	Nao decide NADA de IA; apenas executa movimento pedido pela Decisao.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TiposNPC = require(ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC"):WaitForChild("Tipos"))

local Config = require(script.Parent:WaitForChild("Config"))
local Comportamento = require(script.Parent.Parent:WaitForChild("Comportamento"))

type Ctx = Comportamento.ContextoNPC

local Movimento = {}

-- =============================================================================
-- Orientacao (AlignOrientation no HRP; a orientacao visual fina e do client).
-- =============================================================================

local function obterOuCriarAlignOrientation(ctx: Ctx): AlignOrientation?
	local existente = ctx.estado.alignOrientacaoAlvo
	if typeof(existente) == "Instance" and existente:IsA("AlignOrientation") and existente.Parent then
		return existente :: AlignOrientation
	end

	local hrp = ctx.modelo.PrimaryPart
	if not hrp then
		return nil
	end

	local att = hrp:FindFirstChild("OrientacaoAlvoAttachment") :: Attachment?
	if not att then
		local novoAtt = Instance.new("Attachment")
		novoAtt.Name = "OrientacaoAlvoAttachment"
		novoAtt.Parent = hrp
		att = novoAtt
	end

	local ao = Instance.new("AlignOrientation")
	ao.Name = "AlignOrientacaoAlvo"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	-- Torque/responsividade baixos: so garante que o HRP nao fique de costas.
	ao.MaxTorque = 50000
	ao.Responsiveness = 12
	ao.Parent = hrp

	ctx.estado.alignOrientacaoAlvo = ao
	return ao
end

function Movimento.OrientarParaAlvo(ctx: Ctx, alvoPos: Vector3)
	ctx.humanoide.AutoRotate = false
	local ao = obterOuCriarAlignOrientation(ctx)
	local hrp = ctx.modelo.PrimaryPart
	if ao and hrp then
		local pos = hrp.Position
		local lookPlano = Vector3.new(alvoPos.X, pos.Y, alvoPos.Z)
		-- Threshold evita CFrame.lookAt degenerado (NaN) em proximidade extrema.
		if (lookPlano - pos).Magnitude > 0.8 then
			ao.CFrame = CFrame.lookAt(pos, lookPlano)
		end
	end
end

function Movimento.LimparOrientacao(ctx: Ctx)
	local existente = ctx.estado.alignOrientacaoAlvo
	if typeof(existente) == "Instance" then
		existente:Destroy()
	end
	ctx.estado.alignOrientacaoAlvo = nil

	local hrp = ctx.modelo.PrimaryPart
	if hrp then
		local att = hrp:FindFirstChild("OrientacaoAlvoAttachment")
		if att then
			att:Destroy()
		end
	end
	ctx.humanoide.AutoRotate = true
end

-- =============================================================================
-- Locomocao basica.
-- =============================================================================

function Movimento.Parar(ctx: Ctx)
	ctx.humanoide:Move(Vector3.zero, false)
	ctx.humanoide.WalkSpeed = 0
end

function Movimento.VelocidadePlanaModelo(modelo: Model): number
	local hrp = modelo:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return 0
	end
	local vel = hrp.AssemblyLinearVelocity
	return Vector3.new(vel.X, 0, vel.Z).Magnitude
end

function Movimento.AmbosParados(ctx: Ctx, alvo: Model): boolean
	local humAlvo = alvo:FindFirstChildOfClass("Humanoid")
	local alvoParado = Movimento.VelocidadePlanaModelo(alvo) < 0.8
		and (not humAlvo or humAlvo.MoveDirection.Magnitude < 0.1)
	local npcParado = Movimento.VelocidadePlanaModelo(ctx.modelo) < 0.8
		and ctx.humanoide.MoveDirection.Magnitude < 0.1
	return npcParado and alvoParado
end

-- =============================================================================
-- Animacao direcional.
-- =============================================================================

local function multiplicadorAnimacaoPorWalkSpeed(velocidade: number, correndo: boolean): number
	local baseAnim
	if velocidade <= Config.VELOCIDADE_BLOQUEANDO + 0.05 then
		baseAnim = Config.VELOCIDADE_BASE_ANIM_BLOQUEANDO
	elseif correndo then
		baseAnim = Config.VELOCIDADE_BASE_ANIM_CORRENDO
	else
		baseAnim = Config.VELOCIDADE_BASE_ANIM_ANDANDO
	end
	if baseAnim <= 0 then
		return 1
	end
	local ratio = velocidade / baseAnim
	return math.max(0.3, 1 + (ratio - 1) * 1.05)
end

local function escolherAnimDirecional(
	worldDir: Vector3,
	lookDir: Vector3,
	correndo: boolean,
	velocidade: number
): (string, number)
	if worldDir.Magnitude < 0.05 then
		return "Idle", 1
	end
	local forward = Vector3.new(lookDir.X, 0, lookDir.Z)
	if forward.Magnitude < 0.05 then
		forward = Vector3.new(0, 0, -1)
	else
		forward = forward.Unit
	end
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local moveXZ = Vector3.new(worldDir.X, 0, worldDir.Z).Unit
	local dotForward = forward:Dot(moveXZ)
	local dotRight = right:Dot(moveXZ)
	local prefixo = if correndo then "Correndo" else "Andando"
	local velocidadeAnim = multiplicadorAnimacaoPorWalkSpeed(velocidade, correndo)

	local temLateral = math.abs(dotRight) > 0.3
	local temFrontal = math.abs(dotForward) > 0.3
	if temLateral then
		local indoParaDireita = dotRight > 0
		local indoParaFrente = dotForward > 0
		if temFrontal then
			if indoParaDireita then
				return if indoParaFrente then prefixo .. "Direita" else prefixo .. "Esquerda",
					if indoParaFrente then velocidadeAnim else -velocidadeAnim
			else
				return if indoParaFrente then prefixo .. "Esquerda" else prefixo .. "Direita",
					if indoParaFrente then velocidadeAnim else -velocidadeAnim
			end
		end
		return if indoParaDireita then prefixo .. "Direita" else prefixo .. "Esquerda", velocidadeAnim
	elseif dotForward < -0.1 then
		return prefixo, -velocidadeAnim
	else
		return prefixo, velocidadeAnim
	end
end

-- Move na direcao dada mantendo o olhar no alvo. Retorna o nome da animacao
-- de locomocao; a velocidade da animacao fica em ctx.estado.velocidadeAnimacaoLocomocao.
function Movimento.MoverDirecaoMantendoOlhar(
	ctx: Ctx,
	alvoPos: Vector3,
	direcaoMundo: Vector3,
	velocidade: number,
	correndo: boolean
): string
	Movimento.OrientarParaAlvo(ctx, alvoPos)
	local dirPlana = Vector3.new(direcaoMundo.X, 0, direcaoMundo.Z)
	if dirPlana.Magnitude < 0.05 then
		Movimento.Parar(ctx)
		return "Idle"
	end
	local dirNorm = dirPlana.Unit
	ctx.humanoide.WalkSpeed = velocidade
	ctx.humanoide:Move(dirNorm, false)
	local pos = ctx.modelo:GetPivot().Position
	local lookPlano = Vector3.new(alvoPos.X - pos.X, 0, alvoPos.Z - pos.Z)
	local lookDir = if lookPlano.Magnitude > 0.01 then lookPlano.Unit else Vector3.new(0, 0, -1)
	local nomeAnim, velocidadeAnim = escolherAnimDirecional(dirNorm, lookDir, correndo, velocidade)
	ctx.estado.velocidadeAnimacaoLocomocao = velocidadeAnim
	return nomeAnim
end

-- =============================================================================
-- Faixa de alcance e orbita.
-- =============================================================================

function Movimento.MoverParaFaixaDeAlcance(
	ctx: Ctx,
	pos: Vector3,
	alvoPos: Vector3,
	distanciaAtual: number,
	alcance: number,
	distanciaCorrer: number,
	dt: number
): (boolean, string?)
	local distanciaMinima = math.max(0.5, alcance - Config.TOLERANCIA_ALCANCE)
	local distanciaMaxima = alcance + Config.TOLERANCIA_ALCANCE
	local erro = 0
	local sentido = 0

	if distanciaAtual > distanciaMaxima then
		erro = distanciaAtual - distanciaMaxima
		sentido = 1
	elseif distanciaAtual < distanciaMinima then
		erro = distanciaMinima - distanciaAtual
		sentido = -1
	else
		Movimento.Parar(ctx)
		return false, nil
	end

	local dirRadial = Vector3.new(alvoPos.X - pos.X, 0, alvoPos.Z - pos.Z)
	if dirRadial.Magnitude < 0.001 then
		Movimento.Parar(ctx)
		return false, nil
	end

	local direcaoMundo = if sentido > 0 then dirRadial.Unit else -dirRadial.Unit
	local correndo = sentido > 0 and distanciaAtual >= distanciaCorrer
	local velocidadeMaxima = if correndo then Config.VELOCIDADE_CORRENDO else Config.VELOCIDADE_ANDANDO
	local velocidade = math.min(velocidadeMaxima, (erro / math.max(dt, 0.05)) * 0.8)
	if velocidade < 0.05 then
		Movimento.Parar(ctx)
		return false, nil
	end
	local animLoco = Movimento.MoverDirecaoMantendoOlhar(ctx, alvoPos, direcaoMundo, velocidade, correndo)
	return true, animLoco
end

function Movimento.TentarOrbitar(
	ctx: Ctx,
	alvo: Model,
	pos: Vector3,
	alvoPos: Vector3,
	distanciaAtual: number,
	alcance: number,
	agora: number
): (boolean, string?)
	if (ctx.estado.orbitandoAte or 0) > agora then
		local radial = Vector3.new(pos.X - alvoPos.X, 0, pos.Z - alvoPos.Z)
		if radial.Magnitude < 0.001 then
			return false, nil
		end

		local dirRadial = radial.Unit
		local sinal = ctx.estado.orbitaSinal or 1
		local tangente = Vector3.new(-dirRadial.Z, 0, dirRadial.X) * sinal
		local erroRadial = distanciaAtual - alcance
		local correcaoRadial = -dirRadial * math.clamp(erroRadial / Config.TOLERANCIA_ALCANCE, -0.65, 0.65)
		local direcao = tangente + correcaoRadial
		local animLoco =
			Movimento.MoverDirecaoMantendoOlhar(ctx, alvoPos, direcao, Config.VELOCIDADE_ANDANDO, false)
		return true, animLoco
	end

	if (ctx.estado.proximaRolagemOrbita or 0) > agora then
		return false, nil
	end
	ctx.estado.proximaRolagemOrbita = agora + Config.INTERVALO_ROLAGEM_ORBITA

	if not Movimento.AmbosParados(ctx, alvo) then
		return false, nil
	end
	if math.abs(distanciaAtual - alcance) > Config.TOLERANCIA_ALCANCE then
		return false, nil
	end
	if math.random() > Config.CHANCE_ORBITA then
		return false, nil
	end

	ctx.estado.orbitandoAte = agora + Config.DURACAO_ORBITA
	ctx.estado.orbitaSinal = if math.random() < 0.5 then -1 else 1
	return Movimento.TentarOrbitar(ctx, alvo, pos, alvoPos, distanciaAtual, alcance, agora)
end

function Movimento.EstadoPorAnimacaoLocomocao(nomeAnimacao: string): string
	if string.sub(nomeAnimacao, 1, 8) == "Correndo" then
		return TiposNPC.Estado.Correndo
	end
	return TiposNPC.Estado.Andando
end

return Movimento
