--!strict

--[[
	Script: NucleoCombate.luau
	Caminho: src/ServerScriptService/Combate/Servidor
	Responsabilidade: Estado central de combate no servidor. Guarda as maquinas
	    de estado por entidade, replica estado e animacao para os clientes (com
	    coalescing por frame e filtro por distancia) e expoe os helpers de
	    impulso, knockback e watchdog de ataque.
	Uso: ModuleScript; require(NucleoCombate) em qualquer modulo de combate do
	    servidor. Nao precisa ser iniciado.
	Nao faz: Nao conecta RemoteEvents, nao decide regras de hit ou defesa e nao
	    processa acoes de gameplay.
	Funcoes principais: ObterMaquina, RemoverMaquina, SincronizarEstado,
	    TocarAnimacao, PararAnimacao, AplicarImpulsoAtacante, AplicarKnockback
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combate = ReplicatedStorage:WaitForChild("Combate")
local DominioCombate = Combate:WaitForChild("Dominio")

local Modulo_Configuracoes = require(Combate:WaitForChild("Configuracoes"):WaitForChild("ConfigCombate"))
local Modulo_Impulso = require(DominioCombate:WaitForChild("ImpulsoCombate"))
local Modulo_Knockback = require(DominioCombate:WaitForChild("KnockbackCombate"))
local MaquinaDeEstados =
	require(ReplicatedStorage:WaitForChild("Jogador"):WaitForChild("Estado"):WaitForChild("MaquinaEstadosJogador"))

local Remotos = ReplicatedStorage:WaitForChild("Remotos")
local SincronizarEstadoRemoto = Remotos:WaitForChild("SincronizarEstado") :: RemoteEvent
local TocarAnimacaoRemoto = Remotos:WaitForChild("TocarAnimacao") :: RemoteEvent

local DEBUG_ENABLED = false

-- Animação é puramente visual: nao vale a pena replicar para quem nao enxerga.
local RAIO_REPLICACAO_ANIMACAO = 180
local TIMEOUT_ATAQUE = 1.8
local GOLPES_TOTAIS_PADRAO = 4

local NucleoCombate = {}

NucleoCombate.MaquinaDeEstados = MaquinaDeEstados
NucleoCombate.TIMEOUT_ATAQUE = TIMEOUT_ATAQUE

function NucleoCombate.DebugPrint(...)
	if DEBUG_ENABLED then
		print(...)
	end
end
local DebugPrint = NucleoCombate.DebugPrint

local maquinas: { [Model]: any } = {}
local conexoesEntidade: { [Model]: RBXScriptConnection } = {}
local danoAplicadoEvent = Instance.new("BindableEvent")
local hitboxAtivadaEvent = Instance.new("BindableEvent")

-- =============================================================================
-- Replicacao filtrada. TocarAnimacao vai apenas para clientes proximos; o dono
-- da entidade sempre recebe, custe o que custar.
-- =============================================================================

local bufferJogadores: { Player } = {}

local function jogadoresProximos(entidade: Model): { Player }
	table.clear(bufferJogadores)
	local hrp = entidade:FindFirstChild("HumanoidRootPart") :: BasePart?
	local dono = Players:GetPlayerFromCharacter(entidade)

	for _, player in Players:GetPlayers() do
		if player == dono or not hrp then
			table.insert(bufferJogadores, player)
			continue
		end
		local char = player.Character
		local outroHrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not outroHrp then
			-- Sem personagem carregado: manda mesmo assim, o cliente ignora.
			table.insert(bufferJogadores, player)
			continue
		end
		if (outroHrp.Position - hrp.Position).Magnitude <= RAIO_REPLICACAO_ANIMACAO then
			table.insert(bufferJogadores, player)
		end
	end

	return bufferJogadores
end

-- =============================================================================
-- Sincronizacao de estado com coalescing: N chamadas no mesmo frame viram um
-- unico FireAllClients. Os BoolValues em Status continuam sendo escritos na
-- hora, porque outros scripts do servidor leem deles de forma sincrona.
-- =============================================================================

local pendentesSync: { [Model]: true } = {}
local flushAgendado = false

local function flushSync()
	flushAgendado = false
	for entidade in pendentesSync do
		pendentesSync[entidade] = nil
		local maquina = maquinas[entidade]
		if maquina and entidade.Parent then
			SincronizarEstadoRemoto:FireAllClients(entidade, maquina:ObterDados())
		end
	end
end

local function escreverStatus(entidade: Model, dados: any)
	local status = entidade:FindFirstChild("Status")
	if not status then
		return
	end

	local function atualizarValor(nome: string, valor: any)
		local obj = status:FindFirstChild(nome)
		if
			obj
			and (obj:IsA("IntValue") or obj:IsA("NumberValue") or obj:IsA("StringValue") or obj:IsA("BoolValue"))
		then
			(obj :: any).Value = valor
		end
	end

	atualizarValor("estadoAcao", dados.estadoAcao)
	atualizarValor("BloqueandoOn", dados.bloqueando)
	atualizarValor("ProntoAparar", dados.prontoParaAparar)
	atualizarValor("StunadoOn", dados.stunado)
	atualizarValor("RollOn", dados.rolando)
	atualizarValor("DashOn", dados.dashando)
end

local function ajustarVelocidadeOciosa(entidade: Model, maquina: any, dados: any)
	local humanoid = entidade:FindFirstChildOfClass("Humanoid")
	if not humanoid or dados.estadoAcao ~= "Nenhuma" then
		return
	end

	if maquina.dados.correndoIntent then
		maquina.dados.correndoIntent = nil
		maquina.dados.correndo = true
	end

	if dados.agachado then
		humanoid.WalkSpeed = Modulo_Configuracoes.ObterConfiguracao("VelocidadeAgachando") or 9
	elseif dados.bloqueando then
		humanoid.WalkSpeed = Modulo_Configuracoes.ObterConfiguracao("VelocidadeBloqueando") or 6
	end
end

-- imediato = true forca o envio no mesmo tick (use so quando a ordem importa).
function NucleoCombate.SincronizarEstado(entidade: Model, imediato: boolean?)
	local maquina = maquinas[entidade]
	if not maquina then
		return
	end

	local dados = maquina:ObterDados()
	escreverStatus(entidade, dados)
	ajustarVelocidadeOciosa(entidade, maquina, dados)

	DebugPrint(
		string.format(
			"[Estado] %s: Mov=%s, Acao=%s, Modo=%s",
			entidade.Name,
			tostring(dados.estadoMov),
			tostring(dados.estadoAcao),
			tostring(dados.modoAnimacao)
		)
	)

	if imediato then
		pendentesSync[entidade] = nil
		SincronizarEstadoRemoto:FireAllClients(entidade, dados)
		return
	end

	pendentesSync[entidade] = true
	if not flushAgendado then
		flushAgendado = true
		task.defer(flushSync)
	end
end

-- =============================================================================
-- Animacao.
-- =============================================================================

function NucleoCombate.TocarAnimacao(entidade: Model, nomeAnimacao: string, loop: boolean?, velocidade: number?)
	local maquina = maquinas[entidade]
	if not maquina then
		return
	end

	local animId = Modulo_Configuracoes.ObterAnimacao(maquina:ObterModo(), nomeAnimacao)
	if not animId then
		return
	end

	local agora = workspace:GetServerTimeNow()
	for _, player in jogadoresProximos(entidade) do
		TocarAnimacaoRemoto:FireClient(player, entidade, animId, nomeAnimacao, loop or false, velocidade or 1, agora)
	end
end

function NucleoCombate.PararAnimacao(entidade: Model)
	local agora = workspace:GetServerTimeNow()
	for _, player in jogadoresProximos(entidade) do
		TocarAnimacaoRemoto:FireClient(player, entidade, "STOP", "", false, 0, agora)
	end
end

-- Reaproveita o canal de animacao apenas para mudar a velocidade da track atual.
function NucleoCombate.AjustarVelocidadeAnimacao(entidade: Model, velocidade: number)
	local agora = workspace:GetServerTimeNow()
	for _, player in jogadoresProximos(entidade) do
		TocarAnimacaoRemoto:FireClient(player, entidade, "", "", false, velocidade, agora)
	end
end

-- =============================================================================
-- Maquinas de estado. Cada entidade registra um Destroying para nao vazar.
-- =============================================================================

function NucleoCombate.ObterMaquina(entidade: Model): any
	local existente = maquinas[entidade]
	if existente then
		return existente
	end

	local maquina = MaquinaDeEstados.Novo(entidade)
	maquinas[entidade] = maquina

	maquina:AoMudarEstadoAcao(function(novo, _anterior)
		NucleoCombate.SincronizarEstado(entidade)
		if novo == "Defendendo" then
			NucleoCombate.TocarAnimacao(entidade, "Defesa", true)
		end
	end)

	maquina:AoMudarEstadoMov(function()
		NucleoCombate.SincronizarEstado(entidade)
	end)

	maquina:AoMudarModo(function()
		NucleoCombate.SincronizarEstado(entidade)
	end)

	conexoesEntidade[entidade] = entidade.Destroying:Connect(function()
		NucleoCombate.RemoverMaquina(entidade)
	end)

	return maquina
end

function NucleoCombate.ObterMaquinaExistente(entidade: Model): any?
	return maquinas[entidade]
end

function NucleoCombate.RemoverMaquina(entidade: Model)
	local conn = conexoesEntidade[entidade]
	if conn and conn.Connected then
		conn:Disconnect()
	end
	conexoesEntidade[entidade] = nil
	pendentesSync[entidade] = nil
	maquinas[entidade] = nil
end

-- =============================================================================
-- Combo / tipo de ataque. O total de golpes vem da configuracao do modo, nao
-- mais de um 4 cravado no codigo.
-- =============================================================================

function NucleoCombate.GolpesTotais(modo: string): number
	local cfg = Modulo_Configuracoes.ObterConfiguracaoCombo(modo)
	local total = cfg and (cfg :: any).golpesTotais
	if typeof(total) == "number" and total >= 2 then
		return total
	end
	return GOLPES_TOTAIS_PADRAO
end

function NucleoCombate.DeterminarTipoAtaque(modo: string, indice: number): string
	if indice >= NucleoCombate.GolpesTotais(modo) then
		return "AtaqueFinal"
	end
	return "Ataque"
end

function NucleoCombate.EhGolpeFinal(modo: string, indice: number): boolean
	return indice >= NucleoCombate.GolpesTotais(modo)
end

-- Watchdog unico por maquina: substitui os varios task.delay(1.8) espalhados.
function NucleoCombate.AgendarTimeoutAtaque(entidade: Model, maquina: any, duracao: number?)
	local token = (maquina.dados.watchdogToken or 0) + 1
	maquina.dados.watchdogToken = token

	task.delay(duracao or TIMEOUT_ATAQUE, function()
		if maquina.dados.watchdogToken ~= token then
			return
		end
		if not entidade.Parent then
			return
		end
		if maquina:ObterEstadoAcao() == "Atacando" then
			maquina:CompletarAcao()
			NucleoCombate.SincronizarEstado(entidade)
			DebugPrint(string.format("[Combate] %s: Timeout de ataque (watchdog)", entidade.Name))
		end
	end)
end

function NucleoCombate.CancelarTimeoutAtaque(maquina: any)
	maquina.dados.watchdogToken = (maquina.dados.watchdogToken or 0) + 1
end

-- =============================================================================
-- Fisica de combate.
-- =============================================================================

function NucleoCombate.AplicarImpulsoAtacante(entidade: Model, tipoAtaque: string)
	local maquina = maquinas[entidade]
	if not maquina then
		return
	end
	-- NPCs nao recebem impulso de ataque: quem move o NPC e o controlador.
	if not Players:GetPlayerFromCharacter(entidade) then
		return
	end

	local resultado = Modulo_Impulso.AplicarImpulso(entidade, maquina:ObterModo(), tipoAtaque)
	if not resultado.sucesso then
		DebugPrint("[Combate] Falha ao aplicar impulso: " .. tostring(resultado.erro))
	end
end

function NucleoCombate.AplicarKnockback(alvo: Model, atacante: Model, tipoAtaque: string)
	local maquina = maquinas[atacante]
	if not maquina then
		return
	end

	local resultado = Modulo_Knockback.AplicarKnockback(atacante, alvo, maquina:ObterModo(), tipoAtaque)
	if resultado.sucesso then
		DebugPrint(
			string.format("[Combate] Knockback via %s: %.1f", resultado.metodo or "?", resultado.magnitudeAplicada or 0)
		)
	elseif resultado.erro and not resultado.erro:match("não permite") then
		DebugPrint("[Combate] Falha ao aplicar knockback: " .. tostring(resultado.erro))
	end
end

-- =============================================================================
-- Eventos.
-- =============================================================================

function NucleoCombate.AoDanoAplicado(callback: (Model, Model, string, number) -> ()): RBXScriptConnection
	return danoAplicadoEvent.Event:Connect(callback)
end

function NucleoCombate.AoHitboxAtivada(callback: (Model, any) -> ()): RBXScriptConnection
	return hitboxAtivadaEvent.Event:Connect(callback)
end

function NucleoCombate.NotificarDano(atacante: Model, alvo: Model, tipoAtaque: string, dano: number)
	danoAplicadoEvent:Fire(atacante, alvo, tipoAtaque, dano)
end

function NucleoCombate.NotificarHitbox(entidade: Model, dados: any)
	hitboxAtivadaEvent:Fire(entidade, dados)
end

-- RTT ja saneado pelo PingServer; aqui so limitamos o uso em compensacao.
function NucleoCombate.ObterRTT(entidade: Model, maximo: number?): number
	local player = Players:GetPlayerFromCharacter(entidade)
	if not player then
		return 0
	end
	local valor = player:GetAttribute("RTT")
	if typeof(valor) ~= "number" then
		return 0
	end
	return math.clamp(valor, 0, maximo or 0.25)
end

return NucleoCombate
