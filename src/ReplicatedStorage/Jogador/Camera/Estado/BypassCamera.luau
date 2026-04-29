--[[
	Nome: CameraBypass
	Função: Lista compartilhada de BaseParts que o sistema de oclusão da câmera deve ignorar.
	Responsabilidade:
		- Manter um conjunto de partes que não devem causar zoom-in da câmera (Popper).
		- Não altera propriedades das partes; apenas a lógica de raycast da câmera consulta este conjunto.
	Comunicação: Consultado pelos scripts de câmera no cliente.
	Uso: local Bypass = require(ReplicatedStorage.Shared.Camera.Bypass)
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
