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
local DEBUG_ENABLED = true

local function DebugPrint(...)
	if DEBUG_ENABLED then
		print(...)
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- MÓDULOS
-- ═══════════════════════════════════════════════════════════════════
local Modulos = ReplicatedStorage:WaitForChild("Modulos")
local ToolBuilder = require(Modulos:WaitForChild("ToolBuilder"))
local ModEquip = require(Modulos:WaitForChild("Modulo_Equipamento"))

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
		elseif desc:IsA("ParticleEmitter") or desc:IsA("Trail") or desc:IsA("Beam") then
			desc.Enabled = false
		elseif desc:IsA("Light") then
			desc.Enabled = false
		end
	end
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

--- Busca Tool Punhos na Backpack do player
local function _BuscarPunhos(player: Player): Tool?
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then
		return nil
	end

	for _, child in ipairs(backpack:GetChildren()) do
		if child:IsA("Tool") then
			local tipo = ModEquip.LerTipo(child)
			if tipo == "ArmasEquipadas" then
				local modo = ModEquip.LerModoAnimacao(child)
				if modo == "Punhos" then
					return child
				end
			end
		end
	end

	-- Também verificar no Character (se estiver equipado nas mãos)
	local character = player.Character
	if character then
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Tool") then
				local tipo = ModEquip.LerTipo(child)
				if tipo == "ArmasEquipadas" then
					local modo = ModEquip.LerModoAnimacao(child)
					if modo == "Punhos" then
						return child
					end
				end
			end
		end
	end

	return nil
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

-- ═══════════════════════════════════════════════════════════════════
-- ACESSÓRIOS DE ARMA (SERVER-SIDE)
-- ═══════════════════════════════════════════════════════════════════

--- Clona acessório de arma para o Character do jogador (server-side, visível para todos)
--- RightArm → clona AcessorioMaoDireita
--- LeftArm → clona AcessorioMaoEsquerda (fallback: AcessorioMaoDireita)
---@param player Player
---@param slot string "RightArm" ou "LeftArm"
local function ClonarAcessoriosArmaServerSide(player: Player, slot: string)
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	InicializarCache(player)
	local cache = dadosEquipamento[player][slot]
	if not cache then
		DebugPrint("[ServicoEquipamento] Sem cache para clonar acessório no slot:", slot)
		return
	end

	-- Verificar se o Tool equipado na mão é uma arma real (ArmasEquipadas e não Punhos)
	local toolNaMao = character:FindFirstChildOfClass("Tool")
	if toolNaMao then
		local dadosF = toolNaMao:FindFirstChild("Dados")
		if dadosF then
			local tipoV = dadosF:FindFirstChild("Tipo")
			if tipoV and tipoV.Value ~= "ArmasEquipadas" then
				DebugPrint(
					"[ServicoEquipamento] Tool na mão não é ArmasEquipadas, ignorando clonagem:",
					toolNaMao.Name
				)
				return
			end
			-- Punhos é ArmasEquipadas mas não deve clonar acessórios de arma
			local modoV = dadosF:FindFirstChild("modoAnimacao")
			if modoV and modoV.Value == "Punhos" then
				DebugPrint("[ServicoEquipamento] Tool na mão é Punhos, ignorando clonagem:", toolNaMao.Name)
				return
			end
		end
	end

	-- Obter o tool referenciado pelo ObjectValue do slot
	local slotOV = ObterSlotOV(player, slot)
	if not slotOV or not slotOV.Value then
		DebugPrint("[ServicoEquipamento] Slot sem referência para clonar acessório:", slot)
		return
	end

	local toolEquipada = slotOV.Value

	-- Determinar qual acessório clonar
	local nomeAcessorio = if slot == "LeftArm" then "AcessorioMaoEsquerda" else "AcessorioMaoDireita"

	local acessorioOriginal = toolEquipada:FindFirstChild(nomeAcessorio)
	if not acessorioOriginal or not acessorioOriginal:IsA("Accessory") then
		-- Fallback para LeftArm: tentar AcessorioMaoDireita
		if slot == "LeftArm" then
			acessorioOriginal = toolEquipada:FindFirstChild("AcessorioMaoDireita")
		end
		if not acessorioOriginal or not acessorioOriginal:IsA("Accessory") then
			DebugPrint("[ServicoEquipamento] Acessório não encontrado:", nomeAcessorio, "em", toolEquipada.Name)
			return
		end
	end

	-- Remover acessório com mesmo nome se já existir no character
	local existente = character:FindFirstChild(acessorioOriginal.Name)
	if existente then
		existente:Destroy()
	end

	-- Clonar
	local clone = acessorioOriginal:Clone()
	local handle = clone:FindFirstChild("Handle")
	if not handle then
		clone:Destroy()
		DebugPrint("[ServicoEquipamento] Acessório sem Handle:", acessorioOriginal.Name)
		return
	end

	-- Configurar clone: visível, desancorado, sem colisão
	for _, part in ipairs(clone:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Transparency = 0 -- Tornar visível (original estava oculto no Tool)
			part.Anchored = false -- Desancorar (template vem ancorado)
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.Massless = true
		elseif (part:IsA("Weld") or part:IsA("ManualWeld")) and part.Name == "AccessoryWeld" then
			part:Destroy()
		elseif part:IsA("ProximityPrompt") then
			part:Destroy()
		end
	end

	humanoid:AddAccessory(clone)

	if not cache.acessoriosClonados then
		cache.acessoriosClonados = {}
	end
	table.insert(cache.acessoriosClonados, clone)

	DebugPrint("[ServicoEquipamento] Acessório clonado server-side:", clone.Name, "para slot:", slot)
end

--- Remove acessórios de arma clonados server-side do Character
---@param player Player
---@param slot string
local function RemoverAcessoriosArmaServerSide(player: Player, slot: string)
	InicializarCache(player)
	local cache = dadosEquipamento[player][slot]
	if not cache or not cache.acessoriosClonados then
		return
	end

	for _, acessorio in ipairs(cache.acessoriosClonados) do
		if acessorio and acessorio.Parent then
			acessorio:Destroy()
		end
	end
	cache.acessoriosClonados = {}
	DebugPrint("[ServicoEquipamento] Acessórios removidos server-side para slot:", slot)
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
			if estadoAcao and estadoAcao:IsA("StringValue") then
				local estado = estadoAcao.Value
				if estado ~= "Nenhuma" then
					return false, "Em ação: " .. estado
				end
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

	-- Tool na Backpack
	local backpack = player:FindFirstChild("Backpack")
	if parent == backpack then
		return true
	end

	-- Tool equipado no Character
	if parent == player.Character then
		return true
	end

	return false
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
				-- Se já tem algo na esquerda → desequipar primeiro
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
		if ModEquip.CategoriaBloqueiaMaoEsquerda(categoria) then
			if SlotOcupado(player, "LeftArm") then
				DebugPrint("[ServicoEquipamento] Categoria bloqueia esquerda, limpando LeftArm")
				self:ProcessarDesequiparSlot(player, "LeftArm")
			end
		end

		-- Se é arco → verificar se tem flechas para auto-equipar
		if categoria == "Arcos" then
			local flechas = BuscarFlechasBackpack(player)
			if not flechas then
				warn("[ServicoEquipamento] Arco requer flechas na Backpack! Equipando arco sem flechas.")
				-- Permite equipar arco sem flechas, mas tiro será bloqueado
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

		-- Consumir tool original: se quantidade > 1, decrementar; se == 1, destruir
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
			-- Atualizar dados no cache com quantidade 1 (individual)
			dados.Quantidade = 1
		else
			tool:Destroy()
			DebugPrint("[ServicoEquipamento] Tool original destruído (quantidade era 1)")
		end

		-- Criar ArmaEquipada
		local armaEquipada = ToolBuilder.CriarArmaEquipada(dados, player.Backpack)
		if not armaEquipada then
			warn("[ServicoEquipamento] Falha ao criar ArmaEquipada! Restaurando tool original.")
			-- Tentar restaurar
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
		-- ArmasUmaMao pode ir para esquerda se já tem arma na direita (dual-wield automático)
		local categoriaDir = ObterCategoriaRightArm(player)

		if categoria :: string == "Escudos" then
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
				-- Sem arma na direita ou arma incompatível → equipar na direita (slot padrão)
				-- Redirecionar para equipar na direita
				if not SlotOcupado(player, "RightArm") then
					-- Sem arma na direita, vai para direita normalmente
					dadosEquipamento[player].RightArm = {
						dados = dados,
						acessoriosClonados = {},
					}

					if humanoid then
						humanoid:UnequipTools()
					end

					-- Consumir tool: se quantidade > 1, decrementar; se == 1, destruir
					local quantidade = dados.Quantidade or 1
					if quantidade > 1 then
						local dadosF = tool:FindFirstChild("Dados")
						if dadosF then
							local qtdV = dadosF:FindFirstChild("Quantidade")
							if qtdV then
								qtdV.Value = quantidade - 1
							end
						end
						dados.Quantidade = 1
					else
						tool:Destroy()
					end

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
			-- SegundaArma precisa virar ArmaEquipada (para ter modoAnimacao e acessórios)
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
		ClonarAcessoriosArmaServerSide(player, "LeftArm")
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
		-- Decrementar quantidade no Tool original (fica na Backpack)
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
		-- Quantidade == 1: mover o Tool inteiro
		tool.CanBeDropped = false
		tool.Parent = equipAtivos
		toolParaEquipar = tool
	end

	-- Ocultar TODOS os componentes visuais internos do Tool
	-- (só os clones no Character serão visíveis)
	OcultarComponentesTool(toolParaEquipar)

	-- Clonar acessórios para o Character (visual, server-side)
	local character = player.Character
	if character and humanoid then
		local acessoriosClonados = {}
		for _, child in ipairs(toolParaEquipar:GetChildren()) do
			if child:IsA("Accessory") then
				local clone = child:Clone()
				-- Tornar clone visível e desancorado
				for _, part in ipairs(clone:GetDescendants()) do
					if part:IsA("BasePart") then
						part.Transparency = 0
						part.Anchored = false
						part.CanCollide = false
						part.CanTouch = false
						part.CanQuery = false
						part.Massless = true
					elseif (part:IsA("Weld") or part:IsA("ManualWeld")) and part.Name == "AccessoryWeld" then
						part:Destroy()
					elseif part:IsA("ProximityPrompt") then
						part:Destroy()
					end
				end
				humanoid:AddAccessory(clone)
				table.insert(acessoriosClonados, clone)
				DebugPrint("[ServicoEquipamento] Acessório clonado:", clone.Name)
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
	local _, _bracos = ObterEquipamento(player)
	local humanoid = ObterHumanoid(player)

	-- ═══════════════════════════
	-- DESEQUIPAR RIGHTARM
	-- ═══════════════════════════
	if slotName == "RightArm" then
		local toolEquipado = slotOV.Value
		local categoriaAnterior = nil

		if cache and cache.dados then
			categoriaAnterior = cache.dados.Categoria
		end

		-- Remover acessórios clonados server-side do Character
		RemoverAcessoriosArmaServerSide(player, "RightArm")

		-- Destruir ArmaEquipada da Backpack/Character
		if toolEquipado and toolEquipado.Parent then
			-- Se estiver nas mãos, desequipar primeiro
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

		-- Regras de consistência com a esquerda
		if categoriaAnterior == "Arcos" then
			-- Arco → limpar flechas da esquerda
			if SlotOcupado(player, "LeftArm") then
				local cacheEsq = dadosEquipamento[player].LeftArm
				if cacheEsq and cacheEsq.tipoEsquerda == "Flechas" then
					DebugPrint("[ServicoEquipamento] Removendo flechas (era arco)")
					self:ProcessarDesequiparSlot(player, "LeftArm")
				end
			end
		end

		-- Dual-wield: se tinha segunda arma na esquerda, desequipar também
		if SlotOcupado(player, "LeftArm") then
			local cacheEsq = dadosEquipamento[player].LeftArm
			if cacheEsq and cacheEsq.tipoEsquerda == "SegundaArma" then
				DebugPrint("[ServicoEquipamento] Removendo segunda arma (desequipando direita)")
				self:ProcessarDesequiparSlot(player, "LeftArm")
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
		local cacheLocal = cache

		-- Remover acessórios clonados server-side do Character
		RemoverAcessoriosArmaServerSide(player, "LeftArm")

		-- Destruir/mover Tool de EquipamentosAtivos
		if toolEquipado and toolEquipado.Parent then
			-- Re-criar no Backpack a partir dos dados do cache
			if cacheLocal and cacheLocal.dados then
				if cacheLocal.tipoEsquerda == "Flechas" then
					-- Flechas voltam como Material para Backpack
					ToolBuilder.CriarTool(cacheLocal.dados, player.Backpack)
					DebugPrint("[ServicoEquipamento] Flechas devolvidas ao Backpack")
				else
					-- Escudo ou SegundaArma → recriar Tool de Arma original
					ToolBuilder.CriarTool(cacheLocal.dados, player.Backpack)
					DebugPrint("[ServicoEquipamento] Arma/Escudo devolvido ao Backpack")
				end
			end

			-- Destruir o tool do EquipamentosAtivos
			toolEquipado:Destroy()
		end

		-- Limpar referência
		slotOV.Value = nil

		-- Limpar cache
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
			-- Destruir o tool do EquipamentosAtivos
			toolEquipado:Destroy()

			-- Recriar via CriarTool (que faz empilhamento automático com itens iguais na Backpack)
			if dadosArmadura then
				local toolRecriado = ToolBuilder.CriarTool(dadosArmadura, player.Backpack)
				if toolRecriado then
					DebugPrint(
						"[ServicoEquipamento] Armadura devolvida ao Backpack (com empilhamento):",
						toolRecriado.Name
					)
				else
					warn("[ServicoEquipamento] Falha ao recriar armadura no Backpack!")
				end
			end
		end

		-- Limpar referência
		slotOV.Value = nil

		-- Limpar cache
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

		-- Validar condições básicas para desequipar via UI (não é chamada interna)
		local valido, motivo = ValidarCondicoesBasicas(player)
		if not valido then
			warn("[ServicoEquipamento] Desequipar rejeitado:", motivo)
			return
		end
		ultimaAcao[player] = tick()

		ServicoEquipamento:ProcessarDesequiparSlot(player, argumento)
	elseif acao == "ClonarAcessorio" then
		-- Cliente solicita clonagem de acessório de arma (ao atingir marker "Equip" na animação)
		if type(argumento) ~= "string" then
			warn("[ServicoEquipamento] Argumento inválido para ClonarAcessorio")
			return
		end
		if argumento ~= "RightArm" and argumento ~= "LeftArm" then
			warn("[ServicoEquipamento] Slot inválido para ClonarAcessorio:", argumento)
			return
		end
		ClonarAcessoriosArmaServerSide(player, argumento)
		-- Se clonou RightArm e há SegundaArma no LeftArm → clonar LeftArm junto
		if argumento == "RightArm" then
			InicializarCache(player)
			local cacheEsq = dadosEquipamento[player].LeftArm
			if cacheEsq and cacheEsq.tipoEsquerda == "SegundaArma" then
				ClonarAcessoriosArmaServerSide(player, "LeftArm")
				DebugPrint("[ServicoEquipamento] SegundaArma LeftArm acessório clonado junto com RightArm")
			end
		end
	elseif acao == "RemoverAcessorio" then
		-- Cliente solicita remoção de acessório de arma (ao atingir marker "Desequip" na animação)
		if type(argumento) ~= "string" then
			warn("[ServicoEquipamento] Argumento inválido para RemoverAcessorio")
			return
		end
		if argumento ~= "RightArm" and argumento ~= "LeftArm" then
			warn("[ServicoEquipamento] Slot inválido para RemoverAcessorio:", argumento)
			return
		end
		RemoverAcessoriosArmaServerSide(player, argumento)
		-- Se removeu RightArm e há SegundaArma no LeftArm → remover LeftArm junto (Escudo NÃO)
		if argumento == "RightArm" then
			InicializarCache(player)
			local cacheEsq = dadosEquipamento[player].LeftArm
			if cacheEsq and cacheEsq.tipoEsquerda == "SegundaArma" then
				RemoverAcessoriosArmaServerSide(player, "LeftArm")
				DebugPrint("[ServicoEquipamento] SegundaArma LeftArm acessório removido junto com RightArm")
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
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			-- Resetar cache (equipamento é recriado pelo ConfigIniciar)
			dadosEquipamento[player] = nil
			DebugPrint("[ServicoEquipamento] Cache resetado para respawn:", player.Name)
		end)
	end)

	-- Para players já conectados
	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterAdded:Connect(function()
			dadosEquipamento[player] = nil
		end)
	end

	DebugPrint("[ServicoEquipamento] Inicializado com sucesso!")
end

return ServicoEquipamento
