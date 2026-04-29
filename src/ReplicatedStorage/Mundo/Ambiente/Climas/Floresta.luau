--[[
    Script: Floresta.luau
    Caminho: src/ReplicatedStorage/Mundo/Ambiente/Climas
    Responsabilidade: Define o perfil visual e atmosferico do clima de floresta.
    Uso: ModuleScript; use require(caminho) para ler as tabelas e valores exportados.
    Nao faz: Nao executa comportamento sozinho; apenas fornece dados para outros scripts.
    Funcoes principais: transicao
]]
local function transicao(duracao, pesoClima)
	return { duracao = duracao, pesoClima = pesoClima, estilo = Enum.EasingStyle.Sine, direcao = Enum.EasingDirection.InOut }
end

return {
	id = "Floresta",
	nome = "Floresta",
	descricao = "Copa fechada, sombras verdes e clima mais abafado.",
	ordem = 3,
	ordemClimas = { "DiaLimpo", "ChuvaCalma", "ChuvaNormal", "Tempestade", "Neblina", "CopaSombria" },
	base = {
		id = "BaseFloresta",
		nome = "Base Floresta",
		pesoClima = 0.56,
		lighting = { Brightness = 1.72, ExposureCompensation = -0.08, Ambient = Color3.fromRGB(68, 84, 64), OutdoorAmbient = Color3.fromRGB(88, 116, 82), FogColor = Color3.fromRGB(146, 172, 138), FogStart = 26, FogEnd = 900, EnvironmentDiffuseScale = 0.52, EnvironmentSpecularScale = 0.32 },
		efeitos = {
			Atmosphere = { Density = 0.26, Offset = 0.08, Color = Color3.fromRGB(168, 196, 156), Decay = Color3.fromRGB(48, 72, 52), Glare = 0.06, Haze = 1.25 },
			BloomEffect = { Enabled = true, Intensity = 0.05, Size = 24, Threshold = 1.35 },
			SunRaysEffect = { Enabled = true, Intensity = 0.06, Spread = 0.72 },
			DepthOfFieldEffect = { Enabled = false, FarIntensity = 0, FocusDistance = 140, InFocusRadius = 80, NearIntensity = 0 },
			ColorCorrectionEffect = { Enabled = true, Brightness = -0.01, Contrast = 0.04, Saturation = 0.02, TintColor = Color3.fromRGB(230, 250, 220) },
		},
		clouds = { Enabled = true, Cover = 0.34, Density = 0.24, Color = Color3.fromRGB(218, 230, 218) },
	},
	climas = {
		DiaLimpo = { id = "DiaLimpo", nome = "Dia Limpo", pesoClima = 0.56, transicao = transicao(6, 0.56), lighting = { Brightness = 1.9, FogEnd = 1200 }, efeitos = { Atmosphere = { Density = 0.22, Haze = 0.9 }, SunRaysEffect = { Enabled = true, Intensity = 0.08, Spread = 0.68 } }, clouds = { Enabled = true, Cover = 0.26, Density = 0.16, Color = Color3.fromRGB(236, 246, 236) } },
		ChuvaCalma = { id = "ChuvaCalma", nome = "Chuva Calma", pesoClima = 0.74, transicao = transicao(8, 0.74), lighting = { Brightness = 1.16, ExposureCompensation = -0.18, FogStart = 18, FogEnd = 560, FogColor = Color3.fromRGB(116, 142, 128) }, efeitos = { Atmosphere = { Density = 0.42, Haze = 2.35, Color = Color3.fromRGB(136, 164, 146), Decay = Color3.fromRGB(44, 64, 52), Glare = 0.01 }, SunRaysEffect = { Enabled = true, Intensity = 0.018, Spread = 0.9 } }, clouds = { Enabled = true, Cover = 0.76, Density = 0.54, Color = Color3.fromRGB(116, 132, 124) } },
		ChuvaNormal = { id = "ChuvaNormal", nome = "Chuva Normal", pesoClima = 0.82, transicao = transicao(9, 0.82), lighting = { Brightness = 0.86, ExposureCompensation = -0.3, Ambient = Color3.fromRGB(42, 58, 50), OutdoorAmbient = Color3.fromRGB(56, 78, 66), FogStart = 10, FogEnd = 340, FogColor = Color3.fromRGB(82, 108, 96) }, efeitos = { Atmosphere = { Density = 0.58, Haze = 3.3, Color = Color3.fromRGB(102, 128, 116), Decay = Color3.fromRGB(28, 44, 36), Glare = 0 } }, clouds = { Enabled = true, Cover = 0.9, Density = 0.74, Color = Color3.fromRGB(74, 86, 80) } },
		Tempestade = { id = "Tempestade", nome = "Tempestade", pesoClima = 0.9, transicao = transicao(10, 0.9), lighting = { Brightness = 0.52, ExposureCompensation = -0.5, Ambient = Color3.fromRGB(28, 38, 36), OutdoorAmbient = Color3.fromRGB(36, 50, 46), FogStart = 6, FogEnd = 220, FogColor = Color3.fromRGB(52, 70, 66) }, efeitos = { Atmosphere = { Density = 0.72, Haze = 4.2, Color = Color3.fromRGB(70, 90, 84), Decay = Color3.fromRGB(16, 26, 24), Glare = 0 }, SunRaysEffect = { Enabled = false, Intensity = 0, Spread = 1 } }, clouds = { Enabled = true, Cover = 1, Density = 0.92, Color = Color3.fromRGB(42, 50, 50) } },
		Neblina = { id = "Neblina", nome = "Neblina", pesoClima = 0.76, transicao = transicao(9, 0.76), lighting = { Brightness = 1.05, ExposureCompensation = -0.12, FogStart = 4, FogEnd = 170, FogColor = Color3.fromRGB(162, 184, 174) }, efeitos = { Atmosphere = { Density = 0.68, Offset = 0.23, Haze = 4.4, Color = Color3.fromRGB(170, 196, 184), Decay = Color3.fromRGB(48, 70, 62), Glare = 0.01 } }, clouds = { Enabled = true, Cover = 0.6, Density = 0.42, Color = Color3.fromRGB(170, 186, 180) } },
		CopaSombria = { id = "CopaSombria", nome = "Copa Sombria", pesoClima = 0.7, transicao = transicao(7, 0.7), lighting = { Brightness = 1.0, ExposureCompensation = -0.25, Ambient = Color3.fromRGB(40, 58, 44), OutdoorAmbient = Color3.fromRGB(54, 76, 58), FogStart = 20, FogEnd = 700 }, efeitos = { Atmosphere = { Density = 0.36, Haze = 1.8 }, ColorCorrectionEffect = { Enabled = true, Brightness = -0.04, Contrast = 0.08, Saturation = -0.02, TintColor = Color3.fromRGB(210, 240, 204) } }, clouds = { Enabled = true, Cover = 0.48, Density = 0.3, Color = Color3.fromRGB(134, 150, 132) } },
	},
}
