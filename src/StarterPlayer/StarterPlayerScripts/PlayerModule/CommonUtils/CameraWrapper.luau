--!strict

--[[
    Script: CameraWrapper.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/PlayerModule/CommonUtils
    Responsabilidade: Fornece um wrapper pequeno para acesso controlado a camera atual.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao implementa regras de gameplay do projeto; apenas apoia camera, controle e compatibilidade do jogador.
    Funcoes principais: new, _connectCallbacks, Enable, Disable, Connect, Disconnect
]]
local ConnectionUtil = require(script.Parent.ConnectionUtil)

type CameraWrapperClass = {
	__index: CameraWrapperClass,
	new: () -> CameraWrapper,

	Connect: (self: CameraWrapper, property: string, callback: () -> ()) -> (),

	Disconnect: (self: CameraWrapper, property: string) -> (),

	Enable: (self: CameraWrapper) -> (),
	Disable: (self: CameraWrapper) -> (),

	getCamera: (self: CameraWrapper) -> Camera?,

	_connectCallbacks: (self: CameraWrapper) -> (),
}

export type CameraWrapper = typeof(setmetatable(
	{} :: {

		_camera: Camera?,
		_cameraChangedConnection: RBXScriptConnection?,

		_callbacks: { [string]: () -> () },
		_connectionUtil: ConnectionUtil.ConnectionUtil,

		_enabled: boolean,
	},
	{} :: CameraWrapperClass
))

local CameraWrapper: CameraWrapperClass = {} :: CameraWrapperClass

CameraWrapper.__index = CameraWrapper

function CameraWrapper.new()
	local self = setmetatable({
		_camera = game.Workspace.CurrentCamera,

		_callbacks = {} :: { [string]: () -> () },
		_connectionUtil = ConnectionUtil.new(),

		_enabled = false,
	}, CameraWrapper)

	return self
end

function CameraWrapper:_connectCallbacks()
	self._camera = game.Workspace.CurrentCamera
	if not self._camera then
		return
	end

	for property, callback in self._callbacks do
		self._connectionUtil:trackConnection(
			property,
			self._camera:GetPropertyChangedSignal(property):Connect(callback)
		)

		callback()
	end
end

function CameraWrapper:Enable()
	if self._enabled then
		return
	end

	self._enabled = true

	self._cameraChangedConnection = game.Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		self:_connectCallbacks()
	end)

	self:_connectCallbacks()
end

function CameraWrapper:Disable()
	if not self._enabled then
		return
	end

	self._enabled = false

	if self._cameraChangedConnection then
		self._cameraChangedConnection:Disconnect()
		self._cameraChangedConnection = nil
	end

	self._connectionUtil:disconnectAll()
end

function CameraWrapper:Connect(property: string, callback: () -> ())
	self._callbacks[property] = callback

	if not self._camera then
		return
	end

	self._connectionUtil:trackConnection(property, self._camera:GetPropertyChangedSignal(property):Connect(callback))
end

function CameraWrapper:Disconnect(property: string)
	self._connectionUtil:disconnect(property)

	self._callbacks[property] = nil
end

function CameraWrapper:getCamera()
	return self._camera
end

return CameraWrapper
