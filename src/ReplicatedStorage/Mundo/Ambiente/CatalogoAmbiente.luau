local Lighting = game:GetService("Lighting")

local TiposAmbiente = require(script.Parent:WaitForChild("TiposAmbiente"))
local ClimasFolder = script.Parent:WaitForChild("Climas")

local CatalogoAmbiente = {}

CatalogoAmbiente.AmbientePadrao = "Planice"
CatalogoAmbiente.ClimaPadrao = "DiaLimpo"

CatalogoAmbiente.Periodos = table.freeze({
	{ id = "Dia", nome = "Dia", horario = "12:00", ordem = 1 },
	{ id = "Noite", nome = "Noite", horario = "00:00", ordem = 2 },
	{ id = "Amanhecer", nome = "Amanhecer", horario = "06:00", ordem = 3 },
	{ id = "Anoitecer", nome = "Anoitecer", horario = "18:30", ordem = 4 },
})

CatalogoAmbiente.Condicoes = table.freeze({
	{ id = "Limpo", nome = "Limpo", climaId = "DiaLimpo", ordem = 1 },
	{ id = "ChuvaCalma", nome = "Chuva Calma", climaId = "ChuvaCalma", ordem = 2 },
	{ id = "ChuvaNormal", nome = "Chuva Normal", climaId = "ChuvaNormal", ordem = 3 },
	{ id = "Tempestade", nome = "Tempestade", climaId = "Tempestade", ordem = 4 },
})

local Ambientes = {
	Planice = require(ClimasFolder:WaitForChild("Planice")),
	Pantano = require(ClimasFolder:WaitForChild("Pantano")),
	Floresta = require(ClimasFolder:WaitForChild("Floresta")),
	Neve = require(ClimasFolder:WaitForChild("Neve")),
	Areia = require(ClimasFolder:WaitForChild("Areia")),
}

CatalogoAmbiente.Ambientes = Ambientes

local PROPRIEDADES_EFEITOS = {
	Atmosphere = { "Density", "Offset", "Color", "Decay", "Glare", "Haze" },
	BloomEffect = { "Enabled", "Intensity", "Size", "Threshold" },
	DepthOfFieldEffect = { "Enabled", "FarIntensity", "FocusDistance", "InFocusRadius", "NearIntensity" },
	SunRaysEffect = { "Enabled", "Intensity", "Spread" },
	ColorCorrectionEffect = { "Enabled", "Brightness", "Contrast", "Saturation", "TintColor" },
}

local function copiar(valor)
	if type(valor) ~= "table" then
		return valor
	end

	local novo = {}
	for chave, item in valor do
		novo[chave] = copiar(item)
	end
	return novo
end

local function mesclar(base, sobre)
	local resultado = copiar(base or {})
	for chave, valor in sobre or {} do
		if type(valor) == "table" and type(resultado[chave]) == "table" then
			resultado[chave] = mesclar(resultado[chave], valor)
		else
			resultado[chave] = copiar(valor)
		end
	end
	return resultado
end

local function capturarPropriedades(instancia: Instance?, propriedades)
	local resultado = {}
	if not instancia then
		return resultado
	end

	for _, propriedade in ipairs(propriedades) do
		local ok, valor = pcall(function()
			return instancia[propriedade]
		end)
		if ok then
			resultado[propriedade] = valor
		end
	end
	return resultado
end

local function capturarVisualInicial()
	local captura = {
		lighting = capturarPropriedades(Lighting, TiposAmbiente.PropriedadesLighting),
		efeitos = {},
		clouds = {},
	}

	for _, className in ipairs(TiposAmbiente.EfeitosSuportados) do
		local efeito = Lighting:FindFirstChildOfClass(className)
		if efeito then
			captura.efeitos[className] = capturarPropriedades(efeito, PROPRIEDADES_EFEITOS[className] or {})
		end
	end

	local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
	if clouds then
		captura.clouds = capturarPropriedades(clouds, TiposAmbiente.PropriedadesClouds)
	end

	return captura
end

local function aplicarDiaLimpoInicial()
	local ambientePadrao = Ambientes[CatalogoAmbiente.AmbientePadrao]
	if not ambientePadrao or not ambientePadrao.climas or not ambientePadrao.climas[CatalogoAmbiente.ClimaPadrao] then
		return
	end

	local captura = capturarVisualInicial()
	local climaPadrao = ambientePadrao.climas[CatalogoAmbiente.ClimaPadrao]

	climaPadrao.lighting = captura.lighting
	climaPadrao.efeitos = captura.efeitos
	climaPadrao.clouds = captura.clouds
	climaPadrao.pesoClima = climaPadrao.pesoClima or 0.82
	climaPadrao.transicao = mesclar({ duracao = 5, pesoClima = climaPadrao.pesoClima }, climaPadrao.transicao or {})
	climaPadrao.descricao = "Visual capturado do Lighting inicial do mundo."

	ambientePadrao.base = mesclar(ambientePadrao.base or {}, {})
	ambientePadrao.base.lighting = captura.lighting
	ambientePadrao.base.efeitos = captura.efeitos
	ambientePadrao.base.clouds = captura.clouds
	CatalogoAmbiente.DiaLimpoCapturado = true
end

aplicarDiaLimpoInicial()

local function normalizar(texto: any): string
	return string.lower(tostring(texto or "")):gsub("%s+", "")
end

local function encontrarChave(tabela, valor)
	local termo = normalizar(valor)
	if termo == "" then
		return nil
	end
	for chave, item in tabela do
		if normalizar(chave) == termo or normalizar(item.nome) == termo or normalizar(item.id) == termo then
			return chave
		end
	end
	for chave, item in tabela do
		if string.find(normalizar(chave), termo, 1, true) or string.find(normalizar(item.nome), termo, 1, true) then
			return chave
		end
	end
	return nil
end

local function encontrarItem(lista, valor)
	local termo = normalizar(valor)
	for _, item in ipairs(lista) do
		if normalizar(item.id) == termo or normalizar(item.nome) == termo then
			return item
		end
	end
	return nil
end

function CatalogoAmbiente.ObterAmbiente(ambienteId: any)
	local chave = encontrarChave(Ambientes, ambienteId) or CatalogoAmbiente.AmbientePadrao
	return Ambientes[chave], chave
end

function CatalogoAmbiente.ObterClima(ambienteId: any, climaId: any)
	local ambiente, chaveAmbiente = CatalogoAmbiente.ObterAmbiente(ambienteId)
	local chaveClima = encontrarChave(ambiente.climas, climaId) or CatalogoAmbiente.ClimaPadrao
	if not ambiente.climas[chaveClima] then
		local ordem = ambiente.ordemClimas
		chaveClima = ordem and ordem[1] or next(ambiente.climas)
	end
	return ambiente.climas[chaveClima], chaveClima, ambiente, chaveAmbiente
end

function CatalogoAmbiente.Resolver(ambienteId: any, climaId: any)
	local clima, chaveClima, ambiente, chaveAmbiente = CatalogoAmbiente.ObterClima(ambienteId, climaId)
	return ambiente, clima, chaveAmbiente, chaveClima
end

function CatalogoAmbiente.ListarAmbientes()
	local lista = {}
	for chave, ambiente in Ambientes do
		table.insert(lista, {
			id = chave,
			nome = ambiente.nome,
			descricao = ambiente.descricao,
			ordem = ambiente.ordem or 999,
		})
	end
	table.sort(lista, function(a, b)
		if a.ordem == b.ordem then
			return a.nome < b.nome
		end
		return a.ordem < b.ordem
	end)
	return lista
end

function CatalogoAmbiente.ListarClimas(ambienteId: any)
	local ambiente, chaveAmbiente = CatalogoAmbiente.ObterAmbiente(ambienteId)
	local lista = {}
	local adicionados = {}

	for indice, chaveClima in ipairs(ambiente.ordemClimas or {}) do
		local clima = ambiente.climas[chaveClima]
		if clima then
			adicionados[chaveClima] = true
			table.insert(lista, {
				id = chaveClima,
				nome = clima.nome,
				descricao = clima.descricao,
				ordem = indice,
				ambienteId = chaveAmbiente,
			})
		end
	end

	for chaveClima, clima in ambiente.climas do
		if not adicionados[chaveClima] then
			table.insert(lista, {
				id = chaveClima,
				nome = clima.nome,
				descricao = clima.descricao,
				ordem = 999,
				ambienteId = chaveAmbiente,
			})
		end
	end

	table.sort(lista, function(a, b)
		if a.ordem == b.ordem then
			return a.nome < b.nome
		end
		return a.ordem < b.ordem
	end)

	return lista
end

function CatalogoAmbiente.ListarPeriodos()
	return copiar(CatalogoAmbiente.Periodos)
end

function CatalogoAmbiente.ListarCondicoes(ambienteId: any, _periodoId: any?)
	local lista = {}
	for _, condicao in ipairs(CatalogoAmbiente.Condicoes) do
		local clima, chaveClima = CatalogoAmbiente.ObterClima(ambienteId, condicao.climaId)
		table.insert(lista, {
			id = condicao.id,
			nome = condicao.nome,
			climaId = chaveClima,
			climaNome = clima.nome,
			ordem = condicao.ordem,
		})
	end
	return lista
end

function CatalogoAmbiente.ResolverPorPeriodo(ambienteId: any, periodoId: any, condicaoId: any)
	local periodo = encontrarItem(CatalogoAmbiente.Periodos, periodoId) or CatalogoAmbiente.Periodos[1]
	local condicao = encontrarItem(CatalogoAmbiente.Condicoes, condicaoId) or CatalogoAmbiente.Condicoes[1]
	local clima, chaveClima, ambiente, chaveAmbiente = CatalogoAmbiente.ObterClima(ambienteId, condicao.climaId)
	return ambiente, clima, chaveAmbiente, chaveClima, periodo, condicao
end

function CatalogoAmbiente.ObterPadrao()
	local ambiente, clima, ambienteId, climaId = CatalogoAmbiente.Resolver(
		CatalogoAmbiente.AmbientePadrao,
		CatalogoAmbiente.ClimaPadrao
	)
	return ambiente, clima, ambienteId, climaId
end

return CatalogoAmbiente