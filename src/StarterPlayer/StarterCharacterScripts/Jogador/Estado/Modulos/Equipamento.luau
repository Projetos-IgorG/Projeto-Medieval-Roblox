--[[
    Script: Equipamento.luau
    Caminho: src/StarterPlayer/StarterCharacterScripts/Jogador/Estado/Modulos
    Responsabilidade: Animacoes de equipar/desequipar, clonagem e remocao de acessorios (armas)
                      e markers de equip no servidor.
    Uso: ModuleScript; inicializado pelo ControladorEstadoPersonagem via Inicializar(ctx).
    Nao faz: Nao reproduz animacoes diretamente; delega ao modulo Animacao.
    Funcoes principais: ProcessarEquip, ObterToolEquipado, EstaEmAnimacaoEquip, PodeAlterarTool
]]

local Equipamento = {}

local ctx
local Animacao -- referencia cruzada

-- Estado de equip/desequip
local equipAnimState = {
	animacao = nil :: AnimationTrack?,
	direcao = 0,
	modoAlvo = nil :: string?,
	conexaoTermino = nil :: RBXScriptConnection?,
	tempoInicio = 0,
	armaClonada = nil :: Tool?,
	conexaoMarkerEquip = nil :: RBXScriptConnection?,
	conexaoMarkerDesequip = nil :: RBXScriptConnection?,
	acessorioJaClonado = false,
}

-- ═══════════════════════════════════════════════════════════════════
-- Helpers
-- ═══════════════════════════════════════════════════════════════════

function Equipamento.ObterToolEquipado(): Tool?
	if not ctx.Character then
		return nil
	end
	return ctx.Character:FindFirstChildOfClass("Tool") :: Tool?
end

function Equipamento.ObterAnimacaoEquip(): AnimationTrack?
	return equipAnimState.animacao
end

local function ClonarAcessorioParaJogador()
	if equipAnimState.acessorioJaClonado then
		if equipAnimState.armaClonada and equipAnimState.armaClonada.Parent then
			ctx.DebugPrint("[Equipamento] Arma já existe, ignorando")
			return
		end

		equipAnimState.acessorioJaClonado = false
		equipAnimState.armaClonada = nil
	end

	local tool = Equipamento.ObterToolEquipado()
	if not tool then
		ctx.DebugPrint("[Equipamento] Nenhum Tool equipado para criar joint de arma")
		return
	end

	local id = tool:GetAttribute("Id")
	_ = id -- reservado para uso futuro (ex: verificar categoria pelo catálogo)

	-- Estrutura flat: Handle, Lamina, HitboxPart sao filhos diretos do Tool (sem WeaponModel wrapper)
	-- Valida apenas que existe um Handle valido para o servidor criar o joint
	if not tool:FindFirstChild("Handle") then
		ctx.DebugPrint("[Equipamento] Tool sem Handle, ignorando joint:", tool.Name)
		return
	end

	ctx.EquipamentoAcao:FireServer("ClonarAcessorio", "RightArm")

	equipAnimState.acessorioJaClonado = true

	task.defer(function()
		local tentativas = 0
		while tentativas < 20 do
			if not ctx.Character then
				break
			end

			local rightArm = ctx.Character:FindFirstChild("Right Arm")
			if rightArm then
				local joint = rightArm:FindFirstChild("RightArm_WeaponJoint")
				if joint then
					equipAnimState.armaClonada = joint
					ctx.DebugPrint("[Equipamento] WeaponJoint server-side detectado:", joint.Name)
					break
				end
			end
			task.wait(0.05)
			tentativas += 1
		end
	end)

	ctx.DebugPrint("[Equipamento] Solicitação de criação de joint de arma enviada ao servidor")
end

local function RemoverAcessorioDoJogador()
	ctx.GerenciadorHitboxCliente.DestruirTodas()

	ctx.EquipamentoAcao:FireServer("RemoverAcessorio", "RightArm")

	equipAnimState.armaClonada = nil
	equipAnimState.acessorioJaClonado = false

	ctx.DebugPrint("[Equipamento] Solicitação de remoção de joint de arma enviada ao servidor")
end

local function LimparConexoesMarkersEquip()
	if equipAnimState.conexaoMarkerEquip then
		equipAnimState.conexaoMarkerEquip:Disconnect()
		equipAnimState.conexaoMarkerEquip = nil
	end
	if equipAnimState.conexaoMarkerDesequip then
		equipAnimState.conexaoMarkerDesequip:Disconnect()
		equipAnimState.conexaoMarkerDesequip = nil
	end
end

local function ConfigurarMarkersEquip(track: AnimationTrack, ehEquipar: boolean)
	LimparConexoesMarkersEquip()

	if ehEquipar then
		equipAnimState.conexaoMarkerEquip = track:GetMarkerReachedSignal("Equip"):Connect(function()
			if equipAnimState.direcao == 1 then
				ClonarAcessorioParaJogador()
				ctx.DebugPrint("[Equipamento] Marker 'Equip' atingido - acessório clonado")
			end
		end)
	else
		equipAnimState.conexaoMarkerDesequip = track:GetMarkerReachedSignal("Desequip"):Connect(function()
			if equipAnimState.direcao == -1 then
				RemoverAcessorioDoJogador()
				ctx.DebugPrint("[Equipamento] Marker 'Desequip' atingido - acessório removido")
			end
		end)
	end
end

local function OnEquipAnimacaoTerminou()
	local direcaoFinal = equipAnimState.direcao

	LimparConexoesMarkersEquip()

	if equipAnimState.conexaoTermino then
		equipAnimState.conexaoTermino:Disconnect()
		equipAnimState.conexaoTermino = nil
	end
	equipAnimState.animacao = nil
	equipAnimState.direcao = 0
	equipAnimState.modoAlvo = nil

	if direcaoFinal == 1 then
		if not equipAnimState.acessorioJaClonado then
			ClonarAcessorioParaJogador()
		end
	elseif direcaoFinal == -1 then
		RemoverAcessorioDoJogador()
	end

	if ctx.ClientBridge.OnEquipAnimacaoTerminou then
		ctx.ClientBridge.OnEquipAnimacaoTerminou(direcaoFinal)
	end

	Animacao.AtualizarAnimacaoMovimento()

	ctx.DebugPrint("[Equipamento] Animação de equipar/desequipar terminou (direção:", direcaoFinal, ")")
end

-- ═══════════════════════════════════════════════════════════════════
-- ClientBridge queries
-- ═══════════════════════════════════════════════════════════════════

function Equipamento.EstaEmAnimacaoEquip(): boolean
	return equipAnimState.animacao ~= nil and equipAnimState.animacao.IsPlaying == true
end

function Equipamento.PodeAlterarTool(): boolean
	if ctx.EstadoAtual.estadoAcao ~= "Nenhuma" then
		return false
	end

	if equipAnimState.animacao ~= nil and equipAnimState.animacao.IsPlaying then
		return false
	end

	return true
end

-- ═══════════════════════════════════════════════════════════════════
-- Chamado por Animacao.TocarAnimacaoAcao quando é equip
-- ═══════════════════════════════════════════════════════════════════

function Equipamento.ProcessarEquip(track: AnimationTrack, nomeAnimacao: string)
	if equipAnimState.conexaoTermino then
		equipAnimState.conexaoTermino:Disconnect()
	end

	local ehEquiparDirecao = (nomeAnimacao == "Equipar")

	equipAnimState.animacao = track
	equipAnimState.direcao = ehEquiparDirecao and 1 or -1
	equipAnimState.tempoInicio = os.clock()

	if ehEquiparDirecao then
		equipAnimState.acessorioJaClonado = false
	end

	ConfigurarMarkersEquip(track, ehEquiparDirecao)

	equipAnimState.conexaoTermino = track.Stopped:Connect(function()
		OnEquipAnimacaoTerminou()
	end)

	ctx.DebugPrint("[Equipamento] Animação de", nomeAnimacao, "iniciada (direção:", equipAnimState.direcao, ")")
end

-- ═══════════════════════════════════════════════════════════════════
-- Inicialização
-- ═══════════════════════════════════════════════════════════════════

function Equipamento.Inicializar(contexto)
	ctx = contexto
	Animacao = ctx.Modulos.Animacao

	-- Registrar funções no ClientBridge
	ctx.ClientBridge.EstaEmAnimacaoEquip = Equipamento.EstaEmAnimacaoEquip
	ctx.ClientBridge.PodeAlterarTool = Equipamento.PodeAlterarTool
end

return Equipamento
