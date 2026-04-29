--!strict

--[[
    Script: ConfigMovimento.luau
    Caminho: src/ReplicatedStorage/Jogador/Movimento/Configuracoes
    Responsabilidade: Centraliza parametros de movimento, velocidade e estados locomotores.
    Uso: ModuleScript; use require(caminho) para ler as tabelas e valores exportados.
    Nao faz: Nao executa comportamento sozinho; apenas fornece dados para outros scripts.
    Funcoes principais: ObterConfiguracao
]]
local MovementConfig = {}

MovementConfig.ConfiguracaoGlobal = {
	TempoMinimoQueda = 0.28,
	VelocidadeCorrendoNoAr = 0.4,
	VelocidadeAndando = 12,
	VelocidadeCorrendo = 20,
	VelocidadeBloqueando = 6,
	VelocidadeDefesaQuebrada = 3,
	VelocidadeAgachando = 7,
	VelocidadeAparando = 3,
	VelocidadeEscalando = 12,
	VelocidadeBaseAnimAndando = 15,
	VelocidadeBaseAnimCorrendo = 21,
	VelocidadeBaseAnimAgachando = 11,
	VelocidadeBaseAnimBloqueando = 6,
}

function MovementConfig.ObterConfiguracao(chave: string): any
	if type(chave) ~= "string" then
		warn("[MovementConfig] Chave de configuracao invalida: " .. tostring(chave))
		return nil
	end

	local valor = MovementConfig.ConfiguracaoGlobal[chave]
	if valor == nil then
		warn("[MovementConfig] Configuracao nao encontrada: " .. chave)
	end

	return valor
end

return MovementConfig
