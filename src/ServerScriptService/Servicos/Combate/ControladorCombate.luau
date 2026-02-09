--[[
    ControladorCombate.module.lua
    
    Módulo do servidor responsável por:
    - Receber ações via RemoteEvent
    - Validar via MaquinaDeEstados
    - Aplicar animações (notificar clientes)
    - Criar hitboxes usando Modulo_Hitbox
    - Calcular e aplicar dano usando Modulo_Dano
    - Aplicar knockback usando Modulo_Knockback
    - Gerenciar stun e parry
    
    Autoridade: O servidor é autoridade final de todos os estados.
]]

--!strict

-- ═══════════════════════════════════════════════════════════════════
-- CONFIGURAÇÃO DE DEBUG
-- ═══════════════════════════════════════════════════════════════════
local DEBUG_ENABLED = false -- Altere para true para habilitar prints de debug

local function DebugPrint(...)
	if DEBUG_ENABLED then
		print(...)
	end
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Modulos = ReplicatedStorage:WaitForChild("Modulos")
local Combate = Modulos:WaitForChild("Combate")

local Modulo_Configuracoes = require(Combate:WaitForChild("Modulo_Configuracoes"))
local Modulo_Dano = require(Combate:WaitForChild("Modulo_Dano"))
local Modulo_Hitbox = require(Combate:WaitForChild("Modulo_Hitbox"))
local Modulo_Impulso = require(Combate:WaitForChild("Modulo_Impulso"))
local Modulo_Knockback = require(Combate:WaitForChild("Modulo_Knockback"))
local _Modulo_Combo = require(Combate:WaitForChild("Modulo_Combo")) -- Mantido se precisar no futuro
local MaquinaDeEstados = require(Modulos:WaitForChild("MaquinaDeEstados"))

local ControladorCombate = {}

-- ═══════════════════════════════════════════════════════════════════
-- CACHE DE ENTIDADES (PLAYERS E NPCS)
-- ═══════════════════════════════════════════════════════════════════

-- Armazena instâncias de MaquinaDeEstados por entidade
local maquinasDeEstado = {}

-- RemoteEvents
local Remotos = ReplicatedStorage:WaitForChild("Remotos")
local TentarAcao = Remotos:WaitForChild("TentarAcao")
local MudarShiftLock = Remotos:WaitForChild("MudarShiftLock")
local SincronizarEstado = Remotos:WaitForChild("SincronizarEstado")
local TocarAnimacao = Remotos:WaitForChild("TocarAnimacao")
local EquipAnimacaoTerminou = Remotos:WaitForChild("EquipAnimacaoTerminou")

-- RemoteEvent para knockback físico (usado pelo Modulo_Knockback se disponível)
local _AplicarKnockback = Remotos:FindFirstChild("AplicarKnockback")

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES AUXILIARES LOCAIS
-- ═══════════════════════════════════════════════════════════════════

local function DeterminarTipoAtaque(indice: number): string
	if indice >= 4 then
		return "AtaqueLeveFinal"
	end
	return "AtaqueLeve"
end

local function EhGolpeFinal(indice: number): boolean
	return indice >= 4
end

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES DO MÓDULO
-- ═══════════════════════════════════════════════════════════════════

--- Obtém ou cria máquina de estados para entidade
---@param entidade Model
---@return table MaquinaDeEstados
function ControladorCombate.ObterMaquina(entidade: Model)
	if not maquinasDeEstado[entidade] then
		maquinasDeEstado[entidade] = MaquinaDeEstados.Novo(entidade)

		-- Configurar callbacks para sincronizar estado
		maquinasDeEstado[entidade]:AoMudarEstadoAcao(function(novo, anterior)
			ControladorCombate._SincronizarEstado(entidade)
		end)

		maquinasDeEstado[entidade]:AoMudarEstadoMov(function(novo, anterior)
			ControladorCombate._SincronizarEstado(entidade)
		end)

		maquinasDeEstado[entidade]:AoMudarModo(function(novo, anterior)
			ControladorCombate._SincronizarEstado(entidade)
		end)
	end

	return maquinasDeEstado[entidade]
end

--- Remove máquina de estados quando entidade é destruída
function ControladorCombate.RemoverMaquina(entidade: Model)
	maquinasDeEstado[entidade] = nil
end

--- Sincroniza estado com todos os clientes e atualiza pasta Status
function ControladorCombate._SincronizarEstado(entidade: Model)
	local maquina = maquinasDeEstado[entidade]
	if not maquina then
		return
	end

	local dados = maquina:ObterDados()

	-- Atualiza pasta Status no character (apenas atributos server-authoritative)
	-- NOTA: modoAnimacao, estadoMov, AgachadoOn, CorrendoOn agora são gerenciados
	-- pelo client na pasta StatusLocal
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

		-- Server-authoritative: apenas estadoAcao e flags de combate
		atualizarValor("estadoAcao", dados.estadoAcao)
		atualizarValor("BloqueandoOn", dados.bloqueando)
		atualizarValor("ProntoAparar", dados.prontoParaAparar)
		atualizarValor("StunadoOn", dados.stunado)
		atualizarValor("DashOn", dados.dashando)
	end

	-- Debug log
	DebugPrint(
		string.format(
			"[Estado] %s: Mov=%s, Acao=%s, Modo=%s",
			entidade.Name,
			dados.estadoMov,
			dados.estadoAcao,
			dados.modoAnimacao
		)
	)

	-- NOTA: WalkSpeed de corrida agora é controlado 100% pelo cliente para evitar lag
	-- O servidor só ajusta WalkSpeed durante ações de combate específicas
	-- Quando estadoAcao == "Nenhuma", o cliente controla a velocidade baseado em isShiftHeld
	local humanoid = entidade:FindFirstChildOfClass("Humanoid")
	if humanoid then
		if dados.estadoAcao == "Nenhuma" then
			-- Se cliente pediu para correr durante a ação, mantém a flag
			-- mas NÃO ajusta velocidade - o cliente faz isso localmente
			if maquina.dados.correndoIntent then
				maquina.dados.correndoIntent = nil
				maquina.dados.correndo = true
				-- NÃO ajusta WalkSpeed aqui - cliente controla corrida
			end
			-- Para agachado/bloqueando, ainda ajustamos pois são estados do servidor
			if dados.agachado then
				humanoid.WalkSpeed = Modulo_Configuracoes.ObterConfiguracao("VelocidadeAgachado") or 9
			elseif dados.bloqueando then
				humanoid.WalkSpeed = Modulo_Configuracoes.ObterConfiguracao("VelocidadeBloqueando") or 6
			end
			-- Corrida normal é controlada pelo cliente
		end
	end

	SincronizarEstado:FireAllClients(entidade, dados)
end

--- Notifica cliente(s) para tocar animação
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

--- Aplica impulso ao atacante
function ControladorCombate._AplicarImpulsoAtacante(entidade: Model, tipoAtaque: string)
	local maquina = maquinasDeEstado[entidade]
	if not maquina then
		return
	end

	local modo = maquina:ObterModo()
	local resultado = Modulo_Impulso.AplicarImpulso(entidade, modo, tipoAtaque)

	if not resultado.sucesso then
		DebugPrint("[Combate] Falha ao aplicar impulso: " .. tostring(resultado.erro))
	end
end

--- Aplica knockback físico baseado na direção que o atacante está virado
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
		-- Knockback pode falhar se o modo não permitir, o que é normal (ex: ferramenta)
		if resultado.erro and not resultado.erro:match("não permite") then
			DebugPrint("[Combate] Falha ao aplicar knockback: " .. tostring(resultado.erro))
		end
	end
end

--- Cria hitbox e detecta colisões
---@return table Lista de entidades atingidas
function ControladorCombate._CriarHitbox(atacante: Model, tipoAtaque: string, cframeCliente: CFrame?)
	local maquina = maquinasDeEstado[atacante]
	if not maquina then
		return {}
	end

	-- Obtém Tool equipada
	local character = atacante
	local tool = character:FindFirstChildOfClass("Tool")
	if not tool then
		return {} -- Sem tool, sem ataque
	end

	-- Validação básica de distância se o cliente enviou CFrame (anti-teleport)
	local cframeFinal: CFrame? = nil
	if cframeCliente then
		local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart
		if hrp then
			-- Se a distância for maior que 8 studs, ignora e usa a do servidor (lag alto ou hack)
			local dist = (hrp.Position - cframeCliente.Position).Magnitude
			if dist < 8 then
				cframeFinal = cframeCliente
			else
				DebugPrint(
					string.format("[Combate] %s: CFrame do cliente ignorado (distância %.1f)", character.Name, dist)
				)
			end
		end
	end

	local resultado = Modulo_Hitbox.CriarHitboxMelee(atacante, tool, tipoAtaque, cframeFinal)

	if not resultado.sucesso then
		DebugPrint("[Combate] Falha ao criar hitbox: " .. tostring(resultado.erro))
		return {}
	end

	return resultado.entidadesAtingidas
end

--- Processa hit em uma entidade
function ControladorCombate._ProcessarHit(atacante: Model, alvo: Model, tipoAtaque: string)
	local maquinaAtacante = maquinasDeEstado[atacante]
	local maquinaAlvo = ControladorCombate.ObterMaquina(alvo)

	if not maquinaAtacante or not maquinaAlvo then
		return
	end

	-- Verifica parry
	if maquinaAlvo:EstaProntoParaAparar() and maquinaAlvo:EstaBloqueando() then
		-- PARRY!
		local tempoStun = Modulo_Configuracoes.ObterConfiguracao("TempoStunAparado") or 0.7

		-- Toca efeito de parry
		ControladorCombate._TocarAnimacao(alvo, "Aparar")
		ControladorCombate._TocarAnimacao(atacante, "Aparado")

		-- Aplica stun no atacante
		maquinaAtacante:EntrarStun(tempoStun)

		DebugPrint(string.format("[Combate] %s APAROU ataque de %s!", alvo.Name, atacante.Name))
		return
	end

	-- Verifica bloqueio
	if maquinaAlvo:EstaBloqueando() then
		-- BLOQUEIO!
		-- Verifica se ataque pesado quebra defesa
		if tipoAtaque == "AtaquePesado" or tipoAtaque == "AtaqueLeveFinal" then
			local tempoStun = Modulo_Configuracoes.ObterConfiguracao("TempoStunPesado") or 0.6

			maquinaAlvo:QuebrarDefesa(tempoStun)
			ControladorCombate._TocarAnimacao(alvo, "DefesaQuebrada")
			ControladorCombate._TocarAnimacao(atacante, "AtaquePesado") -- Reinicia/continua anim

			DebugPrint(string.format("[Combate] %s teve a defesa QUEBRADA por %s!", alvo.Name, atacante.Name))
		else
			-- Bloqueio normal
			local _tempoBlock = Modulo_Configuracoes.ObterConfiguracao("TempoStunLeve") or 0.3
			DebugPrint(string.format("[Combate] %s bloqueou ataque de %s", alvo.Name, atacante.Name))
			return
		end
	end

	-- Aplica dano
	local characterAtacante = atacante
	local tool = characterAtacante:FindFirstChildOfClass("Tool")

	if tool then
		-- Assinatura: tool, atacante, alvo, tipoAtaque
		local resultado = Modulo_Dano.AplicarDano(tool, atacante, alvo, tipoAtaque)

		if resultado.sucesso then
			local danoAplicado = resultado.danoAplicado or 0
			DebugPrint(string.format("[Combate] Dano aplicado: %.1f em %s", danoAplicado, alvo.Name))

			-- Stun no alvo
			local tempoStun
			if tipoAtaque == "AtaquePesado" then
				tempoStun = Modulo_Configuracoes.ObterConfiguracao("TempoStunPesado")
			else
				tempoStun = Modulo_Configuracoes.ObterConfiguracao("TempoStunLeve")
			end

			maquinaAlvo:EntrarStun(tempoStun or 0.3)
			ControladorCombate._TocarAnimacao(alvo, "Stunado")

			-- Knockback
			ControladorCombate._AplicarKnockback(alvo, atacante, tipoAtaque)
		else
			DebugPrint("[Combate] Falha ao aplicar dano: " .. tostring(resultado.erro))
		end
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- PROCESSADORES DE AÇÃO
-- ═══════════════════════════════════════════════════════════════════

--- Processa ação de ataque leve em pé
function ControladorCombate.ProcessarAtacarLeveEmPe(entidade: Model): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, tipoAtaque, motivo = maquina:TenteAtacarLeveEmPe()

	if not sucesso then
		-- Se motivo é "ComboContinuado", foi um input válido durante janela
		if motivo == "ComboContinuado" then
			DebugPrint(string.format("[Combate] %s: Combo input registrado", entidade.Name))
			return true, nil
		end

		DebugPrint(string.format("[Combate] %s: AtacarLeveEmPe FALHOU - %s", entidade.Name, motivo or "?"))
		return false, motivo
	end

	-- Só toca animação se foi um novo ataque (não continuação de combo)
	if tipoAtaque then
		DebugPrint(string.format("[Combate] %s: AtacarLeveEmPe OK - tipo=%s", entidade.Name, tipoAtaque))

		-- Toca animação (cliente configura marcadores)
		ControladorCombate._TocarAnimacao(entidade, tipoAtaque)

		-- Aplica impulso ao atacante
		ControladorCombate._AplicarImpulsoAtacante(entidade, tipoAtaque)

		-- Ao atacar, aplica velocidade de ataque baseada na velocidade de defesa (X + X/2)
		local humanoid = entidade:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local velBloq = Modulo_Configuracoes.ObterConfiguracao("VelocidadeBloqueando") or 6
			local velocidadeAtaque = velBloq * 1.5
			humanoid.WalkSpeed = velocidadeAtaque
		end
	end

	return true, tipoAtaque
end

-- ═══════════════════════════════════════════════════════════════════
-- PROCESSADORES DE COMBO POR MARCADORES
-- ═══════════════════════════════════════════════════════════════════

--- Processa hitbox de combo (chamado pelo cliente via marcador "Ataque")
--- @param entidade Model Personagem atacante
--- @param indiceGolpe number Índice do golpe (1, 2, 3, 4)
function ControladorCombate.ProcessarComboHitbox(entidade: Model, dados: any): (boolean, string?)
	-- dados pode ser o índice (number) ou uma tabela {indice: number, cframe: CFrame}
	local indiceGolpe = typeof(dados) == "table" and dados.indice or (tonumber(dados) or 0)
	local cframeCliente = typeof(dados) == "table" and dados.cframe or nil

	local maquina = ControladorCombate.ObterMaquina(entidade)

	-- Verifica se ainda está atacando
	if maquina:ObterEstadoAcao() ~= "AtacandoLeve" then
		DebugPrint(string.format("[Combate] %s: ComboHitbox ignorado - não está atacando", entidade.Name))
		return false, "NaoAtacando"
	end

	-- Determina o tipo de ataque baseado no índice
	local tipoAtaque = DeterminarTipoAtaque(indiceGolpe)

	DebugPrint(string.format("[Combate] %s: ComboHitbox golpe %d - tipo=%s", entidade.Name, indiceGolpe, tipoAtaque))

	-- Avança o índice do combo na máquina de estados
	maquina:AvancarGolpeCombo(indiceGolpe)

	-- Aplica impulso ao atacante
	ControladorCombate._AplicarImpulsoAtacante(entidade, tipoAtaque)

	-- Cria hitbox e processa hits
	local alvos = ControladorCombate._CriarHitbox(entidade, tipoAtaque, cframeCliente)
	for _, alvo in ipairs(alvos) do
		ControladorCombate._ProcessarHit(entidade, alvo, tipoAtaque)
	end

	-- Se foi o golpe final, agenda completar ação
	if EhGolpeFinal(indiceGolpe) then
		-- Aguarda animação terminar naturalmente
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

--- Processa notificação de combo continuado
--- @param entidade Model Personagem atacante
--- @param proximoIndice number Índice do próximo golpe
function ControladorCombate.ProcessarComboContinuado(entidade: Model, proximoIndice: number): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	-- Verifica se ainda está atacando
	if maquina:ObterEstadoAcao() ~= "AtacandoLeve" then
		return false, "NaoAtacando"
	end

	-- Ativa janela para o próximo golpe na máquina de estados
	maquina:DesativarJanelaCombo()

	DebugPrint(string.format("[Combate] %s: Combo continuado para golpe %d", entidade.Name, proximoIndice))

	return true, nil
end

--- Processa notificação de combo terminado
--- @param entidade Model Personagem atacante
function ControladorCombate.ProcessarComboTerminou(entidade: Model)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	-- Completa a ação se ainda está atacando
	if maquina:ObterEstadoAcao() == "AtacandoLeve" then
		maquina:CompletarAcao()
		ControladorCombate._SincronizarEstado(entidade)

		DebugPrint(string.format("[Combate] %s: Combo terminado", entidade.Name))
	end

	return true, nil
end

--- Processa notificação de early cancel do combo final
--- Muda o estado para Normal antes da animação terminar completamente
--- @param entidade Model Personagem atacante
function ControladorCombate.ProcessarComboEarlyCancel(entidade: Model)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	-- Completa a ação se ainda está atacando
	if maquina:ObterEstadoAcao() == "AtacandoLeve" then
		maquina:CompletarAcao()

		-- Resetar velocidade para normal
		local humanoid = entidade:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = Modulo_Configuracoes.ObterConfiguracao("VelocidadeNormal") or 14
		end

		ControladorCombate._SincronizarEstado(entidade)

		DebugPrint(string.format("[Combate] %s: Combo early cancel executado", entidade.Name))
	end

	return true, nil
end

--- Processa notificação de early cancel do ataque pesado
--- Muda o estado para Normal antes da animação terminar completamente
--- @param entidade Model Personagem atacante
function ControladorCombate.ProcessarHeavyAttackEarlyCancel(entidade: Model)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	-- Completa a ação se ainda está em ataque pesado (SoltandoPesado ou AtaquePesado)
	local estadoAcao = maquina:ObterEstadoAcao()
	if estadoAcao == "SoltandoPesado" or estadoAcao == "AtaquePesado" then
		maquina:CompletarAcao()

		-- Resetar velocidade para normal
		local humanoid = entidade:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = Modulo_Configuracoes.ObterConfiguracao("VelocidadeNormal") or 14
		end

		ControladorCombate._SincronizarEstado(entidade)

		DebugPrint(string.format("[Combate] %s: Heavy attack early cancel executado", entidade.Name))
	end

	return true, nil
end

--- Processa cancelamento de ataque por defesa
--- Chamado quando o jogador inicia bloqueio durante a janela de cancelamento de um ataque
--- @param entidade Model Personagem atacante
--- @param tipoAtaque string Tipo do ataque cancelado ("AtaqueLeve" ou "CarregandoPesado")
function ControladorCombate.ProcessarCancelarAtaquePorDefesa(entidade: Model, tipoAtaque: string)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local estadoAcao = maquina:ObterEstadoAcao()

	-- Verifica se está em um estado válido para cancelar
	local podeCancel = false
	if tipoAtaque == "AtaqueLeve" and estadoAcao == "AtacandoLeve" then
		podeCancel = true
	elseif
		tipoAtaque == "CarregandoPesado"
		and (estadoAcao == "CarregandoPesado" or estadoAcao == "SoltandoPesado" or estadoAcao == "AtaquePesado")
	then
		podeCancel = true
	end

	if podeCancel then
		maquina:CompletarAcao()

		-- Resetar velocidade para normal
		local humanoid = entidade:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = Modulo_Configuracoes.ObterConfiguracao("VelocidadeNormal") or 14
		end

		ControladorCombate._SincronizarEstado(entidade)

		DebugPrint(string.format("[Combate] %s: Ataque '%s' cancelado por defesa", entidade.Name, tipoAtaque))
	end

	return true, nil
end

--- Processa ação de ataque leve agachado
function ControladorCombate.ProcessarAtacarLeveAgachado(entidade: Model)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, _tipoAtaque, motivo = maquina:TenteAtacarLeveAgachado()

	if not sucesso then
		return false, motivo
	end

	ControladorCombate._TocarAnimacao(entidade, "AtaqueLeveAgachado")
	ControladorCombate._AplicarImpulsoAtacante(entidade, "AtaqueLeve")

	task.delay(0.1, function()
		local alvos = ControladorCombate._CriarHitbox(entidade, "AtaqueLeve")
		for _, alvo in ipairs(alvos) do
			ControladorCombate._ProcessarHit(entidade, alvo, "AtaqueLeve")
		end
	end)

	return true, nil
end

--- Processa carregar ataque pesado
function ControladorCombate.ProcessarCarregarPesado(entidade: Model)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, motivo = maquina:TenteCarregarPesado()

	if not sucesso then
		-- Notifica jogador se a ação foi rejeitada (ex: Cooldown)
		local player = Players:GetPlayerFromCharacter(entidade)
		if player then
			local rem = ReplicatedStorage:FindFirstChild("Remotos")
			if rem and rem:FindFirstChild("AcaoRejeitada") then
				rem:FindFirstChild("AcaoRejeitada"):FireClient(player, "CarregarPesado", motivo)
			end
		end
		return false, motivo
	end

	-- Ao carregar, aplica velocidade de ataque (X + X/2)
	local humanoid = entidade:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local velBloq = Modulo_Configuracoes.ObterConfiguracao("VelocidadeBloqueando") or 6
		humanoid.WalkSpeed = velBloq * 1.5
	end

	-- Usa velocidade configurável para o carregamento
	local velocidadeCarregar = Modulo_Configuracoes.ObterConfiguracao("VelocidadeCarregandoPesado") or 1.1
	ControladorCombate._TocarAnimacao(entidade, "AtaquePesado", false, velocidadeCarregar)

	return true, nil
end

--- Processa soltar ataque pesado
function ControladorCombate.ProcessarSoltarPesado(entidade: Model)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, motivo = maquina:TenteSoltarPesado()

	if not sucesso then
		-- Notifica jogador se a ação foi rejeitada (ex: Cooldown)
		local player = Players:GetPlayerFromCharacter(entidade)
		if player then
			local rem = ReplicatedStorage:FindFirstChild("Remotos")
			if rem and rem:FindFirstChild("AcaoRejeitada") then
				rem:FindFirstChild("AcaoRejeitada"):FireClient(player, "SoltarPesado", motivo)
			end
		end
		return false, motivo
	end

	-- Ao soltar, aplica velocidade de ataque (X + X/2)
	local humanoid = entidade:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local velBloq = Modulo_Configuracoes.ObterConfiguracao("VelocidadeBloqueando") or 6
		humanoid.WalkSpeed = velBloq * 1.5
	end

	-- NÃO envia nova animação - o cliente já está tocando e vai ajustar a velocidade
	-- A animação continua de onde parou, apenas com velocidade diferente
	ControladorCombate._AplicarImpulsoAtacante(entidade, "AtaquePesado")

	-- Sincroniza estado para notificar cliente que mudou para SoltandoPesado
	ControladorCombate._SincronizarEstado(entidade)

	-- Hitbox será criada pelo marcador HeavyAttack na animação
	-- O cliente notifica o servidor via TentarAcao quando o marcador é atingido

	return true, nil
end

--- Processa hitbox do ataque pesado (chamado pelo cliente quando o marcador HeavyAttack é atingido)
--- Transiciona de SoltandoPesado para AtaquePesado e cria o hitbox
function ControladorCombate.ProcessarHeavyAttackHitbox(entidade: Model, dados: any?): (boolean, string?)
	local cframeCliente = typeof(dados) == "table" and dados.cframe or nil
	local maquina = ControladorCombate.ObterMaquina(entidade)

	-- Verifica se está no estado correto (SoltandoPesado - M1 foi solto, mas ataque ainda não aconteceu)
	if maquina.dados.estadoAcao ~= "SoltandoPesado" then
		DebugPrint(
			string.format(
				"[Combate] %s: HeavyAttackHitbox FALHOU - não está em SoltandoPesado (está em %s)",
				entidade.Name,
				maquina.dados.estadoAcao
			)
		)
		return false, "EstadoInvalido"
	end

	-- Transiciona para AtaquePesado (momento real do ataque)
	local sucesso, motivo = maquina:TenteExecutarPesado()
	if not sucesso then
		DebugPrint(
			string.format(
				"[Combate] %s: HeavyAttackHitbox FALHOU - TenteExecutarPesado: %s",
				entidade.Name,
				motivo or "?"
			)
		)
		return false, motivo
	end

	DebugPrint(
		string.format("[Combate] %s: HeavyAttackHitbox - estado mudou para AtaquePesado, criando hitbox", entidade.Name)
	)

	-- Sincroniza estado para notificar cliente que mudou para AtaquePesado
	ControladorCombate._SincronizarEstado(entidade)

	-- Cria hitbox e processa hits
	local alvos = ControladorCombate._CriarHitbox(entidade, "AtaquePesado", cframeCliente)
	for _, alvo in ipairs(alvos) do
		ControladorCombate._ProcessarHit(entidade, alvo, "AtaquePesado")
	end

	return true, nil
end

--- Processa início de bloqueio
--- @param shiftLockAtivo boolean? Estado do ShiftLock enviado pelo cliente
function ControladorCombate.ProcessarBloquear(entidade: Model, shiftLockAtivo: boolean?): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, motivo = maquina:TenteBloquear(shiftLockAtivo)

	if not sucesso then
		DebugPrint(string.format("[Combate] %s: Bloquear FALHOU - %s", entidade.Name, motivo or "?"))
		return false, motivo
	end

	DebugPrint(string.format("[Combate] %s: Bloquear OK", entidade.Name))

	-- Ajusta velocidade
	local humanoid = entidade:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Modulo_Configuracoes.ObterConfiguracao("VelocidadeBloqueando") or 6
	end

	ControladorCombate._TocarAnimacao(entidade, "Defesa", true) -- Loop

	-- Parry readiness: imediato se cooldown expirado; janela curta; senão permanece false
	local status = entidade:FindFirstChild("Status")
	local agora = tick()
	local cooldownParry = Modulo_Configuracoes.ObterConfiguracao("CooldownParry") or 2.4
	local podeParry = (agora - (maquina.dados.ultimoParry or 0)) >= cooldownParry

	if podeParry then
		maquina.dados.prontoParaAparar = true
		maquina.dados.ultimoParry = agora
		if status then
			local prontoAparar = status:FindFirstChild("ProntoAparar")
			if prontoAparar and prontoAparar:IsA("BoolValue") then
				prontoAparar.Value = true
			end
		end
		ControladorCombate._SincronizarEstado(entidade)

		-- Desativa após janela
		task.delay(Modulo_Configuracoes.ObterConfiguracao("JanelaParry") or 0.2, function()
			maquina:DesativarParry()
			if status then
				local prontoAparar = status:FindFirstChild("ProntoAparar")
				if prontoAparar and prontoAparar:IsA("BoolValue") then
					prontoAparar.Value = false
				end
			end
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
		ControladorCombate._SincronizarEstado(entidade)
	end

	return true, nil
end

--- Processa fim de bloqueio
function ControladorCombate.ProcessarPararBloqueio(entidade: Model): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, motivo = maquina:TentePararBloqueio()

	if not sucesso then
		return false, motivo
	end

	-- Atualiza Status.ProntoAparar para false
	local status = entidade:FindFirstChild("Status")
	if status then
		local prontoAparar = status:FindFirstChild("ProntoAparar")
		if prontoAparar and prontoAparar:IsA("BoolValue") then
			prontoAparar.Value = false
		end
	end

	-- NOTA: Velocidade não é mais ajustada aqui
	-- O cliente controla velocidade ao sair de defesa via AtualizarVelocidadeLocal()
	-- Isso permite restaurar corrida se Shift estiver pressionado

	-- Sincroniza estado (client irá parar animação de defesa)
	ControladorCombate._SincronizarEstado(entidade)

	return true, nil
end

--- Processa quebrar defesa própria
function ControladorCombate.ProcessarQuebrarDefesa(entidade: Model): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, motivo = maquina:TenteQuebrarDefesa()

	if not sucesso then
		return false, motivo
	end

	-- Velocidade muito lenta
	local humanoid = entidade:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Modulo_Configuracoes.ObterConfiguracao("VelocidadeDefesaQuebrada") or 3
	end

	ControladorCombate._TocarAnimacao(entidade, "DefesaQuebrada")

	return true, nil
end

--- Processa agachar
function ControladorCombate.ProcessarAgachar(entidade: Model): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, motivo = maquina:TenteAgachar()

	if not sucesso then
		DebugPrint(string.format("[Combate] %s: Agachar FALHOU - %s", entidade.Name, motivo or "?"))
		return false, motivo
	end

	DebugPrint(string.format("[Combate] %s: Agachar OK", entidade.Name))

	-- Reduz velocidade
	local humanoid = entidade:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Modulo_Configuracoes.ObterConfiguracao("VelocidadeAgachado") or 9
	end

	return true, nil
end

--- Processa levantar
function ControladorCombate.ProcessarLevantar(entidade: Model): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, motivo = maquina:TenteLevantar()

	if not sucesso then
		DebugPrint(string.format("[Combate] %s: Levantar FALHOU - %s", entidade.Name, motivo or "?"))
		return false, motivo
	end

	DebugPrint(string.format("[Combate] %s: Levantar OK", entidade.Name))

	-- Restaura velocidade
	local humanoid = entidade:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Modulo_Configuracoes.ObterConfiguracao("VelocidadeNormal") or 14
	end

	return true, nil
end

--- Processa pular
function ControladorCombate.ProcessarPular(entidade: Model)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, motivo = maquina:TentePular()

	if not sucesso then
		return false, motivo
	end

	-- O humanoid:Jump() será chamado separadamente
	return true, nil
end

--- Processa equipar modo
function ControladorCombate.ProcessarEquipar(entidade: Model, modo: string): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, motivo = maquina:TenteEquipar(modo)

	if not sucesso then
		DebugPrint(string.format("[Combate] %s: Equipar '%s' FALHOU - %s", entidade.Name, modo, motivo or "?"))
		return false, motivo
	end

	DebugPrint(string.format("[Combate] %s: Equipar '%s' OK", entidade.Name, modo))

	-- Define o novo modo
	maquina:DefinirModo(modo)

	ControladorCombate._TocarAnimacao(entidade, "Equipar")

	-- Mantém estadoAcao = Equipando até o cliente notificar que a animação terminou
	return true, nil
end

--- Processa desequipar
function ControladorCombate.ProcessarDesequipar(entidade: Model)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, motivo = maquina:TenteDesequipar()

	if not sucesso then
		return false, motivo
	end

	-- Toca animação ANTES de mudar modo (para usar animações da arma atual)
	ControladorCombate._TocarAnimacao(entidade, "Desequipar")

	-- Após animação começar, define modo Base
	task.delay(0.1, function()
		maquina:DefinirModo("Base")
		ControladorCombate._SincronizarEstado(entidade)
	end)

	-- Mantém estadoAcao = Desequipando até o cliente notificar que a animação terminou
	return true, nil
end

--- Processa inversão de animação de equipar/desequipar
--- Chamado quando o jogador toggle rapidamente entre equipar e desequipar
--- O cliente cuida de inverter a animação, aqui só atualizamos o estado
--- @param entidade Model
--- @param dados table { direcao: number, modo: string? }
function ControladorCombate.ProcessarInverterEquipAnimacao(entidade: Model, dados: { direcao: number, modo: string? })
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local direcao = dados.direcao
	local modo = dados.modo

	DebugPrint(string.format("[Combate] %s: Invertendo animação para direção %d", entidade.Name, direcao))

	if direcao == 1 then
		-- Inverteu de desequipando para equipando
		-- Define o modo alvo
		if modo then
			maquina:DefinirModo(modo)
		end
	else
		-- Inverteu de equipando para desequipando
		-- Define modo Base após animação
		task.delay(0.1, function()
			maquina:DefinirModo("Base")
			ControladorCombate._SincronizarEstado(entidade)
		end)
	end

	-- Mantém estadoAcao (Equipando/Desequipando) até o cliente notificar que a animação terminou
	return true, nil
end

--- Processa mudança de shift lock
function ControladorCombate.ProcessarShiftLock(entidade: Model, ativo: boolean)
	local maquina = ControladorCombate.ObterMaquina(entidade)
	maquina:DefinirShiftLock(ativo)

	-- Atualiza Status folder
	local status = entidade:FindFirstChild("Status")
	if status then
		local shiftLockValue = status:FindFirstChild("ShiftLockOn")
		if shiftLockValue and shiftLockValue:IsA("BoolValue") then
			shiftLockValue.Value = ativo
		end
	end
end

--- Processa começar a correr
function ControladorCombate.ProcessarCorrer(entidade: Model): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso, motivo = maquina:TenteCorrer()

	if not sucesso then
		DebugPrint(string.format("[Combate] %s: Correr FALHOU - %s", entidade.Name, motivo or "?"))
		-- Se falhou por ação em andamento, registra intenção de correr
		-- para aplicar quando a ação terminar.
		-- Além disso, permite enfileirar quando o estado é bloqueante
		-- devido a Equipando/Desequipando (comportamento esperado pelo cliente).
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

	-- NOTA: WalkSpeed não é mais ajustado aqui
	-- Corrida é 100% client-side para evitar lag e spam de requests
	-- O cliente ajusta WalkSpeed localmente via AtualizarVelocidadeLocal()

	ControladorCombate._SincronizarEstado(entidade)
	return true, nil
end

--- Processa parar de correr
function ControladorCombate.ProcessarPararCorrer(entidade: Model)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local _sucesso = maquina:TentePararCorrer()

	DebugPrint(string.format("[Combate] %s: PararCorrer OK", entidade.Name))

	-- NOTA: WalkSpeed não é mais ajustado aqui
	-- Corrida é 100% client-side para evitar lag e spam de requests
	-- O cliente ajusta WalkSpeed localmente via AtualizarVelocidadeLocal()

	-- Limpamos qualquer pedido enfileirado de corrida
	local humanoid = entidade:FindFirstChildOfClass("Humanoid")
	if humanoid then
		maquina.dados.correndoIntent = nil
	end

	ControladorCombate._SincronizarEstado(entidade)
	return true, nil
end

-- ═══════════════════════════════════════════════════════════════════
-- SISTEMA DE DASH
-- ═══════════════════════════════════════════════════════════════════

--- Processa dash
---@param entidade Model
---@param direcao string "Frente", "Tras", "Esquerda", "Direita"
function ControladorCombate.ProcessarDash(entidade: Model, direcao: string): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	-- Salva se estava correndo antes do dash para restaurar depois
	local estavaCorrendo = maquina.dados.correndo

	local sucesso, motivo = maquina:TenteDash(direcao)

	if not sucesso then
		DebugPrint(string.format("[Combate] %s: Dash FALHOU - %s", entidade.Name, motivo or "?"))
		return false, motivo
	end

	DebugPrint(string.format("[Combate] %s: Dash OK - direção=%s", entidade.Name, direcao))

	-- Se estava correndo, guarda intenção de correr para depois do dash
	if estavaCorrendo then
		(maquina.dados :: any).correndoIntent = true
	end

	-- Toca animação direcional
	local nomeAnimacao = "Dash" .. direcao -- "DashFrente", "DashTras", etc.
	local velocidadeAnim = Modulo_Configuracoes.ObterConfiguracao("VelocidadeAnimacaoDash") or 1.0
	ControladorCombate._TocarAnimacao(entidade, nomeAnimacao, false, velocidadeAnim)

	-- Atualiza status DashOn
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

--- Processa fim do dash (chamado pelo cliente quando animação termina)
function ControladorCombate.ProcessarDashTerminou(entidade: Model): (boolean, string?)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	if maquina.dados.estadoAcao ~= MaquinaDeEstados.EstadoAcao.Dashando then
		return false, "NaoEstaDashando"
	end

	maquina:CompletarDash()

	DebugPrint(string.format("[Combate] %s: Dash TERMINOU", entidade.Name))

	-- Atualiza status DashOn
	local status = entidade:FindFirstChild("Status")
	if status then
		local dashOn = status:FindFirstChild("DashOn")
		if dashOn and dashOn:IsA("BoolValue") then
			dashOn.Value = false
		end
	end

	-- Se tinha intenção de correr, restaura corrida
	local humanoid = entidade:FindFirstChildOfClass("Humanoid")
	if maquina.dados.correndoIntent then
		maquina.dados.correndoIntent = nil
		maquina.dados.correndo = true
		if humanoid then
			humanoid.WalkSpeed = Modulo_Configuracoes.ObterConfiguracao("VelocidadeCorrendo") or 21
		end
		DebugPrint(string.format("[Combate] %s: Corrida restaurada após dash", entidade.Name))
	end

	ControladorCombate._SincronizarEstado(entidade)
	return true, nil
end

--- Processa aterrissar (quando jogador toca o chão)
function ControladorCombate.ProcessarAterrissar(entidade: Model)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	local sucesso = maquina:TenteAterrissar()

	if sucesso then
		ControladorCombate._SincronizarEstado(entidade)
	end

	return sucesso
end

--- Processa sincronizar movimento (cliente envia estado de movimento)
function ControladorCombate.ProcessarSincronizarMovimento(entidade: Model, novoEstado: string)
	local maquina = ControladorCombate.ObterMaquina(entidade)

	-- Valida e define o novo estado
	local sucesso = maquina:DefinirEstadoMov(novoEstado)

	if sucesso then
		ControladorCombate._SincronizarEstado(entidade)
	end

	return sucesso
end

-- ═══════════════════════════════════════════════════════════════════
-- MAPA DE AÇÕES
-- ═══════════════════════════════════════════════════════════════════

local MapaAcoes = {
	AtacarLeveEmPe = ControladorCombate.ProcessarAtacarLeveEmPe,
	AtacarLeveAgachado = ControladorCombate.ProcessarAtacarLeveAgachado,
	CarregarPesado = ControladorCombate.ProcessarCarregarPesado,
	SoltarPesado = ControladorCombate.ProcessarSoltarPesado,
	HeavyAttackHitbox = ControladorCombate.ProcessarHeavyAttackHitbox,
	Bloquear = function(entidade, dados)
		-- Cliente envia shiftLock junto com ação de bloqueio
		local shiftLockAtivo = typeof(dados) == "table" and dados.shiftLock or nil
		return ControladorCombate.ProcessarBloquear(entidade, shiftLockAtivo)
	end,
	PararBloqueio = ControladorCombate.ProcessarPararBloqueio,
	QuebrarDefesa = ControladorCombate.ProcessarQuebrarDefesa,
	Agachar = ControladorCombate.ProcessarAgachar,
	Levantar = ControladorCombate.ProcessarLevantar,
	Pular = ControladorCombate.ProcessarPular,
	Correr = ControladorCombate.ProcessarCorrer,
	PararCorrer = ControladorCombate.ProcessarPararCorrer,
	Aterrissar = ControladorCombate.ProcessarAterrissar,
	Dash = function(entidade, dados)
		return ControladorCombate.ProcessarDash(entidade, dados)
	end,
	DashTerminou = ControladorCombate.ProcessarDashTerminou,
	SincronizarMovimento = function(entidade, dados)
		return ControladorCombate.ProcessarSincronizarMovimento(entidade, dados)
	end,
	Equipar = function(entidade, dados)
		return ControladorCombate.ProcessarEquipar(entidade, dados)
	end,
	Desequipar = ControladorCombate.ProcessarDesequipar,
	InverterEquipAnimacao = function(entidade, dados)
		return ControladorCombate.ProcessarInverterEquipAnimacao(entidade, dados)
	end,

	-- Ações de combo por marcadores
	ComboHitbox = function(entidade, dados)
		-- dados = índice do golpe (1, 2, 3, 4)
		return ControladorCombate.ProcessarComboHitbox(entidade, dados)
	end,
	ComboContinuado = function(entidade, dados)
		-- dados = índice do próximo golpe
		return ControladorCombate.ProcessarComboContinuado(entidade, dados)
	end,
	ComboTerminou = ControladorCombate.ProcessarComboTerminou,
	ComboEarlyCancel = ControladorCombate.ProcessarComboEarlyCancel,
	HeavyAttackEarlyCancel = ControladorCombate.ProcessarHeavyAttackEarlyCancel,

	-- Cancelamento de ataque por defesa
	CancelarAtaquePorDefesa = function(entidade, dados)
		-- dados = tipo do ataque ("AtaqueLeve" ou "CarregandoPesado")
		return ControladorCombate.ProcessarCancelarAtaquePorDefesa(entidade, dados)
	end,
}

--- Processa ação genérica
function ControladorCombate.ProcessarAcao(entidade: Model, acao: string, dados: any?)
	local processador = MapaAcoes[acao]
	if not processador then
		warn("[ControladorCombate] Ação desconhecida: " .. acao)
		return false, "AcaoDesconhecida"
	end

	return processador(entidade, dados)
end

-- ═══════════════════════════════════════════════════════════════════
-- CONEXÃO COM REMOTE EVENTS
-- ═══════════════════════════════════════════════════════════════════

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

EquipAnimacaoTerminou.OnServerEvent:Connect(function(player)
	local character = player.Character
	if not character then
		return
	end

	local maquina = ControladorCombate.ObterMaquina(character)
	if not maquina then
		return
	end

	local estadoAcao = maquina:ObterEstadoAcao()
	if
		estadoAcao == MaquinaDeEstados.EstadoAcao.Equipando
		or estadoAcao == MaquinaDeEstados.EstadoAcao.Desequipando
	then
		DebugPrint(string.format("[Combate] %s: Animação de equip/desequip terminou", character.Name))
		maquina:CompletarAcao()
		ControladorCombate._SincronizarEstado(character)
	end
end)

-- Recebe notificação genérica de que uma animação de AÇÃO terminou
-- Ex: AtaqueLeve, AtaquePesado, CarregandoPesado
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
	-- Só completa a ação se o que terminou no cliente for o que o servidor acha que está acontecendo
	-- Isso evita que animações anteriores interrompidas (ex: Pesado cancelado por Leve) resetem o novo estado
	if estadoAcao == nomeAcao then
		DebugPrint(
			string.format(
				"[Combate] %s: Animação de AÇÃO '%s' terminou - completando ação",
				character.Name,
				nomeAcao or "(desconhecida)"
			)
		)
		maquina:CompletarAcao()
		-- Resetar velocidade para normal
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = Modulo_Configuracoes.ObterConfiguracao("VelocidadeNormal") or 14
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

-- ═══════════════════════════════════════════════════════════════════
-- LIMPEZA
-- ═══════════════════════════════════════════════════════════════════

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		-- Aguarda pasta Status ser criada pelo Setup.lua
		local status = character:WaitForChild("Status", 5)
		if not status then
			warn("[ControladorCombate] Status não encontrado para " .. player.Name)
		end

		-- Inicializa máquina de estados para o personagem
		local _maquina = ControladorCombate.ObterMaquina(character)

		-- Sincroniza estado inicial
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

-- Inicializa para players já conectados
for _, player in ipairs(Players:GetPlayers()) do
	if player.Character then
		-- Aguarda pasta Status
		local _status = player.Character:WaitForChild("Status", 5)
		ControladorCombate.ObterMaquina(player.Character)

		-- Sincroniza estado inicial
		task.defer(function()
			ControladorCombate._SincronizarEstado(player.Character)
		end)
	end
end

DebugPrint("[ControladorCombate] Inicializado no servidor")

return ControladorCombate
