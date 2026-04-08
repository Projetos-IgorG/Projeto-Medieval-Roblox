--!strict
--[[
	Modulo_ConfiguracoesJogador - Configurações centralizadas para câmera e jogador
	
	Este módulo contém todas as configurações relacionadas ao sistema de câmera,
	ShiftLock customizado, FOV dinâmico, e visibilidade do corpo em primeira pessoa.
	
	Uso:
		local ConfigJogador = require(ReplicatedStorage.Modulos.Jogador.Modulo_ConfiguracoesJogador)
		local toggleKey = ConfigJogador.ObterConfiguracao("ToggleKey")
--]]

local Modulo_ConfiguracoesJogador = {}

-- ═══════════════════════════════════════════════════════════════════
-- TIPOS
-- ═══════════════════════════════════════════════════════════════════

export type ZoomRange = {
	Min: number,
	Max: number,
}

export type ConfiguracaoCamera = {
	-- Toggle ShiftLock
	ToggleKey: Enum.KeyCode,

	-- Offsets de câmera
	OffsetShoulder: Vector3, -- Câmera de lado (ShiftLock ativo)
	OffsetCrouch: Vector3, -- Deslocamento ao agachar
	WalkOffset: Vector3, -- Deslocamento ao andar
	RunOffset: Vector3, -- Deslocamento ao correr

	-- Zoom (3ª pessoa)
	ZoomRangeOn: ZoomRange, -- Limites com ShiftLock ativo
	ZoomRangeOff: ZoomRange, -- Limites com ShiftLock desativado

	-- Primeira Pessoa
	TeclaPrimeiraPessoa: Enum.KeyCode, -- Tecla para toggle de 1ª pessoa
	OffsetFPCabeca: Vector3, -- Offset a partir do centro da cabeça
	FOVPrimeiraPessoa: number, -- FOV base em 1ª pessoa
	FOVCorrendoPrimeiraPessoa: number, -- FOV ao correr em 1ª pessoa
	TransicaoPrimeiraPessoaTempo: number, -- Tempo do tween de transição 3ª→1ª pessoa

	-- FOV (3ª pessoa)
	DefaultFOV: number, -- Valor base de FOV (parado e ao entrar no jogo)
	WalkFOV: number, -- FOV ao andar
	RunFOV: number, -- FOV ao correr
	FOVTransitionTime: number, -- Tempo de transição do FOV (andar/parar)
	RunFOVRampTime: number, -- Tempo pra FOV subir de walk até run ao iniciar corrida

	-- Velocidade
	RunSpeedThreshold: number, -- Velocidade acima da qual é considerado corrida
	TransitionTime: number, -- Tempo geral de animações/tweens
	SmoothFactor: number, -- Suavidade do movimento de câmera
}

-- ═══════════════════════════════════════════════════════════════════
-- CONFIGURAÇÕES PADRÃO
-- ═══════════════════════════════════════════════════════════════════

local ConfiguracaoPadrao: ConfiguracaoCamera = {
	-- Toggle ShiftLock
	ToggleKey = Enum.KeyCode.LeftControl,

	-- Offsets de câmera
	-- Vector3.new(x (largura), y (altura), z (profundidade))
	OffsetShoulder = Vector3.new(-2.5, 0, 0),
	OffsetCrouch = Vector3.new(0, -0.5, 0),
	WalkOffset = Vector3.new(0, 0, 0.4),
	RunOffset = Vector3.new(0, 0, 0.7),

	-- Zoom (3ª pessoa)
	ZoomRangeOn = { Min = 4, Max = 15 },
	ZoomRangeOff = { Min = 4, Max = 50 },

	-- Primeira Pessoa
	TeclaPrimeiraPessoa = Enum.KeyCode.V,
	OffsetFPCabeca = Vector3.new(0, 0.3, -0.5),
	FOVPrimeiraPessoa = 90,
	FOVCorrendoPrimeiraPessoa = 110,
	TransicaoPrimeiraPessoaTempo = 0.25,

	-- FOV (3ª pessoa)
	DefaultFOV = 100,
	WalkFOV = 100,
	RunFOV = 120,
	FOVTransitionTime = 0.3,
	RunFOVRampTime = 0.05,

	-- Velocidade
	RunSpeedThreshold = 18,
	TransitionTime = 0.35,
	SmoothFactor = 0.3,
}

-- ═══════════════════════════════════════════════════════════════════
-- ESTADO INTERNO
-- ═══════════════════════════════════════════════════════════════════

local configuracaoAtual: ConfiguracaoCamera = ConfiguracaoPadrao

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES PÚBLICAS
-- ═══════════════════════════════════════════════════════════════════

--- Obtém uma configuração específica pelo nome
---@param nome string Nome da configuração
---@return any Valor da configuração ou nil se não existir
function Modulo_ConfiguracoesJogador.ObterConfiguracao(nome: string): any
	return (configuracaoAtual :: any)[nome]
end

--- Obtém todas as configurações
---@return ConfiguracaoCamera Tabela com todas as configurações
function Modulo_ConfiguracoesJogador.ObterTodasConfiguracoes(): ConfiguracaoCamera
	return configuracaoAtual
end

--- Define uma configuração específica
---@param nome string Nome da configuração
---@param valor any Novo valor
function Modulo_ConfiguracoesJogador.DefinirConfiguracao(nome: string, valor: any)
	if (configuracaoAtual :: any)[nome] ~= nil then
		(configuracaoAtual :: any)[nome] = valor
	else
		warn(string.format("[Modulo_ConfiguracoesJogador] Configuração '%s' não existe!", nome))
	end
end

--- Reseta todas as configurações para os valores padrão
function Modulo_ConfiguracoesJogador.ResetarConfiguracoes()
	configuracaoAtual = table.clone(ConfiguracaoPadrao)
end

--- Obtém o TweenInfo padrão para transições
---@return TweenInfo TweenInfo configurado
function Modulo_ConfiguracoesJogador.ObterTweenInfo(): TweenInfo
	return TweenInfo.new(configuracaoAtual.TransitionTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
end

--- Obtém o TweenInfo para transições de FOV
---@return TweenInfo TweenInfo configurado para FOV
function Modulo_ConfiguracoesJogador.ObterTweenInfoFOV(): TweenInfo
	return TweenInfo.new(configuracaoAtual.FOVTransitionTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
end

--- Obtém o TweenInfo para transição de primeira pessoa
---@return TweenInfo TweenInfo configurado para primeira pessoa
function Modulo_ConfiguracoesJogador.ObterTweenInfoPrimeiraPessoa(): TweenInfo
	return TweenInfo.new(configuracaoAtual.TransicaoPrimeiraPessoaTempo, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
end

--- Verifica se uma velocidade é considerada "correndo"
---@param velocidade number Velocidade atual
---@return boolean true se está correndo
function Modulo_ConfiguracoesJogador.EstaCorrendo(velocidade: number): boolean
	return velocidade >= configuracaoAtual.RunSpeedThreshold
end

--- Obtém o FOV alvo baseado no estado de movimento para primeira pessoa
---@param andando boolean Se está andando
---@param correndo boolean Se está correndo
---@return number FOV alvo de primeira pessoa
function Modulo_ConfiguracoesJogador.ObterFOVAlvoPrimeiraPessoa(andando: boolean, correndo: boolean): number
	if correndo then
		return configuracaoAtual.FOVCorrendoPrimeiraPessoa
	elseif andando then
		return configuracaoAtual.FOVPrimeiraPessoa -- sem variação ao andar
	end
	return configuracaoAtual.FOVPrimeiraPessoa
end

--- Obtém o FOV alvo baseado no estado de movimento
---@param andando boolean Se está andando
---@param correndo boolean Se está correndo
---@return number FOV alvo
function Modulo_ConfiguracoesJogador.ObterFOVAlvo(andando: boolean, correndo: boolean): number
	if correndo then
		return configuracaoAtual.RunFOV
	elseif andando then
		return configuracaoAtual.WalkFOV
	end
	return configuracaoAtual.DefaultFOV
end

--- Obtém o offset de movimento baseado no estado
---@param andando boolean Se está andando
---@param correndo boolean Se está correndo
---@param agachado boolean Se está agachado
---@return Vector3 Offset combinado
function Modulo_ConfiguracoesJogador.ObterOffsetMovimento(
	andando: boolean,
	correndo: boolean,
	agachado: boolean
): Vector3
	local offset = Vector3.zero

	if correndo then
		offset = offset + configuracaoAtual.RunOffset
	elseif andando then
		offset = offset + configuracaoAtual.WalkOffset
	end

	if agachado then
		offset = offset + configuracaoAtual.OffsetCrouch
	end

	return offset
end

return Modulo_ConfiguracoesJogador
