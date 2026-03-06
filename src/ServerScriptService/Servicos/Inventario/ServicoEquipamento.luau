--[[
	ServicoEquipamento.luau
	ServerScriptService > Servicos > Inventario > ServicoEquipamento.luau

	Serviço server-side que gerencia toda a lógica de equipamento:
	- Equipar/desequipar armas (mão direita + dual-wield + escudo + arco)
	- Equipar/desequipar armaduras (slots do corpo)
	- Validação anti-exploit em todas as ações
	- Cache runtime dos dados originais para re-criação ao desequipar
	- Resolução de conflitos entre slots (arco vs escudo, 2 mãos bloqueia esquerda, etc.)
	- Gerenciamento de acessórios visuais de armaduras

	COMUNICAÇÃO: RemoteEvent unificado "EquipamentoAcao" com ações:
	  - "EquiparArma"     → (player, "EquiparArma", toolRef)
	  - "EquiparArmadura" → (player, "EquiparArmadura", toolRef)
	  - "DesequiparSlot"  → (player, "DesequiparSlot", slotName)

	ESTRUTURA NO CHARACTER:
	  Character.Equipamento (Folder)
	  ├── Bracos (Folder)
	  │   ├── RightArm (ObjectValue)
	  │   └── LeftArm (ObjectValue)
	  ├── Corpo (Folder)
	  │   ├── Head / Torso / Legs / Foot (ObjectValue)
	  └── EquipamentosAtivos (Folder)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- ═══════════════════════════════════════════════════════════════════
-- CONFIGURAÇÃO DE DEBUG
-- ═══════════════════════════════════════════════════════════════════
local DEBUG_ENABLED = false

local function DebugPrint(...)
	if DEBUG_ENABLED then
		print(...)
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- MÓDULOS
-- ═══════════════════════════════════════════════════════════════════
local Modulos = ReplicatedStorage:WaitForChild("Modulos")
local ToolBuilder = require(Modulos:WaitForChild("Ferramentas"):WaitForChild("ToolBuilder"))
local ModEquip = require(Modulos:WaitForChild("Jogador"):WaitForChild("Modulo_Equipamento"))

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES AUXILIARES DE ACESSÓRIO
-- ═══════════════════════════════════════════════════════════════════

--- Oculta todos os componentes visuais de um Tool (para Tools armazenados em EquipamentosAtivos)
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

--- Prepara um Accessory clonado para uso no Character:
--- torna BaseParts visíveis e desancoradas, remove AccessoryWelds e ProximityPrompts.
--- Retorna true se o clone está válido (tem Handle), false caso contrário (clone já é destruído).
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

--- Lê o valor de modoAnimacao de um Tool (via folder Dados)
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

--- Lê o valor de Tipo de um Tool (via folder Dados)
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

-- ═══════════════════════════════════════════════════════════════════
-- MÓDULO
-- ═══════════════════════════════════════════════════════════════════
local ServicoEquipamento = {}

-- ═══════════════════════════════════════════════════════════════════
-- CONSTANTES
-- ═══════════════════════════════════════════════════════════════════
local COOLDOWN_EQUIPAMENTO = 0.3 -- Mínimo entre ações de equipamento (anti-spam)

-- ═══════════════════════════════════════════════════════════════════
-- CACHE RUNTIME
-- ═══════════════════════════════════════════════════════════════════

-- dadosEquipamento[player] = { RightArm = {dados, acessoriosClonados}, LeftArm = {...}, Head = {...}, ... }
local dadosEquipamento: { [Player]: { [string]: any } } = {}

-- Cooldown por jogador
local ultimaAcao: { [Player]: number } = {}

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES UTILITÁRIAS
-- ═══════════════════════════════════════════════════════════════════

--- Obtém as referências do folder Equipamento do Character
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

--- Obtém o Humanoid do player
local function ObterHumanoid(player: Player): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

--- Inicializa cache do player se não existe
local function InicializarCache(player: Player)
	if not dadosEquipamento[player] then
		dadosEquipamento[player] = {}
	end
end

--- Obtém o ObjectValue de um slot específico
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

--- Verifica se um slot está ocupado
local function SlotOcupado(player: Player, slotName: string): boolean
	local ov = ObterSlotOV(player, slotName)
	return ov ~= nil and ov.Value ~= nil
end

--- Obtém a Categoria da arma equipada no RightArm
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

--- Busca flechas na Backpack do player
local function BuscarFlechasBackpack(player: Player): Tool?
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then
		return nil
	end

	for _, child in ipairs(backpack:GetChildren()) do
		if child:IsA("Tool") then
			local tipo = ModEquip.LerTipo(child)
			-- Flechas são do tipo "Materiais" com Id contendo "flecha"
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

--- Consome um tool: se quantidade > 1, decrementa; se == 1, destrói.
--- Retorna os dados atualizados (com Quantidade = 1).
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

-- ═══════════════════════════════════════════════════════════════════
-- ARMA VISUAL VIA MOTOR6D (SERVER-SIDE)
-- ═══════════════════════════════════════════════════════════════════

--- Mapeia o nome do slot para o nome da Part do braço no Character R6.
local SLOT_PARA_BRACO: { [string]: string } = {
	RightArm = "Right Arm",
	LeftArm = "Left Arm",
}

--- Prepara todas as BaseParts de um Model clonado de arma:
--- torna visíveis, desancoradas e sem colisão/toque.
local function PrepararModelArma(model: Model)
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			-- "Hitbox" permanece invisível (usada apenas para detecção de colisão/dano)
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

--- Sufixo de nome por slot: "Right" ou "Left".
local SLOT_SUFIXO: { [string]: string } = {
	RightArm = "Right",
	LeftArm = "Left",
}

--- Clona um WeaponModel, renomeia Model/Handle de acordo com o slot,
--- cria um Motor6D ligando o Handle ao braço e retorna (clone, joint).
--- O Motor6D usa C0 calculado a partir de um offset padrão na mão.
---@param weaponModel Model Modelo original dentro do Tool
---@param armPart BasePart Parte do braço ("Right Arm" ou "Left Arm")
---@param slot string "RightArm" ou "LeftArm"
---@param character Model Character do jogador
---@return Model armaClone, Motor6D joint
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

	-- Renomear Model e Handle de acordo com o slot
	armaClone.Name = "WeaponModel" .. sufixo
	local handleClone = armaClone:FindFirstChild("Handle") :: BasePart
	assert(handleClone, "[ServicoEquipamento] WeaponModel sem Handle!")
	handleClone.Name = "Handle" .. sufixo

	armaClone.Parent = character

	-- Posicionar handle aproximadamente na mão (offset padrão, ajustar in-game)
	handleClone.CFrame = armPart.CFrame * CFrame.new(0, -1, 0) * CFrame.Angles(math.rad(-90), 0, 0)

	-- Criar Motor6D "fotografando" o offset atual
	local joint = Instance.new("Motor6D")
	joint.Name = jointName
	joint.Part0 = armPart
	joint.Part1 = handleClone
	joint.C0 = armPart.CFrame:Inverse() * handleClone.CFrame
	joint.C1 = CFrame.new()
	joint.Parent = armPart

	return armaClone, joint
end

--- Cria joint(s) Motor6D para a arma equipada do jogador (server-side, visível para todos).
--- Para armas normais: clona WeaponModel e cria um Motor6D no braço do slot.
--- Para Punhos: clona WeaponModel duas vezes — uma para cada braço.
---@param player Player
---@param slot string "RightArm" ou "LeftArm"
local function CriarJointArmaServerSide(player: Player, slot: string)
	local character = player.Character
	if not character then
		return
	end

	InicializarCache(player)
	local cache = dadosEquipamento[player][slot]

	-- Verificar tool na mão
	local toolNaMao = character:FindFirstChildOfClass("Tool")

	-- Se não tem cache, verificar se é Punhos (não passa por ProcessarEquiparArma)
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

	-- Verificar se o Tool na mão é ArmasEquipadas
	if toolNaMao and LerTipoDados(toolNaMao) ~= "ArmasEquipadas" then
		DebugPrint("[ServicoEquipamento] Tool na mão não é ArmasEquipadas, ignorando:", toolNaMao.Name)
		return
	end

	-- Obter o tool: Punhos na mão tem prioridade, senão usa ObjectValue do slot
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

	-- Buscar WeaponModel dentro do Tool
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
		-- Punhos: clonar o mesmo WeaponModel para cada braço
		local rightArm = character:FindFirstChild("Right Arm") :: BasePart
		local leftArm = character:FindFirstChild("Left Arm") :: BasePart
		if not rightArm or not leftArm then
			DebugPrint("[ServicoEquipamento] Braços não encontrados para Punhos")
			return
		end

		-- Remover joints existentes se houver
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

		-- Guardar no cache — armaModels e armaJoints como listas para Punhos
		cache.armaModels = { cloneDir, cloneEsq }
		cache.armaJoints = { jointDir, jointEsq }

		DebugPrint("[ServicoEquipamento] Punhos: joints criados para ambos os braços")
	else
		-- Arma normal: clonar WeaponModel para o braço do slot
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

		-- Remover joint existente se houver
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

--- Remove joints e modelos de arma do Character do jogador.
---@param player Player
---@param slot string "RightArm" ou "LeftArm"
local function RemoverJointArmaServerSide(player: Player, slot: string)
	InicializarCache(player)
	local cache = dadosEquipamento[player][slot]
	if not cache then
		return
	end

	-- Limpar joint(s) e model(s) — suporta tanto campo único quanto listas (Punhos)
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

-- ═══════════════════════════════════════════════════════════════════
-- VALIDAÇÃO ANTI-EXPLOIT
-- ═══════════════════════════════════════════════════════════════════

--- Valida condições básicas antes de qualquer ação de equipamento
local function ValidarCondicoesBasicas(player: Player): (boolean, string?)
	-- Cooldown
	local agora = tick()
	local ultima = ultimaAcao[player]
	if ultima and (agora - ultima) < COOLDOWN_EQUIPAMENTO then
		return false, "Cooldown"
	end

	-- Player vivo
	local humanoid = ObterHumanoid(player)
	if not humanoid or humanoid.Health <= 0 then
		return false, "Player morto"
	end

	-- Verificar estado de ação (não pode equipar durante combate/stun/etc)
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

	-- Equipamento folder existe
	local equipamento = ObterEquipamento(player)
	if not equipamento then
		return false, "Sem folder Equipamento"
	end

	return true, nil
end

--- Valida que um Tool pertence ao player
local function ValidarPosseTool(player: Player, tool: Tool): boolean
	if not tool or not tool:IsA("Tool") then
		return false
	end

	local parent = tool.Parent
	return parent == player:FindFirstChild("Backpack") or parent == player.Character
end

-- ═══════════════════════════════════════════════════════════════════
-- EQUIPAR ARMA
-- ═══════════════════════════════════════════════════════════════════

--- Processa equipar uma arma (mão direita ou esquerda conforme categoria)
function ServicoEquipamento:ProcessarEquiparArma(player: Player, tool: Tool)
	DebugPrint("[ServicoEquipamento] ProcessarEquiparArma para:", player.Name, "- Tool:", tool.Name)

	-- Validar condições
	local valido, motivo = ValidarCondicoesBasicas(player)
	if not valido then
		warn("[ServicoEquipamento] Equipar arma rejeitado:", motivo)
		return
	end

	-- Validar posse
	if not ValidarPosseTool(player, tool) then
		warn("[ServicoEquipamento] Anti-exploit: Tool não pertence ao player:", player.Name)
		return
	end

	-- Extrair dados
	local dados = ToolBuilder.ExtrairDados(tool)
	if not dados then
		warn("[ServicoEquipamento] Falha ao extrair dados do Tool:", tool.Name)
		return
	end

	-- Validar tipo
	if dados.Tipo ~= "Armas" then
		warn("[ServicoEquipamento] Tool não é do tipo Armas:", dados.Tipo)
		return
	end

	-- Validar categoria
	local categoria = dados.Categoria
	if not categoria or not ModEquip.ValidarCategoria(categoria) then
		warn("[ServicoEquipamento] Categoria inválida:", tostring(categoria))
		return
	end

	-- Determinar slot destino
	local slotDestino = ModEquip.ObterSlotDestino(categoria)
	local _, bracos, _, equipAtivos = ObterEquipamento(player)
	if not bracos or not equipAtivos then
		return
	end

	InicializarCache(player)
	ultimaAcao[player] = tick()

	local humanoid = ObterHumanoid(player)

	-- ═══════════════════════════
	-- EQUIPAR NA MÃO DIREITA
	-- ═══════════════════════════
	if slotDestino == "RightArm" then
		-- Se já tem arma no RightArm E a nova é ArmasUmaMao → redirecionar para LeftArm (dual-wield)
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

		-- Se já tem arma no RightArm (não dual-wield) → desequipar primeiro
		if SlotOcupado(player, "RightArm") then
			DebugPrint("[ServicoEquipamento] RightArm ocupado, desequipando primeiro")
			self:ProcessarDesequiparSlot(player, "RightArm")
		end

		-- Se categoria bloqueia mão esquerda → limpar LeftArm
		if ModEquip.CategoriaBloqueiaMaoEsquerda(categoria) and SlotOcupado(player, "LeftArm") then
			DebugPrint("[ServicoEquipamento] Categoria bloqueia esquerda, limpando LeftArm")
			self:ProcessarDesequiparSlot(player, "LeftArm")
		end

		-- Se é arco → verificar se tem flechas para auto-equipar
		if categoria == "Arcos" then
			local flechas = BuscarFlechasBackpack(player)
			if not flechas then
				warn("[ServicoEquipamento] Arco requer flechas na Backpack! Equipando arco sem flechas.")
			end
		end

		-- Salvar dados no cache
		dadosEquipamento[player].RightArm = {
			dados = dados,
			acessoriosClonados = {},
		}

		-- Desequipar tool atual das mãos
		if humanoid then
			humanoid:UnequipTools()
		end

		-- Consumir tool original
		dados = ConsumirTool(tool, dados)

		-- Criar ArmaEquipada
		local armaEquipada = ToolBuilder.CriarArmaEquipada(dados, player.Backpack)
		if not armaEquipada then
			warn("[ServicoEquipamento] Falha ao criar ArmaEquipada! Restaurando tool original.")
			ToolBuilder.CriarTool(dados, player.Backpack)
			dadosEquipamento[player].RightArm = nil
			return
		end

		-- Setar referência ObjectValue
		local rightArmOV = bracos:FindFirstChild("RightArm") :: ObjectValue
		if rightArmOV then
			rightArmOV.Value = armaEquipada
		end

		DebugPrint("[ServicoEquipamento] Arma equipada no RightArm:", armaEquipada.Name)

		-- Se é arco → auto-equipar flechas na esquerda
		if categoria == "Arcos" then
			local flechas = BuscarFlechasBackpack(player)
			if flechas then
				self:_EquiparItemNaEsquerda(player, flechas, "Flechas")
			end
		end

		return
	end

	-- ═══════════════════════════
	-- EQUIPAR NA MÃO ESQUERDA (Escudo ou Dual-Wield)
	-- ═══════════════════════════
	if slotDestino == "LeftArm" or (categoria == "ArmasUmaMao" and SlotOcupado(player, "RightArm")) then
		local categoriaDir = ObterCategoriaRightArm(player)

		if (categoria :: string) == "Escudos" then
			-- Verificar conflito: Escudo + Arco
			if categoriaDir == "Arcos" then
				warn("[ServicoEquipamento] Conflito: Escudo + Arco. Desequipando arco primeiro.")
				self:ProcessarDesequiparSlot(player, "RightArm")
			end
			-- Verificar conflito: Escudo + DuasMaos
			if categoriaDir == "ArmasDuasMaos" then
				warn("[ServicoEquipamento] Rejeita: Não pode equipar escudo com arma de duas mãos.")
				return
			end
		elseif categoria == "ArmasUmaMao" then
			-- Dual-wield: validar que RightArm tem ArmasUmaMao
			if not categoriaDir or categoriaDir ~= "ArmasUmaMao" then
				if not SlotOcupado(player, "RightArm") then
					-- Sem arma na direita, vai para direita normalmente
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

		-- Se já tem algo na esquerda → desequipar primeiro
		if SlotOcupado(player, "LeftArm") then
			DebugPrint("[ServicoEquipamento] LeftArm ocupado, desequipando primeiro")
			self:ProcessarDesequiparSlot(player, "LeftArm")
		end

		-- Equipar na esquerda
		self:_EquiparItemNaEsquerda(player, tool, (categoria :: string) == "Escudos" and "Escudo" or "SegundaArma")
		return
	end
end

--- Função interna para equipar um item na mão esquerda
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

	-- Salvar no cache
	dadosEquipamento[player].LeftArm = {
		dados = dados,
		tipoEsquerda = tipoEsq,
		acessoriosClonados = {},
	}

	local humanoid = ObterHumanoid(player)
	if humanoid then
		humanoid:UnequipTools()
	end

	-- Consumir tool original: se quantidade > 1, decrementar e clonar; se == 1, reparentar
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
		-- Recriar uma cópia individual no EquipamentosAtivos
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
			-- SegundaArma: destruir tool original e criar ArmaEquipada
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
			-- Escudo/Flechas: apenas reparentar
			tool.CanBeDropped = false
			tool.Parent = equipAtivos
			OcultarComponentesTool(tool)
		end
	end

	-- Setar referência
	local leftArmOV = bracos:FindFirstChild("LeftArm") :: ObjectValue
	if leftArmOV then
		leftArmOV.Value = tool
	end

	-- Clonar acessório server-side para LeftArm
	-- Escudo: clonar imediatamente (sempre visível, independente da animação)
	-- SegundaArma: NÃO clonar agora — será clonado junto com RightArm no marker "Equip" da animação
	if tipoEsq == "Escudo" then
		CriarJointArmaServerSide(player, "LeftArm")
	end

	DebugPrint("[ServicoEquipamento] Item equipado na esquerda:", tool.Name, "Tipo:", tipoEsq)
end

-- ═══════════════════════════════════════════════════════════════════
-- EQUIPAR ARMADURA
-- ═══════════════════════════════════════════════════════════════════

--- Processa equipar uma armadura em um slot do corpo
function ServicoEquipamento:ProcessarEquiparArmadura(player: Player, tool: Tool)
	DebugPrint("[ServicoEquipamento] ProcessarEquiparArmadura para:", player.Name, "- Tool:", tool.Name)

	-- Validar condições
	local valido, motivo = ValidarCondicoesBasicas(player)
	if not valido then
		warn("[ServicoEquipamento] Equipar armadura rejeitado:", motivo)
		return
	end

	-- Validar posse
	if not ValidarPosseTool(player, tool) then
		warn("[ServicoEquipamento] Anti-exploit: Tool não pertence ao player:", player.Name)
		return
	end

	-- Extrair dados
	local dados = ToolBuilder.ExtrairDados(tool)
	if not dados then
		warn("[ServicoEquipamento] Falha ao extrair dados da armadura:", tool.Name)
		return
	end

	-- Validar tipo
	if dados.Tipo ~= "Armaduras" then
		warn("[ServicoEquipamento] Tool não é do tipo Armaduras:", dados.Tipo)
		return
	end

	-- Obter slot do corpo
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

	-- Se slot já ocupado → desequipar primeiro
	if SlotOcupado(player, slot) then
		DebugPrint("[ServicoEquipamento] Slot", slot, "ocupado, desequipando primeiro")
		self:ProcessarDesequiparSlot(player, slot)

		-- Re-extrair dados (o tool na mão pode ter sido empilhado durante o desequipar)
		dados = ToolBuilder.ExtrairDados(tool)
		if not dados then
			warn("[ServicoEquipamento] Falha ao re-extrair dados da armadura após desequip")
			return
		end
	end

	-- Salvar dados no cache
	dadosEquipamento[player][slot] = {
		dados = dados,
		acessoriosClonados = {},
	}

	-- Desequipar das mãos
	local humanoid = ObterHumanoid(player)
	if humanoid then
		humanoid:UnequipTools()
	end

	-- Consumir tool: se quantidade > 1, decrementar e criar cópia; se == 1, reparentar
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
		-- Criar cópia individual no EquipamentosAtivos
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

	-- Ocultar componentes visuais internos do Tool (só os clones no Character serão visíveis)
	OcultarComponentesTool(toolParaEquipar)

	-- Clonar acessórios para o Character (visual, server-side)
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

	-- Setar referência ObjectValue
	local slotOV = corpo:FindFirstChild(slot) :: ObjectValue
	if slotOV then
		slotOV.Value = toolParaEquipar
	end

	DebugPrint("[ServicoEquipamento] Armadura equipada no slot:", slot, "- Tool:", toolParaEquipar.Name)
end

-- ═══════════════════════════════════════════════════════════════════
-- DESEQUIPAR SLOT
-- ═══════════════════════════════════════════════════════════════════

--- Processa desequipar um slot (braço ou corpo)
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

	-- ═══════════════════════════
	-- DESEQUIPAR RIGHTARM
	-- ═══════════════════════════
	if slotName == "RightArm" then
		local toolEquipado = slotOV.Value
		local categoriaAnterior = cache and cache.dados and cache.dados.Categoria

		-- Remover joints/modelos de arma do Character
		RemoverJointArmaServerSide(player, "RightArm")

		-- Destruir ArmaEquipada da Backpack/Character
		if toolEquipado and toolEquipado.Parent then
			if humanoid and toolEquipado.Parent == player.Character then
				humanoid:UnequipTools()
			end
			toolEquipado:Destroy()
			DebugPrint("[ServicoEquipamento] ArmaEquipada destruída")
		end

		-- Re-criar Tool original na Backpack
		if cache and cache.dados then
			local toolRecriado = ToolBuilder.CriarTool(cache.dados, player.Backpack)
			if toolRecriado then
				DebugPrint("[ServicoEquipamento] Tool original recriado:", toolRecriado.Name)
			else
				warn("[ServicoEquipamento] Falha ao recriar Tool original!")
			end
		end

		-- Limpar referência
		slotOV.Value = nil

		-- Regras de consistência com a esquerda: Arco → limpar flechas, Dual-wield → limpar segunda arma
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

		-- Limpar cache
		dadosEquipamento[player].RightArm = nil
		return
	end

	-- ═══════════════════════════
	-- DESEQUIPAR LEFTARM
	-- ═══════════════════════════
	if slotName == "LeftArm" then
		local toolEquipado = slotOV.Value

		-- Remover joints/modelos de arma do Character
		RemoverJointArmaServerSide(player, "LeftArm")

		-- Devolver item ao Backpack e destruir do EquipamentosAtivos
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

	-- ═══════════════════════════
	-- DESEQUIPAR SLOT DO CORPO
	-- ═══════════════════════════
	if ModEquip.EhSlotCorpo(slotName) then
		local toolEquipado = slotOV.Value

		-- Remover acessórios clonados do Character
		if cache and cache.acessoriosClonados then
			for _, acessorio in ipairs(cache.acessoriosClonados) do
				if acessorio and acessorio.Parent then
					acessorio:Destroy()
				end
			end
			DebugPrint("[ServicoEquipamento] Acessórios de armadura removidos")
		end

		-- Devolver armadura ao Backpack (com empilhamento)
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

-- ═══════════════════════════════════════════════════════════════════
-- DISPATCHER DE AÇÕES
-- ═══════════════════════════════════════════════════════════════════

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
		-- Se criou joint RightArm e há SegundaArma no LeftArm → criar joint LeftArm junto
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
		-- Se removeu RightArm e há SegundaArma no LeftArm → remover LeftArm junto (Escudo NÃO)
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

-- ═══════════════════════════════════════════════════════════════════
-- LIMPEZA
-- ═══════════════════════════════════════════════════════════════════

local function OnPlayerRemoving(player: Player)
	dadosEquipamento[player] = nil
	ultimaAcao[player] = nil
	DebugPrint("[ServicoEquipamento] Cache limpo para:", player.Name)
end

-- ═══════════════════════════════════════════════════════════════════
-- INICIALIZAÇÃO
-- ═══════════════════════════════════════════════════════════════════

function ServicoEquipamento:Iniciar()
	DebugPrint("[ServicoEquipamento] Inicializando...")

	-- Conectar RemoteEvent
	local Remotos = ReplicatedStorage:WaitForChild("Remotos")
	local EquipamentoAcao = Remotos:WaitForChild("EquipamentoAcao")
	EquipamentoAcao.OnServerEvent:Connect(OnEquipamentoAcao)

	-- Limpeza ao player sair
	Players.PlayerRemoving:Connect(OnPlayerRemoving)

	-- Resetar equipamento quando player respawna
	local function onCharacterAdded(player: Player)
		return function()
			dadosEquipamento[player] = nil
			DebugPrint("[ServicoEquipamento] Cache resetado para respawn:", player.Name)
		end
	end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(onCharacterAdded(player))
	end)

	-- Para players já conectados
	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterAdded:Connect(onCharacterAdded(player))
	end

	DebugPrint("[ServicoEquipamento] Inicializado com sucesso!")
end

return ServicoEquipamento
