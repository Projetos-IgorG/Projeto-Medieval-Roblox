--!strict

--[[
    Script: ModosAnimacao.luau
    Caminho: src/ReplicatedStorage/Jogador/Animacoes
    Responsabilidade: Define nomes e modos de animacao usados pelos controladores do jogador.
    Uso: ModuleScript; use require(caminho) para ler as tabelas e valores exportados.
    Nao faz: Nao executa comportamento sozinho; apenas fornece dados para outros scripts.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GeneralAnimations = require(script.Parent:WaitForChild("IdsAnimacoesGerais"))
local ActionModes = require(ReplicatedStorage:WaitForChild("Combate"):WaitForChild("Animacoes"):WaitForChild("IdsAnimacoesCombate"))

local ModoAnimacoes = table.clone(GeneralAnimations)

for nome, dados in pairs(ActionModes) do
	ModoAnimacoes[nome] = dados
end

return ModoAnimacoes
