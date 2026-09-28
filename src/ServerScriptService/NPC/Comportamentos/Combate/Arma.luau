--!strict

--[[
	Script: Arma.luau (filho de Combate)
	Responsabilidade: Resolver a arma do NPC e aplicar alcance/dano/timings
	no estado. Ordem de resolucao:
	  1) Tool fisica no modelo (com Id valido no CatalogoItens)
	  2) Atributo NPC_ArmaEquipadaId
	  3) Punhos (fallback)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CatalogoItens =
	require(ReplicatedStorage:WaitForChild("Dados"):WaitForChild("Itens"):WaitForChild("CatalogoItens"))
local Timings =
	require(ReplicatedStorage:WaitForChild("Combate"):WaitForChild("Configuracoes"):WaitForChild("TimingsAtaqueNPC"))
local TiposNPC = require(ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC"):WaitForChild("Tipos"))

local Config = require(script.Parent:WaitForChild("Config"))
local Estado = require(script.Parent:WaitForChild("Estado"))

type EstadoNPC = Estado.EstadoNPC

local Arma = {}

local function dadosDaTool(tool: Tool): any?
	local id = tool:GetAttribute("Id")
	if typeof(id) ~= "string" then
		return nil
	end
	return CatalogoItens.Get(id)
end

local function ehArma(inst: Instance): boolean
	if not inst:IsA("Tool") then
		return false
	end
	local dados = dadosDaTool(inst)
	if dados then
		return dados.Tipo == "Tool" and dados.Subtipo == "Arma"
	end
	return inst:GetAttribute("Tipo") == "Armas"
end

local function encontrarToolArma(modelo: Model): Tool?
	for _, child in modelo:GetChildren() do
		if ehArma(child) then
			return child :: Tool
		end
	end
	return nil
end

-- Retorna (dadosDoCatalogo, toolFisica?).
function Arma.ObterDados(modelo: Model): (any, Tool?)
	local tool = encontrarToolArma(modelo)
	if tool then
		local dados = dadosDaTool(tool)
		if dados then
			return dados, tool
		end
	end
	local idArma = modelo:GetAttribute(TiposNPC.Chaves.ArmaEquipadaId)
	if typeof(idArma) == "string" and idArma ~= "" then
		local dados = CatalogoItens.Get(idArma)
		if dados then
			return dados, nil
		end
	end
	return Config.DADOS_PUNHOS, nil
end

-- Aplica os dados da arma atual no estado (alcance, dano, timings).
function Arma.Aplicar(s: EstadoNPC)
	local dados, tool = Arma.ObterDados(s.modelo)
	s.armaEquipada = tool
	s.alcanceArma = (dados.Alcance :: number?) or Config.DADOS_PUNHOS.Alcance
	s.dano = (dados.Dano :: number?) or (dados.StatBase :: number?) or Config.DADOS_PUNHOS.Dano
	s.timings = Timings.ObterPorArma(dados.ModoAnimacao or "Punhos") or Timings.Punhos
end

function Arma.ObterModoAnimacao(modelo: Model): string
	local dados = Arma.ObterDados(modelo)
	return (dados.ModoAnimacao :: string?) or "Punhos"
end

return Arma
