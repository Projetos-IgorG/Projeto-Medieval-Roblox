--[[
    ArrastarController.client.luau
    
    Sistema de arrastar itens com física estilo Skyrim (cliente):
    - Detecta itens arrastáveis via Raycast da câmera
    - Aplica Highlight visual em itens arrastáveis
    - Gerencia input (mouse/touch) para iniciar/parar arrasto
    - Mantém item a distância máxima do jogador com física suave
    - Conserva momentum ao soltar (física contínua)
    
    Funciona em primeira e terceira pessoa, PC e Mobile.
]]

-- ═══════════════════════════════════════════════════════════════════
-- CONFIGURAÇÃO DE DEBUG
-- ═══════════════════════════════════════════════════════════════════
local DEBUG_ENABLED = false

local function DebugPrint(...)
	if DEBUG_ENABLED then
		print("[ArrastarController]", ...)
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- SERVIÇOS
-- ═══════════════════════════════════════════════════════════════════
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")

-- ═══════════════════════════════════════════════════════════════════
-- CONFIGURAÇÕES
-- ═══════════════════════════════════════════════════════════════════
local CONFIG = {
	-- Distância máxima para detectar e arrastar itens
	DISTANCIA_MAXIMA = 12,

	-- Distância que o item fica do jogador enquanto arrasta
	DISTANCIA_SEGURAR = 5,

	-- Velocidade máxima de movimento do item (studs/segundo)
	-- Se o jogador andar mais rápido que isso, o item não consegue acompanhar
	VELOCIDADE_MAXIMA_ITEM = 14,

	-- Distância em que o item começa a "perder" o jogador e cair
	-- Quando a distância real > DISTANCIA_SEGURAR, o item tenta alcançar
	-- Quando a distância real > DISTANCIA_SOLTAR, o item é solto
	DISTANCIA_SOLTAR = 13,

	-- Velocidade de "catch up" quando o item está atrasado (studs/segundo)
	-- Menor que VELOCIDADE_MAXIMA_ITEM para que o jogador possa escapar
	VELOCIDADE_CATCHUP = 12,

	-- Multiplicador de força para conservação de momentum
	MULTIPLICADOR_MOMENTUM = 1.5,

	-- Tamanho do histórico para cálculo de velocidade
	TAMANHO_HISTORICO_VELOCIDADE = 10,

	-- Configurações de peso/gravidade
	-- Força gravitacional extra por unidade de peso (acima de 1.0)
	GRAVIDADE_POR_PESO = 3.5,

	-- Offset vertical máximo causado pela gravidade do peso
	OFFSET_GRAVIDADE_MAXIMO = 2.0,

	-- Quão rápido o item "cede" à gravidade (suavização)
	SUAVIZACAO_GRAVIDADE = 0.05,

	-- Nome da ação para ContextActionService (mobile)
	NOME_ACAO_ARRASTAR = "ArrastarItem",

	-- ═══════════════════════════════════════════════════════════════════
	-- CONFIGURAÇÕES DE ROTAÇÃO
	-- ═══════════════════════════════════════════════════════════════════
	-- Velocidade de rotação horizontal (radianos/segundo) - mais rápida
	VELOCIDADE_ROTACAO_HORIZONTAL = 4.0,
	-- Responsividade da constraint de orientação
	RESPONSIVIDADE_ORIENTACAO = 15,
}

-- ═══════════════════════════════════════════════════════════════════
-- REFERÊNCIAS
-- ═══════════════════════════════════════════════════════════════════
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local Remotos = ReplicatedStorage:WaitForChild("Remotos")
local ArrastarItemEvent = Remotos:WaitForChild("ArrastarItem")

local VFX = ReplicatedStorage:WaitForChild("VFX")
local HighlightTemplate = VFX:WaitForChild("HighlightArrastar")

-- ═══════════════════════════════════════════════════════════════════
-- ESTADO
-- ═══════════════════════════════════════════════════════════════════
local estado = {
	-- Objeto sendo olhado (hover)
	alvoHover = nil :: Instance?,

	-- Objeto sendo arrastado
	alvoArrastando = nil :: Instance?,

	-- Está arrastando?
	arrastando = false,

	-- Highlight ativo
	highlightAtivo = nil :: Highlight?,

	-- Histórico de posições para cálculo de velocidade
	historicoPosicoes = {} :: { { posicao: Vector3, tempo: number } },

	-- Constraints criadas para física
	alignPosition = nil :: AlignPosition?,
	alignOrientation = nil :: AlignOrientation?,
	attachment = nil :: Attachment?,
	attachmentOrientacao = nil :: Attachment?, -- Para orientação (world-space)
	vectorForce = nil :: VectorForce?, -- Para gravidade do peso

	-- Posição atual do item (controlada manualmente para velocidade fixa)
	posicaoAtualItem = nil :: Vector3?,

	-- Rotação relativa inicial (offset entre objeto e direção do jogador)
	rotacaoRelativaInicial = nil :: CFrame?,

	-- Ângulos de rotação atual (suavizados)
	anguloHorizontalAtual = 0 :: number,

	-- Direção horizontal inicial do jogador para o objeto
	direcaoHorizontalInicial = nil :: Vector3?,

	-- Offset de gravidade atual (suavizado)
	offsetGravidadeAtual = 0 :: number,

	-- Peso do objeto atual
	pesoAtual = 1.0 :: number,
}

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES AUXILIARES
-- ═══════════════════════════════════════════════════════════════════

-- Obtém o Character do jogador
local function ObterCharacter(): Model?
	return player.Character
end

-- Obtém o HumanoidRootPart do jogador
local function ObterHRP(): BasePart?
	local character = ObterCharacter()
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Obtém a parte principal de um objeto
local function ObterPartePrincipal(objeto: Instance): BasePart?
	if objeto:IsA("BasePart") then
		return objeto
	elseif objeto:IsA("Model") then
		return objeto.PrimaryPart or objeto:FindFirstChildWhichIsA("BasePart", true)
	elseif objeto:IsA("Tool") then
		return objeto:FindFirstChild("Handle") :: BasePart?
	end
	return nil
end

-- Verifica se o objeto é arrastável
local function EhArrastavel(objeto: Instance): boolean
	-- Se for uma Tool, procuramos pelo BoolValue Draggable dentro de um Folder chamado "Dados"
	if objeto:IsA("Tool") then
		local dados = objeto:FindFirstChild("Dados")
		if dados and dados:IsA("Folder") then
			local draggableValue = dados:FindFirstChild("Draggable")
			if draggableValue and draggableValue:IsA("BoolValue") then
				return draggableValue.Value == true
			end
		end
		return false
	end

	-- Para outros tipos, mantemos o comportamento baseado em Attributes
	return objeto:GetAttribute("Draggable") == true
end

-- Obtém o peso do objeto
local function ObterPeso(objeto: Instance): number
	-- Se for uma Tool, procuramos por um NumberValue "Peso" dentro de um Folder chamado "Dados"
	if objeto:IsA("Tool") then
		local dados = objeto:FindFirstChild("Dados")
		if dados and dados:IsA("Folder") then
			local pesoValue = dados:FindFirstChild("Peso")
			if pesoValue and pesoValue:IsA("NumberValue") then
				local p = pesoValue.Value
				if typeof(p) == "number" and p > 0 then
					return p
				end
			end
		end
		return 1.0
	end

	-- Para outros tipos, mantemos o comportamento baseado em Attributes
	local peso = objeto:GetAttribute("Peso")
	if typeof(peso) == "number" and peso > 0 then
		return peso
	end
	return 1.0
end

-- Encontra o objeto arrastável pai (subindo na hierarquia)
local function EncontrarObjetoArrastavel(instancia: Instance): Instance?
	local atual = instancia

	while atual and atual ~= workspace do
		if EhArrastavel(atual) then
			return atual
		end
		atual = atual.Parent
	end

	return nil
end

-- ═══════════════════════════════════════════════════════════════════
-- DETECÇÃO DE ALVO (RAYCAST)
-- ═══════════════════════════════════════════════════════════════════

-- Verifica se está em primeira pessoa (câmera muito próxima da cabeça)
local function EstaPrimeiraPessoa(): boolean
	local character = ObterCharacter()
	if not character then
		return false
	end

	local head = character:FindFirstChild("Head")
	if not head then
		return false
	end

	local distanciaCamera = (camera.CFrame.Position - head.Position).Magnitude
	return distanciaCamera < 1.5 -- Threshold para primeira pessoa
end

local function DetectarAlvoHover(): Instance?
	local character = ObterCharacter()
	if not character then
		return nil
	end

	local origem: Vector3
	local direcao: Vector3

	if EstaPrimeiraPessoa() then
		-- Primeira pessoa: raycast do centro da câmera
		origem = camera.CFrame.Position
		direcao = camera.CFrame.LookVector * CONFIG.DISTANCIA_MAXIMA
	else
		-- Terceira pessoa: raycast da posição do mouse
		local mouseLocation = UserInputService:GetMouseLocation()
		local unitRay = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
		origem = unitRay.Origin
		direcao = unitRay.Direction * CONFIG.DISTANCIA_MAXIMA
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true

	local resultado = workspace:Raycast(origem, direcao, params)

	if not resultado then
		return nil
	end

	-- Encontra objeto arrastável na hierarquia
	local objetoArrastavel = EncontrarObjetoArrastavel(resultado.Instance)

	if not objetoArrastavel then
		return nil
	end

	-- Verifica se outro jogador já está arrastando
	local arrastadoPor = objetoArrastavel:GetAttribute("ArrastadoPor")
	if arrastadoPor and arrastadoPor ~= player.UserId then
		return nil
	end

	return objetoArrastavel
end

-- ═══════════════════════════════════════════════════════════════════
-- HIGHLIGHT
-- ═══════════════════════════════════════════════════════════════════

local function AplicarHighlight(objeto: Instance?)
	-- Remove highlight anterior se existir
	if estado.highlightAtivo then
		estado.highlightAtivo.Adornee = nil
		estado.highlightAtivo.Parent = nil
	end

	if not objeto then
		return
	end

	-- Cria ou reutiliza highlight
	if not estado.highlightAtivo then
		estado.highlightAtivo = HighlightTemplate:Clone()
		estado.highlightAtivo.Name = "HighlightArrastarAtivo"
	end

	estado.highlightAtivo.Adornee = objeto
	estado.highlightAtivo.Parent = objeto
end

-- ═══════════════════════════════════════════════════════════════════
-- FÍSICA E CONSTRAINTS
-- ═══════════════════════════════════════════════════════════════════

local function CriarConstraints(partePrincipal: BasePart, peso: number)
	-- Limpa constraints anteriores
	LimparConstraints()

	-- Guarda o peso atual
	estado.pesoAtual = peso

	-- Cria attachment na parte
	local attachment = Instance.new("Attachment")
	attachment.Name = "ArrastarAttachment"
	attachment.Parent = partePrincipal
	estado.attachment = attachment

	-- Cria AlignPosition para física suave
	-- Usamos alta responsividade mas controlamos a posição manualmente
	local alignPosition = Instance.new("AlignPosition")
	alignPosition.Name = "ArrastarAlignPosition"
	alignPosition.Mode = Enum.PositionAlignmentMode.OneAttachment
	alignPosition.Attachment0 = attachment
	alignPosition.ApplyAtCenterOfMass = true
	alignPosition.RigidityEnabled = false

	-- Força alta para seguir a posição que definimos, mas com suavização natural
	alignPosition.MaxForce = 80000
	alignPosition.MaxVelocity = CONFIG.VELOCIDADE_MAXIMA_ITEM
	alignPosition.Responsiveness = 25 -- Alta responsividade para seguir nossa posição calculada

	alignPosition.Parent = partePrincipal
	estado.alignPosition = alignPosition

	-- ═══════════════════════════════════════════════════════════════════
	-- CONFIGURAÇÃO DE ORIENTAÇÃO
	-- ═══════════════════════════════════════════════════════════════════
	-- Cria attachment separado para orientação (no centro do objeto)
	local attachmentOrientacao = Instance.new("Attachment")
	attachmentOrientacao.Name = "ArrastarAttachmentOrientacao"
	attachmentOrientacao.Parent = partePrincipal
	estado.attachmentOrientacao = attachmentOrientacao

	-- Cria AlignOrientation para controlar a rotação do objeto
	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Name = "ArrastarAlignOrientation"
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.Attachment0 = attachmentOrientacao
	alignOrientation.RigidityEnabled = false

	-- Configuração suave para rotação
	alignOrientation.MaxTorque = 50000
	alignOrientation.MaxAngularVelocity = 5
	alignOrientation.Responsiveness = CONFIG.RESPONSIVIDADE_ORIENTACAO

	alignOrientation.Parent = partePrincipal
	estado.alignOrientation = alignOrientation

	-- Inicializa a orientação alvo com a orientação atual do objeto
	alignOrientation.CFrame = partePrincipal.CFrame - partePrincipal.CFrame.Position

	-- Cria VectorForce para aplicar gravidade extra baseada no peso
	-- Isso faz objetos pesados "penderem" para baixo naturalmente
	if peso > 1.0 then
		local vectorForce = Instance.new("VectorForce")
		vectorForce.Name = "ArrastarGravidade"
		vectorForce.Attachment0 = attachment
		vectorForce.ApplyAtCenterOfMass = true
		vectorForce.RelativeTo = Enum.ActuatorRelativeTo.World

		-- Força gravitacional extra proporcional ao peso acima de 1.0
		-- Multiplicamos pela massa para ter efeito consistente
		local massaTotal = partePrincipal.AssemblyMass
		local forcaGravidade = (peso - 1.0) * CONFIG.GRAVIDADE_POR_PESO * massaTotal * workspace.Gravity * 0.1
		vectorForce.Force = Vector3.new(0, -forcaGravidade, 0)

		vectorForce.Parent = partePrincipal
		estado.vectorForce = vectorForce

		DebugPrint("Gravidade extra aplicada - Peso:", peso, "Força:", forcaGravidade)
	end

	DebugPrint("Constraints criadas - Peso:", peso)
end

function LimparConstraints()
	if estado.attachment then
		estado.attachment:Destroy()
		estado.attachment = nil
	end

	if estado.attachmentOrientacao then
		estado.attachmentOrientacao:Destroy()
		estado.attachmentOrientacao = nil
	end

	if estado.alignPosition then
		estado.alignPosition:Destroy()
		estado.alignPosition = nil
	end

	if estado.alignOrientation then
		estado.alignOrientation:Destroy()
		estado.alignOrientation = nil
	end

	if estado.vectorForce then
		estado.vectorForce:Destroy()
		estado.vectorForce = nil
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- CÁLCULO DE VELOCIDADE (MOMENTUM)
-- ═══════════════════════════════════════════════════════════════════

local function RegistrarPosicao(posicao: Vector3)
	table.insert(estado.historicoPosicoes, {
		posicao = posicao,
		tempo = tick(),
	})

	-- Mantém apenas as últimas N posições
	while #estado.historicoPosicoes > CONFIG.TAMANHO_HISTORICO_VELOCIDADE do
		table.remove(estado.historicoPosicoes, 1)
	end
end

local function CalcularVelocidadeMedia(): Vector3
	if #estado.historicoPosicoes < 2 then
		return Vector3.zero
	end

	local primeiro = estado.historicoPosicoes[1]
	local ultimo = estado.historicoPosicoes[#estado.historicoPosicoes]

	local deltaTempo = ultimo.tempo - primeiro.tempo
	if deltaTempo <= 0 then
		return Vector3.zero
	end

	local deltaPosicao = ultimo.posicao - primeiro.posicao
	local velocidade = deltaPosicao / deltaTempo

	return velocidade * CONFIG.MULTIPLICADOR_MOMENTUM
end

local function LimparHistoricoPosicoes()
	estado.historicoPosicoes = {}
end

-- ═══════════════════════════════════════════════════════════════════
-- LÓGICA DE ARRASTO
-- ═══════════════════════════════════════════════════════════════════

local function CalcularPosicaoAlvo(): Vector3
	local hrp = ObterHRP()
	local character = ObterCharacter()

	if not hrp or not character then
		return camera.CFrame.Position + camera.CFrame.LookVector * CONFIG.DISTANCIA_SEGURAR
	end

	local posicaoDesejada: Vector3

	if EstaPrimeiraPessoa() then
		-- Primeira pessoa: posição baseada na câmera
		local posicaoCamera = camera.CFrame.Position
		local direcaoCamera = camera.CFrame.LookVector
		posicaoDesejada = posicaoCamera + direcaoCamera * CONFIG.DISTANCIA_SEGURAR
	else
		-- Terceira pessoa: raycast do mouse para encontrar ponto no mundo
		local mouseLocation = UserInputService:GetMouseLocation()
		local unitRay = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)

		-- Faz raycast para encontrar onde o mouse aponta
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character, estado.alvoArrastando }
		params.IgnoreWater = true

		local resultado = workspace:Raycast(unitRay.Origin, unitRay.Direction * 100, params)

		if resultado then
			-- Ponto onde o mouse aponta no mundo
			local pontoMouse = resultado.Position

			-- Direção do jogador para o ponto do mouse
			local direcaoParaMouse = (pontoMouse - hrp.Position)
			local distanciaParaMouse = direcaoParaMouse.Magnitude

			-- Limita a distância máxima do jogador
			if distanciaParaMouse > CONFIG.DISTANCIA_SEGURAR then
				posicaoDesejada = hrp.Position + direcaoParaMouse.Unit * CONFIG.DISTANCIA_SEGURAR
			else
				posicaoDesejada = pontoMouse
			end

			-- Mantém uma altura mínima do chão
			if posicaoDesejada.Y < hrp.Position.Y - 2 then
				posicaoDesejada = Vector3.new(posicaoDesejada.X, hrp.Position.Y - 2, posicaoDesejada.Z)
			end
		else
			-- Se não atingiu nada, projeta na direção do mouse a partir do jogador
			local direcaoMouse = unitRay.Direction
			posicaoDesejada = hrp.Position
				+ Vector3.new(direcaoMouse.X, 0, direcaoMouse.Z).Unit * CONFIG.DISTANCIA_SEGURAR
			posicaoDesejada = Vector3.new(posicaoDesejada.X, hrp.Position.Y + 1, posicaoDesejada.Z)
		end
	end

	-- Garante que não fique muito longe do jogador (baseado no HRP, não na câmera)
	local distanciaDoJogador = (posicaoDesejada - hrp.Position).Magnitude
	if distanciaDoJogador > CONFIG.DISTANCIA_MAXIMA then
		local direcaoDoJogador = (posicaoDesejada - hrp.Position).Unit
		posicaoDesejada = hrp.Position + direcaoDoJogador * CONFIG.DISTANCIA_MAXIMA
	end

	return posicaoDesejada
end

local function IniciarArrasto()
	if estado.arrastando then
		return
	end
	if not estado.alvoHover then
		return
	end

	local objeto = estado.alvoHover
	local partePrincipal = ObterPartePrincipal(objeto)

	if not partePrincipal then
		DebugPrint("Não foi possível iniciar: sem parte principal")
		return
	end

	-- Marca como arrastando
	estado.arrastando = true
	estado.alvoArrastando = objeto

	-- Limpa histórico de posições
	LimparHistoricoPosicoes()

	-- Inicializa posição atual do item (onde ele realmente está)
	estado.posicaoAtualItem = partePrincipal.Position
	estado.offsetGravidadeAtual = 0

	-- ═══════════════════════════════════════════════════════════════════
	-- INICIALIZAÇÃO DA ROTAÇÃO
	-- ═══════════════════════════════════════════════════════════════════
	-- Guarda a rotação inicial do objeto (será mantida relativa ao jogador)
	estado.rotacaoRelativaInicial = partePrincipal.CFrame - partePrincipal.CFrame.Position

	-- Calcula a direção horizontal inicial do jogador para o objeto
	local hrpInicio = ObterHRP()
	if hrpInicio then
		local direcaoParaObjeto = (partePrincipal.Position - hrpInicio.Position)
		-- Remove componente Y para ter apenas direção horizontal
		estado.direcaoHorizontalInicial = Vector3.new(direcaoParaObjeto.X, 0, direcaoParaObjeto.Z).Unit
	else
		estado.direcaoHorizontalInicial = camera.CFrame.LookVector
		estado.direcaoHorizontalInicial =
			Vector3.new(estado.direcaoHorizontalInicial.X, 0, estado.direcaoHorizontalInicial.Z).Unit
	end

	-- Inicializa ângulos de rotação em zero (será ajustado relativamente)
	estado.anguloHorizontalAtual = 0

	-- Cria constraints para física
	local peso = ObterPeso(objeto)
	estado.pesoAtual = peso
	CriarConstraints(partePrincipal, peso)

	-- Notifica servidor
	ArrastarItemEvent:FireServer("Iniciar", objeto)

	-- Remove highlight durante arrasto
	AplicarHighlight(nil)

	DebugPrint("Arrasto iniciado:", objeto.Name, "Peso:", peso)
end

local function PararArrasto()
	if not estado.arrastando then
		return
	end

	local objeto = estado.alvoArrastando
	local partePrincipal = objeto and ObterPartePrincipal(objeto)

	-- Aplica momentum (física contínua ao soltar)
	if partePrincipal then
		local velocidade = CalcularVelocidadeMedia()

		-- Aplica peso na velocidade vertical (mais difícil jogar pra cima)
		local peso = estado.pesoAtual
		if velocidade.Y > 0 then
			-- Objetos pesados são muito mais difíceis de jogar pra cima
			velocidade = Vector3.new(velocidade.X, velocidade.Y / (peso * peso), velocidade.Z)
		end

		-- Objetos pesados também perdem velocidade horizontal
		if peso > 1.0 then
			local reducaoHorizontal = 1.0 / math.sqrt(peso)
			velocidade = Vector3.new(velocidade.X * reducaoHorizontal, velocidade.Y, velocidade.Z * reducaoHorizontal)
		end

		-- Aplica velocidade
		partePrincipal.AssemblyLinearVelocity = velocidade

		DebugPrint("Momentum aplicado:", velocidade.Magnitude)
	end

	-- Limpa constraints
	LimparConstraints()

	-- Notifica servidor
	ArrastarItemEvent:FireServer("Parar")

	-- Reseta estado
	estado.arrastando = false
	estado.alvoArrastando = nil
	estado.posicaoAtualItem = nil
	estado.offsetGravidadeAtual = 0
	estado.pesoAtual = 1.0
	estado.rotacaoRelativaInicial = nil
	estado.direcaoHorizontalInicial = nil
	estado.anguloHorizontalAtual = 0
	LimparHistoricoPosicoes()

	DebugPrint("Arrasto parado")
end

-- ═══════════════════════════════════════════════════════════════════
-- ATUALIZAÇÃO POR FRAME
-- ═══════════════════════════════════════════════════════════════════

local function AtualizarArrasto(deltaTime: number)
	local objeto = estado.alvoArrastando
	if not objeto or not objeto.Parent then
		PararArrasto()
		return
	end

	local partePrincipal = ObterPartePrincipal(objeto)
	if not partePrincipal then
		PararArrasto()
		return
	end

	local hrp = ObterHRP()
	if not hrp then
		PararArrasto()
		return
	end

	-- Posição atual real do item
	local posicaoRealItem = partePrincipal.Position

	-- Calcula distância do jogador ao item
	local distanciaDoJogador = (posicaoRealItem - hrp.Position).Magnitude

	-- Se o item está muito longe, solta
	if distanciaDoJogador > CONFIG.DISTANCIA_SOLTAR then
		DebugPrint("Item muito longe, soltando. Distância:", distanciaDoJogador)
		PararArrasto()
		return
	end

	-- Calcula posição alvo (onde o jogador quer que o item esteja)
	local posicaoAlvoBase = CalcularPosicaoAlvo()

	-- Calcula offset de gravidade baseado no peso
	-- Objetos pesados "pendem" para baixo naturalmente
	local peso = estado.pesoAtual
	local offsetGravidadeAlvo = 0
	if peso > 1.0 then
		-- Quanto mais pesado, mais o objeto pende
		offsetGravidadeAlvo = math.min((peso - 1.0) * CONFIG.GRAVIDADE_POR_PESO * 0.3, CONFIG.OFFSET_GRAVIDADE_MAXIMO)
	end

	-- Suaviza o offset de gravidade para movimento natural
	estado.offsetGravidadeAtual = estado.offsetGravidadeAtual
		+ (offsetGravidadeAlvo - estado.offsetGravidadeAtual) * CONFIG.SUAVIZACAO_GRAVIDADE

	-- Aplica o offset de gravidade na posição alvo
	local posicaoAlvoComGravidade = posicaoAlvoBase - Vector3.new(0, estado.offsetGravidadeAtual, 0)

	-- Inicializa posição atual se necessário
	if not estado.posicaoAtualItem then
		estado.posicaoAtualItem = posicaoRealItem
	end

	-- Calcula direção e distância da posição atual para o alvo
	local direcaoParaAlvo = posicaoAlvoComGravidade - estado.posicaoAtualItem
	local distanciaParaAlvo = direcaoParaAlvo.Magnitude

	-- Move a posição atual em direção ao alvo com velocidade fixa
	if distanciaParaAlvo > 0.01 then
		-- Determina qual velocidade usar
		local velocidadeUsar: number

		-- Se o item está "atrasado" (longe do alvo), usa velocidade de catch-up
		-- Caso contrário, usa velocidade normal
		if distanciaParaAlvo > 2.0 then
			velocidadeUsar = CONFIG.VELOCIDADE_CATCHUP
		else
			velocidadeUsar = CONFIG.VELOCIDADE_MAXIMA_ITEM
		end

		-- Objetos pesados são mais lentos para se mover
		velocidadeUsar = velocidadeUsar / math.sqrt(peso)

		-- Calcula quanto pode mover neste frame
		local movimentoMaximo = velocidadeUsar * deltaTime

		if distanciaParaAlvo <= movimentoMaximo then
			-- Pode alcançar o alvo neste frame
			estado.posicaoAtualItem = posicaoAlvoComGravidade
		else
			-- Move na direção do alvo com velocidade fixa
			local direcaoNormalizada = direcaoParaAlvo.Unit
			estado.posicaoAtualItem = estado.posicaoAtualItem + direcaoNormalizada * movimentoMaximo
		end
	end

	-- Registra posição para cálculo de momentum
	RegistrarPosicao(posicaoRealItem)

	-- Atualiza a posição alvo do AlignPosition
	if estado.alignPosition then
		estado.alignPosition.Position = estado.posicaoAtualItem
	end

	-- ═══════════════════════════════════════════════════════════════════
	-- ATUALIZAÇÃO DA ROTAÇÃO
	-- ═══════════════════════════════════════════════════════════════════
	if estado.alignOrientation and estado.rotacaoRelativaInicial and estado.direcaoHorizontalInicial then
		-- Calcula a direção horizontal atual do jogador para o objeto
		local direcaoAtualParaObjeto = (estado.posicaoAtualItem - hrp.Position)
		local direcaoHorizontalAtual = Vector3.new(direcaoAtualParaObjeto.X, 0, direcaoAtualParaObjeto.Z)

		-- Evita divisão por zero se o objeto está exatamente acima/abaixo
		if direcaoHorizontalAtual.Magnitude > 0.01 then
			direcaoHorizontalAtual = direcaoHorizontalAtual.Unit

			-- Calcula o ângulo horizontal que mudou desde o início
			-- Isso representa quanto o jogador "girou" em torno do objeto
			local anguloHorizontalAlvo = math.atan2(
				estado.direcaoHorizontalInicial:Cross(direcaoHorizontalAtual).Y,
				estado.direcaoHorizontalInicial:Dot(direcaoHorizontalAtual)
			)

			-- Suaviza a rotação horizontal (mais rápida)
			local deltaHorizontal = anguloHorizontalAlvo - estado.anguloHorizontalAtual
			-- Normaliza para -PI a PI para evitar giros longos
			while deltaHorizontal > math.pi do
				deltaHorizontal = deltaHorizontal - 2 * math.pi
			end
			while deltaHorizontal < -math.pi do
				deltaHorizontal = deltaHorizontal + 2 * math.pi
			end

			-- A velocidade máxima de correção horizontal diminui com o peso
			-- Objetos mais pesados viram mais devagar (dividimos por sqrt(peso))
			local fatorPeso = 8
			if peso and peso > 0 then
				fatorPeso = math.sqrt(peso)
			end
			local maxRotacaoHorizontal = (CONFIG.VELOCIDADE_ROTACAO_HORIZONTAL / fatorPeso) * deltaTime
			if math.abs(deltaHorizontal) > maxRotacaoHorizontal then
				deltaHorizontal = math.sign(deltaHorizontal) * maxRotacaoHorizontal
			end
			estado.anguloHorizontalAtual = estado.anguloHorizontalAtual + deltaHorizontal

			-- Constrói a rotação final (apenas horizontal):
			local rotacaoCompensacaoHorizontal = CFrame.Angles(0, estado.anguloHorizontalAtual, 0)
			local rotacaoFinal = rotacaoCompensacaoHorizontal * estado.rotacaoRelativaInicial

			estado.alignOrientation.CFrame = rotacaoFinal
		end
	end
end

local function AtualizarHover()
	-- Detecta alvo
	estado.alvoHover = DetectarAlvoHover()

	-- Aplica highlight
	AplicarHighlight(estado.alvoHover)
end

-- ═══════════════════════════════════════════════════════════════════
-- INPUT
-- ═══════════════════════════════════════════════════════════════════

-- Handler para input (PC e Mobile)
local function OnInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		IniciarArrasto()
	end
end

local function OnInputEnded(input: InputObject, gameProcessed: boolean)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		PararArrasto()
	end
end

-- Handler para ContextActionService (mobile com botão dedicado opcional)
local function HandleArrastarAction(actionName: string, inputState: Enum.UserInputState, inputObject: InputObject)
	if inputState == Enum.UserInputState.Begin then
		IniciarArrasto()
	elseif inputState == Enum.UserInputState.End then
		PararArrasto()
	end

	return Enum.ContextActionResult.Pass
end

-- ═══════════════════════════════════════════════════════════════════
-- CONEXÕES
-- ═══════════════════════════════════════════════════════════════════

-- Input
UserInputService.InputBegan:Connect(OnInputBegan)
UserInputService.InputEnded:Connect(OnInputEnded)

-- Loop principal
RunService.RenderStepped:Connect(function(deltaTime)
	if estado.arrastando then
		AtualizarArrasto(deltaTime)
	else
		AtualizarHover()
	end
end)

-- Limpa quando personagem morre/respawna
player.CharacterRemoving:Connect(function()
	PararArrasto()
	AplicarHighlight(nil)
end)

-- Touch: registra ação para dispositivos móveis (permite segurar e arrastar)
if UserInputService.TouchEnabled then
	ContextActionService:BindAction(
		CONFIG.NOME_ACAO_ARRASTAR,
		HandleArrastarAction,
		false, -- Não cria botão na tela (usa touch direto)
		Enum.UserInputType.Touch
	)
end

DebugPrint("Sistema de arrastar inicializado (cliente)")
