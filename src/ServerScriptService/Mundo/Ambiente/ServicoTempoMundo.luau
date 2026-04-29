local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ConfiguracaoTempo = require(ReplicatedStorage:WaitForChild("Mundo"):WaitForChild("Ambiente"):WaitForChild("ConfiguracaoTempo"))

local ServicoTempoMundo = {}

ServicoTempoMundo._iniciado = false
ServicoTempoMundo._conexao = nil
ServicoTempoMundo._acumulador = 0
ServicoTempoMundo._minutos = ConfiguracaoTempo.HorarioInicialMinutos
ServicoTempoMundo._dia = ConfiguracaoTempo.DiaInicial
ServicoTempoMundo._valores = nil
ServicoTempoMundo._pausado = false

local function garantirPastaEstado()
	local pasta = ReplicatedStorage:FindFirstChild("EstadoMundo")
	if not pasta then
		pasta = Instance.new("Folder")
		pasta.Name = "EstadoMundo"
		pasta.Parent = ReplicatedStorage
	end
	return pasta
end

local function garantirValor(pasta, classe, nome, valorInicial)
	local valor = pasta:FindFirstChild(nome)
	if not valor or not valor:IsA(classe) then
		if valor then
			valor:Destroy()
		end
		valor = Instance.new(classe)
		valor.Name = nome
		valor.Parent = pasta
	end
	if valorInicial ~= nil then
		valor.Value = valorInicial
	end
	return valor
end

function ServicoTempoMundo:_garantirEstado()
	if self._valores then
		return self._valores
	end

	local pasta = garantirPastaEstado()
	self._valores = {
		Pasta = pasta,
		MinutosDoDia = garantirValor(pasta, "NumberValue", "MinutosDoDia", self._minutos),
		HoraTexto = garantirValor(pasta, "StringValue", "HoraTexto", ConfiguracaoTempo.FormatarHora(self._minutos)),
		FaseDia = garantirValor(pasta, "StringValue", "FaseDia", ConfiguracaoTempo.ObterFase(self._minutos).id),
		Dia = garantirValor(pasta, "IntValue", "Dia", self._dia),
		Semana = garantirValor(pasta, "IntValue", "Semana", math.floor((self._dia - 1) / 7) + 1),
		AtualizadoEm = garantirValor(pasta, "NumberValue", "TempoAtualizadoEm", os.clock()),
		Pausado = garantirValor(pasta, "BoolValue", "TempoPausado", self._pausado),
		DuracaoTransicao = garantirValor(pasta, "NumberValue", "DuracaoTransicaoHorario", ConfiguracaoTempo.DuracaoTransicaoHorarioPadrao),
	}
	return self._valores
end

function ServicoTempoMundo:_replicar()
	local valores = self:_garantirEstado()
	local fase = ConfiguracaoTempo.ObterFase(self._minutos)
	valores.MinutosDoDia.Value = self._minutos
	valores.HoraTexto.Value = ConfiguracaoTempo.FormatarHora(self._minutos)
	valores.FaseDia.Value = fase.id
	valores.Dia.Value = self._dia
	valores.Semana.Value = math.floor((self._dia - 1) / 7) + 1
	valores.AtualizadoEm.Value = os.clock()
	valores.Pasta:SetAttribute("HoraTexto", valores.HoraTexto.Value)
	valores.Pasta:SetAttribute("FaseDia", fase.id)
end

function ServicoTempoMundo:_avancar(deltaMinutos: number)
	local novo = self._minutos + deltaMinutos
	while novo >= ConfiguracaoTempo.MinutosPorDia do
		novo -= ConfiguracaoTempo.MinutosPorDia
		self._dia += 1
	end
	while novo < 0 do
		novo += ConfiguracaoTempo.MinutosPorDia
		self._dia = math.max(1, self._dia - 1)
	end
	self._minutos = ConfiguracaoTempo.NormalizarMinutos(novo)
	self:_replicar()
end

function ServicoTempoMundo:Iniciar()
	if self._iniciado then
		return
	end

	self._iniciado = true
	self:_garantirEstado()
	self:_replicar()

	self._conexao = RunService.Heartbeat:Connect(function(deltaTime)
		if self._pausado then
			self._acumulador = 0
			return
		end
		self._acumulador += deltaTime
		if self._acumulador < ConfiguracaoTempo.IntervaloReplicacao then
			return
		end

		local acumulado = self._acumulador
		self._acumulador = 0
		self:_avancar(acumulado * ConfiguracaoTempo.MinutosJogoPorSegundoReal)
	end)
end

function ServicoTempoMundo:DefinirPausa(pausado)
	self:Iniciar()
	local estado = pausado == true
	self._pausado = estado
	local valores = self:_garantirEstado()
	valores.Pausado.Value = estado
	valores.Pasta:SetAttribute("TempoPausado", estado)
	return true, if estado then "Tempo pausado" else "Tempo retomado"
end

function ServicoTempoMundo:AlternarPausa()
	return self:DefinirPausa(not self._pausado)
end

function ServicoTempoMundo:EstaPausado()
	return self._pausado
end

function ServicoTempoMundo:DefinirDuracaoTransicao(duracao)
	self:Iniciar()
	local valor = math.max(tonumber(duracao) or 0, 0)
	local valores = self:_garantirEstado()
	valores.DuracaoTransicao.Value = valor
	return true, "Duracao de transicao definida para " .. tostring(valor)
end

function ServicoTempoMundo:DefinirHorario(valorHorario)
	self:Iniciar()
	local minutos = ConfiguracaoTempo.ConverterHorario(valorHorario)
	if not minutos then
		return false, "Horario invalido"
	end
	self._minutos = minutos
	self:_replicar()
	return true, "Horario definido para " .. ConfiguracaoTempo.FormatarHora(minutos)
end

function ServicoTempoMundo:AvancarMinutos(minutos)
	self:Iniciar()
	local delta = tonumber(minutos) or 0
	self:_avancar(delta)
	return true, "Tempo avancado em " .. tostring(math.floor(delta + 0.5)) .. " minutos"
end

function ServicoTempoMundo:ObterEstado()
	self:Iniciar()
	return {
		minutosDoDia = self._minutos,
		horaTexto = ConfiguracaoTempo.FormatarHora(self._minutos),
		faseDia = ConfiguracaoTempo.ObterFase(self._minutos).id,
		dia = self._dia,
		semana = math.floor((self._dia - 1) / 7) + 1,
	}
end

return ServicoTempoMundo