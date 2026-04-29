--[[
    Script: ControladorAmbiente.client.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/Mundo/Ambiente
    Responsabilidade: Recebe estados de ambiente do servidor e aplica transicoes visuais no cliente.
    Uso: LocalScript; roda automaticamente para o jogador local em src/StarterPlayer/StarterPlayerScripts/Mundo/Ambiente.
    Nao faz: Nao valida autoridade do servidor, nao salva dados persistentes e nao substitui regras server-side.
    Funcoes principais: lerValor, tempoPausado, ambientePausado, distanciaCircularMinutos, deltaCircularMinutos, obterMinutosVisuais
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local AmbienteReplicado = ReplicatedStorage:WaitForChild("Mundo"):WaitForChild("Ambiente")
local CatalogoAmbiente = require(AmbienteReplicado:WaitForChild("CatalogoAmbiente"))
local CompositorAmbiente = require(AmbienteReplicado:WaitForChild("CompositorAmbiente"))
local AplicadorAmbiente = require(AmbienteReplicado:WaitForChild("AplicadorAmbiente"))
local ConfiguracaoTempo = require(AmbienteReplicado:WaitForChild("ConfiguracaoTempo"))

local EstadoMundo = ReplicatedStorage:WaitForChild("EstadoMundo", 15)
if not EstadoMundo then
	warn("[ControladorAmbiente] EstadoMundo nao encontrado; ambiente visual nao foi iniciado")
	return
end

local intervaloAtualizacao = 1
local acumulado = 0
local ultimoCodigoVisual = ""
local transicaoVisualAte = 0

local minutosBase = ConfiguracaoTempo.HorarioInicialMinutos
local relogioBase = os.clock()

local transicaoTempoInicio = 0
local transicaoTempoDuracao = 0
local transicaoTempoOrigem = 0
local transicaoTempoDelta = 0

local function lerValor(nome: string, padrao)
	local valor = EstadoMundo:FindFirstChild(nome)
	if valor and valor:IsA("ValueBase") then
		return valor.Value
	end
	return padrao
end

local function tempoPausado(): boolean
	return lerValor("TempoPausado", false) == true
end

local function ambientePausado(): boolean
	return lerValor("AmbientePausado", false) == true
end

local function distanciaCircularMinutos(a: number, b: number): number
	local diferenca = math.abs(ConfiguracaoTempo.NormalizarMinutos(a) - ConfiguracaoTempo.NormalizarMinutos(b))
	return math.min(diferenca, ConfiguracaoTempo.MinutosPorDia - diferenca)
end

local function deltaCircularMinutos(de: number, ate: number): number

	local diff = ConfiguracaoTempo.NormalizarMinutos(ate) - ConfiguracaoTempo.NormalizarMinutos(de)
	if diff > ConfiguracaoTempo.MinutosPorDia / 2 then
		diff -= ConfiguracaoTempo.MinutosPorDia
	elseif diff < -ConfiguracaoTempo.MinutosPorDia / 2 then
		diff += ConfiguracaoTempo.MinutosPorDia
	end
	return diff
end

local function obterMinutosVisuais(): number
	local agora = os.clock()
	if transicaoTempoDuracao > 0 then
		local t = math.clamp((agora - transicaoTempoInicio) / transicaoTempoDuracao, 0, 1)
		local easing = TweenService:GetValue(t, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		return ConfiguracaoTempo.NormalizarMinutos(transicaoTempoOrigem + transicaoTempoDelta * easing)
	end

	if tempoPausado() then
		return ConfiguracaoTempo.NormalizarMinutos(minutosBase)
	end

	local deltaReal = agora - relogioBase
	return ConfiguracaoTempo.NormalizarMinutos(minutosBase + deltaReal * ConfiguracaoTempo.MinutosJogoPorSegundoReal)
end

local function ancorarTempoEm(valor: number)
	minutosBase = ConfiguracaoTempo.NormalizarMinutos(valor)
	relogioBase = os.clock()
end

local function iniciarTransicaoSuaveAte(novoMinutos: number)
	local origemVisual = obterMinutosVisuais()
	local delta = deltaCircularMinutos(origemVisual, novoMinutos)
	if math.abs(delta) < 0.01 then
		ancorarTempoEm(novoMinutos)
		transicaoTempoDuracao = 0
		return
	end

	local duracaoConfig = tonumber(lerValor("DuracaoTransicaoHorario", ConfiguracaoTempo.DuracaoTransicaoHorarioPadrao)) or 2.5

	local fatorDistancia = math.clamp(math.abs(delta) / 360, 0.3, 1.6)
	transicaoTempoInicio = os.clock()
	transicaoTempoDuracao = math.max(duracaoConfig * fatorDistancia, 0.4)
	transicaoTempoOrigem = origemVisual
	transicaoTempoDelta = delta

	ancorarTempoEm(novoMinutos)
	relogioBase = os.clock() + transicaoTempoDuracao
end

local function aplicarAmbiente(forcar: boolean?)
	if ambientePausado() and not forcar then
		return
	end
	local minutos = obterMinutosVisuais()
	local ambienteId = lerValor("AmbienteAtual", CatalogoAmbiente.AmbientePadrao)
	local climaId = lerValor("ClimaAtual", CatalogoAmbiente.ClimaPadrao)
	local faseDia = lerValor("FaseDia", "Dia")
	local transicaoAtual = tonumber(lerValor("TransicaoAtual", 6)) or 6
	local codigo = tostring(ambienteId) .. ":" .. tostring(climaId) .. ":" .. tostring(faseDia)
	local mudouEstado = codigo ~= ultimoCodigoVisual
	local duracao = if forcar or mudouEstado then transicaoAtual else 1.15

	local resolvido = CompositorAmbiente.Compor(ambienteId, climaId, minutos, { duracao = duracao })
	AplicadorAmbiente.Aplicar(resolvido, { duracao = duracao })
	ultimoCodigoVisual = codigo
	if forcar or mudouEstado then
		transicaoVisualAte = os.clock() + duracao
	end
end

local function atualizarClockTime()
	if ambientePausado() then
		return
	end
	local minutos = obterMinutosVisuais()
	Lighting.ClockTime = ConfiguracaoTempo.NormalizarMinutos(minutos) / 60
end

local function conectarValor(nome: string)
	local valor = EstadoMundo:FindFirstChild(nome)
	if valor and valor:IsA("ValueBase") then
		valor.Changed:Connect(function()
			aplicarAmbiente(true)
		end)
	end
end

for _, nome in ipairs({ "TransicaoAtual", "AmbienteAtualizadoEm", "FaseDia" }) do
	conectarValor(nome)
end

local minutosValor = EstadoMundo:FindFirstChild("MinutosDoDia")
if minutosValor and minutosValor:IsA("NumberValue") then
	ancorarTempoEm(minutosValor.Value)
	minutosValor.Changed:Connect(function()
		local novoMinutos = minutosValor.Value
		local visualAtual = obterMinutosVisuais()
		local diff = distanciaCircularMinutos(visualAtual, novoMinutos)

		if diff <= 1.5 and transicaoTempoDuracao == 0 then
			ancorarTempoEm(novoMinutos)
			return
		end

		iniciarTransicaoSuaveAte(novoMinutos)
	end)
else
	ancorarTempoEm(ConfiguracaoTempo.HorarioInicialMinutos)
end

local pausadoAmbValor = EstadoMundo:FindFirstChild("AmbientePausado")
if pausadoAmbValor and pausadoAmbValor:IsA("BoolValue") then
	pausadoAmbValor.Changed:Connect(function(novo)
		if not novo then

			aplicarAmbiente(true)
		end
	end)
end

aplicarAmbiente(true)

RunService.Heartbeat:Connect(function(deltaTime)
	atualizarClockTime()

	if transicaoTempoDuracao > 0 and (os.clock() - transicaoTempoInicio) >= transicaoTempoDuracao then
		transicaoTempoDuracao = 0
		ancorarTempoEm(transicaoTempoOrigem + transicaoTempoDelta)
	end

	if ambientePausado() then
		return
	end

	if os.clock() < transicaoVisualAte then
		return
	end

	acumulado += deltaTime
	if acumulado < intervaloAtualizacao then
		return
	end
	acumulado = 0
	aplicarAmbiente(false)
end)
