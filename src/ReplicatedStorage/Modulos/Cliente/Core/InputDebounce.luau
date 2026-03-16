-- ReplicatedStorage > Modulos > Cliente > Core > InputDebounce.luau

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
