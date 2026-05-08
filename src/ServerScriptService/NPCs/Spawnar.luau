--!nonstrict
--[[
	Script: Spawnar.luau
	Caminho: src/ServerScriptService/NPCs
	Responsabilidade: Spawnar NPC R6 visivel no servidor. Suporta:
	  - templateId "__Player__": cria avatar R6 do player (CreateHumanoidModelFromUserId R6).
	  - templateId catalogado: clona Model/Folder do catalogo.
	  - opts.armaTipo + opts.armaId: equipa Tool do catalogo (ReplicatedStorage.Equipamentos.Modelos.<tipo>.<id>).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local CatalogoNPCs = require(ReplicatedStorage:WaitForChild("NPCs"):WaitForChild("CatalogoNPCs"))
local CatalogoIAs = require(ReplicatedStorage:WaitForChild("NPCs"):WaitForChild("CatalogoIAs"))
local Especies = require(ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("Especies"))

local pastaNPCsServer = ServerScriptService:WaitForChild("NPCs")
local IAFolder = pastaNPCsServer:WaitForChild("IA")
local FabricaIA = require(IAFolder:WaitForChild("FabricaIA"))
local GerenciadorIA = require(IAFolder:WaitForChild("GerenciadorIA"))

local pastaEntidadesServer = ServerScriptService:WaitForChild("Entidades")
local GerenciadorEntidades = require(pastaEntidadesServer:WaitForChild("GerenciadorEntidades"))

local pastaEquipModelos = ReplicatedStorage:WaitForChild("Equipamentos"):WaitForChild("Modelos")

local Spawnar = {}

local DEBUG = true
local function dbg(...)
	if DEBUG then
		print("[SpawnarNPC]", ...)
	end
end
local function dbgWarn(...)
	if DEBUG then
		warn("[SpawnarNPC]", ...)
	end
end

export type OpcoesSpawn = {
	templateId: string,
	nomeFinal: string?,
	cframe: CFrame,
	especie: string?,
	registrarEntidade: boolean?,
	iaId: string?,
	hostil: boolean?,
	playerOrigem: Player?,
	armaTipo: string?, -- ex: "Armas"
	armaId: string?, -- ex: "espada_ferro"
}

local function obterPastaNPCsWorkspace(): Folder
	local pasta = workspace:FindFirstChild("NPCs")
	if not pasta then
		pasta = Instance.new("Folder")
		pasta.Name = "NPCs"
		pasta.Parent = workspace
	end
	return pasta :: Folder
end

local function garantirPrimaryPart(modelo: Model)
	local hrp = modelo:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		modelo.PrimaryPart = hrp
		return
	end
	if modelo.PrimaryPart and modelo.PrimaryPart.Parent == modelo then
		return
	end
	for _, d in modelo:GetDescendants() do
		if d:IsA("BasePart") then
			modelo.PrimaryPart = d
			return
		end
	end
end

local function posicionar(modelo: Model, cframe: CFrame)
	garantirPrimaryPart(modelo)
	if modelo.PrimaryPart then
		modelo:PivotTo(cframe)
	end
end

local function folderParaModel(folder: Folder, nomeFinal: string?): Model
	local modelo = Instance.new("Model")
	modelo.Name = nomeFinal or folder.Name
	for _, filho in folder:GetChildren() do
		filho.Parent = modelo
	end
	for atributo, valor in folder:GetAttributes() do
		modelo:SetAttribute(atributo, valor)
	end
	return modelo
end

local function clonarTemplate(template: Instance, nomeFinal: string?): Model?
	local clone = template:Clone()
	if clone:IsA("Model") then
		if nomeFinal and nomeFinal ~= "" then
			clone.Name = nomeFinal
		end
		return clone
	elseif clone:IsA("Folder") then
		return folderParaModel(clone :: Folder, nomeFinal)
	end
	clone:Destroy()
	return nil
end

-- Cria avatar R6 do player. Animate vai junto e funciona em NPC server-side.
local function criarRigR6DePlayer(player: Player, nomeFinal: string?): (Model?, string?)
	dbg("criarRigR6DePlayer: player=", player.Name, "userId=", player.UserId)

	local modelo: Model? = nil
	local ok, retorno = pcall(function()
		return Players:CreateHumanoidModelFromUserId(player.UserId, Enum.HumanoidRigType.R6)
	end)
	if ok and retorno and (retorno :: any):IsA("Model") then
		modelo = retorno
		dbg("criarRigR6DePlayer: API OK")
	else
		return nil, "CreateHumanoidModelFromUserId R6 falhou: " .. tostring(retorno)
	end

	assert(modelo, "modelo nil")

	modelo.Name = (nomeFinal and nomeFinal ~= "") and nomeFinal or ("NPC_" .. player.Name)

	-- copia atributos relevantes do char original (Ent_*, ModoCombate, etc).
	local char = player.Character
	if char then
		for atributo, valor in char:GetAttributes() do
			modelo:SetAttribute(atributo, valor)
		end
	end

	garantirPrimaryPart(modelo)

	local h = modelo:FindFirstChildOfClass("Humanoid")
	if h then
		h.Health = h.MaxHealth
		h.BreakJointsOnDeath = true
		h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		h.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn
		pcall(function()
			h:SetStateEnabled(Enum.HumanoidStateType.Climbing, true)
			h:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
			h:SetStateEnabled(Enum.HumanoidStateType.Freefall, true)
			h:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
			h:SetStateEnabled(Enum.HumanoidStateType.Landed, true)
		end)
	end

	return modelo, nil
end

-- Inferir modo de combate a partir do nome/dados da tool.
local function inferirModoCombate(tool: Instance): string
	local dados = tool:FindFirstChild("Dados")
	if dados then
		local modo = dados:FindFirstChild("Modo")
		if modo and modo:IsA("StringValue") and modo.Value ~= "" then
			return modo.Value
		end
	end
	-- fallback pelo nome
	local n = string.lower(tool.Name)
	if string.find(n, "espada") then
		return "EspadaUmaMao"
	elseif string.find(n, "machado") then
		return "Machado"
	elseif string.find(n, "arco") then
		return "Arco"
	end
	return "Punhos"
end

local function limparEstadoArma(npc: Model)
	for _, filho in npc:GetChildren() do
		if filho:IsA("Tool") then
			filho:Destroy()
		end
	end

	npc:SetAttribute("ModoCombate", "Punhos")
	npc:SetAttribute("NPC_ArmaVisualId", nil)
	npc:SetAttribute("NPC_ArmaDanoId", nil)
	npc:SetAttribute("NPC_ArmaTipo", nil)
end

-- Equipa arma no NPC: clona Tool de ReplicatedStorage.Equipamentos.Modelos.<tipo>.<id>
-- e parenta no Model (com Humanoid presente, fica equipada automaticamente).
local function equiparArma(npc: Model, armaTipo: string, armaId: string): (boolean, string?)
	local pastaTipo = pastaEquipModelos:FindFirstChild(armaTipo)
	if not pastaTipo then
		return false, "Tipo arma nao encontrado: " .. armaTipo
	end
	local template = pastaTipo:FindFirstChild(armaId)
	if not template then
		return false, "Arma nao encontrada: " .. armaTipo .. "/" .. armaId
	end
	-- template pode ser Tool, Model ou Folder. Tentamos primeiro Tool.
	local tool: Tool? = nil
	if template:IsA("Tool") then
		tool = template:Clone()
	else
		-- procura uma Tool dentro do template
		local toolDentro = template:FindFirstChildWhichIsA("Tool", true)
		if toolDentro then
			tool = toolDentro:Clone()
		end
	end
	if not tool then
		return false, "Template nao contem uma Tool: " .. armaId
	end

	tool.Parent = npc -- com Humanoid presente, vira "equipada"

	local modo = inferirModoCombate(tool)
	npc:SetAttribute("ModoCombate", modo)
	dbg("arma equipada:", tool.Name, "modo=", modo)
	return true, nil
end

function Spawnar.SpawnarNPC(opts: OpcoesSpawn): (Model?, string?)
	dbg("=== SpawnarNPC iniciado ===")
	dbg(
		"templateId=",
		opts.templateId,
		"nomeFinal=",
		opts.nomeFinal,
		"iaId=",
		opts.iaId,
		"hostil=",
		opts.hostil,
		"armaTipo=",
		opts.armaTipo,
		"armaId=",
		opts.armaId,
		"playerOrigem=",
		opts.playerOrigem and opts.playerOrigem.Name
	)

	local defNPC = CatalogoNPCs.Obter(opts.templateId)

	local npc: Model? = nil

	if opts.templateId == "__Player__" then
		if not opts.playerOrigem then
			return nil, "Clone do jogador exige playerOrigem"
		end
		local rig, err = criarRigR6DePlayer(opts.playerOrigem, opts.nomeFinal)
		if not rig then
			return nil, err
		end
		npc = rig
	else
		local template = CatalogoNPCs.ObterTemplate(opts.templateId)
		if not template then
			return nil, "Template NPC nao encontrado: " .. tostring(opts.templateId)
		end
		npc = clonarTemplate(template, opts.nomeFinal)
		if not npc then
			return nil, "Falha ao clonar template: " .. tostring(opts.templateId)
		end
	end

	assert(npc, "npc nil apos criacao")

	npc.Parent = obterPastaNPCsWorkspace()
	posicionar(npc, opts.cframe)
	dbg("npc posicionado em", npc:GetPivot().Position)

	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local hrp = npc:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			pcall(function()
				hrp:SetNetworkOwner(nil)
			end)
		end
	end

	-- Equipar arma se solicitado.
	if opts.armaTipo and opts.armaId and opts.armaTipo ~= "" and opts.armaId ~= "" then
		limparEstadoArma(npc)
		local ok, errArma = equiparArma(npc, opts.armaTipo, opts.armaId)
		if not ok then
			dbgWarn("equiparArma falhou:", errArma)
		end
	else
		limparEstadoArma(npc)
	end

	-- Especie + Entidade
	local especieId = opts.especie or (defNPC and defNPC.especiePadrao)
	local registrar = opts.registrarEntidade
	if registrar == nil then
		registrar = defNPC and defNPC.registrarEntidadePadrao or false
	end

	local entidade: any = nil
	if registrar and especieId and Especies.Existe(especieId) then
		entidade = GerenciadorEntidades.Registrar(npc, especieId)
	end

	if opts.hostil ~= nil then
		npc:SetAttribute("Hostil", opts.hostil)
	end

	-- IA
	local iaId = opts.iaId or (defNPC and defNPC.iaPadrao) or CatalogoIAs.PADRAO
	local aviso: string? = nil

	if iaId and iaId ~= "Nenhuma" then
		if not humanoid then
			aviso = "NPC criado mas sem Humanoid; IA '" .. iaId .. "' ignorada"
		elseif not CatalogoIAs.Existe(iaId) then
			aviso = "NPC criado mas IA invalida: " .. tostring(iaId)
		else
			local defIA = CatalogoIAs.Obter(iaId)
			if defIA and defIA.requerEntidade and not entidade then
				aviso = "NPC criado mas IA '" .. iaId .. "' requer entidade"
			else
				local ia = FabricaIA.Criar(iaId, npc)
				if not ia then
					aviso = "NPC criado mas falhou ao instanciar IA: " .. iaId
				else
					if entidade then
						ia:vincularEntidade(entidade)
					end
					GerenciadorIA.Registrar(npc, ia)
				end
			end
		end
	end

	dbg("=== SpawnarNPC concluido ===", "npc=", npc.Name, "aviso=", aviso)
	return npc, aviso
end

return Spawnar
