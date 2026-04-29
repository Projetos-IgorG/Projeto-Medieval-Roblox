--[[
    Script: Types.luau
    Caminho: src/ReplicatedStorage/Combate/Hitbox/Shapecast
    Responsabilidade: Centraliza tipos Luau usados pelo pacote Shapecast.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao roda sozinho nem cria fluxo de jogo por conta propria; depende dos scripts que importam este modulo.
]]
export type Hitbox = {
	Instance: Instance?,
	RaycastParams: RaycastParams?,
	RaycastResult: RaycastResult?,
	Active: boolean,
	Resolution: number,
	CastData: CastData,
	Attributes: { [any]: any },
	FilterPartsHit: boolean,
	GetAllSegments: (self: Hitbox) -> { [any]: Segment },
	GetSegment: (self: Hitbox, instance: Instance) -> Segment,
	AddSegment: (self: Hitbox, descendant: any) -> Segment,
	RemoveSegment: (self: Hitbox, descendant: any) -> Hitbox,
	Reconcile: (self: Hitbox) -> (),
	HitStart: (self: Hitbox, timer: number?, raycastParams: RaycastParams?) -> Hitbox,
	HitStop: (self: Hitbox) -> Hitbox,
	Destroy: (self: Hitbox) -> (),
	SetResolution: (self: Hitbox, resolution: number) -> Hitbox,
	SetCastData: (self: Hitbox, castData: CastData) -> Hitbox,
	BeforeStart: (self: Hitbox, startCallback: StartCallback) -> Hitbox,
	OnUpdate: (self: Hitbox, updateCallback: UpdateCallback) -> Hitbox,
	OnHit: (self: Hitbox, hitCallback: HitCallback) -> Hitbox,
	OnStopped: (self: Hitbox, stopCallback: StopCallback) -> Hitbox,
}

export type Segment = {
	Instance: any,
	Distance: number,
	Position: Vector3?,
	LastDirection: Vector3,
	RaycastResult: RaycastResult?,
	CastData: CastData,
	_update: (self: Segment) -> (),
}

export type CastData = {
	CastType: string,
	CFrame: CFrame,
	Size: Vector3,
	Radius: number,
	_LastCFrameBlockCast: CFrame?,
}

export type AdornmentData = {
	Adornment: LineHandleAdornment,
	LastUse: number,
}

export type SphereAdornmentData = {
	Adornment: SphereHandleAdornment,
	LastUse: number,
}

export type BoxAdornmentData = {
	Adornment: BoxHandleAdornment,
	LastUse: number,
}

export type StartCallback = () -> ()
export type UpdateCallback = (delta: number) -> ()
export type HitCallback = (raycastResult: RaycastResult, segmentHit: Segment) -> ()
export type StopCallback = typeof(function(_clearCallbacks) end)

return {}
