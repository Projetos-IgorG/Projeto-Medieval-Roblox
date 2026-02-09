--[[
    StatusLocal.client.luau
    
    Script local que cria e gerencia a pasta StatusLocal no character.
    Esta pasta contém atributos de estado que são gerenciados 100% pelo cliente
    para evitar latência e sincronização desnecessária com o servidor.
    
    Atributos client-side:
    - modoAnimacao: String, modo de animação atual (Base, Espada, etc.)
    - estadoMov: String, estado de movimento (Parado, Andando, Correndo, etc.)
    - ShiftLockOn: Bool, câmera travada (ShiftLock/1ª pessoa)
    - AgachadoOn: Bool, jogador agachado
    - CorrendoOn: Bool, jogador correndo
    
    Atributos que permanecem no servidor (pasta Status):
    - estadoAcao, BloqueandoOn, ProntoAparar, StunadoOn, DashOn
]]

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()

-- ═══════════════════════════════════════════════════════════════════
-- CRIAR PASTA STATUSLOCAL
-- ═══════════════════════════════════════════════════════════════════

local function CriarStatusLocal(char: Model)
	-- Verifica se já existe
	local existing = char:FindFirstChild("StatusLocal")
	if existing then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = "StatusLocal"
	folder.Parent = char

	local function createValue(className: string, name: string, default: any)
		local v = Instance.new(className)
		v.Name = name
		if default ~= nil then
			v.Value = default
		end
		v.Parent = folder
		return v
	end

	-- Atributos de movimento (client-only)
	createValue("StringValue", "modoAnimacao", "Base")
	createValue("StringValue", "estadoMov", "Parado")
	createValue("BoolValue", "ShiftLockOn", false)
	createValue("BoolValue", "AgachadoOn", false)
	createValue("BoolValue", "CorrendoOn", false)

	return folder
end

-- Cria para character atual
local _statusLocal = CriarStatusLocal(character)

-- Recria quando respawnar
player.CharacterAdded:Connect(function(newCharacter)
	character = newCharacter
	_statusLocal = CriarStatusLocal(newCharacter)
end)

-- ═══════════════════════════════════════════════════════════════════
-- FUNÇÕES GLOBAIS PARA ATUALIZAR STATUSLOCAL
-- ═══════════════════════════════════════════════════════════════════

--- Obtém a pasta StatusLocal do character atual
function _G.ObterStatusLocal(): Folder?
	return character and character:FindFirstChild("StatusLocal")
end

--- Atualiza um valor na pasta StatusLocal
function _G.AtualizarStatusLocal(nome: string, valor: any)
	local folder = _G.ObterStatusLocal()
	if not folder then
		return
	end

	local obj = folder:FindFirstChild(nome)
	if obj and (obj:IsA("StringValue") or obj:IsA("BoolValue") or obj:IsA("NumberValue")) then
		(obj :: any).Value = valor
	end
end

--- Lê um valor da pasta StatusLocal
function _G.LerStatusLocal(nome: string): any
	local folder = _G.ObterStatusLocal()
	if not folder then
		return nil
	end

	local obj = folder:FindFirstChild(nome)
	if obj and (obj:IsA("StringValue") or obj:IsA("BoolValue") or obj:IsA("NumberValue")) then
		return (obj :: any).Value
	end
	return nil
end

print("[StatusLocal] Pasta StatusLocal criada para", player.Name)
