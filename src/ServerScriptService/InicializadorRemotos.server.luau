--[[
    InicializadorRemotos.server.luau
    
    Cria os RemoteEvents necessários para o sistema de combate.
    Executado no servidor antes de qualquer outro script.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ═══════════════════════════════════════════════════════════════════
-- CRIAR PASTA DE REMOTOS
-- ═══════════════════════════════════════════════════════════════════

local function CriarRemoto(pasta, nome, tipo)
	local existente = pasta:FindFirstChild(nome)
	if existente then
		return existente
	end

	local remoto
	if tipo == "Event" then
		remoto = Instance.new("RemoteEvent")
	elseif tipo == "Function" then
		remoto = Instance.new("RemoteFunction")
	end

	remoto.Name = nome
	remoto.Parent = pasta

	return remoto
end

-- Função auxiliar para criar BindableEvents/Functions em uma pasta Bindables
local function CriarBindable(pasta, nome, tipo)
	local existente = pasta:FindFirstChild(nome)
	if existente then
		return existente
	end

	local bindable
	if tipo == "Event" then
		bindable = Instance.new("BindableEvent")
	elseif tipo == "Function" then
		bindable = Instance.new("BindableFunction")
	end

	bindable.Name = nome
	bindable.Parent = pasta
	return bindable
end

-- Cria pasta principal
local Remotos = ReplicatedStorage:FindFirstChild("Remotos")
if not Remotos then
	Remotos = Instance.new("Folder")
	Remotos.Name = "Remotos"
	Remotos.Parent = ReplicatedStorage
end

-- Cria pasta de Bindables (server-side)
local Bindables = ReplicatedStorage:FindFirstChild("Bindables")
if not Bindables then
	Bindables = Instance.new("Folder")
	Bindables.Name = "Bindables"
	Bindables.Parent = ReplicatedStorage
end

-- ═══════════════════════════════════════════════════════════════════
-- REMOTE EVENTS
-- ═══════════════════════════════════════════════════════════════════

-- Cliente → Servidor: Enviar ação do jogador
CriarRemoto(Remotos, "TentarAcao", "Event")

-- Cliente → Servidor: Mudar estado do ShiftLock
CriarRemoto(Remotos, "MudarShiftLock", "Event")

-- Servidor → Cliente: Sincronizar estado da entidade
CriarRemoto(Remotos, "SincronizarEstado", "Event")

-- Servidor → Cliente: Tocar animação em uma entidade
CriarRemoto(Remotos, "TocarAnimacao", "Event")

-- BindableEvents server-side (uso interno do servidor)
CriarBindable(Bindables, "SpawnNPC", "Event")

-- ═══════════════════════════════════════════════════════════════════
-- LISTENER DO SHIFTLOCKCHANGED (usado pelo ShiftLockController)
-- ═══════════════════════════════════════════════════════════════════

-- Cria ou obtém o RemoteEvent ShiftLockChanged (na raiz do ReplicatedStorage)
local ShiftLockChanged = ReplicatedStorage:FindFirstChild("ShiftLockChanged")
if not ShiftLockChanged then
	ShiftLockChanged = Instance.new("RemoteEvent")
	ShiftLockChanged.Name = "ShiftLockChanged"
	ShiftLockChanged.Parent = ReplicatedStorage
end

-- Listener para atualizar Status.ShiftLockOn quando cliente muda
ShiftLockChanged.OnServerEvent:Connect(function(player, estado)
	local character = player.Character
	if not character then
		return
	end

	local status = character:FindFirstChild("Status")
	if status then
		local shiftLockValue = status:FindFirstChild("ShiftLockOn")
		if shiftLockValue then
			shiftLockValue.Value = estado
			print(string.format("[ShiftLock] %s: ShiftLockOn atualizado para %s", player.Name, tostring(estado)))
		end
	end
end)

-- ═══════════════════════════════════════════════════════════════════

print("[InicializadorRemotos] RemoteEvents criados")
