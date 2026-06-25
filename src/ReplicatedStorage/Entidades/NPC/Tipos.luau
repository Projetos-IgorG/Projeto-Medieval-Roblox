--!strict

--[[
    Script: Tipos.luau
    Caminho: src/ReplicatedStorage/Entidades/NPC
    Responsabilidade: Define tipos compartilhados (archetypes, estados, intencoes, opcoes de spawn) usados por servidor e cliente.
    Uso: ModuleScript; require para tipar APIs do sistema de NPC.
    Nao faz: Nao mantem estado nem instancia nada; apenas define tipos e constantes.
]]

local TiposNPC = {}

-- Archetypes suportados na v1. Adicionar novo nao exige mudar nucleo:
-- basta criar um Comportamento (servidor) e uma View (cliente) com o mesmo id.
TiposNPC.Archetype = {
	Dialogo = "Dialogo",
	Combate = "Combate",
	Animal = "Animal",
}

-- Estados de alto nivel replicados via Attribute "NPC_Estado".
-- Tudo que a View precisa saber para escolher animacao/efeito.
TiposNPC.Estado = {
	Idle = "Idle",
	Andando = "Andando",
	Correndo = "Correndo",
	Atacando = "Atacando",
	Defendendo = "Defendendo",
	Aparando = "Aparando",
	Aparado = "Aparado",
	DefesaQuebrada = "DefesaQuebrada",
	Fugindo = "Fugindo",
	Pastando = "Pastando",
	Stunado = "Stunado",
	Morto = "Morto",
}

-- Niveis de LOD comportamental (cliente).
-- Far  = oculto/pausado (0 trabalho)
-- Med  = pose estatica + interpolacao basica
-- Near = animacao completa + comportamento total
TiposNPC.LOD = {
	Distante = "Distante",
	Medio = "Medio",
	Proximo = "Proximo",
}

export type Archetype = string
export type Estado = string
export type LOD = string

-- Opcoes aceitas por GerenciadorNPC.SpawnNPC.
-- Todas opcionais menos archetype e cframe.
export type OpcoesSpawn = {
	archetype: Archetype,
	cframe: CFrame,
	-- Para archetype "Animal": id da especie no catalogo de Especies (Galinha/Ovelha/Vaca).
	especie: string?,
	-- Para archetype "Combate"/"Dialogo": Player cuja aparencia deve ser clonada.
	-- Se nil, usa fallback (R6 base).
	aparenciaDe: Player?,
	-- Nome customizado exibido sobre o NPC; default = archetype/especie.
	nome: string?,
	-- Hostil = pode atacar players. So usado por archetype "Combate".
	hostil: boolean?,
	-- Capacidades opcionais (default: andar=true, atacar=true, defender=false, parry=false).
	podeAndar: boolean?,
	podeAtacar: boolean?,
	podeDefender: boolean?,
	podeParry: boolean?,
}

-- Snapshot devolvido por consultas (nunca a referencia interna).
export type RegistroNPC = {
	id: number,
	archetype: Archetype,
	especie: string?,
	modelo: Model,
}

-- Chaves de Attribute padronizadas (evita strings magicas espalhadas).
TiposNPC.Chaves = {
	Id = "NPC_Id",
	Archetype = "NPC_Archetype",
	Estado = "NPC_Estado",
	Hostil = "NPC_Hostil",
	-- Id (numerico) do alvo atual quando aplicavel; 0 = sem alvo.
	-- Usamos UserId para players e -id para NPCs.
	AlvoRef = "NPC_AlvoRef",
	-- Capacidades (lidas pelos comportamentos).
	PodeAndar = "NPC_PodeAndar",
	PodeAtacar = "NPC_PodeAtacar",
	PodeDefender = "NPC_PodeDefender",
	PodeParry = "NPC_PodeParry",
	-- True quando o NPC esta em postura de combate ("arma equipada" = modo Punhos).
	ModoCombate = "NPC_ModoCombate",
	-- Visual / replicacao client-fat. Servidor NAO toca animacoes; apenas seta
	-- estes attributes e a View no cliente reage tocando as anims localmente.
	-- Acao = qual anim de combate o NPC esta executando agora (Idle/Ataque/Equipar/Desequipar).
	Acao = "NPC_Acao",
	-- Indice do combo atual (1..4) para Ataque. Usado para escolher variante visual.
	AcaoIndice = "NPC_AcaoIndice",
	-- Timestamp (os.clock no servidor) toda vez que Acao/Indice mudam. Permite ao
	-- cliente detectar "mesmo Acao = Ataque, mas eh um novo swing".
	AcaoTick = "NPC_AcaoTick",
	-- Nome da locomocao atual (Idle/Andando/Correndo/...). View aplica fade entre tracks.
	LocomocaoNome = "NPC_LocomocaoNome",
	-- Velocidade da animacao de locomocao (negativa = andar de costas).
	LocomocaoVelocidade = "NPC_LocomocaoVelocidade",
	-- True quando arma esta visualmente nas maos (apos terminar Equipar).
	ArmaPronta = "NPC_ArmaPronta",
	-- Id da arma equipada (string) - cliente clona o WeaponModel local com base nisso.
	ArmaEquipadaId = "NPC_ArmaEquipadaId",
}

-- Acoes de combate replicadas via NPC_Acao. View no cliente escolhe a animacao.
TiposNPC.Acao = {
	Idle = "Idle",
	Ataque = "Ataque",
	Equipar = "Equipar",
	Desequipar = "Desequipar",
}

return TiposNPC
