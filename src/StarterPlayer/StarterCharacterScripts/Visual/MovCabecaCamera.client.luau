local camera = workspace.CurrentCamera
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RotacaoCabeca = require(ReplicatedStorage:WaitForChild("Modulos"):WaitForChild("Cliente"):WaitForChild("Visual"):WaitForChild("RotacaoCabeca"))

local character = game.Players.LocalPlayer.Character or game.Players.LocalPlayer.CharacterAdded:Wait()
local root = character:WaitForChild("HumanoidRootPart")
local neck = character:FindFirstChild("Neck", true)
local yOffset = neck.C0.Y

local targetC0 = neck.C0

game:GetService("RunService").RenderStepped:Connect(function(_dt)
	local cameraDirection = root.CFrame:toObjectSpace(camera.CFrame).lookVector

	local desiredC0 = RotacaoCabeca.CalcularTargetC0(cameraDirection, yOffset)

	targetC0 = targetC0:Lerp(desiredC0, 0.2) -- menor = transição mais lenta
	neck.C0 = targetC0
end)
