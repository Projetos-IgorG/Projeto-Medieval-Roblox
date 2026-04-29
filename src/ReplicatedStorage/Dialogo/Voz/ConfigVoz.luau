--[[
    Script: ConfigVoz.luau
    Caminho: src/ReplicatedStorage/Dialogo/Voz
    Responsabilidade: Centraliza parametros de voz sintetica e mapeamentos de som para dialogos.
    Uso: ModuleScript; use require(caminho) para ler as tabelas e valores exportados.
    Nao faz: Nao executa comportamento sozinho; apenas fornece dados para outros scripts.
    Funcoes principais: ResolverSimpleVoice
]]
local VozConfig = {}

VozConfig.SimpleVoice = true
VozConfig.CustomVoice = false

VozConfig.SimpleVoiceConfigs = {

	["Male"] = { Pitch = 1.0, Velocidade = 0.04, FrequenciaSom = 3 },
	["StrongMale"] = { Pitch = 0.9, Velocidade = 0.05, FrequenciaSom = 4 },
	["KidMale"] = { Pitch = 1.2, Velocidade = 0.04, FrequenciaSom = 2 },

	["Female"] = { Pitch = 1.5, Velocidade = 0.04, FrequenciaSom = 3 },
	["StrongFemale"] = { Pitch = 1.2, Velocidade = 0.05, FrequenciaSom = 4 },
	["KidFemale"] = { Pitch = 2, Velocidade = 0.04, FrequenciaSom = 2 },
}

VozConfig.SimpleVoiceTickSoundId = "rbxassetid://97441356620294"

VozConfig.CustomVoiceConfigs = {

	["FunnyMale"] = { AudioId = "rbxassetid://0", Volume = 0.5 },
	["KidMale"] = { AudioId = "rbxassetid://0", Volume = 0.5 },
	["MerchantMale"] = { AudioId = "rbxassetid://0", Volume = 0.5 },
	["NeutralMale"] = { AudioId = "rbxassetid://74489671463496", Volume = 0.5 },
	["NobleMale"] = { AudioId = "rbxassetid://0", Volume = 0.5 },
	["OldMale"] = { AudioId = "rbxassetid://0", Volume = 0.5 },
	["StrongMale"] = { AudioId = "rbxassetid://0", Volume = 0.5 },
	["VillainMale"] = { AudioId = "rbxassetid://0", Volume = 0.5 },
	["WiseMale"] = { AudioId = "rbxassetid://139997731227387", Volume = 0.6 },

	["FunnyFemale"] = { AudioId = "rbxassetid://0", Volume = 0.5 },
	["KidFemale"] = { AudioId = "rbxassetid://0", Volume = 0.5 },
	["MerchantFemale"] = { AudioId = "rbxassetid://0", Volume = 0.5 },
	["NeutralFemale"] = { AudioId = "rbxassetid://89086904993691", Volume = 1 },
	["NobleFemale"] = { AudioId = "rbxassetid://0", Volume = 0.5 },
	["OldFemale"] = { AudioId = "rbxassetid://0", Volume = 0.5 },
	["StrongFemale"] = { AudioId = "rbxassetid://0", Volume = 0.5 },
	["VillainFemale"] = { AudioId = "rbxassetid://0", Volume = 0.5 },
	["WiseFemale"] = { AudioId = "rbxassetid://139153490291810", Volume = 0.3 },
}

VozConfig.CustomVoicePontosDeInicio = { 0, 0.39, 1.334, 2.54, 4.0, 6.6, 7.474, 8, 862, 11.21, 13.632, 14.503 }

VozConfig.CustomVoicePitchOptions = { 0.94, 1.0, 1.06 }

VozConfig.CustomVoiceFadeDuration = 0.4

function VozConfig.ResolverSimpleVoice(tipoVoz: string): string
	if VozConfig.SimpleVoiceConfigs[tipoVoz] then
		return tipoVoz
	end

	if string.find(tipoVoz, "Kid") then
		if string.find(tipoVoz, "Female") then
			return "KidFemale"
		end
		return "KidMale"
	end

	if string.find(tipoVoz, "Female") then
		return "Female"
	end
	return "Male"
end

return VozConfig
