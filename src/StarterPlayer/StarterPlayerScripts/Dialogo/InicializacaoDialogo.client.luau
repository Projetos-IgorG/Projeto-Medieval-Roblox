--[[
    Script: InicializacaoDialogo.client.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/Dialogo
    Responsabilidade: Inicializa o sistema de dialogo no cliente e conecta UI, remotes e voz.
    Uso: LocalScript; roda automaticamente para o jogador local em src/StarterPlayer/StarterPlayerScripts/Dialogo.
    Nao faz: Nao valida autoridade do servidor, nao salva dados persistentes e nao substitui regras server-side.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modulos = ReplicatedStorage
local DialogoClient = require(Modulos:WaitForChild("Dialogo"):WaitForChild("ControladorDialogoCliente"))

DialogoClient.Init()
