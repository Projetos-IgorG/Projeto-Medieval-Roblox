--[[
    GerenciadorNPC.luau (Módulo)
    
    Script do servidor para gerenciar IA de NPCs.
    Usa MaquinaDeEstados e ControladorCombate compartilhados com players.
    
    Funcionalidades:
    - Detecção de alvos
    - Movimentação e perseguição
    - Combate usando sistema unificado
    - Ragdoll na morte
]]

-- ═══════════════════════════════════════════════════════════════════
-- CONFIGURAÇÃO DE DEBUG
-- ═══════════════════════════════════════════════════════════════════
local DEBUG_ENABLED = false -- Altere para true para habilitar prints de debug

local function DebugPrint(...)
	if DEBUG_ENABLED then
		print(...)
	end
end

local Players = game:GetService("Players")
-- local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- local Modulos = ReplicatedStorage:WaitForChild("Modulos")
-- local MaquinaDeEstados = require(Modulos:WaitForChild("MaquinaDeEstados")) -- Removido se não usado diretamente

local ServerScriptService = game:GetService("ServerScriptService")
local Servicos = ServerScriptService:WaitForChild("Servicos")
local Combate = Servicos:WaitForChild("Combate")
local ControladorCombate = require(Combate:WaitForChild("ControladorCombate"))

local GerenciadorNPC = {}

-- ═══════════════════════════════════════════════════════════════════
-- CONFIGURAÇÃO DE IA
-- ═══════════════════════════════════════════════════════════════════

local ConfiguracaoIA = {
	-- Detecção
	RaioDeteccao = 50,
	RaioPararPerseguir = 60,

	-- Movimento
	VelocidadePerto = 13,
	VelocidadeLonge = 16,
	DistanciaPerto = 15,

	-- Combate
	DistanciaAtaque = 6.5,
	DistanciaIniciarAtaque = 5.8,
	DistanciaContinuarCombo = 6.2,

	-- Rotação
	VelocidadeRotacao = 10,

	-- Delays
	DelayEntreAtaques = 0.3,
	DelayAposCombo = 1.0,
}

-- ═══════════════════════════════════════════════════════════════════
-- CACHE DE NPCS
-- ═══════════════════════════════════════════════════════════════════

local npcsAtivos = {}

-- ═══════════════════════════════════════════════════════════════════
-- CLASSE NPC
-- ═══════════════════════════════════════════════════════════════════

local NPCController = {}
NPCController.__index = NPCController

function NPCController.Novo(modelo: Model)
	local self = setmetatable({}, NPCController)

	self.modelo = modelo
	self.humanoid = modelo:FindFirstChildOfClass("Humanoid")
	self.humanoidRoot = modelo:FindFirstChild("HumanoidRootPart")

	-- Obtém máquina de estados via ControladorCombate
	self.maquina = ControladorCombate.ObterMaquina(modelo)

	-- Define modo de combate (pode ser configurado via atributo)
	local modo = modelo:GetAttribute("ModoCombate") or "Punhos"
	self.maquina:DefinirModo(modo)

	-- Estado da IA
	self.alvo = nil
	self.ultimoAtaque = 0
	self.indiceComboAtual = 0
	self.ativo = true

	-- Conexões
	self.conexoes = {}

	return self
end

--- Encontra jogador mais próximo dentro do raio de detecção
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

--- Rotaciona suavemente em direção ao alvo
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

	-- Normaliza para -pi a pi
	while diferenca > math.pi do
		diferenca = diferenca - 2 * math.pi
	end
	while diferenca < -math.pi do
		diferenca = diferenca + 2 * math.pi
	end

	local novoAngulo = anguloAtual + diferenca * math.min(ConfiguracaoIA.VelocidadeRotacao * dt, 1)

	self.humanoidRoot.CFrame = CFrame.new(self.humanoidRoot.Position) * CFrame.Angles(0, novoAngulo, 0)
end

--- Move em direção ao alvo
function NPCController:MoverParaAlvo()
	if not self.alvo or not self.alvo.Character then
		return
	end

	local alvoRoot = self.alvo.Character:FindFirstChild("HumanoidRootPart")
	if not alvoRoot then
		return
	end

	local distancia = (alvoRoot.Position - self.humanoidRoot.Position).Magnitude

	-- Ajusta velocidade baseado na distância
	if distancia > ConfiguracaoIA.DistanciaPerto then
		self.humanoid.WalkSpeed = ConfiguracaoIA.VelocidadeLonge
	else
		self.humanoid.WalkSpeed = ConfiguracaoIA.VelocidadePerto
	end

	-- Move
	self.humanoid:MoveTo(alvoRoot.Position)
end

--- Tenta atacar o alvo
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

	-- Verifica se está em range e pode atacar
	if self.indiceComboAtual > 0 then
		-- Continuando combo - range mais generoso
		if distancia > ConfiguracaoIA.DistanciaContinuarCombo then
			return false
		end
	else
		-- Iniciando ataque - range mais estrito
		if distancia > ConfiguracaoIA.DistanciaIniciarAtaque then
			return false
		end
	end

	-- Verifica cooldown
	local delay = self.indiceComboAtual > 0 and ConfiguracaoIA.DelayEntreAtaques or ConfiguracaoIA.DelayAposCombo
	if (agora - self.ultimoAtaque) < delay then
		return false
	end

	-- Tenta atacar via ControladorCombate
	local sucesso, tipoAtaque = ControladorCombate.ProcessarAtacarLeveEmPe(self.modelo)

	if sucesso then
		self.ultimoAtaque = agora
		self.indiceComboAtual = self.maquina:ObterIndiceCombo()

		-- Se combo terminou, reseta
		if self.indiceComboAtual == 0 or tipoAtaque == "AtaqueLeveFinal" then
			self.indiceComboAtual = 0
			self.ultimoAtaque = agora -- Delay maior após combo completo
		end

		return true
	end

	return false
end

--- Loop principal de IA
function NPCController:Atualizar(dt: number)
	if not self.ativo then
		return
	end
	if not self.humanoid or self.humanoid.Health <= 0 then
		self:Desativar()
		return
	end

	-- Verifica se está stunado
	if self.maquina:EstaStunado() then
		self.humanoid:MoveTo(self.humanoidRoot.Position) -- Para
		return
	end

	-- Encontra ou valida alvo
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

	-- Sem alvo, fica parado
	if not self.alvo then
		self.humanoid:MoveTo(self.humanoidRoot.Position)
		return
	end

	-- Rotaciona para o alvo
	self:RotacionarParaAlvo(dt)

	-- Verifica distância para atacar ou perseguir
	local alvoRoot = self.alvo.Character:FindFirstChild("HumanoidRootPart")
	if alvoRoot then
		local distancia = (alvoRoot.Position - self.humanoidRoot.Position).Magnitude

		if distancia <= ConfiguracaoIA.DistanciaAtaque then
			-- Em range de ataque
			self.humanoid:MoveTo(self.humanoidRoot.Position) -- Para
			self:TentarAtacar()
		else
			-- Persegue
			self:MoverParaAlvo()
		end
	end
end

--- Aplica ragdoll na morte
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

--- Desativa NPC
function NPCController:Desativar()
	self.ativo = false

	-- Desconecta eventos
	for _, conexao in ipairs(self.conexoes) do
		if conexao.Connected then
			conexao:Disconnect()
		end
	end

	-- Remove do cache
	npcsAtivos[self.modelo] = nil

	-- Aplica ragdoll se morreu
	if self.humanoid and self.humanoid.Health <= 0 then
		self:AplicarRagdoll()
	end

	-- Remove máquina de estados
	ControladorCombate.RemoverMaquina(self.modelo)
end

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES PÚBLICAS
-- ═══════════════════════════════════════════════════════════════════

--- Registra um NPC para ser gerenciado
function GerenciadorNPC.RegistrarNPC(modelo: Model)
	if npcsAtivos[modelo] then
		return
	end

	local controller = NPCController.Novo(modelo)
	npcsAtivos[modelo] = controller

	-- Conecta morte
	if controller.humanoid then
		table.insert(
			controller.conexoes,
			controller.humanoid.Died:Connect(function()
				controller:Desativar()
			end)
		)
	end

	-- Conecta remoção do modelo
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

--- Remove NPC do gerenciamento
function GerenciadorNPC.RemoverNPC(modelo: Model)
	local controller = npcsAtivos[modelo]
	if controller then
		controller:Desativar()
	end
end

--- Obtém controller de um NPC
function GerenciadorNPC.ObterController(modelo: Model)
	return npcsAtivos[modelo]
end

-- ═══════════════════════════════════════════════════════════════════
-- LOOP DE ATUALIZAÇÃO
-- ═══════════════════════════════════════════════════════════════════

RunService.Heartbeat:Connect(function(dt)
	for modelo, controller in pairs(npcsAtivos) do
		if controller.ativo then
			controller:Atualizar(dt)
		end
	end
end)

-- ═══════════════════════════════════════════════════════════════════
-- AUTO-REGISTRO DE NPCS EXISTENTES
-- ═══════════════════════════════════════════════════════════════════

-- Busca NPCs na pasta NPCs (se existir)
local pastaNPCs = workspace:FindFirstChild("NPCs")
if pastaNPCs then
	for _, modelo in ipairs(pastaNPCs:GetChildren()) do
		if modelo:IsA("Model") and modelo:FindFirstChildOfClass("Humanoid") then
			GerenciadorNPC.RegistrarNPC(modelo)
		end
	end

	pastaNPCs.ChildAdded:Connect(function(modelo)
		if modelo:IsA("Model") and modelo:FindFirstChildOfClass("Humanoid") then
			task.wait(0.1) -- Aguarda modelo carregar
			GerenciadorNPC.RegistrarNPC(modelo)
		end
	end)
end

DebugPrint("[GerenciadorNPC] Inicializado")

return GerenciadorNPC
