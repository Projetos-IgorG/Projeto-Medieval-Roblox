--[[
    Script: RequisitosDialogo.luau
    Caminho: src/ReplicatedStorage/Dialogo/Requisitos
    Responsabilidade: Avalia requisitos de dialogo antes de liberar falas ou escolhas.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao roda sozinho nem cria fluxo de jogo por conta propria; depende dos scripts que importam este modulo.
    Funcoes principais: ChecarRequisitos
]]
local GerenciadorRequisitos = {}

function GerenciadorRequisitos.ChecarRequisitos(player: Player, requisitos: { any }): boolean
	if not requisitos or #requisitos == 0 then
		return true
	end

	for _, req in ipairs(requisitos) do
		local tipoReq = req.Tipo
		local valorReq = req.Valor
		local nomeReq = req.Nome

		if tipoReq == "Tag" then
			local tagsFolder = player:FindFirstChild("Tags")
			if not tagsFolder then
				return false
			end

			if not tagsFolder:GetAttribute(valorReq) then
				return false
			end
		elseif tipoReq == "Level" then
			local leaderstats = player:FindFirstChild("leaderstats")
			if not leaderstats then
				return false
			end
			local nivel = leaderstats:FindFirstChild("Level") or leaderstats:FindFirstChild("Nivel")
			if not nivel or nivel.Value < valorReq then
				return false
			end
		elseif tipoReq == "Moedas" then
			local leaderstats = player:FindFirstChild("leaderstats")
			if not leaderstats then
				return false
			end
			local moedas = leaderstats:FindFirstChild("Moedas") or leaderstats:FindFirstChild("Ouro")
			if not moedas or moedas.Value < valorReq then
				return false
			end
		elseif tipoReq == "Item" then

			local backpack = player:FindFirstChild("Backpack")
			if not backpack or not backpack:FindFirstChild(nomeReq) then
				local char = player.Character
				if not char or not char:FindFirstChild(nomeReq) then
					return false
				end
			end
		end
	end

	return true
end

return GerenciadorRequisitos
