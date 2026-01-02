--[[
    MaquinaDeEstados.luau
    
    Máquina de Estados compartilhada para Player e NPC.
    Gerencia transições de estado com validação de condições.
    
    Estados de Movimento (estadoMov):
    - Parado, Andando, Correndo, Pulando, Caindo, Escalando, Nadando, Agachado
    
    Estados de Ação (estadoAcao):
    - Nenhuma, AtacandoLeve, CarregandoPesado, AtaquePesado, Defendendo,
      DefesaQuebrada, Aparando, Aparado, Stunado, Equipando, Desequipando, Morto
    
    Funções seguem o padrão "Tente[Ação]" retornando sucesso/falha.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MaquinaDeEstados = {}
MaquinaDeEstados.__index = MaquinaDeEstados

-- ═══════════════════════════════════════════════════════════════════
-- ENUMS DE ESTADO
-- ═══════════════════════════════════════════════════════════════════

MaquinaDeEstados.EstadoMov = {
	Parado = "Parado",
	Andando = "Andando",
	Correndo = "Correndo",
	Pulando = "Pulando",
	Caindo = "Caindo",
	Escalando = "Escalando",
	Nadando = "Nadando",
	Agachado = "Agachado",
}

MaquinaDeEstados.EstadoAcao = {
	Nenhuma = "Nenhuma",
	AtacandoLeve = "AtacandoLeve",
	CarregandoPesado = "CarregandoPesado",
	AtaquePesado = "AtaquePesado",
	Defendendo = "Defendendo",
	DefesaQuebrada = "DefesaQuebrada",
	Aparando = "Aparando",
	Aparado = "Aparado",
	Stunado = "Stunado",
	Equipando = "Equipando",
	Desequipando = "Desequipando",
	Morto = "Morto",
}

-- Estados que bloqueiam ações
local ESTADOS_BLOQUEANTES = {
	[MaquinaDeEstados.EstadoAcao.Stunado] = true,
	[MaquinaDeEstados.EstadoAcao.Aparado] = true,
	[MaquinaDeEstados.EstadoAcao.Morto] = true,
	[MaquinaDeEstados.EstadoAcao.Equipando] = true,
	[MaquinaDeEstados.EstadoAcao.Desequipando] = true,
}

-- Estados que permitem cancelar para ataque (riposte)
local ESTADOS_PERMITE_RIPOSTE = {
	[MaquinaDeEstados.EstadoAcao.Aparando] = true,
}

-- Estados que permitem iniciar bloqueio
local ESTADOS_PERMITE_BLOQUEIO = {
	[MaquinaDeEstados.EstadoAcao.Nenhuma] = true,
}

-- Estados de movimento que permitem ataque
local MOVIMENTO_PERMITE_ATAQUE = {
	[MaquinaDeEstados.EstadoMov.Parado] = true,
	[MaquinaDeEstados.EstadoMov.Andando] = true,
	[MaquinaDeEstados.EstadoMov.Correndo] = true,
	[MaquinaDeEstados.EstadoMov.Agachado] = true,
	[MaquinaDeEstados.EstadoMov.Pulando] = true, -- Permite atacar no ar
	[MaquinaDeEstados.EstadoMov.Caindo] = true, -- Permite atacar no ar
}

-- ═══════════════════════════════════════════════════════════════════
-- CONSTRUTOR
-- ═══════════════════════════════════════════════════════════════════

export type DadosEstado = {
	estadoMov: string,
	estadoAcao: string,
	modoAnimacao: string,
	agachado: boolean,
	bloqueando: boolean,
	prontoParaAparar: boolean,
	stunado: boolean,
	shiftLock: boolean,
	correndo: boolean,
	indiceCombo: number,
	ultimoAtaque: number,
	ultimoParry: number,
	-- Novos campos para sistema de combo por marcadores
	janelaComboAtiva: boolean, -- Se está na janela de input do combo
	continuarCombo: boolean, -- Se o player clicou M1 durante a janela
}

--- Cria nova instância da máquina de estados
---@param entidade Model Character ou NPC
---@return table
function MaquinaDeEstados.Novo(entidade: Model)
	local self = setmetatable({}, MaquinaDeEstados)

	self.entidade = entidade
	self.humanoid = entidade:FindFirstChildOfClass("Humanoid")

	-- Estado atual
	self.dados = {
		estadoMov = MaquinaDeEstados.EstadoMov.Parado,
		estadoAcao = MaquinaDeEstados.EstadoAcao.Nenhuma,
		modoAnimacao = "Base",
		agachado = false,
		bloqueando = false,
		prontoParaAparar = false,
		stunado = false,
		shiftLock = false,
		correndo = false,
		indiceCombo = 0,
		ultimoAtaque = 0,
		ultimoParry = 0,
		parryToken = 0,
		-- Sistema de combo por marcadores
		janelaComboAtiva = false,
		continuarCombo = false,
	} :: DadosEstado

	-- Callbacks para notificar mudanças
	self.callbacks = {
		aoMudarEstadoMov = nil,
		aoMudarEstadoAcao = nil,
		aoMudarModo = nil,
	}

	return self
end

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES INTERNAS
-- ═══════════════════════════════════════════════════════════════════

--- Verifica se está em estado bloqueante
function MaquinaDeEstados:_EstaBloqueado(): boolean
	return ESTADOS_BLOQUEANTES[self.dados.estadoAcao] == true
end

--- Verifica se pode atacar baseado no movimento
function MaquinaDeEstados:_MovimentoPermiteAtaque(): boolean
	return MOVIMENTO_PERMITE_ATAQUE[self.dados.estadoMov] == true
end

--- Para de correr e muda para andando (se estava correndo no chão)
--- Usado ao iniciar ações de combate
function MaquinaDeEstados:_PararCorrida()
	if self.dados.correndo then
		self.dados.correndo = false
	end

	-- Se está correndo no chão, muda para andando ou parado
	if self.dados.estadoMov == MaquinaDeEstados.EstadoMov.Correndo then
		-- Verifica se o humanoid está se movendo
		if self.humanoid and self.humanoid.MoveDirection.Magnitude > 0.1 then
			self:_AlterarEstadoMov(MaquinaDeEstados.EstadoMov.Andando)
		else
			self:_AlterarEstadoMov(MaquinaDeEstados.EstadoMov.Parado)
		end
	end
end

--- Altera estado de movimento e notifica
function MaquinaDeEstados:_AlterarEstadoMov(novoEstado: string)
	if self.dados.estadoMov == novoEstado then
		return
	end

	local estadoAnterior = self.dados.estadoMov
	self.dados.estadoMov = novoEstado

	-- Debug log
	print(string.format("[MaquinaDeEstados] %s: estadoMov %s -> %s", self.entidade.Name, estadoAnterior, novoEstado))

	if self.callbacks.aoMudarEstadoMov then
		self.callbacks.aoMudarEstadoMov(novoEstado, estadoAnterior)
	end
end

--- Altera estado de ação e notifica
function MaquinaDeEstados:_AlterarEstadoAcao(novoEstado: string)
	if self.dados.estadoAcao == novoEstado then
		return
	end

	local estadoAnterior = self.dados.estadoAcao
	self.dados.estadoAcao = novoEstado

	-- Debug log
	print(string.format("[MaquinaDeEstados] %s: estadoAcao %s -> %s", self.entidade.Name, estadoAnterior, novoEstado))

	if self.callbacks.aoMudarEstadoAcao then
		self.callbacks.aoMudarEstadoAcao(novoEstado, estadoAnterior)
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES PÚBLICAS - TENTATIVAS DE AÇÃO
-- ═══════════════════════════════════════════════════════════════════

--- Tenta pular
---@return boolean sucesso
---@return string? motivo
function MaquinaDeEstados:TentePular(): (boolean, string?)
	-- Não pode pular se bloqueado
	if self:_EstaBloqueado() then
		return false, "EstadoBloqueante"
	end

	-- Não pode pular se já pulando ou caindo
	if
		self.dados.estadoMov == MaquinaDeEstados.EstadoMov.Pulando
		or self.dados.estadoMov == MaquinaDeEstados.EstadoMov.Caindo
	then
		return false, "JaPulando"
	end

	-- Não pode pular agachado
	if self.dados.agachado then
		return false, "Agachado"
	end

	-- Não pode pular bloqueando
	if self.dados.bloqueando then
		return false, "Bloqueando"
	end

	-- Não pode pular enquanto ataca (leve, pesado, carregando)
	if
		self.dados.estadoAcao == MaquinaDeEstados.EstadoAcao.AtacandoLeve
		or self.dados.estadoAcao == MaquinaDeEstados.EstadoAcao.CarregandoPesado
		or self.dados.estadoAcao == MaquinaDeEstados.EstadoAcao.AtaquePesado
		or self.dados.estadoAcao == MaquinaDeEstados.EstadoAcao.Defendendo
	then
		return false, "AcaoEmAndamento"
	end

	self:_AlterarEstadoMov(MaquinaDeEstados.EstadoMov.Pulando)
	return true, nil
end

--- Tenta aterrissar (chamado quando jogador toca o chão)
---@return boolean sucesso
function MaquinaDeEstados:TenteAterrissar(): boolean
	-- Só aterrissa se estava no ar
	if
		self.dados.estadoMov == MaquinaDeEstados.EstadoMov.Pulando
		or self.dados.estadoMov == MaquinaDeEstados.EstadoMov.Caindo
	then
		self:_AlterarEstadoMov(MaquinaDeEstados.EstadoMov.Parado)
		return true
	end
	return false
end

--- Define estado de movimento diretamente (para sincronizar com cliente)
---@param novoEstado string
---@return boolean sucesso
function MaquinaDeEstados:DefinirEstadoMov(novoEstado: string): boolean
	-- Valida se é um estado válido
	local estadoValido = false
	for _, estado in pairs(MaquinaDeEstados.EstadoMov) do
		if estado == novoEstado then
			estadoValido = true
			break
		end
	end

	if not estadoValido then
		return false
	end

	self:_AlterarEstadoMov(novoEstado)
	return true
end

--- Tenta atacar leve em pé
--- No novo sistema, esta função é chamada tanto para iniciar combo quanto para continuar
--- O controle real do combo é feito via marcadores de animação no cliente
---@return boolean sucesso
---@return string? tipoAtaque ("AtaqueLeve" ou nil se já está atacando)
---@return string? motivo
function MaquinaDeEstados:TenteAtacarLeveEmPe(): (boolean, string?, string?)
	-- Não pode atacar se bloqueado (exceto riposte)
	if self:_EstaBloqueado() then
		return false, nil, "EstadoBloqueante"
	end

	-- Permite riposte de Aparando
	if ESTADOS_PERMITE_RIPOSTE[self.dados.estadoAcao] then
		self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.AtacandoLeve)
		self.dados.indiceCombo = 1
		self.dados.janelaComboAtiva = false
		self.dados.continuarCombo = false
		return true, "AtaqueLeve", "Riposte"
	end

	-- Não pode atacar agachado (usar TenteAtacarLeveAgachado)
	if self.dados.agachado then
		return false, nil, "Agachado"
	end

	-- Verifica movimento
	if not self:_MovimentoPermiteAtaque() then
		return false, nil, "MovimentoInvalido"
	end

	-- Verifica se está defendendo
	if self.dados.bloqueando then
		return false, nil, "Bloqueando"
	end

	-- Carrega ArmasTemplate para verificar cooldown
	local ArmasTemplate = require(ReplicatedStorage:WaitForChild("Modulos"):WaitForChild("ArmasTemplate"))
	local arma = ArmasTemplate.ObterArma(self.dados.modoAnimacao)

	if not arma or not ArmasTemplate.PodeCombater(self.dados.modoAnimacao) then
		return false, nil, "SemCombate"
	end

	local agora = tick()

	-- Se já está atacando e está na janela de combo
	if self.dados.estadoAcao == MaquinaDeEstados.EstadoAcao.AtacandoLeve then
		if self.dados.janelaComboAtiva then
			-- Marca que deve continuar o combo
			self.dados.continuarCombo = true
			print(string.format("[MaquinaDeEstados] %s: Combo continuado na janela!", self.entidade.Name))
			return true, nil, "ComboContinuado"
		else
			-- Não está na janela, ignora input
			return false, nil, "ForaDaJanela"
		end
	end

	-- Novo ataque - verifica cooldown
	local ataque = ArmasTemplate.ObterAtaque(self.dados.modoAnimacao, "AtaqueLeve")
	if ataque and self.dados.ultimoAtaque > 0 then
		local cooldown = ataque.tempoRecarga or 0.5
		if (agora - self.dados.ultimoAtaque) < cooldown then
			return false, nil, "Cooldown"
		end
	end

	-- Inicia novo combo
	self.dados.ultimoAtaque = agora
	self.dados.indiceCombo = 1
	self.dados.janelaComboAtiva = false
	self.dados.continuarCombo = false

	-- Para de correr ao atacar (se estava correndo no chão)
	self:_PararCorrida()

	self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.AtacandoLeve)

	return true, "AtaqueLeve", nil
end

--- Tenta atacar leve agachado
---@return boolean sucesso
---@return string? tipoAtaque
---@return string? motivo
function MaquinaDeEstados:TenteAtacarLeveAgachado(): (boolean, string?, string?)
	if self:_EstaBloqueado() then
		return false, nil, "EstadoBloqueante"
	end

	if not self.dados.agachado then
		return false, nil, "NaoAgachado"
	end

	if self.dados.bloqueando then
		return false, nil, "Bloqueando"
	end

	local ArmasTemplate = require(ReplicatedStorage:WaitForChild("Modulos"):WaitForChild("ArmasTemplate"))

	if not ArmasTemplate.PodeCombater(self.dados.modoAnimacao) then
		return false, nil, "SemCombate"
	end

	-- Ataque agachado não tem combo
	self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.AtacandoLeve)
	self.dados.indiceCombo = 1

	return true, "AtaqueLeve", nil
end

--- Tenta carregar ataque pesado
---@return boolean sucesso
---@return string? motivo
function MaquinaDeEstados:TenteCarregarPesado(): (boolean, string?)
	if self:_EstaBloqueado() then
		return false, "EstadoBloqueante"
	end

	if self.dados.agachado then
		return false, "Agachado"
	end

	if not self:_MovimentoPermiteAtaque() then
		return false, "MovimentoInvalido"
	end

	if self.dados.bloqueando then
		return false, "Bloqueando"
	end

	local ArmasTemplate = require(ReplicatedStorage:WaitForChild("Modulos"):WaitForChild("ArmasTemplate"))

	if not ArmasTemplate.PodeCombater(self.dados.modoAnimacao) then
		return false, "SemCombate"
	end

	-- Verifica cooldown do ataque pesado
	local ataque = ArmasTemplate.ObterAtaque(self.dados.modoAnimacao, "AtaquePesado")
	if ataque then
		local agora = tick()
		if (agora - self.dados.ultimoAtaque) < ataque.tempoRecarga then
			return false, "Cooldown"
		end
	end

	-- Para de correr ao carregar ataque pesado (se estava correndo no chão)
	self:_PararCorrida()

	self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.CarregandoPesado)
	return true, nil
end

--- Tenta soltar ataque pesado (após carregar)
---@return boolean sucesso
---@return string? motivo
function MaquinaDeEstados:TenteSoltarPesado(): (boolean, string?)
	if self.dados.estadoAcao ~= MaquinaDeEstados.EstadoAcao.CarregandoPesado then
		return false, "NaoCarregando"
	end

	self.dados.ultimoAtaque = tick()
	self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.AtaquePesado)
	return true, nil
end

--- Tenta bloquear
---@return boolean sucesso
---@return string? motivo
function MaquinaDeEstados:TenteBloquear(): (boolean, string?)
	if self:_EstaBloqueado() then
		return false, "EstadoBloqueante"
	end

	-- Verifica ShiftLock na pasta Status da entidade
	local shiftLockAtivo = self.dados.shiftLock
	local status = self.entidade:FindFirstChild("Status")
	if status then
		local shiftLockValue = status:FindFirstChild("ShiftLockOn")
		if shiftLockValue then
			shiftLockAtivo = shiftLockValue.Value
			print(
				string.format(
					"[MaquinaDeEstados] %s: ShiftLockOn lido da Status = %s",
					self.entidade.Name,
					tostring(shiftLockAtivo)
				)
			)
		else
			print(string.format("[MaquinaDeEstados] %s: ShiftLockOn NAO ENCONTRADO na Status!", self.entidade.Name))
		end
	else
		print(string.format("[MaquinaDeEstados] %s: Pasta Status NAO ENCONTRADA!", self.entidade.Name))
	end

	if not shiftLockAtivo then
		return false, "SemShiftLock"
	end

	if not ESTADOS_PERMITE_BLOQUEIO[self.dados.estadoAcao] then
		print(
			string.format(
				"[MaquinaDeEstados] %s: Bloqueio falhou - estadoAcao=%s nao permite",
				self.entidade.Name,
				self.dados.estadoAcao
			)
		)
		return false, "AcaoEmAndamento"
	end

	if not self:_MovimentoPermiteAtaque() then
		print(
			string.format(
				"[MaquinaDeEstados] %s: Bloqueio falhou - estadoMov=%s nao permite",
				self.entidade.Name,
				self.dados.estadoMov
			)
		)
		return false, "MovimentoInvalido"
	end

	local ArmasTemplate = require(ReplicatedStorage:WaitForChild("Modulos"):WaitForChild("ArmasTemplate"))

	if not ArmasTemplate.PodeCombater(self.dados.modoAnimacao) then
		return false, "SemCombate"
	end

	-- Reset parry readiness on block start
	self.dados.prontoParaAparar = false
	self.dados.parryToken += 1

	-- Para de correr ao bloquear (se estava correndo no chão)
	self:_PararCorrida()

	self.dados.bloqueando = true
	self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.Defendendo)

	return true, nil
end

--- Tenta parar de bloquear
---@return boolean sucesso
---@return string? motivo
function MaquinaDeEstados:TentePararBloqueio(): (boolean, string?)
	if not self.dados.bloqueando then
		return false, "NaoBloqueando"
	end

	self.dados.bloqueando = false
	self.dados.prontoParaAparar = false
	self.dados.parryToken += 1 -- invalida timers de parry
	self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.Nenhuma)

	return true, nil
end

--- Tenta quebrar própria defesa
---@return boolean sucesso
---@return string? motivo
function MaquinaDeEstados:TenteQuebrarDefesa(): (boolean, string?)
	if not self.dados.bloqueando then
		return false, "NaoBloqueando"
	end

	self.dados.bloqueando = false
	self.dados.prontoParaAparar = false
	self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.DefesaQuebrada)

	return true, nil
end

--- Tenta agachar
---@return boolean sucesso
---@return string? motivo
function MaquinaDeEstados:TenteAgachar(): (boolean, string?)
	if self:_EstaBloqueado() then
		return false, "EstadoBloqueante"
	end

	if
		self.dados.estadoMov == MaquinaDeEstados.EstadoMov.Pulando
		or self.dados.estadoMov == MaquinaDeEstados.EstadoMov.Caindo
	then
		return false, "NoAr"
	end

	if self.dados.bloqueando then
		return false, "Bloqueando"
	end

	self.dados.agachado = true
	self:_AlterarEstadoMov(MaquinaDeEstados.EstadoMov.Agachado)

	return true, nil
end

--- Tenta levantar (parar de agachar)
---@return boolean sucesso
---@return string? motivo
function MaquinaDeEstados:TenteLevantar(): (boolean, string?)
	if not self.dados.agachado then
		return false, "NaoAgachado"
	end

	self.dados.agachado = false
	self:_AlterarEstadoMov(MaquinaDeEstados.EstadoMov.Parado)

	return true, nil
end

--- Tenta correr
---@return boolean sucesso
---@return string? motivo
function MaquinaDeEstados:TenteCorrer(): (boolean, string?)
	if self:_EstaBloqueado() then
		return false, "EstadoBloqueante"
	end

	if self.dados.agachado then
		return false, "Agachado"
	end

	if self.dados.bloqueando then
		return false, "Bloqueando"
	end

	-- Não pode correr enquanto ataca ou defende
	if
		self.dados.estadoAcao == MaquinaDeEstados.EstadoAcao.AtacandoLeve
		or self.dados.estadoAcao == MaquinaDeEstados.EstadoAcao.CarregandoPesado
		or self.dados.estadoAcao == MaquinaDeEstados.EstadoAcao.AtaquePesado
		or self.dados.estadoAcao == MaquinaDeEstados.EstadoAcao.Defendendo
	then
		return false, "AcaoEmAndamento"
	end

	if
		self.dados.estadoMov == MaquinaDeEstados.EstadoMov.Pulando
		or self.dados.estadoMov == MaquinaDeEstados.EstadoMov.Caindo
	then
		return false, "NoAr"
	end

	self.dados.correndo = true

	return true, nil
end

--- Tenta parar de correr
---@return boolean sucesso
function MaquinaDeEstados:TentePararCorrer(): boolean
	self.dados.correndo = false
	return true
end

--- Tenta equipar modo de combate
---@param modo string Nome do modo/arma
---@return boolean sucesso
---@return string? motivo
function MaquinaDeEstados:TenteEquipar(modo: string): (boolean, string?)
	if self:_EstaBloqueado() then
		return false, "EstadoBloqueante"
	end

	if self.dados.estadoAcao ~= MaquinaDeEstados.EstadoAcao.Nenhuma then
		return false, "AcaoEmAndamento"
	end

	local ArmasTemplate = require(ReplicatedStorage:WaitForChild("Modulos"):WaitForChild("ArmasTemplate"))

	if not ArmasTemplate.ObterArma(modo) then
		return false, "ModoInvalido"
	end

	self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.Equipando)

	return true, nil
end

--- Tenta desequipar modo de combate
---@return boolean sucesso
---@return string? motivo
function MaquinaDeEstados:TenteDesequipar(): (boolean, string?)
	if self:_EstaBloqueado() then
		return false, "EstadoBloqueante"
	end

	if self.dados.estadoAcao ~= MaquinaDeEstados.EstadoAcao.Nenhuma then
		return false, "AcaoEmAndamento"
	end

	if self.dados.modoAnimacao == "Base" then
		return false, "JaBase"
	end

	self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.Desequipando)

	return true, nil
end

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES DE APLICAÇÃO FORÇADA (SERVIDOR)
-- ═══════════════════════════════════════════════════════════════════

--- Aplica stun (ignorando condições)
---@param duracao number
function MaquinaDeEstados:AplicarStun(duracao: number)
	self.dados.stunado = true
	self.dados.bloqueando = false
	self.dados.prontoParaAparar = false
	self.dados.indiceCombo = 0
	self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.Stunado)

	-- Agendar remoção do stun
	task.delay(duracao, function()
		if self.dados.estadoAcao == MaquinaDeEstados.EstadoAcao.Stunado then
			self.dados.stunado = false
			self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.Nenhuma)
		end
	end)
end

--- Aplica estado de aparado (foi parried)
---@param duracao number
function MaquinaDeEstados:AplicarAparado(duracao: number)
	self.dados.stunado = true
	self.dados.bloqueando = false
	self.dados.indiceCombo = 0
	self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.Aparado)

	task.delay(duracao, function()
		if self.dados.estadoAcao == MaquinaDeEstados.EstadoAcao.Aparado then
			self.dados.stunado = false
			self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.Nenhuma)
		end
	end)
end

--- Aplica estado de aparando (executou parry com sucesso)
function MaquinaDeEstados:AplicarAparando()
	self.dados.prontoParaAparar = false
	self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.Aparando)
end

--- Aplica morte
function MaquinaDeEstados:AplicarMorte()
	self.dados.stunado = true
	self.dados.bloqueando = false
	self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.Morto)
end

--- Completa ação atual (chamado quando animação termina)
function MaquinaDeEstados:CompletarAcao()
	if self.dados.estadoAcao == MaquinaDeEstados.EstadoAcao.Morto then
		return -- Morte é permanente
	end

	if
		self.dados.estadoAcao == MaquinaDeEstados.EstadoAcao.Stunado
		or self.dados.estadoAcao == MaquinaDeEstados.EstadoAcao.Aparado
	then
		return -- Gerenciado por timer
	end

	-- Reseta dados de combo ao completar ação
	self.dados.indiceCombo = 0
	self.dados.janelaComboAtiva = false
	self.dados.continuarCombo = false

	self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.Nenhuma)
end

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES DO SISTEMA DE COMBO POR MARCADORES
-- ═══════════════════════════════════════════════════════════════════

--- Ativa a janela de input do combo
--- Chamado quando o marcador "ComboTentaAcabar" é atingido na animação
---@param indiceGolpe number Índice do golpe atual (1, 2, 3)
function MaquinaDeEstados:AtivarJanelaCombo(indiceGolpe: number)
	if self.dados.estadoAcao ~= MaquinaDeEstados.EstadoAcao.AtacandoLeve then
		return -- Não está atacando, ignora
	end

	self.dados.janelaComboAtiva = true
	self.dados.continuarCombo = false -- Reseta flag de continuar
	self.dados.indiceCombo = indiceGolpe

	print(string.format("[MaquinaDeEstados] %s: Janela de combo ativada (golpe %d)", self.entidade.Name, indiceGolpe))
end

--- Desativa a janela de input do combo
--- Chamado quando o tempo da janela expira
function MaquinaDeEstados:DesativarJanelaCombo()
	self.dados.janelaComboAtiva = false
end

--- Verifica se o jogador quer continuar o combo
--- Chamado para decidir se deve continuar a animação ou parar
---@return boolean True se deve continuar o combo
function MaquinaDeEstados:DeveContinuarCombo(): boolean
	local resultado = self.dados.continuarCombo
	self.dados.continuarCombo = false -- Consome o input
	return resultado
end

--- Avança para o próximo golpe do combo
--- Chamado quando o marcador "Ataque" é atingido na animação
---@param indiceGolpe number Índice do golpe que acabou de conectar (1, 2, 3, 4)
function MaquinaDeEstados:AvancarGolpeCombo(indiceGolpe: number)
	if self.dados.estadoAcao ~= MaquinaDeEstados.EstadoAcao.AtacandoLeve then
		return
	end

	self.dados.indiceCombo = indiceGolpe
	self.dados.ultimoAtaque = tick() -- Atualiza timestamp do último ataque

	print(string.format("[MaquinaDeEstados] %s: Golpe %d executado", self.entidade.Name, indiceGolpe))
end

--- Verifica se a janela de combo está ativa
---@return boolean
function MaquinaDeEstados:EstaJanelaComboAtiva(): boolean
	return self.dados.janelaComboAtiva
end

--- Define modo de animação/combate
function MaquinaDeEstados:DefinirModo(modo: string)
	if self.dados.modoAnimacao == modo then
		return
	end

	local modoAnterior = self.dados.modoAnimacao
	self.dados.modoAnimacao = modo

	if self.callbacks.aoMudarModo then
		self.callbacks.aoMudarModo(modo, modoAnterior)
	end
end

--- Atualiza shift lock
function MaquinaDeEstados:DefinirShiftLock(ativo: boolean)
	self.dados.shiftLock = ativo
end

--- Desativa janela de parry
function MaquinaDeEstados:DesativarParry()
	self.dados.prontoParaAparar = false
end

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES DE MOVIMENTO (AUTOMÁTICAS)
-- ═══════════════════════════════════════════════════════════════════

--- Atualiza estado de movimento baseado no Humanoid
---@param velocidade number
---@param noChao boolean
---@param velocidadeY number
function MaquinaDeEstados:AtualizarMovimento(velocidade: number, noChao: boolean, velocidadeY: number)
	-- Prioridade: estados especiais
	if
		self.dados.estadoMov == MaquinaDeEstados.EstadoMov.Escalando
		or self.dados.estadoMov == MaquinaDeEstados.EstadoMov.Nadando
	then
		return -- Gerenciado externamente
	end

	if self.dados.agachado then
		return -- Mantém agachado
	end

	-- No ar
	if not noChao then
		if velocidadeY > 1 then
			self:_AlterarEstadoMov(MaquinaDeEstados.EstadoMov.Pulando)
		else
			self:_AlterarEstadoMov(MaquinaDeEstados.EstadoMov.Caindo)
		end
		return
	end

	-- No chão
	if velocidade < 0.5 then
		self:_AlterarEstadoMov(MaquinaDeEstados.EstadoMov.Parado)
	elseif velocidade > 12 then
		self:_AlterarEstadoMov(MaquinaDeEstados.EstadoMov.Correndo)
	else
		self:_AlterarEstadoMov(MaquinaDeEstados.EstadoMov.Andando)
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- CALLBACKS
-- ═══════════════════════════════════════════════════════════════════

--- Registra callback para mudança de estado de movimento
function MaquinaDeEstados:AoMudarEstadoMov(callback: (string, string) -> ())
	self.callbacks.aoMudarEstadoMov = callback
end

--- Registra callback para mudança de estado de ação
function MaquinaDeEstados:AoMudarEstadoAcao(callback: (string, string) -> ())
	self.callbacks.aoMudarEstadoAcao = callback
end

--- Registra callback para mudança de modo
function MaquinaDeEstados:AoMudarModo(callback: (string, string) -> ())
	self.callbacks.aoMudarModo = callback
end

-- ═══════════════════════════════════════════════════════════════════
-- GETTERS
-- ═══════════════════════════════════════════════════════════════════

function MaquinaDeEstados:ObterEstadoMov(): string
	return self.dados.estadoMov
end

function MaquinaDeEstados:ObterEstadoAcao(): string
	return self.dados.estadoAcao
end

function MaquinaDeEstados:ObterModo(): string
	return self.dados.modoAnimacao
end

function MaquinaDeEstados:ObterIndiceCombo(): number
	return self.dados.indiceCombo
end

function MaquinaDeEstados:EstaBloqueando(): boolean
	return self.dados.bloqueando
end

function MaquinaDeEstados:EstaProntoParaAparar(): boolean
	return self.dados.prontoParaAparar
end

function MaquinaDeEstados:EstaAgachado(): boolean
	return self.dados.agachado
end

function MaquinaDeEstados:EstaStunado(): boolean
	return self.dados.stunado
end

function MaquinaDeEstados:ObterDados(): DadosEstado
	return self.dados
end

return MaquinaDeEstados
