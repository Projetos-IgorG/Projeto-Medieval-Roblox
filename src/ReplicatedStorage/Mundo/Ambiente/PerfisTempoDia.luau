--[[
    Script: PerfisTempoDia.luau
    Caminho: src/ReplicatedStorage/Mundo/Ambiente
    Responsabilidade: Define perfis de luz e atmosfera para periodos do dia.
    Uso: ModuleScript; use require(caminho) para ler as tabelas e valores exportados.
    Nao faz: Nao executa comportamento sozinho; apenas fornece dados para outros scripts.
    Funcoes principais: ObterPerfil, frame, copiar, interpolarValor, obterIntervalo
]]
local ConfiguracaoTempo = require(script.Parent:WaitForChild("ConfiguracaoTempo"))

local PerfisTempoDia = {}

local function frame(minuto, nome, lighting, efeitos, clouds)
	return {
		minuto = minuto,
		nome = nome,
		lighting = lighting,
		efeitos = efeitos,
		clouds = clouds,
	}
end

PerfisTempoDia.Keyframes = table.freeze({
	frame(0, "Noite", {
		Brightness = 0.42,
		ExposureCompensation = -0.5,
		Ambient = Color3.fromRGB(30, 36, 54),
		OutdoorAmbient = Color3.fromRGB(20, 28, 48),
		FogColor = Color3.fromRGB(34, 42, 62),
		FogStart = 20,
		FogEnd = 520,
		EnvironmentDiffuseScale = 0.25,
		EnvironmentSpecularScale = 0.25,
	}, {
		Atmosphere = { Density = 0.32, Offset = 0.05, Color = Color3.fromRGB(70, 86, 120), Decay = Color3.fromRGB(18, 24, 42), Glare = 0, Haze = 1.2 },
		BloomEffect = { Enabled = true, Intensity = 0.05, Size = 18, Threshold = 1.45 },
		SunRaysEffect = { Enabled = true, Intensity = 0.01, Spread = 0.8 },
		DepthOfFieldEffect = { Enabled = false, FarIntensity = 0, FocusDistance = 160, InFocusRadius = 80, NearIntensity = 0 },
	}, { Enabled = true, Cover = 0.32, Density = 0.18, Color = Color3.fromRGB(62, 72, 96) }),

	frame(5 * 60, "Amanhecer", {
		Brightness = 0.72,
		ExposureCompensation = -0.22,
		Ambient = Color3.fromRGB(72, 64, 76),
		OutdoorAmbient = Color3.fromRGB(92, 82, 88),
		FogColor = Color3.fromRGB(162, 132, 118),
		FogStart = 18,
		FogEnd = 720,
		EnvironmentDiffuseScale = 0.35,
		EnvironmentSpecularScale = 0.3,
	}, {
		Atmosphere = { Density = 0.25, Offset = 0.08, Color = Color3.fromRGB(220, 168, 134), Decay = Color3.fromRGB(92, 88, 112), Glare = 0.12, Haze = 1.0 },
		BloomEffect = { Enabled = true, Intensity = 0.08, Size = 24, Threshold = 1.25 },
		SunRaysEffect = { Enabled = true, Intensity = 0.08, Spread = 0.75 },
		DepthOfFieldEffect = { Enabled = false, FarIntensity = 0, FocusDistance = 160, InFocusRadius = 80, NearIntensity = 0 },
	}, { Enabled = true, Cover = 0.28, Density = 0.18, Color = Color3.fromRGB(190, 160, 144) }),

	frame(7 * 60, "Dia", {
		Brightness = 2.25,
		ExposureCompensation = 0,
		Ambient = Color3.fromRGB(120, 120, 118),
		OutdoorAmbient = Color3.fromRGB(160, 165, 168),
		FogColor = Color3.fromRGB(220, 232, 255),
		FogStart = 0,
		FogEnd = 100000,
		EnvironmentDiffuseScale = 0.72,
		EnvironmentSpecularScale = 0.55,
	}, {
		Atmosphere = { Density = 0.13, Offset = 0.04, Color = Color3.fromRGB(218, 228, 244), Decay = Color3.fromRGB(125, 142, 168), Glare = 0.16, Haze = 0.35 },
		BloomEffect = { Enabled = true, Intensity = 0.05, Size = 18, Threshold = 1.35 },
		SunRaysEffect = { Enabled = true, Intensity = 0.08, Spread = 0.8 },
		DepthOfFieldEffect = { Enabled = false, FarIntensity = 0, FocusDistance = 180, InFocusRadius = 90, NearIntensity = 0 },
	}, { Enabled = true, Cover = 0.24, Density = 0.14, Color = Color3.fromRGB(245, 248, 255) }),

	frame(17 * 60, "Anoitecer", {
		Brightness = 1.45,
		ExposureCompensation = -0.08,
		Ambient = Color3.fromRGB(126, 94, 72),
		OutdoorAmbient = Color3.fromRGB(168, 118, 86),
		FogColor = Color3.fromRGB(230, 156, 108),
		FogStart = 15,
		FogEnd = 900,
		EnvironmentDiffuseScale = 0.48,
		EnvironmentSpecularScale = 0.38,
	}, {
		Atmosphere = { Density = 0.22, Offset = 0.08, Color = Color3.fromRGB(240, 174, 114), Decay = Color3.fromRGB(110, 78, 76), Glare = 0.2, Haze = 1.1 },
		BloomEffect = { Enabled = true, Intensity = 0.1, Size = 28, Threshold = 1.2 },
		SunRaysEffect = { Enabled = true, Intensity = 0.13, Spread = 0.7 },
		DepthOfFieldEffect = { Enabled = false, FarIntensity = 0, FocusDistance = 160, InFocusRadius = 80, NearIntensity = 0 },
	}, { Enabled = true, Cover = 0.38, Density = 0.22, Color = Color3.fromRGB(228, 168, 130) }),

	frame(21 * 60, "Noite", {
		Brightness = 0.5,
		ExposureCompensation = -0.42,
		Ambient = Color3.fromRGB(42, 48, 68),
		OutdoorAmbient = Color3.fromRGB(30, 38, 58),
		FogColor = Color3.fromRGB(42, 52, 78),
		FogStart = 22,
		FogEnd = 620,
		EnvironmentDiffuseScale = 0.28,
		EnvironmentSpecularScale = 0.28,
	}, {
		Atmosphere = { Density = 0.3, Offset = 0.05, Color = Color3.fromRGB(80, 96, 130), Decay = Color3.fromRGB(24, 30, 48), Glare = 0, Haze = 1.15 },
		BloomEffect = { Enabled = true, Intensity = 0.05, Size = 18, Threshold = 1.45 },
		SunRaysEffect = { Enabled = true, Intensity = 0.01, Spread = 0.8 },
		DepthOfFieldEffect = { Enabled = false, FarIntensity = 0, FocusDistance = 160, InFocusRadius = 80, NearIntensity = 0 },
	}, { Enabled = true, Cover = 0.34, Density = 0.2, Color = Color3.fromRGB(70, 82, 108) }),
})

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

local function interpolarValor(a, b, alpha)
	if a == nil then
		return copiar(b)
	end
	if b == nil then
		return copiar(a)
	end
	if type(a) == "number" and type(b) == "number" then
		return a + (b - a) * alpha
	end
	if typeof(a) == "Color3" and typeof(b) == "Color3" then
		return a:Lerp(b, alpha)
	end
	if type(a) == "table" and type(b) == "table" then
		local resultado = {}
		for chave, valor in a do
			resultado[chave] = interpolarValor(valor, b[chave], alpha)
		end
		for chave, valor in b do
			if resultado[chave] == nil then
				resultado[chave] = interpolarValor(a[chave], valor, alpha)
			end
		end
		return resultado
	end
	return copiar(if alpha >= 0.5 then b else a)
end

local function obterIntervalo(minutos: number)
	local normalizado = ConfiguracaoTempo.NormalizarMinutos(minutos)
	local frames = PerfisTempoDia.Keyframes
	for i = 1, #frames - 1 do
		local atual = frames[i]
		local proximo = frames[i + 1]
		if normalizado >= atual.minuto and normalizado < proximo.minuto then
			return atual, proximo, (normalizado - atual.minuto) / (proximo.minuto - atual.minuto)
		end
	end

	local ultimo = frames[#frames]
	local primeiro = frames[1]
	local fimDia = ConfiguracaoTempo.MinutosPorDia
	local distancia = (fimDia - ultimo.minuto) + primeiro.minuto
	local progresso = if normalizado >= ultimo.minuto
		then (normalizado - ultimo.minuto) / distancia
		else ((fimDia - ultimo.minuto) + normalizado) / distancia
	return ultimo, primeiro, progresso
end

function PerfisTempoDia.ObterPerfil(minutos: number)
	local atual, proximo, alpha = obterIntervalo(minutos)
	local fase = ConfiguracaoTempo.ObterFase(minutos)
	local perfil = {
		nome = fase.nome,
		faseDia = fase.id,
		lighting = interpolarValor(atual.lighting, proximo.lighting, alpha),
		efeitos = interpolarValor(atual.efeitos, proximo.efeitos, alpha),
		clouds = interpolarValor(atual.clouds, proximo.clouds, alpha),
	}
	return perfil
end

return PerfisTempoDia
