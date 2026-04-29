--[[
    Script: MaquinaEstadosJogador.luau
    Caminho: src/ReplicatedStorage/Jogador/Estado
    Responsabilidade: Mantem a maquina de estados que coordena transicoes de comportamento do jogador.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao roda sozinho nem cria fluxo de jogo por conta propria; depende dos scripts que importam este modulo.
    Funcoes principais: Novo, _EstaBloqueado, _MovimentoPermiteAtaque, _PararCorrida, _AlterarEstadoMov, _AlterarEstadoAcao
]]
local DEBUG_ENABLED = false

local function DebugPrint(...)
	if DEBUG_ENABLED then
		print(...)
	end
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modulo_Configuracoes =
	require(ReplicatedStorage:WaitForChild("Combate"):WaitForChild("Configuracoes"):WaitForChild("ConfigCombate"))

local MaquinaDeEstados = {}
MaquinaDeEstados.__index = MaquinaDeEstados

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
	SoltandoPesado = "SoltandoPesado",
	AtaquePesado = "AtaquePesado",
	Defendendo = "Defendendo",
	DefesaQuebrada = "DefesaQuebrada",
	Aparando = "Aparando",
	Aparado = "Aparado",
	Stunado = "Stunado",
	Equipando = "Equipando",
	Desequipando = "Desequipando",
	Dashando = "Dashando",
	Morto = "Morto",
}

local ESTADOS_BLOQUEANTES = {
	[MaquinaDeEstados.EstadoAcao.Stunado] = true,
	[MaquinaDeEstados.EstadoAcao.Aparado] = true,
	[MaquinaDeEstados.EstadoAcao.Morto] = true,
	[MaquinaDeEstados.EstadoAcao.Equipando] = true,
	[MaquinaDeEstados.EstadoAcao.Desequipando] = true,
	[MaquinaDeEstados.EstadoAcao.Dashando] = true,
}

local ESTADOS_PERMITE_RIPOSTE = {
	[MaquinaDeEstados.EstadoAcao.Aparando] = true,
}

local ESTADOS_PERMITE_BLOQUEIO = {
	[MaquinaDeEstados.EstadoAcao.Nenhuma] = true,
}

local MOVIMENTO_PERMITE_ATAQUE = {
	[MaquinaDeEstados.EstadoMov.Parado] = true,
	[MaquinaDeEstados.EstadoMov.Andando] = true,
	[MaquinaDeEstados.EstadoMov.Correndo] = true,
	[MaquinaDeEstados.EstadoMov.Agachado] = true,
	[MaquinaDeEstados.EstadoMov.Pulando] = true,
	[MaquinaDeEstados.EstadoMov.Caindo] = true,
}

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

	janelaComboAtiva: boolean,
	continuarCombo: boolean,

	dashando: boolean,
	ultimoDash: number,
	direcaoDash: string,
	correndoIntent: boolean?,
}

function MaquinaDeEstados.Novo(entidade: Model)
	local self = setmetatable({}, MaquinaDeEstados)

	self.entidade = entidade
	self.humanoid = entidade:FindFirstChildOfClass("Humanoid")

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

		ultimoAtaqueTipos = {},

		ultimoAtaque = 0,
		ultimoParry = 0,
		parryToken = 0,

		janelaComboAtiva = false,
		continuarCombo = false,

		dashando = false,
		ultimoDash = 0,
		direcaoDash = "Frente",
	} :: DadosEstado

	self.callbacks = {
		aoMudarEstadoMov = nil,
		aoMudarEstadoAcao = nil,
		aoMudarModo = nil,
	}

	return self
end

function MaquinaDeEstados:_EstaBloqueado(): boolean
	return ESTADOS_BLOQUEANTES[self.dados.estadoAcao] == true
end

function MaquinaDeEstados:_MovimentoPermiteAtaque(): boolean
	return MOVIMENTO_PERMITE_ATAQUE[self.dados.estadoMov] == true
end

function MaquinaDeEstados:_PararCorrida()
	if self.dados.correndo then
		self.dados.correndo = false
	end

	if self.dados.estadoMov == MaquinaDeEstados.EstadoMov.Correndo then

		if self.humanoid and self.humanoid.MoveDirection.Magnitude > 0.1 then
			self:_AlterarEstadoMov(MaquinaDeEstados.EstadoMov.Andando)
		else
			self:_AlterarEstadoMov(MaquinaDeEstados.EstadoMov.Parado)
		end
	end
end

function MaquinaDeEstados:_AlterarEstadoMov(novoEstado: string)
	if self.dados.estadoMov == novoEstado then
		return
	end

	local estadoAnterior = self.dados.estadoMov
	self.dados.estadoMov = novoEstado

	DebugPrint(
		string.format("[MaquinaDeEstados] %s: estadoMov %s -> %s", self.entidade.Name, estadoAnterior, novoEstado)
	)

	if self.callbacks.aoMudarEstadoMov then
		self.callbacks.aoMudarEstadoMov(novoEstado, estadoAnterior)
	end
end

function MaquinaDeEstados:_AlterarEstadoAcao(novoEstado: string)
	if self.dados.estadoAcao == novoEstado then
		return
	end

	local estadoAnterior = self.dados.estadoAcao
	self.dados.estadoAcao = novoEstado

	DebugPrint(
		string.format("[MaquinaDeEstados] %s: estadoAcao %s -> %s", self.entidade.Name, estadoAnterior, novoEstado)
	)

	if self.callbacks.aoMudarEstadoAcao then
		self.callbacks.aoMudarEstadoAcao(novoEstado, estadoAnterior)
	end
end

function MaquinaDeEstados:TentePular(): (boolean, string?)

	if self:_EstaBloqueado() then
		return false, "EstadoBloqueante"
	end

	if
		self.dados.estadoMov == MaquinaDeEstados.EstadoMov.Pulando
		or self.dados.estadoMov == MaquinaDeEstados.EstadoMov.Caindo
	then
		return false, "JaPulando"
	end

	if self.dados.agachado then
		return false, "Agachado"
	end

	if self.dados.bloqueando then
		return false, "Bloqueando"
	end

	if
		self.dados.estadoAcao == MaquinaDeEstados.EstadoAcao.AtacandoLeve
		or self.dados.estadoAcao == MaquinaDeEstados.EstadoAcao.CarregandoPesado
		or self.dados.estadoAcao == MaquinaDeEstados.EstadoAcao.SoltandoPesado
		or self.dados.estadoAcao == MaquinaDeEstados.EstadoAcao.AtaquePesado
		or self.dados.estadoAcao == MaquinaDeEstados.EstadoAcao.Defendendo
	then
		return false, "AcaoEmAndamento"
	end

	self:_AlterarEstadoMov(MaquinaDeEstados.EstadoMov.Pulando)
	return true, nil
end

function MaquinaDeEstados:TenteAterrissar(): boolean

	if
		self.dados.estadoMov == MaquinaDeEstados.EstadoMov.Pulando
		or self.dados.estadoMov == MaquinaDeEstados.EstadoMov.Caindo
	then
		self:_AlterarEstadoMov(MaquinaDeEstados.EstadoMov.Parado)
		return true
	end
	return false
end

function MaquinaDeEstados:DefinirEstadoMov(novoEstado: string): boolean

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

function MaquinaDeEstados:TenteAtacarLeveEmPe(): (boolean, string?, string?)

	if self:_EstaBloqueado() then
		return false, nil, "EstadoBloqueante"
	end

	if ESTADOS_PERMITE_RIPOSTE[self.dados.estadoAcao] then
		self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.AtacandoLeve)
		self.dados.indiceCombo = 1
		self.dados.janelaComboAtiva = false
		self.dados.continuarCombo = false
		return true, "AtaqueLeve", "Riposte"
	end

	if self.dados.agachado then
		return false, nil, "Agachado"
	end

	if not self:_MovimentoPermiteAtaque() then
		return false, nil, "MovimentoInvalido"
	end

	if self.dados.bloqueando then
		return false, nil, "Bloqueando"
	end

	local configModo = Modulo_Configuracoes.ObterModoAnimacao(self.dados.modoAnimacao)

	if not configModo or configModo.tipo ~= "Combate" then
		return false, nil, "SemCombate"
	end

	local agora = tick()

	if self.dados.estadoAcao == MaquinaDeEstados.EstadoAcao.AtacandoLeve then
		if self.dados.janelaComboAtiva then

			self.dados.continuarCombo = true
			DebugPrint(string.format("[MaquinaDeEstados] %s: Combo continuado na janela!", self.entidade.Name))
			return false, nil, "ComboContinuado"
		else

			return false, nil, "ForaDaJanela"
		end
	end

	if self.dados.estadoAcao ~= MaquinaDeEstados.EstadoAcao.Nenhuma then
		DebugPrint(
			string.format(
				"[MaquinaDeEstados] %s: Ataque leve bloqueado - estadoAcao=%s",
				self.entidade.Name,
				self.dados.estadoAcao
			)
		)
		return false, nil, "AcaoEmAndamento"
	end

	local cooldown = Modulo_Configuracoes.ObterConfiguracao("CooldownComboLeve") or 0.5
	local dadosAtaque = self.dados.ultimoAtaqueTipos
	local ultimoLeve = dadosAtaque and dadosAtaque["AtaqueLeve"] or 0
	local ultimoPesado = dadosAtaque and dadosAtaque["AtaquePesado"] or 0

	local ultimoAtaque = math.max(ultimoLeve, ultimoPesado)

	if ultimoAtaque > 0 and (agora - ultimoAtaque) < cooldown then
		return false, nil, "Cooldown"
	end

	self.dados.ultimoAtaqueTipos["AtaqueLeve"] = agora

	self.dados.ultimoAtaque = agora
	self.dados.indiceCombo = 1
	self.dados.janelaComboAtiva = false
	self.dados.continuarCombo = false

	self:_PararCorrida()

	self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.AtacandoLeve)

	return true, "AtaqueLeve", nil
end

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

	local configModo = Modulo_Configuracoes.ObterModoAnimacao(self.dados.modoAnimacao)

	if not configModo or configModo.tipo ~= "Combate" then
		return false, nil, "SemCombate"
	end

	if self.dados.estadoAcao ~= MaquinaDeEstados.EstadoAcao.Nenhuma then
		return false, nil, "AcaoEmAndamento"
	end

	local agora = tick()
	local cooldown = Modulo_Configuracoes.ObterConfiguracao("CooldownComboLeve") or 0.5
	local dadosAtaque = self.dados.ultimoAtaqueTipos
	local ultimoLeve = dadosAtaque and dadosAtaque["AtaqueLeve"] or 0
	local ultimoPesado = dadosAtaque and dadosAtaque["AtaquePesado"] or 0

	local ultimoAtaque = math.max(ultimoLeve, ultimoPesado)

	if ultimoAtaque > 0 and (agora - ultimoAtaque) < cooldown then
		return false, nil, "Cooldown"
	end

	self.dados.ultimoAtaqueTipos["AtaqueLeve"] = agora
	self.dados.ultimoAtaque = agora
	self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.AtacandoLeve)
	self.dados.indiceCombo = 1

	return true, "AtaqueLeve", nil
end

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

	local configModo = Modulo_Configuracoes.ObterModoAnimacao(self.dados.modoAnimacao)

	if not configModo or configModo.tipo ~= "Combate" then
		return false, "SemCombate"
	end

	if self.dados.estadoAcao ~= MaquinaDeEstados.EstadoAcao.Nenhuma then
		return false, "AcaoEmAndamento"
	end

	local cooldown = Modulo_Configuracoes.ObterConfiguracao("CooldownAtaquePesado") or 2.0
	local agora = tick()
	local ultimoPesado = self.dados.ultimoAtaqueTipos and self.dados.ultimoAtaqueTipos["AtaquePesado"] or 0
	if ultimoPesado > 0 and (agora - ultimoPesado) < cooldown then
		return false, "Cooldown"
	end

	self:_PararCorrida()

	self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.CarregandoPesado)
	return true, nil
end

function MaquinaDeEstados:TenteSoltarPesado(): (boolean, string?)
	if self.dados.estadoAcao ~= MaquinaDeEstados.EstadoAcao.CarregandoPesado then
		return false, "NaoCarregando"
	end

	self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.SoltandoPesado)
	return true, nil
end

function MaquinaDeEstados:TenteExecutarPesado(): (boolean, string?)
	if self.dados.estadoAcao ~= MaquinaDeEstados.EstadoAcao.SoltandoPesado then
		return false, "NaoSoltando"
	end

	local agora = tick()

	self.dados.ultimoAtaqueTipos["AtaquePesado"] = agora

	self.dados.ultimoAtaque = agora
	self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.AtaquePesado)
	return true, nil
end

function MaquinaDeEstados:TenteBloquear(shiftLockAtivo: boolean?): (boolean, string?)
	if self:_EstaBloqueado() then
		return false, "EstadoBloqueante"
	end

	local estaComShiftLock = shiftLockAtivo
	if estaComShiftLock == nil then

		local statusLocal = self.entidade:FindFirstChild("StatusLocal")
		if statusLocal then
			local shiftLockValue = statusLocal:FindFirstChild("ShiftLockOn")
			if shiftLockValue and shiftLockValue:IsA("BoolValue") then
				estaComShiftLock = shiftLockValue.Value
				DebugPrint(
					string.format(
						"[MaquinaDeEstados] %s: ShiftLockOn lido de StatusLocal = %s",
						self.entidade.Name,
						tostring(estaComShiftLock)
					)
				)
			end
		end

		if estaComShiftLock == nil then
			estaComShiftLock = self.dados.shiftLock
		end
	end

	if not estaComShiftLock then
		return false, "SemShiftLock"
	end

	if not ESTADOS_PERMITE_BLOQUEIO[self.dados.estadoAcao] then
		DebugPrint(
			string.format(
				"[MaquinaDeEstados] %s: Bloqueio falhou - estadoAcao=%s nao permite",
				self.entidade.Name,
				self.dados.estadoAcao
			)
		)
		return false, "AcaoEmAndamento"
	end

	if not self:_MovimentoPermiteAtaque() then
		DebugPrint(
			string.format(
				"[MaquinaDeEstados] %s: Bloqueio falhou - estadoMov=%s nao permite",
				self.entidade.Name,
				self.dados.estadoMov
			)
		)
		return false, "MovimentoInvalido"
	end

	local configModo = Modulo_Configuracoes.ObterModoAnimacao(self.dados.modoAnimacao)

	if not configModo or configModo.tipo ~= "Combate" then
		return false, "SemCombate"
	end

	self.dados.prontoParaAparar = false
	self.dados.parryToken += 1

	self:_PararCorrida()

	self.dados.bloqueando = true
	self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.Defendendo)

	return true, nil
end

function MaquinaDeEstados:TentePararBloqueio(): (boolean, string?)
	if not self.dados.bloqueando then
		return false, "NaoBloqueando"
	end

	self.dados.bloqueando = false
	self.dados.prontoParaAparar = false
	self.dados.parryToken += 1
	self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.Nenhuma)

	return true, nil
end

function MaquinaDeEstados:TenteQuebrarDefesa(): (boolean, string?)
	if not self.dados.bloqueando then
		return false, "NaoBloqueando"
	end

	self.dados.bloqueando = false
	self.dados.prontoParaAparar = false
	self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.DefesaQuebrada)

	return true, nil
end

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

function MaquinaDeEstados:TenteLevantar(): (boolean, string?)
	if not self.dados.agachado then
		return false, "NaoAgachado"
	end

	self.dados.agachado = false
	self:_AlterarEstadoMov(MaquinaDeEstados.EstadoMov.Parado)

	return true, nil
end

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

	if
		self.dados.estadoAcao == MaquinaDeEstados.EstadoAcao.AtacandoLeve
		or self.dados.estadoAcao == MaquinaDeEstados.EstadoAcao.CarregandoPesado
		or self.dados.estadoAcao == MaquinaDeEstados.EstadoAcao.SoltandoPesado
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

function MaquinaDeEstados:TentePararCorrer(): boolean
	self.dados.correndo = false
	return true
end

function MaquinaDeEstados:TenteEquipar(modo: string): (boolean, string?)
	if self:_EstaBloqueado() then
		return false, "EstadoBloqueante"
	end

	if self.dados.estadoAcao ~= MaquinaDeEstados.EstadoAcao.Nenhuma then
		return false, "AcaoEmAndamento"
	end

	local configModo = Modulo_Configuracoes.ObterModoAnimacao(modo)

	if not configModo then
		return false, "ModoInvalido"
	end

	self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.Equipando)

	return true, nil
end

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

function MaquinaDeEstados:TenteDash(direcao: string): (boolean, string?)

	if self:_EstaBloqueado() then
		return false, "EstadoBloqueante"
	end

	if self.dados.estadoAcao ~= MaquinaDeEstados.EstadoAcao.Nenhuma then
		return false, "AcaoEmAndamento"
	end

	if self.dados.bloqueando then
		return false, "Bloqueando"
	end

	if self.dados.agachado then
		return false, "Agachado"
	end

	if
		self.dados.estadoMov == MaquinaDeEstados.EstadoMov.Pulando
		or self.dados.estadoMov == MaquinaDeEstados.EstadoMov.Caindo
	then
		return false, "NoAr"
	end

	if self.humanoid and self.humanoid.FloorMaterial == Enum.Material.Air then
		DebugPrint(string.format("[MaquinaDeEstados] %s: Dash bloqueado - FloorMaterial é Air", self.entidade.Name))
		return false, "NoAr"
	end

	local agora = tick()
	local cooldown = Modulo_Configuracoes.ObterConfiguracao("CooldownDash") or 1.5

	if (agora - self.dados.ultimoDash) < cooldown then
		return false, "Cooldown"
	end

	self.dados.dashando = true
	self.dados.direcaoDash = direcao or "Frente"
	self.dados.ultimoDash = agora

	self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.Dashando)

	return true, nil
end

function MaquinaDeEstados:CompletarDash()
	if self.dados.estadoAcao ~= MaquinaDeEstados.EstadoAcao.Dashando then
		return false
	end

	self.dados.dashando = false
	self.dados.direcaoDash = "Frente"
	self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.Nenhuma)

	return true
end

function MaquinaDeEstados:AplicarStun(duracao: number)
	self.dados.stunado = true
	self.dados.bloqueando = false
	self.dados.prontoParaAparar = false
	self.dados.indiceCombo = 0
	self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.Stunado)

	task.delay(duracao, function()
		if self.dados.estadoAcao == MaquinaDeEstados.EstadoAcao.Stunado then
			self.dados.stunado = false
			self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.Nenhuma)
		end
	end)
end

function MaquinaDeEstados:EntrarStun(duracao: number)
	self:AplicarStun(duracao)
end

function MaquinaDeEstados:QuebrarDefesa(duracao: number)
	self.dados.stunado = true
	self.dados.bloqueando = false
	self.dados.prontoParaAparar = false
	self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.DefesaQuebrada)

	task.delay(duracao, function()
		if self.dados.estadoAcao == MaquinaDeEstados.EstadoAcao.DefesaQuebrada then
			self.dados.stunado = false
			self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.Nenhuma)
		end
	end)
end

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

function MaquinaDeEstados:AplicarAparando()
	self.dados.prontoParaAparar = false
	self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.Aparando)
end

function MaquinaDeEstados:AplicarMorte()
	self.dados.stunado = true
	self.dados.bloqueando = false
	self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.Morto)
end

function MaquinaDeEstados:CompletarAcao()
	if self.dados.estadoAcao == MaquinaDeEstados.EstadoAcao.Morto then
		return
	end

	if
		self.dados.estadoAcao == MaquinaDeEstados.EstadoAcao.Stunado
		or self.dados.estadoAcao == MaquinaDeEstados.EstadoAcao.Aparado
	then
		return
	end

	self.dados.indiceCombo = 0
	self.dados.janelaComboAtiva = false
	self.dados.continuarCombo = false

	self:_AlterarEstadoAcao(MaquinaDeEstados.EstadoAcao.Nenhuma)
end

function MaquinaDeEstados:AtivarJanelaCombo(indiceGolpe: number)
	if self.dados.estadoAcao ~= MaquinaDeEstados.EstadoAcao.AtacandoLeve then
		return
	end

	self.dados.janelaComboAtiva = true
	self.dados.continuarCombo = false
	self.dados.indiceCombo = indiceGolpe

	DebugPrint(
		string.format("[MaquinaDeEstados] %s: Janela de combo ativada (golpe %d)", self.entidade.Name, indiceGolpe)
	)
end

function MaquinaDeEstados:DesativarJanelaCombo()
	self.dados.janelaComboAtiva = false
end

function MaquinaDeEstados:DeveContinuarCombo(): boolean
	local resultado = self.dados.continuarCombo
	self.dados.continuarCombo = false
	return resultado
end

function MaquinaDeEstados:AvancarGolpeCombo(indiceGolpe: number)
	if self.dados.estadoAcao ~= MaquinaDeEstados.EstadoAcao.AtacandoLeve then
		return
	end

	self.dados.indiceCombo = indiceGolpe
	local agora = tick()

	self.dados.ultimoAtaqueTipos["AtaqueLeve"] = agora

	self.dados.ultimoAtaque = agora

	DebugPrint(string.format("[MaquinaDeEstados] %s: Golpe %d executado", self.entidade.Name, indiceGolpe))
end

function MaquinaDeEstados:EstaJanelaComboAtiva(): boolean
	return self.dados.janelaComboAtiva
end

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

function MaquinaDeEstados:DefinirShiftLock(ativo: boolean)
	self.dados.shiftLock = ativo
end

function MaquinaDeEstados:DesativarParry()
	self.dados.prontoParaAparar = false
end

function MaquinaDeEstados:AtualizarMovimento(velocidade: number, noChao: boolean, velocidadeY: number)

	if
		self.dados.estadoMov == MaquinaDeEstados.EstadoMov.Escalando
		or self.dados.estadoMov == MaquinaDeEstados.EstadoMov.Nadando
	then
		return
	end

	if self.dados.agachado then
		return
	end

	if not noChao then
		if velocidadeY > 1 then
			self:_AlterarEstadoMov(MaquinaDeEstados.EstadoMov.Pulando)
		else
			self:_AlterarEstadoMov(MaquinaDeEstados.EstadoMov.Caindo)
		end
		return
	end

	if velocidade < 0.5 then
		self:_AlterarEstadoMov(MaquinaDeEstados.EstadoMov.Parado)
	elseif velocidade > 12 then
		self:_AlterarEstadoMov(MaquinaDeEstados.EstadoMov.Correndo)
	else
		self:_AlterarEstadoMov(MaquinaDeEstados.EstadoMov.Andando)
	end
end

function MaquinaDeEstados:AoMudarEstadoMov(callback: (string, string) -> ())
	self.callbacks.aoMudarEstadoMov = callback
end

function MaquinaDeEstados:AoMudarEstadoAcao(callback: (string, string) -> ())
	self.callbacks.aoMudarEstadoAcao = callback
end

function MaquinaDeEstados:AoMudarModo(callback: (string, string) -> ())
	self.callbacks.aoMudarModo = callback
end

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
