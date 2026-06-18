--!strict

--[[
    Script: ConfigCamera.luau
    Caminho: src/ReplicatedStorage/Jogador/Camera/Configuracoes
    Responsabilidade: Centraliza parametros de camera usados pelos sistemas do jogador.
    Uso: ModuleScript; use require(caminho) para ler as tabelas e valores exportados.
    Nao faz: Nao executa comportamento sozinho; apenas fornece dados para outros scripts.
    Funcoes principais: ObterConfiguracao, ObterTodasConfiguracoes, DefinirConfiguracao, ResetarConfiguracoes, ObterTweenInfo, ObterTweenInfoFOV
]]
local Modulo_ConfiguracoesJogador = {}

export type ZoomRange = {
	Min: number,
	Max: number,
}

export type ConfiguracaoCamera = {
	ToggleKey: Enum.KeyCode,

	OffsetShoulder: Vector3,
	OffsetCrouch: Vector3,
	WalkOffset: Vector3,
	RunOffset: Vector3,

	ZoomRangeOn: ZoomRange,
	ZoomRangeOff: ZoomRange,

	TeclaPrimeiraPessoa: Enum.KeyCode,
	OffsetFPCabeca: Vector3,
	FOVPrimeiraPessoa: number,
	FOVCorrendoPrimeiraPessoa: number,
	TransicaoPrimeiraPessoaTempo: number,

	DefaultFOV: number,
	WalkFOV: number,
	RunFOV: number,
	FOVTransitionTime: number,
	RunFOVRampTime: number,

	RunSpeedThreshold: number,
	TransitionTime: number,
	SmoothFactor: number,
	OffsetLerpSpeed: number,
}

local ConfiguracaoPadrao: ConfiguracaoCamera = {
	ToggleKey = Enum.KeyCode.LeftControl,

	OffsetShoulder = Vector3.new(-2.5, 0, 0),
	OffsetCrouch = Vector3.new(0, -0.5, 0),
	WalkOffset = Vector3.new(0, 0, 0.4),
	RunOffset = Vector3.new(0, 0, 0.7),

	ZoomRangeOn = { Min = 4, Max = 15 },
	ZoomRangeOff = { Min = 4, Max = 50 },

	TeclaPrimeiraPessoa = Enum.KeyCode.V,
	OffsetFPCabeca = Vector3.new(0, 0.3, -0.35),
	FOVPrimeiraPessoa = 90,
	FOVCorrendoPrimeiraPessoa = 110,
	TransicaoPrimeiraPessoaTempo = 0.4,

	DefaultFOV = 100,
	WalkFOV = 100,
	RunFOV = 120,
	FOVTransitionTime = 0.3,
	RunFOVRampTime = 0.05,

	RunSpeedThreshold = 18,
	TransitionTime = 0.35,
	SmoothFactor = 0.3,
	OffsetLerpSpeed = 6,
}

local configuracaoAtual: ConfiguracaoCamera = ConfiguracaoPadrao

function Modulo_ConfiguracoesJogador.ObterConfiguracao(nome: string): any
	return (configuracaoAtual :: any)[nome]
end

function Modulo_ConfiguracoesJogador.ObterTodasConfiguracoes(): ConfiguracaoCamera
	return configuracaoAtual
end

function Modulo_ConfiguracoesJogador.DefinirConfiguracao(nome: string, valor: any)
	if (configuracaoAtual :: any)[nome] ~= nil then
		(configuracaoAtual :: any)[nome] = valor
	else
		warn(string.format("[Modulo_ConfiguracoesJogador] Configuracao '%s' nao existe!", nome))
	end
end

function Modulo_ConfiguracoesJogador.ResetarConfiguracoes()
	configuracaoAtual = table.clone(ConfiguracaoPadrao)
end

function Modulo_ConfiguracoesJogador.ObterTweenInfo(): TweenInfo
	return TweenInfo.new(configuracaoAtual.TransitionTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
end

function Modulo_ConfiguracoesJogador.ObterTweenInfoFOV(): TweenInfo
	return TweenInfo.new(configuracaoAtual.FOVTransitionTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
end

function Modulo_ConfiguracoesJogador.ObterTweenInfoPrimeiraPessoa(): TweenInfo
	return TweenInfo.new(configuracaoAtual.TransicaoPrimeiraPessoaTempo, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
end

function Modulo_ConfiguracoesJogador.EstaCorrendo(velocidade: number): boolean
	return velocidade >= configuracaoAtual.RunSpeedThreshold
end

function Modulo_ConfiguracoesJogador.ObterFOVAlvoPrimeiraPessoa(andando: boolean, correndo: boolean): number
	if correndo then
		return configuracaoAtual.FOVCorrendoPrimeiraPessoa
	elseif andando then
		return configuracaoAtual.FOVPrimeiraPessoa
	end
	return configuracaoAtual.FOVPrimeiraPessoa
end

function Modulo_ConfiguracoesJogador.ObterFOVAlvo(andando: boolean, correndo: boolean): number
	if correndo then
		return configuracaoAtual.RunFOV
	elseif andando then
		return configuracaoAtual.WalkFOV
	end
	return configuracaoAtual.DefaultFOV
end

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
