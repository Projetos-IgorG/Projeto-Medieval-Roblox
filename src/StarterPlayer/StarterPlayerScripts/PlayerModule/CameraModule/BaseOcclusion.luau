--[[
    Script: BaseOcclusion.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/PlayerModule/CameraModule
    Responsabilidade: Define a base para controladores de oclusao da camera.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao implementa regras de gameplay do projeto; apenas apoia camera, controle e compatibilidade do jogador.
    Funcoes principais: new, CharacterAdded, CharacterRemoving, OnCameraSubjectChanged, GetOcclusionMode, Enable
]]
local BaseOcclusion: any = {}
BaseOcclusion.__index = BaseOcclusion
setmetatable(BaseOcclusion, {
	__call = function(_, ...)
		return BaseOcclusion.new(...)
	end,
})

function BaseOcclusion.new()
	local self = setmetatable({}, BaseOcclusion)
	return self
end

function BaseOcclusion:CharacterAdded(_char: Model, _player: Player) end

function BaseOcclusion:CharacterRemoving(_char: Model, _player: Player) end

function BaseOcclusion:OnCameraSubjectChanged(_newSubject) end

function BaseOcclusion:GetOcclusionMode(): Enum.DevCameraOcclusionMode?
	warn("BaseOcclusion GetOcclusionMode must be overridden by derived classes")
	return nil
end

function BaseOcclusion:Enable(_enabled: boolean)
	warn("BaseOcclusion Enable must be overridden by derived classes")
end

function BaseOcclusion:Update(_dt: number, desiredCameraCFrame: CFrame, desiredCameraFocus: CFrame)
	warn("BaseOcclusion Update must be overridden by derived classes")
	return desiredCameraCFrame, desiredCameraFocus
end

return BaseOcclusion
