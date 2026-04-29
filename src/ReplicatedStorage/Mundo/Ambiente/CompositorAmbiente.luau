local CatalogoAmbiente = require(script.Parent:WaitForChild("CatalogoAmbiente"))
local ConfiguracaoTempo = require(script.Parent:WaitForChild("ConfiguracaoTempo"))
local PerfisTempoDia = require(script.Parent:WaitForChild("PerfisTempoDia"))

local CompositorAmbiente = {}

local TRANSICAO_PADRAO = {
	duracao = 20,
	estilo = Enum.EasingStyle.Sine,
	direcao = Enum.EasingDirection.InOut,
	pesoClima = 0.68,
}

local function copiar(valor)
	if type(valor) ~= "table" then
		return valor
	end
	local novo = {}
	for chave, item in valor do
		novo[chave] = copiar(item)
	end
	return novo
end

local function mesclar(base, sobre)
	local resultado = copiar(base or {})
	for chave, valor in sobre or {} do
		if type(valor) == "table" and type(resultado[chave]) == "table" then
			resultado[chave] = mesclar(resultado[chave], valor)
		else
			resultado[chave] = copiar(valor)
		end
	end
	return resultado
end

local function interpolar(a, b, peso)
	if a == nil then
		return copiar(b)
	end
	if b == nil then
		return copiar(a)
	end
	if type(a) == "number" and type(b) == "number" then
		return a + (b - a) * peso
	end
	if typeof(a) == "Color3" and typeof(b) == "Color3" then
		return a:Lerp(b, peso)
	end
	if type(a) == "table" and type(b) == "table" then
		local resultado = {}
		for chave, valor in a do
			resultado[chave] = interpolar(valor, b[chave], peso)
		end
		for chave, valor in b do
			if resultado[chave] == nil then
				resultado[chave] = interpolar(a[chave], valor, peso)
			end
		end
		return resultado
	end
	return copiar(if peso >= 0.5 then b else a)
end

local function obterPesoClima(template)
	local transicao = template.transicao or {}
	return math.clamp(template.pesoClima or transicao.pesoClima or TRANSICAO_PADRAO.pesoClima, 0, 1)
end

function CompositorAmbiente.Compor(ambienteId: any, climaId: any, minutosDoDia: number, opcoes)
	local ambiente, clima, chaveAmbiente, chaveClima = CatalogoAmbiente.Resolver(ambienteId, climaId)
	local perfilTempo = PerfisTempoDia.ObterPerfil(minutosDoDia)
	local template = mesclar(ambiente.base, clima)
	local pesoClima = obterPesoClima(template)

	local lighting = interpolar(perfilTempo.lighting, template.lighting or {}, pesoClima)
	-- ClockTime NAO entra no estado resolvido. O ControladorAmbiente atualiza
	-- ClockTime todo Heartbeat de forma continua. Se incluirmos aqui, o Tween
	-- do AplicadorAmbiente fica brigando com o Heartbeat e o sol da pulinhos.
	lighting.ClockTime = nil

	local transicao = mesclar(TRANSICAO_PADRAO, template.transicao or {})
	if opcoes and opcoes.duracao then
		transicao.duracao = opcoes.duracao
	end

	return {
		ambienteId = chaveAmbiente,
		ambienteNome = ambiente.nome,
		climaId = chaveClima,
		climaNome = clima.nome,
		minutosDoDia = ConfiguracaoTempo.NormalizarMinutos(minutosDoDia),
		horaTexto = ConfiguracaoTempo.FormatarHora(minutosDoDia),
		faseDia = perfilTempo.faseDia,
		transicao = transicao,
		lighting = lighting,
		efeitos = interpolar(perfilTempo.efeitos, template.efeitos or {}, pesoClima),
		clouds = interpolar(perfilTempo.clouds, template.clouds or {}, pesoClima),
	}
end

return CompositorAmbiente