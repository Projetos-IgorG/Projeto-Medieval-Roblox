--!strict

--[[
	Script: Acoes.luau (filho de Combate)
	Responsabilidade: Acoes de combate do NPC (equipar, desequipar, atacar,
	combo, bloquear). Delega TUDO ao pipeline canonico do CombateServidor
	(mesmo pipeline do player).

	Correcoes em relacao ao codigo antigo:
	- acaoTick estavel por swing: o historico de swings agora casa exatamente
	  com o NPC_AcaoTick replicado (hits nao dependem mais do fallback de 0.4s).
	- verificarAlvo e usado de verdade: o combo so continua se o alvo ainda
	  for valido (antes era codigo morto).
	- Guard de maquina.dados (nil-index em Mod.Atacar).
	- Bloqueio proibido durante stun/defesa quebrada.
	- Historico de swings limpo por retencao (sem crescer indefinidamente).
	- Tokens mortos (equipToken/desequipToken/ultimoSwingFim) removidos.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TiposNPC = require(ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC"):WaitForChild("Tipos"))

local Config = require(script.Parent:WaitForChild("Config"))
local Estado = require(script.Parent:WaitForChild("Estado"))
local Arma = require(script.Parent:WaitForChild("Arma"))
local Sincronia = require(script.Parent:WaitForChild("Sincronia"))

type EstadoNPC = Estado.EstadoNPC

local Acoes = {}

-- =============================================================================
-- Helpers internos.
-- =============================================================================

local function limparHistoricoAntigo(s: EstadoNPC)
	local agora = os.clock()
	for tick in s.historicoAcoes do
		if agora - tick > Config.RETENCAO_HISTORICO then
			s.historicoAcoes[tick] = nil
		end
	end
end

local function resetarCombo(s: EstadoNPC)
	s.indiceCombo = 0
	if not s.destruido then
		s.modelo:SetAttribute("NPC_AcertouCombo", false)
	end
	local cs = Estado.ObterCombateServidor()
	if cs and cs.ProcessarComboTerminou then
		pcall(cs.ProcessarComboTerminou, s.modelo)
	end
	if not s.destruido and not s.atacando and not s.equipando then
		Sincronia.DefinirAcao(s, TiposNPC.Acao.Idle, 0)
	end
end

-- =============================================================================
-- Ciclo de swing/combo.
-- =============================================================================

local iniciarSwing: (s: EstadoNPC, cs: any, token: number) -> ()

local function finalizarSwing(s: EstadoNPC, token: number)
	if s.destruido or s.comboToken ~= token then
		return
	end

	local cs = Estado.ObterCombateServidor()
	local maquina = if cs and cs.ObterMaquina then cs.ObterMaquina(s.modelo) else nil
	local dados = maquina and maquina.dados

	local continuar = false
	if dados and dados.continuarCombo then
		dados.continuarCombo = false
		-- FIX: valida o alvo antes de continuar o combo (antes, verificarAlvo
		-- nunca era chamado e o NPC continuava combo em alvo morto/longe).
		local verificar = s.verificarAlvo
		continuar = verificar == nil or verificar() == true
	end

	if continuar and s.indiceCombo < Config.INDICE_COMBO_MAX and maquina then
		s.indiceCombo += 1
		s.comboToken += 1
		local novoToken = s.comboToken
		if maquina.AvancarGolpeCombo then
			pcall(maquina.AvancarGolpeCombo, maquina, s.indiceCombo)
		end
		task.defer(function()
			if s.destruido or s.comboToken ~= novoToken then
				return
			end
			iniciarSwing(s, cs, novoToken)
		end)
		return
	end

	s.atacando = false

	-- Reseta o combo se nao houver novo ataque dentro da janela de continuacao.
	local janela = (s.timings and s.timings.Ataque.ContinuacaoCombo) or 0.8
	local indiceNoFim = s.indiceCombo
	task.delay(janela, function()
		if s.destruido or s.comboToken ~= token or s.atacando then
			return
		end
		if s.indiceCombo == indiceNoFim then
			resetarCombo(s)
		end
	end)
end

iniciarSwing = function(s: EstadoNPC, cs: any, token: number)
	if s.destruido or s.comboToken ~= token then
		return
	end

	local t = s.timings.Ataque
	-- UNICO ponto que gera NPC_AcaoTick durante ataque: o valor replicado e
	-- exatamente a chave do historico, entao o reporte do cliente sempre casa.
	local tick = Sincronia.DefinirAcao(s, TiposNPC.Acao.Ataque, s.indiceCombo)
	s.swingHitInicio = tick + t.AtrasoHit
	s.swingHitFim = tick + t.Duracao

	local tipoAtaque = if s.indiceCombo >= Config.INDICE_COMBO_MAX then "AtaqueFinal" else "Ataque"
	s.tipoAtaqueAtual = tipoAtaque
	s.historicoAcoes[tick] = {
		tipoAtaque = tipoAtaque,
		indiceCombo = s.indiceCombo,
		swingHitInicio = s.swingHitInicio,
		swingHitFim = s.swingHitFim,
		jaAtingidos = {},
	}
	limparHistoricoAntigo(s)

	-- ProcessarComboHitbox ja aplica o impulso do atacante internamente.
	if cs.ProcessarComboHitbox then
		pcall(cs.ProcessarComboHitbox, s.modelo, { indice = s.indiceCombo })
	end

	task.delay(t.Duracao, function()
		finalizarSwing(s, token)
	end)
end

-- =============================================================================
-- API publica (equivalente ao antigo ControladorCombateNPC).
-- =============================================================================

function Acoes.EquiparArma(modelo: Model)
	local s = Estado.Obter(modelo)
	if not s or s.destruido or s.armaPronta or s.equipando then
		return
	end
	local cs = Estado.ObterCombateServidor()
	if not cs then
		return
	end

	Arma.Aplicar(s) -- re-resolve arma/timings antes de equipar

	s.equipando = true
	s.desequipando = false
	Sincronia.DefinirAcao(s, TiposNPC.Acao.Equipar, 0)

	-- Delega ao pipeline do player; a conclusao chega via hook da maquina
	-- (estadoAcao volta para "Nenhuma" -> Sincronia atualiza NPC_ArmaPronta).
	local ok = pcall(cs.ProcessarEquipar, modelo, Arma.ObterModoAnimacao(modelo))
	if not ok then
		s.equipando = false
	end
end

function Acoes.DesequiparArma(modelo: Model)
	local s = Estado.Obter(modelo)
	if not s or s.destruido or not s.armaPronta or s.equipando then
		return
	end
	if s.atacando then
		Acoes.PararAtaque(modelo)
	end
	local cs = Estado.ObterCombateServidor()
	if not cs then
		return
	end

	s.equipando = true
	s.desequipando = true
	Sincronia.DefinirAcao(s, TiposNPC.Acao.Desequipar, 0)

	local ok = pcall(cs.ProcessarDesequipar, modelo)
	if not ok then
		s.equipando = false
		s.desequipando = false
		s.armaPronta = false
		Sincronia.DefinirArmaPronta(s, false)
	end
end

function Acoes.Atacar(modelo: Model, verificarAlvo: (() -> boolean)?): boolean
	local s = Estado.Obter(modelo)
	if not s or s.destruido then
		return false
	end
	local cs = Estado.ObterCombateServidor()
	if not cs then
		return false
	end
	local maquina = cs.ObterMaquina(modelo)
	if not maquina then
		return false
	end
	local dados = maquina.dados -- FIX: guard (antes indexava nil direto)

	s.verificarAlvo = verificarAlvo

	-- Ja atacando: pedido de continuacao de combo dentro da janela do swing.
	if s.atacando then
		if not dados then
			return false
		end
		dados.ultimoComboTerminou = 0
		local agora = os.clock()
		local duracao = s.timings.Ataque.Duracao
		if agora >= s.swingHitInicio - 0.05 and agora <= s.acaoTick + duracao then
			dados.continuarCombo = true
			return true
		end
		return false
	end

	if not s.armaPronta or s.equipando then
		return false
	end
	-- FIX: nunca inicia ataque stunado.
	if maquina.EstaStunado and maquina:EstaStunado() then
		return false
	end

	if dados then
		dados.ultimoComboTerminou = 0
	end
	if maquina.DefinirModo then
		maquina:DefinirModo(Arma.ObterModoAnimacao(modelo))
	end

	-- Pipeline do player: valida estado, toca animacao, aplica impulso.
	local ok, tipoAtaque = cs.ProcessarAtacarEmPe(modelo)
	if not ok then
		return false
	end

	s.indiceCombo = 1
	s.tipoAtaqueAtual = tipoAtaque
	s.atacando = true
	s.comboToken += 1
	iniciarSwing(s, cs, s.comboToken)
	return true
end

function Acoes.PararAtaque(modelo: Model)
	local s = Estado.Obter(modelo)
	if not s then
		return
	end
	s.comboToken += 1 -- invalida swings/delays pendentes
	s.atacando = false
	s.verificarAlvo = nil
	s.swingHitFim = 0
	limparHistoricoAntigo(s)
	resetarCombo(s)
end

function Acoes.Bloquear(modelo: Model): boolean
	local s = Estado.Obter(modelo)
	if not s or s.destruido then
		return false
	end
	if s.atacando or s.equipando or not s.armaPronta then
		return false
	end
	local cs = Estado.ObterCombateServidor()
	if not cs then
		return false
	end
	-- FIX: nunca bloquear durante stun/defesa quebrada.
	local maquina = if cs.ObterMaquina then cs.ObterMaquina(modelo) else nil
	if maquina and maquina.EstaStunado and maquina:EstaStunado() then
		return false
	end

	-- `true` simula ShiftLock ativo (exigido pela MaquinaDeEstados).
	local ok, _motivo = cs.ProcessarBloquear(modelo, true)
	return ok == true
end

function Acoes.PararBloqueio(modelo: Model): boolean
	local cs = Estado.ObterCombateServidor()
	if not cs then
		return false
	end
	local ok, _motivo = cs.ProcessarPararBloqueio(modelo)
	return ok == true
end

function Acoes.TocarLocomocao(modelo: Model, nome: string, velocidadeAnimacao: number?)
	local s = Estado.Obter(modelo)
	if not s or s.destruido or s.equipando then
		return
	end
	Sincronia.DefinirLocomocao(s, nome, velocidadeAnimacao)
end

-- =============================================================================
-- Consultas.
-- =============================================================================

function Acoes.EstaArmaPronta(modelo: Model): boolean
	local s = Estado.Obter(modelo)
	return s ~= nil and s.armaPronta
end

function Acoes.EstaAtacando(modelo: Model): boolean
	local s = Estado.Obter(modelo)
	return s ~= nil and s.atacando
end

function Acoes.EstaEquipando(modelo: Model): boolean
	local s = Estado.Obter(modelo)
	return s ~= nil and s.equipando
end

function Acoes.EstaBloqueando(modelo: Model): boolean
	local cs = Estado.ObterCombateServidor()
	if not cs or not cs.ObterMaquina then
		return false
	end
	local maquina = cs.ObterMaquina(modelo)
	return maquina ~= nil and maquina:EstaBloqueando() == true
end

function Acoes.ObterAlcanceArma(modelo: Model): number?
	local s = Estado.Obter(modelo)
	if not s then
		return nil
	end
	return s.alcanceArma
end

function Acoes.ObterModoAnimacao(modelo: Model): string
	return Arma.ObterModoAnimacao(modelo)
end

return Acoes
