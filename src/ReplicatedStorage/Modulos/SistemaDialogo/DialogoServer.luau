--[[
	Módulo Server para o Sistema de Diálogo.
	Gerencia as ações solicitadas pelo cliente e recompensa jogadores ou altera estados.
]]
local SistemaDialogoServer = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modulos = ReplicatedStorage:WaitForChild("Modulos")
local FolderRemotes = Modulos:WaitForChild("SistemaDialogo"):WaitForChild("DialogoRemotes")
local _GerenciadorRequisitos = require(Modulos:WaitForChild("GerenciadorRequisitos"))

local RemoteAcao = FolderRemotes:FindFirstChild("AcaoDialogo")
if not RemoteAcao then
	RemoteAcao = Instance.new("RemoteEvent")
	RemoteAcao.Name = "AcaoDialogo"
	RemoteAcao.Parent = FolderRemotes
end

-- Dicionário de funções que o Servidor pode executar quando o Diálogo pede
local AcoesRegistradas = {

	["DarTag"] = function(player, valorDaTag)
		if not valorDaTag then
			return
		end
		local tagsFolder = player:FindFirstChild("Tags")
		if not tagsFolder then
			tagsFolder = Instance.new("Folder")
			tagsFolder.Name = "Tags"
			tagsFolder.Parent = player
		end

		if not tagsFolder:GetAttribute(valorDaTag) then
			tagsFolder:SetAttribute(valorDaTag, true)
			print("[Diálogo Server]: Tag '" .. tostring(valorDaTag) .. "' concedida a", player.Name)
		end
	end,

	-- Exemplos de expansão futura:
	-- ["DarItem"] = function(player, nomeDoItem) ... end
}

function SistemaDialogoServer.Init()
	RemoteAcao.OnServerEvent:Connect(function(player, dadosAcao)
		if type(dadosAcao) ~= "table" or not dadosAcao.Acao then
			warn("[Diálogo Server]: Ação enviada pelo client não é uma tabela válida:", dadosAcao)
			return
		end

		local nomeAcao = dadosAcao.Acao
		local valorAcao = dadosAcao.Valor

		local acaoFunc = AcoesRegistradas[nomeAcao]
		if acaoFunc then
			acaoFunc(player, valorAcao)
		else
			warn("[Diálogo Server]: Ação de diálogo não registrada no Servidor:", nomeAcao)
		end
	end)
end

return SistemaDialogoServer
