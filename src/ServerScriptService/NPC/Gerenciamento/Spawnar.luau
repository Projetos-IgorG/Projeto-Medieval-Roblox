--!strict

--[[
	Script: Spawnar.luau
	Caminho: src/ServerScriptService/NPC/Gerenciamento
	Responsabilidade: Wrapper de compatibilidade para spawnar NPC usando o novo GerenciadorNPC.

	Correcao em relacao ao codigo antigo:
	- armaId agora vai DENTRO das opcoes do GerenciadorNPC (o atributo
	  NPC_ArmaEquipadaId e setado ANTES do comportamento de Combate iniciar,
	  eliminando a corrida em que o NPC resolvia "punhos" e so depois recebia
	  a arma).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TiposNPC = require(ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC"):WaitForChild("Tipos"))
local GerenciadorNPC =
	require(ServerScriptService:WaitForChild("NPC"):WaitForChild("Gerenciamento"):WaitForChild("GerenciadorNPC"))

local Spawnar = {}

export type OpcoesSpawn = {
	templateId: string,
	nomeFinal: string?,
	cframe: CFrame,
	especie: string?,
	registrarEntidade: boolean?,
	iaId: string?,
	hostil: boolean?,
	playerOrigem: Player?,
	armaTipo: string?, -- ex: "Armas"
	armaId: string?, -- ex: "espada_ferro"
	tempoDespawnMorte: number?, -- segundos ate despawnar apos a morte (padrao 60)
}

function Spawnar.SpawnarNPC(opts: OpcoesSpawn): (Model?, string?)
	local archetype = "Dialogo"
	local templateLower = string.lower(opts.templateId or "")
	local iaLower = string.lower(opts.iaId or "")
	local especie = opts.especie

	if templateLower == "galinha" or templateLower == "ovelha" or templateLower == "vaca" then
		archetype = "Animal"
		especie = opts.templateId
	elseif iaLower == "animal" then
		archetype = "Animal"
		especie = especie or "Galinha"
	elseif iaLower == "combate" or opts.hostil == true then
		archetype = "Combate"
	elseif iaLower == "dialogo" then
		archetype = "Dialogo"
	end

	local especieLower = string.lower(especie or "")
	if especieLower == "galinha" or especieLower == "ovelha" or especieLower == "vaca" then
		archetype = "Animal"
	end

	local aparenciaDe = if opts.templateId == "__Player__" then opts.playerOrigem else nil

	local opcoes: TiposNPC.OpcoesSpawn = {
		archetype = archetype,
		cframe = opts.cframe,
		especie = especie,
		aparenciaDe = aparenciaDe,
		nome = opts.nomeFinal,
		hostil = opts.hostil == true,
		podeAndar = true,
		podeAtacar = true,
		podeDefender = true,
		podeParry = true,
	}

	-- FIX: arma e tempo de despawn entram nas opcoes (setados antes do iniciar).
	(opcoes :: any).armaId = if opts.armaId and opts.armaId ~= "" then opts.armaId else nil
	(opcoes :: any).tempoDespawnMorte = opts.tempoDespawnMorte

	local registro = GerenciadorNPC.SpawnNPC(opcoes)
	if registro and registro.modelo then
		local modelo = registro.modelo
		if opts.armaId and opts.armaId ~= "" and opts.armaTipo then
			modelo:SetAttribute("NPC_ArmaTipo", opts.armaTipo)
		end
		return modelo, nil
	end

	return nil, "Falha ao spawnar NPC com GerenciadorNPC"
end

return Spawnar
