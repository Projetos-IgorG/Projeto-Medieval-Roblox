--[[
    ServicoPortal.luau
    
    Sistema de Portais Teleportadores
    Gerencia o teleporte entre dois portais com efeito de fade
]]

local ServicoPortal = {}

-- ═══════════════════════════════════════════════════════════════════
-- CONFIGURAÇÃO DE DEBUG
-- ═══════════════════════════════════════════════════════════════════
local DEBUG_ENABLED = false

local function DebugPrint(...)
	if DEBUG_ENABLED then
		print("[ServicoPortal]", ...)
	end
end

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Configurações dos portais
local PORTAL_DISTANCE = 7
local TELEPORT_DURATION = 0.8
local FADE_DURATION = 0.1
local COOLDOWN_TIME = 2

-- Tabela para controlar cooldown de teleporte por player
local playerCooldowns = {}

-- RemoteEvent (será criado na inicialização)
local cameraUpdateEvent = nil

-- Função para criar a tela de transição preta
local function createTransitionScreen(player)
	local playerGui = player:WaitForChild("PlayerGui")
	local oldScreen = playerGui:FindFirstChild("PortalTransitionScreen")
	if oldScreen then
		oldScreen:Destroy()
	end
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PortalTransitionScreen"
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.Position = UDim2.new(0, 0, 0, 0)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = screenGui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 200, 0, 50)
	label.Position = UDim2.new(0.5, -100, 0.5, -25)
	label.BackgroundTransparency = 1
	label.Text = "Teleportando..."
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.SourceSansBold
	label.TextTransparency = 1
	label.Parent = frame

	return frame, label
end

local function fadeTransition(frame, label, targetTransparency, duration)
	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	local bgTween = TweenService:Create(frame, tweenInfo, {
		BackgroundTransparency = targetTransparency,
	})
	local textTransparency = targetTransparency == 0 and 0 or 1
	local textTween = TweenService:Create(label, tweenInfo, {
		TextTransparency = textTransparency,
	})
	bgTween:Play()
	textTween:Play()
	return bgTween
end

local function teleportPlayerToPortalFront(player, targetPortal)
	local character = player.Character
	if not character then
		return
	end
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return
	end

	local portalCFrame = targetPortal.CFrame
	local targetCFrame = portalCFrame * CFrame.new(0, 0, -PORTAL_DISTANCE)
	character:PivotTo(targetCFrame)
	cameraUpdateEvent:FireClient(player, portalCFrame.LookVector)
end

local function teleportPlayer(player, fromPortal, toPortal)
	if playerCooldowns[player] and (tick() - playerCooldowns[player]) < COOLDOWN_TIME then
		return
	end
	playerCooldowns[player] = tick()
	local transitionFrame, textLabel = createTransitionScreen(player)
	local fadeInTween = fadeTransition(transitionFrame, textLabel, 0, FADE_DURATION)
	fadeInTween.Completed:Wait()
	teleportPlayerToPortalFront(player, toPortal)
	task.wait(TELEPORT_DURATION - (2 * FADE_DURATION))
	local fadeOutTween = fadeTransition(transitionFrame, textLabel, 1, FADE_DURATION)
	fadeOutTween.Completed:Wait()
	transitionFrame.Parent:Destroy()
end

local function onPortalTouched(portal, otherPortal)
	return function(otherPart)
		local character = otherPart.Parent
		if not character then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end
		if humanoid.Health <= 0 then
			return
		end
		teleportPlayer(player, portal, otherPortal)
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- INICIALIZAÇÃO DO SERVIÇO
-- ═══════════════════════════════════════════════════════════════════

function ServicoPortal:Iniciar()
	DebugPrint("Inicializando ServicoPortal...")

	-- Criar RemoteEvent para comunicação com o cliente
	cameraUpdateEvent = Instance.new("RemoteEvent")
	cameraUpdateEvent.Name = "PortalCameraUpdate"
	cameraUpdateEvent.Parent = ReplicatedStorage

	-- Referências aos portais
	local portal1 = workspace:FindFirstChild("Portal1")
	local portal2 = workspace:FindFirstChild("Portal2")

	if portal1 and portal2 then
		portal1.Touched:Connect(onPortalTouched(portal1, portal2))
		portal2.Touched:Connect(onPortalTouched(portal2, portal1))
		DebugPrint("Sistema de portais inicializado!")
		DebugPrint("Portal1 -> Portal2")
		DebugPrint("Portal2 -> Portal1")
	else
		DebugPrint("Portais não encontrados no Workspace (Portal1/Portal2) - pulando inicialização")
	end

	Players.PlayerRemoving:Connect(function(player)
		playerCooldowns[player] = nil
	end)

	DebugPrint("ServicoPortal inicializado!")
end

return ServicoPortal
