--[[
	CameraBypass.luau
	Shared set of BaseParts the camera occlusion system should ignore.
	Parts in this set will NOT cause the camera to zoom in (Popper).
	No part properties are modified — only the camera raycast logic checks this set.
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
