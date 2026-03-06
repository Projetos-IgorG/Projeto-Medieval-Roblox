--[[
	Modulo_Combo.luau
	
	Sistema de detecção e escuta de marcadores de animação de combate.
	
	Responsabilidades:
	- Configurar listeners para keyframe markers automaticamente
	- Gerenciar callbacks para eventos de ataque, janelas de combo e fim de hitbox
	- Interface limpa sem necessidade de configurar nomes de markers
	
	═══════════════════════════════════════════════════════════════════
	MARCADORES DE ANIMAÇÃO (definidos no Roblox Studio):
	═══════════════════════════════════════════════════════════════════
	
	┌───────────────────┬────────────────────────────────────────────────┐
	│ MARCADOR          │ DESCRIÇÃO                                      │
	├───────────────────┼────────────────────────────────────────────────┤
	│ AttackRight       │ Inicia hitbox da mão direita (param: índice)   │
	│ AttackLeft        │ Inicia hitbox da mão esquerda (param: índice)  │
	│ AttackBoth        │ Inicia hitbox de ambas as mãos (param: índice) │
	│ AttackEnd         │ Finaliza hitboxes de ataque leve               │
	├───────────────────┼────────────────────────────────────────────────┤
	│ ComboEnd          │ Janela de input para continuar combo           │
	│ ComboEndFinal     │ Última janela do combo (golpe final chegando)  │
	├───────────────────┼────────────────────────────────────────────────┤
	│ AttackRelease     │ Ponto de liberação do ataque pesado carregado  │
	│ HeavyAttack       │ Execução do ataque pesado (genérico)           │
	├───────────────────┼────────────────────────────────────────────────┤
	│ HeavyAttackRight  │ Inicia hitbox pesado da mão direita            │
	│ HeavyAttackLeft   │ Inicia hitbox pesado da mão esquerda           │
	│ HeavyAttackBoth   │ Inicia hitbox pesado de ambas as mãos          │
	│ HeavyAttackEnd    │ Finaliza hitboxes de ataque pesado             │
	└───────────────────┴────────────────────────────────────────────────┘
	
	NOTA: Parâmetros são passados como string ("1", "2", "3"...).
	      ComboEnd/ComboEndFinal não precisam de parâmetros.
	      HeavyAttack* não precisam de parâmetros (um golpe por ataque).
]]

--!strict

-- ═══════════════════════════════════════════════════════════════════
-- CONSTANTES
-- ═══════════════════════════════════════════════════════════════════

local MARCADORES = {
	-- Markers de ataque leve por mão (iniciam hitbox)
	ATAQUE_DIREITA = "AttackRight",
	ATAQUE_ESQUERDA = "AttackLeft",
	ATAQUE_AMBOS = "AttackBoth",
	
	-- Marker de fim de hitbox (ataque leve)
	ATAQUE_FIM = "AttackEnd",

	-- Markers de janela de combo
	COMBO_END = "ComboEnd",
	COMBO_END_FINAL = "ComboEndFinal",

	-- Markers de ataque pesado (controle de carga)
	ATTACK_RELEASE = "AttackRelease",
	HEAVY_ATTACK = "HeavyAttack",
	
	-- Markers de ataque pesado por mão (iniciam hitbox)
	HEAVY_ATAQUE_DIREITA = "HeavyAttackRight",
	HEAVY_ATAQUE_ESQUERDA = "HeavyAttackLeft",
	HEAVY_ATAQUE_AMBOS = "HeavyAttackBoth",
	
	-- Marker de fim de hitbox (ataque pesado)
	HEAVY_ATAQUE_FIM = "HeavyAttackEnd",
}

-- ═══════════════════════════════════════════════════════════════════
-- TYPES
-- ═══════════════════════════════════════════════════════════════════

export type MarcadoresDetectados = {
	temAttackRelease: boolean,
	temHeavyAttack: boolean,
}

export type CallbacksMarcadores = {
	--- Callbacks de ataque leve por mão (recebem índice do golpe)
	onAtaqueDireita: ((indice: number) -> ())?,
	onAtaqueEsquerda: ((indice: number) -> ())?,
	onAtaqueAmbos: ((indice: number) -> ())?,
	
	--- Callback de fim de hitbox (ataque leve)
	onAtaqueFim: (() -> ())?,

	--- Callbacks de janela de combo
	onJanelaCombo: ((ehFinal: boolean) -> ())?,

	--- Callbacks de ataque pesado (controle de carga)
	onAttackRelease: (() -> ())?,
	onHeavyAttack: (() -> ())?,
	
	--- Callbacks de ataque pesado por mão (iniciam hitbox)
	onHeavyAtaqueDireita: (() -> ())?,
	onHeavyAtaqueEsquerda: (() -> ())?,
	onHeavyAtaqueAmbos: (() -> ())?,
	
	--- Callback de fim de hitbox (ataque pesado)
	onHeavyAtaqueFim: (() -> ())?,
}

-- ═══════════════════════════════════════════════════════════════════
-- MÓDULO
-- ═══════════════════════════════════════════════════════════════════

local Modulo_Combo = {}

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES DE DETECÇÃO
-- ═══════════════════════════════════════════════════════════════════

--- Detecta marcadores especiais presentes em uma AnimationTrack
--- NOTA: Esta função só funciona APÓS a animação ser carregada
---@param animationTrack AnimationTrack
---@return MarcadoresDetectados
function Modulo_Combo.DetectarMarcadores(animationTrack: AnimationTrack): MarcadoresDetectados
	local resultado: MarcadoresDetectados = {
		temAttackRelease = false,
		temHeavyAttack = false,
	}

	if not animationTrack then
		warn("[Modulo_Combo] AnimationTrack é nil")
		return resultado
	end

	-- Usa pcall para segurança ao acessar GetMarkerReachedSignal
	local sucesso, erro = pcall(function()
		-- Detecta AttackRelease
		local releaseSignal = animationTrack:GetMarkerReachedSignal(MARCADORES.ATTACK_RELEASE)
		resultado.temAttackRelease = releaseSignal ~= nil

		-- Detecta HeavyAttack
		local heavySignal = animationTrack:GetMarkerReachedSignal(MARCADORES.HEAVY_ATTACK)
		resultado.temHeavyAttack = heavySignal ~= nil
	end)

	if not sucesso then
		warn("[Modulo_Combo] Erro ao detectar marcadores: " .. tostring(erro))
	end

	return resultado
end

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES DE CONFIGURAÇÃO DE LISTENERS
-- ═══════════════════════════════════════════════════════════════════

--- Configura listeners para todos os marcadores de uma animação.
--- Os nomes dos markers são definidos internamente — o consumidor só passa callbacks.
---@param animationTrack AnimationTrack
---@param callbacks CallbacksMarcadores
---@return () -> () Função de limpeza para desconectar todos os listeners
function Modulo_Combo.ConfigurarListenersMarcadores(
	animationTrack: AnimationTrack,
	callbacks: CallbacksMarcadores
): () -> ()
	local conexoes: { RBXScriptConnection } = {}

	if not animationTrack then
		warn("[Modulo_Combo] AnimationTrack é nil para configurar listeners")
		return function() end
	end

	-- Helper: conecta um marker de forma segura (ignora erro se marker não existe)
	local function ConectarMarker(markerName: string, callback: (...any) -> ())
		local _sucesso, _erro = pcall(function()
			local conexao = animationTrack:GetMarkerReachedSignal(markerName):Connect(function(param)
				local ok, callbackErro = pcall(function()
					callback(param)
				end)
				if not ok then
					warn("[Modulo_Combo] Erro no callback " .. markerName .. ": " .. tostring(callbackErro))
				end
			end)
			table.insert(conexoes, conexao)
		end)
		-- Erro ignorado: esperado que nem todos os markers existam
	end

	-- ═══════════════════════════════════════════════════════════════
	-- LISTENERS DE ATAQUE (iniciam hitbox)
	-- ═══════════════════════════════════════════════════════════════
	
	if callbacks.onAtaqueDireita then
		ConectarMarker(MARCADORES.ATAQUE_DIREITA, function(param)
			callbacks.onAtaqueDireita(tonumber(param) or 1)
		end)
	end

	if callbacks.onAtaqueEsquerda then
		ConectarMarker(MARCADORES.ATAQUE_ESQUERDA, function(param)
			callbacks.onAtaqueEsquerda(tonumber(param) or 1)
		end)
	end

	if callbacks.onAtaqueAmbos then
		ConectarMarker(MARCADORES.ATAQUE_AMBOS, function(param)
			callbacks.onAtaqueAmbos(tonumber(param) or 1)
		end)
	end

	-- ═══════════════════════════════════════════════════════════════
	-- LISTENER DE FIM DE HITBOX
	-- ═══════════════════════════════════════════════════════════════
	
	if callbacks.onAtaqueFim then
		ConectarMarker(MARCADORES.ATAQUE_FIM, function()
			callbacks.onAtaqueFim()
		end)
	end

	-- ═══════════════════════════════════════════════════════════════
	-- LISTENERS DE JANELA DE COMBO
	-- ═══════════════════════════════════════════════════════════════
	
	if callbacks.onJanelaCombo then
		-- ComboEnd: janela intermediária (ehFinal = false)
		ConectarMarker(MARCADORES.COMBO_END, function()
			callbacks.onJanelaCombo(false)
		end)
		
		-- ComboEndFinal: última janela antes do golpe final (ehFinal = true)
		ConectarMarker(MARCADORES.COMBO_END_FINAL, function()
			callbacks.onJanelaCombo(true)
		end)
	end

	-- ═══════════════════════════════════════════════════════════════
	-- LISTENERS DE ATAQUE PESADO (controle de carga)
	-- ═══════════════════════════════════════════════════════════════
	
	if callbacks.onAttackRelease then
		ConectarMarker(MARCADORES.ATTACK_RELEASE, function()
			callbacks.onAttackRelease()
		end)
	end

	if callbacks.onHeavyAttack then
		ConectarMarker(MARCADORES.HEAVY_ATTACK, function()
			callbacks.onHeavyAttack()
		end)
	end

	-- ═══════════════════════════════════════════════════════════════
	-- LISTENERS DE HITBOX DE ATAQUE PESADO (por mão)
	-- ═══════════════════════════════════════════════════════════════
	
	if callbacks.onHeavyAtaqueDireita then
		ConectarMarker(MARCADORES.HEAVY_ATAQUE_DIREITA, function()
			callbacks.onHeavyAtaqueDireita()
		end)
	end

	if callbacks.onHeavyAtaqueEsquerda then
		ConectarMarker(MARCADORES.HEAVY_ATAQUE_ESQUERDA, function()
			callbacks.onHeavyAtaqueEsquerda()
		end)
	end

	if callbacks.onHeavyAtaqueAmbos then
		ConectarMarker(MARCADORES.HEAVY_ATAQUE_AMBOS, function()
			callbacks.onHeavyAtaqueAmbos()
		end)
	end

	if callbacks.onHeavyAtaqueFim then
		ConectarMarker(MARCADORES.HEAVY_ATAQUE_FIM, function()
			callbacks.onHeavyAtaqueFim()
		end)
	end

	-- ═══════════════════════════════════════════════════════════════
	-- FUNÇÃO DE LIMPEZA
	-- ═══════════════════════════════════════════════════════════════
	
	return function()
		for _, conexao in ipairs(conexoes) do
			pcall(function()
				conexao:Disconnect()
			end)
		end
		table.clear(conexoes)
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES DE UTILIDADE
-- ═══════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES DE LOGGING
-- ═══════════════════════════════════════════════════════════════════

--- Log estruturado dos marcadores detectados (para debug)
---@param marcadores MarcadoresDetectados
---@param nomeAnimacao string?
function Modulo_Combo.LogMarcadoresDetectados(marcadores: MarcadoresDetectados, nomeAnimacao: string?)
	local nome = nomeAnimacao or "Desconhecida"

	print("═══════════════════════════════════════════════════════════")
	print("[Modulo_Combo] Marcadores detectados para animação: " .. nome)
	print("───────────────────────────────────────────────────────────")
	print("  Tem AttackRelease: " .. tostring(marcadores.temAttackRelease))
	print("  Tem HeavyAttack: " .. tostring(marcadores.temHeavyAttack))
	print("═══════════════════════════════════════════════════════════")
end

--- Retorna as constantes de marcadores (para uso externo se necessário)
function Modulo_Combo.ObterConstantesMarcadores(): typeof(MARCADORES)
	return MARCADORES
end

return Modulo_Combo
