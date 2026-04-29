--[[
    Script: GerenciadorNPCCombate.luau
    Caminho: src/ServerScriptService/Combate/Servidor
    Responsabilidade: Gerencia IA de NPCs de combate, busca de alvos, perseguicao e ataques.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao roda sozinho nem cria fluxo de jogo por conta propria; depende dos scripts que importam este modulo.
    Funcoes principais: Novo, EncontrarAlvo, RotacionarParaAlvo, MoverParaAlvo, TentarAtacar, Atualizar
]]
local DEBUG_ENABLED = false

local function DebugPrint(...)
	if DEBUG_ENABLED then
		print(...)
	end
end

local Players = game:GetService("Players")

local RunService = game:GetService("RunService")

local ServerScriptService = game:GetService("ServerScriptService")
local CombateServidor = ServerScriptService:WaitForChild("Combate"):WaitForChild("Servidor")
local ControladorCombate = require(CombateServidor:WaitForChild("CombateServidor"))

local GerenciadorNPC = {}

local ConfiguracaoIA = {

	RaioDeteccao = 50,
	RaioPararPerseguir = 60,

	VelocidadePerto = 13,
	VelocidadeLonge = 16,
	DistanciaPerto = 15,

	DistanciaAtaque = 6.5,
	DistanciaIniciarAtaque = 5.8,
	DistanciaContinuarCombo = 6.2,

	VelocidadeRotacao = 10,

	DelayEntreAtaques = 0.3,
	DelayAposCombo = 1.0,
}

local npcsAtivos = {}

local NPCController = {}
NPCController.__index = NPCController

function NPCController.Novo(modelo: Model)
	local self = setmetatable({}, NPCController)

	self.modelo = modelo
	self.humanoid = modelo:FindFirstChildOfClass("Humanoid")
	self.humanoidRoot = modelo:FindFirstChild("HumanoidRootPart")

	self.maquina = ControladorCombate.ObterMaquina(modelo)

	local modo = modelo:GetAttribute("ModoCombate") or "Punhos"
	self.maquina:DefinirModo(modo)

	self.alvo = nil
	self.ultimoAtaque = 0
	self.indiceComboAtual = 0
	self.ativo = true

	self.conexoes = {}

	return self
end

function NPCController:EncontrarAlvo(): Player?
	local posicaoNPC = self.humanoidRoot.Position
	local menorDistancia = ConfiguracaoIA.RaioDeteccao
	local alvoMaisProximo = nil

	for _, jogador in ipairs(Players:GetPlayers()) do
		local personagem = jogador.Character
		if personagem then
			local humanoidJogador = personagem:FindFirstChildOfClass("Humanoid")
			local rootJogador = personagem:FindFirstChild("HumanoidRootPart")

			if humanoidJogador and rootJogador and humanoidJogador.Health > 0 then
				local distancia = (rootJogador.Position - posicaoNPC).Magnitude

				if distancia < menorDistancia then
					menorDistancia = distancia
					alvoMaisProximo = jogador
				end
			end
		end
	end

	return alvoMaisProximo
end

function NPCController:RotacionarParaAlvo(dt: number)
	if not self.alvo or not self.alvo.Character then
		return
	end

	local alvoRoot = self.alvo.Character:FindFirstChild("HumanoidRootPart")
	if not alvoRoot then
		return
	end

	local direcao = (alvoRoot.Position - self.humanoidRoot.Position)
	direcao = Vector3.new(direcao.X, 0, direcao.Z).Unit

	if direcao.Magnitude < 0.1 then
		return
	end

	local anguloAlvo = math.atan2(-direcao.X, -direcao.Z)
	local anguloAtual = math.atan2(-self.humanoidRoot.CFrame.LookVector.X, -self.humanoidRoot.CFrame.LookVector.Z)

	local diferenca = anguloAlvo - anguloAtual

	while diferenca > math.pi do
		diferenca = diferenca - 2 * math.pi
	end
	while diferenca < -math.pi do
		diferenca = diferenca + 2 * math.pi
	end

	local novoAngulo = anguloAtual + diferenca * math.min(ConfiguracaoIA.VelocidadeRotacao * dt, 1)

	self.humanoidRoot.CFrame = CFrame.new(self.humanoidRoot.Position) * CFrame.Angles(0, novoAngulo, 0)
end

function NPCController:MoverParaAlvo()
	if not self.alvo or not self.alvo.Character then
		return
	end

	local alvoRoot = self.alvo.Character:FindFirstChild("HumanoidRootPart")
	if not alvoRoot then
		return
	end

	local distancia = (alvoRoot.Position - self.humanoidRoot.Position).Magnitude

	if distancia > ConfiguracaoIA.DistanciaPerto then
		self.humanoid.WalkSpeed = ConfiguracaoIA.VelocidadeLonge
	else
		self.humanoid.WalkSpeed = ConfiguracaoIA.VelocidadePerto
	end

	self.humanoid:MoveTo(alvoRoot.Position)
end

function NPCController:TentarAtacar(): boolean
	if not self.alvo or not self.alvo.Character then
		return false
	end

	local alvoRoot = self.alvo.Character:FindFirstChild("HumanoidRootPart")
	if not alvoRoot then
		return false
	end

	local distancia = (alvoRoot.Position - self.humanoidRoot.Position).Magnitude
	local agora = tick()

	if self.indiceComboAtual > 0 then

		if distancia > ConfiguracaoIA.DistanciaContinuarCombo then
			return false
		end
	else

		if distancia > ConfiguracaoIA.DistanciaIniciarAtaque then
			return false
		end
	end

	local delay = self.indiceComboAtual > 0 and ConfiguracaoIA.DelayEntreAtaques or ConfiguracaoIA.DelayAposCombo
	if (agora - self.ultimoAtaque) < delay then
		return false
	end

	local sucesso, tipoAtaque = ControladorCombate.ProcessarAtacarLeveEmPe(self.modelo)

	if sucesso then
		self.ultimoAtaque = agora
		self.indiceComboAtual = self.maquina:ObterIndiceCombo()

		if self.indiceComboAtual == 0 or tipoAtaque == "AtaqueLeveFinal" then
			self.indiceComboAtual = 0
			self.ultimoAtaque = agora
		end

		return true
	end

	return false
end

function NPCController:Atualizar(dt: number)
	if not self.ativo then
		return
	end
	if not self.humanoid or self.humanoid.Health <= 0 then
		self:Desativar()
		return
	end

	if self.maquina:EstaStunado() then
		self.humanoid:MoveTo(self.humanoidRoot.Position)
		return
	end

	if self.alvo then
		local personagemAlvo = self.alvo.Character
		if not personagemAlvo then
			self.alvo = nil
		else
			local rootAlvo = personagemAlvo:FindFirstChild("HumanoidRootPart")
			local humanoidAlvo = personagemAlvo:FindFirstChildOfClass("Humanoid")

			if not rootAlvo or not humanoidAlvo or humanoidAlvo.Health <= 0 then
				self.alvo = nil
			else
				local distancia = (rootAlvo.Position - self.humanoidRoot.Position).Magnitude
				if distancia > ConfiguracaoIA.RaioPararPerseguir then
					self.alvo = nil
				end
			end
		end
	end

	if not self.alvo then
		self.alvo = self:EncontrarAlvo()
		self.indiceComboAtual = 0
	end

	if not self.alvo then
		self.humanoid:MoveTo(self.humanoidRoot.Position)
		return
	end

	self:RotacionarParaAlvo(dt)

	local alvoRoot = self.alvo.Character:FindFirstChild("HumanoidRootPart")
	if alvoRoot then
		local distancia = (alvoRoot.Position - self.humanoidRoot.Position).Magnitude

		if distancia <= ConfiguracaoIA.DistanciaAtaque then

			self.humanoid:MoveTo(self.humanoidRoot.Position)
			self:TentarAtacar()
		else

			self:MoverParaAlvo()
		end
	end
end

function NPCController:AplicarRagdoll()
	for _, parte in ipairs(self.modelo:GetDescendants()) do
		if parte:IsA("Motor6D") then
			local anexo0 = Instance.new("Attachment")
			anexo0.CFrame = parte.C0
			anexo0.Parent = parte.Part0

			local anexo1 = Instance.new("Attachment")
			anexo1.CFrame = parte.C1
			anexo1.Parent = parte.Part1

			local junta = Instance.new("BallSocketConstraint")
			junta.Attachment0 = anexo0
			junta.Attachment1 = anexo1
			junta.LimitsEnabled = true
			junta.TwistLimitsEnabled = true
			junta.Parent = parte.Part0

			parte:Destroy()
		end
	end

	self.humanoid.PlatformStand = true
end

function NPCController:Desativar()
	self.ativo = false

	for _, conexao in ipairs(self.conexoes) do
		if conexao.Connected then
			conexao:Disconnect()
		end
	end

	npcsAtivos[self.modelo] = nil

	if self.humanoid and self.humanoid.Health <= 0 then
		self:AplicarRagdoll()
	end

	ControladorCombate.RemoverMaquina(self.modelo)
end

function GerenciadorNPC.RegistrarNPC(modelo: Model)
	if npcsAtivos[modelo] then
		return
	end

	local controller = NPCController.Novo(modelo)
	npcsAtivos[modelo] = controller

	if controller.humanoid then
		table.insert(
			controller.conexoes,
			controller.humanoid.Died:Connect(function()
				controller:Desativar()
			end)
		)
	end

	table.insert(
		controller.conexoes,
		modelo.AncestryChanged:Connect(function(_, parent)
			if not parent then
				controller:Desativar()
			end
		end)
	)

	DebugPrint("[GerenciadorNPC] NPC registrado: " .. modelo.Name)
end

function GerenciadorNPC.RemoverNPC(modelo: Model)
	local controller = npcsAtivos[modelo]
	if controller then
		controller:Desativar()
	end
end

function GerenciadorNPC.ObterController(modelo: Model)
	return npcsAtivos[modelo]
end

RunService.Heartbeat:Connect(function(dt)
	for _modelo, controller in pairs(npcsAtivos) do
		if controller.ativo then
			controller:Atualizar(dt)
		end
	end
end)

local pastaNPCs = workspace:FindFirstChild("NPCs")
if pastaNPCs then
	for _, modelo in ipairs(pastaNPCs:GetChildren()) do
		if modelo:IsA("Model") and modelo:FindFirstChildOfClass("Humanoid") then
			GerenciadorNPC.RegistrarNPC(modelo)
		end
	end

	pastaNPCs.ChildAdded:Connect(function(modelo)
		if modelo:IsA("Model") and modelo:FindFirstChildOfClass("Humanoid") then
			task.wait(0.1)
			GerenciadorNPC.RegistrarNPC(modelo)
		end
	end)
end

DebugPrint("[GerenciadorNPC] Inicializado")

return GerenciadorNPC
