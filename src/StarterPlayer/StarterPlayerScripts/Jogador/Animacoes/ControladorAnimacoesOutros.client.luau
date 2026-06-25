--[[
    Script: ControladorAnimacoesOutros.client.luau
    Caminho: src/StarterPlayer/StarterPlayerScripts/Jogador/Animacoes
    Responsabilidade: Reproduz animacoes de combate (TocarAnimacao) para personagens
        de outros jogadores no cliente local. Necessario para que o jogador local possa
        ver as animacoes de ataque dos adversarios fielmente e dar parry baseado no visual.
    Uso: LocalScript; roda automaticamente em StarterPlayerScripts.
    Nao faz: Nao controla animacoes do proprio personagem (gerenciado por
        ControladorEstadoPersonagem); nao aplica logica de combate.
    Boas praticas:
        - Cache de AnimationTrack por (character, animId) para evitar LoadAnimation
          redundante.
        - Cleanup completo quando jogador sai (PlayerRemoving / CharacterRemoving).
        - Nenhum loop de polling: usa apenas eventos reativos.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DEBUG_ENABLED = false
local function DebugPrint(...)
	if DEBUG_ENABLED then
		print(...)
	end
end

-- ─── Remotos ───────────────────────────────────────────────────────────────
local Remotos = ReplicatedStorage:WaitForChild("Remotos")
local TocarAnimacao = Remotos:WaitForChild("TocarAnimacao")

-- ─── Jogador local ─────────────────────────────────────────────────────────
local localPlayer = Players.LocalPlayer

-- ─── Estado por personagem ─────────────────────────────────────────────────
-- Mapa: character (Model) → {
--   animator: Animator,
--   trackCache: { [animId: string]: AnimationTrack },
--   trackAtivo: AnimationTrack?,
-- }
type EntradaPersonagem = {
	animator: Animator,
	trackCache: { [string]: AnimationTrack },
	trackAtivo: AnimationTrack?,
}

local estadoPersonagens: { [Model]: EntradaPersonagem } = {}

-- ─── Auxiliares ────────────────────────────────────────────────────────────

local function ObterOuCriarEntrada(character: Model): EntradaPersonagem?
	if estadoPersonagens[character] then
		return estadoPersonagens[character]
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		-- Criar Animator se ausente (personagens carregados antes do script)
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local entrada: EntradaPersonagem = {
		animator = animator :: Animator,
		trackCache = {},
		trackAtivo = nil,
	}
	estadoPersonagens[character] = entrada
	return entrada
end

local function LimparEntrada(character: Model)
	local entrada = estadoPersonagens[character]
	if not entrada then
		return
	end

	-- Parar e limpar todos os tracks em cache
	for _, track in pairs(entrada.trackCache) do
		if track.IsPlaying then
			track:Stop(0)
		end
	end

	estadoPersonagens[character] = nil
	DebugPrint("[AnimOutros] Limpou estado de:", character.Name)
end

-- ─── Tocar animacao em outro personagem ────────────────────────────────────

local function TocarAnimacaoOutro(
	character: Model,
	animId: string,
	nomeAnim: string,
	loop: boolean,
	velocidade: number,
	serverTimestamp: number?
)
	local entrada = ObterOuCriarEntrada(character)
	if not entrada then
		return
	end

	if animId == "STOP" then
		if entrada.trackAtivo and entrada.trackAtivo.IsPlaying then
			entrada.trackAtivo:Stop(0.15)
			entrada.trackAtivo = nil
		end
		-- Parar qualquer outra track de prioridade Action/Movement para forçar a parada visivel imediata
		for _, t in ipairs(entrada.animator:GetPlayingAnimationTracks()) do
			if t.Priority == Enum.AnimationPriority.Action or t.Priority == Enum.AnimationPriority.Movement then
				t:Stop(0.15)
			end
		end
		return
	end

	-- Ajuste de velocidade sem alterar a animação ativa
	if animId == "" or animId == nil then
		if entrada.trackAtivo and entrada.trackAtivo.IsPlaying then
			entrada.trackAtivo:AdjustSpeed(velocidade)
		end
		return
	end

	-- Recuperar ou carregar o track
	local track = entrada.trackCache[animId]
	if not track or not track.Animation then
		local animObj = Instance.new("Animation")
		animObj.AnimationId = animId

		local ok, resultado = pcall(function()
			return entrada.animator:LoadAnimation(animObj)
		end)
		animObj:Destroy() -- Nao precisamos mais do objeto

		if not ok or not resultado then
			DebugPrint("[AnimOutros] Falha ao carregar animacao:", animId, resultado)
			return
		end
		track = resultado :: AnimationTrack
		entrada.trackCache[animId] = track
	end

	-- Parar track anterior se diferente
	if entrada.trackAtivo and entrada.trackAtivo ~= track then
		if entrada.trackAtivo.IsPlaying then
			entrada.trackAtivo:Stop(0.15)
		end
	end

	entrada.trackAtivo = track

	-- Parar tracks de Action duplicadas e tracks com mesmo animId em um único passo
	for _, t in ipairs(entrada.animator:GetPlayingAnimationTracks()) do
		if t ~= track then
			if t.Priority == Enum.AnimationPriority.Action then
				t:Stop(0.1)
			elseif t.Animation and t.Animation.AnimationId == animId then
				t:Stop(0)
			end
		end
	end

	track.Looped = loop
	if not track.IsPlaying then
		track:Play(0.15)
	end
	track:AdjustSpeed(velocidade)

	-- Sincronização por TimePosition baseada em timestamp do servidor
	if serverTimestamp and velocidade > 0 then
		local atraso = workspace:GetServerTimeNow() - serverTimestamp
		if atraso > 0 then
			local timePosition = atraso * velocidade
			if timePosition < track.Length then
				track.TimePosition = timePosition
			else
				track:Stop(0)
			end
		end
	end

	DebugPrint(
		string.format(
			"[AnimOutros] %s: tocando '%s' (loop=%s, vel=%.1f)",
			character.Name,
			nomeAnim,
			tostring(loop),
			velocidade
		)
	)
end

-- ─── Handler do remote ─────────────────────────────────────────────────────

TocarAnimacao.OnClientEvent:Connect(
	function(entidade: Model, animId: string, nomeAnim: string, loop: boolean, velocidade: number, serverTimestamp: number?)
		-- Ignorar o proprio personagem (gerenciado por ControladorEstadoPersonagem)
		if entidade == localPlayer.Character then
			return
		end

		-- Validacoes basicas de tipo
		if typeof(entidade) ~= "Instance" or not entidade:IsA("Model") then
			return
		end

		-- Ignorar NPCs (gerenciados localmente por ControladorNPC / Views)
		if entidade:GetAttribute("NPC_Id") ~= nil then
			return
		end

		if typeof(animId) ~= "string" then
			return
		end

		TocarAnimacaoOutro(entidade, animId, nomeAnim or "", loop or false, velocidade or 1, serverTimestamp)
	end
)

-- ─── Rastrear personagens de outros jogadores ──────────────────────────────

local function AoPersonagemAdicionado(player: Player, character: Model)
	-- Pre-registrar o personagem assim que ele aparece para ter o Animator pronto
	-- quando o primeiro evento de animacao chegar.
	character:WaitForChild("Humanoid", 5)
	ObterOuCriarEntrada(character)
	DebugPrint("[AnimOutros] Personagem registrado:", player.Name)
end

local function AoPersonagemRemovido(character: Model)
	LimparEntrada(character)
end

local function AoJogadorAdicionado(player: Player)
	if player == localPlayer then
		return
	end

	if player.Character then
		task.spawn(AoPersonagemAdicionado, player, player.Character)
	end

	player.CharacterAdded:Connect(function(character)
		AoPersonagemAdicionado(player, character)
	end)

	player.CharacterRemoving:Connect(function(character)
		AoPersonagemRemovido(character)
	end)
end

-- Conectar jogadores ja presentes
for _, player in ipairs(Players:GetPlayers()) do
	AoJogadorAdicionado(player)
end

-- Conectar jogadores que entram depois
Players.PlayerAdded:Connect(AoJogadorAdicionado)

-- Limpar quando jogador sai
Players.PlayerRemoving:Connect(function(player)
	if player == localPlayer then
		return
	end
	-- CharacterRemoving deve ter sido chamado antes, mas garantimos cleanup aqui
	if player.Character then
		LimparEntrada(player.Character)
	end
end)

DebugPrint("[AnimOutros] Inicializado - escutando animacoes de outros jogadores")
