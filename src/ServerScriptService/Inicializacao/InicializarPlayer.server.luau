--[[
	Script: InicializarPlayer.server.luau
	Caminho: src/ServerScriptService/Inicializacao
	Responsabilidade: Configura cada jogador ao entrar e a cada respawn (limpa acessorios nao-cabelo, normaliza WalkSpeed e unifica o rosto).
	Uso: Script de servidor; roda automaticamente em ServerScriptService/Inicializacao.
	Nao faz: Nao gerencia UI, inputs ou estado de combate; foca apenas em ajustes pos-spawn de aparencia/movimento.
	Funcoes principais: RemoverAcessoriosNaoHair, AjustarVelocidadePadrao, UnificarRosto, ConfigurarPersonagem, ConfigurarJogador
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UnificacaoFacial = require(
	ReplicatedStorage:WaitForChild("Jogador")
		:WaitForChild("Aparencia")
		:WaitForChild("UnificacaoFacial")
)
local ConfigCombate = require(
	ReplicatedStorage:WaitForChild("Combate")
		:WaitForChild("Configuracoes")
		:WaitForChild("ConfigCombate")
)

local USAR_HEAD_PADRAO = false

local function RemoverAcessoriosNaoHair(character : Model)
	for _, child in ipairs(character:GetChildren()) do
		if child.ClassName == "Accessory" then
			local handle = (child :: Accessory):FindFirstChild("Handle")
			if handle and not handle:FindFirstChild("HairAttachment") then
				child:Destroy()
			end
		end
	end
end

local function AjustarVelocidadePadrao(humanoid : Humanoid)
	local velocidade = ConfigCombate.ObterConfiguracao("VelocidadeAndando") or 14
	humanoid.WalkSpeed = velocidade
end

local function UnificarRosto(humanoid : Humanoid)
	local ok, resultadoOuErro = pcall(function()
		return UnificacaoFacial:ConvertAnimatedHead(humanoid, USAR_HEAD_PADRAO)
	end)
	if not ok then
		warn("[UnificacaoFacial] Falha ao unificar rosto:", resultadoOuErro)
	end
end

local function ConfigurarPersonagem(character : Model)
	if not character then
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end

	RemoverAcessoriosNaoHair(character)
	AjustarVelocidadePadrao(humanoid)
	UnificarRosto(humanoid)
end

local function ConfigurarJogador(player : Player)
	player.CharacterAppearanceLoaded:Connect(ConfigurarPersonagem)
	if player.Character then
		ConfigurarPersonagem(player.Character)
	end
end

Players.PlayerAdded:Connect(ConfigurarJogador)
for _, player in ipairs(Players:GetPlayers()) do
	ConfigurarJogador(player)
end
