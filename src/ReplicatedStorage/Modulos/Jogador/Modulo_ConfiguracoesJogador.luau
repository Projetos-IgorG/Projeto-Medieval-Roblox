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
	OffsetFP: Vector3, -- Câmera em 1ª pessoa
	OffsetCrouch: Vector3, -- Deslocamento ao agachar
	WalkOffset: Vector3, -- Deslocamento ao andar
	RunOffset: Vector3, -- Deslocamento ao correr

	-- Zoom
	ZoomRangeOn: ZoomRange, -- Limites com ShiftLock ativo
	ZoomRangeOff: ZoomRange, -- Limites com ShiftLock desativado
	DefaultZoomOut: number, -- Zoom ao sair da 1ª pessoa via toggle
	FP_Threshold: number, -- Distância para considerar modo FPS
	HeadHideLimit: number, -- Zoom mínimo onde acessórios de cabeça somem

	-- Dead Zone / Snap
	DeadZoneSnapDelay: number, -- Tempo em segundos na zona morta antes do snap
	SnapTransitionTime: number, -- Tempo da transição suave do snap

	-- FOV
	DefaultFOV: number, -- Valor base de FOV
	WalkFOV: number, -- FOV ao andar
	RunFOV: number, -- FOV ao correr
	FOVTransitionTime: number, -- Tempo de transição do FOV

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
	OffsetShoulder = Vector3.new(-2.5, 0, 2),
	OffsetFP = Vector3.new(0, 0.27, 0.9),
	OffsetCrouch = Vector3.new(0, -0.5, 0),
	WalkOffset = Vector3.new(0, 0, 0.4),
	RunOffset = Vector3.new(0, 0, 0.7),

	-- Zoom
	ZoomRangeOn = { Min = 0.5, Max = 15 },
	ZoomRangeOff = { Min = 0.5, Max = 50 },
	DefaultZoomOut = 10,
	FP_Threshold = 1.5,
	HeadHideLimit = 0.6,

	-- Dead Zone / Snap
	DeadZoneSnapDelay = 0.2,
	SnapTransitionTime = 0.25,

	-- FOV
	DefaultFOV = 78,
	WalkFOV = 78,
	RunFOV = 86,
	FOVTransitionTime = 0.3,

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

--- Obtém o TweenInfo para snap de câmera
---@return TweenInfo TweenInfo configurado para snap
function Modulo_ConfiguracoesJogador.ObterTweenInfoSnap(): TweenInfo
	return TweenInfo.new(configuracaoAtual.SnapTransitionTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
end

--- Verifica se uma velocidade é considerada "correndo"
---@param velocidade number Velocidade atual
---@return boolean true se está correndo
function Modulo_ConfiguracoesJogador.EstaCorrendo(velocidade: number): boolean
	return velocidade >= configuracaoAtual.RunSpeedThreshold
end

--- Verifica se uma distância está na zona morta (entre HeadHideLimit e FP_Threshold)
---@param distancia number Distância da câmera ao foco
---@return boolean true se está na zona morta
function Modulo_ConfiguracoesJogador.EstaEmZonaMorta(distancia: number): boolean
	return distancia > configuracaoAtual.HeadHideLimit and distancia < configuracaoAtual.FP_Threshold
end

--- Verifica se uma distância é considerada primeira pessoa
---@param distancia number Distância da câmera ao foco
---@return boolean true se está em primeira pessoa
function Modulo_ConfiguracoesJogador.EstaEmPrimeiraPessoa(distancia: number): boolean
	return distancia < configuracaoAtual.FP_Threshold
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
