--[[
    Script: Areia.luau
    Caminho: src/ReplicatedStorage/Mundo/Ambiente/Climas
    Responsabilidade: Define o perfil visual e atmosferico do clima de areia.
    Uso: ModuleScript; use require(caminho) para ler as tabelas e valores exportados.
    Nao faz: Nao executa comportamento sozinho; apenas fornece dados para outros scripts.
    Funcoes principais: transicao
]]
local function transicao(duracao, pesoClima)
	return { duracao = duracao, pesoClima = pesoClima, estilo = Enum.EasingStyle.Sine, direcao = Enum.EasingDirection.InOut }
end

return {
	id = "Areia",
	nome = "Areia",
	descricao = "Seco, quente, alto contraste e muita poeira no horizonte.",
	ordem = 5,
	ordemClimas = { "DiaLimpo", "ChuvaCalma", "ChuvaNormal", "Tempestade", "CalorSeco", "TempestadeAreia" },
	base = {
		id = "BaseAreia",
		nome = "Base Areia",
		pesoClima = 0.62,
		lighting = { Brightness = 2.45, ExposureCompensation = 0.04, Ambient = Color3.fromRGB(150, 126, 92), OutdoorAmbient = Color3.fromRGB(210, 176, 122), FogColor = Color3.fromRGB(236, 196, 132), FogStart = 30, FogEnd = 1400, EnvironmentDiffuseScale = 0.78, EnvironmentSpecularScale = 0.42 },
		efeitos = {
			Atmosphere = { Density = 0.24, Offset = 0.1, Color = Color3.fromRGB(238, 202, 144), Decay = Color3.fromRGB(150, 104, 68), Glare = 0.22, Haze = 1.55 },
			BloomEffect = { Enabled = true, Intensity = 0.08, Size = 30, Threshold = 1.18 },
			SunRaysEffect = { Enabled = true, Intensity = 0.12, Spread = 0.72 },
			DepthOfFieldEffect = { Enabled = false, FarIntensity = 0, FocusDistance = 180, InFocusRadius = 90, NearIntensity = 0 },
			ColorCorrectionEffect = { Enabled = true, Brightness = 0.02, Contrast = 0.05, Saturation = -0.02, TintColor = Color3.fromRGB(255, 232, 190) },
		},
		clouds = { Enabled = true, Cover = 0.18, Density = 0.12, Color = Color3.fromRGB(248, 224, 184) },
	},
	climas = {
		DiaLimpo = { id = "DiaLimpo", nome = "Dia Limpo", pesoClima = 0.58, transicao = transicao(6, 0.58), lighting = { Brightness = 2.7, ExposureCompensation = 0.08, FogEnd = 1800 }, efeitos = { Atmosphere = { Density = 0.2, Haze = 1.1, Glare = 0.26 }, SunRaysEffect = { Enabled = true, Intensity = 0.15, Spread = 0.68 } }, clouds = { Enabled = true, Cover = 0.1, Density = 0.06, Color = Color3.fromRGB(255, 240, 204) } },
		ChuvaCalma = { id = "ChuvaCalma", nome = "Chuva Rara", pesoClima = 0.68, transicao = transicao(8, 0.68), lighting = { Brightness = 1.55, ExposureCompensation = -0.12, Ambient = Color3.fromRGB(114, 100, 88), OutdoorAmbient = Color3.fromRGB(150, 134, 116), FogStart = 24, FogEnd = 620, FogColor = Color3.fromRGB(170, 152, 130) }, efeitos = { Atmosphere = { Density = 0.34, Haze = 2.2, Color = Color3.fromRGB(184, 166, 144), Decay = Color3.fromRGB(94, 76, 62), Glare = 0.02 } }, clouds = { Enabled = true, Cover = 0.64, Density = 0.42, Color = Color3.fromRGB(142, 130, 122) } },
		ChuvaNormal = { id = "ChuvaNormal", nome = "Chuva Pesada", pesoClima = 0.78, transicao = transicao(9, 0.78), lighting = { Brightness = 1.02, ExposureCompensation = -0.26, Ambient = Color3.fromRGB(78, 74, 72), OutdoorAmbient = Color3.fromRGB(102, 96, 90), FogStart = 14, FogEnd = 360, FogColor = Color3.fromRGB(112, 108, 104) }, efeitos = { Atmosphere = { Density = 0.48, Haze = 3.0, Color = Color3.fromRGB(132, 128, 122), Decay = Color3.fromRGB(54, 50, 48), Glare = 0 } }, clouds = { Enabled = true, Cover = 0.86, Density = 0.7, Color = Color3.fromRGB(88, 86, 86) } },
		Tempestade = { id = "Tempestade", nome = "Tempestade Seca", pesoClima = 0.86, transicao = transicao(10, 0.86), lighting = { Brightness = 0.78, ExposureCompensation = -0.36, Ambient = Color3.fromRGB(64, 58, 54), OutdoorAmbient = Color3.fromRGB(78, 70, 64), FogStart = 8, FogEnd = 260, FogColor = Color3.fromRGB(92, 82, 72) }, efeitos = { Atmosphere = { Density = 0.62, Haze = 4.0, Color = Color3.fromRGB(116, 100, 84), Decay = Color3.fromRGB(40, 32, 28), Glare = 0 }, SunRaysEffect = { Enabled = false, Intensity = 0, Spread = 1 } }, clouds = { Enabled = true, Cover = 0.94, Density = 0.82, Color = Color3.fromRGB(70, 62, 56) } },
		CalorSeco = { id = "CalorSeco", nome = "Calor Seco", pesoClima = 0.76, transicao = transicao(8, 0.76), lighting = { Brightness = 2.85, ExposureCompensation = 0.12, FogStart = 18, FogEnd = 760, FogColor = Color3.fromRGB(248, 204, 128) }, efeitos = { Atmosphere = { Density = 0.36, Haze = 3.2, Color = Color3.fromRGB(248, 210, 142), Decay = Color3.fromRGB(158, 92, 50), Glare = 0.3 }, BloomEffect = { Enabled = true, Intensity = 0.12, Size = 34, Threshold = 1.08 }, ColorCorrectionEffect = { Enabled = true, Brightness = 0.03, Contrast = 0.08, Saturation = -0.08, TintColor = Color3.fromRGB(255, 220, 170) } }, clouds = { Enabled = true, Cover = 0.22, Density = 0.18, Color = Color3.fromRGB(232, 194, 144) } },
		TempestadeAreia = { id = "TempestadeAreia", nome = "Tempestade de Areia", pesoClima = 0.94, transicao = transicao(12, 0.94), lighting = { Brightness = 0.95, ExposureCompensation = -0.22, Ambient = Color3.fromRGB(112, 82, 54), OutdoorAmbient = Color3.fromRGB(142, 100, 62), FogStart = 0, FogEnd = 85, FogColor = Color3.fromRGB(176, 124, 74) }, efeitos = { Atmosphere = { Density = 0.92, Offset = 0.3, Haze = 6.6, Color = Color3.fromRGB(210, 150, 88), Decay = Color3.fromRGB(110, 66, 36), Glare = 0.04 }, BloomEffect = { Enabled = true, Intensity = 0.05, Size = 26, Threshold = 1.4 }, DepthOfFieldEffect = { Enabled = true, FarIntensity = 0.28, FocusDistance = 70, InFocusRadius = 28, NearIntensity = 0.04 }, SunRaysEffect = { Enabled = false, Intensity = 0, Spread = 1 }, ColorCorrectionEffect = { Enabled = true, Brightness = -0.02, Contrast = 0.1, Saturation = -0.18, TintColor = Color3.fromRGB(236, 170, 104) } }, clouds = { Enabled = true, Cover = 1, Density = 1, Color = Color3.fromRGB(160, 112, 70) } },
	},
}
