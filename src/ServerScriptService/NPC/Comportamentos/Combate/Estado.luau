--!strict

--[[
	Script: Estado.luau (filho de Combate)
	Responsabilidade: Estado de combate por NPC (criacao, acesso, destruicao)
	e acesso lazy ao CombateServidor.
	UNICO dono da tabela de estados. Estado.Destruir garante zero leaks:
	desconecta hooks, limpa historico e remove a maquina do CombateServidor.
]]

local ServerScriptService = game:GetService("ServerScriptService")

export type RegistroSwing = {
	tipoAtaque: string,
	indiceCombo: number,
	swingHitInicio: number,
	swingHitFim: number,
	jaAtingidos: { [Model]: boolean },
}

export type EstadoNPC = {
	modelo: Model,
	humanoide: Humanoid,
	destruido: boolean,

	-- Arma
	armaEquipada: Tool?,
	alcanceArma: number,
	dano: number,
	timings: any,
	armaPronta: boolean,

	-- Acoes
	atacando: boolean,
	equipando: boolean,
	desequipando: boolean,
	indiceCombo: number,
	comboToken: number,
	acaoTick: number,
	swingHitInicio: number,
	swingHitFim: number,
	tipoAtaqueAtual: string?,
	verificarAlvo: (() -> boolean)?,

	-- Swings recentes, chave = acaoTick replicado ao cliente.
	historicoAcoes: { [number]: RegistroSwing },

	-- Funcoes de disconnect dos hooks instalados na MaquinaDeEstados.
	desconectarHooks: { () -> () },
}

local estados: { [Model]: EstadoNPC } = {}

local Estado = {}

-- =============================================================================
-- Acesso lazy ao CombateServidor (evita ciclo de require na inicializacao).
-- Cacheado: o hot path nunca repete FindFirstChild/require.
-- =============================================================================

local combateServidor: any = nil

function Estado.ObterCombateServidor(): any?
	if combateServidor then
		return combateServidor
	end
	local pasta = ServerScriptService:FindFirstChild("Combate")
	local servidor = pasta and pasta:FindFirstChild("Servidor")
	local mod = servidor and servidor:FindFirstChild("CombateServidor")
	if mod and mod:IsA("ModuleScript") then
		local ok, m = pcall(require, mod)
		if ok then
			combateServidor = m
			return m
		end
	end
	return nil
end

-- =============================================================================
-- CRUD do estado.
-- =============================================================================

function Estado.Obter(modelo: Model): EstadoNPC?
	return estados[modelo]
end

function Estado.ObterOuCriar(modelo: Model, humanoide: Humanoid): EstadoNPC
	local existente = estados[modelo]
	if existente then
		return existente
	end
	local s: EstadoNPC = {
		modelo = modelo,
		humanoide = humanoide,
		destruido = false,

		armaEquipada = nil,
		alcanceArma = 4,
		dano = 4,
		timings = nil,
		armaPronta = false,

		atacando = false,
		equipando = false,
		desequipando = false,
		indiceCombo = 0,
		comboToken = 0,
		acaoTick = 0,
		swingHitInicio = 0,
		swingHitFim = 0,
		tipoAtaqueAtual = nil,
		verificarAlvo = nil,

		historicoAcoes = {},
		desconectarHooks = {},
	}
	estados[modelo] = s
	return s
end

function Estado.Destruir(modelo: Model)
	local s = estados[modelo]
	if not s then
		return
	end
	s.destruido = true
	s.comboToken += 1 -- invalida qualquer task.delay/defer pendente
	s.atacando = false
	s.equipando = false
	s.desequipando = false
	s.armaPronta = false
	s.armaEquipada = nil
	s.verificarAlvo = nil
	table.clear(s.historicoAcoes)

	for _, desconectar in s.desconectarHooks do
		pcall(desconectar)
	end
	table.clear(s.desconectarHooks)

	-- Remove a maquina de estados cacheada no servidor.
	local cs = Estado.ObterCombateServidor()
	if cs and cs.RemoverMaquina then
		pcall(cs.RemoverMaquina, modelo)
	end

	estados[modelo] = nil
end

return Estado
