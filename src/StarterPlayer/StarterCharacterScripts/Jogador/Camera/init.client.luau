--!strict
--[[
	Script: init.client.luau (Camera)
	Caminho: src/StarterPlayer/StarterCharacterScripts/Jogador/Camera
	Responsabilidade: Orquestra todos os sistemas de câmera/cabeça do personagem local:
		- Rotação da cabeça (MovimentoCabeca)
		- Inclinação do torso (InclinacaoTorso)
		- Sombra da cabeça em 1ª pessoa (SombraCabecaModulo)
	Uso: LocalScript; roda automaticamente para o jogador local.
	Não faz: Não valida autoridade do servidor, não salva dados persistentes e não substitui regras server-side.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- ── Módulos filhos ─────────────────────────────────────────────────────

local MovimentoCabeca = require(script:WaitForChild("MovimentoCabeca"))
local InclinacaoTorso = require(script:WaitForChild("InclinacaoTorso"))
local SombraCabecaModulo = require(script:WaitForChild("SombraCabecaModulo"))

-- ── Interface de tipos para o módulo InclinacaoTorso ───────────────────

export type TorsoTiltInstance = InclinacaoTorso.TorsoTiltInstance


-- ── Estado ─────────────────────────────────────────────────────────────

local player = Players.LocalPlayer

local connection: RBXScriptConnection? = nil
local currentTiltInstance: TorsoTiltInstance? = nil

-- ── Setup do personagem ────────────────────────────────────────────────

local function setup(character: Model)
	-- Limpa estado anterior
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if currentTiltInstance then
		currentTiltInstance:Destroy()
		currentTiltInstance = nil
	end

	-- ── Rotação da cabeça + inclinação do torso ──

	local root = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	local neck = character:FindFirstChild("Neck", true) :: Motor6D?
	if not root or not neck then
		return
	end

	local yOffset = neck.C0.Y
	local targetC0 = neck.C0

	local tilt: TorsoTiltInstance = InclinacaoTorso.new(character)
	tilt:Enable()
	currentTiltInstance = tilt

	connection = RunService.RenderStepped:Connect(function(_dt)
		if not root.Parent or not neck.Parent then
			if connection then
				connection:Disconnect()
				connection = nil
			end
			if currentTiltInstance == tilt then
				tilt:Destroy()
				currentTiltInstance = nil
			end
			return
		end

		targetC0 = MovimentoCabeca.AtualizarNeck(root, neck, targetC0, yOffset)
	end)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Once(function()
			if connection then
				connection:Disconnect()
				connection = nil
			end
			if currentTiltInstance == tilt then
				tilt:Destroy()
				currentTiltInstance = nil
			end
		end)
	end

	-- ── Sombra da cabeça ──

	SombraCabecaModulo.OnCharacterAdded(character)
end

-- ── Inicialização ──────────────────────────────────────────────────────

SombraCabecaModulo.Bind()

if player.Character then
	setup(player.Character)
end

-- ── Limpeza ao destruir ────────────────────────────────────────────────

script.Destroying:Connect(function()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if currentTiltInstance then
		currentTiltInstance:Destroy()
		currentTiltInstance = nil
	end
	SombraCabecaModulo.Destroy()
end)
