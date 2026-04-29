--[[
    Script: DialogoServidor.luau
    Caminho: src/ReplicatedStorage/Dialogo
    Responsabilidade: Registra acoes de dialogo no servidor e executa respostas autorizadas.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao roda sozinho nem cria fluxo de jogo por conta propria; depende dos scripts que importam este modulo.
    Funcoes principais: Init
]]
local SistemaDialogoServer = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SistemaDialogoFolder = ReplicatedStorage:WaitForChild("Dialogo")
local FolderRemotes = SistemaDialogoFolder:WaitForChild("DialogoRemotes")
local _GerenciadorRequisitos = require(SistemaDialogoFolder:WaitForChild("Requisitos"):WaitForChild("RequisitosDialogo"))

local RemoteAcao = FolderRemotes:FindFirstChild("AcaoDialogo")
if not RemoteAcao then
	RemoteAcao = Instance.new("RemoteEvent")
	RemoteAcao.Name = "AcaoDialogo"
	RemoteAcao.Parent = FolderRemotes
end

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
