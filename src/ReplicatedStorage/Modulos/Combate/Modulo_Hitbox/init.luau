--[[
	Modulo_Hitbox.luau
	
	Wrapper sobre ShapecastHitbox para hitboxes baseadas em DmgPoints.
	
	Responsabilidades:
	- Criar hitboxes vinculadas ao HitboxPart de um WeaponModel
	- Gerenciar hitboxes por mão (Right / Left)
	- Prover API limpa de start/stop com deduplicação de alvos
	- Filtrar hits para entidades com Humanoid vivo
	
	Uso:
	  O cliente (GerenciadorHitboxCliente) chama CriarHitbox() ao equipar a arma
	  e AtivarHitbox()/PararHitbox() nos markers de animação.
	  Cada hit detectado é reportado ao servidor via callback.
]]

--!strict

local ShapecastHitbox = require(script.Modulo_Shapecast)

-- ═══════════════════════════════════════════════════════════════════
-- TYPES
-- ═══════════════════════════════════════════════════════════════════

export type Mao = "Right" | "Left"

--- Callback chamado quando uma entidade é atingida (já deduplicada)
export type OnHitCallback = (alvo: Model, mao: Mao) -> ()

--- Handle retornado por CriarHitbox, usado para controlar a hitbox
export type HitboxHandle = {
	mao: Mao,
	hitbox: any, -- ShapecastHitbox.Hitbox (tipo opaco)
	ativa: boolean,
	jaAtingidos: { [Model]: boolean },
	_onHitCallback: OnHitCallback?,
}

-- ═══════════════════════════════════════════════════════════════════
-- MÓDULO
-- ═══════════════════════════════════════════════════════════════════

local Modulo_Hitbox = {}

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES DE VALIDAÇÃO
-- ═══════════════════════════════════════════════════════════════════

--- Valida se um WeaponModel tem HitboxPart com DmgPoints
---@param weaponModel Model
---@return boolean sucesso
---@return string? erro
function Modulo_Hitbox.ValidarWeaponModel(weaponModel: Model): (boolean, string?)
	if not weaponModel then
		return false, "WeaponModel é nil"
	end

	local hitboxPart = weaponModel:FindFirstChild("HitboxPart")
	if not hitboxPart then
		return false, "WeaponModel sem HitboxPart"
	end

	-- Verifica se há pelo menos um DmgPoint
	local temDmgPoint = false
	for _, desc in ipairs(hitboxPart:GetDescendants()) do
		if desc.Name == "DmgPoint" or desc:HasTag("DmgPoint") then
			temDmgPoint = true
			break
		end
	end

	if not temDmgPoint then
		return false, "HitboxPart sem Attachments DmgPoint"
	end

	return true, nil
end

--- Busca o WeaponModel de uma mão no character
---@param character Model
---@param mao Mao
---@return Model?
function Modulo_Hitbox.BuscarWeaponModel(character: Model, mao: Mao): Model?
	local nomeModel = "WeaponModel" .. mao
	return character:FindFirstChild(nomeModel) :: Model?
end

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES PRINCIPAIS
-- ═══════════════════════════════════════════════════════════════════

--- Cria uma hitbox vinculada ao HitboxPart de um WeaponModel.
--- A hitbox é criada inativa — use AtivarHitbox() para iniciar a detecção.
---@param weaponModel Model O WeaponModel com HitboxPart e DmgPoints
---@param mao Mao Qual mão ("Right" ou "Left")
---@param raycastParams RaycastParams? Params opcionais (se nil, cria um padrão)
---@return HitboxHandle? handle
---@return string? erro
function Modulo_Hitbox.CriarHitbox(
	weaponModel: Model,
	mao: Mao,
	raycastParams: RaycastParams?
): (HitboxHandle?, string?)
	-- Valida weapon model
	local valido, erro = Modulo_Hitbox.ValidarWeaponModel(weaponModel)
	if not valido then
		return nil, erro
	end

	local hitboxPart = weaponModel:FindFirstChild("HitboxPart")

	-- Cria RaycastParams padrão se não fornecido
	local params = raycastParams or RaycastParams.new()
	if not raycastParams then
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = {}
	end

	-- Instancia o ShapecastHitbox apontando para o HitboxPart
	local hitbox = ShapecastHitbox.new(hitboxPart, params)

	local handle: HitboxHandle = {
		mao = mao,
		hitbox = hitbox,
		ativa = false,
		jaAtingidos = {},
		_onHitCallback = nil,
	}

	return handle, nil
end

--- Cria RaycastParams que excluem o character do atacante.
---@param character Model
---@return RaycastParams
function Modulo_Hitbox.CriarRaycastParamsAtacante(character: Model): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	return params
end

--- Filtra um RaycastResult para encontrar um Model com Humanoid vivo.
--- Retorna o Model se válido, nil caso contrário.
---@param raycastResult RaycastResult
---@return Model?
local function _FiltrarParaEntidadeViva(raycastResult: RaycastResult): Model?
	local instancia = raycastResult.Instance
	if not instancia then
		return nil
	end

	local modelo = instancia:FindFirstAncestorOfClass("Model")
	if not modelo then
		return nil
	end

	local humanoid = modelo:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end

	return modelo
end

--- Ativa a hitbox para começar a detectar colisões.
--- Limpa a lista de alvos já atingidos e registra o callback.
---@param handle HitboxHandle
---@param onHit OnHitCallback Callback chamado para cada entidade atingida (deduplicado)
---@param duracao number? Duração em segundos (nil = indefinido até PararHitbox)
function Modulo_Hitbox.AtivarHitbox(handle: HitboxHandle, onHit: OnHitCallback, duracao: number?)
	if not handle or not handle.hitbox then
		warn("[Modulo_Hitbox] Handle inválido para AtivarHitbox")
		return
	end

	-- Reset estado
	table.clear(handle.jaAtingidos)
	handle.ativa = true
	handle._onHitCallback = onHit

	-- Registra callback de hit com deduplicação
	handle.hitbox:OnHit(function(raycastResult: RaycastResult, _segment: any)
		if not handle.ativa then
			return
		end

		local modelo = _FiltrarParaEntidadeViva(raycastResult)
		if not modelo then
			return
		end

		-- Deduplicação: só notifica uma vez por entidade por ativação
		if handle.jaAtingidos[modelo] then
			return
		end

		handle.jaAtingidos[modelo] = true

		-- Chama callback
		if handle._onHitCallback then
			handle._onHitCallback(modelo, handle.mao)
		end
	end)

	-- Registra cleanup ao parar
	handle.hitbox:OnStopped(function(cleanCallbacks)
		handle.ativa = false
		cleanCallbacks()
	end)

	-- Inicia a hitbox
	handle.hitbox:HitStart(duracao)
end

--- Para a hitbox ativa.
---@param handle HitboxHandle
function Modulo_Hitbox.PararHitbox(handle: HitboxHandle)
	if not handle or not handle.hitbox then
		return
	end

	handle.ativa = false
	handle.hitbox:HitStop()
end

--- Destroi a hitbox completamente, liberando a conexão PostSimulation.
--- Após Destruir, o handle não pode ser reutilizado.
---@param handle HitboxHandle
function Modulo_Hitbox.DestruirHitbox(handle: HitboxHandle)
	if not handle or not handle.hitbox then
		return
	end

	handle.ativa = false
	handle.hitbox:HitStop()
	handle.hitbox:Destroy()
	handle.hitbox = nil :: any
end

return Modulo_Hitbox
