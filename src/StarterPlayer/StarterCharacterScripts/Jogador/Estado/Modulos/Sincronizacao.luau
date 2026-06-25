--[[
    Script: Sincronizacao.luau
    Caminho: src/StarterPlayer/StarterCharacterScripts/Jogador/Estado/Modulos
    Responsabilidade: Predicao local de animacoes, sincronizacao de estado com o servidor
                      e processamento de animacoes remotas.
    Uso: ModuleScript; inicializado pelo ControladorEstadoPersonagem via Inicializar(ctx).
    Nao faz: Nao reproduz animacoes diretamente; delega ao modulo Animacao.
    Funcoes principais: PredictAnimation, PredictStopAnimation, ProcessarSincronizacao,
                        ProcessarTocarAnimacao, AplicarKnockbackRecebido
]]

local Sincronizacao = {}

local ctx
local Animacao -- referencia cruzada
local Movimento -- referencia cruzada

-- Estado de predição
local predicaoAtiva = nil

-- ═══════════════════════════════════════════════════════════════════
-- Predição
-- ═══════════════════════════════════════════════════════════════════

function Sincronizacao.PredictAnimation(nomeAnimacao: string, loop: boolean, velocidade: number)
	local acao = ctx.EstadoAtual.estadoAcao
	if acao == "Aparando" or acao == "Aparado" or acao == "Stunado" or acao == "DefesaQuebrada" or acao == "Morto" then
		ctx.DebugPrint("[Predict] Blocked prediction: lock state active: " .. acao)
		return
	end

	local animId = ctx.Modulo_Configuracoes.ObterIdAnimacao(ctx.EstadoAtual.modoAnimacao, nomeAnimacao)
	if not animId then
		animId = ctx.Modulo_Configuracoes.ObterIdAnimacao("Base", nomeAnimacao)
	end
	if not animId then
		return
	end

	predicaoAtiva = {
		animId = animId,
		nomeAnimacao = nomeAnimacao,
		timestamp = os.clock(),
	}

	ctx.DebugPrint("[Predict] Playing predicted animation locally:", nomeAnimacao, animId)

	-- Resetar flags de esquiva caso estejamos prevendo outra ação (ex: ataque, defesa)
	if not nomeAnimacao:match("^Roll") then
		ctx.MovementFlags.isRolling = false
	end
	if not nomeAnimacao:match("^Dash") then
		ctx.MovementFlags.isDashing = false
	end

	-- Atualizar estados locais para minimizar delay
	if nomeAnimacao == "Ataque" or nomeAnimacao:match("^Ataque") then
		ctx.EstadoAtual.estadoAcao = "Atacando"
	elseif nomeAnimacao == "Defesa" then
		ctx.EstadoAtual.estadoAcao = "Defendendo"
		ctx.EstadoAtual.bloqueando = true
	elseif nomeAnimacao == "Equipar" then
		ctx.EstadoAtual.estadoAcao = "Equipando"
	elseif nomeAnimacao == "Desequipar" then
		ctx.EstadoAtual.estadoAcao = "Desequipando"
	elseif nomeAnimacao:match("^Roll") then
		ctx.EstadoAtual.estadoAcao = "Rolando"
		ctx.MovementFlags.isRolling = true
	elseif nomeAnimacao:match("^Dash") then
		ctx.EstadoAtual.estadoAcao = "Dashando"
		ctx.MovementFlags.isDashing = true
	end

	Animacao.TocarAnimacaoAcao(animId, loop, velocidade, nomeAnimacao)

	Movimento.AtualizarVelocidadeLocal()
	Movimento.SincronizarStatusLocal()
end

function Sincronizacao.PredictStopAnimation()
	predicaoAtiva = {
		animId = "STOP",
		nomeAnimacao = "STOP",
		timestamp = os.clock(),
	}
	ctx.DebugPrint("[Predict] Predict stop animation locally")

	if ctx.EstadoAtual.estadoAcao == "Defendendo" then
		ctx.EstadoAtual.estadoAcao = "Nenhuma"
		ctx.EstadoAtual.bloqueando = false
		Animacao.PararAnimacaoAcao()
	end

	Movimento.AtualizarVelocidadeLocal()
	Movimento.SincronizarStatusLocal()
end

function Sincronizacao.PredictCancel()
	predicaoAtiva = {
		animId = "STOP",
		nomeAnimacao = "STOP",
		timestamp = os.clock(),
	}
	ctx.DebugPrint("[Predict] Predict cancel/feint locally")
end

-- ═══════════════════════════════════════════════════════════════════
-- Sincronização de estado
-- ═══════════════════════════════════════════════════════════════════

function Sincronizacao.ProcessarSincronizacao(entidade: Model, dados)
	if entidade ~= ctx.Character then
		return
	end

	local acaoAnterior = ctx.EstadoAtual.estadoAcao
	local modoAnterior = ctx.EstadoAtual.modoAnimacao
	local estadoMovAnterior = ctx.EstadoAtual.estadoMov
	local bloqueandoAnterior = ctx.EstadoAtual.bloqueando
	local agachadoAnterior = ctx.EstadoAtual.agachado
	local correndoAnterior = ctx.EstadoAtual.correndo

	local rtt = ctx.Player:GetAttribute("RTT") or 0.0
	local threshold = math.clamp(rtt + 0.15, 0.20, 1.0)
	local ignorarReversao = false
	if predicaoAtiva and (os.clock() - predicaoAtiva.timestamp < threshold) then
		if predicaoAtiva.animId == "STOP" then
			-- Previsto parada/cancelamento: queremos ser "Nenhuma".
			-- Ignora se o servidor nos mandar estados ativos antigos.
			ignorarReversao = (dados.estadoAcao ~= "Nenhuma" and dados.estadoAcao ~= "Nenhum")
		else
			-- Previsto ação ativa: queremos manter o estado previsto.
			-- Ignora se o servidor ainda estiver em "Nenhuma".
			ignorarReversao = (dados.estadoAcao == "Nenhuma" or dados.estadoAcao == "Nenhum")
		end
	end

	ctx.EstadoAtual.estadoMov = dados.estadoMov
	if not ignorarReversao then
		ctx.EstadoAtual.estadoAcao = dados.estadoAcao
		ctx.EstadoAtual.bloqueando = dados.bloqueando
	else
		ctx.DebugPrint("[Predict] Ignored server state reset to Nenhuma (pending predicted action)")
	end
	ctx.EstadoAtual.modoAnimacao = dados.modoAnimacao
	ctx.EstadoAtual.agachado = dados.agachado
	ctx.EstadoAtual.correndo = dados.correndo

	if ctx.ParkourState.ativo then
		ctx.EstadoAtual.estadoAcao = "Parkour"
		ctx.EstadoAtual.estadoMov = "Parkour"
		Movimento.SincronizarStatusLocal()
		return
	end

	local movimentoMudou = estadoMovAnterior ~= ctx.EstadoAtual.estadoMov
		or bloqueandoAnterior ~= ctx.EstadoAtual.bloqueando
		or agachadoAnterior ~= ctx.EstadoAtual.agachado
		or correndoAnterior ~= ctx.EstadoAtual.correndo
		or acaoAnterior ~= ctx.EstadoAtual.estadoAcao

	if movimentoMudou then
		Movimento.AtualizarVelocidadeLocal()
	end

	Animacao.AtualizarBaseIdle()

	local modoMudou = modoAnterior ~= ctx.EstadoAtual.modoAnimacao
	if modoMudou then
		local animMov = Animacao.ObterAnimacaoAtualMov()
		if animMov then
			-- Forçar a próxima animação de movimento a ser recriada se não estiver pulando ou caindo
			if not ctx.MovementFlags.isJumping and not ctx.MovementFlags.isFalling then
				Animacao.PararAnimacaoMov(true)
			end
		end
	end

	if ctx.EstadoAtual.estadoAcao == "Atacando" or ctx.EstadoAtual.estadoAcao == "Defendendo" then
		ctx.MovementFlags.isRunning = false

		Movimento.AtualizarVelocidadeLocal()

		Animacao.AtualizarAnimacaoMovimento()
	end

	if acaoAnterior ~= "Nenhuma" and ctx.EstadoAtual.estadoAcao == "Nenhuma" then
		local foiEquipDesequip = (acaoAnterior == "Equipando" or acaoAnterior == "Desequipando")

		local animAcao = Animacao.ObterAnimacaoAtualAcao()
		if foiEquipDesequip and animAcao and animAcao.IsPlaying then
			animAcao.Stopped:Once(function()
				Animacao.AtualizarAnimacaoMovimento()
			end)
		else
			Animacao.PararAnimacaoAcao()
		end
	end

	if acaoAnterior == "Atacando" and ctx.EstadoAtual.estadoAcao == "Nenhuma" then
		if ctx.IsShiftHeld() then
			ctx.MovementFlags.isRunning = true

			ctx.EstadoAtual.estadoMov = "Correndo"
			ctx.EstadoAtual.correndo = true
		end

		Movimento.AtualizarVelocidadeLocal()
		Animacao.AtualizarAnimacaoMovimento()
	end

	if ctx.MovementFlags.isRunning and (ctx.MovementFlags.isJumping or ctx.MovementFlags.isFalling) then
		Animacao.DefinirVelocidadeMovimento(ctx.TIMINGS.RunInAirSpeed)
		return
	end

	Animacao.AtualizarAnimacaoMovimento()

	if acaoAnterior == "Defendendo" and ctx.EstadoAtual.estadoAcao == "Nenhuma" then
		if ctx.IsShiftHeld() then
			ctx.MovementFlags.isRunning = true

			ctx.EstadoAtual.estadoMov = "Correndo"
			ctx.EstadoAtual.correndo = true
		end

		Movimento.AtualizarVelocidadeLocal()
		Animacao.AtualizarAnimacaoMovimento()
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- Processar animação remota
-- ═══════════════════════════════════════════════════════════════════

function Sincronizacao.ProcessarTocarAnimacao(
	entidade: Model,
	animId: string,
	nomeAnimacao: string,
	loop: boolean,
	velocidade: number,
	_serverTimestamp: number?
)
	if entidade ~= ctx.Character then
		return
	end

	if predicaoAtiva and predicaoAtiva.animId == animId then
		local diff = os.clock() - predicaoAtiva.timestamp
		if diff < 1.2 then
			ctx.DebugPrint(string.format("[Predict] Ignored server replication for predicted animation %s (diff: %.3fs)", nomeAnimacao, diff))
			predicaoAtiva = nil
			return
		end
	end

	if animId == "STOP" then
		if predicaoAtiva then
			local diff = os.clock() - predicaoAtiva.timestamp
			if predicaoAtiva.animId == "STOP" then
				if diff < 1.2 then
					ctx.DebugPrint(string.format("[Predict] Ignored server replication for predicted STOP (diff: %.3fs)", diff))
					return
				end
			elseif predicaoAtiva.animId ~= "STOP" then
				-- Se prevemos uma animação real (tipo Ataque ou Defesa) muito recentemente,
				-- ignoramos o STOP antigo que veio do servidor (ex: término do Dash anterior)
				if diff < 1.0 then
					ctx.DebugPrint(string.format("[Predict] Ignored server STOP because a new prediction %s is active (diff: %.3fs)", predicaoAtiva.nomeAnimacao, diff))
					return
				end
			end
		end
		Animacao.PararAnimacaoAcao()
		return
	end

	Animacao.TocarAnimacaoAcao(animId, loop, velocidade, nomeAnimacao)
end

-- ═══════════════════════════════════════════════════════════════════
-- Knockback recebido
-- ═══════════════════════════════════════════════════════════════════

function Sincronizacao.AplicarKnockbackRecebido(direcao: Vector3, magnitude: number)
	local hrp = ctx.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	direcao = Vector3.new(direcao.X, 0, direcao.Z).Unit

	local velocidadeAtual = hrp.AssemblyLinearVelocity
	hrp.AssemblyLinearVelocity = Vector3.new(direcao.X * magnitude, velocidadeAtual.Y, direcao.Z * magnitude)

	ctx.DebugPrint(string.format("[Sincronizacao] Knockback recebido: magnitude=%.1f", magnitude))
end

-- ═══════════════════════════════════════════════════════════════════
-- Inicialização
-- ═══════════════════════════════════════════════════════════════════

function Sincronizacao.Inicializar(contexto)
	ctx = contexto
	Animacao = ctx.Modulos.Animacao
	Movimento = ctx.Modulos.Movimento

	-- Registrar funções no ClientBridge
	ctx.ClientBridge.PredictAnimation = Sincronizacao.PredictAnimation
	ctx.ClientBridge.PredictStopAnimation = Sincronizacao.PredictStopAnimation
	ctx.ClientBridge.PredictCancel = Sincronizacao.PredictCancel

	-- Conectar eventos de rede
	ctx.ConectarGlobal(ctx.SincronizarEstado.OnClientEvent, Sincronizacao.ProcessarSincronizacao)
	ctx.ConectarGlobal(ctx.TocarAnimacao.OnClientEvent, Sincronizacao.ProcessarTocarAnimacao)

	-- Conectar knockback
	local Remotos = game:GetService("ReplicatedStorage"):WaitForChild("Remotos")
	local AplicarKnockbackRemote = Remotos:FindFirstChild("AplicarKnockback")
	if AplicarKnockbackRemote then
		ctx.ConectarGlobal(AplicarKnockbackRemote.OnClientEvent, function(direcao, magnitude)
			Sincronizacao.AplicarKnockbackRecebido(direcao, magnitude)
		end)
	end
end

return Sincronizacao
