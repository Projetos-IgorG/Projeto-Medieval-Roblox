--[[
	Módulo responsável por unificar a checagem de requisitos do jogador no jogo.
	Pode ser usado tanto pelo Sistema de Diálogos quanto por Quests, Interações ou Lojas.
]]
local GerenciadorRequisitos = {}

-- Tipos de Requisitos Suportados:
-- 1. "Atributo" / "Tag" (ex: "JaConheceuFerreiro", "MissaoGuardaCompleta") - Verifica se o booleno existe ou é true
-- 2. "Level" - Verifica level geral
-- 3. "ProfissaoNivel" - Verifica o nível em uma profissão exata
-- 4. "Item" - Verifica se o jogador possui um item no inventário
-- 5. "Moedas" / "Ouro" - Verifica quantidade de dinheiro

function GerenciadorRequisitos.ChecarRequisitos(player: Player, requisitos: { any }): boolean
	if not requisitos or #requisitos == 0 then
		return true -- Se não tem requisito, passa direto
	end

	for _, req in ipairs(requisitos) do
		local tipoReq = req.Tipo
		local valorReq = req.Valor
		local nomeReq = req.Nome -- Usado pra Item, Tag, Profissao, etc

		if tipoReq == "Tag" then
			-- Checa no folder Tags do jogador se existe o Atributo com o Valor requisitado
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
			-- Adicione a logica para verificar no inventario / Backpack real do seu jogo
			local backpack = player:FindFirstChild("Backpack")
			if not backpack or not backpack:FindFirstChild(nomeReq) then
				-- Tentar checar no character (se estiver equipado)
				local char = player.Character
				if not char or not char:FindFirstChild(nomeReq) then
					return false
				end
			end

			-- Mais tipos de verificações podem ser adicionadas facilmente (StatusRegiao, Horario)
		end
	end

	return true
end

return GerenciadorRequisitos
