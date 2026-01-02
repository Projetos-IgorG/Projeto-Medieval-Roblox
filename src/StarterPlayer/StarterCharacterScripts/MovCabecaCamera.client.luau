local camera = workspace.CurrentCamera

local character = game.Players.LocalPlayer.Character or game.Players.LocalPlayer.CharacterAdded:Wait()
local root = character:WaitForChild("HumanoidRootPart")
local neck = character:FindFirstChild("Neck", true)
local yOffset = neck.C0.Y

local CFNew, CFAng, asin = CFrame.new, CFrame.Angles, math.asin

local targetC0 = neck.C0

game:GetService("RunService").RenderStepped:Connect(function(dt)
	local cameraDirection = root.CFrame:toObjectSpace(camera.CFrame).lookVector

	local maxSide = math.rad(55)      -- Lateral: 55° p/ cada lado
	local maxUpDown = math.rad(30)    -- Vertical: 30° p/ cima/baixo

	local sideAngle = math.clamp(-asin(cameraDirection.x), -maxSide, maxSide)
	local upDownAngle = math.clamp(-asin(cameraDirection.y), -maxUpDown, maxUpDown)

	local desiredC0 =
		CFNew(0, yOffset, 0)
		* CFrame.Angles(3 * math.pi/2, 0, math.pi)
		* CFAng(0, 0, sideAngle)
		* CFAng(upDownAngle, 0, 0)

	targetC0 = targetC0:Lerp(desiredC0, 0.2) -- menor = transição mais lenta
	neck.C0 = targetC0
end)
