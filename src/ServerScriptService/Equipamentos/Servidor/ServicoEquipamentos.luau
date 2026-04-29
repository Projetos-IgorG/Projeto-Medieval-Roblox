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
local ToolBuilder = require(Modulos:WaitForChild("Equipamentos"):WaitForChild("ConstrutorFerramentas"))
local ModEquip = require(Modulos:WaitForChild("Equipamentos"):WaitForChild("ValidacaoEquipamentos"))

local function OcultarComponentesTool(tool: Tool)
	for _, desc in ipairs(tool:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Transparency = 1
			desc.CanCollide = false
			desc.CanTouch = false
			desc.CanQuery = false
			desc.Massless = true
			desc.Anchored = true
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

local function LerModoDados(tool: Instance): string?
	local dadosF = tool:FindFirstChild("Dados")
	if not dadosF then
		return nil
	end
	local modoV = dadosF:FindFirstChild("modoAnimacao")
	if modoV then
		return modoV.Value
	end
	return nil
end

local function LerTipoDados(tool: Instance): string?
	local dadosF = tool:FindFirstChild("Dados")
	if not dadosF then
		return nil
	end
	local tipoV = dadosF:FindFirstChild("Tipo")
	if tipoV then
		return tipoV.Value
	end
	return nil
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
				local dados = child:FindFirstChild("Dados")
				if dados then
					local idValue = dados:FindFirstChild("Id")
					if idValue and idValue:IsA("StringValue") then
						if string.find(string.lower(idValue.Value), "flecha") then
							return child
						end
					end
				end
			end
		end
	end

	return nil
end

local function ConsumirTool(tool: Tool, dados: any): any
	local quantidade = dados.Quantidade or 1
	if quantidade > 1 then
		local dadosFolder = tool:FindFirstChild("Dados")
		if dadosFolder then
			local qtdValue = dadosFolder:FindFirstChild("Quantidade")
			if qtdValue then
				qtdValue.Value = quantidade - 1
				DebugPrint("[ServicoEquipamento] Quantidade decrementada para:", quantidade - 1)
			end
		end
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
	handleClone.Name = "Handle" .. sufixo

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
		local ehPunhos = toolNaMao
			and LerTipoDados(toolNaMao) == "ArmasEquipadas"
			and LerModoDados(toolNaMao) == "Punhos"
		if ehPunhos then
			dadosEquipamento[player][slot] = { acessoriosClonados = {} }
			cache = dadosEquipamento[player][slot]
		else
			DebugPrint("[ServicoEquipamento] Sem cache para criar joint no slot:", slot)
			return
		end
	end

	if toolNaMao and LerTipoDados(toolNaMao) ~= "ArmasEquipadas" then
		DebugPrint("[ServicoEquipamento] Tool na mão não é ArmasEquipadas, ignorando:", toolNaMao.Name)
		return
	end

	local toolEquipada
	if toolNaMao and LerModoDados(toolNaMao) == "Punhos" then
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

	local weaponModel = toolEquipada:FindFirstChild("WeaponModel")
	if not weaponModel or not weaponModel:IsA("Model") then
		DebugPrint("[ServicoEquipamento] WeaponModel não encontrado em", toolEquipada.Name)
		return
	end

	local handleOriginal = weaponModel:FindFirstChild("Handle")
	if not handleOriginal or not handleOriginal:IsA("BasePart") then
		DebugPrint("[ServicoEquipamento] Handle não encontrado dentro de WeaponModel em", toolEquipada.Name)
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
	DebugPrint("[ServicoEquipamento] ProcessarEquiparArma para:", player.Name, "- Tool:", tool.Name)

	local valido, motivo = ValidarCondicoesBasicas(player)
	if not valido then
		warn("[ServicoEquipamento] Equipar arma rejeitado:", motivo)
		return
	end

	if not ValidarPosseTool(player, tool) then
		warn("[ServicoEquipamento] Anti-exploit: Tool não pertence ao player:", player.Name)
		return
	end

	local dados = ToolBuilder.ExtrairDados(tool)
	if not dados then
		warn("[ServicoEquipamento] Falha ao extrair dados do Tool:", tool.Name)
		return
	end

	if dados.Tipo ~= "Armas" then
		warn("[ServicoEquipamento] Tool não é do tipo Armas:", dados.Tipo)
		return
	end

	local categoria = dados.Categoria
	if not categoria or not ModEquip.ValidarCategoria(categoria) then
		warn("[ServicoEquipamento] Categoria inválida:", tostring(categoria))
		return
	end

	local slotDestino = ModEquip.ObterSlotDestino(categoria)
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

		local armaEquipada = ToolBuilder.CriarArmaEquipada(dados, player.Backpack)
		if not armaEquipada then
			warn("[ServicoEquipamento] Falha ao criar ArmaEquipada! Restaurando tool original.")
			ToolBuilder.CriarTool(dados, player.Backpack)
			dadosEquipamento[player].RightArm = nil
			return
		end

		local rightArmOV = bracos:FindFirstChild("RightArm") :: ObjectValue
		if rightArmOV then
			rightArmOV.Value = armaEquipada
		end

		DebugPrint("[ServicoEquipamento] Arma equipada no RightArm:", armaEquipada.Name)

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

					local armaEquipada = ToolBuilder.CriarArmaEquipada(dados, player.Backpack)
					if not armaEquipada then
						ToolBuilder.CriarTool(dados, player.Backpack)
						dadosEquipamento[player].RightArm = nil
						return
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

	local quantidade = dados.Quantidade or 1
	if quantidade > 1 then
		local dadosFolderTool = tool:FindFirstChild("Dados")
		if dadosFolderTool then
			local qtdValue = dadosFolderTool:FindFirstChild("Quantidade")
			if qtdValue then
				qtdValue.Value = quantidade - 1
				DebugPrint("[ServicoEquipamento] Quantidade decrementada para (esquerda):", quantidade - 1)
			end
		end

		dados.Quantidade = 1
		local copiaTool
		if tipoEsq == "SegundaArma" then
			copiaTool = ToolBuilder.CriarArmaEquipada(dados, equipAtivos)
		else
			copiaTool = ToolBuilder.CriarTool(dados, equipAtivos)
			OcultarComponentesTool(copiaTool)
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
			local armaEquipada = ToolBuilder.CriarArmaEquipada(dados, equipAtivos)
			if not armaEquipada then
				warn("[ServicoEquipamento] Falha ao criar ArmaEquipada para esquerda")
				dadosEquipamento[player].LeftArm = nil
				return
			end
			armaEquipada.CanBeDropped = false
			tool = armaEquipada
			DebugPrint("[ServicoEquipamento] SegundaArma convertida para ArmaEquipada:", armaEquipada.Name)
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
	DebugPrint("[ServicoEquipamento] ProcessarEquiparArmadura para:", player.Name, "- Tool:", tool.Name)

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

	if dados.Tipo ~= "Armaduras" then
		warn("[ServicoEquipamento] Tool não é do tipo Armaduras:", dados.Tipo)
		return
	end

	local slot = dados.Slot
	if not slot or not ModEquip.ValidarSlotCorpo(slot) then
		warn("[ServicoEquipamento] Slot de corpo inválido:", tostring(slot))
		return
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
		local dadosFolderTool = tool:FindFirstChild("Dados")
		if dadosFolderTool then
			local qtdValue = dadosFolderTool:FindFirstChild("Quantidade")
			if qtdValue then
				qtdValue.Value = quantidade - 1
				DebugPrint("[ServicoEquipamento] Quantidade de armadura decrementada para:", quantidade - 1)
			end
		end

		dados.Quantidade = 1
		local copiaTool = ToolBuilder.CriarTool(dados, equipAtivos)
		if copiaTool then
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
		for _, child in ipairs(toolParaEquipar:GetChildren()) do
			if child:IsA("Accessory") then
				local clone = child:Clone()
				if PrepararCloneAcessorio(clone) then
					humanoid:AddAccessory(clone)
					table.insert(acessoriosClonados, clone)
					DebugPrint("[ServicoEquipamento] Acessório clonado:", clone.Name)
				end
			end
		end
		dadosEquipamento[player][slot].acessoriosClonados = acessoriosClonados
	end

	local slotOV = corpo:FindFirstChild(slot) :: ObjectValue
	if slotOV then
		slotOV.Value = toolParaEquipar
	end

	DebugPrint("[ServicoEquipamento] Armadura equipada no slot:", slot, "- Tool:", toolParaEquipar.Name)
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
			local toolRecriado = ToolBuilder.CriarTool(cache.dados, player.Backpack)
			if toolRecriado then
				DebugPrint("[ServicoEquipamento] Tool original recriado:", toolRecriado.Name)
			else
				warn("[ServicoEquipamento] Falha ao recriar Tool original!")
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
				ToolBuilder.CriarTool(cache.dados, player.Backpack)
				DebugPrint("[ServicoEquipamento] Item devolvido ao Backpack:", cache.tipoEsquerda or "desconhecido")
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
				local toolRecriado = ToolBuilder.CriarTool(dadosArmadura, player.Backpack)
				if toolRecriado then
					DebugPrint("[ServicoEquipamento] Armadura devolvida ao Backpack:", toolRecriado.Name)
				else
					warn("[ServicoEquipamento] Falha ao recriar armadura no Backpack!")
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
