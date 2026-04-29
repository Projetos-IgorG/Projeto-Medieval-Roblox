local Lighting = game:GetService("Lighting")

local TiposAmbiente = require(script.Parent:WaitForChild("TiposAmbiente"))

local ExtratorAmbiente = {}

local PROPRIEDADES_EFEITOS = {
	Atmosphere = { "Density", "Offset", "Color", "Decay", "Glare", "Haze" },
	BloomEffect = { "Enabled", "Intensity", "Size", "Threshold" },
	DepthOfFieldEffect = { "Enabled", "FarIntensity", "FocusDistance", "InFocusRadius", "NearIntensity" },
	SunRaysEffect = { "Enabled", "Intensity", "Spread" },
	ColorCorrectionEffect = { "Enabled", "Brightness", "Contrast", "Saturation", "TintColor" },
}

local function arredondar(numero: number): number
	return math.floor(numero * 1000 + 0.5) / 1000
end

local function valorParaCodigo(valor): string
	local tipo = typeof(valor)
	if tipo == "Color3" then
		return string.format(
			"Color3.fromRGB(%d, %d, %d)",
			math.floor(valor.R * 255 + 0.5),
			math.floor(valor.G * 255 + 0.5),
			math.floor(valor.B * 255 + 0.5)
		)
	elseif tipo == "string" then
		return string.format("%q", valor)
	elseif tipo == "number" then
		return tostring(arredondar(valor))
	elseif tipo == "boolean" then
		return tostring(valor)
	end
	return "nil"
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

local function escreverTabela(linhas, nome: string, tabela, indent: string)
	table.insert(linhas, indent .. nome .. " = {")
	local chaves = {}
	for chave in tabela do
		table.insert(chaves, chave)
	end
	table.sort(chaves, function(a, b)
		return tostring(a) < tostring(b)
	end)
	for _, chave in ipairs(chaves) do
		local valor = tabela[chave]
		if type(valor) == "table" and typeof(valor) ~= "Color3" then
			escreverTabela(linhas, tostring(chave), valor, indent .. "\t")
		else
			table.insert(linhas, indent .. "\t" .. tostring(chave) .. " = " .. valorParaCodigo(valor) .. ",")
		end
	end
	table.insert(linhas, indent .. "},")
end

function ExtratorAmbiente.CapturarAtual()
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

function ExtratorAmbiente.GerarClima(id: string?, nome: string?)
	local captura = ExtratorAmbiente.CapturarAtual()
	local linhas = {
		"{",
		"\tid = " .. valorParaCodigo(id or "ClimaExtraido") .. ",",
		"\tnome = " .. valorParaCodigo(nome or "Clima Extraido") .. ",",
		"\tpesoClima = 0.72,",
		"\ttransicao = { duracao = 20, pesoClima = 0.72 },",
	}
	escreverTabela(linhas, "lighting", captura.lighting, "\t")
	escreverTabela(linhas, "efeitos", captura.efeitos, "\t")
	escreverTabela(linhas, "clouds", captura.clouds, "\t")
	table.insert(linhas, "}")
	return table.concat(linhas, "\n")
end

function ExtratorAmbiente.GerarAmbiente(id: string?, nome: string?)
	local clima = ExtratorAmbiente.GerarClima("DiaLimpo", "Dia Limpo")
	return table.concat({
		"return {",
		"\tid = " .. valorParaCodigo(id or "AmbienteExtraido") .. ",",
		"\tnome = " .. valorParaCodigo(nome or "Ambiente Extraido") .. ",",
		"\tordem = 99,",
		"\tordemClimas = { \"DiaLimpo\" },",
		"\tbase = nil,",
		"\tclimas = {",
		"\t\tDiaLimpo = " .. clima:gsub("\n", "\n\t\t"),
		"\t},",
		"}",
	}, "\n")
end

function ExtratorAmbiente.ImprimirClima(id: string?, nome: string?)
	local codigo = ExtratorAmbiente.GerarClima(id, nome)
	print("[ExtratorAmbiente] Clima extraido:\n" .. codigo)
	return codigo
end

function ExtratorAmbiente.ImprimirAmbiente(id: string?, nome: string?)
	local codigo = ExtratorAmbiente.GerarAmbiente(id, nome)
	print("[ExtratorAmbiente] Ambiente extraido:\n" .. codigo)
	return codigo
end

return ExtratorAmbiente