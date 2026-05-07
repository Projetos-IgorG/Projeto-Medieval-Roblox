--[[
    Script: InicializarEntidades.server.luau
    Caminho: src/ServerScriptService/Entidades
    Responsabilidade: Cria e destroi a entidade "Humano" para cada Player ao spawnar/respawnar e sincroniza com o Humanoid.
    Uso: Script de servidor; roda automaticamente em ServerScriptService/Entidades.
	Nao faz: Nao define visual/aparencia nem persistencia; apenas registra a entidade do jogador.
    Funcoes principais: configurarPersonagem, desconectarPersonagem, configurarPlayer
]]

local Players = game:GetService("Players")

local Gerenciador = require(script.Parent:WaitForChild("GerenciadorEntidades"))

local ESPECIE_PADRAO_PLAYER = "Humano"

-- Mantemos as conexoes por personagem para liberar quando o character for trocado.
local conexoesPersonagem: { [Model]: { RBXScriptConnection } } = {}

local function limparConexoes(character: Model)
	local conns = conexoesPersonagem[character]
	if not conns then
		return
	end
	for _, c in conns do
		if c.Connected then
			c:Disconnect()
		end
	end
	conexoesPersonagem[character] = nil
end

local function configurarPersonagem(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not humanoid then
		humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	end

	local entidade = Gerenciador.Registrar(character, ESPECIE_PADRAO_PLAYER)

	-- Sincroniza Vida com Humanoid.Health (Humanoid continua sendo a fonte para combate),
	-- mas a entidade reflete o valor para a UI.
	if humanoid then
		-- Inicializa
		entidade:definirAtributo("Vida", humanoid.Health)

		local conns = {} :: { RBXScriptConnection }
		conexoesPersonagem[character] = conns

		table.insert(conns, humanoid.HealthChanged:Connect(function(saude)
			entidade:definirAtributo("Vida", saude)
		end))

		table.insert(conns, humanoid.Died:Connect(function()
			entidade:definirAtributo("Vida", 0)
		end))

		-- Se o character sair do jogo (ex: respawn), limpamos.
		table.insert(conns, character.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				limparConexoes(character)
				Gerenciador.Desregistrar(character)
			end
		end))
	end

	local _ = player -- reservado para uso futuro (autoridade, persistencia)
end

local function configurarPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		configurarPersonagem(player, character)
	end)
	player.CharacterRemoving:Connect(function(character)
		limparConexoes(character)
		Gerenciador.Desregistrar(character)
	end)
	if player.Character then
		configurarPersonagem(player, player.Character)
	end
end

Players.PlayerAdded:Connect(configurarPlayer)
Players.PlayerRemoving:Connect(function(player)
	if player.Character then
		limparConexoes(player.Character)
		Gerenciador.Desregistrar(player.Character)
	end
end)
for _, player in Players:GetPlayers() do
	configurarPlayer(player)
end
