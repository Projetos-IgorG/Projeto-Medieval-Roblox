--!strict

--[[
    Script: ConnectionUtil.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/PlayerModule/CommonUtils
    Responsabilidade: Ajuda a criar, substituir e limpar conexoes RBXScriptConnection.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao implementa regras de gameplay do projeto; apenas apoia camera, controle e compatibilidade do jogador.
    Funcoes principais: new, trackConnection, trackBoundFunction, disconnect, disconnectAll
]]
type ConnectionUtilClass = {
	__index: ConnectionUtilClass,
	new: () -> ConnectionUtil,

	trackConnection: (self: ConnectionUtil, string, RBXScriptConnection) -> (),

	trackBoundFunction: (self: ConnectionUtil, string, () -> ()) -> (),

	disconnect: (self: ConnectionUtil, string) -> (),

	disconnectAll: (self: ConnectionUtil) -> (),
}

export type ConnectionUtil = typeof(setmetatable({} :: {

	_connections: {[string]: () -> ()},
}, {} :: ConnectionUtilClass))

local ConnectionUtil: ConnectionUtilClass = {} :: ConnectionUtilClass;
ConnectionUtil.__index = ConnectionUtil

function ConnectionUtil.new()
	local self = setmetatable({}, ConnectionUtil)

	self._connections = {}

	return self
end

function ConnectionUtil:trackConnection(key, connection)
	if self._connections[key] then
		self._connections[key]()
	end

	self._connections[key] = function()
		connection:Disconnect()
	end
end

function ConnectionUtil:trackBoundFunction(key, disconnectionFunc)
	if self._connections[key] then
		self._connections[key]()
	end
	self._connections[key] = disconnectionFunc
end

function ConnectionUtil:disconnect(key)
	if self._connections[key] then
		self._connections[key]()
		self._connections[key] = nil
	end
end

function ConnectionUtil:disconnectAll()
	for _, disconnectFunc in pairs(self._connections) do
		disconnectFunc()
	end
	self._connections = {}
end

return ConnectionUtil
