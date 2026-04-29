--[[
    Script: HitboxConfig.luau
    Caminho: src/ReplicatedStorage/Combate/Hitbox/Shapecast
    Responsabilidade: Define configuracoes padrao para hitboxes baseadas em Shapecast.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao roda sozinho nem cria fluxo de jogo por conta propria; depende dos scripts que importam este modulo.
]]
return {

	Tag = "DmgPoint",

	Minimum_Stationary_Length = 1,

	Debug_Visible = true,
	Debug_Instance_Raycast_Destroy_Time = 1,
	Debug_Instance_Spherecast_Destroy_Time = 0.1,
	Debug_Instance_Blockcast_Destroy_Time = 0.1,

	Debug_Instance_Transparency = 0.2,
	Debug_Instance_Color = Color3.fromRGB(255, 0, 0),
	Debug_Instance_Hit_Color = Color3.fromRGB(0, 255, 0),
	Debug_Instance_Raycast_Width = 10,
	Debug_Instance_Derender_Location = CFrame.new(0, math.huge, 0),
}
