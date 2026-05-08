--!strict

--[[
    Script: ConstrutorModeloNPC.luau
    Caminho: src/ServerScriptService/NPC
    Responsabilidade: Constroi o Model R6 de um NPC sem usar templates manuais (clona aparencia do player ou monta R6 base; para animais, clona da pasta de animais se existir).
    Uso: ModuleScript; require em servidor; chame Construir(opcoes).
    Nao faz: Nao registra a entidade nem inicia comportamento; apenas devolve o Model pronto para uso.
    Funcoes principais: Construir
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TiposNPC = require(
	ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC"):WaitForChild("Tipos")
)

type OpcoesSpawn = TiposNPC.OpcoesSpawn

local Construtor = {}

local CACHE_DESCRICAO_PADRAO: HumanoidDescription? = nil

local function obterDescricaoPadrao(): HumanoidDescription
	if CACHE_DESCRICAO_PADRAO then
		return CACHE_DESCRICAO_PADRAO
	end
	local desc = Instance.new("HumanoidDescription")
	-- Cores neutras para fallback (humano generico).
	desc.HeadColor = Color3.fromRGB(213, 178, 138)
	desc.LeftArmColor = desc.HeadColor
	desc.RightArmColor = desc.HeadColor
	desc.LeftLegColor = Color3.fromRGB(76, 56, 40)
	desc.RightLegColor = desc.LeftLegColor
	desc.TorsoColor = Color3.fromRGB(91, 64, 41)
	CACHE_DESCRICAO_PADRAO = desc
	return desc
end

local function ehScriptPadraoRoblox(inst: Instance): boolean
	-- Scripts adicionados automaticamente pelo Roblox em personagens (Animate, Sound, Health, Animator)
	-- conflitam com nosso sistema (Animate dispara Idle/Walk/Run em paralelo as nossas tracks).
	if not (inst:IsA("LocalScript") or inst:IsA("Script")) then
		return false
	end
	local nome = inst.Name
	return nome == "Animate" or nome == "Sound" or nome == "Health"
end

local function limparScriptsConflitantes(modelo: Model)
	for _, desc in modelo:GetDescendants() do
		if ehScriptPadraoRoblox(desc) then
			desc:Destroy()
		end
	end
end

local function clonarPersonagemDoPlayer(player: Player): Model?
	local char = player.Character
	if not char then
		return nil
	end
	if not char:FindFirstChildOfClass("Humanoid") then
		return nil
	end
	-- Aguarda parts essenciais.
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end
	local sucesso, copia = pcall(function()
		return char:Clone() :: Model
	end)
	if not sucesso or not copia then
		return nil
	end
	-- Limpa scripts/anexos que pertencem ao player original.
	limparScriptsConflitantes(copia)
	return copia
end

local function criarHumanoR6Generico(): Model
	-- Usa o servico oficial para garantir um R6 funcional sem template.
	local sucesso, modelo = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(
			obterDescricaoPadrao(),
			Enum.HumanoidRigType.R6
		)
	end)
	if sucesso and modelo then
		return modelo
	end
	-- Fallback minimo (nunca deveria acontecer, mas garante seguranca).
	warn("[ConstrutorModeloNPC] Falha em CreateHumanoidModelFromDescriptionAsync; usando placeholder.")
	local placeholder = Instance.new("Model")
	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Size = Vector3.new(2, 2, 1)
	hrp.Transparency = 1
	hrp.CanCollide = false
	hrp.Parent = placeholder
	placeholder.PrimaryPart = hrp
	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R6
	hum.Parent = placeholder
	return placeholder
end

local function clonarTemplateAnimal(especieId: string): Model?
	local raiz = ReplicatedStorage:FindFirstChild("Entidades")
	local pastaNPC = raiz and raiz:FindFirstChild("NPC")
	local pastaAnimais = pastaNPC and pastaNPC:FindFirstChild("Animais")
	if not pastaAnimais then
		return nil
	end
	local template = pastaAnimais:FindFirstChild(especieId)
	if not template or not template:IsA("Model") then
		return nil
	end
	local copia = template:Clone()
	if not copia:FindFirstChildOfClass("Humanoid") then
		local hum = Instance.new("Humanoid")
		hum.RigType = Enum.HumanoidRigType.R6
		hum.Parent = copia
	end
	if not copia.PrimaryPart then
		copia.PrimaryPart = copia:FindFirstChild("HumanoidRootPart") :: BasePart?
			or copia:FindFirstChildWhichIsA("BasePart")
	end
	return copia
end

local function ajustarHumanoide(modelo: Model)
	local hum = modelo:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	-- Forca R6.
	hum.RigType = Enum.HumanoidRigType.R6
	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false
	hum.AutoRotate = true
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Subject
	-- Mostra barra de vida quando ferido (ver vida do NPC).
	hum.HealthDisplayDistance = 120
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged
	hum.NameDisplayDistance = 60
	-- Desabilita estados que nao usaremos (parkour proprio do NPC e ragdoll).
	hum:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
end

function Construtor.Construir(opcoes: OpcoesSpawn): Model?
	local archetype = opcoes.archetype
	local modelo: Model?

	if archetype == TiposNPC.Archetype.Animal then
		local especie = opcoes.especie or "Galinha"
		modelo = clonarTemplateAnimal(especie)
		if not modelo then
			warn(string.format(
				"[ConstrutorModeloNPC] Template de animal '%s' nao encontrado em ReplicatedStorage/Entidades/NPC/Animais; usando R6 generico como placeholder.",
				especie
			))
			modelo = criarHumanoR6Generico()
		end
	else
		-- Dialogo / Combate => humano.
		if opcoes.aparenciaDe then
			modelo = clonarPersonagemDoPlayer(opcoes.aparenciaDe)
		end
		if not modelo then
			modelo = criarHumanoR6Generico()
		end
	end

	if not modelo then
		return nil
	end

	modelo.Name = opcoes.nome or (archetype .. (opcoes.especie and ("_" .. opcoes.especie) or ""))
	ajustarHumanoide(modelo)
	-- Limpa Animate/Sound/Health gerados automaticamente (CreateHumanoidModelFromDescriptionAsync
	-- e clones de Character podem trazer estes; nosso sistema toca tudo manualmente).
	limparScriptsConflitantes(modelo)

	-- Garante PrimaryPart.
	if not modelo.PrimaryPart then
		modelo.PrimaryPart = modelo:FindFirstChild("HumanoidRootPart") :: BasePart?
			or modelo:FindFirstChildWhichIsA("BasePart")
	end

	return modelo
end

return Construtor
