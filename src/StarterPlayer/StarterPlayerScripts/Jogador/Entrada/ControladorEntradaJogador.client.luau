--[[
    Script: ControladorEntradaJogador.client.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/Jogador/Entrada
    Responsabilidade: Detecta inputs do jogador e distribui intencoes para movimento, combate e parkour.
    Uso: LocalScript; roda automaticamente para o jogador local em src/StarterPlayer/StarterPlayerScripts/Jogador/Entrada.
    Nao faz: Nao valida autoridade do servidor, nao salva dados persistentes e nao substitui regras server-side.
    Funcoes principais: EstaSegurandoM1, EstaEmAnimacaoEquip, OnEquipAnimacaoTerminou, DebugWarn, EnviarAcaoComDebounce
]]
local DEBUG_ENABLED = false

local function DebugPrint(...)
	if DEBUG_ENABLED then
		print(...)
	end
end

local function DebugWarn(...)
	if DEBUG_ENABLED then
		warn(...)
	end
end

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientBridge =
	require(ReplicatedStorage:WaitForChild("Jogador"):WaitForChild("ComunicacaoCliente"):WaitForChild("PonteCliente"))

local player = Players.LocalPlayer

local Modulo_Configuracoes =
	require(ReplicatedStorage:WaitForChild("Combate"):WaitForChild("Configuracoes"):WaitForChild("ConfigCombate"))
local ModEquip =
	require(ReplicatedStorage:WaitForChild("Equipamentos"):WaitForChild("ValidacaoEquipamentos"))

local Remotos = ReplicatedStorage:WaitForChild("Remotos")
local TentarAcao = Remotos:WaitForChild("TentarAcao")
local EquipAnimacaoTerminou = Remotos:WaitForChild("EquipAnimacaoTerminou")
local Configuracao = {

	CooldownDefesa = 0.5,

	DebounceAcao = 0.05,

	TeclaAgachar = Enum.KeyCode.C,
	TeclaCorrer = Enum.KeyCode.LeftShift,
	TeclaQuebrarDefesa = Enum.KeyCode.G,
	TeclaRoll = Enum.KeyCode.Q,
}

local estadoInput = {
	mouse1Pressionado = false,
	mouse2Pressionado = false,
	tempoMouse1 = 0,
	tempoMouse2 = 0,
	agachadoAtivo = false,
	correndoAtivo = false,
	ultimaDefesa = 0,
}

local toolConexoes: { RBXScriptConnection } = {}

local InputDebounce = require(ReplicatedStorage:WaitForChild("Jogador"):WaitForChild("Entrada"):WaitForChild("DebounceEntrada"))

local function EnviarAcaoComDebounce(acao: string, dados: any?)
	InputDebounce.EnviarAcaoComDebounce(TentarAcao, acao, dados)
end

function ClientBridge.EstaSegurandoM1()
	return estadoInput.mouse1Pressionado
end


local estadoEquip = "idle"
local toolAtualEquipado: Tool? = nil
local toolPendente: Tool? = nil
local revertendoTool = false

function ClientBridge.EstaEmAnimacaoEquip()
	return estadoEquip ~= "idle"
end

local function EnviarAcao(acao: string, dados: any?)
	TentarAcao:FireServer(acao, dados)
end

local function ObterModoDoTool(tool: Tool): string?
	if not tool then
		return nil
	end

	local modoBase = nil
	local dados = tool:FindFirstChild("Dados")
	if dados and dados:IsA("Folder") then
		local modoValue = dados:FindFirstChild("modoAnimacao")
		if modoValue and modoValue:IsA("StringValue") and modoValue.Value ~= "" and modoValue.Value ~= "Base" then
			modoBase = modoValue.Value
		end
	else

		local modoValue = tool:FindFirstChild("modoAnimacao")
		if modoValue and modoValue:IsA("StringValue") and modoValue.Value ~= "" and modoValue.Value ~= "Base" then
			modoBase = modoValue.Value
		end
	end

	if not modoBase then
		return nil
	end

	local toolEsq = ClientBridge.ObterEquipamentoBraco and ClientBridge.ObterEquipamentoBraco("LeftArm") or nil
	local estadoEsq = ModEquip.ResolverEstadoMaoEsquerda(toolEsq)
	local categoriaDir = ClientBridge.ObterCategoriaRightArm and ClientBridge.ObterCategoriaRightArm() or nil

	local modoResolvido = ModEquip.ResolverModoAtivo(modoBase, estadoEsq, categoriaDir)
	DebugPrint("[EntradaJogador] Modo base:", modoBase, "| Estado esq:", estadoEsq, "| Resolvido:", modoResolvido)

	return modoResolvido
end

local function ObterHumanoid(): Humanoid?
	local char = player.Character
	if char then
		return char:FindFirstChildOfClass("Humanoid") :: Humanoid?
	end
	return nil
end

local function IniciarEquipar(tool: Tool, modo: string)
	estadoEquip = "equipando"
	EnviarAcao("Equipar", modo)
	DebugPrint("[EntradaJogador] Iniciando equipar:", tool.Name, "- Modo:", modo)
end

local function IniciarDesequipar(tool: Tool)
	estadoEquip = "desequipando"
	EnviarAcao("Desequipar")
	DebugPrint("[EntradaJogador] Iniciando desequipar:", tool and tool.Name or "?")
end

ClientBridge.OnEquipAnimacaoTerminou = function(direcaoFinal: number)
	DebugPrint(
		"[EntradaJogador] Animacao terminou. Direcao:",
		direcaoFinal,
		"Tool atual:",
		toolAtualEquipado and toolAtualEquipado.Name or "nil",
		"Tool pendente:",
		toolPendente and toolPendente.Name or "nil"
	)

	if direcaoFinal == 1 then

		local char = player.Character
		if char then
			local toolNoCharacter = char:FindFirstChildOfClass("Tool") :: Tool?
			if toolNoCharacter then
				toolAtualEquipado = toolNoCharacter
			end
		end
		toolPendente = nil
	elseif direcaoFinal == -1 then

		toolAtualEquipado = nil
	end

	estadoEquip = "idle"

	EquipAnimacaoTerminou:FireServer()

	if direcaoFinal == -1 and toolPendente then
		local pendente = toolPendente
		toolPendente = nil
		local modo = ObterModoDoTool(pendente)
		if modo then

			if pendente.Parent == player.Character then
				IniciarEquipar(pendente, modo)
			else
				DebugPrint("[EntradaJogador] Tool pendente nao esta mais no character, ignorando")
			end
		end
	end
end

local function ProcessarMouse1Pressionado()
	if ClientBridge.EstaEmParkour and ClientBridge.EstaEmParkour() then
		DebugPrint("[EntradaJogador] M1 ignorado - jogador em parkour")
		return
	end

	estadoInput.mouse1Pressionado = true
	estadoInput.tempoMouse1 = tick()

	local comboAtivo = ClientBridge.EstaComboAtivo and ClientBridge.EstaComboAtivo()
	local janelaAtiva = ClientBridge.EstaJanelaComboAtiva and ClientBridge.EstaJanelaComboAtiva()

	if comboAtivo or janelaAtiva then
		if ClientBridge.MarcarContinuarCombo then
			local marcou = ClientBridge.MarcarContinuarCombo()
			if marcou then
				EnviarAcao("AtacarLeveEmPe")
				return
			end
		end
	end

	if ClientBridge.PodeAtacarLeve and not ClientBridge.PodeAtacarLeve() then
		DebugPrint("[EntradaJogador] M1 ignorado - ataque em cooldown pós-combo")
		return
	end

	DebugPrint("[EntradaJogador] M1 pressionado - iniciando ataque leve")
	if estadoInput.agachadoAtivo then
		EnviarAcao("AtacarLeveAgachado")
	else
		EnviarAcao("AtacarLeveEmPe")
	end
end

local function ProcessarMouse1Solto()
	if not estadoInput.mouse1Pressionado then
		return
	end

	estadoInput.mouse1Pressionado = false
	DebugPrint("[EntradaJogador] M1 solto")
	if ClientBridge.SoltouM1 then
		ClientBridge.SoltouM1()
	end
end

local function ProcessarMouse2Pressionado()
	if ClientBridge.EstaEmParkour and ClientBridge.EstaEmParkour() then
		DebugPrint("[EntradaJogador] M2 ignorado - jogador em parkour")
		return
	end

	local agora = tick()
	if (agora - estadoInput.ultimaDefesa) < Configuracao.CooldownDefesa then
		return
	end

	estadoInput.mouse2Pressionado = true
	estadoInput.tempoMouse2 = agora

	if ClientBridge.TentarCancelarAtaquePorDefesa then
		local cancelou, tipoAtaque = ClientBridge.TentarCancelarAtaquePorDefesa()
		if cancelou then
			DebugPrint("[EntradaJogador] Ataque cancelado por defesa:", tipoAtaque)

			EnviarAcao("CancelarAtaquePorDefesa", tipoAtaque)

			local tempoParaDefesa = Modulo_Configuracoes.ObterConfiguracao("TempoSegurandoM2ParaDefesa") or 0.15

			task.delay(tempoParaDefesa, function()

				if estadoInput.mouse2Pressionado then
					DebugPrint("[EntradaJogador] M2 ainda pressionado após cancel - iniciando defesa")

					if ClientBridge.CancelarCancelPendente then
						ClientBridge.CancelarCancelPendente()
					end
					estadoInput.ultimaDefesa = tick()

					local shiftLockAtivo = ClientBridge.LerStatusLocal and ClientBridge.LerStatusLocal("ShiftLockOn")
						or false
					EnviarAcao("Bloquear", { shiftLock = shiftLockAtivo, timestamp = tick() })
				else
					DebugPrint("[EntradaJogador] M2 solto após cancel - apenas cancelou, sem defesa")

					if ClientBridge.ResolverCancelPendente then
						ClientBridge.ResolverCancelPendente()
					end
				end
			end)

			return
		end
	end

	estadoInput.ultimaDefesa = agora

	local shiftLockAtivo = ClientBridge.LerStatusLocal and ClientBridge.LerStatusLocal("ShiftLockOn") or false
	EnviarAcao("Bloquear", { shiftLock = shiftLockAtivo, timestamp = tick() })
end

local function ProcessarMouse2Solto()
	if not estadoInput.mouse2Pressionado then
		return
	end

	estadoInput.mouse2Pressionado = false
	EnviarAcao("PararBloqueio")
end

local function ProcessarAgacharPressionado()
	estadoInput.agachadoAtivo = true
	EnviarAcaoComDebounce("Agachar")
end

local function ProcessarAgacharSolto()
	estadoInput.agachadoAtivo = false
	EnviarAcaoComDebounce("Levantar")
end

local function ProcessarQuebrarDefesa()
	EnviarAcaoComDebounce("QuebrarDefesa")
end

local function ProcessarToolEquipado(tool: Tool)

	if revertendoTool then
		return
	end

	local dadosFolder = tool:FindFirstChild("Dados")
	if dadosFolder then
		local tipoValue = dadosFolder:FindFirstChild("Tipo")
		if tipoValue and tipoValue:IsA("StringValue") then
			local tipo = tipoValue.Value
			if tipo == "Armas" or tipo == "Armaduras" then
				DebugPrint("[EntradaJogador] Tool de equipamento ignorado (EquipamentoController cuida):", tool.Name)
				return
			end
		end
	end

	local modoDesejado = ObterModoDoTool(tool)
	if not modoDesejado then
		DebugWarn("[EntradaJogador] Tool '", tool.Name, "' não tem modoAnimacao válido")
		return
	end

	DebugPrint("[EntradaJogador] Tool adicionado:", tool.Name, "- Estado atual:", estadoEquip)

	local podeAlterar = ClientBridge.PodeAlterarTool and ClientBridge.PodeAlterarTool()
	if not podeAlterar then

		DebugPrint("[EntradaJogador] Troca bloqueada - revertendo. Tool:", tool.Name)
		local humanoid = ObterHumanoid()
		if humanoid then
			revertendoTool = true

			if toolAtualEquipado and toolAtualEquipado ~= tool then

				humanoid:UnequipTools()
				task.defer(function()
					if toolAtualEquipado and toolAtualEquipado.Parent then
						humanoid:EquipTool(toolAtualEquipado)
					end
					revertendoTool = false
				end)
			elseif toolAtualEquipado == tool then

				revertendoTool = false
			else

				humanoid:UnequipTools()
				revertendoTool = false
			end
		end
		return
	end

	for _, conexao in ipairs(toolConexoes) do
		pcall(function()
			conexao:Disconnect()
		end)
	end
	table.clear(toolConexoes)

	local conexaoActivated = tool.Activated:Connect(function()
		ProcessarMouse1Pressionado()
	end)
	table.insert(toolConexoes, conexaoActivated)

	local conexaoDeactivated = tool.Deactivated:Connect(function()
		ProcessarMouse1Solto()
	end)
	table.insert(toolConexoes, conexaoDeactivated)

	DebugPrint("[EntradaJogador] Configurado tool.Activated/Deactivated para:", tool.Name)

	if estadoEquip == "idle" then
		if toolAtualEquipado then

			toolPendente = tool
			IniciarDesequipar(toolAtualEquipado)
		else

			IniciarEquipar(tool, modoDesejado)
		end
		return
	end

	if estadoEquip == "desequipando" then
		toolPendente = tool
		DebugPrint("[EntradaJogador] Desequipando - tool pendente atualizado para:", tool.Name)
		return
	end

	DebugPrint("[EntradaJogador] Tool adicionado durante animação de equipar - ignorando")
end

local function ProcessarToolDesequipado(tool: Tool)

	if revertendoTool then
		return
	end

	DebugPrint("[EntradaJogador] Tool removido:", tool.Name, "- Estado atual:", estadoEquip)

	for _, conexao in ipairs(toolConexoes) do
		pcall(function()
			conexao:Disconnect()
		end)
	end
	table.clear(toolConexoes)
	DebugPrint("[EntradaJogador] Limpas conexões tool.Activated/Deactivated para:", tool.Name)

	local podeAlterar = ClientBridge.PodeAlterarTool and ClientBridge.PodeAlterarTool()
	if not podeAlterar then

		DebugPrint("[EntradaJogador] Desequip bloqueado - revertendo. Tool:", tool.Name)
		local humanoid = ObterHumanoid()
		if humanoid and tool.Parent then
			revertendoTool = true
			humanoid:EquipTool(tool)
			revertendoTool = false
		end
		return
	end

	if estadoEquip == "idle" then
		if toolAtualEquipado == tool then
			IniciarDesequipar(tool)
		end
		return
	end

	DebugPrint("[EntradaJogador] Tool removido durante animação - ignorando (não deveria ocorrer)")
end

local function ProcessarRoll()
	if ClientBridge.EstaEmParkour and ClientBridge.EstaEmParkour() then
		DebugPrint("[EntradaJogador] Roll bloqueado: Jogador em parkour")
		return
	end

	if ClientBridge.EstaEmAnimacaoEquip and ClientBridge.EstaEmAnimacaoEquip() then
		DebugPrint("[EntradaJogador] Roll bloqueado: Animação de equipamento em andamento")
		return
	end

	local cooldownRoll = Modulo_Configuracoes.ObterConfiguracao("CooldownRoll") or 1.5
	local agora = tick()
	local ultimoRoll = ClientBridge.UltimoRollTime or 0
	if (agora - ultimoRoll) < cooldownRoll then
		DebugPrint("[EntradaJogador] Roll bloqueado: Cooldown ativo")
		return
	end

	-- Salva a rotação original do boneco antes do roll começar
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if hrp and humanoid then
		ClientBridge.CFrameRotacaoOriginalRoll = hrp.CFrame - hrp.Position
		ClientBridge.CFrameRotacaoRoll = hrp.CFrame - hrp.Position
		ClientBridge.PreRollActive = true

		local moveDir = humanoid.MoveDirection
		if moveDir.Magnitude > 0.1 then
			ClientBridge.DirecaoMovimentoRoll = Vector3.new(moveDir.X, 0, moveDir.Z).Unit
		else
			ClientBridge.DirecaoMovimentoRoll = nil
		end
	end

	local direcao = "Frente"
	if ClientBridge.CalcularDirecaoRoll then
		direcao = ClientBridge.CalcularDirecaoRoll(true)
	end

	EnviarAcao("Roll", direcao)

	task.delay(0.5, function()
		if ClientBridge.PreRollActive then
			ClientBridge.PreRollActive = nil
			ClientBridge.CFrameRotacaoRoll = nil
			ClientBridge.CFrameRotacaoOriginalRoll = nil
			ClientBridge.DirecaoMovimentoRoll = nil
		end
	end)
end

local function ProcessarDash(direcaoParam: string?)
	if ClientBridge.EstaEmParkour and ClientBridge.EstaEmParkour() then
		DebugPrint("[EntradaJogador] Dash bloqueado: Jogador em parkour")
		return
	end

	if ClientBridge.EstaEmAnimacaoEquip and ClientBridge.EstaEmAnimacaoEquip() then
		DebugPrint("[EntradaJogador] Dash bloqueado: Animação de equipamento em andamento")
		return
	end

	local estaCorrendo = ClientBridge.LerStatusLocal and ClientBridge.LerStatusLocal("CorrendoOn") or false
	local estadoMov = ClientBridge.LerStatusLocal and ClientBridge.LerStatusLocal("estadoMov") or "Parado"
	if estaCorrendo or estadoMov == "Correndo" then
		DebugPrint("[EntradaJogador] Dash bloqueado: Jogador está correndo")
		return
	end

	local cooldownDash = Modulo_Configuracoes.ObterConfiguracao("CooldownDash") or 1.5
	local agora = tick()
	local ultimoDash = ClientBridge.UltimoDashTime or 0
	if (agora - ultimoDash) < cooldownDash then
		DebugPrint("[EntradaJogador] Dash bloqueado: Cooldown ativo")
		return
	end

	-- Salva a rotação original do boneco antes do dash começar
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if hrp and humanoid then
		ClientBridge.CFrameRotacaoDash = hrp.CFrame - hrp.Position
		ClientBridge.PreDashActive = true
	end

	local direcao = direcaoParam or "Tras"

	EnviarAcao("Dash", direcao)

	task.delay(0.5, function()
		if ClientBridge.PreDashActive then
			ClientBridge.PreDashActive = nil
			ClientBridge.CFrameRotacaoDash = nil
		end
	end)
end

local function ProcessarPular()

	if estadoInput.agachadoAtivo then
		estadoInput.agachadoAtivo = false
		EnviarAcao("Levantar")
		task.delay(0.05, function()
			EnviarAcao("Pular")
		end)
		return
	end

	-- Verifica se o jogador está se movendo para trás ou para os lados.
	-- Se sim, a tecla Space aciona o Dash em vez do pulo (apenas se ShiftLock estiver ativo).
	local direcao = "Frente"
	if ClientBridge.CalcularDirecaoRoll then
		direcao = ClientBridge.CalcularDirecaoRoll(false)
	end

	local shiftLockAtivo = ClientBridge.LerStatusLocal and ClientBridge.LerStatusLocal("ShiftLockOn") or false
	if shiftLockAtivo and (direcao == "Tras" or direcao == "Esquerda" or direcao == "Direita") then
		ProcessarDash(direcao)
		return
	end

	EnviarAcao("Pular")
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		ProcessarMouse2Pressionado()
		return
	end

	if input.KeyCode == Configuracao.TeclaCorrer then
		estadoInput.correndoAtivo = true

		if estadoInput.agachadoAtivo then
			estadoInput.agachadoAtivo = false
			EnviarAcao("Levantar")

		end

		return
	end

	if input.KeyCode == Configuracao.TeclaAgachar then
		ProcessarAgacharPressionado()
		return
	end

	if input.KeyCode == Configuracao.TeclaQuebrarDefesa then
		ProcessarQuebrarDefesa()
		return
	end

	if input.KeyCode == Configuracao.TeclaRoll then
		ProcessarRoll()
		return
	end

	if input.KeyCode == Enum.KeyCode.Space then
		ProcessarPular()
		return
	end
end)

UserInputService.InputEnded:Connect(function(input, _gameProcessed)

	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		ProcessarMouse2Solto()
		return
	end

	if input.KeyCode == Configuracao.TeclaCorrer then
		estadoInput.correndoAtivo = false

		return
	end

	if input.KeyCode == Configuracao.TeclaAgachar then
		ProcessarAgacharSolto()
		return
	end
end)



local function OnChildAdded(child)
	if child:IsA("Tool") then

		local char = player.Character
		if char then
			local humanoid = char:FindFirstChild("Humanoid") :: Humanoid?
			if humanoid and humanoid.Health <= 0 then

				local dados = child:FindFirstChild("Dados")
				local temModo = false
				if dados and dados:IsA("Folder") then
					temModo = dados:FindFirstChild("modoAnimacao") ~= nil
				else
					temModo = child:FindFirstChild("modoAnimacao") ~= nil
				end
				if temModo then
					humanoid:UnequipTools()
					DebugPrint("[EntradaJogador] Tool desequipado automaticamente (jogador morto):", child.Name)
				end
				return
			end
		end

		ProcessarToolEquipado(child)
	end
end

local function OnChildRemoved(child)
	if child:IsA("Tool") then
		ProcessarToolDesequipado(child)
	end
end

local function ConfigurarCharacter(char)

	estadoInput = {
		mouse1Pressionado = false,
		mouse2Pressionado = false,
		tempoMouse1 = 0,
		tempoMouse2 = 0,
		agachadoAtivo = false,
		correndoAtivo = false,
		ultimaDefesa = 0,
	}

	estadoEquip = "idle"
	toolAtualEquipado = nil
	toolPendente = nil
	revertendoTool = false

	char.ChildAdded:Connect(OnChildAdded)
	char.ChildRemoved:Connect(OnChildRemoved)

	local humanoid = char:WaitForChild("Humanoid") :: Humanoid
	humanoid.Died:Connect(function()

		estadoEquip = "idle"
		toolPendente = nil
		revertendoTool = false
		DebugPrint("[EntradaJogador] Jogador morreu - Estado resetado")
	end)

	for _, child in pairs(char:GetChildren()) do
		if child:IsA("Tool") then
			ProcessarToolEquipado(child)
			break
		end
	end
end

player.CharacterAdded:Connect(ConfigurarCharacter)

if player.Character then
	ConfigurarCharacter(player.Character)
end

DebugPrint("[EntradaJogador] Inicializado - capturando inputs")
