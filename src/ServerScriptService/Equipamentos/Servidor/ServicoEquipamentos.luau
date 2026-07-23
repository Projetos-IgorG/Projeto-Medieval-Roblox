--[[
    Script: ServicoEquipamentos.luau
    Caminho: src/ServerScriptService/Equipamentos/Servidor
    Responsabilidade: Gerencia equipar, desequipar, criar e validar equipamentos no servidor.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao roda sozinho nem cria fluxo de jogo por conta propria; depende dos scripts que importam este modulo.
    Funcoes principais: ProcessarEquiparArma, _EquiparItemNaEsquerda, ProcessarEquiparArmadura, ProcessarDesequiparSlot, Iniciar, OcultarComponentesTool
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local DEBUG_ENABLED = false

local function DebugPrint(...)
	if DEBUG_ENABLED then
		print(...)
	end
end

local Modulos = ReplicatedStorage
local ToolBuilder = require(Modulos:WaitForChild("SistemaItens"):WaitForChild("ConstrutorTools") :: ModuleScript)
local ModEquip = require(Modulos:WaitForChild("SistemaItens"):WaitForChild("ValidacaoEquipamentos") :: ModuleScript)
local CatalogoItens =
	require(Modulos:WaitForChild("Dados"):WaitForChild("Itens"):WaitForChild("CatalogoItens") :: ModuleScript)

local function OcultarComponentesTool(tool: Tool)
	for _, desc in ipairs(tool:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Transparency = 1
			desc.CanCollide = false
			desc.CanTouch = false
			desc.CanQuery = false
			desc.Massless = true
			-- NAO ancorar: se a Part for o Handle, o Roblox solda o braco nele.
			-- Se estiver ancorado, o braco (e o personagem) fica preso no lugar.
			desc.Anchored = false
		elseif desc:IsA("Decal") or desc:IsA("Texture") then
			desc.Transparency = 1
		elseif desc:IsA("ParticleEmitter") or desc:IsA("Trail") or desc:IsA("Beam") or desc:IsA("Light") then
			desc.Enabled = false
		end
	end
end

local function PrepararCloneAcessorio(clone: Accessory): boolean
	local handle = clone:FindFirstChild("Handle")
	if not handle then
		clone:Destroy()
		return false
	end

	local instanciasParaDestruir: { Instance } = {}
	for _, part in ipairs(clone:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Transparency = 0
			part.Anchored = false
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.Massless = true
		elseif (part:IsA("JointInstance") and part.Name == "AccessoryWeld") or part:IsA("ProximityPrompt") then
			table.insert(instanciasParaDestruir, part)
		end
	end
	for _, inst in ipairs(instanciasParaDestruir) do
		inst:Destroy()
	end

	return true
end

-- Welda manualmente o acessorio no character (suporta R15 via attachments e R6 via fallback)
local function AdicionarAcessorioManual(character: Model, clone: Accessory)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local handle = clone:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		return
	end

	-- 1. Tentar achar o attachment correspondente no character
	local attachmentNaMochila = handle:FindFirstChildOfClass("Attachment")
	local attachmentNoChar = nil
	if attachmentNaMochila then
		attachmentNoChar = character:FindFirstChild(attachmentNaMochila.Name, true)
	end

	if attachmentNoChar and attachmentNoChar:IsA("Attachment") then
		-- Encontrou attachment correspondente! Weld igual o Roblox faz
		local targetPart = attachmentNoChar.Parent :: BasePart
		
		clone:SetAttribute("Equipamento", true)
		clone.Parent = character
		
		-- Alinha CFrame do Handle do Acessorio com o Attachment do Character
		handle.CFrame = targetPart.CFrame * attachmentNoChar.CFrame * attachmentNaMochila.CFrame:Inverse()
		
		local weld = Instance.new("Weld")
		weld.Name = "AccessoryWeld"
		weld.Part0 = handle
		weld.Part1 = targetPart
		weld.C0 = attachmentNaMochila.CFrame
		weld.C1 = attachmentNoChar.CFrame
		weld.Parent = handle
	else
		-- 2. Se nao encontrou attachment (caso do R6 sem attachments especificos),
		-- identifica a parte do corpo baseada no nome do acessorio ou do Slot
		local targetPartName = "Torso"
		local lowerName = clone.Name:lower()
		if lowerName:find("bracodireito") or lowerName:find("rightarm") then
			targetPartName = "Right Arm"
		elseif lowerName:find("bracoesquerdo") or lowerName:find("leftarm") then
			targetPartName = "Left Arm"
		elseif lowerName:find("pernadireita") or lowerName:find("rightleg") then
			targetPartName = "Right Leg"
		elseif lowerName:find("pernaesquerda") or lowerName:find("leftleg") then
			targetPartName = "Left Leg"
		elseif lowerName:find("cabeca") or lowerName:find("head") then
			targetPartName = "Head"
		end

		local targetPart = character:FindFirstChild(targetPartName)
		if targetPart and targetPart:IsA("BasePart") then
			clone:SetAttribute("Equipamento", true)
			clone.Parent = character
			
			-- Alinha CFrame ao centro da parte (offset zero para armadura R6 moldada)
			handle.CFrame = targetPart.CFrame
			
			local weld = Instance.new("Weld")
			weld.Name = "AccessoryWeld"
			weld.Part0 = handle
			weld.Part1 = targetPart
			weld.C0 = CFrame.new()
			weld.C1 = CFrame.new()
			weld.Parent = handle
		else
			-- Fallback para humanoid:AddAccessory caso seja R15 padrão
			if humanoid then
				clone:SetAttribute("Equipamento", true)
				humanoid:AddAccessory(clone)
			end
		end
	end
end


local function LerModoDados(tool: Instance): string?
	local id = tool:GetAttribute("Id")
	if typeof(id) ~= "string" then
		return nil
	end
	local dados = CatalogoItens.Get(id)
	return dados and dados.ModoAnimacao
end

local function LerTipoDados(tool: Instance): string?
	local id = tool:GetAttribute("Id")
	if typeof(id) ~= "string" then
		return tool:GetAttribute("Tipo") :: string?
	end
	local dados = CatalogoItens.Get(id)
	if dados then
		-- Mapeia os tipos do catálogo novo para os esperados pelo jogo
		if dados.Tipo == "Tool" then
			if dados.Subtipo == "Arma" then
				return "Armas"
			elseif dados.Subtipo == "Ferramenta" then
				return "Ferramentas"
			end
		elseif dados.Tipo == "Equipment" then
			return "Armaduras"
		end
		return dados.Tipo
	end
	return tool:GetAttribute("Tipo") :: string?
end

local ServicoEquipamento = {}

local COOLDOWN_EQUIPAMENTO = 0.3

local dadosEquipamento: { [Player]: { [string]: any } } = {}

local ultimaAcao: { [Player]: number } = {}

local function ObterEquipamento(player: Player): (Folder?, Folder?, Folder?, Folder?)
	local character = player.Character
	if not character then
		return nil, nil, nil, nil
	end

	local equipamento = character:FindFirstChild("Equipamento")
	if not equipamento then
		return nil, nil, nil, nil
	end

	local bracos = equipamento:FindFirstChild("Bracos")
	local corpo = equipamento:FindFirstChild("Corpo")
	local equipAtivos = equipamento:FindFirstChild("EquipamentosAtivos")

	return equipamento :: Folder, bracos :: Folder, corpo :: Folder, equipAtivos :: Folder
end

local function ObterHumanoid(player: Player): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

local function ObterBackpack(player: Player): any
	return player:FindFirstChildOfClass("Backpack") :: any
end

local function InicializarCache(player: Player)
	if not dadosEquipamento[player] then
		dadosEquipamento[player] = {}
	end
end

local function ObterSlotOV(player: Player, slotName: string): ObjectValue?
	local _, bracos, corpo = ObterEquipamento(player)

	if ModEquip.EhSlotBraco(slotName) then
		if bracos then
			return bracos:FindFirstChild(slotName) :: ObjectValue
		end
	elseif ModEquip.EhSlotCorpo(slotName) then
		if corpo then
			return corpo:FindFirstChild(slotName) :: ObjectValue
		end
	end

	return nil
end

local function SlotOcupado(player: Player, slotName: string): boolean
	local ov = ObterSlotOV(player, slotName)
	return ov ~= nil and ov.Value ~= nil
end

local function ObterCategoriaRightArm(player: Player): string?
	local _, bracos = ObterEquipamento(player)
	if not bracos then
		return nil
	end
	local rightArmOV = bracos:FindFirstChild("RightArm") :: ObjectValue
	if not rightArmOV or not rightArmOV.Value then
		return nil
	end
	return ModEquip.LerCategoria(rightArmOV.Value)
end

local function BuscarFlechasBackpack(player: Player): Tool?
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then
		return nil
	end

	for _, child in ipairs(backpack:GetChildren()) do
		if child:IsA("Tool") then
			local tipo = ModEquip.LerTipo(child)

			if tipo == "Materiais" then
				local id = child:GetAttribute("Id")
				if typeof(id) == "string" and string.find(string.lower(id), "flecha") then
					return child
				end
			end
		end
	end

	return nil
end

local function ConsumirTool(tool: Tool, dados: any): any
	local quantidade = tool:GetAttribute("Quantidade") or 1
	if quantidade > 1 then
		tool:SetAttribute("Quantidade", quantidade - 1)
		DebugPrint("[ServicoEquipamento] Quantidade decrementada para:", quantidade - 1)
		dados.Quantidade = 1
	else
		tool:Destroy()
		DebugPrint("[ServicoEquipamento] Tool original destruído (quantidade era 1)")
	end
	return dados
end

local SLOT_PARA_BRACO: { [string]: string } = {
	RightArm = "Right Arm",
	LeftArm = "Left Arm",
}

local function PrepararModelArma(model: Model)
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Transparency = if desc.Name == "HitboxPart" then 1 else 0
			desc.Anchored = false
			desc.CanCollide = false
			desc.CanTouch = false
			desc.CanQuery = false
			desc.Massless = true
		elseif desc:IsA("Decal") or desc:IsA("Texture") then
			desc.Transparency = 0
		elseif desc:IsA("Light") or desc:IsA("ParticleEmitter") or desc:IsA("Trail") or desc:IsA("Beam") then
			desc.Enabled = true
		elseif desc:IsA("ProximityPrompt") then
			desc:Destroy()
		end
	end
end

local SLOT_SUFIXO: { [string]: string } = {
	RightArm = "Right",
	LeftArm = "Left",
}

-- Monta um Model temporario contendo os filhos da Tool (estrutura flat).
-- A Tool tem Handle, Lamina, HitboxPart, etc., todos como filhos diretos.
-- Clona o tool inteiro para preservar WeldConstraints entre as partes (ex: Lamina presa no Handle).
-- O HitboxPart é mantido pois é necessário para a inicialização da hitbox de combate.
-- Apenas scripts, prompts de proximidade e configurações são removidos do clone visual.
local function MontarModelVisualDaTool(tool: Tool): Model?
	local handle = tool:FindFirstChild("Handle") :: BasePart
	if not handle or not handle:IsA("BasePart") then
		DebugPrint("[ServicoEquipamento] Tool sem Handle:", tool.Name)
		return nil
	end

	local cloneTool = tool:Clone()
	local modelVisual = Instance.new("Model")
	modelVisual.Name = "WeaponVisual"

	local hasWeaponModel = cloneTool:FindFirstChild("WeaponModel") ~= nil

	-- Move todos os filhos uteis (incluindo HitboxPart e WeldConstraints) do clone para o Model
	for _, filho in ipairs(cloneTool:GetChildren()) do
		if filho:IsA("Script") or filho:IsA("LocalScript") or filho:IsA("ProximityPrompt") or filho:IsA("Configuration") then
			filho:Destroy()
		elseif filho:IsA("Model") and filho.Name == "WeaponModel" then
			-- Descompacta os filhos do WeaponModel (ex: no Punhos) para ficarem flat no root
			for _, subFilho in ipairs(filho:GetChildren()) do
				if not (subFilho:IsA("Script") or subFilho:IsA("LocalScript") or subFilho:IsA("ProximityPrompt") or subFilho:IsA("Configuration")) then
					subFilho.Parent = modelVisual
				end
			end
			filho:Destroy()
		else
			if hasWeaponModel and filho.Name == "Handle" then
				-- Se temos um WeaponModel, o root Handle é sobressalente/placeholder do Roblox, então removemos
				filho:Destroy()
			else
				filho.Parent = modelVisual
			end
		end
	end
	cloneTool:Destroy()

	if not modelVisual:FindFirstChild("Handle") then
		modelVisual:Destroy()
		DebugPrint("[ServicoEquipamento] Handle nao encontrado ao montar model visual de:", tool.Name)
		return nil
	end

	return modelVisual
end


local function CriarJointParaBraco(
	weaponModel: Model,
	armPart: BasePart,
	slot: string,
	character: Model
): (Model, Motor6D)
	local sufixo = SLOT_SUFIXO[slot] or "Right"
	local jointName = slot .. "_WeaponJoint"

	local armaClone = weaponModel:Clone()
	PrepararModelArma(armaClone)

	armaClone.Name = "WeaponModel" .. sufixo
	local handleClone = armaClone:FindFirstChild("Handle") :: BasePart
	assert(handleClone, "[ServicoEquipamento] WeaponModel sem Handle!")
	-- Mantém o nome original como "Handle" para compatibilidade com animações
	handleClone.Name = "Handle"

	armaClone.Parent = character

	handleClone.CFrame = armPart.CFrame * CFrame.new(0, -1, 0) * CFrame.Angles(math.rad(-90), 0, 0)

	local joint = Instance.new("Motor6D")
	joint.Name = jointName
	joint.Part0 = armPart
	joint.Part1 = handleClone
	joint.C0 = armPart.CFrame:Inverse() * handleClone.CFrame
	joint.C1 = CFrame.new()
	joint.Parent = armPart

	return armaClone, joint
end

local function CriarJointArmaServerSide(player: Player, slot: string)
	local character = player.Character
	if not character then
		return
	end

	InicializarCache(player)
	local cache = dadosEquipamento[player][slot]

	local toolNaMao = character:FindFirstChildOfClass("Tool")

	if not cache then
		if toolNaMao and LerTipoDados(toolNaMao) == "Armas" then
			local dados = ToolBuilder.ExtrairDados(toolNaMao)
			if dados then
				dadosEquipamento[player][slot] = {
					dados = dados,
					acessoriosClonados = {},
				}
				cache = dadosEquipamento[player][slot]
			end
		end
	end

	if not cache then
		DebugPrint("[ServicoEquipamento] Sem cache para criar joint no slot:", slot)
		return
	end

	if toolNaMao and LerTipoDados(toolNaMao) ~= "Armas" then
		DebugPrint("[ServicoEquipamento] Tool na mão não é Armas, ignorando:", toolNaMao.Name)
		return
	end

	local toolEquipada
	if toolNaMao and LerTipoDados(toolNaMao) == "Armas" then
		toolEquipada = toolNaMao
	else
		local slotOV = ObterSlotOV(player, slot)
		if slotOV and slotOV.Value then
			toolEquipada = slotOV.Value
		end
	end

	if not toolEquipada then
		DebugPrint("[ServicoEquipamento] Slot sem referência para criar joint:", slot)
		return
	end

	-- Monta o Model visual a partir dos filhos flat da Tool (sem WeaponModel wrapper)
	local weaponModel = MontarModelVisualDaTool(toolEquipada)
	if not weaponModel then
		DebugPrint("[ServicoEquipamento] Nao foi possivel montar model visual de:", toolEquipada.Name)
		return
	end

	local handleOriginal = weaponModel:FindFirstChild("Handle")
	if not handleOriginal or not handleOriginal:IsA("BasePart") then
		weaponModel:Destroy()
		DebugPrint("[ServicoEquipamento] Handle nao encontrado no model visual de:", toolEquipada.Name)
		return
	end

	local ehPunhos = LerModoDados(toolEquipada) == "Punhos"

	if ehPunhos then
		local rightArm = character:FindFirstChild("Right Arm") :: BasePart
		local leftArm = character:FindFirstChild("Left Arm") :: BasePart
		if not rightArm or not leftArm then
			DebugPrint("[ServicoEquipamento] Braços não encontrados para Punhos")
			return
		end

		local existenteDir = rightArm:FindFirstChild("RightArm_WeaponJoint")
		if existenteDir then
			existenteDir:Destroy()
		end
		local existenteEsq = leftArm:FindFirstChild("LeftArm_WeaponJoint")
		if existenteEsq then
			existenteEsq:Destroy()
		end

		local cloneDir, jointDir = CriarJointParaBraco(weaponModel, rightArm, "RightArm", character)
		local cloneEsq, jointEsq = CriarJointParaBraco(weaponModel, leftArm, "LeftArm", character)
		weaponModel:Destroy() -- model temporario, ja clonado

		cache.armaModels = { cloneDir, cloneEsq }
		cache.armaJoints = { jointDir, jointEsq }

		DebugPrint("[ServicoEquipamento] Punhos: joints criados para ambos os braços")
	else
		local nomeBraco = SLOT_PARA_BRACO[slot]
		if not nomeBraco then
			warn("[ServicoEquipamento] Slot desconhecido para braço:", slot)
			return
		end

		local armPart = character:FindFirstChild(nomeBraco) :: BasePart
		if not armPart then
			DebugPrint("[ServicoEquipamento] Braço não encontrado:", nomeBraco)
			return
		end

		local jointName = slot .. "_WeaponJoint"

		local existente = armPart:FindFirstChild(jointName)
		if existente then
			existente:Destroy()
		end

		local armaClone, joint = CriarJointParaBraco(weaponModel, armPart, slot, character)
		weaponModel:Destroy() -- model temporario, ja clonado

		cache.armaModel = armaClone
		cache.armaJoint = joint

		DebugPrint("[ServicoEquipamento] Joint criado:", jointName, "para", toolEquipada.Name)
	end
end

local function RemoverJointArmaServerSide(player: Player, slot: string)
	InicializarCache(player)
	local cache = dadosEquipamento[player][slot]
	if not cache then
		return
	end

	if cache.armaJoints then
		for _, j in ipairs(cache.armaJoints) do
			if j and j.Parent then
				j:Destroy()
			end
		end
		cache.armaJoints = nil
	end
	if cache.armaJoint and cache.armaJoint.Parent then
		cache.armaJoint:Destroy()
	end
	cache.armaJoint = nil

	if cache.armaModels then
		for _, m in ipairs(cache.armaModels) do
			if m and m.Parent then
				m:Destroy()
			end
		end
		cache.armaModels = nil
	end
	if cache.armaModel and cache.armaModel.Parent then
		cache.armaModel:Destroy()
	end
	cache.armaModel = nil

	DebugPrint("[ServicoEquipamento] Joints/modelos de arma removidos para slot:", slot)
end

local function ValidarCondicoesBasicas(player: Player): (boolean, string?)
	local agora = tick()
	local ultima = ultimaAcao[player]
	if ultima and (agora - ultima) < COOLDOWN_EQUIPAMENTO then
		return false, "Cooldown"
	end

	local humanoid = ObterHumanoid(player)
	if not humanoid or humanoid.Health <= 0 then
		return false, "Player morto"
	end

	local character = player.Character
	if character then
		local status = character:FindFirstChild("Status")
		if status then
			local estadoAcao = status:FindFirstChild("estadoAcao")
			if estadoAcao and estadoAcao:IsA("StringValue") and estadoAcao.Value ~= "Nenhuma" then
				return false, "Em ação: " .. estadoAcao.Value
			end
		end
	end

	local equipamento = ObterEquipamento(player)
	if not equipamento then
		return false, "Sem folder Equipamento"
	end

	return true, nil
end

local function ValidarPosseTool(player: Player, tool: Tool): boolean
	if not tool or not tool:IsA("Tool") then
		return false
	end

	local parent = tool.Parent
	return parent == player:FindFirstChild("Backpack") or parent == player.Character
end

function ServicoEquipamento:ProcessarEquiparArma(player: Player, tool: Tool)
	if DEBUG_ENABLED then
		print("[Equip:SERVIDOR] 🗡️ EquiparArma recebido")
		print("  Jogador:", player.Name, "| Tool:", tool.Name)
		print("  Id:", tostring(tool:GetAttribute("Id")))
	end

	local valido, motivo = ValidarCondicoesBasicas(player)
	if not valido then
		warn("[ServicoEquipamento] Equipar arma rejeitado:", motivo)
		return
	end

	if not ValidarPosseTool(player, tool) then
		warn("[ServicoEquipamento] Anti-exploit: Tool nao pertence ao player:", player.Name)
		return
	end

	local dados = ToolBuilder.ExtrairDados(tool)
	if not dados then
		warn("[ServicoEquipamento] Falha ao extrair dados do Tool:", tool.Name)
		return
	end

	-- O catalogo define Tipo="Tool" + Subtipo="Arma" para armas.
	-- "Armas" nunca aparece como Tipo; a verificacao correta e pelo par Tipo+Subtipo.
	if dados.Tipo ~= "Tool" or dados.Subtipo ~= "Arma" then
		warn("[ServicoEquipamento] Tool nao e uma arma (Tipo:", dados.Tipo, "Subtipo:", dados.Subtipo, ")")
		return
	end

	local categoria = dados.Categoria
	if not categoria or not ModEquip.ValidarCategoria(categoria) then
		warn("[ServicoEquipamento] Categoria invalida:", tostring(categoria))
		return
	end

	local slotDestino = ModEquip.ObterSlotDestino(categoria)
	if DEBUG_ENABLED then
		print("  Subtipo:", dados.Subtipo, "| Categoria:", categoria)
		print("  Slot destino inicial:", tostring(slotDestino))
	end

	local _, bracos, _, equipAtivos = ObterEquipamento(player)
	if not bracos or not equipAtivos then
		return
	end

	InicializarCache(player)
	ultimaAcao[player] = tick()

	local humanoid = ObterHumanoid(player)

	if slotDestino == "RightArm" then
		if SlotOcupado(player, "RightArm") and categoria == "ArmasUmaMao" then
			local categoriaDir = ObterCategoriaRightArm(player)
			if categoriaDir == "ArmasUmaMao" then
				DebugPrint("[ServicoEquipamento] Dual-wield detectado: redirecionando para LeftArm")
				if SlotOcupado(player, "LeftArm") then
					self:ProcessarDesequiparSlot(player, "LeftArm")
				end
				self:_EquiparItemNaEsquerda(player, tool, "SegundaArma")
				return
			end
		end

		if SlotOcupado(player, "RightArm") then
			DebugPrint("[ServicoEquipamento] RightArm ocupado, desequipando primeiro")
			self:ProcessarDesequiparSlot(player, "RightArm")
		end

		if ModEquip.CategoriaBloqueiaMaoEsquerda(categoria) and SlotOcupado(player, "LeftArm") then
			DebugPrint("[ServicoEquipamento] Categoria bloqueia esquerda, limpando LeftArm")
			self:ProcessarDesequiparSlot(player, "LeftArm")
		end

		if categoria == "Arcos" then
			local flechas = BuscarFlechasBackpack(player)
			if not flechas then
				warn("[ServicoEquipamento] Arco requer flechas na Backpack! Equipando arco sem flechas.")
			end
		end

		dadosEquipamento[player].RightArm = {
			dados = dados,
			acessoriosClonados = {},
		}

		if humanoid then
			humanoid:UnequipTools()
		end

		dados = ConsumirTool(tool, dados)

		local armaEquipada = ToolBuilder.CriarTool(dados.Id, dados)
		if not armaEquipada then
			warn("[ServicoEquipamento] Falha ao criar Tool! Restaurando tool original.")
			local backpack = ObterBackpack(player)
			if backpack then
				ToolBuilder.EmpilharNoContainer(backpack, dados.Id, dados)
			end
			dadosEquipamento[player].RightArm = nil
			return
		end
		OcultarComponentesTool(armaEquipada) -- Torna o tool placeholder invisivel
		local backpack = ObterBackpack(player)
		if backpack then
			armaEquipada.Parent = backpack
		end

		local rightArmOV = bracos:FindFirstChild("RightArm") :: ObjectValue
		if rightArmOV then
			rightArmOV.Value = armaEquipada
		end

		if DEBUG_ENABLED then
			print("[Equip:SERVIDOR] ✅ Arma equipada com sucesso!")
			print("  Slot: RightArm (Mao Direita) | Tool:", armaEquipada.Name)
			print("  Categoria:", categoria)
		end

		if categoria == "Arcos" then
			local flechas = BuscarFlechasBackpack(player)
			if flechas then
				self:_EquiparItemNaEsquerda(player, flechas, "Flechas")
			end
		end

		return
	end

	if slotDestino == "LeftArm" or (categoria == "ArmasUmaMao" and SlotOcupado(player, "RightArm")) then
		local categoriaDir = ObterCategoriaRightArm(player)

		if (categoria :: string) == "Escudos" then
			if categoriaDir == "Arcos" then
				warn("[ServicoEquipamento] Conflito: Escudo + Arco. Desequipando arco primeiro.")
				self:ProcessarDesequiparSlot(player, "RightArm")
			end

			if categoriaDir == "ArmasDuasMaos" then
				warn("[ServicoEquipamento] Rejeita: Não pode equipar escudo com arma de duas mãos.")
				return
			end
		elseif categoria == "ArmasUmaMao" then
			if not categoriaDir or categoriaDir ~= "ArmasUmaMao" then
				if not SlotOcupado(player, "RightArm") then
					dadosEquipamento[player].RightArm = {
						dados = dados,
						acessoriosClonados = {},
					}

					if humanoid then
						humanoid:UnequipTools()
					end

					dados = ConsumirTool(tool, dados)

					local armaEquipada = ToolBuilder.CriarTool(dados.Id, dados)
					if not armaEquipada then
						warn("[ServicoEquipamento] Falha ao criar Tool! Restaurando tool original.")
						local backpack = ObterBackpack(player)
						if backpack then
							ToolBuilder.EmpilharNoContainer(backpack, dados.Id, dados)
						end
						dadosEquipamento[player].RightArm = nil
						return
					end
					local backpack = ObterBackpack(player)
					if backpack then
						armaEquipada.Parent = backpack
					end

					local rightArmOV = bracos:FindFirstChild("RightArm") :: ObjectValue
					if rightArmOV then
						rightArmOV.Value = armaEquipada
					end

					DebugPrint("[ServicoEquipamento] ArmasUmaMao equipada no RightArm (sem arma prévia)")
					return
				else
					warn("[ServicoEquipamento] Rejeita: RightArm não é ArmasUmaMao para dual-wield")
					return
				end
			end
		end

		if SlotOcupado(player, "LeftArm") then
			DebugPrint("[ServicoEquipamento] LeftArm ocupado, desequipando primeiro")
			self:ProcessarDesequiparSlot(player, "LeftArm")
		end

		self:_EquiparItemNaEsquerda(player, tool, (categoria :: string) == "Escudos" and "Escudo" or "SegundaArma")
		return
	end
end

function ServicoEquipamento:_EquiparItemNaEsquerda(player: Player, tool: Tool, tipoEsq: string)
	local _, bracos, _, equipAtivos = ObterEquipamento(player)
	if not bracos or not equipAtivos then
		return
	end

	InicializarCache(player)

	local dados = ToolBuilder.ExtrairDados(tool)
	if not dados then
		warn("[ServicoEquipamento] Falha ao extrair dados para LeftArm")
		return
	end

	dadosEquipamento[player].LeftArm = {
		dados = dados,
		tipoEsquerda = tipoEsq,
		acessoriosClonados = {},
	}

	local humanoid = ObterHumanoid(player)
	if humanoid then
		humanoid:UnequipTools()
	end

	local quantidade = tool:GetAttribute("Quantidade") or 1
	if quantidade > 1 then
		tool:SetAttribute("Quantidade", quantidade - 1)
		DebugPrint("[ServicoEquipamento] Quantidade decrementada para (esquerda):", quantidade - 1)

		dados.Quantidade = 1
		local copiaTool = ToolBuilder.CriarTool(dados.Id, dados)
		if copiaTool then
			copiaTool.Parent = equipAtivos
			if tipoEsq ~= "SegundaArma" then
				OcultarComponentesTool(copiaTool)
			end
		end
		if copiaTool then
			copiaTool.CanBeDropped = false
			tool = copiaTool
		else
			warn("[ServicoEquipamento] Falha ao criar cópia individual para esquerda")
			return
		end
	else
		if tipoEsq == "SegundaArma" then
			tool:Destroy()
			dados.Quantidade = 1
			local armaEquipada = ToolBuilder.CriarTool(dados.Id, dados)
			if not armaEquipada then
				warn("[ServicoEquipamento] Falha ao criar Tool para esquerda")
				dadosEquipamento[player].LeftArm = nil
				return
			end
			OcultarComponentesTool(armaEquipada) -- Torna o tool placeholder invisivel
			armaEquipada.Parent = equipAtivos
			armaEquipada.CanBeDropped = false
			tool = armaEquipada
			DebugPrint("[ServicoEquipamento] SegundaArma convertida para Tool:", armaEquipada.Name)
		else
			tool.CanBeDropped = false
			tool.Parent = equipAtivos
			OcultarComponentesTool(tool)
		end
	end

	local leftArmOV = bracos:FindFirstChild("LeftArm") :: ObjectValue
	if leftArmOV then
		leftArmOV.Value = tool
	end

	if tipoEsq == "Escudo" then
		CriarJointArmaServerSide(player, "LeftArm")
	end

	DebugPrint("[ServicoEquipamento] Item equipado na esquerda:", tool.Name, "Tipo:", tipoEsq)
end

function ServicoEquipamento:ProcessarEquiparArmadura(player: Player, tool: Tool)
	if DEBUG_ENABLED then
		print("[Equip:SERVIDOR] 🛡️ EquiparArmadura recebido")
		print("  Jogador:", player.Name, "| Tool:", tool.Name)
		print("  Id:", tostring(tool:GetAttribute("Id")))
	end

	local valido, motivo = ValidarCondicoesBasicas(player)
	if not valido then
		warn("[ServicoEquipamento] Equipar armadura rejeitado:", motivo)
		return
	end

	if not ValidarPosseTool(player, tool) then
		warn("[ServicoEquipamento] Anti-exploit: Tool não pertence ao player:", player.Name)
		return
	end

	local dados = ToolBuilder.ExtrairDados(tool)
	if not dados then
		warn("[ServicoEquipamento] Falha ao extrair dados da armadura:", tool.Name)
		return
	end

	-- O catalogo define Tipo="Equipment" para todos os equipamentos de corpo.
	-- "Armaduras" nunca aparece como Tipo; a verificacao correta e Tipo=="Equipment".
	if dados.Tipo ~= "Equipment" then
		warn(
			"[ServicoEquipamento] Tool nao e um equipamento de corpo (Tipo:",
			dados.Tipo,
			"Subtipo:",
			dados.Subtipo,
			")"
		)
		return
	end

	local slot = dados.Slot
	if not slot or not ModEquip.ValidarSlotCorpo(slot) then
		warn("[ServicoEquipamento] Slot de corpo invalido:", tostring(slot))
		return
	end

	if DEBUG_ENABLED then
		print("  Subtipo:", tostring(dados.Subtipo), "| Slot de corpo:", slot)
	end

	local _, _, corpo, equipAtivos = ObterEquipamento(player)
	if not corpo or not equipAtivos then
		return
	end

	InicializarCache(player)
	ultimaAcao[player] = tick()

	if SlotOcupado(player, slot) then
		DebugPrint("[ServicoEquipamento] Slot", slot, "ocupado, desequipando primeiro")
		self:ProcessarDesequiparSlot(player, slot)

		dados = ToolBuilder.ExtrairDados(tool)
		if not dados then
			warn("[ServicoEquipamento] Falha ao re-extrair dados da armadura após desequip")
			return
		end
	end

	dadosEquipamento[player][slot] = {
		dados = dados,
		acessoriosClonados = {},
	}

	local humanoid = ObterHumanoid(player)
	if humanoid then
		humanoid:UnequipTools()
	end

	local quantidade = dados.Quantidade or 1
	local toolParaEquipar = tool
	if quantidade > 1 then
		tool:SetAttribute("Quantidade", quantidade - 1)
		DebugPrint("[ServicoEquipamento] Quantidade de armadura decrementada para:", quantidade - 1)

		dados.Quantidade = 1
		local copiaTool = ToolBuilder.CriarTool(dados.Id, dados)
		if copiaTool then
			copiaTool.Parent = equipAtivos
			copiaTool.CanBeDropped = false
			toolParaEquipar = copiaTool
			DebugPrint("[ServicoEquipamento] Cópia de armadura criada no EquipamentosAtivos")
		else
			warn("[ServicoEquipamento] Falha ao criar cópia de armadura!")
			dadosEquipamento[player][slot] = nil
			return
		end
	else
		tool.CanBeDropped = false
		tool.Parent = equipAtivos
		toolParaEquipar = tool
	end

	OcultarComponentesTool(toolParaEquipar)

	local character = player.Character
	if character and humanoid then
		local acessoriosClonados = {}
		local totalFilhos = 0
		local totalAcessorios = 0
		for _, child in ipairs(toolParaEquipar:GetChildren()) do
			totalFilhos += 1
			if child:IsA("Accessory") then
				totalAcessorios += 1
				local clone = child:Clone()
				if PrepararCloneAcessorio(clone) then
					AdicionarAcessorioManual(character, clone)
					table.insert(acessoriosClonados, clone)
					DebugPrint("[ServicoEquipamento] Acessório clonado:", clone.Name)
				else
					DebugPrint("[ServicoEquipamento] PrepararCloneAcessorio falhou para:", child.Name)
				end

			end
		end
		DebugPrint("[ServicoEquipamento] Armadura - filhos do tool:", totalFilhos, "| Accessory encontrados:", totalAcessorios, "| clonados com sucesso:", #acessoriosClonados)
		dadosEquipamento[player][slot].acessoriosClonados = acessoriosClonados
	end

	local slotOV = corpo:FindFirstChild(slot) :: ObjectValue
	if slotOV then
		slotOV.Value = toolParaEquipar
	end

	if DEBUG_ENABLED then
		print("[Equip:SERVIDOR] ✅ Armadura equipada com sucesso!")
		print("  Slot:", slot, "| Tool:", toolParaEquipar.Name)
		print("  Subtipo:", tostring(dados.Subtipo))
	end
end

function ServicoEquipamento:ProcessarDesequiparSlot(player: Player, slotName: string)
	DebugPrint("[ServicoEquipamento] ProcessarDesequiparSlot:", slotName, "para:", player.Name)

	if not ModEquip.ValidarSlot(slotName) then
		warn("[ServicoEquipamento] Slot inválido:", slotName)
		return
	end

	local slotOV = ObterSlotOV(player, slotName)
	if not slotOV or not slotOV.Value then
		DebugPrint("[ServicoEquipamento] Slot já vazio:", slotName)
		return
	end

	InicializarCache(player)

	local cache = dadosEquipamento[player][slotName]
	local humanoid = ObterHumanoid(player)

	if slotName == "RightArm" then
		local toolEquipado = slotOV.Value
		local categoriaAnterior = cache and cache.dados and cache.dados.Categoria

		RemoverJointArmaServerSide(player, "RightArm")

		if toolEquipado and toolEquipado.Parent then
			if humanoid and toolEquipado.Parent == player.Character then
				humanoid:UnequipTools()
			end
			toolEquipado:Destroy()
			DebugPrint("[ServicoEquipamento] ArmaEquipada destruída")
		end

		if cache and cache.dados then
			local backpack = ObterBackpack(player)
			if backpack then
				ToolBuilder.EmpilharNoContainer(backpack, cache.dados.Id, cache.dados)
				DebugPrint("[ServicoEquipamento] Tool original devolvido (empilhado) ao Backpack")
			end
		end

		slotOV.Value = nil

		if SlotOcupado(player, "LeftArm") then
			local cacheEsq = dadosEquipamento[player].LeftArm
			if cacheEsq then
				local tipoEsq = cacheEsq.tipoEsquerda
				if (categoriaAnterior == "Arcos" and tipoEsq == "Flechas") or tipoEsq == "SegundaArma" then
					DebugPrint("[ServicoEquipamento] Removendo item da esquerda (consistência):", tipoEsq)
					self:ProcessarDesequiparSlot(player, "LeftArm")
				end
			end
		end

		dadosEquipamento[player].RightArm = nil
		return
	end

	if slotName == "LeftArm" then
		local toolEquipado = slotOV.Value

		RemoverJointArmaServerSide(player, "LeftArm")

		if toolEquipado and toolEquipado.Parent then
			if cache and cache.dados then
				local backpack = ObterBackpack(player)
				if backpack then
					ToolBuilder.EmpilharNoContainer(backpack, cache.dados.Id, cache.dados)
					DebugPrint("[ServicoEquipamento] Item devolvido (empilhado) ao Backpack")
				end
			end
			toolEquipado:Destroy()
		end

		slotOV.Value = nil
		dadosEquipamento[player].LeftArm = nil
		return
	end

	if ModEquip.EhSlotCorpo(slotName) then
		local toolEquipado = slotOV.Value

		if cache and cache.acessoriosClonados then
			for _, acessorio in ipairs(cache.acessoriosClonados) do
				if acessorio and acessorio.Parent then
					acessorio:Destroy()
				end
			end
			DebugPrint("[ServicoEquipamento] Acessórios de armadura removidos")
		end

		if toolEquipado and toolEquipado.Parent then
			local dadosArmadura = cache and cache.dados
			toolEquipado:Destroy()

			if dadosArmadura then
				local backpack = ObterBackpack(player)
				if backpack then
					ToolBuilder.EmpilharNoContainer(backpack, dadosArmadura.Id, dadosArmadura)
					DebugPrint("[ServicoEquipamento] Armadura devolvida (empilhada) ao Backpack")
				end
			end
		end

		slotOV.Value = nil
		dadosEquipamento[player][slotName] = nil
		return
	end
end

local function OnEquipamentoAcao(player: Player, acao: string, argumento: any)
	if type(acao) ~= "string" then
		warn("[ServicoEquipamento] Ação inválida de:", player.Name)
		return
	end

	DebugPrint("[ServicoEquipamento] Ação recebida:", acao, "de:", player.Name)

	if acao == "EquiparArma" then
		if not argumento or not (typeof(argumento) == "Instance" and argumento:IsA("Tool")) then
			warn("[ServicoEquipamento] Argumento inválido para EquiparArma")
			return
		end
		ServicoEquipamento:ProcessarEquiparArma(player, argumento)
	elseif acao == "EquiparArmadura" then
		if not argumento or not (typeof(argumento) == "Instance" and argumento:IsA("Tool")) then
			warn("[ServicoEquipamento] Argumento inválido para EquiparArmadura")
			return
		end
		ServicoEquipamento:ProcessarEquiparArmadura(player, argumento)
	elseif acao == "DesequiparSlot" then
		if type(argumento) ~= "string" then
			warn("[ServicoEquipamento] Argumento inválido para DesequiparSlot")
			return
		end

		local valido, motivo = ValidarCondicoesBasicas(player)
		if not valido then
			warn("[ServicoEquipamento] Desequipar rejeitado:", motivo)
			return
		end
		ultimaAcao[player] = tick()

		ServicoEquipamento:ProcessarDesequiparSlot(player, argumento)
	elseif acao == "ClonarAcessorio" then
		if type(argumento) ~= "string" or (argumento ~= "RightArm" and argumento ~= "LeftArm") then
			warn("[ServicoEquipamento] Argumento inválido para ClonarAcessorio:", tostring(argumento))
			return
		end
		CriarJointArmaServerSide(player, argumento)

		if argumento == "RightArm" then
			InicializarCache(player)
			local cacheEsq = dadosEquipamento[player].LeftArm
			if cacheEsq and cacheEsq.tipoEsquerda == "SegundaArma" then
				CriarJointArmaServerSide(player, "LeftArm")
				DebugPrint("[ServicoEquipamento] SegundaArma LeftArm joint criado junto com RightArm")
			end
		end
	elseif acao == "RemoverAcessorio" then
		if type(argumento) ~= "string" or (argumento ~= "RightArm" and argumento ~= "LeftArm") then
			warn("[ServicoEquipamento] Argumento inválido para RemoverAcessorio:", tostring(argumento))
			return
		end
		RemoverJointArmaServerSide(player, argumento)

		if argumento == "RightArm" then
			InicializarCache(player)
			local cacheEsq = dadosEquipamento[player].LeftArm
			if cacheEsq and cacheEsq.tipoEsquerda == "SegundaArma" then
				RemoverJointArmaServerSide(player, "LeftArm")
				DebugPrint("[ServicoEquipamento] SegundaArma LeftArm joint removido junto com RightArm")
			end
		end
	else
		warn("[ServicoEquipamento] Ação desconhecida:", acao)
	end
end

local function OnPlayerRemoving(player: Player)
	dadosEquipamento[player] = nil
	ultimaAcao[player] = nil
	DebugPrint("[ServicoEquipamento] Cache limpo para:", player.Name)
end

function ServicoEquipamento:Iniciar()
	DebugPrint("[ServicoEquipamento] Inicializando...")

	local Remotos = ReplicatedStorage:WaitForChild("Remotos")
	local EquipamentoAcao = Remotos:WaitForChild("EquipamentoAcao")
	EquipamentoAcao.OnServerEvent:Connect(OnEquipamentoAcao)

	Players.PlayerRemoving:Connect(OnPlayerRemoving)

	local function onCharacterAdded(player: Player)
		return function()
			dadosEquipamento[player] = nil
			DebugPrint("[ServicoEquipamento] Cache resetado para respawn:", player.Name)
		end
	end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(onCharacterAdded(player))
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterAdded:Connect(onCharacterAdded(player))
	end

	DebugPrint("[ServicoEquipamento] Inicializado com sucesso!")
end

return ServicoEquipamento
