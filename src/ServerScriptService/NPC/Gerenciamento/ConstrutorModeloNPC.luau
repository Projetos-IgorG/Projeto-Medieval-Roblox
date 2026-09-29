--!strict

--[[
	Script: ConstrutorModeloNPC.luau
	Caminho: src/ServerScriptService/NPC/Gerenciamento
	Responsabilidade: Construir o Model fisico do NPC a partir das opcoes de
	spawn (template de ReplicatedStorage, aparencia de player ou rig padrao).

	Correcao em relacao ao codigo antigo:
	- Ao clonar o personagem de um player, as Tools carregadas pelo player
	  eram clonadas junto (o NPC nascia "segurando" a Tool do player e a
	  resolucao de arma via Tool fisica pegava a arma errada). Agora as Tools
	  sao removidas da copia.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConstrutorModeloNPC = {}

local function prepararModelo(modelo: Model, nome: string?)
	if nome and nome ~= "" then
		modelo.Name = nome
	end

	local hum = modelo:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.BreakJointsOnDeath = false -- ragdoll cuida da morte
	end

	local hrp = modelo:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		modelo.PrimaryPart = hrp
	end

	for _, desc in modelo:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Anchored = false
		elseif desc:IsA("Motor6D") and desc.Name:match("WeaponJoint") then
			desc:Destroy()
		end
	end

	for _, child in modelo:GetChildren() do
		if
			child:IsA("Tool")
			or child:IsA("Model") and (child.Name:match("^WeaponModel") or child.Name == "WeaponVisual")
		then
			child:Destroy()
		end
	end
end

local function clonarPersonagemDoPlayer(player: Player, nome: string?): Model?
	local char = player.Character
	if not char then
		return nil
	end

	char.Archivable = true
	local copia = char:Clone()
	char.Archivable = false
	if not copia then
		return nil
	end

	-- FIX: nunca herdar Tools, WeaponModels ou joints de arma do player
	-- (arma do NPC é gerenciada exclusivamente via NPC_ArmaEquipadaId e view local do cliente).
	for _, child in copia:GetChildren() do
		if
			child:IsA("Tool")
			or child:IsA("Model") and (child.Name:match("^WeaponModel") or child.Name == "WeaponVisual")
		then
			child:Destroy()
		end
	end

	-- Scripts do personagem do player nao devem rodar no NPC, e joints de armas
	-- herdadas do player (ex: RightArm_WeaponJoint) devem ser removidos.
	for _, desc in copia:GetDescendants() do
		if
			desc:IsA("BaseScript")
			or desc:IsA("ForceField")
			or desc:IsA("Motor6D") and desc.Name:match("WeaponJoint")
		then
			desc:Destroy()
		end
	end

	prepararModelo(copia, nome or (player.Name .. "_NPC"))
	return copia
end

local function buscarTemplate(nomeTemplate: string): Model?
	local pastaTemplates = ReplicatedStorage:FindFirstChild("Entidades")
	local templates = pastaTemplates and pastaTemplates:FindFirstChild("Templates")
	if not templates then
		return nil
	end
	local alvo = templates:FindFirstChild(nomeTemplate)
	if alvo and alvo:IsA("Model") then
		return alvo
	end
	return nil
end

function ConstrutorModeloNPC.Construir(opcoes: any): Model?
	-- 1) Aparencia de player (payload __Player__ / aparenciaDe).
	local aparenciaDe = opcoes.aparenciaDe
	if typeof(aparenciaDe) == "Instance" and aparenciaDe:IsA("Player") then
		local copia = clonarPersonagemDoPlayer(aparenciaDe, opcoes.nome)
		if copia then
			return copia
		end
	end

	-- 2) Template por especie/nome.
	local nomeTemplate = opcoes.especie or opcoes.template or opcoes.nome
	if typeof(nomeTemplate) == "string" and nomeTemplate ~= "" then
		local template = buscarTemplate(nomeTemplate)
		if template then
			local copia = template:Clone()
			prepararModelo(copia, opcoes.nome or nomeTemplate)
			return copia
		end
	end

	-- 3) Fallback: rig humanoide padrao em Templates/NPCBase.
	local base = buscarTemplate("NPCBase")
	if base then
		local copia = base:Clone()
		prepararModelo(copia, opcoes.nome or "NPC")
		return copia
	end

	warn("[ConstrutorModeloNPC] Nenhum template encontrado para:", tostring(nomeTemplate))
	return nil
end

return ConstrutorModeloNPC
