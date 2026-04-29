local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modulos = ReplicatedStorage
local DialogoClient = require(Modulos:WaitForChild("Dialogo"):WaitForChild("ControladorDialogoCliente"))

-- Inicializa os listeners de ProximityPrompt da interface de diálogo no Client
DialogoClient.Init()
