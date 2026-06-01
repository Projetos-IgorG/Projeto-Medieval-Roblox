--!strict

--[[
    Script: GerenciadorHitboxCliente.luau
    Caminho: src/ReplicatedStorage/Combate/Hitbox
    Responsabilidade: Controla hitboxes no cliente durante animacoes de combate e envia acertos candidatos ao servidor.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao roda sozinho nem cria fluxo de jogo por conta propria; depende dos scripts que importam este modulo.
    Funcoes principais: DefinirCallbackHit, DefinirCharacter, CriarHitboxParaMao, CriarHitboxesDisponiveis, IniciarAtaqueMao, PararAtaqueMao
]]
local Modulo_Hitbox = require(script.Parent)

local DEBUG_ENABLED = true

local function DebugPrint(...)
	if DEBUG_ENABLED then
		print(...)
	end
end

type Mao = Modulo_Hitbox.Mao
type HitboxHandle = Modulo_Hitbox.HitboxHandle

export type OnAlvoAtingido = (alvo: Model, mao: Mao) -> ()

local hitboxesPorMao: { [Mao]: HitboxHandle? } = {
	Right = nil,
	Left = nil,
}

local callbackAlvoAtingido: OnAlvoAtingido? = nil
local callbackParteSolida: ((raycastResult: RaycastResult, mao: Mao) -> ())? = nil

local character: Model? = nil

local GerenciadorHitboxCliente = {}

function GerenciadorHitboxCliente.DefinirCallbackHit(callback: OnAlvoAtingido)
	callbackAlvoAtingido = callback
end

function GerenciadorHitboxCliente.DefinirCallbackSolidHit(callback: (raycastResult: RaycastResult, mao: Mao) -> ())
	callbackParteSolida = callback
end

function GerenciadorHitboxCliente.DefinirCharacter(novoCharacter: Model)

	GerenciadorHitboxCliente.DestruirTodas()
	character = novoCharacter
end

function GerenciadorHitboxCliente.CriarHitboxParaMao(mao: Mao): (boolean, string?)
	if not character then
		return false, "Character não definido"
	end

	local handleAntigo = hitboxesPorMao[mao]
	if handleAntigo then
		Modulo_Hitbox.DestruirHitbox(handleAntigo)
		hitboxesPorMao[mao] = nil
	end

	local weaponModel = Modulo_Hitbox.BuscarWeaponModel(character, mao)
	if not weaponModel then
		DebugPrint("[GerenciadorHitbox] WeaponModel não encontrado para mão:", mao)
		return false, "WeaponModel" .. mao .. " não encontrado"
	end

	local raycastParams = Modulo_Hitbox.CriarRaycastParamsAtacante(character)

	local handle, erro = Modulo_Hitbox.CriarHitbox(weaponModel, mao, raycastParams)
	if not handle then
		return false, erro
	end

	hitboxesPorMao[mao] = handle
	DebugPrint("[GerenciadorHitbox] Hitbox criada para mão:", mao)
	return true, nil
end

function GerenciadorHitboxCliente.CriarHitboxesDisponiveis()
	GerenciadorHitboxCliente.CriarHitboxParaMao("Right")
	GerenciadorHitboxCliente.CriarHitboxParaMao("Left")
end

local function _OnHitInterno(alvo: Model, mao: Mao)
	DebugPrint(string.format("[GerenciadorHitbox] Hit: %s pela mão %s", alvo.Name, mao))

	if callbackAlvoAtingido then
		callbackAlvoAtingido(alvo, mao)
	end
end

local function _OnSolidHitInterno(raycastResult: RaycastResult, mao: Mao)
	DebugPrint(string.format("[GerenciadorHitbox] Solid Hit: %s pela mão %s", raycastResult.Instance.Name, mao))

	if callbackParteSolida then
		callbackParteSolida(raycastResult, mao)
	end
end

function GerenciadorHitboxCliente.IniciarAtaqueMao(mao: Mao, duracao: number?)
	local handle = hitboxesPorMao[mao]

	if not handle then
		local sucesso, erro = GerenciadorHitboxCliente.CriarHitboxParaMao(mao)
		if not sucesso then
			DebugPrint("[GerenciadorHitbox] Não foi possível iniciar ataque para mão", mao, ":", erro)
			return
		end
		handle = hitboxesPorMao[mao]
	end

	if not handle then
		return
	end

	if handle.ativa then
		Modulo_Hitbox.PararHitbox(handle)
	end

	Modulo_Hitbox.AtivarHitbox(handle, _OnHitInterno, duracao, _OnSolidHitInterno)
	DebugPrint("[GerenciadorHitbox] Hitbox ativada para mão:", mao)
end

function GerenciadorHitboxCliente.PararAtaqueMao(mao: Mao)
	local handle = hitboxesPorMao[mao]
	if not handle then
		return
	end

	Modulo_Hitbox.PararHitbox(handle)
	DebugPrint("[GerenciadorHitbox] Hitbox parada para mão:", mao)
end

function GerenciadorHitboxCliente.PararTodas()
	GerenciadorHitboxCliente.PararAtaqueMao("Right")
	GerenciadorHitboxCliente.PararAtaqueMao("Left")
end

local function _destruirHitboxMao(mao: Mao)
	local handle = hitboxesPorMao[mao]
	if handle then
		Modulo_Hitbox.DestruirHitbox(handle)
		hitboxesPorMao[mao] = nil
	end
end

function GerenciadorHitboxCliente.DestruirTodas()
	_destruirHitboxMao("Right")
	_destruirHitboxMao("Left")
end

function GerenciadorHitboxCliente.MaoAtiva(mao: Mao): boolean
	local handle = hitboxesPorMao[mao]
	return handle ~= nil and handle.ativa
end

function GerenciadorHitboxCliente.OnMarkerAttackRight(duracao: number?)
	GerenciadorHitboxCliente.IniciarAtaqueMao("Right", duracao)
end

function GerenciadorHitboxCliente.OnMarkerAttackLeft(duracao: number?)
	GerenciadorHitboxCliente.IniciarAtaqueMao("Left", duracao)
end

function GerenciadorHitboxCliente.OnMarkerAttackBoth(duracao: number?)
	GerenciadorHitboxCliente.IniciarAtaqueMao("Right", duracao)
	GerenciadorHitboxCliente.IniciarAtaqueMao("Left", duracao)
end

return GerenciadorHitboxCliente
