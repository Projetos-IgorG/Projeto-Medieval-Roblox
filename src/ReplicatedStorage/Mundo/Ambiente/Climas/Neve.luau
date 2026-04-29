--[[
    Script: Neve.luau
    Caminho: src/ReplicatedStorage/Mundo/Ambiente/Climas
    Responsabilidade: Define o perfil visual e atmosferico do clima de neve.
    Uso: ModuleScript; use require(caminho) para ler as tabelas e valores exportados.
    Nao faz: Nao executa comportamento sozinho; apenas fornece dados para outros scripts.
    Funcoes principais: transicao
]]
local function transicao(duracao, pesoClima)
	return { duracao = duracao, pesoClima = pesoClima, estilo = Enum.EasingStyle.Sine, direcao = Enum.EasingDirection.InOut }
end

return {
	id = "Neve",
	nome = "Neve",
	descricao = "Frio, reflexivo e com contraste azulado.",
	ordem = 4,
	ordemClimas = { "DiaLimpo", "ChuvaCalma", "ChuvaNormal", "Tempestade", "Nevasca", "NoitePolar" },
	base = {
		id = "BaseNeve",
		nome = "Base Neve",
		pesoClima = 0.6,
		lighting = { Brightness = 2.35, ExposureCompensation = 0.05, Ambient = Color3.fromRGB(132, 146, 158), OutdoorAmbient = Color3.fromRGB(178, 194, 208), FogColor = Color3.fromRGB(220, 236, 248), FogStart = 22, FogEnd = 1100, EnvironmentDiffuseScale = 0.8, EnvironmentSpecularScale = 0.68 },
		efeitos = {
			Atmosphere = { Density = 0.22, Offset = 0.07, Color = Color3.fromRGB(222, 238, 252), Decay = Color3.fromRGB(122, 146, 176), Glare = 0.18, Haze = 0.8 },
			BloomEffect = { Enabled = true, Intensity = 0.08, Size = 26, Threshold = 1.2 },
			SunRaysEffect = { Enabled = true, Intensity = 0.09, Spread = 0.82 },
			DepthOfFieldEffect = { Enabled = false, FarIntensity = 0, FocusDistance = 180, InFocusRadius = 90, NearIntensity = 0 },
			ColorCorrectionEffect = { Enabled = true, Brightness = 0.01, Contrast = 0.03, Saturation = -0.08, TintColor = Color3.fromRGB(230, 244, 255) },
		},
		clouds = { Enabled = true, Cover = 0.36, Density = 0.24, Color = Color3.fromRGB(238, 244, 250) },
	},
	climas = {
		DiaLimpo = { id = "DiaLimpo", nome = "Dia Limpo", pesoClima = 0.58, transicao = transicao(7, 0.58), lighting = { Brightness = 2.55, ExposureCompensation = 0.08, FogEnd = 1600 }, efeitos = { Atmosphere = { Density = 0.18, Haze = 0.55, Glare = 0.22 }, BloomEffect = { Enabled = true, Intensity = 0.1, Size = 28, Threshold = 1.18 } }, clouds = { Enabled = true, Cover = 0.24, Density = 0.14, Color = Color3.fromRGB(255, 255, 255) } },
		ChuvaCalma = { id = "ChuvaCalma", nome = "Neve Fina", pesoClima = 0.72, transicao = transicao(9, 0.72), lighting = { Brightness = 1.45, ExposureCompensation = -0.1, FogStart = 12, FogEnd = 520, FogColor = Color3.fromRGB(198, 216, 228) }, efeitos = { Atmosphere = { Density = 0.42, Haze = 2.4, Color = Color3.fromRGB(210, 228, 240), Decay = Color3.fromRGB(108, 130, 154), Glare = 0.04 } }, clouds = { Enabled = true, Cover = 0.76, Density = 0.56, Color = Color3.fromRGB(196, 204, 214) } },
		ChuvaNormal = { id = "ChuvaNormal", nome = "Neve Forte", pesoClima = 0.82, transicao = transicao(10, 0.82), lighting = { Brightness = 1.0, ExposureCompensation = -0.24, Ambient = Color3.fromRGB(88, 104, 122), OutdoorAmbient = Color3.fromRGB(112, 132, 154), FogStart = 4, FogEnd = 260, FogColor = Color3.fromRGB(174, 194, 210) }, efeitos = { Atmosphere = { Density = 0.68, Haze = 4.2, Color = Color3.fromRGB(190, 210, 226), Decay = Color3.fromRGB(80, 100, 124), Glare = 0 } }, clouds = { Enabled = true, Cover = 0.92, Density = 0.82, Color = Color3.fromRGB(162, 174, 188) } },
		Tempestade = { id = "Tempestade", nome = "Tempestade Gelida", pesoClima = 0.9, transicao = transicao(11, 0.9), lighting = { Brightness = 0.62, ExposureCompensation = -0.45, Ambient = Color3.fromRGB(50, 64, 82), OutdoorAmbient = Color3.fromRGB(62, 78, 100), FogStart = 0, FogEnd = 160, FogColor = Color3.fromRGB(112, 132, 154) }, efeitos = { Atmosphere = { Density = 0.84, Haze = 5.4, Color = Color3.fromRGB(140, 162, 186), Decay = Color3.fromRGB(34, 46, 66), Glare = 0 }, SunRaysEffect = { Enabled = false, Intensity = 0, Spread = 1 } }, clouds = { Enabled = true, Cover = 1, Density = 0.96, Color = Color3.fromRGB(86, 100, 120) } },
		Nevasca = { id = "Nevasca", nome = "Nevasca", pesoClima = 0.94, transicao = transicao(12, 0.94), lighting = { Brightness = 0.78, ExposureCompensation = -0.38, Ambient = Color3.fromRGB(66, 82, 102), OutdoorAmbient = Color3.fromRGB(82, 102, 126), FogStart = 0, FogEnd = 90, FogColor = Color3.fromRGB(190, 206, 220) }, efeitos = { Atmosphere = { Density = 0.94, Offset = 0.3, Haze = 6.2, Color = Color3.fromRGB(210, 226, 238), Decay = Color3.fromRGB(62, 80, 104), Glare = 0 }, DepthOfFieldEffect = { Enabled = true, FarIntensity = 0.22, FocusDistance = 80, InFocusRadius = 36, NearIntensity = 0.05 } }, clouds = { Enabled = true, Cover = 1, Density = 1, Color = Color3.fromRGB(204, 212, 222) } },
		NoitePolar = { id = "NoitePolar", nome = "Noite Polar", pesoClima = 0.78, transicao = transicao(9, 0.78), lighting = { Brightness = 0.38, ExposureCompensation = -0.58, Ambient = Color3.fromRGB(28, 40, 66), OutdoorAmbient = Color3.fromRGB(24, 36, 64), FogStart = 8, FogEnd = 340, FogColor = Color3.fromRGB(62, 82, 122) }, efeitos = { Atmosphere = { Density = 0.42, Haze = 1.8, Color = Color3.fromRGB(84, 112, 158), Decay = Color3.fromRGB(14, 22, 46), Glare = 0 }, BloomEffect = { Enabled = true, Intensity = 0.04, Size = 18, Threshold = 1.55 } }, clouds = { Enabled = true, Cover = 0.58, Density = 0.36, Color = Color3.fromRGB(70, 86, 114) } },
	},
}
