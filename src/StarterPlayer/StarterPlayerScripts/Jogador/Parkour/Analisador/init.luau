--[[
	Módulo: Analisador (fachada)
	Caminho: src/StarterPlayer/StarterPlayerScripts/Jogador/Parkour/Analisador
	Responsabilidade: ponto único de entrada do sistema de análise de parkour.
		Mantém a API pública original intacta e delega para os módulos-filhos.
	Uso: ModuleScript; require(caminho) e chame as funções da tabela retornada.
	Não faz: não roda sozinho; depende dos scripts que o importam.

	Arquitetura (filhos deste ModuleScript):
	  Geometria        -> geometria pura, sondagem de malha, cast data
	  Espacos          -> clearances (topo/frente/vault)
	  Suporte          -> ResolveIdleMode (apoio de pernas)
	  Escalada         -> CheckEscalar / checkEscalarAtEdge
	  DeteccaoFrontal  -> grid frontal + classificação de pulo
	  AcaoParkour      -> CheckParkour (corrida/queda -> agarrar/vault)
	  AcaoSubir        -> CheckSubir
	  AcaoDescer       -> CheckDescer
	  AcaoLateral      -> CheckLateral

	Contrato de config: os módulos de ação (AcaoParkour/Subir/Descer/Lateral) e
	Escalada.CheckEscalar resolvem `Configs.mergeConfig` internamente. Os módulos
	utilitários (Espacos, Suporte, Geometria, DeteccaoFrontal) recebem `finalConfig`
	já resolvido. Esta fachada faz o merge apenas para as APIs utilitárias que ela
	expõe diretamente (HasTopClearance, HasFrontClearance, HasVaultClearance,
	HasVaultEdgeClearance, ResolveIdleMode, TentarFallbackAgarrar).
	Funcoes principais: ClearDebug, DrawDebug, HasTopClearance, HasFrontClearance,
	ResolveIdleMode, HasVaultClearance
]]

local Configs = require(script.Parent:WaitForChild("Configuracoes"):WaitForChild("ConfigParkour"))
local Utilidades = require(script.Parent:WaitForChild("Utilidades"))
local Debug = require(script.Parent:WaitForChild("Depuracao"):WaitForChild("DepuracaoParkour"))

local Geometria = require(script:WaitForChild("Geometria"))
local Espacos = require(script:WaitForChild("Espacos"))
local Suporte = require(script:WaitForChild("Suporte"))
local Escalada = require(script:WaitForChild("Escalada"))
local AcaoParkour = require(script:WaitForChild("AcaoParkour"))
local AcaoSubir = require(script:WaitForChild("AcaoSubir"))
local AcaoDescer = require(script:WaitForChild("AcaoDescer"))
local AcaoLateral = require(script:WaitForChild("AcaoLateral"))

local Analisador = {}

-- ===== Debug =====
function Analisador.ClearDebug()
	Debug.ClearDebug()
end

function Analisador.DrawDebug(data)
	Debug.DrawDebug(data)
end

-- ===== Clearances (API utilitária; merge feito aqui) =====
function Analisador.HasTopClearance(data, config)
	return Espacos.HasTopClearance(data, Configs.mergeConfig(config))
end

function Analisador.HasFrontClearance(data, config)
	return Espacos.HasFrontClearance(data, Configs.mergeConfig(config))
end

function Analisador.HasVaultClearance(data, config)
	return Espacos.HasVaultClearance(data, Configs.mergeConfig(config))
end

function Analisador.HasVaultEdgeClearance(data, config)
	return Espacos.HasVaultEdgeClearance(data, Configs.mergeConfig(config))
end

-- ===== Apoio =====
function Analisador.ResolveIdleMode(data, config)
	return Suporte.ResolveIdleMode(data, Configs.mergeConfig(config))
end

-- ===== Ações (merge resolvido dentro de cada módulo) =====
function Analisador.CheckParkour(character, config)
	return AcaoParkour.CheckParkour(character, config)
end

function Analisador.CheckSubir(character, currentEdgePos, currentNormal, config)
	return AcaoSubir.CheckSubir(character, currentEdgePos, currentNormal, config)
end

function Analisador.CheckDescer(character, currentEdgePos, currentNormal, config)
	return AcaoDescer.CheckDescer(character, currentEdgePos, currentNormal, config)
end

function Analisador.CheckLateral(character, currentEdgePos, currentNormal, direcao, config, currentPart)
	return AcaoLateral.CheckLateral(character, currentEdgePos, currentNormal, direcao, config, currentPart)
end

function Analisador.CheckEscalar(character, currentEdgePos, currentNormal, currentPart, config)
	return Escalada.CheckEscalar(character, currentEdgePos, currentNormal, currentPart, config)
end

-- ===== Utilitários diversos =====
function Analisador.IsRunningForVault(humanoid, ClientBridgeRef)
	if ClientBridgeRef and ClientBridgeRef.LerStatusLocal then
		local estadoMov = ClientBridgeRef.LerStatusLocal("estadoMov")
		if type(estadoMov) == "string" and estadoMov == "Correndo" then
			return true
		end

		local correndoOn = ClientBridgeRef.LerStatusLocal("CorrendoOn")
		if type(correndoOn) == "boolean" then
			return correndoOn
		end
	end

	return humanoid.MoveDirection.Magnitude > 0.1 and humanoid.WalkSpeed > 18
end

function Analisador.TentarFallbackAgarrar(character, parkourResult, config)
	if not parkourResult or not parkourResult.EdgePosition or not parkourResult.Normal then
		return nil
	end

	local hrp = Utilidades.getCharacterParts(character)
	if not hrp then
		return nil
	end

	local finalConfig = Configs.mergeConfig(config)
	local fallback = table.clone(parkourResult)
	fallback.Character = character
	fallback.Acao = "Agarrar"
	fallback.Aprovado = false

	if not Geometria.isWallLikeNormal(fallback.Normal, finalConfig) then
		local lookBase = fallback.LookVector
		if not lookBase or lookBase.Magnitude < 0.001 then
			lookBase = hrp.CFrame.LookVector
		end

		local lookXZ = Vector3.new(lookBase.X, 0, lookBase.Z)
		if lookXZ.Magnitude > 0.001 then
			fallback.Normal = -lookXZ.Unit
		else
			local planarNormal = Vector3.new(fallback.Normal.X, 0, fallback.Normal.Z)
			if planarNormal.Magnitude > 0.001 then
				fallback.Normal = planarNormal.Unit
			else
				fallback.Normal = Vector3.new(0, 0, -1)
			end
		end

		Debug.Verbose("[Parkour] Fallback Agarrar normal ajustada para parede | novo:", fallback.Normal)
	end

	local distReal = (fallback.EdgePosition - hrp.Position).Magnitude
	if distReal > finalConfig.MaxGrabDistance then
		fallback.Reason = "TooFarToGrab"
		return fallback
	end

	local hasTopClearance, topBlocker, topCf, topSize = Espacos.HasTopClearance(fallback, finalConfig)
	fallback.TopClearanceCFrame = topCf
	fallback.TopClearanceSize = topSize
	if not hasTopClearance then
		fallback.Reason = "NoTopClearance"
		fallback.TopBlocker = topBlocker
		return fallback
	end

	local hasFrontClearance, frontBlocker, frontCf, frontSize = Espacos.HasFrontClearance(fallback, finalConfig)
	fallback.FrontClearanceCFrame = frontCf
	fallback.FrontClearanceSize = frontSize
	if not hasFrontClearance then
		fallback.Reason = "NoFrontClearance"
		fallback.FrontBlocker = frontBlocker
		return fallback
	end

	local idleMode, legHit, legProbeRaysDebug = Suporte.ResolveIdleMode(fallback, finalConfig)
	fallback.IdleMode = idleMode
	fallback.LegHit = legHit
	fallback.LegProbeRaysDebug = legProbeRaysDebug
	fallback.Reason = "OkFallbackNoRun"
	fallback.Aprovado = true

	return fallback
end

return Analisador
