--[[
    Script: InicializarDialogo.server.luau
    Caminho: src/ServerScriptService/Dialogo
    Responsabilidade: Inicializa remotes, modulos e conexoes principais do sistema de dialogo.
    Uso: Script de servidor; roda automaticamente em src/ServerScriptService/Dialogo quando a instancia existe no jogo.
    Nao faz: Nao controla UI local nem le inputs diretamente; recebe sinais ja autorizados pelo fluxo do jogo.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modulos = ReplicatedStorage
local DialogoServer = require(Modulos:WaitForChild("Dialogo"):WaitForChild("DialogoServidor"))

DialogoServer.Init()
