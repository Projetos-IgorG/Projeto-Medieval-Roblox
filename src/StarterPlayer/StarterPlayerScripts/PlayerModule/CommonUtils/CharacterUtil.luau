--!strict

--[[
    Script: CharacterUtil.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/PlayerModule/CommonUtils
    Responsabilidade: Fornece utilitarios para localizar e acompanhar Character, Humanoid e partes.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao implementa regras de gameplay do projeto; apenas apoia camera, controle e compatibilidade do jogador.
    Funcoes principais: getLocalPlayer, onLocalPlayer, getCharacter, onCharacter, getChild, onChild
]]
local Players = game:GetService("Players")

local CommonUtils = script.Parent
local ConnectionUtil = require(CommonUtils:WaitForChild("ConnectionUtil"))

local CONNECTIONS = {
	LOCAL_PLAYER = "LOCAL_PLAYER",
	ON_LOCAL_PLAYER = "ON_LOCAL_PLAYER",
	CHARACTER_ADDED = "CHARACTER_ADDED",
	ON_CHARACTER = "ON_CHARACTER",
	CHARACTER_CHILD_ADDED = "CHARACTER_CHILD_ADDED",
}
export type CharacterUtilClass = {

	getLocalPlayer: () -> Player?,

	onLocalPlayer: (func: (Player) -> ()) -> RBXScriptConnection,

	getCharacter: () -> Model?,

	onCharacter: (func: (Model) -> ()) -> RBXScriptConnection,

	getChild: (name: string, className: string) -> Instance?,

	onChild: (name: string, className: string, func: (Instance) -> ()) -> RBXScriptConnection,

	_connectionUtil: ConnectionUtil.ConnectionUtil,

	_boundEvents: { [string]: BindableEvent },

	_getOrCreateBoundEvent: (name: string) -> BindableEvent,
}

local CharacterUtil: CharacterUtilClass = {} :: CharacterUtilClass

CharacterUtil._connectionUtil = ConnectionUtil.new()
CharacterUtil._boundEvents = {}

function CharacterUtil.getLocalPlayer()
	return Players.LocalPlayer
end

function CharacterUtil.onLocalPlayer(func)
	local localPlayer = CharacterUtil.getLocalPlayer()
	if localPlayer then
		func(localPlayer)
	end

	CharacterUtil._connectionUtil:trackConnection(
		CONNECTIONS.LOCAL_PLAYER,
		Players:GetPropertyChangedSignal("LocalPlayer"):Connect(function()
			local updatedLocalPlayer = CharacterUtil.getLocalPlayer()
			assert(updatedLocalPlayer, "LocalPlayer should exist when LocalPlayer property changes")
			CharacterUtil._getOrCreateBoundEvent(CONNECTIONS.LOCAL_PLAYER):Fire(updatedLocalPlayer)
		end)
	)

	local boundEvent = CharacterUtil._getOrCreateBoundEvent(CONNECTIONS.LOCAL_PLAYER)
	return boundEvent.Event:Connect(func)
end

function CharacterUtil.getCharacter()
	local localPlayer = CharacterUtil.getLocalPlayer()
	if not localPlayer then
		return nil
	end
	return localPlayer.Character
end

function CharacterUtil.onCharacter(func)
	CharacterUtil._connectionUtil:trackConnection(
		CONNECTIONS.ON_LOCAL_PLAYER,

		CharacterUtil.onLocalPlayer(function(localPlayer)
			local character = CharacterUtil.getCharacter()
			if character then
				func(character)
			end

			CharacterUtil._connectionUtil:trackConnection(
				CONNECTIONS.CHARACTER_ADDED,

				localPlayer.CharacterAdded:Connect(function(newCharacter)
					assert(newCharacter, "CharacterAdded must provide a character")
					CharacterUtil._getOrCreateBoundEvent(CONNECTIONS.CHARACTER_ADDED):Fire(newCharacter)
				end)
			)
		end)
	)

	local boundEvent = CharacterUtil._getOrCreateBoundEvent(CONNECTIONS.CHARACTER_ADDED)
	return boundEvent.Event:Connect(func)
end

function CharacterUtil.getChild(name: string, className: string)
	local character = CharacterUtil.getCharacter()
	if not character then
		return nil
	end
	local child = character:FindFirstChild(name)
	if child and child:IsA(className) then
		return child
	end
	return nil
end

function CharacterUtil.onChild(name: string, className: string, func)
	CharacterUtil._connectionUtil:trackConnection(
		CONNECTIONS.ON_CHARACTER,

		CharacterUtil.onCharacter(function(character)
			local child = CharacterUtil.getChild(name, className)
			if child then
				func(child)
			end

			CharacterUtil._connectionUtil:trackConnection(
				CONNECTIONS.CHARACTER_CHILD_ADDED,
				character.ChildAdded:Connect(function(newChild)
					if newChild.Name == name and newChild:IsA(className) then
						CharacterUtil._getOrCreateBoundEvent(CONNECTIONS.CHARACTER_CHILD_ADDED .. name .. className)
							:Fire(newChild)
					end
				end)
			)
		end)
	)

	local boundEvent = CharacterUtil._getOrCreateBoundEvent(CONNECTIONS.CHARACTER_CHILD_ADDED .. name .. className)
	return boundEvent.Event:Connect(func)
end

function CharacterUtil._getOrCreateBoundEvent(name: string)
	if not CharacterUtil._boundEvents[name] then
		CharacterUtil._boundEvents[name] = Instance.new("BindableEvent")
	end
	return CharacterUtil._boundEvents[name]
end

return CharacterUtil
