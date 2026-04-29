--[[
    Script: BypassCamera.luau
    Caminho: src/ReplicatedStorage/Jogador/Camera/Estado
    Responsabilidade: Controla estados em que a camera deve ignorar travas ou transicoes comuns.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao roda sozinho nem cria fluxo de jogo por conta propria; depende dos scripts que importam este modulo.
    Funcoes principais: add, remove, clear, has
]]
local CameraBypass = {}

local _bypassed: { [BasePart]: boolean } = {}

function CameraBypass.add(part: BasePart)
	_bypassed[part] = true
end

function CameraBypass.remove(part: BasePart)
	_bypassed[part] = nil
end

function CameraBypass.clear()
	table.clear(_bypassed)
end

function CameraBypass.has(part: BasePart): boolean
	return _bypassed[part] == true
end

return CameraBypass
