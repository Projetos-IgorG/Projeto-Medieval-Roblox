local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RotacaoCabeca = require(ReplicatedStorage:WaitForChild("Jogador"):WaitForChild("Camera"):WaitForChild("Cabeca"):WaitForChild("RotacaoCabeca"))

local camera = workspace.CurrentCamera
local player = Players.LocalPlayer

local connection: RBXScriptConnection? = nil

local function setup(character: Model)
	-- Limpa conexão anterior (respawn)
	if connection then
		connection:Disconnect()
		connection = nil
	end

	local root = character:WaitForChild("HumanoidRootPart", 5)
	local neck = character:FindFirstChild("Neck", true)
	if not root or not neck then return end

	local yOffset = neck.C0.Y
	local targetC0 = neck.C0

	connection = RunService.RenderStepped:Connect(function(_dt)
		if not root.Parent or not neck.Parent then
			if connection then
				connection:Disconnect()
				connection = nil
			end
			return
		end

		local cameraDirection = root.CFrame:ToObjectSpace(camera.CFrame).LookVector
		local desiredC0 = RotacaoCabeca.CalcularTargetC0(cameraDirection, yOffset)
		targetC0 = targetC0:Lerp(desiredC0, 0.2)
		neck.C0 = targetC0
	end)

	-- Limpa ao morrer
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Once(function()
			if connection then
				connection:Disconnect()
				connection = nil
			end
		end)
	end
end

if player.Character then
	setup(player.Character)
end
player.CharacterAdded:Connect(setup)
