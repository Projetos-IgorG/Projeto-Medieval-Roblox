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
local CatalogoItens = require(ReplicatedStorage:WaitForChild("Dados"):WaitForChild("Itens"):WaitForChild("CatalogoItens"))

local ClientBridge =
	require(ReplicatedStorage:WaitForChild("Jogador"):WaitForChild("ComunicacaoCliente"):WaitForChild("PonteCliente"))

local player = Players.LocalPlayer

local Modulo_Configuracoes =
	require(ReplicatedStorage:WaitForChild("Combate"):WaitForChild("Configuracoes"):WaitForChild("ConfigCombate"))
local ModEquip =
	require(ReplicatedStorage:WaitForChild("SistemaItens"):WaitForChild("ValidacaoEquipamentos"))

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

function ClientBridge.EstaSegurandoM2()
	return estadoInput.mouse2Pressionado
end


local estadoEquip = "idle"
local toolAtualEquipado: Tool? = nil
local toolPendente: Tool? = nil
local revertendoTool = false
local bloquearPuloTemp = false
local blockJumpUntilRelease = false
local spaceOrButtonAHeld = false

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

	local id = tool:GetAttribute("Id")
	local catalogData = id and CatalogoItens.Get(id)
	local modoBase = catalogData and catalogData.ModoAnimacao

	if not modoBase then
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
	if ClientBridge.PredictAnimation then
		ClientBridge.PredictAnimation("Equipar", false, 1.0)
	end
	EnviarAcao("Equipar", modo)
	DebugPrint("[EntradaJogador] Iniciando equipar:", tool.Name, "- Modo:", modo)
end

local function IniciarDesequipar(tool: Tool)
	estadoEquip = "desequipando"
	if ClientBridge.PredictAnimation then
		ClientBridge.PredictAnimation("Desequipar", false, 1.0)
	end
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

	local estadoAcao = ClientBridge.LerStatusLocal and ClientBridge.LerStatusLocal("estadoAcao") or "Nenhuma"
	if estadoAcao == "Rolando" or estadoAcao == "Dashando" then
		DebugPrint("[EntradaJogador] M1 ignorado - jogador em esquiva (roll/dash)")
		return
	end

	local estaDefendendo = (estadoAcao == "Defendendo") 
		or (ClientBridge.LerStatusLocal and ClientBridge.LerStatusLocal("bloqueando") == true)
		or estadoInput.mouse2Pressionado
	if estaDefendendo and estadoAcao ~= "Aparando" then
		DebugPrint("[EntradaJogador] M1 ignorado - jogador defendendo/bloqueando")
		return
	end

	estadoInput.mouse1Pressionado = true
	estadoInput.tempoMouse1 = os.clock()

	local comboAtivo = ClientBridge.EstaComboAtivo and ClientBridge.EstaComboAtivo()
	local janelaAtiva = ClientBridge.EstaJanelaComboAtiva and ClientBridge.EstaJanelaComboAtiva()

	if comboAtivo or janelaAtiva then
		if ClientBridge.MarcarContinuarCombo then
			local marcou = ClientBridge.MarcarContinuarCombo()
			if marcou then
				EnviarAcao("AtacarEmPe")
				return
			end
		end
	end

	if ClientBridge.PodeAtacar and not ClientBridge.PodeAtacar() then
		DebugPrint("[EntradaJogador] M1 ignorado - ataque em cooldown pós-combo")
		return
	end

	DebugPrint("[EntradaJogador] M1 pressionado - iniciando ataque")
	if ClientBridge.PredictAnimation then
		ClientBridge.PredictAnimation("Ataque", false, 1.0)
	end
	if estadoInput.agachadoAtivo then
		EnviarAcao("AtacarAgachado")
	else
		EnviarAcao("AtacarEmPe")
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

	local agora = os.clock()
	if (agora - estadoInput.ultimaDefesa) < Configuracao.CooldownDefesa then
		return
	end

	local estadoAcao = ClientBridge.LerStatusLocal and ClientBridge.LerStatusLocal("estadoAcao") or "Nenhuma"
	if estadoAcao == "Rolando" or estadoAcao == "Dashando" then
		DebugPrint("[EntradaJogador] M2 ignorado - jogador em esquiva (roll/dash)")
		return
	end

	if estadoAcao == "Atacando" then
		if ClientBridge.TentarFintar then
			local cancelou, tipoAtaque = ClientBridge.TentarFintar()
			if cancelou then
				estadoInput.mouse2Pressionado = true
				estadoInput.tempoMouse2 = agora
				DebugPrint("[EntradaJogador] Ataque fintado:", tipoAtaque)

				EnviarAcao("Fintar", tipoAtaque)
			else
				DebugPrint("[EntradaJogador] Tentativa de finta falhou (cooldown ou fora da janela) - ignorando M2")
				estadoInput.mouse2Pressionado = false
			end
		else
			estadoInput.mouse2Pressionado = false
		end
		return
	end
	local shiftLockAtivo = ClientBridge.LerStatusLocal and ClientBridge.LerStatusLocal("ShiftLockOn") or false
	if not shiftLockAtivo then
		DebugPrint("[EntradaJogador] M2 ignorado - ShiftLock não está ativo")
		return
	end

	estadoInput.mouse2Pressionado = true
	estadoInput.tempoMouse2 = agora
	estadoInput.ultimaDefesa = agora

	if ClientBridge.PredictAnimation then
		ClientBridge.PredictAnimation("Defesa", true, 1.0)
	end
	EnviarAcao("Bloquear", { shiftLock = shiftLockAtivo, timestamp = workspace:GetServerTimeNow() })
end

local function ProcessarMouse2Solto()
	if not estadoInput.mouse2Pressionado then
		return
	end

	estadoInput.mouse2Pressionado = false
	if ClientBridge.PredictStopAnimation then
		ClientBridge.PredictStopAnimation()
	end
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

local function IsAlreadyEquipped(tool: Tool): boolean
	local char = player.Character
	if not char then return false end
	local equipamento = char:FindFirstChild("Equipamento")
	if not equipamento then return false end
	local bracos = equipamento:FindFirstChild("Bracos")
	if not bracos then return false end
	local rightArm = bracos:FindFirstChild("RightArm") :: ObjectValue
	local leftArm = bracos:FindFirstChild("LeftArm") :: ObjectValue
	return (rightArm and rightArm.Value == tool) or (leftArm and leftArm.Value == tool)
end

local function ProcessarToolEquipado(tool: Tool)

	if revertendoTool then
		return
	end

	local id = tool:GetAttribute("Id")
	local catalogData = id and CatalogoItens.Get(id)
	if catalogData then
		local tipo = catalogData.Tipo
		if tipo == "Tool" and catalogData.Subtipo == "Arma" then
			tipo = "Armas"
		elseif tipo == "Equipment" then
			tipo = "Armaduras"
		end
		if (tipo == "Armas" or tipo == "Armaduras") and not IsAlreadyEquipped(tool) then
			DebugPrint("[EntradaJogador] Tool de equipamento ignorado (EquipamentoController cuida):", tool.Name)
			return
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
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local state = humanoid:GetState()
		local noAr = humanoid.FloorMaterial == Enum.Material.Air 
			or state == Enum.HumanoidStateType.Jumping 
			or state == Enum.HumanoidStateType.Freefall
		if noAr then
			DebugPrint("[EntradaJogador] Roll bloqueado: Jogador no ar")
			return
		end
	end

	local estadoAcao = ClientBridge.LerStatusLocal and ClientBridge.LerStatusLocal("estadoAcao") or "Nenhuma"
	if estadoAcao == "Atacando" then
		DebugPrint("[EntradaJogador] Roll bloqueado: Jogador atacando")
		return
	end

	if ClientBridge.EstaEmParkour and ClientBridge.EstaEmParkour() then
		DebugPrint("[EntradaJogador] Roll bloqueado: Jogador em parkour")
		return
	end

	if ClientBridge.EstaEmAnimacaoEquip and ClientBridge.EstaEmAnimacaoEquip() then
		DebugPrint("[EntradaJogador] Roll bloqueado: Animação de equipamento em andamento")
		return
	end

	local cooldownRoll = Modulo_Configuracoes.ObterConfiguracao("CooldownRoll") or 1.5
	local agora = os.clock()
	local ultimoRoll = ClientBridge.UltimoRollTime or 0
	local ultimoDash = ClientBridge.UltimoDashTime or 0
	if (agora - ultimoRoll) < cooldownRoll or (agora - ultimoDash) < cooldownRoll then
		DebugPrint("[EntradaJogador] Roll bloqueado: Cooldown ativo (Roll/Dash compartilhado)")
		return
	end

	if spaceOrButtonAHeld then
		blockJumpUntilRelease = true
	end

	-- Salva a rotação original do boneco antes do roll começar
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
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

	if ClientBridge.PredictAnimation then
		local nomeAnim = "Roll" .. direcao
		local velocidadeAnim = Modulo_Configuracoes.ObterConfiguracao("VelocidadeAnimacaoRoll") or 1.0
		ClientBridge.PredictAnimation(nomeAnim, false, velocidadeAnim)
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
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local state = humanoid:GetState()
		local noAr = humanoid.FloorMaterial == Enum.Material.Air 
			or state == Enum.HumanoidStateType.Jumping 
			or state == Enum.HumanoidStateType.Freefall
		if noAr then
			DebugPrint("[EntradaJogador] Dash bloqueado: Jogador no ar")
			return
		end
	end

	local estadoAcao = ClientBridge.LerStatusLocal and ClientBridge.LerStatusLocal("estadoAcao") or "Nenhuma"
	if estadoAcao == "Atacando" then
		DebugPrint("[EntradaJogador] Dash bloqueado: Jogador atacando")
		return
	end

	if ClientBridge.EstaEmParkour and ClientBridge.EstaEmParkour() then
		DebugPrint("[EntradaJogador] Dash bloqueado: Jogador em parkour")
		return
	end

	if ClientBridge.EstaEmAnimacaoEquip and ClientBridge.EstaEmAnimacaoEquip() then
		DebugPrint("[EntradaJogador] Dash bloqueado: Animação de equipamento em andamento")
		return
	end

	local camera = workspace.CurrentCamera
	local isFirstPerson = camera and (camera.Focus.Position - camera.CFrame.Position).Magnitude < 1.0 or false
	local shiftLockAtivo = ClientBridge.LerStatusLocal and ClientBridge.LerStatusLocal("ShiftLockOn") or false
	if not (shiftLockAtivo or isFirstPerson) then
		DebugPrint("[EntradaJogador] Dash bloqueado: Fora de ShiftLock ou Primeira Pessoa")
		return
	end

	local modoAnimacao = ClientBridge.LerStatusLocal and ClientBridge.LerStatusLocal("modoAnimacao") or "Base"
	if not Modulo_Configuracoes.EhCombate(modoAnimacao) then
		DebugPrint("[EntradaJogador] Dash bloqueado: Jogador não está em modo de combate")
		return
	end

	local estaCorrendo = ClientBridge.LerStatusLocal and ClientBridge.LerStatusLocal("CorrendoOn") or false
	local estadoMov = ClientBridge.LerStatusLocal and ClientBridge.LerStatusLocal("estadoMov") or "Parado"
	if estaCorrendo or estadoMov == "Correndo" then
		DebugPrint("[EntradaJogador] Dash bloqueado: Jogador está correndo")
		return
	end

	local cooldownDash = Modulo_Configuracoes.ObterConfiguracao("CooldownDash") or 1.5
	local agora = os.clock()
	local ultimoDash = ClientBridge.UltimoDashTime or 0
	local ultimoRoll = ClientBridge.UltimoRollTime or 0
	if (agora - ultimoDash) < cooldownDash or (agora - ultimoRoll) < cooldownDash then
		DebugPrint("[EntradaJogador] Dash bloqueado: Cooldown ativo (Roll/Dash compartilhado)")
		return
	end

	blockJumpUntilRelease = true

	-- Salva a rotação original do boneco antes do dash começar
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp and humanoid then
		ClientBridge.CFrameRotacaoDash = hrp.CFrame - hrp.Position
		ClientBridge.PreDashActive = true
	end

	local direcao = direcaoParam or "Tras"

	if ClientBridge.PredictAnimation then
		local nomeAnim = "Dash" .. direcao
		local velocidadeAnim = Modulo_Configuracoes.ObterConfiguracao("VelocidadeAnimacaoDash") or 1.0
		ClientBridge.PredictAnimation(nomeAnim, false, velocidadeAnim)
	end
	EnviarAcao("Dash", direcao)

	task.delay(0.5, function()
		if ClientBridge.PreDashActive then
			ClientBridge.PreDashActive = nil
			ClientBridge.CFrameRotacaoDash = nil
		end
	end)
end

local function ProcessarPular()
	local estadoAcao = ClientBridge.LerStatusLocal and ClientBridge.LerStatusLocal("estadoAcao") or "Nenhuma"
	local estaBloqueando = (estadoAcao == "Defendendo") or (ClientBridge.LerStatusLocal and ClientBridge.LerStatusLocal("bloqueando") == true)
	local estaEsquivando = (estadoAcao == "Rolando") or (estadoAcao == "Dashando")
	if estaEsquivando then
		blockJumpUntilRelease = true
		return
	end

	if estaBloqueando then
		return
	end

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
	local modoAnimacao = ClientBridge.LerStatusLocal and ClientBridge.LerStatusLocal("modoAnimacao") or "Base"
	local estaCorrendo = ClientBridge.LerStatusLocal and ClientBridge.LerStatusLocal("CorrendoOn") or false
	local estadoMov = ClientBridge.LerStatusLocal and ClientBridge.LerStatusLocal("estadoMov") or "Parado"
	local emParkour = ClientBridge.EstaEmParkour and ClientBridge.EstaEmParkour() or false
	local noAr = false

	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local state = humanoid:GetState()
		noAr = humanoid.FloorMaterial == Enum.Material.Air 
			or state == Enum.HumanoidStateType.Jumping 
			or state == Enum.HumanoidStateType.Freefall
	end

	local camera = workspace.CurrentCamera
	local isFirstPerson = camera and (camera.Focus.Position - camera.CFrame.Position).Magnitude < 1.0 or false
	local emShiftLockOuPrimeiraPessoa = shiftLockAtivo or isFirstPerson

	local podeDarDash = emShiftLockOuPrimeiraPessoa 
		and (direcao == "Tras" or direcao == "Esquerda" or direcao == "Direita")
		and Modulo_Configuracoes.EhCombate(modoAnimacao)
		and not emParkour
		and not estaCorrendo
		and estadoMov ~= "Correndo"
		and not noAr
		and not estaBloqueando

	if podeDarDash then
		-- Desabilita temporariamente o pulo do humanoid para evitar o pulo automático do Roblox
		bloquearPuloTemp = true
		task.delay(0.2, function()
			bloquearPuloTemp = false
		end)

		if humanoid then
			humanoid.Jump = false
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
			task.delay(0.15, function()
				if humanoid and humanoid.Parent then
					humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
				end
			end)
		end
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

	if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
		spaceOrButtonAHeld = true
		if input.KeyCode == Enum.KeyCode.Space then
			ProcessarPular()
		end
		return
	end
end)

UserInputService.InputEnded:Connect(function(input, _gameProcessed)
	if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
		spaceOrButtonAHeld = false
		blockJumpUntilRelease = false
	end

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

				local id = child:GetAttribute("Id")
				local catalogData = id and CatalogoItens.Get(id)
				local temModo = (catalogData and catalogData.ModoAnimacao ~= nil) or child:FindFirstChild("modoAnimacao") ~= nil
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
	bloquearPuloTemp = false
	blockJumpUntilRelease = false
	spaceOrButtonAHeld = false

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

UserInputService.JumpRequest:Connect(function()
	local estadoAcao = ClientBridge.LerStatusLocal and ClientBridge.LerStatusLocal("estadoAcao") or "Nenhuma"
	local estaBloqueando = (estadoAcao == "Defendendo") or (ClientBridge.LerStatusLocal and ClientBridge.LerStatusLocal("bloqueando") == true)
	local estaEsquivando = (estadoAcao == "Rolando") or (estadoAcao == "Dashando")
	if bloquearPuloTemp or estaBloqueando or estaEsquivando or blockJumpUntilRelease then
		local char = player.Character
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Jump = false
		end
	end
end)

DebugPrint("[EntradaJogador] Inicializado - capturando inputs")
