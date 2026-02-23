local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modulos = ReplicatedStorage:WaitForChild("Modulos")
local DialogoServer = require(Modulos:WaitForChild("SistemaDialogo"):WaitForChild("DialogoServer"))

-- Inicia ouvintes de Remotes de Diálogo
DialogoServer.Init()
