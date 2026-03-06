--[[
	GerenciadorHitboxCliente.luau
	
	Módulo client-side que gerencia hitboxes ativas por mão (Right / Left).
	Usa ShapecastHitbox via Modulo_Hitbox para rastrear DmgPoints quadro a quadro.
	
	Responsabilidades:
	- Criar/cachear hitboxes por mão ao equipar arma
	- Ativar/parar hitboxes nos markers de animação
	- Deduplicar alvos por mão (sets independentes)
	- Reportar hits ao servidor via RemoteEvent
	
	Markers de animação que controlam este módulo:
	  - "AttackRight" → ativa hitbox da mão direita
	  - "AttackLeft"  → ativa hitbox da mão esquerda
	  - "AttackBoth"  → ativa ambas as hitboxes
	  - "AttackEnd"   → para todas as hitboxes ativas
]]

--!strict

local _Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modulos = ReplicatedStorage:WaitForChild("Modulos")
local Modulo_Hitbox = require(Modulos:WaitForChild("Combate"):WaitForChild("Modulo_Hitbox"))

-- ═══════════════════════════════════════════════════════════════════
-- CONFIGURAÇÃO DE DEBUG
-- ═══════════════════════════════════════════════════════════════════

local DEBUG_ENABLED = true

local function DebugPrint(...)
	if DEBUG_ENABLED then
		print(...)
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- TYPES
-- ═══════════════════════════════════════════════════════════════════

type Mao = Modulo_Hitbox.Mao
type HitboxHandle = Modulo_Hitbox.HitboxHandle

--- Callback externo chamado quando um alvo é atingido.
--- O consumidor (ControladorEstado) decide o que fazer (enviar ao servidor, etc.)
export type OnAlvoAtingido = (alvo: Model, mao: Mao) -> ()

-- ═══════════════════════════════════════════════════════════════════
-- ESTADO INTERNO
-- ═══════════════════════════════════════════════════════════════════

--- Hitboxes cacheadas por mão (persistem enquanto a arma está equipada)
local hitboxesPorMao: { [Mao]: HitboxHandle? } = {
	Right = nil,
	Left = nil,
}

--- Callback configurado pelo consumidor (ControladorEstado)
local callbackAlvoAtingido: OnAlvoAtingido? = nil

--- Referência ao character atual
local character: Model? = nil

-- ═══════════════════════════════════════════════════════════════════
-- MÓDULO
-- ═══════════════════════════════════════════════════════════════════

local GerenciadorHitboxCliente = {}

-- ═══════════════════════════════════════════════════════════════════
-- CONFIGURAÇÃO
-- ═══════════════════════════════════════════════════════════════════

--- Define o callback chamado quando uma entidade é atingida.
--- Deve ser chamado uma vez durante a inicialização do script consumidor.
---@param callback OnAlvoAtingido
function GerenciadorHitboxCliente.DefinirCallbackHit(callback: OnAlvoAtingido)
	callbackAlvoAtingido = callback
end

--- Atualiza a referência do character (chamar ao trocar de character).
---@param novoCharacter Model
function GerenciadorHitboxCliente.DefinirCharacter(novoCharacter: Model)
	-- Destroi hitboxes anteriores se houver
	GerenciadorHitboxCliente.DestruirTodas()
	character = novoCharacter
end

-- ═══════════════════════════════════════════════════════════════════
-- GERENCIAMENTO DE HITBOXES
-- ═══════════════════════════════════════════════════════════════════

--- Cria (ou re-cria) a hitbox para uma mão específica.
--- Busca o WeaponModel correspondente no character.
--- Deve ser chamado quando a arma é equipada ou o WeaponModel muda.
---@param mao Mao
---@return boolean sucesso
---@return string? erro
function GerenciadorHitboxCliente.CriarHitboxParaMao(mao: Mao): (boolean, string?)
	if not character then
		return false, "Character não definido"
	end

	-- Destroi hitbox anterior dessa mão se existir
	local handleAntigo = hitboxesPorMao[mao]
	if handleAntigo then
		Modulo_Hitbox.DestruirHitbox(handleAntigo)
		hitboxesPorMao[mao] = nil
	end

	-- Busca WeaponModel
	local weaponModel = Modulo_Hitbox.BuscarWeaponModel(character, mao)
	if not weaponModel then
		DebugPrint("[GerenciadorHitbox] WeaponModel não encontrado para mão:", mao)
		return false, "WeaponModel" .. mao .. " não encontrado"
	end

	-- Cria RaycastParams excluindo o próprio character
	local raycastParams = Modulo_Hitbox.CriarRaycastParamsAtacante(character)

	-- Cria a hitbox
	local handle, erro = Modulo_Hitbox.CriarHitbox(weaponModel, mao, raycastParams)
	if not handle then
		return false, erro
	end

	hitboxesPorMao[mao] = handle
	DebugPrint("[GerenciadorHitbox] Hitbox criada para mão:", mao)
	return true, nil
end

--- Tenta criar hitboxes para ambas as mãos.
--- Ignora silenciosamente mãos sem WeaponModel (normal para armas de uma mão).
function GerenciadorHitboxCliente.CriarHitboxesDisponiveis()
	GerenciadorHitboxCliente.CriarHitboxParaMao("Right")
	GerenciadorHitboxCliente.CriarHitboxParaMao("Left")
end

-- ═══════════════════════════════════════════════════════════════════
-- ATIVAÇÃO / PARADA
-- ═══════════════════════════════════════════════════════════════════

--- Callback interno passado ao Modulo_Hitbox.AtivarHitbox.
--- Encaminha o hit para o callback externo configurado.
---@param alvo Model
---@param mao Mao
local function _OnHitInterno(alvo: Model, mao: Mao)
	DebugPrint(string.format("[GerenciadorHitbox] Hit: %s pela mão %s", alvo.Name, mao))

	if callbackAlvoAtingido then
		callbackAlvoAtingido(alvo, mao)
	end
end

--- Ativa a hitbox de uma mão específica.
--- Se a hitbox não existe, tenta criá-la automaticamente.
---@param mao Mao
---@param duracao number? Duração opcional (nil = até PararAtaqueMao)
function GerenciadorHitboxCliente.IniciarAtaqueMao(mao: Mao, duracao: number?)
	local handle = hitboxesPorMao[mao]

	-- Tenta criar se não existe
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

	-- Se já está ativa, para antes de reativar (garante estado limpo)
	if handle.ativa then
		Modulo_Hitbox.PararHitbox(handle)
	end

	Modulo_Hitbox.AtivarHitbox(handle, _OnHitInterno, duracao)
	DebugPrint("[GerenciadorHitbox] Hitbox ativada para mão:", mao)
end

--- Para a hitbox de uma mão específica.
---@param mao Mao
function GerenciadorHitboxCliente.PararAtaqueMao(mao: Mao)
	local handle = hitboxesPorMao[mao]
	if not handle then
		return
	end

	Modulo_Hitbox.PararHitbox(handle)
	DebugPrint("[GerenciadorHitbox] Hitbox parada para mão:", mao)
end

--- Para todas as hitboxes ativas.
function GerenciadorHitboxCliente.PararTodas()
	GerenciadorHitboxCliente.PararAtaqueMao("Right")
	GerenciadorHitboxCliente.PararAtaqueMao("Left")
end

--- Destroi a hitbox de uma mão específica (helper interno).
---@param mao Mao
local function _destruirHitboxMao(mao: Mao)
	local handle = hitboxesPorMao[mao]
	if handle then
		Modulo_Hitbox.DestruirHitbox(handle)
		hitboxesPorMao[mao] = nil
	end
end

--- Destroi todas as hitboxes (ao desequipar arma ou morrer).
function GerenciadorHitboxCliente.DestruirTodas()
	_destruirHitboxMao("Right")
	_destruirHitboxMao("Left")
end

--- Verifica se uma mão tem hitbox ativa.
---@param mao Mao
---@return boolean
function GerenciadorHitboxCliente.MaoAtiva(mao: Mao): boolean
	local handle = hitboxesPorMao[mao]
	return handle ~= nil and handle.ativa
end

-- ═══════════════════════════════════════════════════════════════════
-- ATALHOS PARA MARKERS DE ANIMAÇÃO
-- ═══════════════════════════════════════════════════════════════════

--- Processa o marker "AttackRight".
---@param duracao number?
function GerenciadorHitboxCliente.OnMarkerAttackRight(duracao: number?)
	GerenciadorHitboxCliente.IniciarAtaqueMao("Right", duracao)
end

--- Processa o marker "AttackLeft".
---@param duracao number?
function GerenciadorHitboxCliente.OnMarkerAttackLeft(duracao: number?)
	GerenciadorHitboxCliente.IniciarAtaqueMao("Left", duracao)
end

--- Processa o marker "AttackBoth" — ativa ambas as mãos independentemente.
---@param duracao number?
function GerenciadorHitboxCliente.OnMarkerAttackBoth(duracao: number?)
	GerenciadorHitboxCliente.IniciarAtaqueMao("Right", duracao)
	GerenciadorHitboxCliente.IniciarAtaqueMao("Left", duracao)
end

return GerenciadorHitboxCliente
