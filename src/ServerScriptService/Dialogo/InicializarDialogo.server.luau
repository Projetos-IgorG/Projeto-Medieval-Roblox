local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modulos = ReplicatedStorage
local DialogoServer = require(Modulos:WaitForChild("Dialogo"):WaitForChild("DialogoServidor"))

-- Inicia ouvintes de Remotes de Diálogo
DialogoServer.Init()
