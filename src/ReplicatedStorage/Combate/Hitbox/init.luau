--!strict

--[[
    Script: init.luau
    Caminho: src/ReplicatedStorage/Combate/Hitbox
    Responsabilidade: Expoe a fachada compartilhada do sistema de hitbox de combate.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao roda sozinho nem cria fluxo de jogo por conta propria; depende dos scripts que importam este modulo.
    Funcoes principais: ValidarWeaponModel, BuscarWeaponModel, CriarHitbox, CriarRaycastParamsAtacante, AtivarHitbox, PararHitbox
]]
local ShapecastHitbox = require(script.Shapecast)

export type Mao = "Right" | "Left"

export type OnHitCallback = (alvo: Model, mao: Mao) -> ()
export type OnSolidHitCallback = (raycastResult: RaycastResult, mao: Mao) -> ()

export type HitboxHandle = {
	mao: Mao,
	hitbox: any,
	ativa: boolean,
	jaAtingidos: { [Model]: boolean },
	jaAcertouSolido: boolean,
	_onHitCallback: OnHitCallback?,
	_onSolidHitCallback: OnSolidHitCallback?,
}

local Modulo_Hitbox = {}

function Modulo_Hitbox.ValidarWeaponModel(weaponModel: Model): (boolean, string?)
	if not weaponModel then
		return false, "WeaponModel é nil"
	end

	local hitboxPart = weaponModel:FindFirstChild("HitboxPart")
	if not hitboxPart then
		return false, "WeaponModel sem HitboxPart"
	end

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

function Modulo_Hitbox.BuscarWeaponModel(character: Model, mao: Mao): Model?
	local nomeModel = "WeaponModel" .. mao
	return character:FindFirstChild(nomeModel) :: Model?
end

function Modulo_Hitbox.CriarHitbox(
	weaponModel: Model,
	mao: Mao,
	raycastParams: RaycastParams?
): (HitboxHandle?, string?)

	local valido, erro = Modulo_Hitbox.ValidarWeaponModel(weaponModel)
	if not valido then
		return nil, erro
	end

	local hitboxPart = weaponModel:FindFirstChild("HitboxPart")

	local params = raycastParams or RaycastParams.new()
	if not raycastParams then
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = {}
	end

	local hitbox = ShapecastHitbox.new(hitboxPart, params)

	local handle: HitboxHandle = {
		mao = mao,
		hitbox = hitbox,
		ativa = false,
		jaAtingidos = {},
		jaAcertouSolido = false,
		_onHitCallback = nil,
		_onSolidHitCallback = nil,
	}

	return handle, nil
end

function Modulo_Hitbox.CriarRaycastParamsAtacante(character: Model): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	return params
end

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

local function _EhParteSolida(raycastResult: RaycastResult): boolean
	local instancia = raycastResult.Instance
	if not instancia or not instancia:IsA("BasePart") then
		return false
	end
	local parte = instancia :: BasePart
	if not parte.CanCollide then
		return false
	end
	if parte.Transparency > 0.1 then
		return false
	end
	return true
end

function Modulo_Hitbox.AtivarHitbox(handle: HitboxHandle, onHit: OnHitCallback, duracao: number?, onSolidHit: OnSolidHitCallback?)
	if not handle or not handle.hitbox then
		warn("[Modulo_Hitbox] Handle inválido para AtivarHitbox")
		return
	end

	table.clear(handle.jaAtingidos)
	handle.jaAcertouSolido = false
	handle.ativa = true
	handle._onHitCallback = onHit
	handle._onSolidHitCallback = onSolidHit

	handle.hitbox:OnHit(function(raycastResult: RaycastResult, _segment: any)
		if not handle.ativa then
			return
		end

		local modelo = _FiltrarParaEntidadeViva(raycastResult)
		if modelo then
			if handle.jaAtingidos[modelo] then
				return
			end

			handle.jaAtingidos[modelo] = true

			if handle._onHitCallback then
				handle._onHitCallback(modelo, handle.mao)
			end
			return
		end

		if not handle.jaAcertouSolido and _EhParteSolida(raycastResult) then
			handle.jaAcertouSolido = true
			if handle._onSolidHitCallback then
				handle._onSolidHitCallback(raycastResult, handle.mao)
			end
		end
	end)

	handle.hitbox:OnStopped(function(cleanCallbacks)
		handle.ativa = false
		cleanCallbacks()
	end)

	handle.hitbox:HitStart(duracao)
end

function Modulo_Hitbox.PararHitbox(handle: HitboxHandle)
	if not handle or not handle.hitbox then
		return
	end

	handle.ativa = false
	handle.hitbox:HitStop()
end

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
