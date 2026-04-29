--[[
    Script: Planice.luau
    Caminho: src/ReplicatedStorage/Mundo/Ambiente/Climas
    Responsabilidade: Define o perfil visual e atmosferico do clima de planice.
    Uso: ModuleScript; use require(caminho) para ler as tabelas e valores exportados.
    Nao faz: Nao executa comportamento sozinho; apenas fornece dados para outros scripts.
    Funcoes principais: transicao
]]
local function transicao(duracao, pesoClima)
	return {
		duracao = duracao,
		pesoClima = pesoClima,
		estilo = Enum.EasingStyle.Sine,
		direcao = Enum.EasingDirection.InOut,
	}
end

return {
	id = "Planice",
	nome = "Planicie",
	descricao = "Campos abertos, ceu amplo e leitura clara de dia/noite.",
	ordem = 1,
	ordemClimas = { "DiaLimpo", "ChuvaCalma", "ChuvaNormal", "Tempestade", "Nublado", "NeblinaBaixa" },
	base = {
		id = "BasePlanice",
		nome = "Base Planicie",
		pesoClima = 0.42,
		lighting = {
			Brightness = 2.1,
			ExposureCompensation = 0,
			Ambient = Color3.fromRGB(118, 118, 112),
			OutdoorAmbient = Color3.fromRGB(158, 164, 164),
			FogColor = Color3.fromRGB(218, 232, 246),
			FogStart = 0,
			FogEnd = 100000,
			EnvironmentDiffuseScale = 0.72,
			EnvironmentSpecularScale = 0.48,
		},
		efeitos = {
			Atmosphere = { Density = 0.14, Offset = 0.04, Color = Color3.fromRGB(218, 228, 242), Decay = Color3.fromRGB(122, 140, 162), Glare = 0.14, Haze = 0.35 },
			BloomEffect = { Enabled = true, Intensity = 0.04, Size = 18, Threshold = 1.35 },
			SunRaysEffect = { Enabled = true, Intensity = 0.08, Spread = 0.82 },
			DepthOfFieldEffect = { Enabled = false, FarIntensity = 0, FocusDistance = 180, InFocusRadius = 90, NearIntensity = 0 },
			ColorCorrectionEffect = { Enabled = true, Brightness = 0, Contrast = 0.02, Saturation = 0.02, TintColor = Color3.fromRGB(255, 255, 246) },
		},
		clouds = { Enabled = true, Cover = 0.22, Density = 0.12, Color = Color3.fromRGB(248, 250, 255) },
	},
	climas = {
		DiaLimpo = {
			id = "DiaLimpo",
			nome = "Dia Limpo",
			descricao = "Clima padrao do mundo.",
			pesoClima = 0.54,
			transicao = transicao(5, 0.54),
			lighting = { Brightness = 2.25, ExposureCompensation = 0, FogEnd = 100000 },
			efeitos = {
				Atmosphere = { Density = 0.12, Offset = 0.04, Glare = 0.16, Haze = 0.25 },
				SunRaysEffect = { Enabled = true, Intensity = 0.1, Spread = 0.8 },
			},
			clouds = { Enabled = true, Cover = 0.18, Density = 0.08, Color = Color3.fromRGB(255, 255, 255) },
		},
		ChuvaCalma = {
			id = "ChuvaCalma",
			nome = "Chuva Calma",
			pesoClima = 0.68,
			transicao = transicao(8, 0.68),
			lighting = { Brightness = 1.45, ExposureCompensation = -0.12, Ambient = Color3.fromRGB(88, 94, 100), OutdoorAmbient = Color3.fromRGB(116, 124, 130), FogColor = Color3.fromRGB(164, 174, 182), FogStart = 30, FogEnd = 900 },
			efeitos = {
				Atmosphere = { Density = 0.32, Offset = 0.1, Color = Color3.fromRGB(174, 186, 194), Decay = Color3.fromRGB(90, 104, 116), Glare = 0.03, Haze = 1.45 },
				BloomEffect = { Enabled = true, Intensity = 0.03, Size = 18, Threshold = 1.5 },
				SunRaysEffect = { Enabled = true, Intensity = 0.02, Spread = 0.9 },
			},
			clouds = { Enabled = true, Cover = 0.68, Density = 0.45, Color = Color3.fromRGB(150, 158, 166) },
		},
		ChuvaNormal = {
			id = "ChuvaNormal",
			nome = "Chuva Normal",
			pesoClima = 0.76,
			transicao = transicao(9, 0.76),
			lighting = { Brightness = 1.05, ExposureCompensation = -0.22, Ambient = Color3.fromRGB(72, 80, 88), OutdoorAmbient = Color3.fromRGB(92, 104, 114), FogColor = Color3.fromRGB(128, 140, 150), FogStart = 18, FogEnd = 520 },
			efeitos = {
				Atmosphere = { Density = 0.42, Offset = 0.14, Color = Color3.fromRGB(150, 164, 174), Decay = Color3.fromRGB(62, 76, 88), Glare = 0, Haze = 2.0 },
				BloomEffect = { Enabled = true, Intensity = 0.025, Size = 16, Threshold = 1.55 },
				SunRaysEffect = { Enabled = true, Intensity = 0.01, Spread = 0.95 },
			},
			clouds = { Enabled = true, Cover = 0.84, Density = 0.65, Color = Color3.fromRGB(108, 118, 128) },
		},
		Tempestade = {
			id = "Tempestade",
			nome = "Tempestade",
			pesoClima = 0.88,
			transicao = transicao(10, 0.88),
			lighting = { Brightness = 0.72, ExposureCompensation = -0.4, Ambient = Color3.fromRGB(48, 56, 66), OutdoorAmbient = Color3.fromRGB(58, 68, 82), FogColor = Color3.fromRGB(76, 88, 104), FogStart = 10, FogEnd = 360 },
			efeitos = {
				Atmosphere = { Density = 0.58, Offset = 0.18, Color = Color3.fromRGB(104, 116, 132), Decay = Color3.fromRGB(34, 42, 56), Glare = 0, Haze = 2.8 },
				BloomEffect = { Enabled = true, Intensity = 0.015, Size = 12, Threshold = 1.7 },
				SunRaysEffect = { Enabled = false, Intensity = 0, Spread = 1 },
			},
			clouds = { Enabled = true, Cover = 1, Density = 0.88, Color = Color3.fromRGB(58, 66, 78) },
		},
		Nublado = {
			id = "Nublado",
			nome = "Nublado",
			pesoClima = 0.62,
			transicao = transicao(7, 0.62),
			lighting = { Brightness = 1.5, ExposureCompensation = -0.1, Ambient = Color3.fromRGB(94, 98, 104), OutdoorAmbient = Color3.fromRGB(126, 132, 138), FogColor = Color3.fromRGB(174, 184, 192), FogStart = 45, FogEnd = 1200 },
			efeitos = { Atmosphere = { Density = 0.28, Haze = 1.25, Glare = 0.04 }, SunRaysEffect = { Enabled = true, Intensity = 0.035, Spread = 0.9 } },
			clouds = { Enabled = true, Cover = 0.72, Density = 0.42, Color = Color3.fromRGB(170, 176, 184) },
		},
		NeblinaBaixa = {
			id = "NeblinaBaixa",
			nome = "Neblina Baixa",
			pesoClima = 0.7,
			transicao = transicao(9, 0.7),
			lighting = { Brightness = 1.25, ExposureCompensation = -0.08, FogColor = Color3.fromRGB(190, 202, 198), FogStart = 8, FogEnd = 220 },
			efeitos = { Atmosphere = { Density = 0.56, Offset = 0.2, Color = Color3.fromRGB(196, 210, 206), Decay = Color3.fromRGB(84, 98, 100), Glare = 0.02, Haze = 3.1 } },
			clouds = { Enabled = true, Cover = 0.54, Density = 0.32, Color = Color3.fromRGB(198, 206, 208) },
		},
	},
}
