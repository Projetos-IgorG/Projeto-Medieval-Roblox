--[[
	VozConfig — Configurações centralizadas do sistema de voz dos NPCs.
	
	Flags:
	  SimpleVoice  → Tick por letra (sistema legado)
	  CustomVoice  → Murmúrio em loop (sistema novo)
	  Ambos podem ser true ao mesmo tempo.
]]

local VozConfig = {}

-- ==========================================
-- Flags Globais
-- ==========================================
VozConfig.SimpleVoice = false
VozConfig.CustomVoice = true

-- ==========================================
-- SimpleVoice — Configurações por tipo
-- ==========================================
-- Apenas 4 variantes base. Qualquer TipoVoz que não
-- esteja aqui cairá no fallback por gênero (Male/Female).

VozConfig.SimpleVoiceConfigs = {
	-- ── Male ──
	["Male"] = { Pitch = 1.0, Velocidade = 0.04, FrequenciaSom = 2 },
	["StrongMale"] = { Pitch = 0.9, Velocidade = 0.05, FrequenciaSom = 2 },

	-- ── Female ──
	["Female"] = { Pitch = 1.5, Velocidade = 0.04, FrequenciaSom = 1 },
	["StrongFemale"] = { Pitch = 1.2, Velocidade = 0.05, FrequenciaSom = 2 },
}

-- Som de tick para SimpleVoice
VozConfig.SimpleVoiceTickSoundId = "rbxassetid://97441356620294"

-- ==========================================
-- CustomVoice — Configurações por tipo
-- ==========================================
-- 18 tipos de voz. Cada um com seu AudioId e Volume.

VozConfig.CustomVoiceConfigs = {
	-- ── Male ──
	["FunnyMale"] = { AudioId = "rbxassetid://0", Volume = 0.5 },
	["KidMale"] = { AudioId = "rbxassetid://0", Volume = 0.5 },
	["MerchantMale"] = { AudioId = "rbxassetid://0", Volume = 0.5 },
	["NeutralMale"] = { AudioId = "rbxassetid://74489671463496", Volume = 0.5 },
	["NobleMale"] = { AudioId = "rbxassetid://0", Volume = 0.5 },
	["OldMale"] = { AudioId = "rbxassetid://0", Volume = 0.5 },
	["StrongMale"] = { AudioId = "rbxassetid://0", Volume = 0.5 },
	["VillainMale"] = { AudioId = "rbxassetid://0", Volume = 0.5 },
	["WiseMale"] = { AudioId = "rbxassetid://139997731227387", Volume = 0.5 },

	-- ── Female ──
	["FunnyFemale"] = { AudioId = "rbxassetid://0", Volume = 0.5 },
	["KidFemale"] = { AudioId = "rbxassetid://0", Volume = 0.5 },
	["MerchantFemale"] = { AudioId = "rbxassetid://0", Volume = 0.5 },
	["NeutralFemale"] = { AudioId = "rbxassetid://89086904993691", Volume = 0.6 },
	["NobleFemale"] = { AudioId = "rbxassetid://0", Volume = 0.5 },
	["OldFemale"] = { AudioId = "rbxassetid://0", Volume = 0.5 },
	["StrongFemale"] = { AudioId = "rbxassetid://0", Volume = 0.5 },
	["VillainFemale"] = { AudioId = "rbxassetid://0", Volume = 0.5 },
	["WiseFemale"] = { AudioId = "rbxassetid://139153490291810", Volume = 0.3 },
}

-- Pontos de início possíveis para o áudio (compartilhado por todas as vozes)
VozConfig.CustomVoicePontosDeInicio = { 0, 0.39, 1.334, 2.54, 4.0, 6.6, 7.474, 8, 862, 11.21, 13.632, 14.503 }

-- Opções de pitch para CustomVoice (sorteio por frase)
VozConfig.CustomVoicePitchOptions = { 0.94, 1.0, 1.06 }

-- Duração do fade-in e fade-out entre loops (segundos)
VozConfig.CustomVoiceFadeDuration = 0.4

-- ==========================================
-- Fallback — Resolve qualquer TipoVoz para
-- uma chave válida no SimpleVoiceConfigs
-- ==========================================

--- Retorna a chave SimpleVoice válida para o TipoVoz dado.
--- Ex: "WiseFemale" → "Female", "StrongMale" → "StrongMale"
function VozConfig.ResolverSimpleVoice(tipoVoz: string): string
	if VozConfig.SimpleVoiceConfigs[tipoVoz] then
		return tipoVoz
	end

	-- Fallback por gênero: pega o sufixo "Male" ou "Female"
	if string.find(tipoVoz, "Female") then
		return "Female"
	end
	return "Male"
end

return VozConfig
