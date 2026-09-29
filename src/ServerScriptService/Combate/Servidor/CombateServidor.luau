--!strict

--[[
	Script: CombateServidor.luau
	Caminho: src/ServerScriptService/Combate/Servidor
	Responsabilidade: Fachada do combate no servidor. Conecta os RemoteEvents,
	    roteia acoes com rate limit por categoria, cuida do ciclo de vida dos
	    personagens e reexporta a API publica usada pelo resto do jogo.
	Uso: ModuleScript; use require(caminho) e chame as funcoes retornadas.
	Nao faz: Nao implementa regras de combate; delega para NucleoCombate,
	    AcoesCombate e ProcessadorHit.
	Funcoes principais: ObterMaquina, RemoverMaquina, ProcessarAcao,
	    _ProcessarHit, _SincronizarEstado, _TocarAnimacao
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RegistroNPC = require(ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC"):WaitForChild("RegistroNPC"))

local Nucleo = require(script.Parent:WaitForChild("NucleoCombate"))
local Acoes = require(script.Parent:WaitForChild("AcoesCombate"))
local ProcessadorHit = require(script.Parent:WaitForChild("ProcessadorHit"))
local RateLimit = require(script.Parent:WaitForChild("RateLimitAcoes"))
local Historico = require(script.Parent:WaitForChild("HistoricoPosicoes"))
local Ragdoll = require(script.Parent:WaitForChild("Ragdoll"))

local DebugPrint = Nucleo.DebugPrint

local Remotos = ReplicatedStorage:WaitForChild("Remotos")
local TentarAcao = Remotos:WaitForChild("TentarAcao") :: RemoteEvent
local MudarShiftLock = Remotos:WaitForChild("MudarShiftLock") :: RemoteEvent
local EquipAnimacaoTerminou = Remotos:WaitForChild("EquipAnimacaoTerminou") :: RemoteEvent
local AcaoAnimacaoTerminou = Remotos:WaitForChild("AcaoAnimacaoTerminou") :: RemoteEvent

local ControladorCombate = {}

-- =============================================================================
-- Roteador de acoes.
-- =============================================================================

local MapaAcoes: { [string]: (Model, any) -> ...any } = {
	AtacarEmPe = Acoes.ProcessarAtacarEmPe,
	AtacarAgachado = Acoes.ProcessarAtacarAgachado,
	Bloquear = function(entidade, dados)
		local ehTabela = typeof(dados) == "table"
		local shiftLock = if ehTabela and typeof(dados.shiftLock) == "boolean" then dados.shiftLock else nil
		local timestamp = if ehTabela and typeof(dados.timestamp) == "number" then dados.timestamp else nil
		return Acoes.ProcessarBloquear(entidade, shiftLock, timestamp)
	end,
	PararBloqueio = Acoes.ProcessarPararBloqueio,
	QuebrarDefesa = Acoes.ProcessarQuebrarDefesa,
	Agachar = Acoes.ProcessarAgachar,
	Levantar = Acoes.ProcessarLevantar,
	Pular = Acoes.ProcessarPular,
	Correr = Acoes.ProcessarCorrer,
	PararCorrer = Acoes.ProcessarPararCorrer,
	Aterrissar = Acoes.ProcessarAterrissar,
	SincronizarMovimento = Acoes.ProcessarSincronizarMovimento,

	Roll = Acoes.ProcessarRoll,
	RollTerminou = Acoes.ProcessarRollTerminou,
	RollEarlyCancel = Acoes.ProcessarRollEarlyCancel,
	Dash = Acoes.ProcessarDash,
	DashTerminou = Acoes.ProcessarDashTerminou,
	DashEarlyCancel = Acoes.ProcessarDashEarlyCancel,

	Equipar = Acoes.ProcessarEquipar,
	Desequipar = Acoes.ProcessarDesequipar,

	ComboHitbox = Acoes.ProcessarComboHitbox,
	ComboContinuado = Acoes.ProcessarComboContinuado,
	ComboTerminou = Acoes.ProcessarComboTerminou,
	ComboEarlyCancel = Acoes.ProcessarComboEarlyCancel,

	HitboxAcerto = ProcessadorHit.ProcessarHitboxAcerto,
	Fintar = Acoes.ProcessarFintar,
	AjustarVelocidadeAnimacao = Acoes.ProcessarAjustarVelocidadeAnimacao,
}

function ControladorCombate.ProcessarAcao(entidade: Model, acao: string, dados: any?): (boolean, string?)
	local processador = MapaAcoes[acao]
	if not processador then
		warn("[ControladorCombate] Acao desconhecida: " .. tostring(acao))
		return false, "AcaoDesconhecida"
	end
	return processador(entidade, dados)
end

-- =============================================================================
-- API publica (nomes preservados para compatibilidade).
-- =============================================================================

ControladorCombate.ObterMaquina = Nucleo.ObterMaquina
ControladorCombate.ObterMaquinaExistente = Nucleo.ObterMaquinaExistente
ControladorCombate.RemoverMaquina = Nucleo.RemoverMaquina
ControladorCombate.AoDanoAplicado = Nucleo.AoDanoAplicado
ControladorCombate.AoHitboxAtivada = Nucleo.AoHitboxAtivada
ControladorCombate._SincronizarEstado = Nucleo.SincronizarEstado
ControladorCombate._TocarAnimacao = Nucleo.TocarAnimacao
ControladorCombate._PararAnimacao = Nucleo.PararAnimacao
ControladorCombate._AplicarImpulsoAtacante = Nucleo.AplicarImpulsoAtacante
ControladorCombate._AplicarKnockback = Nucleo.AplicarKnockback
ControladorCombate._ProcessarHit = ProcessadorHit.ProcessarHit
ControladorCombate.ProcessarShiftLock = Acoes.ProcessarShiftLock
ControladorCombate.ProcessarHitboxAcerto = ProcessadorHit.ProcessarHitboxAcerto

-- Acoes de combate e locomocao (usadas por NPC e outros subsistemas)
ControladorCombate.ProcessarEquipar = Acoes.ProcessarEquipar
ControladorCombate.ProcessarDesequipar = Acoes.ProcessarDesequipar
ControladorCombate.ProcessarAnimacaoEquipTerminou = Acoes.ProcessarAnimacaoEquipTerminou
ControladorCombate.ProcessarAtacarEmPe = Acoes.ProcessarAtacarEmPe
ControladorCombate.ProcessarAtacarAgachado = Acoes.ProcessarAtacarAgachado
ControladorCombate.ProcessarComboHitbox = Acoes.ProcessarComboHitbox
ControladorCombate.ProcessarComboContinuado = Acoes.ProcessarComboContinuado
ControladorCombate.ProcessarComboTerminou = Acoes.ProcessarComboTerminou
ControladorCombate.ProcessarComboEarlyCancel = Acoes.ProcessarComboEarlyCancel
ControladorCombate.ProcessarBloquear = Acoes.ProcessarBloquear
ControladorCombate.ProcessarPararBloqueio = Acoes.ProcessarPararBloqueio
ControladorCombate.ProcessarQuebrarDefesa = Acoes.ProcessarQuebrarDefesa
ControladorCombate.ProcessarFintar = Acoes.ProcessarFintar
ControladorCombate.ProcessarAjustarVelocidadeAnimacao = Acoes.ProcessarAjustarVelocidadeAnimacao
ControladorCombate.ProcessarAcaoAnimacaoTerminou = Acoes.ProcessarAcaoAnimacaoTerminou

-- =============================================================================
-- RemoteEvents.
-- =============================================================================

TentarAcao.OnServerEvent:Connect(function(player, acao, dados)
	if typeof(acao) ~= "string" then
		return
	end
	-- Rate limit por categoria: sincronizacao nunca engole um ataque.
	if not RateLimit.Permitir(player, acao) then
		return
	end
	local character = player.Character
	if not character then
		return
	end
	ControladorCombate.ProcessarAcao(character, acao, dados)
end)

MudarShiftLock.OnServerEvent:Connect(function(player, ativo)
	local character = player.Character
	if character and typeof(ativo) == "boolean" then
		Acoes.ProcessarShiftLock(character, ativo)
	end
end)

EquipAnimacaoTerminou.OnServerEvent:Connect(function(player, npcModel)
	-- Com npcModel, e a View do NPC avisando; sem ele, e o proprio personagem.
	local entidade: Model? = player.Character
	if typeof(npcModel) == "Instance" and npcModel:IsA("Model") and npcModel ~= player.Character then
		entidade = npcModel
	end
	if entidade then
		Acoes.ProcessarAnimacaoEquipTerminou(entidade)
	end
end)

AcaoAnimacaoTerminou.OnServerEvent:Connect(function(player, nomeAcao)
	local character = player.Character
	if character and typeof(nomeAcao) == "string" then
		Acoes.ProcessarAcaoAnimacaoTerminou(character, nomeAcao)
	end
end)

-- =============================================================================
-- Ciclo de vida.
-- =============================================================================

local function configurarCharacter(player: Player, character: Model)
	if not character:WaitForChild("Status", 5) then
		warn("[ControladorCombate] Status nao encontrado para " .. player.Name)
	end

	Nucleo.ObterMaquina(character)
	task.defer(function()
		if character.Parent then
			Nucleo.SincronizarEstado(character, true)
		end
	end)

	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5) :: Humanoid?
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end

	humanoid.BreakJointsOnDeath = false
	humanoid.Died:Connect(function()
		local maquina = Nucleo.ObterMaquinaExistente(character)
		if maquina then
			maquina:AplicarMorte()
		end
		Ragdoll.Ativar(character)
	end)
end

local function configurarPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		configurarCharacter(player, character)
	end)
	player.CharacterRemoving:Connect(function(character)
		Nucleo.RemoverMaquina(character)
	end)
	if player.Character then
		configurarCharacter(player, player.Character)
	end
end

Players.PlayerAdded:Connect(configurarPlayer)
for _, player in Players:GetPlayers() do
	configurarPlayer(player)
end

RegistroNPC.Iniciar()
Historico.Iniciar()

DebugPrint("[ControladorCombate] Inicializado no servidor")

return ControladorCombate
