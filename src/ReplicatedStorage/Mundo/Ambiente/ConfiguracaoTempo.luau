--[[
    Script: ConfiguracaoTempo.luau
    Caminho: src/ReplicatedStorage/Mundo/Ambiente
    Responsabilidade: Define parametros do ciclo de tempo usado pelo mundo.
    Uso: ModuleScript; use require(caminho) para ler as tabelas e valores exportados.
    Nao faz: Nao executa comportamento sozinho; apenas fornece dados para outros scripts.
    Funcoes principais: NormalizarMinutos, ObterFase, FormatarHora, ConverterHorario, estaNoIntervalo
]]
local ConfiguracaoTempo = {}

ConfiguracaoTempo.SegundosPorHoraJogo = 60
ConfiguracaoTempo.MinutosPorDia = 24 * 60
ConfiguracaoTempo.MinutosJogoPorSegundoReal = 1
ConfiguracaoTempo.IntervaloReplicacao = 0.25
ConfiguracaoTempo.HorarioInicialMinutos = 7 * 60
ConfiguracaoTempo.DiaInicial = 1
ConfiguracaoTempo.DuracaoTransicaoHorarioPadrao = 2.5

ConfiguracaoTempo.Fases = table.freeze({
	{
		id = "Amanhecer",
		nome = "Amanhecer",
		inicio = 5 * 60,
		fim = 7 * 60,
	},
	{
		id = "Dia",
		nome = "Dia",
		inicio = 7 * 60,
		fim = 17 * 60,
	},
	{
		id = "Anoitecer",
		nome = "Anoitecer",
		inicio = 17 * 60,
		fim = 21 * 60,
	},
	{
		id = "Noite",
		nome = "Noite",
		inicio = 21 * 60,
		fim = 5 * 60,
	},
})

function ConfiguracaoTempo.NormalizarMinutos(minutos: number): number
	return ((minutos % ConfiguracaoTempo.MinutosPorDia) + ConfiguracaoTempo.MinutosPorDia)
		% ConfiguracaoTempo.MinutosPorDia
end

local function estaNoIntervalo(minutos: number, inicio: number, fim: number): boolean
	if inicio <= fim then
		return minutos >= inicio and minutos < fim
	end
	return minutos >= inicio or minutos < fim
end

function ConfiguracaoTempo.ObterFase(minutos: number)
	local normalizado = ConfiguracaoTempo.NormalizarMinutos(minutos)
	for _, fase in ipairs(ConfiguracaoTempo.Fases) do
		if estaNoIntervalo(normalizado, fase.inicio, fase.fim) then
			return fase
		end
	end
	return ConfiguracaoTempo.Fases[2]
end

function ConfiguracaoTempo.FormatarHora(minutos: number): string
	local normalizado = math.floor(ConfiguracaoTempo.NormalizarMinutos(minutos) + 0.5)
	local hora = math.floor(normalizado / 60) % 24
	local minuto = normalizado % 60
	return string.format("%02d:%02d", hora, minuto)
end

function ConfiguracaoTempo.ConverterHorario(valor: any): number?
	if type(valor) == "number" then
		if valor <= 24 then
			return ConfiguracaoTempo.NormalizarMinutos(valor * 60)
		end
		return ConfiguracaoTempo.NormalizarMinutos(valor)
	end

	local texto = tostring(valor or "")
	local hora, minuto = string.match(texto, "^(%d%d?):(%d%d)$")
	if hora and minuto then
		return ConfiguracaoTempo.NormalizarMinutos((tonumber(hora) or 0) * 60 + (tonumber(minuto) or 0))
	end

	local numero = tonumber(texto)
	if numero then
		return ConfiguracaoTempo.ConverterHorario(numero)
	end

	return nil
end

return ConfiguracaoTempo
