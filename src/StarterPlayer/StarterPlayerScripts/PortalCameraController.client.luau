-- Script cliente para controlar a câmera durante o teleporte do portal
-- Autor: Roblox Assistant

-- ═══════════════════════════════════════════════════════════════════
-- CONFIGURAÇÃO DE DEBUG
-- ═══════════════════════════════════════════════════════════════════
local DEBUG_ENABLED = false -- Altere para true para habilitar prints de debug

local function DebugPrint(...)
	if DEBUG_ENABLED then
		print(...)
	end
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Referência ao RemoteEvent
local cameraUpdateEvent = ReplicatedStorage:WaitForChild("PortalCameraUpdate")

-- Função para atualizar a câmera do cliente
local function updateCamera(lookDirection)
	local player = Players.LocalPlayer
	local character = player.Character

	if not character then
		return
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	-- Obter a direção atual da câmera
	local currentLookVector = camera.CFrame.LookVector

	-- Manter apenas o componente Y (horizontal) da direção do portal
	-- Manter o componente X (vertical) atual da câmera
	local portalHorizontal = Vector3.new(lookDirection.X, 0, lookDirection.Z).Unit
	local currentVertical = Vector3.new(0, currentLookVector.Y, 0)

	-- Combinar as direções: horizontal do portal + vertical atual
	local newLookDirection = (portalHorizontal + currentVertical).Unit

	-- Atualizar a câmera com a nova direção
	camera.CFrame = CFrame.new(humanoidRootPart.Position, humanoidRootPart.Position + newLookDirection)

	-- Forçar a câmera a manter essa rotação por um curto período
	local connection
	connection = RunService.Heartbeat:Connect(function()
		if camera and humanoidRootPart then
			camera.CFrame = CFrame.new(humanoidRootPart.Position, humanoidRootPart.Position + newLookDirection)
		end
	end)

	-- Remover a força após 0.5 segundos para permitir controle normal
	task.wait(0.5)
	if connection then
		connection:Disconnect()
	end
end

-- Conectar ao evento do servidor
cameraUpdateEvent.OnClientEvent:Connect(updateCamera)

DebugPrint("[PortalCameraController] Inicializado no cliente!")
