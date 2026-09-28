--!strict

--[[
	Script: HitReport.luau (filho de Combate)
	Responsabilidade: Receber e validar o reporte de hit do cliente do alvo
	(RemoteEvent NPC_HitReport) e delegar o dano canonico ao
	CombateServidor._ProcessarHit.

	Validacoes (anti-cheat):
	- Cliente so reporta hit no proprio personagem.
	- O tick reportado precisa casar com um swing real do historico
	  (agora com match exato, pois o tick e estavel).
	- Swing interrompido por stun/parry nao aplica dano.
	- Janela temporal do swing com compensacao de RTT.
	- Dedup por swing (um alvo so toma 1 hit por swing).
	- Alvo vivo + distancia plausivel com compensacao de RTT.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent:WaitForChild("Config"))
local Estado = require(script.Parent:WaitForChild("Estado"))

type EstadoNPC = Estado.EstadoNPC
type RegistroSwing = Estado.RegistroSwing

local Remotos = ReplicatedStorage:WaitForChild("Remotos")
local NPC_HitReport: RemoteEvent = Remotos:WaitForChild("NPC_HitReport") :: RemoteEvent

local HitReport = {}

-- Logs de rejeicao sao uteis para depurar anti-cheat, mas poluem o output
-- em producao. Ative apenas quando precisar investigar.
local DEBUG = false
local function dbg(...: any)
	if DEBUG then
		warn("[NPC HitReport]", ...)
	end
end

local function distanciaModelos(a: Model, b: Model): number
	local pa = a.PrimaryPart or a:FindFirstChild("HumanoidRootPart") :: BasePart?
	local pb = b.PrimaryPart or b:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not pa or not pb then
		return math.huge
	end
	return (pa.Position - pb.Position).Magnitude
end

-- Match exato primeiro; tolerancia minima so para imprecisao de float
-- na replicacao do atributo.
local function encontrarSwing(s: EstadoNPC, tickReportado: number): (RegistroSwing?, number?)
	local exato = s.historicoAcoes[tickReportado]
	if exato then
		return exato, tickReportado
	end
	for tick, registro in s.historicoAcoes do
		if math.abs(tick - tickReportado) <= Config.TOLERANCIA_TICK then
			return registro, tick
		end
	end
	return nil, nil
end

local function processarReporteHit(
	jogador: Player,
	npcModel: any,
	alvoModel: any,
	acaoTickReportado: any,
	parteAtingida: any,
	npcCFrame: any,
	alvoCFrame: any
)
	-- Tipos basicos (payload vem do cliente: nunca confiar).
	if typeof(npcModel) ~= "Instance" or not npcModel:IsA("Model") then
		return
	end
	if typeof(alvoModel) ~= "Instance" or not alvoModel:IsA("Model") then
		return
	end
	if typeof(acaoTickReportado) ~= "number" then
		return
	end
	if parteAtingida ~= nil and typeof(parteAtingida) ~= "string" then
		return
	end
	if npcCFrame ~= nil and typeof(npcCFrame) ~= "CFrame" then
		return
	end
	if alvoCFrame ~= nil and typeof(alvoCFrame) ~= "CFrame" then
		return
	end

	local s = Estado.Obter(npcModel)
	if not s or s.destruido then
		return
	end

	-- Cliente so pode reportar hit no proprio personagem.
	if alvoModel ~= jogador.Character then
		return
	end

	-- Swing correspondente ao tick reportado.
	local registro, tickSwing = encontrarSwing(s, acaoTickReportado)
	if not registro or not tickSwing then
		dbg("rejeitado: tick sem swing correspondente", acaoTickReportado)
		return
	end

	-- Swing interrompido por stun/parry: por-swing (antes a checagem era
	-- global e comparava com o ultimo ataque, nao com o swing reportado).
	local cs = Estado.ObterCombateServidor()
	if cs and cs.ObterMaquina then
		local ok, maquina = pcall(cs.ObterMaquina, npcModel)
		if ok and maquina and maquina.dados then
			local ultimoStun = maquina.dados.ultimoStunTimestamp or 0
			if ultimoStun > tickSwing then
				dbg("rejeitado: swing interrompido por stun/parry")
				return
			end
		end
	end

	-- Janela temporal do swing, compensando RTT do jogador.
	local agora = os.clock()
	local rttVal = jogador:GetAttribute("RTT")
	local rtt = math.clamp(if typeof(rttVal) == "number" then rttVal else 0, 0, Config.RTT_MAX)
	local limiteMinimo = registro.swingHitInicio - 0.05
	local limiteMaximo = registro.swingHitFim + Config.JANELA_HIT_EXTRA + rtt
	if agora < limiteMinimo or agora > limiteMaximo then
		dbg(string.format("rejeitado: fora da janela (agora=%.3f min=%.3f max=%.3f)", agora, limiteMinimo, limiteMaximo))
		return
	end

	-- Dedup por swing.
	if registro.jaAtingidos[alvoModel] then
		dbg("rejeitado: alvo ja atingido neste swing")
		return
	end

	-- Alvo válido.
	local hum = alvoModel:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end

	-- Distancia plausivel, compensando RTT.
	local alcance = s.alcanceArma
	local compensacao = math.clamp(rtt * Config.COMPENSACAO_DISTANCIA_POR_RTT, 0, Config.COMPENSACAO_DISTANCIA_MAX)
	local limiteDistancia = alcance + Config.TOLERANCIA_DISTANCIA + compensacao
	local d = distanciaModelos(s.modelo, alvoModel)
	if d > limiteDistancia then
		dbg(string.format("rejeitado: distancia invalida (d=%.2f limite=%.2f)", d, limiteDistancia))
		return
	end

	registro.jaAtingidos[alvoModel] = true
	s.modelo:SetAttribute("NPC_AcertouCombo", true)

	if cs and cs._ProcessarHit then
		pcall(
			cs._ProcessarHit,
			s.modelo,
			alvoModel,
			registro.tipoAtaque,
			s.dano,
			parteAtingida,
			nil,
			npcCFrame,
			alvoCFrame
		)
	end
end

-- Conecta o listener UMA unica vez (idempotente).
local conectado = false
function HitReport.Iniciar()
	if conectado then
		return
	end
	conectado = true
	NPC_HitReport.OnServerEvent:Connect(processarReporteHit)
end

return HitReport
