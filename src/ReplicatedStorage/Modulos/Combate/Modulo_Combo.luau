--[[
	Modulo_Combo.luau
	
	Sistema de detecção automática de marcadores de animação.
	
	Responsabilidades:
	- Detectar marcadores de animação em tempo de execução
	- Configurar listeners para keyframe markers
	- Determinar automaticamente número de golpes e janelas de combo
	- Logging estruturado para debug
	
	Marcadores suportados:
	- "Attack" (params: "1", "2", "3", ...) - Momento de criar hitbox
	- "ComboEndX" (X = 1, 2, 3, ...) - Início da janela de input
	- "AttackRelease" - Momento de carga máxima/disparo
	- "HeavyAttack" - Disparo do ataque pesado
]]

--!strict

-- ═══════════════════════════════════════════════════════════════════
-- CONSTANTES
-- ═══════════════════════════════════════════════════════════════════

local MARCADORES = {
	ATAQUE = "Attack",
	COMBO_END_PREFIX = "ComboEnd",
	ATTACK_RELEASE = "AttackRelease",
	HEAVY_ATTACK = "HeavyAttack",
}

-- ═══════════════════════════════════════════════════════════════════
-- TYPES
-- ═══════════════════════════════════════════════════════════════════

export type MarcadoresDetectados = {
	ataques: { number },
	janelasCombo: { number },
	temAttackRelease: boolean,
	temHeavyAttack: boolean,
	totalGolpes: number,
	totalJanelas: number,
}

export type CallbacksMarcadores = {
	onAtaque: ((indice: number) -> ())?,
	onJanelaCombo: ((indice: number) -> ())?,
	onAttackRelease: (() -> ())?,
	onHeavyAttack: (() -> ())?,
}

-- ═══════════════════════════════════════════════════════════════════
-- MÓDULO
-- ═══════════════════════════════════════════════════════════════════

local Modulo_Combo = {}

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES DE DETECÇÃO
-- ═══════════════════════════════════════════════════════════════════

--- Extrai o número de um marcador ComboEndX
---@param marcador string
---@return number?
local function _ExtrairNumeroComboEnd(marcador: string): number?
	local numero = marcador:match("^" .. MARCADORES.COMBO_END_PREFIX .. "(%d+)$")
	return numero and tonumber(numero) or nil
end

--- Detecta todos os marcadores presentes em uma AnimationTrack
--- NOTA: Esta função só funciona APÓS a animação ser carregada
---@param animationTrack AnimationTrack
---@return MarcadoresDetectados
function Modulo_Combo.DetectarMarcadores(animationTrack: AnimationTrack): MarcadoresDetectados
	local resultado: MarcadoresDetectados = {
		ataques = {},
		janelasCombo = {},
		temAttackRelease = false,
		temHeavyAttack = false,
		totalGolpes = 0,
		totalJanelas = 0,
	}

	if not animationTrack then
		warn("[Modulo_Combo] AnimationTrack é nil")
		return resultado
	end

	-- Usa pcall para segurança ao acessar GetMarkerReachedSignal
	local sucesso, erro = pcall(function()
		-- Infelizmente, não há API nativa para listar todos os marcadores
		-- Vamos tentar detectar os marcadores mais comuns

		-- Tenta detectar Attack 1-10
		for i = 1, 10 do
			local markerSignal = animationTrack:GetMarkerReachedSignal(MARCADORES.ATAQUE)
			if markerSignal then
				-- O marcador existe, mas não sabemos se tem parâmetro específico ainda
				-- Isso será detectado quando o marcador for atingido
				break
			end
		end

		-- Tenta detectar ComboEnd 1-10
		for i = 1, 10 do
			local markerName = MARCADORES.COMBO_END_PREFIX .. tostring(i)
			local markerSignal = animationTrack:GetMarkerReachedSignal(markerName)
			if markerSignal then
				table.insert(resultado.janelasCombo, i)
			end
		end

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

	-- Atualiza totais
	resultado.totalGolpes = #resultado.ataques
	resultado.totalJanelas = #resultado.janelasCombo

	return resultado
end

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES DE CONFIGURAÇÃO DE LISTENERS
-- ═══════════════════════════════════════════════════════════════════

--- Configura listeners para todos os marcadores de uma animação
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

	-- Listener para marcador Attack (com parâmetro numérico)
	if callbacks.onAtaque then
		local sucesso, erro = pcall(function()
			local conexao = animationTrack:GetMarkerReachedSignal(MARCADORES.ATAQUE):Connect(function(param)
				local indice = tonumber(param)
				if indice then
					local ok, callbackErro = pcall(function()
						callbacks.onAtaque(indice)
					end)
					if not ok then
						warn("[Modulo_Combo] Erro no callback onAtaque: " .. tostring(callbackErro))
					end
				else
					warn("[Modulo_Combo] Parâmetro inválido para Attack: " .. tostring(param))
				end
			end)
			table.insert(conexoes, conexao)
		end)

		if not sucesso then
			warn("[Modulo_Combo] Erro ao configurar listener Attack: " .. tostring(erro))
		end
	end

	-- Listeners para marcadores ComboEnd1, ComboEnd2, etc.
	if callbacks.onJanelaCombo then
		for i = 1, 10 do
			local markerName = MARCADORES.COMBO_END_PREFIX .. tostring(i)

			local _sucesso, _erro = pcall(function()
				local conexao = animationTrack:GetMarkerReachedSignal(markerName):Connect(function()
					local ok, callbackErro = pcall(function()
						callbacks.onJanelaCombo(i)
					end)
					if not ok then
						warn("[Modulo_Combo] Erro no callback onJanelaCombo: " .. tostring(callbackErro))
					end
				end)
				table.insert(conexoes, conexao)
			end)

			-- Não reporta erro, pois é esperado que nem todos os marcadores existam
		end
	end

	-- Listener para AttackRelease
	if callbacks.onAttackRelease then
		local _sucesso, _erro = pcall(function()
			local conexao = animationTrack:GetMarkerReachedSignal(MARCADORES.ATTACK_RELEASE):Connect(function()
				local ok, callbackErro = pcall(function()
					callbacks.onAttackRelease()
				end)
				if not ok then
					warn("[Modulo_Combo] Erro no callback onAttackRelease: " .. tostring(callbackErro))
				end
			end)
			table.insert(conexoes, conexao)
		end)

		-- Erro ignorado: esperado que nem todas animações tenham esse marcador
	end

	-- Listener para HeavyAttack
	if callbacks.onHeavyAttack then
		local _sucesso, _erro = pcall(function()
			local conexao = animationTrack:GetMarkerReachedSignal(MARCADORES.HEAVY_ATTACK):Connect(function()
				local ok, callbackErro = pcall(function()
					callbacks.onHeavyAttack()
				end)
				if not ok then
					warn("[Modulo_Combo] Erro no callback onHeavyAttack: " .. tostring(callbackErro))
				end
			end)
			table.insert(conexoes, conexao)
		end)

		-- Erro ignorado: esperado que nem todas animações tenham esse marcador
	end

	-- Retorna função de limpeza
	return function()
		for _, conexao in ipairs(conexoes) do
			local _ok, _ = pcall(function()
				conexao:Disconnect()
			end)
		end
		table.clear(conexoes)
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES DE UTILIDADE
-- ═══════════════════════════════════════════════════════════════════

--- Determina o tipo de ataque baseado no índice e total de golpes
---@param indice number Índice do golpe atual (1, 2, 3, ...)
---@param totalGolpes number Total de golpes na animação
---@return string Tipo de ataque ("AtaqueLeve", "AtaqueLeveFinal", "AtaquePesado")
function Modulo_Combo.DeterminarTipoAtaque(indice: number, totalGolpes: number): string
	-- Se é o último golpe do combo, é AtaqueLeveFinal
	if indice >= totalGolpes and totalGolpes > 1 then
		return "AtaqueLeveFinal"
	end

	return "AtaqueLeve"
end

--- Verifica se o índice é o último golpe do combo
---@param indice number
---@param totalGolpes number
---@return boolean
function Modulo_Combo.EhGolpeFinal(indice: number, totalGolpes: number): boolean
	return indice >= totalGolpes
end

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES DE LOGGING
-- ═══════════════════════════════════════════════════════════════════

--- Log estruturado dos marcadores detectados (para debug)
---@param marcadores MarcadoresDetectados
---@param nomeAnimacao string?
function Modulo_Combo.LogMarcadoresDetectados(marcadores: MarcadoresDetectados, nomeAnimacao: string?)
	local nome = nomeAnimacao or "Desconhecida"

	print(
		"═══════════════════════════════════════════════════════════"
	)
	print("[Modulo_Combo] Marcadores detectados para animação: " .. nome)
	print(
		"───────────────────────────────────────────────────────────"
	)
	print("  Ataques: " .. table.concat(marcadores.ataques, ", "))
	print("  Janelas de Combo: " .. table.concat(marcadores.janelasCombo, ", "))
	print("  Tem AttackRelease: " .. tostring(marcadores.temAttackRelease))
	print("  Tem HeavyAttack: " .. tostring(marcadores.temHeavyAttack))
	print("  Total de Golpes: " .. marcadores.totalGolpes)
	print("  Total de Janelas: " .. marcadores.totalJanelas)
	print(
		"═══════════════════════════════════════════════════════════"
	)
end

--- Retorna as constantes de marcadores (para uso externo se necessário)
function Modulo_Combo.ObterConstantesMarcadores(): typeof(MARCADORES)
	return MARCADORES
end

return Modulo_Combo
