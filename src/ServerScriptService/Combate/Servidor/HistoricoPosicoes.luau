--!strict

--[[
	Script: HistoricoPosicoes.luau
	Caminho: src/ServerScriptService/Combate/Servidor
	Responsabilidade: Guarda um historico curto (0.6s) da posicao do
	    HumanoidRootPart de players e NPCs, permitindo validar um hit contra a
	    posicao que o alvo tinha no instante em que o atacante viu o golpe.
	Uso: ModuleScript; chame HistoricoPosicoes.Iniciar() uma vez no servidor.
	Nao faz: Nao move nem corrige personagens; so amostra e interpola.
	Funcoes principais: Iniciar, Registrar, Remover, ObterPosicao
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local TAXA_AMOSTRAGEM = 1 / 20
local DURACAO_HISTORICO = 0.6
local MAX_AMOSTRAS = math.ceil(DURACAO_HISTORICO / TAXA_AMOSTRAGEM) + 2

local HistoricoPosicoes = {}

type Amostra = { t: number, p: Vector3 }
type Trilha = { amostras: { Amostra }, raiz: BasePart? }

local trilhas: { [Model]: Trilha } = {}
local acumulador = 0
local iniciado = false

local function obterRaiz(modelo: Model): BasePart?
	local trilha = trilhas[modelo]
	if trilha and trilha.raiz and trilha.raiz.Parent then
		return trilha.raiz
	end
	local raiz = modelo:FindFirstChild("HumanoidRootPart") :: BasePart?
	if trilha then
		trilha.raiz = raiz
	end
	return raiz
end

function HistoricoPosicoes.Registrar(inst: Instance)
	if not inst:IsA("Model") or trilhas[inst] then
		return
	end
	trilhas[inst] = { amostras = {}, raiz = nil }
end

function HistoricoPosicoes.Remover(inst: Instance)
	if inst:IsA("Model") then
		trilhas[inst] = nil
	end
end

-- Posicao interpolada no tempo de servidor pedido. Retorna nil quando nao ha
-- historico util (ai o chamador deve usar a posicao atual).
function HistoricoPosicoes.ObterPosicao(modelo: Model, tempo: number): Vector3?
	local trilha = trilhas[modelo]
	if not trilha then
		return nil
	end

	local amostras = trilha.amostras
	local n = #amostras
	if n == 0 then
		return nil
	end

	if tempo >= amostras[n].t then
		return amostras[n].p
	end
	if tempo <= amostras[1].t then
		return amostras[1].p
	end

	for i = n, 2, -1 do
		local depois = amostras[i]
		local antes = amostras[i - 1]
		if tempo >= antes.t and tempo <= depois.t then
			local intervalo = depois.t - antes.t
			if intervalo <= 0 then
				return depois.p
			end
			return antes.p:Lerp(depois.p, (tempo - antes.t) / intervalo)
		end
	end

	return amostras[n].p
end

local function amostrar()
	local agora = workspace:GetServerTimeNow()
	for modelo, trilha in trilhas do
		if not modelo.Parent then
			trilhas[modelo] = nil
			continue
		end
		local raiz = obterRaiz(modelo)
		if not raiz then
			continue
		end
		local amostras = trilha.amostras
		table.insert(amostras, { t = agora, p = raiz.Position })
		while #amostras > MAX_AMOSTRAS do
			table.remove(amostras, 1)
		end
	end
end

local function ligarJogador(player: Player)
	player.CharacterAdded:Connect(HistoricoPosicoes.Registrar)
	player.CharacterRemoving:Connect(HistoricoPosicoes.Remover)
	if player.Character then
		HistoricoPosicoes.Registrar(player.Character)
	end
end

function HistoricoPosicoes.Iniciar()
	if iniciado then
		return
	end
	iniciado = true

	for _, player in Players:GetPlayers() do
		ligarJogador(player)
	end
	Players.PlayerAdded:Connect(ligarJogador)

	for _, inst in CollectionService:GetTagged("NPC") do
		HistoricoPosicoes.Registrar(inst)
	end
	CollectionService:GetInstanceAddedSignal("NPC"):Connect(HistoricoPosicoes.Registrar)
	CollectionService:GetInstanceRemovedSignal("NPC"):Connect(HistoricoPosicoes.Remover)

	RunService.Heartbeat:Connect(function(dt)
		acumulador += dt
		if acumulador < TAXA_AMOSTRAGEM then
			return
		end
		acumulador -= TAXA_AMOSTRAGEM
		if acumulador > TAXA_AMOSTRAGEM then
			acumulador = 0
		end
		amostrar()
	end)
end

return HistoricoPosicoes
