--[[
    Script: AplicadorAmbiente.luau
    Caminho: src/ReplicatedStorage/Mundo/Ambiente
    Responsabilidade: Aplica propriedades visuais de ambiente em Lighting, atmosfera e efeitos do mundo.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao roda sozinho nem cria fluxo de jogo por conta propria; depende dos scripts que importam este modulo.
    Funcoes principais: Aplicar, obterDesligamentosInstancia, cancelarDesligamentoPendente, agendarDesligamento, cancelarTweens, ehTweenavel
]]
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local AplicadorAmbiente = {}

local NOMES_EFEITOS = {
	Atmosphere = "AmbienteAtmosfera",
	BloomEffect = "AmbienteBloom",
	DepthOfFieldEffect = "AmbienteDepthOfField",
	SunRaysEffect = "AmbienteSunRays",
	ColorCorrectionEffect = "AmbienteColorCorrection",
}

local EFEITOS_DESATIVADOS = {
	Atmosphere = {
		Density = 0,
		Offset = 0,
		Glare = 0,
		Haze = 0,
		Color = Color3.fromRGB(255, 255, 255),
		Decay = Color3.fromRGB(255, 255, 255),
	},
	BloomEffect = {
		Enabled = false,
		Intensity = 0,
		Size = 0,
		Threshold = 10,
	},
	DepthOfFieldEffect = {
		Enabled = false,
		FarIntensity = 0,
		FocusDistance = 0,
		InFocusRadius = 0,
		NearIntensity = 0,
	},
	SunRaysEffect = {
		Enabled = false,
		Intensity = 0,
		Spread = 1,
	},
	ColorCorrectionEffect = {
		Enabled = false,
		Brightness = 0,
		Contrast = 0,
		Saturation = 0,
		TintColor = Color3.fromRGB(255, 255, 255),
	},
}

local tweensAtivos = {}
local desligamentosPendentes = {}

local function obterDesligamentosInstancia(instancia: Instance)
	local desligamentos = desligamentosPendentes[instancia]
	if not desligamentos then
		desligamentos = {}
		desligamentosPendentes[instancia] = desligamentos
	end
	return desligamentos
end

local function cancelarDesligamentoPendente(instancia: Instance, propriedade: string)
	local desligamentos = desligamentosPendentes[instancia]
	local pendente = desligamentos and desligamentos[propriedade]
	if pendente then
		task.cancel(pendente)
		desligamentos[propriedade] = nil
		if next(desligamentos) == nil then
			desligamentosPendentes[instancia] = nil
		end
	end
end

local function agendarDesligamento(instancia: Instance, propriedade: string, valor: any, duracao: number)
	cancelarDesligamentoPendente(instancia, propriedade)
	local desligamentos = obterDesligamentosInstancia(instancia)
	desligamentos[propriedade] = task.delay(duracao, function()
		desligamentos[propriedade] = nil
		if next(desligamentos) == nil then
			desligamentosPendentes[instancia] = nil
		end
		if instancia.Parent then
			pcall(function()
				instancia[propriedade] = valor
			end)
		end
	end)
end

local function cancelarTweens()
	for _, tween in ipairs(tweensAtivos) do
		pcall(function()
			tween:Cancel()
		end)
	end
	table.clear(tweensAtivos)
end

local function ehTweenavel(valor)
	local tipo = typeof(valor)
	return tipo == "number" or tipo == "Color3" or tipo == "Vector3"
end

local function criarTweenInfo(transicao)
	local duracao = math.max(tonumber(transicao and transicao.duracao) or 0, 0)
	local estilo = (transicao and transicao.estilo) or Enum.EasingStyle.Sine
	local direcao = (transicao and transicao.direcao) or Enum.EasingDirection.InOut
	return TweenInfo.new(duracao, estilo, direcao), duracao
end

local function aplicarPropriedades(instancia: Instance, propriedades, tweenInfo: TweenInfo, duracao: number)
	if not instancia or not propriedades then
		return
	end

	local tweenProps = {}
	for propriedade, valor in propriedades do

		if propriedade == "ClockTime" then
			continue
		end
		local existe = pcall(function()
			return instancia[propriedade]
		end)

		if existe then
			if propriedade == "Enabled" and valor == false and duracao > 0 then
				agendarDesligamento(instancia, propriedade, valor, duracao)
			elseif propriedade == "Enabled" or not ehTweenavel(valor) or duracao <= 0 then
				cancelarDesligamentoPendente(instancia, propriedade)
				pcall(function()
					instancia[propriedade] = valor
				end)
			else
				tweenProps[propriedade] = valor
			end
		end
	end

	if next(tweenProps) then
		local tween = TweenService:Create(instancia, tweenInfo, tweenProps)
		table.insert(tweensAtivos, tween)
		tween:Play()
	end
end

local function obterEfeito(className: string): Instance?
	local nome = NOMES_EFEITOS[className]
	local existente = nome and Lighting:FindFirstChild(nome)
	if existente then
		return existente
	end

	local porClasse = Lighting:FindFirstChildOfClass(className)
	if porClasse and porClasse.Name ~= "VRFade" then
		porClasse.Name = nome or porClasse.Name
		return porClasse
	end

	local ok, novo = pcall(function()
		return Instance.new(className)
	end)
	if ok and novo then
		novo.Name = nome or className
		novo.Parent = Lighting
		return novo
	end

	return nil
end

local function obterClouds(): Clouds
	local terrain = workspace.Terrain
	local clouds = terrain:FindFirstChildOfClass("Clouds")
	if not clouds then
		clouds = Instance.new("Clouds")
		clouds.Name = "Clouds"
		clouds.Parent = terrain
	end
	return clouds
end

local function desativarEfeitosAusentes(efeitosDesejados, tweenInfo: TweenInfo, duracao: number)
	for className in NOMES_EFEITOS do
		if efeitosDesejados and efeitosDesejados[className] ~= nil then
			continue
		end

		local efeito = obterEfeito(className)
		local propsDesativadas = EFEITOS_DESATIVADOS[className]
		if efeito and propsDesativadas then
			aplicarPropriedades(efeito, table.clone(propsDesativadas), tweenInfo, duracao)
		end
	end
end

function AplicadorAmbiente.Aplicar(estadoResolvido, opcoes)
	if not estadoResolvido then
		return
	end

	cancelarTweens()

	local transicao = table.clone(estadoResolvido.transicao or {})
	if opcoes and opcoes.duracao ~= nil then
		transicao.duracao = tonumber(opcoes.duracao) or transicao.duracao
	end

	local tweenInfo, duracao = criarTweenInfo(transicao)
	aplicarPropriedades(Lighting, estadoResolvido.lighting, tweenInfo, duracao)

	for className, props in estadoResolvido.efeitos or {} do
		local efeito = obterEfeito(className)
		if efeito then
			aplicarPropriedades(efeito, props, tweenInfo, duracao)
		end
	end

	desativarEfeitosAusentes(estadoResolvido.efeitos, tweenInfo, duracao)

	aplicarPropriedades(obterClouds(), estadoResolvido.clouds, tweenInfo, duracao)
end

return AplicadorAmbiente
