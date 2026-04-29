--[[
	Nome: Requirements
	Função: Centralizar a checagem de pré-requisitos de jogador.
	Responsabilidade:
		- Avaliar requisitos do tipo Tag, Level, Moedas e Item.
		- Retornar true apenas quando todos os requisitos forem atendidos.
	Comunicação: Consumido por sistemas de Diálogo, Quests, Interações e Lojas.
	Uso: local Req = require(ReplicatedStorage.Dialogo.Requisitos.RequisitosDialogo)
]]

local GerenciadorRequisitos = {}

-- Tipos suportados em req.Tipo: "Tag", "Level", "Moedas", "Item".

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
			-- Item considerado presente se estiver no Backpack ou já equipado no Character.
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
