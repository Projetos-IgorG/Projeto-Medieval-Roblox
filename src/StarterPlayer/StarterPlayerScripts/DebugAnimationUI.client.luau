-- StarterPlayer > StarterPlayerScripts > DebugAnimationUI (LocalScript)

--[[
    DebugAnimationUI
    ----------------
    UI leve para visualizar:
    - Player.Status.modoAnimacao
    - Player.Status.estadoMov
    - Player.Status.estadoAcao
    - Player.Status.ShiftLockOn
    - Player.Status.AgachadoOn
    - Player.Status.BloqueandoOn
    - Player.Status.StunadoOn

    Útil para inspecionar a máquina de estados e validar transições.
]]

--==============================================================================
-- Serviços
--==============================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

--==============================================================================
-- Criar UI
--==============================================================================

local function createLabelGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = "DebugAnimationUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.AnchorPoint = Vector2.new(0, 0)
	frame.Position = UDim2.new(0, 5, 0, 100)
	frame.Size = UDim2.new(0, 250, 0, 140)
	frame.Size = UDim2.new(0, 250, 0, 170)
	frame.Size = UDim2.new(0, 250, 0, 190)
	frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	frame.BackgroundTransparency = 0.4
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local uiList = Instance.new("UIListLayout")
	uiList.Parent = frame
	uiList.Padding = UDim.new(0, 2)

	local function mkLabel(name)
		local lbl = Instance.new("TextLabel")
		lbl.Name = name
		lbl.Size = UDim2.new(1, 0, 0, 18)
		lbl.BackgroundTransparency = 1
		lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
		lbl.Font = Enum.Font.Code
		lbl.TextSize = 14
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Text = name .. ": ..."
		lbl.Parent = frame
		return lbl
	end

	local labels = {
		modoAnimacao = mkLabel("modoAnimacao"),
		estadoMov = mkLabel("estadoMov"),
		estadoAcao = mkLabel("estadoAcao"),
		ShiftLockOn = mkLabel("ShiftLockOn"),
		AgachadoOn = mkLabel("AgachadoOn"),
		BloqueandoOn = mkLabel("BloqueandoOn"),
		ProntoAparar = mkLabel("ProntoAparar"),
		StunadoOn = mkLabel("StunadoOn"),
		CorrendoOn = mkLabel("CorrendoOn"),
	}

	return labels
end

local function getStatusFld()
	local char = player.Character
	if not char then
		return nil
	end
	return char:FindFirstChild("Status")
end

--==============================================================================
-- Update Loop
--==============================================================================

local function main()
	local labels = createLabelGui()
	local watchedKeys = {
		"modoAnimacao",
		"estadoMov",
		"estadoAcao",
		"ShiftLockOn",
		"AgachadoOn",
		"BloqueandoOn",
		"ProntoAparar",
		"StunadoOn",
		"CorrendoOn",
	}

	local last = {}

	RunService.RenderStepped:Connect(function()
		local status = getStatusFld()
		if not status then
			for k, label in pairs(labels) do
				label.Text = k .. ": [Status N/A]"
			end
			return
		end

		for _, key in ipairs(watchedKeys) do
			local valObj = status:FindFirstChild(key)
			local value
			if valObj and valObj:IsA("ValueBase") then
				value = tostring(valObj.Value)
			else
				value = "[N/A]"
			end
			if last[key] ~= value then
				labels[key].Text = key .. ": " .. value
				last[key] = value
			end
		end
	end)
end

main()
