--!strict
--!native
--!optimize 2

--[[
    Script: init.luau
    Caminho: src/ReplicatedStorage/Combate/Hitbox/Shapecast
    Responsabilidade: Agrupa a API publica do pacote Shapecast usado pelas hitboxes.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao roda sozinho nem cria fluxo de jogo por conta propria; depende dos scripts que importam este modulo.
]]
local Types = require(script.Types)

export type Segment = Types.Segment
export type CastData = Types.CastData
export type Hitbox = Types.Hitbox
export type UpdateCallback = Types.UpdateCallback
export type HitCallback = Types.HitCallback
export type StopCallback = Types.StopCallback
export type AdornmentData = Types.AdornmentData
export type SphereAdornmentData = Types.SphereAdornmentData
export type BoxAdornmentData = Types.BoxAdornmentData

return {
	new = require(script.Engine),
	Settings = require(script.HitboxConfig),
	CastTypes = {
		Raycast = "Raycast",
		Blockcast = "Blockcast",
		Spherecast = "Spherecast",
	},
}
