--[[
    Script: DevAdmin.server.luau
    Caminho: src/ServerScriptService/Administracao
    Responsabilidade: Fornece comandos administrativos e utilitarios de desenvolvimento no servidor.
    Uso: Script de servidor; roda automaticamente em src/ServerScriptService/Administracao quando a instancia existe no jogo.
    Nao faz: Nao controla UI local nem le inputs diretamente; recebe sinais ja autorizados pelo fluxo do jogo.
    Funcoes principais: CriarToolMundo, DarTool, TrazerAlvo, IrAteAlvo, CongelarAlvo, DescongelarAlvo
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ToolBuilder = require(ReplicatedStorage:WaitForChild("Equipamentos"):WaitForChild("ConstrutorFerramentas"))
local ServicosAmbiente = script.Parent.Parent:WaitForChild("Mundo"):WaitForChild("Ambiente")
local ServicoTempoMundo = require(ServicosAmbiente:WaitForChild("ServicoTempoMundo"))
local ServicoAmbienteMundo = require(ServicosAmbiente:WaitForChild("ServicoAmbienteMundo"))

local REMOTE_NAME = "AcaoAdminDev"
local DEFAULT_TOOL_CATEGORY = "Armas"
local DEFAULT_TOOL_NAME = "espada_ferro"

local Remotos = ReplicatedStorage:FindFirstChild("Remotos")
if not Remotos then
	Remotos = Instance.new("Folder")
	Remotos.Name = "Remotos"
	Remotos.Parent = ReplicatedStorage
end

local Remote = Remotos:FindFirstChild(REMOTE_NAME)
if not Remote then
	Remote = Instance.new("RemoteEvent")
	Remote.Name = REMOTE_NAME
	Remote.Parent = Remotos
end

local function responder(jogador, sucesso, mensagem)
	Remote:FireClient(jogador, "Resultado", mensagem, sucesso)
end

local function podeUsarAdmin(jogador)
	if RunService:IsStudio() then
		return true
	end

	if game.CreatorType == Enum.CreatorType.User and jogador.UserId == game.CreatorId then
		return true
	end

	return jogador:GetAttribute("AdminDev") == true
end

local function textoNormalizado(valor)
	return string.lower(tostring(valor or "")):gsub("%s+", "")
end

local function encontrarJogador(nome, padrao)
	local termo = textoNormalizado(nome)
	if termo == "" or termo == "me" or termo == "eu" then
		return padrao
	end

	for _, jogador in ipairs(Players:GetPlayers()) do
		local nomeJogador = textoNormalizado(jogador.Name)
		local nomeExibicao = textoNormalizado(jogador.DisplayName)
		if nomeJogador == termo or nomeExibicao == termo then
			return jogador
		end
	end

	for _, jogador in ipairs(Players:GetPlayers()) do
		local nomeJogador = textoNormalizado(jogador.Name)
		local nomeExibicao = textoNormalizado(jogador.DisplayName)
		if string.find(nomeJogador, termo, 1, true) or string.find(nomeExibicao, termo, 1, true) then
			return jogador
		end
	end

	return nil
end

local function obterHumanoidRootPart(jogador)
	local personagem = jogador.Character
	if not personagem then
		return nil
	end
	return personagem:FindFirstChild("HumanoidRootPart")
end

local function obterCFrameNaFrente(jogador, distancia)
	local hrp = obterHumanoidRootPart(jogador)
	if not hrp then
		return CFrame.new(0, 5, 0)
	end

	local frente = hrp.CFrame.LookVector
	local posicao = hrp.Position + frente * math.max(distancia or 8, 3) + Vector3.new(0, 2, 0)
	return CFrame.lookAt(posicao, posicao + frente)
end

local function procurarFilho(container, nome)
	if not container then
		return nil
	end

	local termo = textoNormalizado(nome)
	local primeiro = nil
	for _, filho in ipairs(container:GetChildren()) do
		if not primeiro then
			primeiro = filho
		end

		local nomeFilho = textoNormalizado(filho.Name)
		if termo ~= "" and (nomeFilho == termo or string.find(nomeFilho, termo, 1, true)) then
			return filho
		end
	end

	return if termo == "" then primeiro else nil
end

local function encontrarTemplateTool(categoria, nomeTool)
	local equipamentos = ReplicatedStorage:FindFirstChild("Equipamentos")
	local modelos = equipamentos and equipamentos:FindFirstChild("Modelos")
	if not modelos then
		return nil
	end

	local nomeCategoria = tostring(categoria or "")
	if nomeCategoria == "" then
		nomeCategoria = DEFAULT_TOOL_CATEGORY
	end

	local nomeTemplate = tostring(nomeTool or "")
	if nomeTemplate == "" then
		nomeTemplate = DEFAULT_TOOL_NAME
	end

	local pastaCategoria = modelos:FindFirstChild(nomeCategoria)
	if pastaCategoria then
		return procurarFilho(pastaCategoria, nomeTemplate)
	end

	for _, pasta in ipairs(modelos:GetChildren()) do
		local encontrado = procurarFilho(pasta, nomeTemplate)
		if encontrado then
			return encontrado
		end
	end

	return nil
end

local function criarTool(jogador, payload, destino)
	local alvo = encontrarJogador(payload.alvo, jogador) or jogador
	local template = encontrarTemplateTool(payload.tipoTool, payload.tool)
	if not template then
		return false, "Template de tool nao encontrado"
	end

	local quantidade = math.clamp(math.floor(tonumber(payload.quantidade) or 1), 1, 20)
	local dados = ToolBuilder.ExtrairDados(template)
	if not dados then
		return false, "Dados da tool nao encontrados"
	end
	dados.Quantidade = quantidade

	local toolCriada = nil
	if destino == "Mundo" then
		local cframe = obterCFrameNaFrente(alvo, tonumber(payload.distancia) or 8)
		toolCriada = ToolBuilder.CriarToolNoMundo(dados, cframe)
	else
		local mochila = alvo:FindFirstChildOfClass("Backpack") or alvo:WaitForChild("Backpack", 5)
		if not mochila then
			return false, "Backpack do alvo nao encontrado"
		end
		toolCriada = ToolBuilder.CriarTool(dados, mochila)
	end

	if not toolCriada then
		return false, "Falha ao criar tool"
	end

	return true, string.format("Tool criada: %s (x%d)", toolCriada.Name, quantidade)
end

local function curarJogador(jogador, payload)
	local alvo = encontrarJogador(payload.alvo, jogador) or jogador
	local humanoid = alvo.Character and alvo.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, "Humanoid do alvo nao encontrado"
	end

	humanoid.Health = humanoid.MaxHealth
	return true, "Jogador curado: " .. alvo.Name
end

local function respawnJogador(jogador, payload)
	local alvo = encontrarJogador(payload.alvo, jogador) or jogador
	alvo:LoadCharacter()
	return true, "Respawn solicitado: " .. alvo.Name
end

local function moverJogador(jogador, payload, modo)
	local alvo = encontrarJogador(payload.alvo, jogador)
	if not alvo then
		return false, "Jogador alvo nao encontrado"
	end

	local origem = if modo == "Trazer" then jogador else alvo
	local destino = if modo == "Trazer" then alvo else jogador
	local origemHrp = obterHumanoidRootPart(origem)
	local destinoHrp = obterHumanoidRootPart(destino)
	if not origemHrp or not destinoHrp then
		return false, "Personagem sem HumanoidRootPart"
	end

	destinoHrp.CFrame = origemHrp.CFrame * CFrame.new(3, 0, -3)
	return true, if modo == "Trazer" then "Jogador trazido" else "Teleportado ate o alvo"
end

local function congelarJogador(jogador, payload, congelado)
	local alvo = encontrarJogador(payload.alvo, jogador) or jogador
	local hrp = obterHumanoidRootPart(alvo)
	if not hrp then
		return false, "HumanoidRootPart do alvo nao encontrado"
	end

	hrp.Anchored = congelado
	return true, if congelado then "Jogador congelado: " .. alvo.Name else "Jogador descongelado: " .. alvo.Name
end

local function limparToolsSoltas()
	local removidas = 0
	for _, filho in ipairs(workspace:GetChildren()) do
		if filho:IsA("Tool") then
			filho:Destroy()
			removidas += 1
		end
	end
	return true, "Tools soltas removidas: " .. tostring(removidas)
end

local function aplicarAmbienteClima(_jogador, payload)
	return ServicoAmbienteMundo:DefinirAmbienteClima(payload.ambiente, payload.clima, payload.transicao)
end

local function definirHorarioMundo(_jogador, payload)
	return ServicoTempoMundo:DefinirHorario(payload.horario or payload.minutos)
end

local function avancarTempoMundo(_jogador, payload)
	return ServicoTempoMundo:AvancarMinutos(payload.minutos or payload.quantidade or 60)
end

local function pausarMundo(_jogador, payload)
	local pausarTempo
	local pausarAmbiente
	if payload.pausado == nil then
		pausarTempo = not ServicoTempoMundo:EstaPausado()
		pausarAmbiente = pausarTempo
	else
		pausarTempo = payload.pausado == true
		pausarAmbiente = pausarTempo
	end
	ServicoTempoMundo:DefinirPausa(pausarTempo)
	ServicoAmbienteMundo:DefinirPausa(pausarAmbiente)
	return true, if pausarTempo then "Mundo pausado" else "Mundo retomado"
end

local handlers = {
	CriarToolMundo = function(jogador, payload)
		return criarTool(jogador, payload, "Mundo")
	end,
	DarTool = function(jogador, payload)
		return criarTool(jogador, payload, "Backpack")
	end,
	CurarAlvo = curarJogador,
	RespawnAlvo = respawnJogador,
	TrazerAlvo = function(jogador, payload)
		return moverJogador(jogador, payload, "Trazer")
	end,
	IrAteAlvo = function(jogador, payload)
		return moverJogador(jogador, payload, "Ir")
	end,
	CongelarAlvo = function(jogador, payload)
		return congelarJogador(jogador, payload, true)
	end,
	DescongelarAlvo = function(jogador, payload)
		return congelarJogador(jogador, payload, false)
	end,
	LimparToolsSoltas = function()
		return limparToolsSoltas()
	end,
	AplicarAmbienteClima = aplicarAmbienteClima,
	DefinirHorarioMundo = definirHorarioMundo,
	AvancarTempoMundo = avancarTempoMundo,
	PausarMundo = pausarMundo,
	MudarDebugParry = function(_jogador, payload)
		local ativo = payload.ativo == true
		ReplicatedStorage:SetAttribute("ParryDebugBlock", ativo)
		for _, desc in ipairs(workspace:GetDescendants()) do
			if desc.Name == "DefesaBlock" and desc:IsA("BasePart") then
				desc.Transparency = if ativo then 0.5 else 1.0
			end
		end
		return true, "Debug parry definido para: " .. tostring(ativo)
	end,
}

Remote.OnServerEvent:Connect(function(jogador, acao, payload)
	if not podeUsarAdmin(jogador) then
		responder(jogador, false, "Sem permissao para usar o painel admin")
		return
	end

	if type(acao) ~= "string" or type(payload) ~= "table" then
		responder(jogador, false, "Requisicao admin invalida")
		return
	end

	local handler = handlers[acao]
	if not handler then
		responder(jogador, false, "Acao admin desconhecida: " .. acao)
		return
	end

	local ok, sucesso, mensagem = pcall(handler, jogador, payload)
	if not ok then
		responder(jogador, false, tostring(sucesso))
		return
	end

	responder(jogador, sucesso == true, tostring(mensagem or "Acao concluida"))
end)
