--[[
	Modulo_Hitbox.luau
	
	Cria hitboxes dinâmicas baseadas no alcance da Tool.
	
	Responsabilidades:
	- Validar propriedade "Alcance" na Tool
	- Criar hitboxes com dimensões dinâmicas
	- Detectar entidades na área de ataque
	- Hitbox específica para Arcos (projétil)
]]

--!strict

local _Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modulo_Configuracoes =
	require(ReplicatedStorage:WaitForChild("Modulos"):WaitForChild("Combate"):WaitForChild("Modulo_Configuracoes"))

-- ═══════════════════════════════════════════════════════════════════
-- CONSTANTES
-- ═══════════════════════════════════════════════════════════════════

local PASTA_DADOS = "Dados"
local PROP_ALCANCE = "Alcance"

-- Configurações padrão de hitbox
local CONFIG_HITBOX = {
	duracaoPadrao = 0.1,
	alturaBase = 3.5,
	larguraMultiplicador = 0.8,
	profundidadeMultiplicador = 1.2,
}

-- Multiplicadores por tipo de ataque
local MULTIPLICADORES_HITBOX: { [string]: { tamanho: number, offset: number } } = {
	AtaqueLeve = { tamanho = 1.0, offset = 1.0 },
	AtaqueLeveFinal = { tamanho = 1.2, offset = 1.1 },
	AtaquePesado = { tamanho = 1.4, offset = 1.2 },
}

-- ═══════════════════════════════════════════════════════════════════
-- TYPES
-- ═══════════════════════════════════════════════════════════════════

export type ConfiguracaoHitbox = {
	tamanho: Vector3,
	offset: CFrame,
	duracao: number,
}

export type ResultadoHitbox = {
	sucesso: boolean,
	entidadesAtingidas: { Model },
	erro: string?,
}

-- ═══════════════════════════════════════════════════════════════════
-- MÓDULO
-- ═══════════════════════════════════════════════════════════════════

local Modulo_Hitbox = {}

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES DE VALIDAÇÃO
-- ═══════════════════════════════════════════════════════════════════

--- Valida se a Tool tem a propriedade Alcance
---@param tool Tool
---@return boolean sucesso
---@return string? erro
function Modulo_Hitbox.ValidarToolAlcance(tool: Tool): (boolean, string?)
	if not tool then
		return false, "Tool é nil"
	end

	local dados = tool:FindFirstChild(PASTA_DADOS)
	if not dados then
		return false, "Tool sem pasta '" .. PASTA_DADOS .. "'"
	end

	local alcanceValue = dados:FindFirstChild(PROP_ALCANCE)
	if not alcanceValue then
		return false, "Pasta Dados sem propriedade '" .. PROP_ALCANCE .. "'"
	end

	if not (alcanceValue:IsA("NumberValue") or alcanceValue:IsA("IntValue")) then
		return false, "Propriedade Alcance não é numérica"
	end

	return true, nil
end

--- Valida se um atacante é válido
---@param atacante Model
---@return boolean sucesso
---@return string? erro
function Modulo_Hitbox.ValidarAtacante(atacante: Model): (boolean, string?)
	if not atacante then
		return false, "Atacante é nil"
	end

	local humanoidRoot = atacante:FindFirstChild("HumanoidRootPart")
	if not humanoidRoot then
		return false, "Atacante sem HumanoidRootPart"
	end

	return true, nil
end

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES DE ACESSO
-- ═══════════════════════════════════════════════════════════════════

--- Obtém o alcance da Tool
---@param tool Tool
---@return number?
function Modulo_Hitbox.ObterAlcance(tool: Tool): number?
	local valido, erro = Modulo_Hitbox.ValidarToolAlcance(tool)
	if not valido then
		warn("[Modulo_Hitbox] " .. (erro or "Erro desconhecido"))
		return nil
	end

	local dados = tool:FindFirstChild(PASTA_DADOS)
	local alcanceValue = dados and dados:FindFirstChild(PROP_ALCANCE)

	if alcanceValue and (alcanceValue:IsA("NumberValue") or alcanceValue:IsA("IntValue")) then
		return (alcanceValue :: NumberValue).Value
	end

	return nil
end

--- Calcula as dimensões da hitbox baseado no alcance e tipo de ataque
---@param alcance number
---@param tipoAtaque string
---@return ConfiguracaoHitbox
function Modulo_Hitbox.CalcularDimensoesHitbox(alcance: number, tipoAtaque: string): ConfiguracaoHitbox
	local mult = MULTIPLICADORES_HITBOX[tipoAtaque] or MULTIPLICADORES_HITBOX.AtaqueLeve

	local largura = alcance * CONFIG_HITBOX.larguraMultiplicador * mult.tamanho
	local altura = CONFIG_HITBOX.alturaBase * mult.tamanho
	local profundidade = alcance * CONFIG_HITBOX.profundidadeMultiplicador * mult.tamanho

	local offsetZ = -(alcance / 2) * mult.offset

	return {
		tamanho = Vector3.new(largura, altura, profundidade),
		offset = CFrame.new(0, 0, offsetZ),
		duracao = CONFIG_HITBOX.duracaoPadrao,
	}
end

--- Cria uma representação visual temporária da hitbox no mundo
local function _VisualizarHitbox(cf: CFrame, size: Vector3, duracao: number)
	if not Modulo_Configuracoes.ObterConfiguracao("VisualizarHitbox") then
		return
	end

	local visual = Instance.new("Part")
	visual.Name = "DEBUG_HitboxVisual"
	visual.Anchored = true
	visual.CanCollide = false
	visual.CanQuery = false
	visual.CastShadow = false
	visual.Material = Enum.Material.ForceField
	visual.Color = Color3.fromRGB(255, 0, 0)
	visual.Transparency = 0.5
	visual.CFrame = cf
	visual.Size = size
	visual.Parent = workspace

	task.delay(duracao, function()
		visual:Destroy()
	end)
end

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÃO PRINCIPAL - MELEE
-- ═══════════════════════════════════════════════════════════════════

--- Cria hitbox para combate corpo-a-corpo
---@param atacante Model Character atacante
---@param tool Tool Ferramenta equipada
---@param tipoAtaque string Tipo de ataque
---@param atacanteCFrame CFrame? CFrame opcional para substituir a posição atual (ex: vindo do cliente)
---@return ResultadoHitbox
function Modulo_Hitbox.CriarHitboxMelee(
	atacante: Model,
	tool: Tool,
	tipoAtaque: string,
	atacanteCFrame: CFrame?
): ResultadoHitbox
	-- Validação de atacante
	local atacanteValido, atacanteErro = Modulo_Hitbox.ValidarAtacante(atacante)
	if not atacanteValido then
		return {
			sucesso = false,
			entidadesAtingidas = {},
			erro = atacanteErro,
		}
	end

	-- Obtém alcance da Tool
	local alcance = Modulo_Hitbox.ObterAlcance(tool) :: number?
	if not alcance then
		-- Usa valor padrão se não encontrar
		alcance = 5
		warn("[Modulo_Hitbox] Usando alcance padrão: " .. tostring(alcance))
	end

	-- Calcula dimensões da hitbox
	local configHitbox = Modulo_Hitbox.CalcularDimensoesHitbox(alcance :: number, tipoAtaque)

	-- Obtém posição e orientação do atacante
	local humanoidRoot = atacante:FindFirstChild("HumanoidRootPart") :: BasePart
	local baseCFrame = atacanteCFrame or humanoidRoot.CFrame
	local hitboxCFrame = baseCFrame * configHitbox.offset
	local hitboxSize = configHitbox.tamanho

	-- Cria OverlapParams
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { atacante }

	-- Detecta partes na hitbox
	local sucesso, resultado = pcall(function()
		return workspace:GetPartBoundsInBox(hitboxCFrame, hitboxSize, overlapParams)
	end)

	-- Visualização de Debug
	_VisualizarHitbox(hitboxCFrame, hitboxSize, configHitbox.duracao or 0.2)

	if not sucesso then
		return {
			sucesso = false,
			entidadesAtingidas = {},
			erro = "Erro ao criar hitbox: " .. tostring(resultado),
		}
	end

	local partesEncontradas = resultado :: { BasePart }

	-- Filtra para encontrar humanoids únicos
	local entidadesAtingidas: { Model } = {}
	local jaProcessados: { [Model]: boolean } = {}

	for _, parte in ipairs(partesEncontradas) do
		local modelo = parte:FindFirstAncestorOfClass("Model")
		if modelo and not jaProcessados[modelo] then
			local humanoid = modelo:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				jaProcessados[modelo] = true
				table.insert(entidadesAtingidas, modelo)
			end
		end
	end

	return {
		sucesso = true,
		entidadesAtingidas = entidadesAtingidas,
		erro = nil,
	}
end

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÃO - ARCO (PROJÉTIL)
-- ═══════════════════════════════════════════════════════════════════

--- Cria hitbox para Arco (detecção em linha/raycast)
---@param atacante Model Character atacante
---@param tool Tool Ferramenta equipada
---@param direcao Vector3 Direção do disparo
---@return ResultadoHitbox
function Modulo_Hitbox.CriarHitboxArco(atacante: Model, tool: Tool, direcao: Vector3): ResultadoHitbox
	-- Validação de atacante
	local atacanteValido, atacanteErro = Modulo_Hitbox.ValidarAtacante(atacante)
	if not atacanteValido then
		return {
			sucesso = false,
			entidadesAtingidas = {},
			erro = atacanteErro,
		}
	end

	-- Obtém alcance da Tool (distância máxima do projétil)
	local alcance = Modulo_Hitbox.ObterAlcance(tool)
	if not alcance then
		alcance = 100 -- Alcance padrão para arcos
		warn("[Modulo_Hitbox] Usando alcance padrão para arco: " .. tostring(alcance))
	end

	-- Normaliza direção
	local direcaoNormalizada = direcao.Unit

	-- Obtém posição de origem
	local humanoidRoot = atacante:FindFirstChild("HumanoidRootPart") :: BasePart
	local origem = humanoidRoot.Position + Vector3.new(0, 1.5, 0) -- Altura do peito

	-- Cria RaycastParams
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { atacante }

	-- Executa raycast
	local sucesso, resultado = pcall(function()
		return workspace:Raycast(origem, direcaoNormalizada * (alcance :: number), raycastParams)
	end)

	-- Visualização de Debug para Arco (Cria uma linha visual)
	if sucesso and Modulo_Configuracoes.ObterConfiguracao("VisualizarHitbox") then
		local dist = resultado and (resultado :: RaycastResult).Distance or (alcance :: number)
		local visualCF = CFrame.lookAt(origem, origem + direcaoNormalizada) * CFrame.new(0, 0, -dist / 2)
		_VisualizarHitbox(visualCF, Vector3.new(0.2, 0.2, dist), 0.5)
	end

	if not sucesso then
		return {
			sucesso = false,
			entidadesAtingidas = {},
			erro = "Erro ao criar raycast: " .. tostring(resultado),
		}
	end

	local rayResult = resultado :: RaycastResult?

	-- Verifica se acertou algo
	if not rayResult then
		return {
			sucesso = true,
			entidadesAtingidas = {},
			erro = nil, -- Não acertou nada, mas é um resultado válido
		}
	end

	-- Verifica se é uma entidade válida
	local modelo = rayResult.Instance:FindFirstAncestorOfClass("Model")
	if modelo then
		local humanoid = modelo:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			return {
				sucesso = true,
				entidadesAtingidas = { modelo },
				erro = nil,
			}
		end
	end

	return {
		sucesso = true,
		entidadesAtingidas = {},
		erro = nil,
	}
end

return Modulo_Hitbox
