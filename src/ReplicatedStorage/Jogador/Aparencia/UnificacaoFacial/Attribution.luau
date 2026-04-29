--[[
	Script: Attribution.luau
	Caminho: src/ReplicatedStorage/Jogador/Aparencia/UnificacaoFacial
	Responsabilidade: Imprime atribuicao do autor e checa se a versao do Facial Unification esta atualizada.
	Uso: ModuleScript; carregado por UnificacaoFacial em runtime fora do Studio para preservar credito ao autor.
	Nao faz: Nao altera personagens nem descriptions; apenas escreve no console e consulta MarketplaceService.
	Funcoes principais: UpToDate
]]
local DEV = false
local VERSION = "v1.4"

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local function UpToDate()
	local asset = 85110005799468 -- Modelo oficial do autor

	local name = ""
	repeat
		local success, info = pcall(function()
			return MarketplaceService:GetProductInfoAsync(asset)
		end)
		if success and info then
			name = info.Name
			break
		end
		task.wait(1)
	until name ~= ""

	local latestVersion = VERSION
	latestVersion = string.match(name, "^Facial Unification (.*)$")
	return latestVersion ~= nil and latestVersion == VERSION
end

if DEV or not RunService:IsStudio() then
	local creator = Players:GetNameFromUserIdAsync(1371995) -- Dogutsune
	print(`🙂 Running Facial Unification ({VERSION}) by @{creator}`)
end

if not UpToDate() then
	warn("⚠️ Facial Unification has a new version! You can check the official DevForum post at: https://devforum.roblox.com/t/4312162")
end

return {}
