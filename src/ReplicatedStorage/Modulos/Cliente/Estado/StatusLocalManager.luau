local StatusLocalManager = {}

function StatusLocalManager.CriarStatusLocal(char: Model)
	local existing = char:FindFirstChild("StatusLocal")
	if existing then return existing end

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

	createValue("StringValue", "modoAnimacao", "Base")
	createValue("StringValue", "estadoMov", "Parado")
	createValue("BoolValue", "ShiftLockOn", false)
	createValue("BoolValue", "AgachadoOn", false)
	createValue("BoolValue", "CorrendoOn", false)

	return folder
end

function StatusLocalManager.ObterStatusLocal(character: Model?): Folder?
	if not character then
		return nil
	end
	return character:FindFirstChild("StatusLocal") :: Folder?
end

function StatusLocalManager.AtualizarStatusLocal(character: Model?, nome: string, valor: any)
	local folder = StatusLocalManager.ObterStatusLocal(character)
	if not folder then return end

	local obj = folder:FindFirstChild(nome)
	if obj and (obj:IsA("StringValue") or obj:IsA("BoolValue") or obj:IsA("NumberValue")) then
		(obj :: any).Value = valor
	end
end

function StatusLocalManager.LerStatusLocal(character: Model?, nome: string): any
	local folder = StatusLocalManager.ObterStatusLocal(character)
	if not folder then return nil end

	local obj = folder:FindFirstChild(nome)
	if obj and (obj:IsA("StringValue") or obj:IsA("BoolValue") or obj:IsA("NumberValue")) then
		return (obj :: any).Value
	end
	return nil
end

return StatusLocalManager
