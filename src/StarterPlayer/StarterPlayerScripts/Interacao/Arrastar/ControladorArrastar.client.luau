--[[
    Script: ControladorArrastar.client.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/Interacao/Arrastar
    Responsabilidade: Controla input e feedback local para arrastar objetos interativos.
    Uso: LocalScript; roda automaticamente para o jogador local em src/StarterPlayer/StarterPlayerScripts/Interacao/Arrastar.
    Nao faz: Nao valida autoridade do servidor, nao salva dados persistentes e nao substitui regras server-side.
    Funcoes principais: LimparConstraints, ObterCharacter, ObterHRP, EstaPrimeiraPessoa, DetectarAlvoHover, AplicarHighlight
]]
local DEBUG_ENABLED = false

local function DebugPrint(...)
	if DEBUG_ENABLED then
		print("[ArrastarController]", ...)
	end
end

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")

local CONFIG = {

	DISTANCIA_MAXIMA = 12,

	DISTANCIA_SEGURAR = 5,

	VELOCIDADE_MAXIMA_ITEM = 14,

	DISTANCIA_SOLTAR = 13,

	VELOCIDADE_CATCHUP = 12,

	MULTIPLICADOR_MOMENTUM = 1.5,

	TAMANHO_HISTORICO_VELOCIDADE = 10,

	GRAVIDADE_POR_PESO = 3.5,

	OFFSET_GRAVIDADE_MAXIMO = 2.0,

	SUAVIZACAO_GRAVIDADE = 0.05,

	NOME_ACAO_ARRASTAR = "ArrastarItem",

	VELOCIDADE_ROTACAO_HORIZONTAL = 4.0,

	RESPONSIVIDADE_ORIENTACAO = 15,
}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local Remotos = ReplicatedStorage:WaitForChild("Remotos")
local ArrastarItemEvent = Remotos:WaitForChild("ArrastarItem")

local EfeitosVisuaisArrastar = ReplicatedStorage:WaitForChild("Interacao"):WaitForChild("Arrastar"):WaitForChild("EfeitosVisuais")
local HighlightTemplate = EfeitosVisuaisArrastar:WaitForChild("HighlightArrastar")

local Modulo_Configuracoes =
	require(ReplicatedStorage:WaitForChild("Combate"):WaitForChild("Configuracoes"):WaitForChild("ConfigCombate"))

local estado = {

	alvoHover = nil :: Instance?,

	alvoArrastando = nil :: Instance?,

	arrastando = false,

	highlightAtivo = nil :: Highlight?,

	historicoPosicoes = {} :: { { posicao: Vector3, tempo: number } },

	alignPosition = nil :: AlignPosition?,
	alignOrientation = nil :: AlignOrientation?,
	attachment = nil :: Attachment?,
	attachmentOrientacao = nil :: Attachment?,
	vectorForce = nil :: VectorForce?,

	posicaoAtualItem = nil :: Vector3?,

	rotacaoRelativaInicial = nil :: CFrame?,

	anguloHorizontalAtual = 0 :: number,

	direcaoHorizontalInicial = nil :: Vector3?,

	offsetGravidadeAtual = 0 :: number,

	pesoAtual = 1.0 :: number,

	interacaoBloqueada = false,
}

local FisicaHelpers = require(ReplicatedStorage:WaitForChild("Interacao"):WaitForChild("Arrastar"):WaitForChild("FisicaAuxiliarArrastar"))

local ObterPartePrincipal = FisicaHelpers.ObterPartePrincipal
local ObterPeso = FisicaHelpers.ObterPeso
local EncontrarObjetoArrastavel = FisicaHelpers.EncontrarObjetoArrastavel

local function ObterCharacter(): Model?
	return player.Character
end

local function ObterHRP(): BasePart?
	local character = ObterCharacter()
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local sharedRayParams = RaycastParams.new()
sharedRayParams.FilterType = Enum.RaycastFilterType.Exclude
sharedRayParams.IgnoreWater = true

local ClientBridge =
	require(ReplicatedStorage:WaitForChild("Jogador"):WaitForChild("ComunicacaoCliente"):WaitForChild("PonteCliente"))

local function EstaPrimeiraPessoa(): boolean
	return ClientBridge.EstaEmPrimeiraPessoa and ClientBridge.EstaEmPrimeiraPessoa() or false
end

local function DetectarAlvoHover(): Instance?
	local character = ObterCharacter()
	if not character then
		return nil
	end

	local origem: Vector3
	local direcao: Vector3

	if EstaPrimeiraPessoa() then

		origem = camera.CFrame.Position
		direcao = camera.CFrame.LookVector * CONFIG.DISTANCIA_MAXIMA
	else

		local mouseLocation = UserInputService:GetMouseLocation()
		local unitRay = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
		origem = unitRay.Origin
		direcao = unitRay.Direction * CONFIG.DISTANCIA_MAXIMA
	end

	sharedRayParams.FilterDescendantsInstances = { character }

	local resultado = workspace:Raycast(origem, direcao, sharedRayParams)

	if not resultado then
		return nil
	end

	local objetoArrastavel = EncontrarObjetoArrastavel(resultado.Instance)

	if not objetoArrastavel then
		return nil
	end

	local arrastadoPor = objetoArrastavel:GetAttribute("ArrastadoPor")
	if arrastadoPor and arrastadoPor ~= player.UserId then
		return nil
	end

	return objetoArrastavel
end

local function AplicarHighlight(objeto: Instance?)

	if estado.highlightAtivo then
		estado.highlightAtivo.Adornee = nil
		estado.highlightAtivo.Parent = nil
	end

	if not objeto then
		return
	end

	if not estado.highlightAtivo then
		estado.highlightAtivo = HighlightTemplate:Clone()
		estado.highlightAtivo.Name = "HighlightArrastarAtivo"
	end

	estado.highlightAtivo.Adornee = objeto
	estado.highlightAtivo.Parent = objeto
end

local function CriarConstraints(partePrincipal: BasePart, peso: number)

	LimparConstraints()

	estado.pesoAtual = peso

	local attachment = Instance.new("Attachment")
	attachment.Name = "ArrastarAttachment"
	attachment.Parent = partePrincipal
	estado.attachment = attachment

	local alignPosition = Instance.new("AlignPosition")
	alignPosition.Name = "ArrastarAlignPosition"
	alignPosition.Mode = Enum.PositionAlignmentMode.OneAttachment
	alignPosition.Attachment0 = attachment
	alignPosition.ApplyAtCenterOfMass = true
	alignPosition.RigidityEnabled = false

	alignPosition.MaxForce = 80000
	alignPosition.MaxVelocity = CONFIG.VELOCIDADE_MAXIMA_ITEM
	alignPosition.Responsiveness = 25

	alignPosition.Parent = partePrincipal
	estado.alignPosition = alignPosition

	local attachmentOrientacao = Instance.new("Attachment")
	attachmentOrientacao.Name = "ArrastarAttachmentOrientacao"
	attachmentOrientacao.Parent = partePrincipal
	estado.attachmentOrientacao = attachmentOrientacao

	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Name = "ArrastarAlignOrientation"
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.Attachment0 = attachmentOrientacao
	alignOrientation.RigidityEnabled = false

	alignOrientation.MaxTorque = 50000
	alignOrientation.MaxAngularVelocity = 5
	alignOrientation.Responsiveness = CONFIG.RESPONSIVIDADE_ORIENTACAO

	alignOrientation.Parent = partePrincipal
	estado.alignOrientation = alignOrientation

	alignOrientation.CFrame = partePrincipal.CFrame - partePrincipal.CFrame.Position

	if peso > 1.0 then
		local vectorForce = Instance.new("VectorForce")
		vectorForce.Name = "ArrastarGravidade"
		vectorForce.Attachment0 = attachment
		vectorForce.ApplyAtCenterOfMass = true
		vectorForce.RelativeTo = Enum.ActuatorRelativeTo.World

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

local function RegistrarPosicao(posicao: Vector3)
	table.insert(estado.historicoPosicoes, {
		posicao = posicao,
		tempo = tick(),
	})

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

local function CalcularPosicaoAlvo(): Vector3
	local hrp = ObterHRP()
	local character = ObterCharacter()

	if not hrp or not character then
		return camera.CFrame.Position + camera.CFrame.LookVector * CONFIG.DISTANCIA_SEGURAR
	end

	local posicaoDesejada: Vector3

	if EstaPrimeiraPessoa() then

		local posicaoCamera = camera.CFrame.Position
		local direcaoCamera = camera.CFrame.LookVector
		posicaoDesejada = posicaoCamera + direcaoCamera * CONFIG.DISTANCIA_SEGURAR
	else

		local mouseLocation = UserInputService:GetMouseLocation()
		local unitRay = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)

		sharedRayParams.FilterDescendantsInstances = { character, estado.alvoArrastando }

		local resultado = workspace:Raycast(unitRay.Origin, unitRay.Direction * 100, sharedRayParams)

		if resultado then

			local pontoMouse = resultado.Position

			local direcaoParaMouse = (pontoMouse - hrp.Position)
			local distanciaParaMouse = direcaoParaMouse.Magnitude

			if distanciaParaMouse > CONFIG.DISTANCIA_SEGURAR then
				posicaoDesejada = hrp.Position + direcaoParaMouse.Unit * CONFIG.DISTANCIA_SEGURAR
			else
				posicaoDesejada = pontoMouse
			end

			if posicaoDesejada.Y < hrp.Position.Y - 2 then
				posicaoDesejada = Vector3.new(posicaoDesejada.X, hrp.Position.Y - 2, posicaoDesejada.Z)
			end
		else

			local direcaoMouse = unitRay.Direction
			posicaoDesejada = hrp.Position
				+ Vector3.new(direcaoMouse.X, 0, direcaoMouse.Z).Unit * CONFIG.DISTANCIA_SEGURAR
			posicaoDesejada = Vector3.new(posicaoDesejada.X, hrp.Position.Y + 1, posicaoDesejada.Z)
		end
	end

	local distanciaDoJogador = (posicaoDesejada - hrp.Position).Magnitude
	if distanciaDoJogador > CONFIG.DISTANCIA_MAXIMA then
		local direcaoDoJogador = (posicaoDesejada - hrp.Position).Unit
		posicaoDesejada = hrp.Position + direcaoDoJogador * CONFIG.DISTANCIA_MAXIMA
	end

	return posicaoDesejada
end

local function IniciarArrasto()
	if estado.interacaoBloqueada then
		return
	end
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

	estado.arrastando = true
	estado.alvoArrastando = objeto

	LimparHistoricoPosicoes()

	estado.posicaoAtualItem = partePrincipal.Position
	estado.offsetGravidadeAtual = 0

	estado.rotacaoRelativaInicial = partePrincipal.CFrame - partePrincipal.CFrame.Position

	local hrpInicio = ObterHRP()
	if hrpInicio then
		local direcaoParaObjeto = (partePrincipal.Position - hrpInicio.Position)

		estado.direcaoHorizontalInicial = Vector3.new(direcaoParaObjeto.X, 0, direcaoParaObjeto.Z).Unit
	else
		estado.direcaoHorizontalInicial = camera.CFrame.LookVector
		estado.direcaoHorizontalInicial =
			Vector3.new(estado.direcaoHorizontalInicial.X, 0, estado.direcaoHorizontalInicial.Z).Unit
	end

	estado.anguloHorizontalAtual = 0

	local peso = ObterPeso(objeto)
	estado.pesoAtual = peso
	CriarConstraints(partePrincipal, peso)

	ArrastarItemEvent:FireServer("Iniciar", objeto)

	AplicarHighlight(nil)

	DebugPrint("Arrasto iniciado:", objeto.Name, "Peso:", peso)
end

local function PararArrasto()
	if not estado.arrastando then
		return
	end

	local objeto = estado.alvoArrastando
	local partePrincipal = objeto and ObterPartePrincipal(objeto)

	if partePrincipal then
		local velocidade = CalcularVelocidadeMedia()

		local peso = estado.pesoAtual
		if velocidade.Y > 0 then

			velocidade = Vector3.new(velocidade.X, velocidade.Y / (peso * peso), velocidade.Z)
		end

		if peso > 1.0 then
			local reducaoHorizontal = 1.0 / math.sqrt(peso)
			velocidade = Vector3.new(velocidade.X * reducaoHorizontal, velocidade.Y, velocidade.Z * reducaoHorizontal)
		end

		partePrincipal.AssemblyLinearVelocity = velocidade

		DebugPrint("Momentum aplicado:", velocidade.Magnitude)
	end

	LimparConstraints()

	ArrastarItemEvent:FireServer("Parar")

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

	local posicaoRealItem = partePrincipal.Position

	local distanciaDoJogador = (posicaoRealItem - hrp.Position).Magnitude

	if distanciaDoJogador > CONFIG.DISTANCIA_SOLTAR then
		DebugPrint("Item muito longe, soltando. Distância:", distanciaDoJogador)
		PararArrasto()
		return
	end

	local posicaoAlvoBase = CalcularPosicaoAlvo()

	local peso = estado.pesoAtual
	local offsetGravidadeAlvo = 0
	if peso > 1.0 then

		offsetGravidadeAlvo = math.min((peso - 1.0) * CONFIG.GRAVIDADE_POR_PESO * 0.3, CONFIG.OFFSET_GRAVIDADE_MAXIMO)
	end

	estado.offsetGravidadeAtual = estado.offsetGravidadeAtual
		+ (offsetGravidadeAlvo - estado.offsetGravidadeAtual) * CONFIG.SUAVIZACAO_GRAVIDADE

	local posicaoAlvoComGravidade = posicaoAlvoBase - Vector3.new(0, estado.offsetGravidadeAtual, 0)

	if not estado.posicaoAtualItem then
		estado.posicaoAtualItem = posicaoRealItem
	end

	local direcaoParaAlvo = posicaoAlvoComGravidade - estado.posicaoAtualItem
	local distanciaParaAlvo = direcaoParaAlvo.Magnitude

	if distanciaParaAlvo > 0.01 then

		local velocidadeUsar: number

		if distanciaParaAlvo > 2.0 then
			velocidadeUsar = CONFIG.VELOCIDADE_CATCHUP
		else
			velocidadeUsar = CONFIG.VELOCIDADE_MAXIMA_ITEM
		end

		velocidadeUsar = velocidadeUsar / math.sqrt(peso)

		local movimentoMaximo = velocidadeUsar * deltaTime

		if distanciaParaAlvo <= movimentoMaximo then

			estado.posicaoAtualItem = posicaoAlvoComGravidade
		else

			local direcaoNormalizada = direcaoParaAlvo.Unit
			estado.posicaoAtualItem = estado.posicaoAtualItem + direcaoNormalizada * movimentoMaximo
		end
	end

	RegistrarPosicao(posicaoRealItem)

	if estado.alignPosition then
		estado.alignPosition.Position = estado.posicaoAtualItem
	end

	if estado.alignOrientation and estado.rotacaoRelativaInicial and estado.direcaoHorizontalInicial then

		local direcaoAtualParaObjeto = (estado.posicaoAtualItem - hrp.Position)
		local direcaoHorizontalAtual = Vector3.new(direcaoAtualParaObjeto.X, 0, direcaoAtualParaObjeto.Z)

		if direcaoHorizontalAtual.Magnitude > 0.01 then
			direcaoHorizontalAtual = direcaoHorizontalAtual.Unit

			local anguloHorizontalAlvo = math.atan2(
				estado.direcaoHorizontalInicial:Cross(direcaoHorizontalAtual).Y,
				estado.direcaoHorizontalInicial:Dot(direcaoHorizontalAtual)
			)

			local deltaHorizontal = anguloHorizontalAlvo - estado.anguloHorizontalAtual

			while deltaHorizontal > math.pi do
				deltaHorizontal = deltaHorizontal - 2 * math.pi
			end
			while deltaHorizontal < -math.pi do
				deltaHorizontal = deltaHorizontal + 2 * math.pi
			end

			local fatorPeso = 8
			if peso and peso > 0 then
				fatorPeso = math.sqrt(peso)
			end
			local maxRotacaoHorizontal = (CONFIG.VELOCIDADE_ROTACAO_HORIZONTAL / fatorPeso) * deltaTime
			if math.abs(deltaHorizontal) > maxRotacaoHorizontal then
				deltaHorizontal = math.sign(deltaHorizontal) * maxRotacaoHorizontal
			end
			estado.anguloHorizontalAtual = estado.anguloHorizontalAtual + deltaHorizontal

			local rotacaoCompensacaoHorizontal = CFrame.Angles(0, estado.anguloHorizontalAtual, 0)
			local rotacaoFinal = rotacaoCompensacaoHorizontal * estado.rotacaoRelativaInicial

			estado.alignOrientation.CFrame = rotacaoFinal
		end
	end
end

local function AtualizarHover()

	estado.alvoHover = DetectarAlvoHover()

	AplicarHighlight(estado.alvoHover)
end

local function OnInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		IniciarArrasto()
	end
end

local function OnInputEnded(input: InputObject, _gameProcessed: boolean)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		PararArrasto()
	end
end

local function HandleArrastarAction(_actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject)
	if inputState == Enum.UserInputState.Begin then
		IniciarArrasto()
	elseif inputState == Enum.UserInputState.End then
		PararArrasto()
	end

	return Enum.ContextActionResult.Pass
end

UserInputService.InputBegan:Connect(OnInputBegan)
UserInputService.InputEnded:Connect(OnInputEnded)

RunService.RenderStepped:Connect(function(deltaTime)

	if estado.interacaoBloqueada then
		if estado.arrastando then
			PararArrasto()
		end
		if estado.alvoHover then
			AplicarHighlight(nil)
			estado.alvoHover = nil
		end
		return
	end

	if estado.arrastando then
		AtualizarArrasto(deltaTime)
	else
		AtualizarHover()
	end
end)

player.CharacterRemoving:Connect(function()
	PararArrasto()
	AplicarHighlight(nil)
end)

if UserInputService.TouchEnabled then
	ContextActionService:BindAction(
		CONFIG.NOME_ACAO_ARRASTAR,
		HandleArrastarAction,
		false,
		Enum.UserInputType.Touch
	)
end

local function AtualizarBloqueioArrastar(modoAnimacao: string)
	local bloqueado = Modulo_Configuracoes.BloqueiaInteracao(modoAnimacao)
	estado.interacaoBloqueada = bloqueado

	if bloqueado and estado.arrastando then
		PararArrasto()
	end
end

local function ConectarStatusLocalArrastar(character: Model)
	local statusLocal = character:WaitForChild("StatusLocal", 10)
	if not statusLocal then
		return
	end
	local modoVal = statusLocal:WaitForChild("modoAnimacao", 10)
	if not modoVal then
		return
	end

	modoVal.Changed:Connect(function(novoModo)
		AtualizarBloqueioArrastar(novoModo)
	end)

	AtualizarBloqueioArrastar(modoVal.Value)
end

if player.Character then
	task.spawn(ConectarStatusLocalArrastar, player.Character)
end

player.CharacterAdded:Connect(function(character)
	estado.interacaoBloqueada = false
	task.spawn(ConectarStatusLocalArrastar, character)
end)

DebugPrint("Sistema de arrastar inicializado (cliente)")
