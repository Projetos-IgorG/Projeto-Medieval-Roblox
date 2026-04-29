--!strict

-- Animations.Modes: une os modos gerais com os modos de ação numa única tabela.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GeneralAnimations = require(script.Parent:WaitForChild("IdsAnimacoesGerais"))
local ActionModes = require(ReplicatedStorage:WaitForChild("Combate"):WaitForChild("Animacoes"):WaitForChild("IdsAnimacoesCombate"))

local ModoAnimacoes = table.clone(GeneralAnimations)

for nome, dados in pairs(ActionModes) do
	ModoAnimacoes[nome] = dados
end

return ModoAnimacoes
