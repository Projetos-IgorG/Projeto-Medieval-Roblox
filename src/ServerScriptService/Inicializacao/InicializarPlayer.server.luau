--[[
	Script: InicializarPlayer.server.luau
	Caminho: src/ServerScriptService/Inicializacao
	Responsabilidade: Configura cada jogador ao entrar e a cada respawn (limpa acessorios nao-cabelo, normaliza WalkSpeed e unifica o rosto).
	Uso: Script de servidor; roda automaticamente em ServerScriptService/Inicializacao.
	Nao faz: Nao gerencia UI, inputs ou estado de combate; foca apenas em ajustes pos-spawn de aparencia/movimento.
	Funcoes principais: RemoverAcessoriosNaoHair, AjustarVelocidadePadrao, UnificarRosto, ConfigurarPersonagem, ConfigurarJogador
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UnificacaoFacial = require(
	ReplicatedStorage:WaitForChild("Jogador")
		:WaitForChild("Aparencia")
		:WaitForChild("UnificacaoFacial")
)
local ConfigCombate = require(
	ReplicatedStorage:WaitForChild("Combate")
		:WaitForChild("Configuracoes")
		:WaitForChild("ConfigCombate")
)

local ESCALA_MESH_HEAD_PADRAO = Vector3.new(1.25, 1.25, 1.25)

-- Toda decisao sobre Face/Head 2D fica delegada ao modulo UnificacaoFacial
-- (que internamente chama humanoid:ApplyDescriptionAsync). Nao mantemos ids
-- de face hardcoded aqui: o decal "face" e o SpecialMesh corretos sao
-- recriados pelo proprio engine quando aplicamos a HumanoidDescription.
local USAR_HEAD_PADRAO = true
local FORCAR_HEAD_CLASSICA_FALLBACK = true

-- Janela pos-spawn em que o engine ainda pode (re)inserir o script Animate ou
-- reverter a face customizada (ApplyDescriptionAsync recria partes do character).
local DURACAO_GUARDIAO_SPAWN = 8
local INTERVALO_REVALIDACAO = 0.25
local ATRASOS_VERIFICADOR_PADRAO = {0, 1, 2}

-- Reconversoes em rajada disparadas pelo vigia de Head sao limitadas para nao
-- entrar em loop caso ApplyDescriptionAsync produza efeito colateral.
local INTERVALO_MINIMO_REUNIFICACAO = 0.35

type EstadoConfiguracaoPersonagem = {
	executando: boolean,
	repetirAoFinal: boolean,
}

-- Estado por character: evita execucoes paralelas, mas ainda permite uma segunda
-- passada obrigatoria quando CharacterAppearanceLoaded termina de reaplicar o avatar.
local personagensConfigurados : {[Model]: EstadoConfiguracaoPersonagem} = {}
local ConfigurarPersonagem : ((character : Model, forcarReconfiguracao : boolean?) -> ())

local function EhAcessorioDeCabelo(accessory : Accessory): boolean
	if accessory.AccessoryType == Enum.AccessoryType.Hair then
		return true
	end
	local handle = accessory:FindFirstChild("Handle")
	return handle ~= nil and handle:FindFirstChild("HairAttachment") ~= nil
end

local function RemoverAcessoriosNaoHair(character : Model)
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Accessory") then
			if not EhAcessorioDeCabelo(child) then
				child:Destroy()
			end
		end
	end
end

local function SanearDescricaoAcessorios(humanoid : Humanoid) : boolean
	local ok, mudouOuErro = pcall(function()
		local descricao = humanoid:GetAppliedDescription()
		local acessorios = descricao:GetAccessories(true)
		local acessoriosFiltrados = {}
		local mudou = false

		for _, acessorio in ipairs(acessorios) do
			local accessoryType = acessorio.AccessoryType or Enum.AccessoryType.Unknown
			if accessoryType == Enum.AccessoryType.Hair then
				table.insert(acessoriosFiltrados, acessorio)
			else
				mudou = true
			end
		end

		if not mudou then
			return false
		end

		descricao:SetAccessories(acessoriosFiltrados, true)
		humanoid:ApplyDescriptionAsync(descricao)
		humanoid.ApplyDescriptionFinished:Wait()
		return true
	end)
	if not ok then
		warn("[InicializarPlayer] Falha ao sanear acessorios da descricao:", mudouOuErro)
		return false
	end
	return mudouOuErro == true
end

-- Aplica a HumanoidDescription "limpa": head classico, sem acessorios faciais
-- e sem acessorios extras. NAO mexe em Face: deixamos o ApplyDescriptionAsync
-- escolher a face certa (a do proprio avatar do player ou a mapeada por
-- UnificacaoFacial). Isso garante que o decal "face" no Head fisico seja
-- recriado pelo engine com a textura correta sem hardcode local.
local function AplicarDescricaoCanonica(humanoid : Humanoid) : boolean
	local ok, resultadoOuErro = pcall(function()
		local descricao = humanoid:GetAppliedDescription()
		local acessorios = descricao:GetAccessories(true)
		local acessoriosFiltrados = {}

		for _, acessorio in ipairs(acessorios) do
			local accessoryType = acessorio.AccessoryType or Enum.AccessoryType.Unknown
			if accessoryType == Enum.AccessoryType.Hair then
				table.insert(acessoriosFiltrados, acessorio)
			end
		end

		descricao:SetAccessories(acessoriosFiltrados, true)
		descricao.Head = 0

		humanoid:ApplyDescriptionAsync(descricao)
		humanoid.ApplyDescriptionFinished:Wait()
		return true
	end)
	if not ok then
		warn("[InicializarPlayer] Falha ao aplicar descricao canonica:", resultadoOuErro)
		return false
	end
	return resultadoOuErro == true
end

local function AjustarVelocidadePadrao(humanoid : Humanoid)
	local velocidade = ConfigCombate.ObterConfiguracao("VelocidadeAndando") or 14
	humanoid.WalkSpeed = velocidade
end

-- Idempotente: ConvertAnimatedHead retorna false (sem ApplyDescriptionAsync) se a
-- HumanoidDescription ja esta com Head classico, entao chamar repetido e seguro.
local function UnificarRosto(humanoid : Humanoid) : boolean
	local ok, resultadoOuErro = pcall(function()
		return UnificacaoFacial:ConvertAnimatedHead(humanoid, USAR_HEAD_PADRAO, FORCAR_HEAD_CLASSICA_FALLBACK)
	end)
	if not ok then
		warn("[UnificacaoFacial] Falha ao unificar rosto:", resultadoOuErro)
		return false
	end
	return resultadoOuErro == true
end

local function DestruirAnimateSeExistir(character : Model)
	for _, c in character:GetChildren() do
		if (c:IsA("Script") or c:IsA("LocalScript")) and c.Name == "Animate" then
			c:Destroy()
		end
	end
end

local function ObterMeshDaHead(head : Instance?) : SpecialMesh?
	if not head then
		return nil
	end
	local meshNomeado = head:FindFirstChild("Mesh")
	if meshNomeado and meshNomeado:IsA("SpecialMesh") then
		return meshNomeado
	end
	return head:FindFirstChildOfClass("SpecialMesh")
end

local function MeshDaHeadForaDoPadrao(head : Instance?) : boolean
	local mesh = ObterMeshDaHead(head)
	if not mesh then
		return true
	end
	if mesh.MeshType ~= Enum.MeshType.Head then
		return true
	end
	if mesh.MeshId ~= "" then
		return true
	end
	if mesh.TextureId ~= "" then
		return true
	end
	if mesh.Scale ~= ESCALA_MESH_HEAD_PADRAO then
		return true
	end
	return false
end

local function GarantirMeshHeadPadrao(character : Model) : boolean
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return false
	end

	local mudou = false
	local mesh = ObterMeshDaHead(head)
	if not mesh then
		mesh = Instance.new("SpecialMesh")
		mesh.Name = "Mesh"
		mesh.Parent = head
		mudou = true
	end

	if mesh.MeshType ~= Enum.MeshType.Head then
		mesh.MeshType = Enum.MeshType.Head
		mudou = true
	end
	if mesh.MeshId ~= "" then
		mesh.MeshId = ""
		mudou = true
	end
	if mesh.TextureId ~= "" then
		mesh.TextureId = ""
		mudou = true
	end
	if mesh.Scale ~= ESCALA_MESH_HEAD_PADRAO then
		mesh.Scale = ESCALA_MESH_HEAD_PADRAO
		mudou = true
	end

	return mudou
end

-- Head dinamica pode ser MeshPart/FaceControls/WrapDeformer ou a forma vista
-- nas prints: Part normal com SpecialMesh.MeshType = FileMesh.
local function EhHeadDinamica(head : Instance?): boolean
	if head == nil then
		return false
	end
	if head:IsA("MeshPart") then
		return true
	end
	if head:FindFirstChildOfClass("FaceControls") then
		return true
	end
	if head:FindFirstChildOfClass("WrapDeformer") then
		return true
	end
	if MeshDaHeadForaDoPadrao(head) then
		return true
	end
	return false
end

local function ExisteAcessorioNaoHair(character : Model): boolean
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Accessory") and not EhAcessorioDeCabelo(child) then
			return true
		end
	end
	return false
end

local function ExisteAnimate(character : Model): boolean
	for _, child in ipairs(character:GetChildren()) do
		if (child:IsA("Script") or child:IsA("LocalScript")) and child.Name == "Animate" then
			return true
		end
	end
	return false
end

local function PersonagemForaDoPadrao(character : Model): boolean
	if ExisteAnimate(character) then
		return true
	end
	if ExisteAcessorioNaoHair(character) then
		return true
	end
	if EhHeadDinamica(character:FindFirstChild("Head")) then
		return true
	end
	return false
end

local function AplicarPipelineAparenciaPadrao(character : Model, humanoid : Humanoid)
	-- Sequencia canonica unica: spawn e auto-correcao usam exatamente os mesmos
	-- passos. ApplyDescriptionAsync (dentro de UnificarRosto/AplicarDescricaoCanonica)
	-- recria Head fisico, decal "face" e SpecialMesh com a textura correta para
	-- o avatar do player. A unica correcao fisica manual mantida aqui e o
	-- SpecialMesh classico da cabeca, porque em alguns spawns o engine deixa a
	-- Part "Head" sem mesh e o avatar fica em formato de caixa.
	DestruirAnimateSeExistir(character)
	RemoverAcessoriosNaoHair(character)
	UnificarRosto(humanoid)
	if EhHeadDinamica(character:FindFirstChild("Head")) then
		AplicarDescricaoCanonica(humanoid)
	end
	SanearDescricaoAcessorios(humanoid)
	GarantirMeshHeadPadrao(character)
	DestruirAnimateSeExistir(character)
	RemoverAcessoriosNaoHair(character)
end

local function CorrigirPersonagemForaDoPadrao(character : Model, humanoid : Humanoid)
	AplicarPipelineAparenciaPadrao(character, humanoid)
end

local function VerificarPadraoUmaVez(character : Model)
	if not character.Parent then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	if PersonagemForaDoPadrao(character) then
		CorrigirPersonagemForaDoPadrao(character, humanoid)
	end
end

local function VerificarPadraoAposSpawn(character : Model, humanoid : Humanoid)
	for _, atraso in ipairs(ATRASOS_VERIFICADOR_PADRAO) do
		task.delay(atraso, function()
			if not character.Parent or humanoid.Parent == nil or humanoid.Health <= 0 then
				return
			end
			VerificarPadraoUmaVez(character)
		end)
	end
end

local function AgendarVerificacaoPadrao(character : Model)
	for _, atraso in ipairs(ATRASOS_VERIFICADOR_PADRAO) do
		task.delay(atraso, function()
			VerificarPadraoUmaVez(character)
		end)
	end
end

-- Retorna a lista de conexoes criadas, para que o chamador possa desconectar
-- quando o Head for substituido (evita acumulo de listeners entre respawns
-- ou entre reaplicacoes de HumanoidDescription).
local function VigiarHeadFisica(head : Instance, character : Model, humanoid : Humanoid) : {RBXScriptConnection}
	local conexoes : {RBXScriptConnection} = {}

	local function corrigirSeNecessario()
		if character.Parent and humanoid.Parent and humanoid.Health > 0 and PersonagemForaDoPadrao(character) then
			CorrigirPersonagemForaDoPadrao(character, humanoid)
		end
	end

	local mesh = ObterMeshDaHead(head)
	if mesh then
		table.insert(conexoes, mesh:GetPropertyChangedSignal("MeshType"):Connect(corrigirSeNecessario))
		table.insert(conexoes, mesh:GetPropertyChangedSignal("MeshId"):Connect(corrigirSeNecessario))
		table.insert(conexoes, mesh:GetPropertyChangedSignal("TextureId"):Connect(corrigirSeNecessario))
	end

	table.insert(conexoes, head.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("SpecialMesh") or descendant:IsA("FaceControls") or descendant:IsA("WrapDeformer") then
			task.defer(corrigirSeNecessario)
		end
	end))

	return conexoes
end

local function DesconectarLista(conexoes : {RBXScriptConnection})
	for i = #conexoes, 1, -1 do
		local conexao = conexoes[i]
		if conexao.Connected then
			conexao:Disconnect()
		end
		conexoes[i] = nil
	end
end

local function ConectarBloqueioAnimate(character : Model) : RBXScriptConnection
	-- Conectado ANTES de qualquer ApplyDescriptionAsync para garantir que o
	-- Animate inserido pelo engine durante a recriacao do character seja
	-- destruido na mesma frame em que aparece.
	return character.ChildAdded:Connect(function(child)
		if (child:IsA("Script") or child:IsA("LocalScript")) and child.Name == "Animate" then
			child:Destroy()
		end
	end)
end

local function ConectarBloqueioAcessorios(character : Model) : RBXScriptConnection
	return character.ChildAdded:Connect(function(child)
		if child:IsA("Accessory") and not EhAcessorioDeCabelo(child) then
			child:Destroy()
		end
	end)
end

-- Vigia persistente: se o Head fisico for substituido a qualquer momento por uma
-- versao dinamica (caso raro em que ApplyDescription do engine vence o guardiao),
-- forca uma nova passagem pelo pipeline canonico imediatamente.
-- Retorna uma funcao de cleanup que desconecta TUDO (a conexao raiz e as
-- internas do Head atual). Isso elimina memory leak entre respawns/trocas de Head.
local function ConectarVigiaHead(character : Model, humanoid : Humanoid) : () -> ()
	local ultimaTentativa = 0
	local conexoesDoHeadAtual : {RBXScriptConnection} = {}

	local function corrigirSeNecessario()
		if not (character.Parent and humanoid.Parent and humanoid.Health > 0) then
			return
		end
		if not PersonagemForaDoPadrao(character) then
			return
		end
		local agora = os.clock()
		if agora - ultimaTentativa < INTERVALO_MINIMO_REUNIFICACAO then
			return
		end
		ultimaTentativa = agora
		task.spawn(function()
			CorrigirPersonagemForaDoPadrao(character, humanoid)
		end)
	end

	local function vigiar(head : Instance)
		DesconectarLista(conexoesDoHeadAtual)
		local novas = VigiarHeadFisica(head, character, humanoid)
		for _, conexao in ipairs(novas) do
			table.insert(conexoesDoHeadAtual, conexao)
		end
		if EhHeadDinamica(head) then
			corrigirSeNecessario()
		end
	end

	local headAtual = character:FindFirstChild("Head")
	if headAtual then
		vigiar(headAtual)
	end

	local conexaoRaiz = character.ChildAdded:Connect(function(child)
		if child.Name == "Head" then
			vigiar(child)
		end
	end)

	return function()
		if conexaoRaiz.Connected then
			conexaoRaiz:Disconnect()
		end
		DesconectarLista(conexoesDoHeadAtual)
	end
end

local function GuardiaoPosSpawn(
	character : Model,
	humanoid : Humanoid,
	conexaoAnimate : RBXScriptConnection,
	conexaoAcessorios : RBXScriptConnection,
	_cleanupVigiaHead : () -> (),
	estado : EstadoConfiguracaoPersonagem
)
	task.spawn(function()
		local fim = os.clock() + DURACAO_GUARDIAO_SPAWN
		while os.clock() < fim do
			if not character.Parent or humanoid.Parent == nil or humanoid.Health <= 0 then
				break
			end
			if PersonagemForaDoPadrao(character) then
				CorrigirPersonagemForaDoPadrao(character, humanoid)
			else
				UnificarRosto(humanoid)
			end
			task.wait(INTERVALO_REVALIDACAO)
		end
		if conexaoAnimate.Connected then
			conexaoAnimate:Disconnect()
		end
		if conexaoAcessorios.Connected then
			conexaoAcessorios:Disconnect()
		end
		-- _cleanupVigiaHead permanece ativo ate AncestryChanged: o vigia precisa
		-- cobrir reaplicacoes tardias do engine alguns segundos apos a janela.

		estado.executando = false
		if estado.repetirAoFinal and character.Parent and humanoid.Parent and humanoid.Health > 0 then
			estado.repetirAoFinal = false
			task.defer(function()
				ConfigurarPersonagem(character, true)
			end)
			return
		end

		personagensConfigurados[character] = nil
	end)
end

ConfigurarPersonagem = function(character : Model, forcarReconfiguracao : boolean?)
	if not character or not character.Parent then
		return
	end
	local estado = personagensConfigurados[character]
	if not estado then
		estado = {
			executando = false,
			repetirAoFinal = false,
		}
		personagensConfigurados[character] = estado
	end

	-- CharacterAdded e CharacterAppearanceLoaded podem disparar quase ao mesmo
	-- tempo. Nao rodamos em paralelo, mas quando a carga de aparencia terminar
	-- forçamos uma segunda passada ao final da atual.
	if estado.executando then
		if forcarReconfiguracao == true then
			estado.repetirAoFinal = true
		end
		return
	end
	estado.executando = true
	estado.repetirAoFinal = false

	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid or not humanoid:IsA("Humanoid") then
		personagensConfigurados[character] = nil
		return
	end

	-- Conecta listener ANTES de UnificarRosto: ApplyDescriptionAsync pode
	-- reinserir Animate, e o ChildAdded captura na mesma frame.
	local conexaoAnimate = ConectarBloqueioAnimate(character)
	local conexaoAcessorios = ConectarBloqueioAcessorios(character)
	local cleanupVigiaHead = ConectarVigiaHead(character, humanoid)
	DestruirAnimateSeExistir(character)

	AjustarVelocidadePadrao(humanoid)
	AplicarPipelineAparenciaPadrao(character, humanoid)
	VerificarPadraoAposSpawn(character, humanoid)

	-- Apos UnificarRosto o Roblox pode ter reinserido Animate; redobramos.
	DestruirAnimateSeExistir(character)

	character.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			personagensConfigurados[character] = nil
			if conexaoAnimate.Connected then
				conexaoAnimate:Disconnect()
			end
			if conexaoAcessorios.Connected then
				conexaoAcessorios:Disconnect()
			end
			cleanupVigiaHead()
		end
	end)

	GuardiaoPosSpawn(character, humanoid, conexaoAnimate, conexaoAcessorios, cleanupVigiaHead, estado)
end

local function ConfigurarJogador(player : Player)
	player.CharacterAdded:Connect(function(character)
		ConfigurarPersonagem(character)
		AgendarVerificacaoPadrao(character)
	end)
	player.CharacterAppearanceLoaded:Connect(function(character)
		ConfigurarPersonagem(character, true)
		AgendarVerificacaoPadrao(character)
	end)
	if player.Character then
		ConfigurarPersonagem(player.Character)
		AgendarVerificacaoPadrao(player.Character)
	end
end

Players.PlayerAdded:Connect(ConfigurarJogador)
for _, player in ipairs(Players:GetPlayers()) do
	ConfigurarJogador(player)
end
