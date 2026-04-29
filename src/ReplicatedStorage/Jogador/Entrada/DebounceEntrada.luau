--[[
    Script: DebounceEntrada.luau
    Caminho: src/ReplicatedStorage/Jogador/Entrada
    Responsabilidade: Aplica debounce e janelas de repeticao para inputs do jogador.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao roda sozinho nem cria fluxo de jogo por conta propria; depende dos scripts que importam este modulo.
    Funcoes principais: PodeEnviarAcao, EnviarAcaoComDebounce, RemoverDebounce
]]
local InputDebounce = {}

local ultimasAcoes = {}
local DEBOUNCE_ACAO = 0.05

function InputDebounce.PodeEnviarAcao(nomeAcao: string): boolean
	local agora = tick()
	local ultimaVez = ultimasAcoes[nomeAcao] or 0
	if (agora - ultimaVez) < DEBOUNCE_ACAO then
		return false
	end
	ultimasAcoes[nomeAcao] = agora
	return true
end

function InputDebounce.EnviarAcaoComDebounce(remoto: RemoteEvent, acao: string, dados: any?)
	if InputDebounce.PodeEnviarAcao(acao) then
		remoto:FireServer(acao, dados)
	end
end

function InputDebounce.RemoverDebounce(nomeAcao: string)
    ultimasAcoes[nomeAcao] = nil
end

return InputDebounce
