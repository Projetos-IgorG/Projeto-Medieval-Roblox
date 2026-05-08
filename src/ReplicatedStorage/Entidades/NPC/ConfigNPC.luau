--!strict

--[[
    Script: ConfigNPC.luau
    Caminho: src/ReplicatedStorage/Entidades/NPC
    Responsabilidade: Constantes de configuracao do sistema de NPC (raios LOD, intervalos, limites de pool, taxas de tick).
    Uso: ModuleScript; require para ler configuracoes; nao mantem estado.
    Nao faz: Nao aplica logica.
]]

local ConfigNPC = {}

-- Raios em studs. Tudo configuravel por archetype no override abaixo.
ConfigNPC.Padrao = {
	-- Distancia para promover NPC a "Proximo" (anima full + IA full).
	RaioProximo = 40,
	-- Distancia para promover a "Medio" (pose estatica + ainda observa).
	RaioMedio = 90,
	-- Acima disso, NPC fica "Distante" (view pausada).
	-- Spawn/despawn de view (nao do model) com histerese:
	RaioAtivacao = 120,
	RaioDesativacao = 160,
	-- Periodo do scheduler central (cliente) em segundos.
	IntervaloAtualizacao = 0.1,
	-- Periodo de decisao da IA (servidor) em segundos.
	IntervaloIA = 0.25,
	-- Limite de NPCs com View ativa simultaneamente por archetype no cliente.
	-- Excedentes ficam em fila de prioridade pela distancia.
	MaxAtivosPorArchetype = 24,
	-- Re-avaliacao de NetworkOwnership.
	IntervaloOwnership = 1.0,
}

ConfigNPC.PorArchetype = {
	Dialogo = {
		MaxAtivosPorArchetype = 16,
	},
	Combate = {
		IntervaloIA = 0.15,
		MaxAtivosPorArchetype = 12,
	},
	Animal = {
		RaioProximo = 30,
		RaioMedio = 70,
		RaioAtivacao = 100,
		RaioDesativacao = 140,
		IntervaloIA = 0.5,
		MaxAtivosPorArchetype = 32,
	},
}

function ConfigNPC.Obter(archetype: string, chave: string): any
	local override = ConfigNPC.PorArchetype[archetype]
	if override and override[chave] ~= nil then
		return override[chave]
	end
	return (ConfigNPC.Padrao :: any)[chave]
end

return ConfigNPC
