--[[
    Script: init.client.luau
    Caminho: src/StarterGui/ControleGui/Principal
    Responsabilidade: HUD principal — conecta a UI aos dados do jogo (vida, stamina, status, hotbar, inventario, equipamento e viewport do personagem).
    Uso: LocalScript; roda automaticamente para o jogador local em StarterGui/ControleGui/Principal.
    Nao faz: Nao valida autoridade do servidor, nao salva dados persistentes e nao substitui regras server-side.
    Funcoes principais: atualizarViewport, atualizarItens, reconstruir, atualizarSelecao, equipar, desequipar, guardar, tirar, aoPersonagem
]]

local DEBUG = false -- Habilitar para logs de depuração no output

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ClientBridge = require(
	ReplicatedStorage:WaitForChild("Jogador"):WaitForChild("ComunicacaoCliente"):WaitForChild("PonteCliente") :: ModuleScript
)

local Hud = require(script:WaitForChild("HudConfig"))
local CONFIG = Hud.CONFIG

-- Catálogo (dados fixos): usado só pra ler DurabilidadeMax de cada item.
-- Carregado uma vez; Get() lê de uma tabela em memória, sem custo repetido.
local CatalogoItens = require(ReplicatedStorage.Dados.Itens.CatalogoItens)

-- ConstrutorTools: usado só pra separar 1 unidade de uma pilha ao equipar.
local ConstrutorTools =
	require(ReplicatedStorage:WaitForChild("SistemaItens"):WaitForChild("ConstrutorTools") :: ModuleScript)

local player = Players.LocalPlayer
local hud = script.Parent:WaitForChild("HUD")

--// Referências
local itensFrame = hud:WaitForChild("ItensFrame")
local hotbar = itensFrame:WaitForChild("Hotbar")
local templates = hud:WaitForChild("HotbarTemplate")
local toolTemplate = templates:WaitForChild("ToolTemplate")
local mochilaTemplate = templates:WaitForChild("MochilaTemplate")
local playerView = hud:WaitForChild("PlayerView")
local viewportFrame = playerView:FindFirstChildWhichIsA("ViewportFrame", true)
local clipVida = playerView:WaitForChild("BarraVidaFundo"):WaitForChild("BarraVidaClip")
local clipStamina = playerView:WaitForChild("BarraStaminaFundo"):WaitForChild("BarraStaminaClip")
local statusFundo = playerView:WaitForChild("StatusFundo")
local inventario = itensFrame:WaitForChild("Inventory")
local equipamento = itensFrame:WaitForChild("EquipamentoFrame")
local inventarioScroll = inventario:WaitForChild("ScrollingFrame")
local inventarioTemplate = inventarioScroll:WaitForChild("MochilaInventarioTemplate")
inventarioTemplate.Parent = templates -- tira o template da lista visível (só molde)
inventarioScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
inventarioScroll.CanvasSize = UDim2.new()

-- Molde do espaçador: o script gere os BlankSpace (remove os fixos pra não duplicar)
local blankMolde
for _, filho in hotbar:GetChildren() do
	if filho.Name == "BlankSpace" then
		blankMolde = blankMolde or filho:Clone()
		filho:Destroy()
	end
end
if not blankMolde then
	local molde = templates:FindFirstChild("BlankSpace")
	blankMolde = molde and molde:Clone()
end

-- Dica flutuante: mostra o nome do item do inventário seguindo o cursor
local dica = Instance.new("TextLabel")
dica.Name = "DicaInventario"
dica.AnchorPoint = Vector2.new(0, 1) -- canto inferior esquerdo do nome
dica.AutomaticSize = Enum.AutomaticSize.XY
dica.BackgroundTransparency = 1
dica.Text = ""
dica.TextColor3 = Color3.fromRGB(240, 240, 240)
dica.Font = Enum.Font.GothamBold
dica.TextSize = 14
dica.TextStrokeTransparency = 0.4
dica.ZIndex = 60
dica.Visible = false
dica.Parent = hud

-- Desliga a hotbar padrão do Roblox pra não duplicar
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

--// Status (Attributes do HUD, 0 a 1)
for _, botao in statusFundo:GetChildren() do
	if botao:IsA("ImageButton") then
		Hud.registrarSlot(botao, CONFIG.nomeStatusY)
		local anel = botao:WaitForChild("StatusBar")
		hud:SetAttribute(botao.Name, 1)
		hud:GetAttributeChangedSignal(botao.Name):Connect(function()
			Hud.setAnel(anel, hud:GetAttribute(botao.Name) or 0)
		end)
	end
end

--// Stamina (Attribute "Stamina" do HUD — o gameplay seta esse valor)
hud:SetAttribute("Stamina", 1)
hud:GetAttributeChangedSignal("Stamina"):Connect(function()
	Hud.setBarra(clipStamina, hud:GetAttribute("Stamina") or 0)
end)

--// Hotbar + Inventário (visual)
-- Cada item (Tool) fica num de três lugares:
--   • slots de Tool (equipados, máx CONFIG.maxTools) → ToolTemplate (números 1 a 3)
--   • mochila da hotbar → MochilaTemplate (números 4+)
--   • inventário → MochilaInventarioTemplate, dentro da ScrollingFrame
-- Clique curto = segurar na mão (1 por vez). Arrastar = mover o item entre a
-- hotbar e o inventário (Tools equipadas não vão pro inventário). Promover pros
-- slots de Tool continua só via BindableEvent "Comando". Os espaçadores
-- (BlankSpace) são geridos aqui pra manter os itens centralizados.
local itens = {} -- Tools conhecidas, na ordem de chegada
local equipados = {} -- Tools nos slots de Tool (máx CONFIG.maxTools)
local noInventario = {} -- [Tool] = true → guardada no inventário
local slots = {} -- [Tool] = slot
local porTecla = {} -- [numero da tecla] = Tool (só slots da hotbar)
local espacadores = {} -- BlankSpaces temporários de centralização
local arrasto -- estado do arraste atual, ou nil
local reconstruir -- (definida abaixo)
local atualizarSelecao -- (definida abaixo)

--// Selecionar = segurar na mão (equipa/desequipa a Tool no personagem)
local function segurarNaMao(tool)
	if ClientBridge.PodeAlterarTool and not ClientBridge.PodeAlterarTool() then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if tool.Parent == character then
		humanoid:UnequipTools()
	else
		humanoid:EquipTool(tool)
	end
end

--// O ponteiro do mouse está sobre este elemento de UI?
-- Desconta o GuiInset pra alinhar com AbsolutePosition (mesma base do fantasma).
local function sobre(gui)
	local m = UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
	local p, t = gui.AbsolutePosition, gui.AbsoluteSize
	return m.X >= p.X and m.X <= p.X + t.X and m.Y >= p.Y and m.Y <= p.Y + t.Y
end

--// Arraste: clique curto = segurar na mão; arrastar = mover mochila ↔ inventário
local function encerrarArrasto()
	if not arrasto then
		return
	end
	arrasto.mover:Disconnect()
	arrasto.fim:Disconnect()
	if arrasto.ghost then
		arrasto.ghost:Destroy()
	end
	local tool, arrastou = arrasto.tool, arrasto.arrastou
	arrasto = nil
	if not arrastou then
		segurarNaMao(tool) -- clique curto
	else
		-- Arrastou: solta sobre o inventário → guarda; senão volta pra hotbar.
		local paraInventario = sobre(inventario) or nil
		if noInventario[tool] ~= paraInventario then
			noInventario[tool] = paraInventario
			reconstruir()
		end
	end
end

local function iniciarArrasto(tool, origem)
	if arrasto then
		return
	end
	-- Só dá pra arrastar itens da mochila com o inventário aberto; Tools não.
	local podeArrastar = inventario.Visible and not table.find(equipados, tool)
	local inicio = UserInputService:GetMouseLocation()
	arrasto = { tool = tool, arrastou = false }
	arrasto.mover = UserInputService.InputChanged:Connect(function(input)
		if not podeArrastar or input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end
		local m = UserInputService:GetMouseLocation()
		if not arrasto.arrastou and (m - inicio).Magnitude > 8 then
			arrasto.arrastou = true
			-- Fantasma = clone do slot inteiro (não só o ícone) seguindo o cursor
			local g = origem:Clone()
			local key = g:FindFirstChild("Key")
			if key then
				key:Destroy() -- sem o balão da tecla enquanto arrasta
			end
			local nome = g:FindFirstChild("Nome")
			if nome then
				-- Nome acima do fantasma (igual nos dois sentidos do arraste)
				nome.Visible = true
				nome.TextTransparency = 0
				nome.Position = UDim2.new(nome.Position.X.Scale, nome.Position.X.Offset, CONFIG.nomeToolY, 0)
				local sombra = nome:FindFirstChild("UIShadow")
				if sombra then
					sombra.Transparency = 0.5
				end
			end
			g.Size = UDim2.fromOffset(origem.AbsoluteSize.X, origem.AbsoluteSize.Y)
			g.Name = "GhostArrasto"
			g.AnchorPoint = Vector2.new(0.5, 0.5)
			g.Active = false -- não intercepta o mouse
			g.ZIndex = 50
			g.Parent = hud
			arrasto.ghost = g
		end
		if arrasto.ghost then
			local inset = GuiService:GetGuiInset()
			arrasto.ghost.Position = UDim2.fromOffset(m.X - inset.X, m.Y - inset.Y)
		end
	end)
	arrasto.fim = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			encerrarArrasto()
		end
	end)
end

--// Espaçadores: centralizam os itens visíveis na hotbar
local function adicionarBlank(ordem)
	if not blankMolde then
		return
	end
	local b = blankMolde:Clone()
	b.LayoutOrder = ordem
	b.Parent = hotbar
	table.insert(espacadores, b)
end

function reconstruir()
	dica.Visible = false -- some ao reconstruir: evita o nome "preso" ao fechar a mochila com o mouse em cima
	for _, s in slots do
		if s.conexaoDurabilidade then
			s.conexaoDurabilidade:Disconnect()
		end
		if s.conexaoQuantidade then
			s.conexaoQuantidade:Disconnect()
		end
		s.botao:Destroy()
	end
	slots = {}
	table.clear(porTecla)
	for _, b in espacadores do
		b:Destroy()
	end
	table.clear(espacadores)

	local aberto = inventario.Visible

	-- Classifica os itens fora dos slots de Tool. A mochila da hotbar tem no
	-- máximo maxMochila itens; o que passar disso (ou for guardado) vai pro
	-- inventário (a "backpack").
	local mochila = {} -- itens visíveis na mochila da hotbar
	local guardados = {} -- itens mostrados no inventário
	for _, tool in itens do
		if not table.find(equipados, tool) then
			if noInventario[tool] or #mochila >= CONFIG.maxMochila then
				table.insert(guardados, tool)
			else
				table.insert(mochila, tool)
			end
		end
	end

	-- Cria um slot ocupado por uma Tool
	local function criarSlot(tool, molde, ordem, numero, container)
		local botao = molde:Clone()
		botao.LayoutOrder = ordem
		botao.Name = tool.Name
		botao.Nome.Text = tool.Name
		if tool.TextureId ~= "" then
			botao.Icone.Image = tool.TextureId
		end
		local key = botao:FindFirstChild("Key")
		if key then
			key.KeyText.Text = (numero and numero <= 10) and tostring(numero % 10) or ""
		end
		if numero then
			porTecla[numero] = tool
		end
		botao.Visible = true
		botao.Parent = container

		local s = container == inventarioScroll and Hud.registrarSlotInventario(botao, dica)
			or Hud.registrarSlot(botao, CONFIG.nomeToolY)
		slots[tool] = s

		local anel = botao:FindFirstChild("Durabilidade")
		if anel then
			-- DurabilidadeMax é fixo por item: lê do catálogo uma única vez aqui
			-- (cacheado no slot). O anel mostra Durabilidade (atual) / DurabilidadeMax.
			local dados = CatalogoItens.Get(tool:GetAttribute("Id"))
			local durabMax = dados and dados.DurabilidadeMax
			if durabMax then
				local function atualizar(instantaneo)
					local atual = tool:GetAttribute("Durabilidade") or durabMax
					Hud.setAnel(anel, atual / durabMax, instantaneo)
				end
				-- Só reage quando a durabilidade muda (evento), sem polling.
				s.conexaoDurabilidade = tool:GetAttributeChangedSignal("Durabilidade"):Connect(function()
					atualizar(false)
				end)
				atualizar(true) -- 1ª pintura instantânea: sem isso o anel "pisca cheio" ao reconstruir
			else
				anel.Visible = false -- item sem durabilidade (empilável) não usa anel
			end
		end

		-- Quantidade: só aparece quando há pilha (> 1). Com 1 unidade fica oculto.
		local rotuloQtd = botao:FindFirstChild("Quantidade")
		if rotuloQtd then
			local function atualizarQtd()
				local q = tool:GetAttribute("Quantidade") or 1
				rotuloQtd.Text = "x" .. tostring(q)
				rotuloQtd.Visible = q > 1
			end
			s.conexaoQuantidade = tool:GetAttributeChangedSignal("Quantidade"):Connect(atualizarQtd)
			atualizarQtd()
		end

		botao.MouseButton1Down:Connect(function()
			iniciarArrasto(tool, botao)
		end)
	end

	-- Cria um slot vazio (placeholder apagado, aparece só com o inventário aberto)
	local function criarVazio(molde, ordem)
		local botao = molde:Clone()
		botao.Name = "Vazio"
		botao.LayoutOrder = ordem
		botao.Active = false
		botao.AutoButtonColor = false
		botao.BackgroundTransparency = 0.85 -- mais apagadinho que um slot normal
		botao.Icone.Visible = false
		for _, nome in { "Nome", "Key", "Durabilidade", "Quantidade" } do
			local filho = botao:FindFirstChild(nome)
			if filho then
				filho.Visible = false
			end
		end
		botao.Visible = true
		botao.Parent = hotbar
		table.insert(espacadores, botao)
	end

	-- Slots de Tool (1..maxTools): ocupados mostram a Tool; livres ficam apagados
	local totalTools = aberto and CONFIG.maxTools or #equipados
	for i = 1, totalTools do
		if equipados[i] then
			criarSlot(equipados[i], toolTemplate, i - 1, i, hotbar)
		else
			criarVazio(toolTemplate, i - 1)
		end
	end

	-- Slots de item da mochila (depois dos Tools; no máximo maxMochila)
	local totalMochila = aberto and CONFIG.maxMochila or #mochila
	for j = 1, totalMochila do
		if mochila[j] then
			criarSlot(mochila[j], mochilaTemplate, 4 + j, #equipados + j, hotbar)
		else
			criarVazio(mochilaTemplate, 4 + j)
		end
	end

	-- Itens no inventário (guardados + o que não coube na hotbar)
	for i, tool in guardados do
		criarSlot(tool, inventarioTemplate, i, nil, inventarioScroll)
	end

	-- Separador entre Tools e mochila / centraliza com o inventário fechado
	if aberto or (#equipados > 0 and #mochila > 0) then
		adicionarBlank(CONFIG.maxTools + 1)
	elseif #mochila > 0 then
		adicionarBlank(CONFIG.maxTools + 1)
		adicionarBlank(4 + #mochila + 1)
	end

	atualizarSelecao()
end

--// Seleção (segurar na mão): reflete a Tool que está no personagem
function atualizarSelecao()
	for tool, s in slots do
		Hud.selecionar(s, tool.Parent == player.Character)
	end
end

--// Slots de Tool: promover (equipar) / remover (desequipar). Só via Comando.
local function equipar(nome)
	if #equipados >= CONFIG.maxTools then
		return
	end
	for _, tool in itens do
		if not table.find(equipados, tool) and not noInventario[tool] and (nome == nil or tool.Name == nome) then
			-- Pilha (Quantidade > 1): equipa só UMA unidade. Separa um Tool novo
			-- (Quantidade = 1) e deixa o restante da pilha na mochila.
			local unidade = ConstrutorTools.SepararUnidade(tool)
			if not unidade then
				return
			end
			if unidade ~= tool and not table.find(itens, unidade) then
				table.insert(itens, unidade) -- registra a unidade separada na hora
			end
			table.insert(equipados, unidade)
			reconstruir()
			return
		end
	end
end

local function desequipar(nome)
	for i = #equipados, 1, -1 do
		if nome == nil or equipados[i].Name == nome then
			local tool = equipados[i]
			table.remove(equipados, i)
			-- Ao desequipar, a unidade volta pro estoque e funde com uma pilha
			-- idêntica da mochila (mesma assinatura), se houver espaço.
			if ConstrutorTools.EmpilharExistente(tool.Parent, tool) then
				local j = table.find(itens, tool)
				if j then
					table.remove(itens, j)
				end
				noInventario[tool] = nil
			end
			reconstruir()
			return
		end
	end
end

--// Guardar (mochila → inventário) / tirar (inventário → mochila)
local function guardar(nome)
	for _, tool in itens do
		if not table.find(equipados, tool) and not noInventario[tool] and (nome == nil or tool.Name == nome) then
			noInventario[tool] = true
			reconstruir()
			return
		end
	end
end

local function tirar(nome)
	for _, tool in itens do
		if noInventario[tool] and (nome == nil or tool.Name == nome) then
			noInventario[tool] = nil
			reconstruir()
			return
		end
	end
end

local comando = Instance.new("BindableEvent")
comando.Name = "Comando"
comando.Event:Connect(function(acao, nome)
	if acao == "equipar" then
		equipar(nome)
	elseif acao == "desequipar" then
		desequipar(nome)
	elseif acao == "guardar" then
		guardar(nome)
	elseif acao == "tirar" then
		tirar(nome)
	end
end)
comando.Parent = script

local function coletar(atuais, pai)
	if not pai then
		return
	end
	for _, obj in pai:GetChildren() do
		if obj:IsA("Tool") then
			atuais[obj] = true
		end
	end
end

local function atualizarItens()
	local atuais = {}
	coletar(atuais, player.Character)
	coletar(atuais, player:FindFirstChildOfClass("Backpack"))

	local mudou = false
	for i = #itens, 1, -1 do
		local tool = itens[i]
		if atuais[tool] then
			atuais[tool] = nil -- já conhecida
		else
			table.remove(itens, i) -- sumiu do jogador
			local e = table.find(equipados, tool)
			if e then
				table.remove(equipados, e)
			end
			noInventario[tool] = nil
			mudou = true
		end
	end
	for tool in atuais do
		table.insert(itens, tool)
		mudou = true
	end
	if mudou then
		reconstruir()
	else
		atualizarSelecao()
	end
end

local function observar(pai)
	local function aoMudar(obj)
		if obj:IsA("Tool") then
			task.defer(atualizarItens)
		end
	end
	pai.ChildAdded:Connect(aoMudar)
	pai.ChildRemoved:Connect(aoMudar)
end

--// Viewport circular do personagem (PlayerView)
-- NÃO mexe em posição, pivot nem câmera: mantém o boneco de exemplo
-- (BonecoView) exatamente onde e como está no Viewport. Só COPIA a
-- aparência do jogador (roupa, cor de pele, rosto e acessórios/cabelo) por
-- cima do modelo padrão. Cópia MANUAL em vez de ApplyDescription porque
-- dentro de ViewportFrame o ApplyDescription costuma falhar em silêncio.

-- Remove a aparência padrão do modelo (roupa, cor, acessórios) antes de
-- colocar a do jogador, pra não misturar/duplicar.
local function limparAparencia(model)
	for _, obj in model:GetChildren() do
		if
			obj:IsA("Accessory")
			or obj:IsA("Shirt")
			or obj:IsA("Pants")
			or obj:IsA("ShirtGraphic")
			or obj:IsA("BodyColors")
		then
			obj:Destroy()
		end
	end
end

local function atualizarViewport()
	if not viewportFrame then
		warn("[Viewport] ViewportFrame não encontrado")
		return
	end

	local char = player.Character
	if not char then
		warn("[Viewport] player.Character ainda não existe")
		return
	end

	-- Acha o modelo de exemplo que JÁ está montado no Viewport (dentro do
	-- WorldModel). Ele não é destruído nem movido.
	local worldModel = viewportFrame:FindFirstChildWhichIsA("WorldModel", true)
	local container = worldModel or viewportFrame
	local model = container:FindFirstChild("BonecoView") or container:FindFirstChildWhichIsA("Model")
	if not model then
		if DEBUG then
			warn("[Viewport] modelo de exemplo não encontrado dentro de", container:GetFullName())
		end
		return
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		if DEBUG then
			warn("[Viewport] o modelo", model.Name, "não tem Humanoid")
		end
		return
	end

	if DEBUG then
		print("[Viewport] Aplicando aparência do jogador no modelo", model.Name)
	end

	-- 1) Limpa a aparência padrão do modelo
	limparAparencia(model)

	-- 2) Copia roupa, cores e graphic do personagem do jogador
	local copiados = 0
	for _, obj in char:GetChildren() do
		if obj:IsA("Shirt") or obj:IsA("Pants") or obj:IsA("ShirtGraphic") or obj:IsA("BodyColors") then
			obj:Clone().Parent = model
			copiados += 1
		end
	end
	if DEBUG then
		print("[Viewport] roupas/cores copiadas:", copiados)
	end

	-- 3) Copia o rosto (Decals na Head)
	local charHead = char:FindFirstChild("Head")
	local modelHead = model:FindFirstChild("Head")
	if charHead and modelHead then
		-- Remove todos os Decals existentes no modelo
		for _, v in modelHead:GetChildren() do
			if v:IsA("Decal") then
				v:Destroy()
			end
		end
		-- Copia todos os Decals do personagem
		for _, v in charHead:GetChildren() do
			if v:IsA("Decal") then
				v:Clone().Parent = modelHead
			end
		end
		if DEBUG then
			print("[Viewport] rosto/decalques aplicados")
		end
	else
		if DEBUG then
			warn("[Viewport] Head faltando")
		end
	end

	-- 4) Copia acessórios (cabelo, chapéu, etc.) via Weld com C0/C1 por Attachment.
	-- WeldConstraint mantém o offset de mundo atual entre as partes — como o clone
	-- vem do personagem longe no mundo, o offset ficaria errado (ex: 125, 57, -12).
	-- O Weld com C0 = handleAtt.CFrame e C1 = targetAtt.CFrame posiciona corretamente
	-- independente de onde o Handle está no mundo quando a solda é criada.
	local function encontrarAttachmentNoModelo(modelRef, nomeAtt)
		for _, part in modelRef:GetDescendants() do
			if part:IsA("BasePart") then
				local att = part:FindFirstChild(nomeAtt)
				if att and att:IsA("Attachment") then
					return part, att
				end
			end
		end
		return nil, nil
	end

	local acessorios = 0
	for _, acc in char:GetChildren() do
		if acc:IsA("Accessory") then
			local clone = acc:Clone()
			local handle = clone:FindFirstChild("Handle")
			if handle then
				-- Remove welds/constraints que vieram do personagem original
				for _, c in handle:GetChildren() do
					if c:IsA("Weld") or c:IsA("WeldConstraint") or c:IsA("Motor6D") then
						c:Destroy()
					end
				end

				local handleAtt = handle:FindFirstChildWhichIsA("Attachment")
				if handleAtt then
					local partAlvo, attAlvo = encontrarAttachmentNoModelo(model, handleAtt.Name)
					if partAlvo and attAlvo then
						clone.Parent = model
						-- Posiciona o Handle no lugar correto antes de soldar
						handle.CFrame = partAlvo.CFrame * attAlvo.CFrame * handleAtt.CFrame:Inverse()
						-- Weld com C0/C1: define a posição relativa pelo Attachment, não pelo mundo
						local weld = Instance.new("Weld")
						weld.Name = "AccessoryWeld"
						weld.Part0 = handle
						weld.Part1 = partAlvo
						weld.C0 = handleAtt.CFrame
						weld.C1 = attAlvo.CFrame
						weld.Parent = handle
						acessorios += 1
						continue
					end
				end

				-- Fallback: sem attachment correspondente no modelo (caso de modelo R6 e acessorios R15)
				local targetPartName = "Torso"
				local lowerName = acc.Name:lower()
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

				local targetPart = model:FindFirstChild(targetPartName)
				if targetPart and targetPart:IsA("BasePart") then
					clone.Parent = model
					handle.CFrame = targetPart.CFrame

					local weld = Instance.new("Weld")
					weld.Name = "AccessoryWeld"
					weld.Part0 = handle
					weld.Part1 = targetPart
					weld.C0 = CFrame.new()
					weld.C1 = CFrame.new()
					weld.Parent = handle
					acessorios += 1
					continue
				end

				if DEBUG then
					warn("[Viewport] sem attachment para", acc.Name, "— parentando sem posicionamento preciso")
				end
			end
			clone.Parent = model
			acessorios += 1
		end
	end

	if DEBUG then
		print("[Viewport] acessórios copiados:", acessorios)
	end
end

local function atualizarEquipados()
	local character = player.Character
	local rightWeapon = nil
	local leftWeapon = nil

	if character then
		local equipamentoFolder = character:FindFirstChild("Equipamento")
		if equipamentoFolder then
			local bracos = equipamentoFolder:FindFirstChild("Bracos")
			if bracos then
				local rightArm = bracos:FindFirstChild("RightArm") :: ObjectValue
				local leftArm = bracos:FindFirstChild("LeftArm") :: ObjectValue
				if rightArm then
					rightWeapon = rightArm.Value
				end
				if leftArm then
					leftWeapon = leftArm.Value
				end
			end
		end
	end

	equipados[1] = rightWeapon
	equipados[2] = leftWeapon
	reconstruir()
end

--// Vida (direto do Humanoid) + observação das Tools
local function aoPersonagem(character)
	local humanoid = character:WaitForChild("Humanoid")
	local function vida()
		Hud.setBarra(clipVida, humanoid.Health / math.max(humanoid.MaxHealth, 1))
	end
	humanoid.HealthChanged:Connect(vida)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(vida)
	vida()

	observar(character)
	observar(player:WaitForChild("Backpack"))
	atualizarItens()

	-- Atualiza o Viewport do jogador dinamicamente ao equipar/desequipar armaduras (que adicionam/removem Accessories)
	local conexaoAdicionado = character.ChildAdded:Connect(function(child)
		if child:IsA("Accessory") or child:IsA("Shirt") or child:IsA("Pants") then
			atualizarViewport()
		end
	end)
	local conexaoRemovido = character.ChildRemoved:Connect(function(child)
		if child:IsA("Accessory") or child:IsA("Shirt") or child:IsA("Pants") then
			atualizarViewport()
		end
	end)

	-- Sincroniza armas equipadas nos slots da hotbar
	local equipamentoFolder = character:WaitForChild("Equipamento", 10)
	if equipamentoFolder then
		local bracos = equipamentoFolder:WaitForChild("Bracos", 5)
		if bracos then
			local rightArm = bracos:WaitForChild("RightArm", 5)
			local leftArm = bracos:WaitForChild("LeftArm", 5)

			local conexaoRight, conexaoLeft
			if rightArm then
				conexaoRight = rightArm:GetPropertyChangedSignal("Value"):Connect(atualizarEquipados)
			end
			if leftArm then
				conexaoLeft = leftArm:GetPropertyChangedSignal("Value"):Connect(atualizarEquipados)
			end

			local conexaoAncestry
			conexaoAncestry = character.AncestryChanged:Connect(function(_, parent)
				if not parent then
					if conexaoRight then
						conexaoRight:Disconnect()
					end
					if conexaoLeft then
						conexaoLeft:Disconnect()
					end
					if conexaoAdicionado then
						conexaoAdicionado:Disconnect()
					end
					if conexaoRemovido then
						conexaoRemovido:Disconnect()
					end
					conexaoAncestry:Disconnect()
				end
			end)
		end
	end
	atualizarEquipados()
end

player.CharacterAdded:Connect(aoPersonagem)
if player.Character then
	aoPersonagem(player.Character)
end

-- Dispara a atualização do Viewport apenas uma vez quando a aparência do jogador estiver totalmente carregada
player.CharacterAppearanceLoaded:Connect(function(_)
	atualizarViewport()
end)

if player.Character and player:HasAppearanceLoaded() then
	atualizarViewport()
end

--// Teclas: 1 a 0 seguram o item do slot correspondente; ' abre/fecha o inventário
inventario.Visible = false
equipamento.Visible = false -- começa escondido, igual ao inventário

UserInputService.InputBegan:Connect(function(input, processado)
	if processado then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end

	-- Custom Backspace drop logic
	if input.KeyCode == Enum.KeyCode.Backspace then
		local character = player.Character
		local tool = character and character:FindFirstChildOfClass("Tool")
		if tool then
			local id = tool:GetAttribute("Id")
			if id then
				local DroparToolEvent = ReplicatedStorage:FindFirstChild("Remotos")
					and ReplicatedStorage.Remotos:FindFirstChild("DroparTool")
				if DroparToolEvent then
					DroparToolEvent:FireServer(tool.Name, 1)
				end
			end
		end
		return
	end

	-- Compara pelo caractere impresso na tecla (independe do layout, ex.: ABNT2).
	-- Fallback nas duas posições físicas onde o ' costuma ficar (US x ABNT2).
	local caractere = UserInputService:GetStringForKeyCode(input.KeyCode)
	if
		caractere == CONFIG.teclaInventario
		or input.KeyCode == Enum.KeyCode.Quote
		or input.KeyCode == Enum.KeyCode.Backquote
	then
		inventario.Visible = not inventario.Visible
		equipamento.Visible = inventario.Visible -- o painel de equipamento acompanha o inventário
		reconstruir() -- mostra/esconde os slots vazios da hotbar
	else
		local numero = table.find(CONFIG.teclas, input.KeyCode)
		local tool = numero and porTecla[numero]
		if tool then
			segurarNaMao(tool)
		end
	end
end)
