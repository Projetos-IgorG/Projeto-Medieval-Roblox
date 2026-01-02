local Players = game:GetService("Players")

function PlayerAdded(Player)
	-- Quando o Character for carregado, cria a pasta Status dentro do Character
	Player.CharacterAdded:Connect(function(Character)
		local statusFolder = Instance.new("Folder")
		statusFolder.Name = "Status"
		statusFolder.Parent = Character

		-- Função para criar valor se não existir
		local function createValue(className, name, default)
			local v = Instance.new(className)
			v.Name = name
			if typeof(default) ~= "nil" then
				v.Value = default
			end
			v.Parent = statusFolder
			return v
		end

		-- Cria os valores esperados pelo sistema de combate
		-- Estados
		createValue("StringValue", "modoAnimacao", "Base")
		createValue("StringValue", "estadoMov", "Parado")
		createValue("StringValue", "estadoAcao", "Nenhuma")

		-- Flags
		createValue("BoolValue", "ShiftLockOn", false)
		createValue("BoolValue", "AgachadoOn", false)
		createValue("BoolValue", "BloqueandoOn", false)
		createValue("BoolValue", "ProntoAparar", false)
		createValue("BoolValue", "StunadoOn", false)
		createValue("BoolValue", "CorrendoOn", false)

		-- Atributos de combate
		createValue("NumberValue", "Forca", 0) -- Força (aumenta dano)
		createValue("NumberValue", "CritChance", 0) -- Chance extra de crítico
		createValue("NumberValue", "CritMult", 1.5) -- Multiplicador de crítico
	end)

	Player.CharacterAppearanceLoaded:Connect(function(Character)
		-- Remove acessórios que não sejam cabelo
		local parts = Character:GetChildren()
		for i = 1, #parts do
			local instanceA = parts[i]
			if instanceA.ClassName == "Accessory" then
				if not instanceA.Handle:FindFirstChild("HairAttachment") then
					parts[i]:Destroy()
				end
			end
		end
	end)
end

Players.PlayerAdded:Connect(PlayerAdded)
