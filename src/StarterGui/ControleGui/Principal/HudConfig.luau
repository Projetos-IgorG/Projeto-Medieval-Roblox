--[[
    Script: HudConfig.luau
    Caminho: src/StarterGui/ControleGui/Principal
    Responsabilidade: Configuracoes centralizadas e funcoes reutilizaveis de animacao e interacao do HUD (aneis, barras, slots, hover e selecao).
    Uso: ModuleScript filho do LocalScript Principal; importado via require(script:WaitForChild("HudConfig")).
    Nao faz: Nao gerencia estado de itens, nao conecta eventos de gameplay e nao acessa servicos de rede.
    Funcoes principais: tween, setAnel, setBarra, registrarSlot, registrarSlotInventario, selecionar
]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Hud = {}

--// Configurações
Hud.CONFIG = {
	anim = 0.15, -- duração padrão das animações
	animAnel = 0.25, -- duração da animação dos anéis
	escalaHover = 1.08, -- escala com o mouse em cima
	escalaSelecionado = 1.12, -- escala do slot selecionado
	strokeBoost = 0.5, -- quanto os UIStrokes ficam mais visíveis na seleção
	nomeToolY = -0.3, -- Y (scale) do nome de Tool quando visível
	nomeStatusY = 1.5, -- Y (scale) do nome de Status quando visível
	maxTools = 3, -- quantos slots de Tool a hotbar tem
	maxMochila = 6, -- quantos slots de item a hotbar tem
	teclas = { -- teclas dos slots da hotbar, na ordem (1 a 0)
		Enum.KeyCode.One,
		Enum.KeyCode.Two,
		Enum.KeyCode.Three,
		Enum.KeyCode.Four,
		Enum.KeyCode.Five,
		Enum.KeyCode.Six,
		Enum.KeyCode.Seven,
		Enum.KeyCode.Eight,
		Enum.KeyCode.Nine,
		Enum.KeyCode.Zero,
	},
	teclaInventario = "'", -- caractere que abre/fecha o inventário (independe do layout)
}

--// Tween padrão (Quad Out)
function Hud.tween(obj, props, tempo)
	local t = TweenService:Create(
		obj,
		TweenInfo.new(tempo or Hud.CONFIG.anim, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		props
	)
	t:Play()
	return t
end

--// Anéis (barras circulares via UIStroke + UIGradient)
-- Um NumberValue por anel guia a animação: as duas metades derivam do mesmo
-- valor, então o consumo é sempre sequencial (horário) e nunca dessincroniza.
-- Metade cheia = gradiente desligado / metade vazia = stroke desligado, pra
-- não aparecer emenda no encontro das duas metades (12h e 6h).
local aneis = {}

local function valorAnel(anel)
	local valor = aneis[anel]
	if not valor then
		local ls = anel:WaitForChild("LeftFrame"):WaitForChild("Fill"):WaitForChild("UIStroke")
		local rs = anel:WaitForChild("RightFrame"):WaitForChild("Fill"):WaitForChild("UIStroke")
		local lg = ls:WaitForChild("UIGradient")
		local rg = rs:WaitForChild("UIGradient")
		local function aplicar(alpha)
			local fe = math.min(alpha, 0.5) / 0.5
			local fd = math.max(alpha - 0.5, 0) / 0.5
			ls.Enabled = fe > 0.001
			lg.Enabled = fe < 0.999
			lg.Rotation = (1 - fe) * 180
			rs.Enabled = fd > 0.001
			rg.Enabled = fd < 0.999
			rg.Rotation = 360 - fd * 180
		end
		valor = Instance.new("NumberValue")
		valor.Value = 1
		valor.Changed:Connect(aplicar)
		aplicar(valor.Value)
		valor.Parent = anel
		anel.Destroying:Connect(function()
			aneis[anel] = nil
		end)
		aneis[anel] = valor
	end
	return valor
end

function Hud.setAnel(anel, alpha, instantaneo)
	alpha = math.clamp(alpha, 0, 1)
	local valor = valorAnel(anel)
	if instantaneo then
		valor.Value = alpha -- aplica na hora, sem tween (evita "piscar cheio")
	else
		Hud.tween(valor, { Value = alpha }, Hud.CONFIG.animAnel)
	end
end

--// Barras lineares
-- Anima a largura do frame de clip (ClipsDescendants); a barra interna tem
-- tamanho fixo em pixels, então é cortada em vez de espremida e o UICorner
-- não deforma.
function Hud.setBarra(clip, alpha)
	Hud.tween(clip, { Size = UDim2.new(math.clamp(alpha, 0, 1), 0, 1, 0) })
end

--// Slots (hover, nome e seleção)
local function atualizarTamanho(s)
	if s.semEscala then
		return -- slots do inventário não crescem
	end
	local escala = (s.selecionado and Hud.CONFIG.escalaSelecionado or 1) * (s.hover and Hud.CONFIG.escalaHover or 1)
	Hud.tween(s.botao, { Size = UDim2.fromOffset(s.largura * escala, s.altura * escala) })
end

local function mostrarNome(s, mostrar)
	Hud.tween(s.nome, { TextTransparency = mostrar and 0 or 1, Position = mostrar and s.nomeHover or s.nomeBase })
	if s.nomeSombra then
		Hud.tween(s.nomeSombra, { Transparency = mostrar and 0.5 or 1 })
	end
end

-- Registra hover em um botão; nomeHoverY é o Y (scale) do nome quando visível.
function Hud.registrarSlot(botao, nomeHoverY)
	local nome = botao:WaitForChild("Nome")
	local icone = botao:WaitForChild("Icone")
	local s = {
		botao = botao,
		largura = botao.Size.X.Offset,
		altura = botao.Size.Y.Offset,
		nome = nome,
		nomeSombra = nome:FindFirstChild("UIShadow"),
		nomeBase = nome.Position,
		nomeHover = UDim2.new(nome.Position.X.Scale, nome.Position.X.Offset, nomeHoverY, 0),
		icone = icone,
		iconeBase = icone.ImageTransparency,
		strokes = {}, -- [UIStroke] = transparência base
		hover = false,
		selecionado = false,
	}
	for _, obj in botao:GetDescendants() do
		if obj:IsA("UIStroke") then
			s.strokes[obj] = obj.Transparency
		end
	end
	nome.TextTransparency = 1
	if s.nomeSombra then
		s.nomeSombra.Transparency = 1
	end
	nome.Visible = true

	botao.MouseEnter:Connect(function()
		s.hover = true
		atualizarTamanho(s)
		mostrarNome(s, true)
	end)
	botao.MouseLeave:Connect(function()
		s.hover = false
		atualizarTamanho(s)
		mostrarNome(s, false)
	end)
	return s
end

-- Slot do inventário: não cresce no hover; mostra o nome numa dica junto ao cursor.
function Hud.registrarSlotInventario(botao, dica)
	local icone = botao:WaitForChild("Icone")
	local s = {
		botao = botao,
		icone = icone,
		iconeBase = icone.ImageTransparency,
		strokes = {}, -- [UIStroke] = transparência base
		hover = false,
		selecionado = false,
		semEscala = true,
	}
	for _, obj in botao:GetDescendants() do
		if obj:IsA("UIStroke") then
			s.strokes[obj] = obj.Transparency
		end
	end
	local nome = botao:FindFirstChild("Nome")
	if nome then
		nome.Visible = false -- usa a dica flutuante, não o nome fixo
	end

	botao.MouseEnter:Connect(function()
		dica.Text = botao.Name
		dica.Visible = true
	end)
	botao.MouseMoved:Connect(function()
		local m = UserInputService:GetMouseLocation()
		local inset = GuiService:GetGuiInset()
		dica.Position = UDim2.fromOffset(m.X - inset.X + 12, m.Y - inset.Y - 6)
	end)
	botao.MouseLeave:Connect(function()
		dica.Visible = false
	end)
	return s
end

-- Aplica/remove o visual de selecionado (equipado).
function Hud.selecionar(s, ativo)
	if s.selecionado == ativo then
		return
	end
	s.selecionado = ativo
	atualizarTamanho(s)
	Hud.tween(s.icone, { ImageTransparency = ativo and 0 or s.iconeBase })
	s.icone.ZIndex = ativo and 2 or 1
	for stroke, base in s.strokes do
		Hud.tween(stroke, { Transparency = ativo and math.clamp(base - Hud.CONFIG.strokeBoost, 0, 1) or base })
	end
end

return Hud
