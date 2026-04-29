--[[
    Script: Pantano.luau
    Caminho: src/ReplicatedStorage/Mundo/Ambiente/Climas
    Responsabilidade: Define o perfil visual e atmosferico do clima de pantano.
    Uso: ModuleScript; use require(caminho) para ler as tabelas e valores exportados.
    Nao faz: Nao executa comportamento sozinho; apenas fornece dados para outros scripts.
    Funcoes principais: transicao
]]
local function transicao(duracao, pesoClima)
	return { duracao = duracao, pesoClima = pesoClima, estilo = Enum.EasingStyle.Sine, direcao = Enum.EasingDirection.InOut }
end

return {
	id = "Pantano",
	nome = "Pantano",
	descricao = "Ar pesado, umido e esverdeado, com neblina frequente.",
	ordem = 2,
	ordemClimas = { "DiaLimpo", "ChuvaCalma", "ChuvaNormal", "Tempestade", "NeblinaDensa", "Mormaco" },
	base = {
		id = "BasePantano",
		nome = "Base Pantano",
		pesoClima = 0.58,
		lighting = { Brightness = 1.55, ExposureCompensation = -0.12, Ambient = Color3.fromRGB(74, 82, 68), OutdoorAmbient = Color3.fromRGB(92, 110, 84), FogColor = Color3.fromRGB(126, 146, 118), FogStart = 18, FogEnd = 620, EnvironmentDiffuseScale = 0.48, EnvironmentSpecularScale = 0.28 },
		efeitos = {
			Atmosphere = { Density = 0.38, Offset = 0.16, Color = Color3.fromRGB(146, 166, 132), Decay = Color3.fromRGB(50, 68, 54), Glare = 0.02, Haze = 2.2 },
			BloomEffect = { Enabled = true, Intensity = 0.035, Size = 22, Threshold = 1.45 },
			SunRaysEffect = { Enabled = true, Intensity = 0.035, Spread = 0.9 },
			DepthOfFieldEffect = { Enabled = false, FarIntensity = 0, FocusDistance = 120, InFocusRadius = 70, NearIntensity = 0 },
			ColorCorrectionEffect = { Enabled = true, Brightness = -0.02, Contrast = 0.03, Saturation = -0.08, TintColor = Color3.fromRGB(222, 240, 210) },
		},
		clouds = { Enabled = true, Cover = 0.56, Density = 0.38, Color = Color3.fromRGB(148, 164, 142) },
	},
	climas = {
		DiaLimpo = { id = "DiaLimpo", nome = "Dia Limpo", pesoClima = 0.6, transicao = transicao(7, 0.6), lighting = { Brightness = 1.7, FogStart = 22, FogEnd = 720 }, efeitos = { Atmosphere = { Density = 0.34, Haze = 1.8, Glare = 0.04 } }, clouds = { Enabled = true, Cover = 0.42, Density = 0.28, Color = Color3.fromRGB(180, 196, 174) } },
		ChuvaCalma = { id = "ChuvaCalma", nome = "Chuva Calma", pesoClima = 0.76, transicao = transicao(9, 0.76), lighting = { Brightness = 1.05, ExposureCompensation = -0.2, FogStart = 10, FogEnd = 420, FogColor = Color3.fromRGB(102, 128, 112) }, efeitos = { Atmosphere = { Density = 0.52, Haze = 3.0, Color = Color3.fromRGB(124, 150, 132), Decay = Color3.fromRGB(38, 58, 46), Glare = 0 } }, clouds = { Enabled = true, Cover = 0.8, Density = 0.62, Color = Color3.fromRGB(98, 116, 108) } },
		ChuvaNormal = { id = "ChuvaNormal", nome = "Chuva Normal", pesoClima = 0.82, transicao = transicao(10, 0.82), lighting = { Brightness = 0.82, ExposureCompensation = -0.32, Ambient = Color3.fromRGB(48, 60, 54), OutdoorAmbient = Color3.fromRGB(62, 82, 70), FogStart = 6, FogEnd = 280, FogColor = Color3.fromRGB(76, 98, 88) }, efeitos = { Atmosphere = { Density = 0.66, Haze = 3.8, Color = Color3.fromRGB(96, 122, 112), Decay = Color3.fromRGB(28, 42, 36), Glare = 0 } }, clouds = { Enabled = true, Cover = 0.94, Density = 0.78, Color = Color3.fromRGB(70, 82, 78) } },
		Tempestade = { id = "Tempestade", nome = "Tempestade", pesoClima = 0.9, transicao = transicao(11, 0.9), lighting = { Brightness = 0.5, ExposureCompensation = -0.52, Ambient = Color3.fromRGB(32, 42, 40), OutdoorAmbient = Color3.fromRGB(38, 54, 50), FogStart = 4, FogEnd = 190, FogColor = Color3.fromRGB(50, 66, 64) }, efeitos = { Atmosphere = { Density = 0.78, Haze = 4.6, Color = Color3.fromRGB(70, 88, 84), Decay = Color3.fromRGB(18, 28, 28), Glare = 0 }, SunRaysEffect = { Enabled = false, Intensity = 0, Spread = 1 } }, clouds = { Enabled = true, Cover = 1, Density = 0.94, Color = Color3.fromRGB(44, 52, 54) } },
		NeblinaDensa = { id = "NeblinaDensa", nome = "Neblina Densa", pesoClima = 0.84, transicao = transicao(10, 0.84), lighting = { Brightness = 0.95, ExposureCompensation = -0.18, FogStart = 0, FogEnd = 120, FogColor = Color3.fromRGB(140, 160, 148) }, efeitos = { Atmosphere = { Density = 0.86, Offset = 0.28, Haze = 5.2, Color = Color3.fromRGB(156, 176, 164), Decay = Color3.fromRGB(48, 66, 58), Glare = 0 } }, clouds = { Enabled = true, Cover = 0.72, Density = 0.5, Color = Color3.fromRGB(150, 164, 156) } },
		Mormaco = { id = "Mormaco", nome = "Mormaco", pesoClima = 0.72, transicao = transicao(8, 0.72), lighting = { Brightness = 1.25, ExposureCompensation = -0.05, FogStart = 12, FogEnd = 340, FogColor = Color3.fromRGB(154, 166, 128) }, efeitos = { Atmosphere = { Density = 0.6, Offset = 0.2, Haze = 4.0, Color = Color3.fromRGB(166, 180, 138), Glare = 0.01 }, ColorCorrectionEffect = { Enabled = true, Brightness = -0.02, Contrast = 0.02, Saturation = -0.16, TintColor = Color3.fromRGB(228, 238, 198) } }, clouds = { Enabled = true, Cover = 0.66, Density = 0.48, Color = Color3.fromRGB(162, 172, 138) } },
	},
}
