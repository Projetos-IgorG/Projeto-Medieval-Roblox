--!native
--!strict
--!optimize 2

--[[
    Script: Blockcast.luau
    Caminho: src/ReplicatedStorage/Combate/Hitbox/Shapecast/Visualizers
    Responsabilidade: Desenha visualizacoes de depuracao para Blockcasts.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao detecta dano nem aplica hits; apenas mostra formas para depuracao visual.
    Funcoes principais: _CreateAdornment, GetAdornment, ToRender, ReturnAdornment, Clear
]]
local Types = require(script.Parent.Parent.Types)
local Settings = require(script.Parent.Parent.HitboxConfig)

local cache = {}
cache.__index = cache
cache.__type = `ShapecastHitbox_{script.Name}`
cache._AdornmentInUse = {}
cache._AdornmentInReserve = {}

function cache:_CreateAdornment(): Types.BoxAdornmentData
	local line: BoxHandleAdornment = Instance.new("BoxHandleAdornment")
	line.Name = "_ShapecastHitboxDebugger"
	line.Color3 = Settings.Debug_Instance_Color
	line.Transparency = Settings.Debug_Instance_Transparency
	line.Size = Vector3.zero
	line.CFrame = Settings.Debug_Instance_Derender_Location

	line.Adornee = workspace.Terrain
	line.Parent = workspace.Terrain

	return {
		Adornment = line,
		LastUse = 0,
	}
end

function cache:GetAdornment(): Types.BoxAdornmentData?
	if #cache._AdornmentInReserve <= 0 then

		local adornment: Types.BoxAdornmentData = cache:_CreateAdornment()
		table.insert(cache._AdornmentInReserve, adornment)
	end

	local adornment: Types.BoxAdornmentData? = table.remove(cache._AdornmentInReserve, 1)

	if adornment then
		adornment.Adornment.Visible = true
		adornment.LastUse = os.clock()
		table.insert(cache._AdornmentInUse, adornment)
	end

	return adornment
end

function cache:ToRender(
	adornment: Types.BoxAdornmentData,
	segment: Types.Segment,
	raycastResult: RaycastResult
)
	adornment.Adornment.Size = segment.CastData.Size
	adornment.Adornment.CFrame = (segment.CastData._LastCFrameBlockCast or segment.Instance.WorldCFrame)
		* segment.CastData.CFrame
	adornment.Adornment.Color3 = raycastResult and Settings.Debug_Instance_Hit_Color or Settings.Debug_Instance_Color
	adornment.Adornment.ZIndex = raycastResult and 999 or -1
end

function cache:ReturnAdornment(adornment: Types.BoxAdornmentData)
	adornment.Adornment.Size = Vector3.zero
	adornment.Adornment.Visible = false
	adornment.Adornment.CFrame = Settings.Debug_Instance_Derender_Location
	table.insert(cache._AdornmentInReserve, adornment)
end

function cache:Clear()
	for i: number = #cache._AdornmentInReserve, 1, -1 do
		if cache._AdornmentInReserve[i].Adornment then
			cache._AdornmentInReserve[i].Adornment:Destroy()
		end

		table.remove(cache._AdornmentInReserve, i)
	end
end

return cache
