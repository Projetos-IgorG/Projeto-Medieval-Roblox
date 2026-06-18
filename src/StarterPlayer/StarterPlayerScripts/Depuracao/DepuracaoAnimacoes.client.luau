--[[
    Script: DepuracaoAnimacoes.client.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/Depuracao
    Responsabilidade: Exibe ferramentas locais para depurar animacoes do jogador.
    Uso: LocalScript; roda automaticamente para o jogador local em src/StarterPlayer/StarterPlayerScripts/Depuracao.
    Nao faz: Nao valida autoridade do servidor, nao salva dados persistentes e nao substitui regras server-side.
    Funcoes principais: createLabelGui, mkLabel, getStatusFolders, main
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local function createLabelGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = "DebugAnimationUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.AnchorPoint = Vector2.new(0, 0)
	frame.Position = UDim2.fromOffset(5, 100)
	frame.Size = UDim2.fromOffset(250, 230)
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
		RollOn = mkLabel("RollOn"),
		DashOn = mkLabel("DashOn"),
	}

	return labels
end

local CLIENT_SIDE_ATTRS = {
	modoAnimacao = true,
	estadoMov = true,
	ShiftLockOn = true,
	AgachadoOn = true,
	CorrendoOn = true,
}

local SERVER_SIDE_ATTRS = {
	estadoAcao = true,
	BloqueandoOn = true,
	ProntoAparar = true,
	StunadoOn = true,
	RollOn = true,
	DashOn = true,
}

local function getStatusFolders()
	local char = player.Character
	if not char then
		return nil, nil
	end
	return char:FindFirstChild("StatusLocal"), char:FindFirstChild("Status")
end

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
		"RollOn",
		"DashOn",
	}

	local last = {}

	RunService.RenderStepped:Connect(function()
		local statusLocal, status = getStatusFolders()

		for _, key in ipairs(watchedKeys) do
			local valObj = nil
			local source = ""

			if CLIENT_SIDE_ATTRS[key] then
				if statusLocal then
					valObj = statusLocal:FindFirstChild(key)
					source = "L"
				end
			else
				if status then
					valObj = status:FindFirstChild(key)
					source = "S"
				end
			end

			local value
			if valObj and valObj:IsA("ValueBase") then
				value = tostring(valObj.Value)
			elseif CLIENT_SIDE_ATTRS[key] and not statusLocal then
				value = "[StatusLocal N/A]"
			elseif SERVER_SIDE_ATTRS[key] and not status then
				value = "[Status N/A]"
			else
				value = "[N/A]"
			end

			if last[key] ~= value then
				labels[key].Text = key .. "(" .. source .. "): " .. value
				last[key] = value
			end
		end
	end)
end

main()
