--[[
    Script: ServicoAmbienteMundo.luau
    Caminho: src/ServerScriptService/Mundo/Ambiente
    Responsabilidade: Controla o clima ativo do mundo e replica mudancas de ambiente.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao roda sozinho nem cria fluxo de jogo por conta propria; depende dos scripts que importam este modulo.
    Funcoes principais: _garantirEstado, Iniciar, DefinirAmbienteClima, ObterEstado, DefinirPausa, AlternarPausa
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CatalogoAmbiente = require(ReplicatedStorage:WaitForChild("Mundo"):WaitForChild("Ambiente"):WaitForChild("CatalogoAmbiente"))

local ServicoAmbienteMundo = {}

ServicoAmbienteMundo._iniciado = false
ServicoAmbienteMundo._valores = nil
ServicoAmbienteMundo._pausado = false

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

function ServicoAmbienteMundo:_garantirEstado()
	if self._valores then
		return self._valores
	end

	local _, clima, ambienteId, climaId = CatalogoAmbiente.ObterPadrao()
	local pasta = garantirPastaEstado()
	local transicaoPadrao = clima.transicao and clima.transicao.duracao or 6
	self._valores = {
		Pasta = pasta,
		AmbienteAtual = garantirValor(pasta, "StringValue", "AmbienteAtual", ambienteId),
		ClimaAtual = garantirValor(pasta, "StringValue", "ClimaAtual", climaId),
		TransicaoAtual = garantirValor(pasta, "NumberValue", "TransicaoAtual", transicaoPadrao),
		AmbienteAtualizadoEm = garantirValor(pasta, "NumberValue", "AmbienteAtualizadoEm", os.clock()),
		Pausado = garantirValor(pasta, "BoolValue", "AmbientePausado", self._pausado),
	}
	return self._valores
end

function ServicoAmbienteMundo:Iniciar()
	if self._iniciado then
		return
	end
	self._iniciado = true
	self:_garantirEstado()
end

function ServicoAmbienteMundo:DefinirAmbienteClima(ambienteId, climaId, duracao)
	self:Iniciar()
	local ambiente, clima, chaveAmbiente, chaveClima = CatalogoAmbiente.Resolver(ambienteId, climaId)
	if not ambiente or not clima then
		return false, "Ambiente ou clima invalido"
	end

	local valores = self:_garantirEstado()
	local transicao = tonumber(duracao) or (clima.transicao and clima.transicao.duracao) or 6
	valores.AmbienteAtual.Value = chaveAmbiente
	valores.ClimaAtual.Value = chaveClima
	valores.TransicaoAtual.Value = transicao
	valores.AmbienteAtualizadoEm.Value = os.clock()
	valores.Pasta:SetAttribute("AmbienteAtual", chaveAmbiente)
	valores.Pasta:SetAttribute("ClimaAtual", chaveClima)

	return true, string.format("Ambiente aplicado: %s / %s", ambiente.nome, clima.nome)
end

function ServicoAmbienteMundo:ObterEstado()
	self:Iniciar()
	local valores = self:_garantirEstado()
	return {
		ambiente = valores.AmbienteAtual.Value,
		clima = valores.ClimaAtual.Value,
		transicao = valores.TransicaoAtual.Value,
		pausado = valores.Pausado.Value,
	}
end

function ServicoAmbienteMundo:DefinirPausa(pausado)
	self:Iniciar()
	local estado = pausado == true
	self._pausado = estado
	local valores = self:_garantirEstado()
	valores.Pausado.Value = estado
	valores.Pasta:SetAttribute("AmbientePausado", estado)
	return true, if estado then "Ambiente pausado" else "Ambiente retomado"
end

function ServicoAmbienteMundo:AlternarPausa()
	return self:DefinirPausa(not self._pausado)
end

function ServicoAmbienteMundo:EstaPausado()
	return self._pausado
end

return ServicoAmbienteMundo
