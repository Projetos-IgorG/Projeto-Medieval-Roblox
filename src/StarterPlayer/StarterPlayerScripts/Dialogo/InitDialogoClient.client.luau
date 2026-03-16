local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modulos = ReplicatedStorage:WaitForChild("Modulos")
local DialogoClient = require(Modulos:WaitForChild("SistemaDialogo"):WaitForChild("DialogoClient"))

-- Inicializa os listeners de ProximityPrompt da interface de diálogo no Client
DialogoClient.Init()
