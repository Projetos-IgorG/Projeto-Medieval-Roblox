-- Sistema de Portais Teleportadores
-- Script único que gerencia o teleporte entre dois portais
-- Autor: Roblox Assistant

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Configurações dos portais
local PORTAL_DISTANCE = 7 -- Distância na frente do portal onde o player vai aparecer
local TELEPORT_DURATION = 0.8 -- Duração total do teleporte (segundos)
local FADE_DURATION = 0.1 -- Duração de cada transição de fade (segundos)
local COOLDOWN_TIME = 2 -- Tempo de espera entre teleportes (segundos)

-- Criar RemoteEvent para comunicação com o cliente
local cameraUpdateEvent = Instance.new("RemoteEvent")
cameraUpdateEvent.Name = "PortalCameraUpdate"
cameraUpdateEvent.Parent = ReplicatedStorage

-- Referências aos portais
local portal1 = workspace:WaitForChild("Portal1")
local portal2 = workspace:WaitForChild("Portal2")

-- Tabela para controlar cooldown de teleporte por player
local playerCooldowns = {}

-- Função para criar a tela de transição preta
local function createTransitionScreen(player)
	local playerGui = player:WaitForChild("PlayerGui")

	-- Remover tela anterior se existir
	local oldScreen = playerGui:FindFirstChild("PortalTransitionScreen")
	if oldScreen then
		oldScreen:Destroy()
	end

	-- Criar nova tela
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PortalTransitionScreen"
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.Position = UDim2.new(0, 0, 0, 0)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 1 -- Começa invisível
	frame.BorderSizePixel = 0
	frame.Parent = screenGui

	-- Adicionar texto "Teleportando..."
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 200, 0, 50)
	label.Position = UDim2.new(0.5, -100, 0.5, -25) -- Centralizado
	label.BackgroundTransparency = 1
	label.Text = "Teleportando..."
	label.TextColor3 = Color3.new(1, 1, 1) -- Branco
	label.TextScaled = true
	label.Font = Enum.Font.SourceSansBold
	label.TextTransparency = 1 -- Começa invisível junto com o fundo
	label.Parent = frame

	return frame, label
end

-- Função para fazer a transição de fade
local function fadeTransition(frame, label, targetTransparency, duration)
	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)

	-- Tween para o fundo
	local bgTween = TweenService:Create(frame, tweenInfo, {
		BackgroundTransparency = targetTransparency,
	})

	-- Tween para o texto (sempre visível quando o fundo está visível)
	local textTransparency = targetTransparency == 0 and 0 or 1
	local textTween = TweenService:Create(label, tweenInfo, {
		TextTransparency = textTransparency,
	})

	bgTween:Play()
	textTween:Play()

	return bgTween
end

-- Função para teleportar player para a frente de um portal
local function teleportPlayerToPortalFront(player, targetPortal)
	local character = player.Character
	if not character then
		return
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return
	end

	-- Calcular posição na frente do portal baseado na rotação
	local portalCFrame = targetPortal.CFrame

	-- Criar nova CFrame com a mesma rotação do portal
	-- Isso faz o player ficar olhando na mesma direção que o portal
	local targetCFrame = portalCFrame * CFrame.new(0, 0, -PORTAL_DISTANCE)

	-- Teleportar o character
	character:PivotTo(targetCFrame)

	-- Enviar informação para o cliente ajustar a câmera
	cameraUpdateEvent:FireClient(player, portalCFrame.LookVector)
end

-- Função principal de teleporte
local function teleportPlayer(player, fromPortal, toPortal)
	-- Verificar cooldown
	if playerCooldowns[player] and (tick() - playerCooldowns[player]) < COOLDOWN_TIME then
		return
	end

	-- Atualizar cooldown
	playerCooldowns[player] = tick()

	-- Criar tela de transição
	local transitionFrame, textLabel = createTransitionScreen(player)

	-- Fase 1: Fade in (tela fica preta com texto)
	local fadeInTween = fadeTransition(transitionFrame, textLabel, 0, FADE_DURATION)

	-- Esperar o fade in completar
	fadeInTween.Completed:Wait()

	-- Fase 2: Teleporte (durante a tela preta)
	teleportPlayerToPortalFront(player, toPortal)

	-- Esperar um pouco na tela preta (parte do tempo restante)
	task.wait(TELEPORT_DURATION - (2 * FADE_DURATION))

	-- Fase 3: Fade out (tela volta ao normal)
	local fadeOutTween = fadeTransition(transitionFrame, textLabel, 1, FADE_DURATION)

	-- Esperar o fade out completar e limpar
	fadeOutTween.Completed:Wait()
	transitionFrame.Parent:Destroy()
end

-- Função para detectar quando um player toca em um portal
local function onPortalTouched(portal, otherPortal)
	return function(otherPart)
		-- Verificar se foi um character que tocou
		local character = otherPart.Parent
		if not character then
			return
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end

		-- Encontrar o player dono do character
		local player = Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end

		-- Verificar se o player está vivo
		if humanoid.Health <= 0 then
			return
		end

		-- Realizar o teleporte
		teleportPlayer(player, portal, otherPortal)
	end
end

-- Configurar eventos de toque para os portais
if portal1 and portal2 then
	portal1.Touched:Connect(onPortalTouched(portal1, portal2))
	portal2.Touched:Connect(onPortalTouched(portal2, portal1))

	print("Sistema de portais inicializado com sucesso!")
	print("Portal1 (azul) -> Portal2 (laranja)")
	print("Portal2 (laranja) -> Portal1 (azul)")
else
	warn("Erro: Portais não encontrados no Workspace!")
end

-- Limpar cooldowns de players que saem do jogo
Players.PlayerRemoving:Connect(function(player)
	playerCooldowns[player] = nil
end)
