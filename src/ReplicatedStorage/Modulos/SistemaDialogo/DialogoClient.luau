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

local LocalPlayer = Players.LocalPlayer

-- Pastas e Referências
local Modulos = ReplicatedStorage:WaitForChild("Modulos")
local GerenciadorRequisitos = require(Modulos:WaitForChild("GerenciadorRequisitos"))
local SistemaDialogoFolder = Modulos:WaitForChild("SistemaDialogo")
local FolderDialogos = SistemaDialogoFolder:WaitForChild("Dialogos")
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
local HandleVozAtual = nil -- Handle do GerenciadorVoz ativo

local OpcoesAtuais = {}
local PodeEscolher = false

-- ==========================================
-- Configurações
-- ==========================================
-- Velocidade do efeito typewriter (agora configurado em ConfigVoz)
-- Quanto a câmera corrige horizontalmente para centralizar o NPC (0 = nenhuma, 1 = total)
local CAMERA_CORRECAO_HORIZONTAL = 0.2
-- Quanto a câmera corrige verticalmente para olhar na altura do NPC (0 = nenhuma, 1 = total)
local CAMERA_CORRECAO_VERTICAL = 0.0
-- Duração da correção da câmera (segundos)
local CAMERA_CORRECAO_DURACAO = 0.2

-- Expõe flag global para outros sistemas (ex: ControladorEstado bloquear equip)
_G.EmDialogo = function()
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
	local camera = workspace.CurrentCamera
	TweenService
		:Create(camera, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = 75 })
		:Play()
	RotacionarCameraParaNPC(npc)
end

local function ResetarCamera()
	local camera = workspace.CurrentCamera
	TweenService
		:Create(camera, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = 70 })
		:Play()
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
end

-- Fim do diálogo
local function EncerrarDialogo()
	ConversaAtiva = false
	NPCAtual = nil
	TabelaDialogoAtual = nil

	-- Parar qualquer voz ativa
	if HandleVozAtual then
		HandleVozAtual:Parar()
		HandleVozAtual = nil
	end

	LimparOpcoes()
	ResetarCamera()
	AlterarRestricoesJogador(false)

	-- Esconder os BillboardGuis e limpar Adornee
	DialogoGui.Enabled = false
	DialogoGui.Adornee = nil
	DialogoGuiRespostas.Enabled = false
	DialogoGuiRespostas.Adornee = nil
end

-- Tamanho base dos botões (X scale, Y scale)
local BOTAO_MIN_X = 0.45
local BOTAO_MAX_X = 0.85
local BOTAO_MIN_Y = 0.12 -- botão de texto curto (1 linha)
local BOTAO_MAX_Y = 0.20 -- botão de texto longo
local BOTAO_LIMIAR_TEXTO = 35 -- acima desse nº de caracteres, começa a crescer
local BOTAO_LIMIAR_MAX = 90 -- nº de caracteres para atingir X/Y máximo

-- Hover animation settings
local HOVER_TWEEN_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function CalcularTamanhoBotao(textoCompleto)
	local numChars = #textoCompleto
	if numChars <= BOTAO_LIMIAR_TEXTO then
		return UDim2.new(BOTAO_MIN_X, 0, BOTAO_MIN_Y, 0)
	end

	-- Interpolar linearmente entre min e max baseado no comprimento do texto
	local alpha = math.clamp((numChars - BOTAO_LIMIAR_TEXTO) / (BOTAO_LIMIAR_MAX - BOTAO_LIMIAR_TEXTO), 0, 1)
	local xSize = BOTAO_MIN_X + (BOTAO_MAX_X - BOTAO_MIN_X) * alpha
	local ySize = BOTAO_MIN_Y + (BOTAO_MAX_Y - BOTAO_MIN_Y) * alpha
	return UDim2.new(xSize, 0, ySize, 0)
end

local function CriarOpcaoPeloTemplate(index, texto, acaoCallback)
	local template = RespostasTemplates:FindFirstChild("template")
	if not template then
		warn("[DialogoClient] Template não encontrado em RespostasTemplates!")
		return
	end

	local btn = template:Clone()
	btn.Name = "Opcao_" .. index
	btn.Visible = true

	local lbl = btn:FindFirstChild("text")
	if lbl then
		-- Label apenas para o texto (que vai escalar)
		lbl.Text = texto
		lbl.RichText = false
		lbl.TextWrapped = true
		lbl.AutomaticSize = Enum.AutomaticSize.None

		local offsetIndex = 45 -- Espaço reservado para o "1. "

		-- Label separada e fixa para o número (ex: "1. ")
		local lblIndex = lbl:Clone()
		lblIndex.Name = "IndexNum"
		lblIndex.Text = index .. ". "
		lblIndex.TextColor3 = Color3.fromRGB(255, 220, 127)
		lblIndex.RichText = false
		lblIndex.TextScaled = true
		lblIndex.TextWrapped = true
		lblIndex.TextSize = 50
		lblIndex.TextXAlignment = Enum.TextXAlignment.Right
		lblIndex.Size = UDim2.new(0, offsetIndex, lbl.Size.Y.Scale, lbl.Size.Y.Offset)
		lblIndex.Position = lbl.Position
		lblIndex.Parent = btn

		-- Reduzir e deslocar a label do texto principal
		lbl.Size = UDim2.new(lbl.Size.X.Scale, lbl.Size.X.Offset - offsetIndex, lbl.Size.Y.Scale, lbl.Size.Y.Offset)
		lbl.Position = UDim2.new(
			lbl.Position.X.Scale,
			lbl.Position.X.Offset + offsetIndex,
			lbl.Position.Y.Scale,
			lbl.Position.Y.Offset
		)
	end

	-- Ajustar tamanho do botão baseado no comprimento do texto
	local textoFormatado = index .. " .  " .. texto
	local tamanhoBase = CalcularTamanhoBotao(textoFormatado)
	btn.Size = tamanhoBase

	btn.Parent = FrameRespostas

	-- Criar um UIScale para controlar a animação uniforme sem distorcer margens do botão/imagem
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = 1
	uiScale.Parent = btn

	-- Animações Hover (scale up (Zoom 105%) usando o UIScale + transparência usando o btn pai nativo)
	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, HOVER_TWEEN_INFO, { BackgroundTransparency = 0.8 }):Play()
		TweenService:Create(uiScale, HOVER_TWEEN_INFO, { Scale = 1.05 }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, HOVER_TWEEN_INFO, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(uiScale, HOVER_TWEEN_INFO, { Scale = 1 }):Play()
	end)

	btn.MouseButton1Click:Connect(function()
		if PodeEscolher then
			acaoCallback()
		end
	end)

	return btn
end

-- ==========================================
-- Máquina de Conversa
-- ==========================================
local function MostrarFalaEOpcoes(tabelaFala, dadosNPC)
	if not ConversaAtiva then
		return
	end
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
			labelNome.Text = dadosNPC.Nome or "NPC"
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
			if not escolha.Requisitos or GerenciadorRequisitos.ChecarRequisitos(LocalPlayer, escolha.Requisitos) then
				table.insert(opcoesValidas, escolha)
			end
		end
	end

	-- Renderiza Botões
	for i, escolha in ipairs(opcoesValidas) do
		CriarOpcaoPeloTemplate(i, escolha.TextoMencionado, function()
			PodeEscolher = false

			if escolha.AcaoServidor then
				RemoteAcao:FireServer(escolha.AcaoServidor)
			end

			local idSeguinte = escolha.LevaParaId
			local proximaFala = TabelaDialogoAtual.Ramificacoes and TabelaDialogoAtual.Ramificacoes[idSeguinte]

			if proximaFala then
				MostrarFalaEOpcoes(proximaFala, dadosNPC)
			else
				warn("Falta a referência para: " .. tostring(idSeguinte))
				EncerrarDialogo()
			end
		end)
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

	local nomeNPC = dadosFolder:FindFirstChild("Nome") and dadosFolder.Nome.Value or "NPC"
	local profissaoNPC = dadosFolder:FindFirstChild("Profissao") and dadosFolder.Profissao.Value or "Generico"
	local estadoNPC = dadosFolder:FindFirstChild("Estado") and dadosFolder.Estado.Value or "Livre"
	local tipoVozNPC = dadosFolder:FindFirstChild("TipoVoz") and dadosFolder.TipoVoz.Value or "Homem"

	-- Tentar carregar a tabela com Fallback
	local moduloTabela = FolderDialogos:FindFirstChild(nomeNPC)
	if not moduloTabela then
		moduloTabela = FolderDialogos:FindFirstChild(profissaoNPC)
		if not moduloTabela then
			moduloTabela = FolderDialogos:FindFirstChild("Generico")
			if not moduloTabela then
				warn(
					"[DialogoClient] Nenhum arquivo de diálogo encontrado para Nome: "
						.. nomeNPC
						.. ", Profissao: "
						.. profissaoNPC
						.. ". Nem mesmo o 'Generico'."
				)
				return
			end
		end
	end

	local moduloExigido = require(moduloTabela)
	TabelaDialogoAtual = moduloExigido.Dialogos or moduloExigido

	-- Se estado for ocupado, soltar reposta genérica e sair
	if estadoNPC == "Dormindo" or estadoNPC == "EmCombate" or estadoNPC == "Ocupado" then
		ConversaAtiva = true
		NPCAtual = npc
		MostrarFalaEOpcoes({
			FalaNPC = (estadoNPC == "Dormindo" and "Zzzzz...") or "Estou um pouco ocupado agora...",
			FimDeDialogo = true,
		}, { TipoVoz = tipoVozNPC, Nome = nomeNPC })
		return
	end

	ConversaAtiva = true
	NPCAtual = npc
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
		MostrarFalaEOpcoes(falaInicial, { TipoVoz = tipoVozNPC, Nome = nomeNPC })
	else
		warn("[DialogoClient] Nenhuma fala inicial válida encontrada para " .. nomeNPC .. "!")
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
		if not ConversaAtiva or not PodeEscolher then
			return
		end
		if input.UserInputType == Enum.UserInputType.Keyboard then
			local num = input.KeyCode.Value - Enum.KeyCode.Zero.Value
			if num >= 1 and num <= 9 then
				local opcao = OpcoesAtuais[num]
				if opcao then
					PodeEscolher = false

					if opcao.AcaoServidor then
						RemoteAcao:FireServer(opcao.AcaoServidor)
					end

					local idSeguinte = opcao.LevaParaId
					local proximaFala = TabelaDialogoAtual.Ramificacoes and TabelaDialogoAtual.Ramificacoes[idSeguinte]

					if proximaFala then
						local dadosFolder = NPCAtual:FindFirstChild("Dados")
						local nomeNPC = dadosFolder and dadosFolder:FindFirstChild("Nome") and dadosFolder.Nome.Value
							or "NPC"
						local tipoVoz = dadosFolder
								and dadosFolder:FindFirstChild("TipoVoz")
								and dadosFolder.TipoVoz.Value
							or "Homem"
						MostrarFalaEOpcoes(proximaFala, { TipoVoz = tipoVoz, Nome = nomeNPC })
					else
						EncerrarDialogo()
					end
				end
			end
		end
	end)
end

return SistemaDialogoClient
