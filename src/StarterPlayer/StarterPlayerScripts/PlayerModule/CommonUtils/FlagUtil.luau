--!strict

--[[
    Script: FlagUtil.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/PlayerModule/CommonUtils
    Responsabilidade: Centraliza leitura segura de flags usadas pelo PlayerModule.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao implementa regras de gameplay do projeto; apenas apoia camera, controle e compatibilidade do jogador.
    Funcoes principais: getUserFlag
]]
export type FlagUtilType = {

	getUserFlag: (string) -> boolean,
}

local FlagUtil: FlagUtilType = {} :: FlagUtilType

function FlagUtil.getUserFlag(flagName)
	local success, result = pcall(function()
		return UserSettings():IsUserFeatureEnabled(flagName)
	end)
	return success and result
end

return FlagUtil
