--[[
	Módulo Client para o Sistema de Diálogo.
	Gerencia a UI, Efeitos, Câmera e Restrições do Jogador durante a conversa.
	
	UI: Usa dois BillboardGuis dentro de um ScreenGui "Dialogos" no StarterGui:
	  - DialogoGui (Adornee = NPC Model) → fala do NPC (FrameDialogo + FrameNome)
	  - DialogoGuiRespostas (Adornee = NPC Model) → opções do jogador
	      - RespostasTemplates (Folder com 'template' original)
	      - FrameRespostas (container onde os clones são colocados)
]]
local SistemaDialogoClient = {}

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

-- Ponte de comunicação entre scripts client-side (substitui _G)
local ClientBridge =
	require(ReplicatedStorage:WaitForChild("Modulos"):WaitForChild("Core"):WaitForChild("ClientBridge"))

local LocalPlayer = Players.LocalPlayer

-- Pastas e Referências
local Modulos = ReplicatedStorage:WaitForChild("Modulos")
local GerenciadorRequisitos = require(Modulos:WaitForChild("GerenciadorRequisitos"))
local SistemaDialogoFolder = Modulos:WaitForChild("SistemaDialogo")
local FolderDialogos = SistemaDialogoFolder:WaitForChild("Dialogos")
local FolderDialogosUnicos = FolderDialogos:WaitForChild("Unicos")
local FolderDialogosProfissoes = FolderDialogos:WaitForChild("Profissoes")
local FolderDialogosGenericos = FolderDialogos:WaitForChild("Genericos")
local FolderRemotes = SistemaDialogoFolder:WaitForChild("DialogoRemotes")

-- Sistema de Voz
local GerenciadorVoz = require(SistemaDialogoFolder:WaitForChild("Voz"):WaitForChild("GerenciadorVoz"))

-- Remote de Ações
local RemoteAcao = FolderRemotes:FindFirstChild("AcaoDialogo")
if not RemoteAcao then
	RemoteAcao = Instance.new("RemoteEvent")
	RemoteAcao.Name = "AcaoDialogo"
	RemoteAcao.Parent = FolderRemotes
end

local RemoteSolicitarChatIA = FolderRemotes:FindFirstChild("SolicitarChatIA")
if not RemoteSolicitarChatIA then
	RemoteSolicitarChatIA = Instance.new("RemoteEvent")
	RemoteSolicitarChatIA.Name = "SolicitarChatIA"
	RemoteSolicitarChatIA.Parent = FolderRemotes
end

local RemoteRespostaChatIA = FolderRemotes:FindFirstChild("RespostaChatIA")
if not RemoteRespostaChatIA then
	RemoteRespostaChatIA = Instance.new("RemoteEvent")
	RemoteRespostaChatIA.Name = "RespostaChatIA"
	RemoteRespostaChatIA.Parent = FolderRemotes
end

-- UI (ScreenGui com os dois BillboardGuis)
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local ScreenGuiDialogos = PlayerGui:WaitForChild("Dialogos")
local DialogoGui = ScreenGuiDialogos:WaitForChild("DialogoGui") -- BillboardGui de fala
local DialogoGuiRespostas = ScreenGuiDialogos:WaitForChild("DialogoGuiRespostas") -- BillboardGui de respostas
local FrameRespostas = DialogoGuiRespostas:WaitForChild("FrameRespostas") -- Container dos botões clonados
local RespostasTemplates = DialogoGuiRespostas:WaitForChild("RespostasTemplates") -- Folder com template original

-- Estado Local
local ConversaAtiva = false
local NPCAtual = nil
local TabelaDialogoAtual = nil
local DadosNPCAtual = nil
local HandleVozAtual = nil -- Handle do GerenciadorVoz ativo

local OpcoesAtuais = {}
local PodeEscolher = false
local EntradaChatIAEmFoco = false
local RequisicaoChatIAPendente = nil

-- ==========================================
-- Configurações
-- ==========================================
-- Velocidade do efeito typewriter (agora configurado em ConfigVoz)
-- Quanto a câmera corrige horizontalmente para centralizar o NPC (0 = nenhuma, 1 = total)
local CAMERA_CORRECAO_HORIZONTAL = 0.05
-- Quanto a câmera corrige verticalmente para olhar na altura do NPC (0 = nenhuma, 1 = total)
local CAMERA_CORRECAO_VERTICAL = 0.0
-- Duração da correção da câmera (segundos)
local CAMERA_CORRECAO_DURACAO = 0.25

-- Configurações de botão
local BOTAO_Y_PADRAO = 0.15
local BOTAO_Y_GRANDE = 0.3
local BOTAO_LIMIAR_LETRAS = 40 -- Acima disso, botão cresce em Y
local LIMITE_CARACTERES_CHAT_IA = 180

-- Expõe flag para outros sistemas via ClientBridge (ex: ControladorEstado bloquear equip)
ClientBridge.EmDialogo = function()
	return ConversaAtiva
end

-- Voz: toda a lógica foi movida para os módulos em Voz/

-- Conexão ativa da rotação da câmera (para poder cancelar)
local cameraRotacaoConexao = nil

--- Rotaciona a câmera suavemente em direção ao HumanoidRootPart do NPC.
local function RotacionarCameraParaNPC(npc)
	if cameraRotacaoConexao then
		cameraRotacaoConexao:Disconnect()
		cameraRotacaoConexao = nil
	end

	local npcRoot = npc:FindFirstChild("HumanoidRootPart")
	if not npcRoot then
		return
	end

	local char = LocalPlayer.Character
	if not char then
		return
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local camera = workspace.CurrentCamera
	local duracao = CAMERA_CORRECAO_DURACAO
	local tempoInicio = tick()

	cameraRotacaoConexao = RunService.RenderStepped:Connect(function()
		local elapsed = tick() - tempoInicio
		local alpha = math.clamp(elapsed / duracao, 0, 1)

		if alpha >= 1 or not ConversaAtiva then
			if cameraRotacaoConexao then
				cameraRotacaoConexao:Disconnect()
				cameraRotacaoConexao = nil
			end
			return
		end

		local camPos = camera.CFrame.Position
		local currentLook = camera.CFrame.LookVector

		local yawAtual = math.atan2(-currentLook.X, -currentLook.Z)
		local pitchAtual = math.asin(currentLook.Y)

		local delta = npcRoot.Position - camPos
		if delta.Magnitude < 0.01 then
			return
		end
		local alvoUnit = delta.Unit
		local yawAlvo = math.atan2(-alvoUnit.X, -alvoUnit.Z)
		local pitchAlvo = math.asin(alvoUnit.Y)

		local diffYaw = yawAlvo - yawAtual
		if diffYaw > math.pi then
			diffYaw = diffYaw - 2 * math.pi
		end
		if diffYaw < -math.pi then
			diffYaw = diffYaw + 2 * math.pi
		end
		local yawFinal = yawAtual + diffYaw * alpha * CAMERA_CORRECAO_HORIZONTAL

		local pitchFinal = pitchAtual + (pitchAlvo - pitchAtual) * alpha * CAMERA_CORRECAO_VERTICAL

		local lookFinal = Vector3.new(
			-math.sin(yawFinal) * math.cos(pitchFinal),
			math.sin(pitchFinal),
			-math.cos(yawFinal) * math.cos(pitchFinal)
		)

		camera.CFrame = CFrame.new(camPos, camPos + lookFinal)
	end)
end

local function IniciarCameraZoom(npc)
	RotacionarCameraParaNPC(npc)
end

local function AlterarRestricoesJogador(travado)
	ProximityPromptService.Enabled = not travado
	if travado then
		local char = LocalPlayer.Character
		if char then
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then
				hum:UnequipTools()
			end
		end
	end
end

-- Limpa os botões de resposta clonados do FrameRespostas
local function LimparOpcoes()
	for _, child in FrameRespostas:GetChildren() do
		if child.Name ~= "UIListLayout" then
			child:Destroy()
		end
	end
	OpcoesAtuais = {}
	PodeEscolher = false
	EntradaChatIAEmFoco = false
end

local function ObterDadosNPC(npc)
	local dadosFolder = npc and npc:FindFirstChild("Dados")
	if not dadosFolder then
		return nil
	end

	local nomeNPC = dadosFolder:FindFirstChild("Nome") and dadosFolder.Nome.Value or "NPC"
	local profissaoNPC = dadosFolder:FindFirstChild("Profissao") and dadosFolder.Profissao.Value or "Generico"
	local estadoNPC = dadosFolder:FindFirstChild("Estado") and dadosFolder.Estado.Value or "Livre"
	local tipoVozNPC = dadosFolder:FindFirstChild("TipoVoz") and dadosFolder.TipoVoz.Value or "Homem"
	local canChatAI = dadosFolder:FindFirstChild("CanChatAI") and dadosFolder.CanChatAI.Value == true or false
	local contextoNPC = dadosFolder:FindFirstChild("Contexto") and dadosFolder.Contexto.Value or ""

	return {
		Nome = nomeNPC,
		Profissao = profissaoNPC,
		Estado = estadoNPC,
		TipoVoz = tipoVozNPC,
		CanChatAI = canChatAI,
		Contexto = contextoNPC,
	}
end

-- Fim do diálogo
local function EncerrarDialogo()
	ConversaAtiva = false
	NPCAtual = nil
	TabelaDialogoAtual = nil
	DadosNPCAtual = nil
	RequisicaoChatIAPendente = nil

	-- Parar qualquer voz ativa
	if HandleVozAtual then
		HandleVozAtual:Parar()
		HandleVozAtual = nil
	end

	LimparOpcoes()
	AlterarRestricoesJogador(false)

	-- Esconder os BillboardGuis e limpar Adornee
	DialogoGui.Enabled = false
	DialogoGui.Adornee = nil
	DialogoGuiRespostas.Enabled = false
	DialogoGuiRespostas.Adornee = nil
end

-- Hover animation settings
local HOVER_TWEEN_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local MostrarFalaEOpcoes

local function ConfigurarHoverOpcao(btn)
	local uiScale = btn:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Scale = 1
		uiScale.Parent = btn
	end

	if btn:IsA("GuiButton") then
		btn.MouseEnter:Connect(function()
			TweenService:Create(btn, HOVER_TWEEN_INFO, { ImageTransparency = 0.7 }):Play()
			TweenService:Create(uiScale, HOVER_TWEEN_INFO, { Scale = 1.05 }):Play()
		end)
		btn.MouseLeave:Connect(function()
			TweenService:Create(btn, HOVER_TWEEN_INFO, { ImageTransparency = 0.85 }):Play()
			TweenService:Create(uiScale, HOVER_TWEEN_INFO, { Scale = 1 }):Play()
		end)
	end
end

local function PreencherIndiceOpcao(instancia, index)
	local lblIndex = instancia:FindFirstChild("IndexNum", true)
	if lblIndex and lblIndex:IsA("TextLabel") then
		lblIndex.Text = index .. ". "
	end
end

local function CriarOpcaoPeloTemplate(index, texto, acaoCallback)
	local template = RespostasTemplates:FindFirstChild("Template")
	if not template then
		warn("[DialogoClient] Template não encontrado em RespostasTemplates!")
		return
	end

	local btn = template:Clone()
	btn.Name = "Opcao_" .. index
	btn.Visible = true

	local lbl = btn:FindFirstChild("text", true)
	if lbl and lbl:IsA("TextLabel") then
		lbl.Text = texto
	end

	PreencherIndiceOpcao(btn, index)

	-- Se o texto for longo demais, aumenta o botão em Y para caber
	if #texto > BOTAO_LIMIAR_LETRAS then
		btn.Size = UDim2.new(btn.Size.X.Scale, btn.Size.X.Offset, BOTAO_Y_GRANDE, btn.Size.Y.Offset)
	else
		btn.Size = UDim2.new(btn.Size.X.Scale, btn.Size.X.Offset, BOTAO_Y_PADRAO, btn.Size.Y.Offset)
	end

	btn.Parent = FrameRespostas
	ConfigurarHoverOpcao(btn)

	btn.MouseButton1Click:Connect(function()
		if PodeEscolher then
			acaoCallback()
		end
	end)

	return btn
end

local function MostrarFalaPorId(idFala, dadosNPC)
	local proximaFala = TabelaDialogoAtual.Ramificacoes and TabelaDialogoAtual.Ramificacoes[idFala]
	if proximaFala then
		MostrarFalaEOpcoes(proximaFala, dadosNPC)
	else
		warn("Falta a referência para: " .. tostring(idFala))
		EncerrarDialogo()
	end
end

local function EnviarPerguntaChatIA(textBox, escolha, dadosNPC)
	if not ConversaAtiva or not NPCAtual or not PodeEscolher then
		return
	end

	local pergunta = textBox.Text or ""
	pergunta = pergunta:gsub("%c", " ")
	pergunta = pergunta:match("^%s*(.-)%s*$") or ""

	if pergunta == "" then
		textBox.PlaceholderText = "Escreva tua pergunta primeiro."
		return
	end

	if #pergunta > LIMITE_CARACTERES_CHAT_IA then
		textBox.Text = string.sub(pergunta, 1, LIMITE_CARACTERES_CHAT_IA)
		textBox.CursorPosition = #textBox.Text + 1
		textBox.PlaceholderText = "Pergunta longa demais. Máximo de 180 caracteres."
		return
	end

	PodeEscolher = false
	EntradaChatIAEmFoco = false
	RequisicaoChatIAPendente = {
		NPC = NPCAtual,
		DadosNPC = dadosNPC,
		RetornarParaId = escolha.RetornarParaId,
	}

	textBox.TextEditable = false
	textBox.PlaceholderText = "Aguardando a resposta do NPC..."

	RemoteSolicitarChatIA:FireServer({
		NPC = NPCAtual,
		Mensagem = pergunta,
	})
end

local function CriarEntradaChatIAPeloTemplate(index, escolha, dadosNPC)
	local template = RespostasTemplates:FindFirstChild("TemplateAIChat")
	if not template then
		warn("[DialogoClient] TemplateAIChat não encontrado em RespostasTemplates!")
		return
	end

	local entrada = template:Clone()
	entrada.Name = "OpcaoAIChat_" .. index
	entrada.Visible = true
	PreencherIndiceOpcao(entrada, index)
	entrada.Parent = FrameRespostas

	local textBox = entrada:FindFirstChildWhichIsA("TextBox", true)
	if not textBox then
		warn("[DialogoClient] TemplateAIChat sem TextBox!")
		entrada:Destroy()
		return
	end

	textBox.ClearTextOnFocus = false
	textBox.TextEditable = true
	textBox.PlaceholderText = escolha.PlaceholderText or "Escreva tua pergunta..."
	textBox.Text = ""

	local botaoEnviar = nil
	for _, desc in ipairs(entrada:GetDescendants()) do
		if desc ~= entrada and (desc:IsA("ImageButton") or desc:IsA("TextButton")) then
			botaoEnviar = desc
			break
		end
	end

	textBox.Focused:Connect(function()
		EntradaChatIAEmFoco = true
	end)

	textBox.FocusLost:Connect(function(enterPressed)
		EntradaChatIAEmFoco = false
		if enterPressed then
			EnviarPerguntaChatIA(textBox, escolha, dadosNPC)
		end
	end)

	if botaoEnviar then
		botaoEnviar.MouseButton1Click:Connect(function()
			EnviarPerguntaChatIA(textBox, escolha, dadosNPC)
		end)
	end

	return entrada
end

local function ExecutarEscolha(escolha, dadosNPC)
	PodeEscolher = false

	if escolha.AcaoServidor then
		RemoteAcao:FireServer(escolha.AcaoServidor)
	end

	if escolha.LevaParaId then
		MostrarFalaPorId(escolha.LevaParaId, dadosNPC)
		return
	end

	EncerrarDialogo()
end

-- ==========================================
-- Máquina de Conversa
-- ==========================================
function MostrarFalaEOpcoes(tabelaFala, dadosNPC)
	if not ConversaAtiva then
		return
	end
	DadosNPCAtual = dadosNPC
	LimparOpcoes()
	PodeEscolher = false

	-- Ativar BillboardGui de fala e apontar pro NPC
	DialogoGui.Adornee = NPCAtual
	DialogoGui.Enabled = true

	-- Fixar tamanho do Billboard para evitar reflow de texto ao mudar distância
	-- (AlwaysOnTop + tamanho fixo impede que o Billboard mude de escala com a distância)
	DialogoGui.AlwaysOnTop = true

	local frameDialogo = DialogoGui:FindFirstChild("FrameDialogo")
	local labelDialogo = frameDialogo and frameDialogo:FindFirstChild("Dialogo")
	if not labelDialogo then
		EncerrarDialogo()
		return
	end

	local frameNome = DialogoGui:FindFirstChild("FrameNome")
	if frameNome then
		local labelNome = frameNome:FindFirstChild("Nome")
		if labelNome then
			local nome = dadosNPC.Nome or "NPC"
			local profissao = dadosNPC.Profissao
			if profissao and profissao ~= "" then
				labelNome.Text = nome .. ", the " .. profissao
			else
				labelNome.Text = nome
			end
		end
	end

	-- Exibe o frame da fala
	frameDialogo.Visible = true
	local head = NPCAtual:FindFirstChild("Head")

	-- Parar voz anterior, se houver
	if HandleVozAtual then
		HandleVozAtual:Parar()
		HandleVozAtual = nil
	end

	-- Criar novo handle de voz via GerenciadorVoz
	local handleVoz = GerenciadorVoz.IniciarVoz(head, dadosNPC.TipoVoz)
	HandleVozAtual = handleVoz

	local velocidade = handleVoz:ObterVelocidade()
	local frequenciaSom = handleVoz:ObterFrequenciaSom()

	-- Efeito Typewriter
	labelDialogo.Text = ""
	local textoCompleto = tabelaFala.FalaNPC

	-- Iniciar o loop de murmúrio (CustomVoice, se ativo)
	handleVoz:IniciarLoop()

	for i = 1, #textoCompleto do
		if not ConversaAtiva then
			handleVoz:Parar()
			return
		end
		labelDialogo.Text = string.sub(textoCompleto, 1, i)

		-- Toca o tick (SimpleVoice, se ativo)
		if (i - 1) % frequenciaSom == 0 then
			handleVoz:TocarTick()
		end

		task.wait(velocidade)
	end

	-- Typewriter terminou — parar a voz
	handleVoz:Parar()
	HandleVozAtual = nil

	if not ConversaAtiva then
		return
	end

	if tabelaFala.RetornarParaId then
		task.wait(tabelaFala.TempoAntesDeRetornar or 0.35)
		if not ConversaAtiva then
			return
		end
		MostrarFalaPorId(tabelaFala.RetornarParaId, dadosNPC)
		return
	end

	if tabelaFala.FimDeDialogo then
		task.wait(2)
		EncerrarDialogo()
		return
	end

	-- Ativar BillboardGui de respostas e apontar pro NPC
	DialogoGuiRespostas.Adornee = NPCAtual
	DialogoGuiRespostas.Enabled = true
	DialogoGuiRespostas.AlwaysOnTop = true

	-- Montar Opções baseadas nos requisitos
	local opcoesValidas = {}
	if tabelaFala.Escolhas then
		for _, escolha in ipairs(tabelaFala.Escolhas) do
			local requisitosOk = not escolha.Requisitos
				or GerenciadorRequisitos.ChecarRequisitos(LocalPlayer, escolha.Requisitos)
			local podeUsarChatIA = not escolha.RequerCanChatAI or dadosNPC.CanChatAI
			if requisitosOk and podeUsarChatIA then
				table.insert(opcoesValidas, escolha)
			end
		end
	end

	-- Renderiza Botões
	for i, escolha in ipairs(opcoesValidas) do
		if escolha.Tipo == "AIChatInput" then
			CriarEntradaChatIAPeloTemplate(i, escolha, dadosNPC)
		else
			CriarOpcaoPeloTemplate(i, escolha.TextoMencionado, function()
				ExecutarEscolha(escolha, dadosNPC)
			end)
		end
		OpcoesAtuais[i] = escolha
	end

	PodeEscolher = true
end

local function EncontrarFalaInicial()
	if TabelaDialogoAtual.Inicio then
		for _, fala in ipairs(TabelaDialogoAtual.Inicio) do
			local valid = true
			if fala.Requisitos and not GerenciadorRequisitos.ChecarRequisitos(LocalPlayer, fala.Requisitos) then
				valid = false
			end
			if valid and fala.IgnorarSe then
				if GerenciadorRequisitos.ChecarRequisitos(LocalPlayer, fala.IgnorarSe) then
					valid = false
				end
			end
			if valid then
				return fala
			end
		end
	end
	return nil
end

local function IniciarDialogo(npc)
	if ConversaAtiva then
		return
	end

	local dadosFolder = npc:FindFirstChild("Dados")
	if not dadosFolder then
		return
	end

	local dadosNPC = ObterDadosNPC(npc)
	if not dadosNPC then
		return
	end

	-- Tentar carregar a tabela com Fallback:
	-- 1. Nome próprio do NPC → pasta Unicos
	-- 2. Profissão do NPC → pasta Profissoes
	-- 3. Fallback genérico → pasta Genericos
	-- 4. Fallback de criatura → pasta Criaturas (se o NPC for uma criatura)
	local moduloTabela = FolderDialogosUnicos:FindFirstChild(dadosNPC.Nome)
	if not moduloTabela then
		moduloTabela = FolderDialogosProfissoes:FindFirstChild(dadosNPC.Profissao)
		if not moduloTabela then
			moduloTabela = FolderDialogosGenericos:FindFirstChild("Generic")
			if not moduloTabela then
				warn(
					"[DialogoClient] Nenhum arquivo de diálogo encontrado para Nome: "
						.. dadosNPC.Nome
						.. ", Profissao: "
						.. dadosNPC.Profissao
						.. ". Nem mesmo o 'Generic' em Genericos."
				)
				return
			end
		end
	end

	local moduloExigido = require(moduloTabela)
	TabelaDialogoAtual = moduloExigido.Dialogos or moduloExigido

	-- Se estado for ocupado, soltar reposta genérica e sair
	if dadosNPC.Estado == "Dormindo" or dadosNPC.Estado == "EmCombate" or dadosNPC.Estado == "Ocupado" then
		ConversaAtiva = true
		NPCAtual = npc
		MostrarFalaEOpcoes({
			FalaNPC = (dadosNPC.Estado == "Dormindo" and "Zzzzz...") or "Estou um pouco ocupado agora...",
			FimDeDialogo = true,
		}, dadosNPC)
		return
	end

	ConversaAtiva = true
	NPCAtual = npc
	DadosNPCAtual = dadosNPC
	AlterarRestricoesJogador(true)
	IniciarCameraZoom(npc)

	-- Monitorar distância: se o jogador se afastar demais, encerra diálogo
	task.spawn(function()
		while ConversaAtiva and NPCAtual == npc do
			local char = LocalPlayer.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local npcRoot = npc:FindFirstChild("HumanoidRootPart")
			if hrp and npcRoot then
				local distancia = (hrp.Position - npcRoot.Position).Magnitude
				if distancia > 12 then
					EncerrarDialogo()
					break
				end
			end
			task.wait(0.5)
		end
	end)

	local falaInicial = EncontrarFalaInicial()
	if falaInicial then
		MostrarFalaEOpcoes(falaInicial, dadosNPC)
	else
		warn("[DialogoClient] Nenhuma fala inicial válida encontrada para " .. dadosNPC.Nome .. "!")
		EncerrarDialogo()
	end
end

-- ==========================================
-- Inicialização
-- ==========================================
function SistemaDialogoClient.Init()
	-- Garantir que os BillboardGuis comecem desativados
	DialogoGui.Enabled = false
	DialogoGuiRespostas.Enabled = false

	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if player ~= LocalPlayer then
			return
		end
		if prompt.ActionText == "Falar" then
			-- ProximityPrompt é filho direto do Model do NPC
			local npcModel = prompt.Parent
			if npcModel and npcModel:FindFirstChild("Humanoid") and npcModel:FindFirstChild("Dados") then
				IniciarDialogo(npcModel)
			end
		end
	end)

	-- Configura o ObjectText dos ProximityPrompts de NPCs com "Nome, the Profissao"
	for _, desc in ipairs(workspace:GetDescendants()) do
		if desc:IsA("ProximityPrompt") and desc.ActionText == "Falar" then
			local model = desc.Parent
			if model and model:FindFirstChild("Dados") then
				local dados = model:FindFirstChild("Dados")
				local nome = dados:FindFirstChild("Nome") and dados.Nome.Value or "NPC"
				local profissao = dados:FindFirstChild("Profissao") and dados.Profissao.Value or ""
				if profissao ~= "" then
					desc.ObjectText = nome .. ", the " .. profissao
				else
					desc.ObjectText = nome
				end
			end
		end
	end

	-- Impede o uso de Tools durante o diálogo
	LocalPlayer.CharacterAdded:Connect(function(char)
		char.ChildAdded:Connect(function(child)
			if ConversaAtiva and child:IsA("Tool") then
				local hum = char:FindFirstChildOfClass("Humanoid")
				if hum then
					task.defer(function()
						hum:UnequipTools()
					end)
				end
			end
		end)
	end)

	if LocalPlayer.Character then
		LocalPlayer.Character.ChildAdded:Connect(function(child)
			if ConversaAtiva and child:IsA("Tool") then
				local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
				if hum then
					task.defer(function()
						hum:UnequipTools()
					end)
				end
			end
		end)
	end

	-- Listeners de Input para números 1-9
	UserInputService.InputBegan:Connect(function(input, _gp)
		if not ConversaAtiva or not PodeEscolher or EntradaChatIAEmFoco then
			return
		end
		if input.UserInputType == Enum.UserInputType.Keyboard then
			local num = input.KeyCode.Value - Enum.KeyCode.Zero.Value
			if num >= 1 and num <= 9 then
				local opcao = OpcoesAtuais[num]
				if opcao and opcao.Tipo ~= "AIChatInput" then
					ExecutarEscolha(opcao, DadosNPCAtual or ObterDadosNPC(NPCAtual))
				end
			end
		end
	end)

	RemoteRespostaChatIA.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" or not ConversaAtiva then
			return
		end

		if not RequisicaoChatIAPendente then
			return
		end

		if payload.NPC ~= RequisicaoChatIAPendente.NPC or payload.NPC ~= NPCAtual then
			return
		end

		local dadosNPC = RequisicaoChatIAPendente.DadosNPC or DadosNPCAtual or ObterDadosNPC(NPCAtual)
		local retornarParaId = RequisicaoChatIAPendente.RetornarParaId
		local mensagem = payload.Mensagem or "..."

		RequisicaoChatIAPendente = nil
		PodeEscolher = false

		MostrarFalaEOpcoes({
			FalaNPC = mensagem,
			RetornarParaId = retornarParaId,
		}, dadosNPC)
	end)
end

return SistemaDialogoClient
