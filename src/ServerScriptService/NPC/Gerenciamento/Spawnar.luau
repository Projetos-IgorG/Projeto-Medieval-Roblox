--!strict

--[[
	Script: Spawnar.luau
	Caminho: src/ServerScriptService/NPC/Gerenciamento
	Responsabilidade: Wrapper de compatibilidade para spawnar NPC usando o novo GerenciadorNPC.

	Correcoes em relacao ao codigo antigo:
	- armaId vai DENTRO das opcoes do GerenciadorNPC (o atributo
	  NPC_ArmaEquipadaId e setado ANTES do comportamento de Combate iniciar).
	- archetype explicito do chamador e respeitado (antes era descartado e o
	  archetype era adivinhado por templateId/iaId/hostil, com default
	  "Dialogo" -> NPC de combate nascia como Dialogo e nunca equipava).
	- podeAndar/podeAtacar/podeDefender/podeParry sao repassados (antes eram
	  hardcoded como true).
	- registrarEntidade e repassado (antes era ignorado).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TiposNPC = require(ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC"):WaitForChild("Tipos"))
local GerenciadorNPC =
	require(ServerScriptService:WaitForChild("NPC"):WaitForChild("Gerenciamento"):WaitForChild("GerenciadorNPC"))

local Spawnar = {}

export type OpcoesSpawn = {
	-- FIX: archetype explicito. O painel de dev manda "Combate"/"Dialogo"/"Animal"
	-- e o campo era simplesmente descartado; o archetype era readivinhado a
	-- partir de templateId/iaId/hostil, com default "Dialogo".
	archetype: string?,
	templateId: string?,
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
	-- FIX: capacidades vindas do chamador. Antes eram hardcoded como true e as
	-- flags do painel de dev eram jogadas fora.
	podeAndar: boolean?,
	podeAtacar: boolean?,
	podeDefender: boolean?,
	podeParry: boolean?,
}

local ARCHETYPES_VALIDOS: { [string]: boolean } = {
	Combate = true,
	Dialogo = true,
	Animal = true,
}

local function spawnarComArchetype(opts: OpcoesSpawn, archetype: string, especie: string?): (Model?, string?)
	if archetype == "Animal" and (especie == nil or especie == "") then
		especie = "Galinha"
	end
	local aparenciaDe = if opts.templateId == "__Player__" then opts.playerOrigem else nil

	local opcoes: TiposNPC.OpcoesSpawn = {
		archetype = archetype,
		cframe = opts.cframe,
		especie = especie,
		aparenciaDe = aparenciaDe,
		nome = opts.nomeFinal,
		hostil = opts.hostil == true,
		-- FIX: repassa as capacidades recebidas (default true) em vez de hardcodar.
		podeAndar = opts.podeAndar ~= false,
		podeAtacar = opts.podeAtacar ~= false,
		podeDefender = opts.podeDefender ~= false,
		podeParry = opts.podeParry ~= false,
		registrarEntidade = opts.registrarEntidade,
		armaId = if opts.armaId and opts.armaId ~= "" then opts.armaId else nil,
		tempoDespawnMorte = opts.tempoDespawnMorte,
	}

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

function Spawnar.SpawnarNPC(opts: OpcoesSpawn): (Model?, string?)
	-- Archetype explicito vence a inferencia.
	if opts.archetype and ARCHETYPES_VALIDOS[opts.archetype] then
		return spawnarComArchetype(opts, opts.archetype, opts.especie)
	end

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

	return spawnarComArchetype(opts, archetype, especie)
end

return Spawnar