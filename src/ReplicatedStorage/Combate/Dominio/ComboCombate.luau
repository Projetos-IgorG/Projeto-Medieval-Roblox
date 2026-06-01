--!strict

--[[
    Script: ComboCombate.luau
    Caminho: src/ReplicatedStorage/Combate/Dominio
    Responsabilidade: Calcula sequencias de combo, janelas de entrada e avancos de golpes do combate.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao dispara acoes por conta propria; apenas calcula regras para o script chamador.
    Funcoes principais: DetectarMarcadores, ConfigurarListenersMarcadores, LogMarcadoresDetectados, ObterConstantesMarcadores, ConectarMarker
]]
local MARCADORES = {

	ATAQUE_DIREITA = "AttackRight",
	ATAQUE_ESQUERDA = "AttackLeft",
	ATAQUE_AMBOS = "AttackBoth",

	ATAQUE_FIM = "AttackEnd",

	COMBO_END = "ComboEnd",
	COMBO_END_FINAL = "ComboEndFinal",

	ATTACK_RELEASE = "AttackRelease",
}

export type MarcadoresDetectados = {
	temAttackRelease: boolean,
}

export type CallbacksMarcadores = {

	onAtaqueDireita: ((indice: number) -> ())?,
	onAtaqueEsquerda: ((indice: number) -> ())?,
	onAtaqueAmbos: ((indice: number) -> ())?,

	onAtaqueFim: (() -> ())?,

	onJanelaCombo: ((ehFinal: boolean) -> ())?,

	onAttackRelease: (() -> ())?,
}

local Modulo_Combo = {}

function Modulo_Combo.DetectarMarcadores(animationTrack: AnimationTrack): MarcadoresDetectados
	local resultado: MarcadoresDetectados = {
		temAttackRelease = false,
	}

	if not animationTrack then
		warn("[Modulo_Combo] AnimationTrack é nil")
		return resultado
	end

	local sucesso, erro = pcall(function()

		local releaseSignal = animationTrack:GetMarkerReachedSignal(MARCADORES.ATTACK_RELEASE)
		resultado.temAttackRelease = releaseSignal ~= nil
	end)

	if not sucesso then
		warn("[Modulo_Combo] Erro ao detectar marcadores: " .. tostring(erro))
	end

	return resultado
end

function Modulo_Combo.ConfigurarListenersMarcadores(
	animationTrack: AnimationTrack,
	callbacks: CallbacksMarcadores
): () -> ()
	local conexoes: { RBXScriptConnection } = {}

	if not animationTrack then
		warn("[Modulo_Combo] AnimationTrack é nil para configurar listeners")
		return function() end
	end

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

	end

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

	if callbacks.onAtaqueFim then
		ConectarMarker(MARCADORES.ATAQUE_FIM, function()
			callbacks.onAtaqueFim()
		end)
	end

	if callbacks.onJanelaCombo then

		ConectarMarker(MARCADORES.COMBO_END, function()
			callbacks.onJanelaCombo(false)
		end)

		ConectarMarker(MARCADORES.COMBO_END_FINAL, function()
			callbacks.onJanelaCombo(true)
		end)
	end

	if callbacks.onAttackRelease then
		ConectarMarker(MARCADORES.ATTACK_RELEASE, function()
			callbacks.onAttackRelease()
		end)
	end

	return function()
		for _, conexao in ipairs(conexoes) do
			pcall(function()
				conexao:Disconnect()
			end)
		end
		table.clear(conexoes)
	end
end

function Modulo_Combo.LogMarcadoresDetectados(marcadores: MarcadoresDetectados, nomeAnimacao: string?)
	local nome = nomeAnimacao or "Desconhecida"

	print("═══════════════════════════════════════════════════════════")
	print("[Modulo_Combo] Marcadores detectados para animação: " .. nome)
	print("───────────────────────────────────────────────────────────")
	print("  Tem AttackRelease: " .. tostring(marcadores.temAttackRelease))
	print("═══════════════════════════════════════════════════════════")
end

function Modulo_Combo.ObterConstantesMarcadores(): typeof(MARCADORES)
	return MARCADORES
end

return Modulo_Combo
