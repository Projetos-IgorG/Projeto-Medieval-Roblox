--[[
    TestToolBuilder - Script de teste do módulo ToolBuilder (SIMPLIFICADO)
    ServerScriptService > TestToolBuilder.server.lua
    
    Testa apenas a criação de espada_ferro para jogadores já no jogo
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Aguardar módulo ToolBuilder
warn("[TEST] Aguardando módulo ToolBuilder...")
local ToolBuilder =
	require(ReplicatedStorage:WaitForChild("Modulos"):WaitForChild("Ferramentas"):WaitForChild("ToolBuilder"))
warn("[TEST] Módulo ToolBuilder carregado com sucesso!")

print("========================================")
print("[TEST] Iniciando teste da Espada de Ferro")
print("========================================")

-- ============================================
-- TESTE: Criar Espada de Ferro
-- ============================================
local function TestarEspadaDeFerro()
	print("\n[TEST] Criando Espada de Ferro...")

	local espadaData = {
		Tipo = "Arma",
		Nome = "Espada de Ferro",
		Id = "espada_ferro",
		Peso = 3.5,
		Quantidade = 1,
		Dano = 12,
		Alcance = 2.5,
		MaterialBase = "Lingote de Ferro",
		Upgrade = "Comum",
	}

	-- Criar pasta temporária para teste
	local folder = Instance.new("Folder")
	folder.Name = "TesteEspada"
	folder.Parent = workspace

	warn("[TEST] Chamando ToolBuilder.CriarTool...")
	local tool = ToolBuilder.CriarTool(espadaData, folder)

	if tool then
		print("[TEST] ✅ SUCESSO: Espada criada:", tool.Name)
		print("[TEST] Parent:", tool.Parent:GetFullName())

		-- Verificar dados
		warn("[TEST] Extraindo dados da espada...")
		local dados = ToolBuilder.ExtrairDados(tool)

		if dados then
			print("[TEST] ========== DADOS DA ESPADA ==========")
			print("[TEST] Nome:", dados.Nome)
			print("[TEST] Id:", dados.Id)
			print("[TEST] Tipo:", dados.Tipo)
			print("[TEST] Dano:", dados.Dano)
			print("[TEST] Alcance:", dados.Alcance)
			print("[TEST] Peso:", dados.Peso)
			print("[TEST] Quantidade:", dados.Quantidade)
			print("[TEST] MaterialBase:", dados.MaterialBase)
			print("[TEST] Upgrade:", dados.Upgrade)
			print("[TEST] ==========================================")
		else
			warn("[TEST] ⚠️ AVISO: Não foi possível extrair dados da espada!")
		end

		-- Calcular peso total
		local pesoTotal = ToolBuilder.CalcularPesoTotal(espadaData)
		print("[TEST] Peso total da espada:", pesoTotal, "kg")

		task.wait(3)
		print("[TEST] Removendo pasta de teste...")
		folder:Destroy()
		print("[TEST] ✅ Teste concluído com sucesso!")
	else
		warn("[TEST] ❌ ERRO: Não foi possível criar a espada!")
		warn("[TEST] Verifique se existe o template em:")
		warn("[TEST] ReplicatedStorage > ToolsTemplates > Armas > espada_ferro")
		folder:Destroy()
	end
end

-- ============================================
-- ADICIONAR ESPADA PARA JOGADORES EXISTENTES
-- ============================================
local function AdicionarEspadaParaJogadores()
	warn("[TEST] Procurando jogadores no servidor...")

	local jogadores = Players:GetPlayers()

	if #jogadores == 0 then
		warn("[TEST] ⚠️ Nenhum jogador encontrado no servidor!")
		warn("[TEST] Entre no jogo para testar a criação da espada na backpack.")
		return
	end

	print("[TEST] Jogadores encontrados:", #jogadores)

	for _, player in ipairs(jogadores) do
		warn("[TEST] Processando jogador:", player.Name)

		-- Verificar se o jogador tem character
		if player.Character then
			warn("[TEST] Character encontrado para:", player.Name)

			local espadaData = {
				Tipo = "Arma",
				Nome = "Espada de Ferro",
				Id = "espada_ferro",
				Peso = 3.5,
				Quantidade = 1,
				Dano = 12,
				Alcance = 2.5,
				MaterialBase = "Lingote de Ferro",
				Upgrade = "Comum",
			}

			local tool = ToolBuilder.CriarTool(espadaData, player.Backpack)

			if tool then
				print("[TEST] ✅ SUCESSO: Espada adicionada à backpack de", player.Name)
			else
				warn("[TEST] ❌ ERRO: Não foi possível adicionar espada para", player.Name)
			end
		else
			warn("[TEST] ⚠️ AVISO:", player.Name, "não tem character ainda. Aguardando...")

			-- Aguardar o character spawnar
			player.CharacterAdded:Connect(function(character)
				task.wait(1) -- Aguardar character carregar completamente

				warn("[TEST] Character spawnou para:", player.Name)

				local espadaData = {
					Tipo = "Arma",
					Nome = "Espada de Ferro",
					Id = "espada_ferro",
					Peso = 3.5,
					Quantidade = 1,
					Dano = 12,
					Alcance = 2.5,
					MaterialBase = "Lingote de Ferro",
					Upgrade = "Comum",
				}

				local tool = ToolBuilder.CriarTool(espadaData, player.Backpack)

				if tool then
					print("[TEST] ✅ SUCESSO: Espada adicionada à backpack de", player.Name)
				else
					warn("[TEST] ❌ ERRO: Não foi possível adicionar espada para", player.Name)
				end
			end)
		end
	end
end

-- ============================================
-- EXECUTAR TESTES
-- ============================================
warn("[TEST] Iniciando em 2 segundos...")
task.wait(2)

-- Teste básico
TestarEspadaDeFerro()

task.wait(1)

-- Adicionar espada para jogadores existentes
AdicionarEspadaParaJogadores()

print("\n========================================")
print("[TEST] Sistema de testes concluído!")
print("========================================\n")
