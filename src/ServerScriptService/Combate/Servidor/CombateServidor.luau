--!strict

--[[
    Script: CombateServidor.luau
    Caminho: src/ServerScriptService/Combate/Servidor
    Responsabilidade: Autoriza, valida e aplica acoes de combate recebidas dos clientes.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao roda sozinho nem cria fluxo de jogo por conta propria; depende dos scripts que importam este modulo.
    Funcoes principais: ObterMaquina, RemoverMaquina, _SincronizarEstado, _TocarAnimacao, _AplicarImpulsoAtacante, _AplicarKnockback
]]
local DEBUG_ENABLED = false

local function DebugPrint(...)
	if DEBUG_ENABLED then
		print(...)
	end
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Combate = ReplicatedStorage:WaitForChild("Combate")
local DominioCombate = Combate:WaitForChild("Dominio")

local Modulo_Configuracoes = require(Combate:WaitForChild("Configuracoes"):WaitForChild("ConfigCombate"))
local Modulo_Dano = require(DominioCombate:WaitForChild("DanoCombate"))
local Modulo_Impulso = require(DominioCombate:WaitForChild("ImpulsoCombate"))
local Modulo_Knockback = require(DominioCombate:WaitForChild("KnockbackCombate"))
local MaquinaDeEstados =
	require(ReplicatedStorage:WaitForChild("Jogador"):WaitForChild("Estado"):WaitForChild("MaquinaEstadosJogador"))

local function isParryDebugActive(): boolean
	local attr = ReplicatedStorage:GetAttribute("ParryDebugBlock")
	if attr ~= nil then
		return attr == true
	end
	local ok, HitboxConfig = pcall(
		require,
		ReplicatedStorage:WaitForChild("Combate")
			:WaitForChild("Hitbox")
			:WaitForChild("Shapecast")
			:WaitForChild("HitboxConfig") :: ModuleScript
	)
	return ok and HitboxConfig.ParryDebugBlock == true
end

local function DestruirDefesaBlock(entidade: Model)
	local existente = entidade:FindFirstChild("DefesaBlock")
	if existente then
		existente:Destroy()
	end
end

local function CriarDefesaBlock(entidade: Model, debugAtivo: boolean, prontoParaAparar: boolean)
	local hrp = entidade:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end

	local existente = entidade:FindFirstChild("DefesaBlock")
	if existente then
		existente:Destroy()
	end

	local block = Instance.new("Part")
	block.Name = "DefesaBlock"
	block.Size = Vector3.new(3.7, 5, 1.5)
	block.CanCollide = false
	block.CanTouch = true
	block.CanQuery = true
	block.Massless = true
	block.Transparency = if debugAtivo then 0.5 else 1.0
	block.Color = if prontoParaAparar then Color3.fromRGB(255, 255, 0) else Color3.fromRGB(0, 255, 0) -- Yellow vs Green
	block.Material = Enum.Material.ForceField
	block.CastShadow = false

	-- Se for NPC (não tem player correspondente), solda ao Torso para acompanhar a orientação visual do cliente.
	-- Se for player, solda ao HumanoidRootPart (já acompanha a rotação do personagem pelo controle).
	local player = Players:GetPlayerFromCharacter(entidade)
	local torso = entidade:FindFirstChild("Torso") :: BasePart?
	local part0 = (player and hrp) or torso or hrp

	-- Define o CFrame inicial alinhado com o part0 (frente do personagem) antes de soldar
	block.CFrame = part0.CFrame * CFrame.new(0, 0, -1.5)

	local weld = Instance.new("ManualWeld")
	weld.Name = "DefesaBlockWeld"
	weld.Part0 = part0
	weld.Part1 = block
	weld.C0 = CFrame.new(0, 0, -1.5)
	weld.Parent = block

	block.Parent = entidade
end

local function AtualizarDefesaBlock(entidade: Model, debugAtivo: boolean, prontoParaAparar: boolean)
	local block = entidade:FindFirstChild("DefesaBlock") :: BasePart?
	if block then
		block.Transparency = if debugAtivo then 0.5 else 1.0
		block.Color = if prontoParaAparar then Color3.fromRGB(255, 255, 0) else Color3.fromRGB(0, 255, 0)
	end
end

local ControladorCombate = {}

local maquinasDeEstado: { [Model]: any } = {}
local danoAplicadoEvent = Instance.new("BindableEvent")

local Remotos = ReplicatedStorage:WaitForChild("Remotos")
local TentarAcao = Remotos:WaitForChild("TentarAcao")
local MudarShiftLock = Remotos:WaitForChild("MudarShiftLock")
local SincronizarEstado = Remotos:WaitForChild("SincronizarEstado")
local TocarAnimacao = Remotos:WaitForChild("TocarAnimacao")
local EquipAnimacaoTerminou = Remotos:WaitForChild("EquipAnimacaoTerminou")
local DanoDebugVisual = Remotos:WaitForChild("DanoDebugVisual") :: RemoteEvent

local function DeterminarTipoAtaque(indice: number): string
	if indice >= 4 then
		return "AtaqueLeveFinal"
	end
	return "AtaqueLeve"
end

local function EhGolpeFinal(indice: number): boolean
	return indice >= 4
end

local MAO_PARA_SLOT = {
	Right = "RightArm",
	Left = "LeftArm",
}

local function ObterToolPorMao(character: Model, mao: string): Tool?
	local slotName = MAO_PARA_SLOT[mao]
	if not slotName then
		return nil
	end

	local equipamento = character:FindFirstChild("Equipamento")
	if not equipamento then
		return nil
	end

	local bracos = equipamento:FindFirstChild("Bracos")
	if not bracos then
		return nil
	end

	local slotOV = bracos:FindFirstChild(slotName) :: ObjectValue?
	if slotOV and slotOV.Value and slotOV.Value:IsA("Tool") then
		return slotOV.Value :: Tool
	end

	local toolNaMao = character:FindFirstChildOfClass("Tool")
	if toolNaMao then
		return toolNaMao
	end

	return nil
end

function ControladorCombate.ObterMaquina(entidade: Model): any
	if not maquinasDeEstado[entidade] then
		maquinasDeEstado[entidade] = MaquinaDeEstados.Novo(entidade)

		maquinasDeEstado[entidade]:AoMudarEstadoAcao(function(novo, _anterior)
			ControladorCombate._SincronizarEstado(entidade)
			if novo == "Defendendo" then
				ControladorCombate._TocarAnimacao(entidade, "Defesa", true)
			elseif novo ~= "Aparando" then
				DestruirDefesaBlock(entidade)
			end
		end)

		maquinasDeEstado[entidade]:AoMudarEstadoMov(function(_novo, _anterior)
			ControladorCombate._SincronizarEstado(entidade)
		end)

		maquinasDeEstado[entidade]:AoMudarModo(function(_novo, _anterior)
			ControladorCombate._SincronizarEstado(entidade)
		end)
	end

	return maquinasDeEstado[entidade]
end

function ControladorCombate.RemoverMaquina(entidade: Model)
	maquinasDeEstado[entidade] = nil
end

function ControladorCombate.AoDanoAplicado(callback: (Model, Model, string, number) -> ()): RBXScriptConnection
	return danoAplicadoEvent.Event:Connect(callback)
end

function ControladorCombate._SincronizarEstado(entidade: Model)
	local maquina = maquinasDeEstado[entidade]
	if not maquina then
		return
	end

	local dados = maquina:ObterDados()

	local status = entidade:FindFirstChild("Status")
	if status then
		local function atualizarValor(nome, valor)
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

	DebugPrint(
		string.format(
			"[Estado] %s: Mov=%s, Acao=%s, Modo=%s",
			entidade.Name,
			dados.estadoMov,
			dados.estadoAcao,
			dados.modoAnimacao
		)
	)

	local humanoid = entidade:FindFirstChildOfClass("Humanoid")
	if humanoid then
		if dados.estadoAcao == "Nenhuma" then
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
	end

	SincronizarEstado:FireAllClients(entidade, dados)
end

function ControladorCombate._TocarAnimacao(entidade: Model, nomeAnimacao: string, loop: boolean?, velocidade: number?)
	local maquina = maquinasDeEstado[entidade]
	if not maquina then
		return
	end

	local modo = maquina:ObterModo()
	local animId = Modulo_Configuracoes.ObterAnimacao(modo, nomeAnimacao)

	if animId then
		TocarAnimacao:FireAllClients(entidade, animId, nomeAnimacao, loop or false, velocidade or 1)
	end
end

function ControladorCombate._PararAnimacao(entidade: Model)
	TocarAnimacao:FireAllClients(entidade, "STOP", "", false, 0)
end

function ControladorCombate._AplicarImpulsoAtacante(entidade: Model, tipoAtaque: string)
	local maquina = maquinasDeEstado[entidade]
	if not maquina then
		return
	end

	-- Não aplicar impulso de ataque em NPCs (entidades sem player associado)
	if not Players:GetPlayerFromCharacter(entidade) then
		return
	end

	local modo = maquina:ObterModo()
	local resultado = Modulo_Impulso.AplicarImpulso(entidade, modo, tipoAtaque)

	if not resultado.sucesso then
		DebugPrint("[Combate] Falha ao aplicar impulso: " .. tostring(resultado.erro))
	end
end

function ControladorCombate._AplicarKnockback(alvo: Model, atacante: Model, tipoAtaque: string)
	local maquina = maquinasDeEstado[atacante]
	if not maquina then
		return
	end

	local modo = maquina:ObterModo()

	local resultado = Modulo_Knockback.AplicarKnockback(atacante, alvo, modo, tipoAtaque)

	if resultado.sucesso then
		DebugPrint(
			string.format(
				"[Combate] Knockback aplicado via %s: %.1f",
				resultado.metodo or "?",
				resultado.magnitudeAplicada or 0
			)
		)
	else
		if resultado.erro and not resultado.erro:match("não permite") then
			DebugPrint("[Combate] Falha ao aplicar knockback: " .. tostring(resultado.erro))
		end
	end
end

-- Funções de bloco de defesa movidas para o topo do arquivo

function ControladorCombate._CriarHitbox(_atacante: Model, _tipoAtaque: string, _cframeCliente: CFrame?)
	warn("[ControladorCombate] _CriarHitbox está deprecado. Use ShapecastHitbox no cliente.")
	return {}
end

-- Verifica se o alvo tem um pedido de parry pendente dentro da janela de
-- compensacao de latencia. Retorna true e ativa o parry retroativamente se valido.
-- Garante exploit-safety: timestamp no futuro ou muito antigo sao rejeitados.
local function _VerificarLagCompParry(maquinaAlvo: any): boolean
	local ts = maquinaAlvo.dados.pendingParryTimestamp
	if not ts then
		return false
	end
	local agora = tick()
	-- Rejeitar timestamp no futuro (tolerancia de 50ms para imprecisao de relogio)
	if ts > agora + 0.05 then
		DebugPrint("[Combate] LagComp: timestamp no futuro rejeitado")
		return false
	end
	-- A janela considera o tempo desde que o CLIENTE apertou bloquear ate agora
	local janelaLagComp = Modulo_Configuracoes.ObterConfiguracao("JanelaLagCompParry") or 0.45
	if agora - ts > janelaLagComp then
		DebugPrint(string.format("[Combate] LagComp: timestamp expirado (%.3fs > %.3fs)", agora - ts, janelaLagComp))
		return false
	end
	-- O cooldown de parry ja foi validado ao armazenar o timestamp em ProcessarBloquear
	return true
end

function ControladorCombate._ProcessarHit(
	atacante: Model,
	alvo: Model,
	tipoAtaque: string,
	danoOverride: number?,
	parteAtingida: string?,
	multiplicadorDano: number?
)
	local maquinaAtacante = maquinasDeEstado[atacante]
	local maquinaAlvo = ControladorCombate.ObterMaquina(alvo)

	if not maquinaAtacante or not maquinaAlvo then
		return
	end

	-- ===== LAG-COMP PARRY =====
	-- Se o alvo nao esta bloqueando no servidor mas enviou um pedido de bloquear
	-- dentro da janela de compensacao de latencia, tratamos como bloqueio valido.
	-- Isso cobre o cenario: cliente apertou bloquear, mas o HitboxAcerto chegou
	-- ao servidor antes do Bloquear devido ao ping diferente entre os dois jogadores.
	if parteAtingida == "DefesaBlock" and not maquinaAlvo:EstaBloqueando() then
		if _VerificarLagCompParry(maquinaAlvo) then
			DebugPrint(string.format("[Combate] LagComp: ativando bloqueio retroativo para %s", alvo.Name))
			-- Ativar os campos que EstaBloqueando() e EstaProntoParaAparar() consultam.
			maquinaAlvo.dados.bloqueando = true
			maquinaAlvo.dados.estadoAcao = "Defendendo"
		end
	end
	-- Limpar o timestamp pendente independente do resultado (usado uma vez por swing)
	if parteAtingida == "DefesaBlock" then
		maquinaAlvo.dados.pendingParryTimestamp = nil
	end

	-- ===== PARRY (defensor pronto para aparar e atingiu o bloco de defesa) =====
	if maquinaAlvo:EstaProntoParaAparar() and maquinaAlvo:EstaBloqueando() and parteAtingida == "DefesaBlock" then
		local tempoStun = Modulo_Configuracoes.ObterConfiguracao("TempoStunAparado") or 0.7
		local tempoAparando = Modulo_Configuracoes.ObterConfiguracao("TempoAparando") or tempoStun

		ControladorCombate._TocarAnimacao(alvo, "Aparar")
		ControladorCombate._TocarAnimacao(atacante, "Aparado")

		-- Atacante entra em estado APARADO (anim correta) em vez de Stunado generico.
		if maquinaAtacante.AplicarAparado then
			maquinaAtacante:AplicarAparado(tempoStun)
		else
			maquinaAtacante:EntrarStun(tempoStun)
		end
		if maquinaAlvo.AplicarAparando then
			maquinaAlvo:AplicarAparando(tempoAparando)
		end

		AtualizarDefesaBlock(alvo, isParryDebugActive(), false)

		-- Reseta cooldown de parry do defensor: parry bem sucedido permite aparar
		-- o proximo ataque imediatamente. (REQ: 'Aparar resetar o proprio cooldown')
		maquinaAlvo.dados.ultimoParry = 0

		-- Impulso especifico de parry: metade do impulso do final de combo.
		local resultadoImpulso = Modulo_Impulso.AplicarImpulsoParry(alvo, atacante)
		if not resultadoImpulso.sucesso then
			DebugPrint("[Combate] Falha ao aplicar impulso de parry: " .. tostring(resultadoImpulso.erro))
		end

		DebugPrint(string.format("[Combate] %s APAROU ataque de %s!", alvo.Name, atacante.Name))
		if DanoDebugVisual then
			DanoDebugVisual:FireAllClients(alvo, 0, {
				tipo = "Parry",
				atacante = atacante,
			})
		end
		return
	end

	-- ===== BLOQUEIO (sem parry, mas atingiu o bloco de defesa) =====
	if maquinaAlvo:EstaBloqueando() and parteAtingida == "DefesaBlock" then
		if tipoAtaque == "AtaqueLeveFinal" then
			local tempoStun = 0.6

			maquinaAlvo:QuebrarDefesa(tempoStun)
			ControladorCombate._TocarAnimacao(alvo, "DefesaQuebrada")

			-- Knockback no defensor (defesa quebrada).
			ControladorCombate._AplicarKnockback(alvo, atacante, tipoAtaque)

			DebugPrint(string.format("[Combate] %s teve a defesa QUEBRADA por %s!", alvo.Name, atacante.Name))
			if DanoDebugVisual then
				DanoDebugVisual:FireAllClients(alvo, 0, {
					tipo = "BlockBroken",
					atacante = atacante,
				})
			end
			return
		else
			-- Ataque leve absorvido: nao tira vida, mas cada lado sente um leve impacto.
			-- Defensor recua um pouco, atacante recua um pouco (feedback de hit).
			local modoAtacante = maquinaAtacante:ObterModo()
			local modoAlvo = maquinaAlvo:ObterModo()
			Modulo_Knockback.AplicarKnockback(atacante, alvo, modoAtacante, "AtaqueLeve")
			Modulo_Knockback.AplicarKnockback(alvo, atacante, modoAlvo, "AtaqueLeve")
			DebugPrint(string.format("[Combate] %s bloqueou ataque de %s", alvo.Name, atacante.Name))

			local danoBase = danoOverride
			if not danoBase then
				local tool = atacante:FindFirstChildOfClass("Tool")
				danoBase = (tool and Modulo_Dano.ObterDanoBase(tool)) or 0
			end

			if DanoDebugVisual then
				DanoDebugVisual:FireAllClients(alvo, danoBase, {
					tipo = "Block",
					atacante = atacante,
				})
			end
			return
		end
	end

	-- ===== HIT NORMAL =====
	local resultado
	if danoOverride then
		resultado = Modulo_Dano.AplicarDanoComValor(atacante, alvo, tipoAtaque, danoOverride)
	else
		local characterAtacante = atacante
		local tool = characterAtacante:FindFirstChildOfClass("Tool")
		if not tool then
			DebugPrint("[Combate] Sem tool para aplicar dano")
			return
		end
		resultado = Modulo_Dano.AplicarDano(tool, atacante, alvo, tipoAtaque)
	end

	if resultado.sucesso then
		local danoAplicado = resultado.danoAplicado or 0
		DebugPrint(string.format("[Combate] Dano aplicado: %.1f em %s", danoAplicado, alvo.Name))
		danoAplicadoEvent:Fire(atacante, alvo, tipoAtaque, danoAplicado)

		local tempoStun = Modulo_Configuracoes.ObterConfiguracao("TempoStunLeve")

		maquinaAlvo:EntrarStun(tempoStun or 0.3)
		ControladorCombate._TocarAnimacao(alvo, "Stunado")

		ControladorCombate._AplicarKnockback(alvo, atacante, tipoAtaque)

		if DanoDebugVisual then
			DanoDebugVisual:FireAllClients(alvo, danoAplicado, {
				tipo = "Hit",
				atacante = atacante,
				multiplicador = multiplicadorDano,
				bypassed = (maquinaAlvo:EstaBloqueando() and parteAtingida ~= "DefesaBlock"),
			})
		end
	else
		DebugPrint("[Combate] Falha ao aplicar dano: " .. tostring(resultado.erro))
	end
end

function ControladorCombate.ProcessarAtacarLeveEmPe(entidade: Model, dados: any?): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, tipoAtaque, motivo = maquina:TenteAtacarLeveEmPe()

	if not sucesso then
		if motivo == "ComboContinuado" then
			DebugPrint(string.format("[Combate] %s: Combo input registrado", entidade.Name))
			return true, nil
		end

		DebugPrint(string.format("[Combate] %s: AtacarLeveEmPe FALHOU - %s", entidade.Name, motivo or "?"))
		return false, motivo
	end

	if tipoAtaque then
		DebugPrint(string.format("[Combate] %s: AtacarLeveEmPe OK - tipo=%s", entidade.Name, tipoAtaque))

		local velocidade = (typeof(dados) == "table" and typeof(dados.velocidade) == "number") and dados.velocidade or 1.0
		ControladorCombate._TocarAnimacao(entidade, tipoAtaque, false, velocidade)

		ControladorCombate._AplicarImpulsoAtacante(entidade, tipoAtaque)

		local humanoid = entidade:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local velBloq = Modulo_Configuracoes.ObterConfiguracao("VelocidadeBloqueando") or 6
			local velocidadeAtaque = velBloq * 1.5
			humanoid.WalkSpeed = velocidadeAtaque
		end
	end

	return true, tipoAtaque
end

function ControladorCombate.ProcessarComboHitbox(entidade: Model, dados: any): (boolean, string?)
	local indiceGolpe = typeof(dados) == "table" and dados.indice or (tonumber(dados) or 0)

	local maquina = ControladorCombate.ObterMaquina(entidade)

	if maquina:ObterEstadoAcao() ~= "AtacandoLeve" then
		DebugPrint(string.format("[Combate] %s: ComboHitbox ignorado - não está atacando", entidade.Name))
		return false, "NaoAtacando"
	end

	local tipoAtaque = DeterminarTipoAtaque(indiceGolpe)

	DebugPrint(string.format("[Combate] %s: ComboHitbox golpe %d - tipo=%s", entidade.Name, indiceGolpe, tipoAtaque))

	maquina:AvancarGolpeCombo(indiceGolpe)

	ControladorCombate._AplicarImpulsoAtacante(entidade, tipoAtaque)

	if EhGolpeFinal(indiceGolpe) then
		local tempoFinal = Modulo_Configuracoes.ObterConfiguracao("JanelaCancelamentoComboFinal") or 0.6
		task.delay(tempoFinal, function()
			if maquina:ObterEstadoAcao() == "AtacandoLeve" then
				maquina:CompletarAcao()
				ControladorCombate._SincronizarEstado(entidade)
			end
		end)
	end

	return true, tipoAtaque
end

function ControladorCombate.ProcessarComboContinuado(entidade: Model, proximoIndice: number): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	if maquina:ObterEstadoAcao() ~= "AtacandoLeve" then
		return false, "NaoAtacando"
	end

	maquina:DesativarJanelaCombo()
	maquina.dados.ultimaContinuacaoCombo = tick()

	DebugPrint(string.format("[Combate] %s: Combo continuado para golpe %d", entidade.Name, proximoIndice))

	return true, nil
end

function ControladorCombate.ProcessarComboTerminou(entidade: Model)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	if maquina:ObterEstadoAcao() == "AtacandoLeve" then
		maquina:CompletarAcao()
		ControladorCombate._PararAnimacao(entidade)
		ControladorCombate._SincronizarEstado(entidade)

		DebugPrint(string.format("[Combate] %s: Combo terminado", entidade.Name))
	end

	return true, nil
end

function ControladorCombate.ProcessarComboEarlyCancel(entidade: Model)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	if maquina:ObterEstadoAcao() == "AtacandoLeve" then
		maquina:CompletarAcao()

		local humanoid = entidade:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = Modulo_Configuracoes.ObterConfiguracao("VelocidadeAndando") or 14
		end

		ControladorCombate._PararAnimacao(entidade)
		ControladorCombate._SincronizarEstado(entidade)

		DebugPrint(string.format("[Combate] %s: Combo early cancel executado", entidade.Name))
	end

	return true, nil
end

function ControladorCombate.ProcessarRollEarlyCancel(entidade: Model)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	if maquina:ObterEstadoAcao() == MaquinaDeEstados.EstadoAcao.Rolando then
		maquina:CompletarRoll()

		maquina.dados.correndoIntent = nil

		local status = entidade:FindFirstChild("Status")
		if status then
			local rollOn = status:FindFirstChild("RollOn")
			if rollOn and rollOn:IsA("BoolValue") then
				rollOn.Value = false
			end
		end

		ControladorCombate._PararAnimacao(entidade)
		ControladorCombate._SincronizarEstado(entidade)

		DebugPrint(string.format("[Combate] %s: Roll early cancel executado", entidade.Name))
	end

	return true, nil
end

function ControladorCombate.ProcessarDashEarlyCancel(entidade: Model)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	if maquina:ObterEstadoAcao() == MaquinaDeEstados.EstadoAcao.Dashando then
		maquina:CompletarDash()

		maquina.dados.correndoIntent = nil

		local status = entidade:FindFirstChild("Status")
		if status then
			local dashOn = status:FindFirstChild("DashOn")
			if dashOn and dashOn:IsA("BoolValue") then
				dashOn.Value = false
			end
		end

		ControladorCombate._PararAnimacao(entidade)
		ControladorCombate._SincronizarEstado(entidade)

		DebugPrint(string.format("[Combate] %s: Dash early cancel executado", entidade.Name))
	end

	return true, nil
end

function ControladorCombate.ProcessarCancelarAtaquePorDefesa(entidade: Model, tipoAtaque: string)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local estadoAcao = maquina:ObterEstadoAcao()

	local podeCancel = (tipoAtaque == "AtaqueLeve" and estadoAcao == "AtacandoLeve")

	if podeCancel then
		maquina:CompletarAcao()

		local cooldownCompleto = Modulo_Configuracoes.ObterConfiguracao("CooldownComboLeve") or 0.4
		local cooldownCancel = 0.1
		maquina.dados.ultimoComboTerminou = tick() - cooldownCompleto + cooldownCancel

		local humanoid = entidade:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = Modulo_Configuracoes.ObterConfiguracao("VelocidadeAndando") or 14
		end

		ControladorCombate._PararAnimacao(entidade)
		ControladorCombate._SincronizarEstado(entidade)

		DebugPrint(string.format("[Combate] %s: Ataque '%s' cancelado por defesa", entidade.Name, tipoAtaque))
	end

	return true, nil
end

function ControladorCombate.ProcessarAjustarVelocidadeAnimacao(entidade: Model, dados: any): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)
	if not maquina then
		return false, "SemMaquina"
	end

	local estadoAcao = maquina:ObterEstadoAcao()
	if estadoAcao ~= "AtacandoLeve" then
		return false, "NaoAtacando"
	end

	if typeof(dados) == "table" and typeof(dados.velocidade) == "number" then
		local animId = ""
		TocarAnimacao:FireAllClients(entidade, animId, "", false, dados.velocidade)
	end

	return true, nil
end

function ControladorCombate.ProcessarAtacarLeveAgachado(entidade: Model, dados: any?): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, tipoAtaque, motivo = maquina:TenteAtacarLeveAgachado()

	if not sucesso then
		return false, motivo
	end

	tipoAtaque = tipoAtaque or "AtaqueLeve"

	local velocidade = (typeof(dados) == "table" and typeof(dados.velocidade) == "number") and dados.velocidade or 1.0
	ControladorCombate._TocarAnimacao(entidade, tipoAtaque, false, velocidade)
	ControladorCombate._AplicarImpulsoAtacante(entidade, tipoAtaque)

	local humanoid = entidade:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local velBloq = Modulo_Configuracoes.ObterConfiguracao("VelocidadeBloqueando") or 6
		humanoid.WalkSpeed = velBloq * 1.5
	end

	return true, nil
end

-- Aceita o timestamp reportado pelo cliente para compensação de latência de parry.
-- Regras anti-exploit verificadas em _ProcessarHit: timestamp no futuro ou muito
-- antigo sao descartados. O bloquear ainda precisa ter sido aceito pela maquina.
function ControladorCombate.ProcessarBloquear(
	entidade: Model,
	shiftLockAtivo: boolean?,
	clienteTimestamp: number?
): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, motivo = maquina:TenteBloquear(shiftLockAtivo)

	if not sucesso then
		DebugPrint(string.format("[Combate] %s: Bloquear FALHOU - %s", entidade.Name, motivo or "?"))
		return false, motivo
	end

	DebugPrint(string.format("[Combate] %s: Bloquear OK", entidade.Name))

	local humanoid = entidade:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Modulo_Configuracoes.ObterConfiguracao("VelocidadeBloqueando") or 6
	end

	-- Animação agora é iniciada de forma centralizada pelo listener AoMudarEstadoAcao

	local status = entidade:FindFirstChild("Status")
	local agora = tick()
	local cooldownParry = Modulo_Configuracoes.ObterConfiguracao("CooldownParry") or 2.4
	local podeParry = (agora - (maquina.dados.ultimoParry or 0)) >= cooldownParry

	if podeParry then
		maquina.dados.prontoParaAparar = true
		maquina.dados.ultimoParry = agora

		-- Guardar o timestamp do cliente para lag-comp: usado em _ProcessarHit
		-- para validar parry retroativo de jogadores com latencia alta.
		-- O timestamp e validado em _ProcessarHit; aqui apenas armazenamos se
		-- o valor e plausivel (nao esta muito no futuro).
		if typeof(clienteTimestamp) == "number" and clienteTimestamp <= agora + 0.1 then
			maquina.dados.pendingParryTimestamp = clienteTimestamp
		else
			maquina.dados.pendingParryTimestamp = agora
		end

		if status then
			local prontoAparar = status:FindFirstChild("ProntoAparar")
			if prontoAparar and prontoAparar:IsA("BoolValue") then
				prontoAparar.Value = true
			end
		end
		CriarDefesaBlock(entidade, isParryDebugActive(), true)
		ControladorCombate._SincronizarEstado(entidade)

		task.delay(Modulo_Configuracoes.ObterConfiguracao("JanelaParry") or 0.2, function()
			maquina:DesativarParry()
			-- Limpar timestamp pendente ao expirar a janela de parry
			maquina.dados.pendingParryTimestamp = nil
			if status then
				local prontoAparar = status:FindFirstChild("ProntoAparar")
				if prontoAparar and prontoAparar:IsA("BoolValue") then
					prontoAparar.Value = false
				end
			end
			AtualizarDefesaBlock(entidade, isParryDebugActive(), false)
			ControladorCombate._SincronizarEstado(entidade)
		end)
	else
		maquina.dados.prontoParaAparar = false
		if status then
			local prontoAparar = status:FindFirstChild("ProntoAparar")
			if prontoAparar and prontoAparar:IsA("BoolValue") then
				prontoAparar.Value = false
			end
		end
		CriarDefesaBlock(entidade, isParryDebugActive(), false)
		ControladorCombate._SincronizarEstado(entidade)
	end

	return true, nil
end

function ControladorCombate.ProcessarPararBloqueio(entidade: Model): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, motivo = maquina:TentePararBloqueio()

	if not sucesso then
		return false, motivo
	end

	local status = entidade:FindFirstChild("Status")
	if status then
		local prontoAparar = status:FindFirstChild("ProntoAparar")
		if prontoAparar and prontoAparar:IsA("BoolValue") then
			prontoAparar.Value = false
		end
	end

	DestruirDefesaBlock(entidade)
	ControladorCombate._PararAnimacao(entidade)
	ControladorCombate._SincronizarEstado(entidade)

	return true, nil
end

function ControladorCombate.ProcessarQuebrarDefesa(entidade: Model): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, motivo = maquina:TenteQuebrarDefesa()

	if not sucesso then
		return false, motivo
	end

	local humanoid = entidade:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Modulo_Configuracoes.ObterConfiguracao("VelocidadeDefesaQuebrada") or 3
	end

	ControladorCombate._TocarAnimacao(entidade, "DefesaQuebrada")
	DestruirDefesaBlock(entidade)

	return true, nil
end

function ControladorCombate.ProcessarAgachar(entidade: Model): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, motivo = maquina:TenteAgachar()

	if not sucesso then
		DebugPrint(string.format("[Combate] %s: Agachar FALHOU - %s", entidade.Name, motivo or "?"))
		return false, motivo
	end

	DebugPrint(string.format("[Combate] %s: Agachar OK", entidade.Name))

	local humanoid = entidade:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Modulo_Configuracoes.ObterConfiguracao("VelocidadeAgachando") or 9
	end

	return true, nil
end

function ControladorCombate.ProcessarLevantar(entidade: Model): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, motivo = maquina:TenteLevantar()

	if not sucesso then
		DebugPrint(string.format("[Combate] %s: Levantar FALHOU - %s", entidade.Name, motivo or "?"))
		return false, motivo
	end

	DebugPrint(string.format("[Combate] %s: Levantar OK", entidade.Name))

	local humanoid = entidade:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Modulo_Configuracoes.ObterConfiguracao("VelocidadeAndando") or 14
	end

	return true, nil
end

function ControladorCombate.ProcessarPular(entidade: Model)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, motivo = maquina:TentePular()

	if not sucesso then
		return false, motivo
	end

	return true, nil
end

function ControladorCombate.ProcessarEquipar(entidade: Model, modo: string): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, motivo = maquina:TenteEquipar(modo)

	if not sucesso then
		DebugPrint(string.format("[Combate] %s: Equipar '%s' FALHOU - %s", entidade.Name, modo, motivo or "?"))
		return false, motivo
	end

	DebugPrint(string.format("[Combate] %s: Equipar '%s' OK", entidade.Name, modo))

	maquina:DefinirModo(modo)

	ControladorCombate._TocarAnimacao(entidade, "Equipar")

	return true, nil
end

function ControladorCombate.ProcessarDesequipar(entidade: Model)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, motivo = maquina:TenteDesequipar()

	if not sucesso then
		return false, motivo
	end

	ControladorCombate._TocarAnimacao(entidade, "Desequipar")

	task.delay(0.1, function()
		maquina:DefinirModo("Base")
		ControladorCombate._SincronizarEstado(entidade)
	end)

	return true, nil
end

function ControladorCombate.ProcessarShiftLock(entidade: Model, ativo: boolean)
	local maquina = ControladorCombate.ObterMaquina(entidade)
	maquina:DefinirShiftLock(ativo)

	local status = entidade:FindFirstChild("Status")
	if status then
		local shiftLockValue = status:FindFirstChild("ShiftLockOn")
		if shiftLockValue and shiftLockValue:IsA("BoolValue") then
			shiftLockValue.Value = ativo
		end
	end
end

function ControladorCombate.ProcessarCorrer(entidade: Model): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, motivo = maquina:TenteCorrer()

	if not sucesso then
		DebugPrint(string.format("[Combate] %s: Correr FALHOU - %s", entidade.Name, motivo or "?"))

		if motivo == "AcaoEmAndamento" then
			(maquina.dados :: any).correndoIntent = true
			DebugPrint(
				string.format("[Combate] %s: Pedido de correr enfileirado enquanto ação em andamento", entidade.Name)
			)
			return true, nil
		end
		if motivo == "EstadoBloqueante" then
			local estadoAcao = maquina.dados.estadoAcao
			if
				estadoAcao == MaquinaDeEstados.EstadoAcao.Equipando
				or estadoAcao == MaquinaDeEstados.EstadoAcao.Desequipando
				or estadoAcao == MaquinaDeEstados.EstadoAcao.Rolando
				or estadoAcao == MaquinaDeEstados.EstadoAcao.Dashando
			then
				(maquina.dados :: any).correndoIntent = true
				DebugPrint(
					string.format("[Combate] %s: Pedido de correr enfileirado durante %s", entidade.Name, estadoAcao)
				)
				return true, nil
			end
		end
		return false, motivo
	end

	DebugPrint(string.format("[Combate] %s: Correr OK", entidade.Name))

	ControladorCombate._SincronizarEstado(entidade)
	return true, nil
end

function ControladorCombate.ProcessarPararCorrer(entidade: Model)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local _sucesso = maquina:TentePararCorrer()

	DebugPrint(string.format("[Combate] %s: PararCorrer OK", entidade.Name))

	local humanoid = entidade:FindFirstChildOfClass("Humanoid")
	if humanoid then
		maquina.dados.correndoIntent = nil
	end

	ControladorCombate._SincronizarEstado(entidade)
	return true, nil
end

function ControladorCombate.ProcessarRoll(entidade: Model, direcao: string): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local estavaCorrendo = maquina.dados.correndo

	local sucesso, motivo = maquina:TenteRoll(direcao)

	if not sucesso then
		DebugPrint(string.format("[Combate] %s: Roll FALHOU - %s", entidade.Name, motivo or "?"))
		return false, motivo
	end

	DebugPrint(string.format("[Combate] %s: Roll OK - direção=%s", entidade.Name, direcao))

	if estavaCorrendo then
		(maquina.dados :: any).correndoIntent = true
	end

	local nomeAnimacao = "Roll" .. direcao
	local velocidadeAnim = Modulo_Configuracoes.ObterConfiguracao("VelocidadeAnimacaoRoll") or 1.0
	ControladorCombate._TocarAnimacao(entidade, nomeAnimacao, false, velocidadeAnim)

	local status = entidade:FindFirstChild("Status")
	if status then
		local rollOn = status:FindFirstChild("RollOn")
		if rollOn and rollOn:IsA("BoolValue") then
			rollOn.Value = true
		end
	end

	ControladorCombate._SincronizarEstado(entidade)
	return true, nil
end

function ControladorCombate.ProcessarRollTerminou(entidade: Model): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	if maquina.dados.estadoAcao ~= MaquinaDeEstados.EstadoAcao.Rolando then
		return false, "NaoEstaRolando"
	end

	maquina:CompletarRoll()

	DebugPrint(string.format("[Combate] %s: Roll TERMINOU", entidade.Name))

	local status = entidade:FindFirstChild("Status")
	if status then
		local rollOn = status:FindFirstChild("RollOn")
		if rollOn and rollOn:IsA("BoolValue") then
			rollOn.Value = false
		end
	end

	maquina.dados.correndoIntent = nil

	ControladorCombate._SincronizarEstado(entidade)
	return true, nil
end

function ControladorCombate.ProcessarDash(entidade: Model, direcao: string): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local estavaCorrendo = maquina.dados.correndo

	local sucesso, motivo = maquina:TenteDash(direcao)

	if not sucesso then
		DebugPrint(string.format("[Combate] %s: Dash FALHOU - %s", entidade.Name, motivo or "?"))
		return false, motivo
	end

	DebugPrint(string.format("[Combate] %s: Dash OK - direção=%s", entidade.Name, direcao))

	if estavaCorrendo then
		(maquina.dados :: any).correndoIntent = true
	end

	local nomeAnimacao = "Dash" .. direcao
	local velocidadeAnim = Modulo_Configuracoes.ObterConfiguracao("VelocidadeAnimacaoDash") or 1.0
	ControladorCombate._TocarAnimacao(entidade, nomeAnimacao, false, velocidadeAnim)

	local status = entidade:FindFirstChild("Status")
	if status then
		local dashOn = status:FindFirstChild("DashOn")
		if dashOn and dashOn:IsA("BoolValue") then
			dashOn.Value = true
		end
	end

	ControladorCombate._SincronizarEstado(entidade)
	return true, nil
end

function ControladorCombate.ProcessarDashTerminou(entidade: Model): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	if maquina.dados.estadoAcao ~= MaquinaDeEstados.EstadoAcao.Dashando then
		return false, "NaoEstaDashando"
	end

	maquina:CompletarDash()

	DebugPrint(string.format("[Combate] %s: Dash TERMINOU", entidade.Name))

	local status = entidade:FindFirstChild("Status")
	if status then
		local dashOn = status:FindFirstChild("DashOn")
		if dashOn and dashOn:IsA("BoolValue") then
			dashOn.Value = false
		end
	end

	maquina.dados.correndoIntent = nil

	ControladorCombate._SincronizarEstado(entidade)
	return true, nil
end

function ControladorCombate.ProcessarAterrissar(entidade: Model)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso = maquina:TenteAterrissar()

	if sucesso then
		ControladorCombate._SincronizarEstado(entidade)
	end

	return sucesso
end

function ControladorCombate.ProcessarSincronizarMovimento(entidade: Model, novoEstado: string)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso = maquina:DefinirEstadoMov(novoEstado)

	if sucesso then
		ControladorCombate._SincronizarEstado(entidade)
	end

	return sucesso
end

function ControladorCombate.ProcessarHitboxAcerto(entidade: Model, dados: any): (boolean, string?)
	if typeof(dados) ~= "table" then
		return false, "DadosInvalidos"
	end

	local mao: string? = dados.mao
	local alvoInstance: any = dados.alvo
	local _cframeCliente: CFrame? = dados.cframe

	if not mao or (mao ~= "Right" and mao ~= "Left") then
		return false, "MaoInvalida"
	end

	if not alvoInstance or typeof(alvoInstance) ~= "Instance" or not alvoInstance:IsA("Model") then
		return false, "AlvoInvalido"
	end

	local alvo = alvoInstance :: Model

	if alvo == entidade then
		return false, "AutoHit"
	end

	local alvoHumanoid = alvo:FindFirstChildOfClass("Humanoid")
	if not alvoHumanoid or alvoHumanoid.Health <= 0 then
		return false, "AlvoMorto"
	end

	local maquina = ControladorCombate.ObterMaquina(entidade)

	local estadoAcao = maquina:ObterEstadoAcao()
	local emAtaque = estadoAcao == "AtacandoLeve" or estadoAcao == "AtacandoLeveAgachado"

	if not emAtaque then
		DebugPrint(
			string.format(
				"[Combate] %s: HitboxAcerto ignorado - não está atacando (estado=%s)",
				entidade.Name,
				estadoAcao
			)
		)
		return false, "NaoAtacando"
	end

	local tool = (ObterToolPorMao(entidade, mao) or entidade:FindFirstChildOfClass("Tool")) :: any

	if not tool then
		DebugPrint(string.format("[Combate] %s: HitboxAcerto - sem tool para mao %s", entidade.Name, mao))
		return false, "SemTool"
	end

	local hrpAtacante = entidade:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hrpAlvo = alvo:FindFirstChild("HumanoidRootPart") :: BasePart?

	if hrpAtacante and hrpAlvo then
		local alcanceMaximo = 8
		local dadosTool = tool:FindFirstChild("Dados")
		local alcanceValue = dadosTool and dadosTool:FindFirstChild("Alcance")
		if alcanceValue and (alcanceValue:IsA("NumberValue") or alcanceValue:IsA("IntValue")) then
			alcanceMaximo = (alcanceValue :: any).Value
		end

		local distancia = (hrpAtacante.Position - hrpAlvo.Position).Magnitude
		if distancia > alcanceMaximo * 2 then
			DebugPrint(
				string.format(
					"[Combate] %s: HitboxAcerto rejeitado - distância %.1f > máximo %.1f",
					entidade.Name,
					distancia,
					alcanceMaximo * 2
				)
			)
			return false, "ForaDeAlcance"
		end
	end

	local tipoAtaque = "AtaqueLeve"
	if estadoAcao == "AtacandoLeve" then
		local indiceCombo = maquina.dados.indiceCombo or 1
		tipoAtaque = DeterminarTipoAtaque(indiceCombo)
	end

	local modo = maquina:ObterModo()
	local configCombo = Modulo_Configuracoes.ObterConfiguracaoCombo(modo)
	local ehDivideDano = configCombo and configCombo.divideDano == true

	local danoBase = Modulo_Dano.ObterDanoBase(tool)
	if not danoBase then
		return false, "SemDanoBase"
	end

	local multMax = Modulo_Configuracoes.ObterConfiguracao("MultiplicadorDanoMaximoCarga") or 1.2
	local multiplicadorDano = 1.0
	if typeof(dados.multiplicadorDano) == "number" then
		multiplicadorDano = math.clamp(dados.multiplicadorDano, 1.0, multMax)
	end

	local danoOverride: number? = nil
	if ehDivideDano then
		danoOverride = (danoBase / 2) * multiplicadorDano
	else
		danoOverride = danoBase * multiplicadorDano
	end

	local parteAtingida: string? = dados.parteAtingida
	ControladorCombate._ProcessarHit(entidade, alvo, tipoAtaque, danoOverride, parteAtingida, multiplicadorDano)

	DebugPrint(
		string.format(
			"[Combate] %s: HitboxAcerto processado - mao=%s, alvo=%s, tipo=%s, mult=%.2f",
			entidade.Name,
			mao,
			alvo.Name,
			tipoAtaque,
			multiplicadorDano
		)
	)

	return true, tipoAtaque
end

local MapaAcoes = {
	AtacarLeveEmPe = ControladorCombate.ProcessarAtacarLeveEmPe,
	AtacarLeveAgachado = ControladorCombate.ProcessarAtacarLeveAgachado,
	Bloquear = function(entidade, dados)
		local shiftLockAtivo = typeof(dados) == "table" and dados.shiftLock or nil
		local clienteTimestamp = typeof(dados) == "table" and typeof(dados.timestamp) == "number" and dados.timestamp or nil
		return ControladorCombate.ProcessarBloquear(entidade, shiftLockAtivo, clienteTimestamp)
	end,
	PararBloqueio = ControladorCombate.ProcessarPararBloqueio,
	QuebrarDefesa = ControladorCombate.ProcessarQuebrarDefesa,
	Agachar = ControladorCombate.ProcessarAgachar,
	Levantar = ControladorCombate.ProcessarLevantar,
	Pular = ControladorCombate.ProcessarPular,
	Correr = ControladorCombate.ProcessarCorrer,
	PararCorrer = ControladorCombate.ProcessarPararCorrer,
	Aterrissar = ControladorCombate.ProcessarAterrissar,
	Roll = function(entidade, dados)
		return ControladorCombate.ProcessarRoll(entidade, dados)
	end,
	RollTerminou = ControladorCombate.ProcessarRollTerminou,
	RollEarlyCancel = ControladorCombate.ProcessarRollEarlyCancel,
	Dash = function(entidade, dados)
		return ControladorCombate.ProcessarDash(entidade, dados)
	end,
	DashTerminou = ControladorCombate.ProcessarDashTerminou,
	DashEarlyCancel = ControladorCombate.ProcessarDashEarlyCancel,
	SincronizarMovimento = function(entidade, dados)
		return ControladorCombate.ProcessarSincronizarMovimento(entidade, dados)
	end,
	Equipar = function(entidade, dados)
		return ControladorCombate.ProcessarEquipar(entidade, dados)
	end,
	Desequipar = ControladorCombate.ProcessarDesequipar,

	ComboHitbox = function(entidade, dados)
		return ControladorCombate.ProcessarComboHitbox(entidade, dados)
	end,
	ComboContinuado = function(entidade, dados)
		return ControladorCombate.ProcessarComboContinuado(entidade, dados)
	end,
	ComboTerminou = ControladorCombate.ProcessarComboTerminou,
	ComboEarlyCancel = ControladorCombate.ProcessarComboEarlyCancel,

	HitboxAcerto = function(entidade, dados)
		return ControladorCombate.ProcessarHitboxAcerto(entidade, dados)
	end,

	CancelarAtaquePorDefesa = function(entidade, dados)
		return ControladorCombate.ProcessarCancelarAtaquePorDefesa(entidade, dados)
	end,
	AjustarVelocidadeAnimacao = function(entidade, dados)
		return ControladorCombate.ProcessarAjustarVelocidadeAnimacao(entidade, dados)
	end,
}

function ControladorCombate.ProcessarAcao(entidade: Model, acao: string, dados: any?)
	local processador = MapaAcoes[acao]
	if not processador then
		warn("[ControladorCombate] Ação desconhecida: " .. acao)
		return false, "AcaoDesconhecida"
	end

	return processador(entidade, dados)
end

TentarAcao.OnServerEvent:Connect(function(player, acao, dados)
	local character = player.Character
	if not character then
		return
	end

	ControladorCombate.ProcessarAcao(character, acao, dados)
end)

MudarShiftLock.OnServerEvent:Connect(function(player, ativo)
	local character = player.Character
	if not character then
		return
	end

	ControladorCombate.ProcessarShiftLock(character, ativo)
end)

EquipAnimacaoTerminou.OnServerEvent:Connect(function(player, npcModel: Model?)
	-- Se npcModel foi enviado, a View do NPC no cliente esta notificando
	-- que a animacao de equip/desequip do NPC terminou.
	local entidade: Model?
	if typeof(npcModel) == "Instance" and npcModel:IsA("Model") and npcModel ~= (player.Character :: any) then
		entidade = npcModel
	else
		entidade = player.Character
	end
	if not entidade then
		return
	end

	local maquina = ControladorCombate.ObterMaquina(entidade)
	if not maquina then
		return
	end

	local estadoAcao = maquina:ObterEstadoAcao()
	if
		estadoAcao == MaquinaDeEstados.EstadoAcao.Equipando
		or estadoAcao == MaquinaDeEstados.EstadoAcao.Desequipando
	then
		DebugPrint(string.format("[Combate] %s: Animação de equip/desequip terminou", entidade.Name))
		maquina:CompletarAcao()
		ControladorCombate._SincronizarEstado(entidade)
	end
end)

local AcaoAnimacaoTerminou = Remotos:WaitForChild("AcaoAnimacaoTerminou")
AcaoAnimacaoTerminou.OnServerEvent:Connect(function(player, nomeAcao)
	local character = player.Character
	if not character then
		return
	end

	local maquina = ControladorCombate.ObterMaquina(character)
	if not maquina then
		return
	end

	local estadoAcao = maquina:ObterEstadoAcao()

	if estadoAcao == nomeAcao then
		DebugPrint(
			string.format(
				"[Combate] %s: Animação de AÇÃO '%s' terminou - completando ação",
				character.Name,
				nomeAcao or "(desconhecida)"
			)
		)
		maquina:CompletarAcao()

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = Modulo_Configuracoes.ObterConfiguracao("VelocidadeAndando") or 14
		end
		ControladorCombate._SincronizarEstado(character)
	else
		DebugPrint(
			string.format(
				"[Combate] %s: ignorando AcaoAnimacaoTerminou '%s' (estado atual é %s)",
				character.Name,
				tostring(nomeAcao),
				tostring(estadoAcao)
			)
		)
	end
end)

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		local status = character:WaitForChild("Status", 5)
		if not status then
			warn("[ControladorCombate] Status não encontrado para " .. player.Name)
		end

		local _maquina = ControladorCombate.ObterMaquina(character)

		task.defer(function()
			ControladorCombate._SincronizarEstado(character)
		end)

		local humanoid = character:FindFirstChild("Humanoid")
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.Died:Connect(function()
				local maquinaAtual = maquinasDeEstado[character]
				if maquinaAtual then
					maquinaAtual:AplicarMorte()
				end
			end)
		end
	end)

	player.CharacterRemoving:Connect(function(character)
		ControladorCombate.RemoverMaquina(character)
	end)
end)

for _, player in ipairs(Players:GetPlayers()) do
	if player.Character then
		local _status = player.Character:WaitForChild("Status", 5)
		ControladorCombate.ObterMaquina(player.Character)

		task.defer(function()
			ControladorCombate._SincronizarEstado(player.Character)
		end)
	end
end

DebugPrint("[ControladorCombate] Inicializado no servidor")

return ControladorCombate
