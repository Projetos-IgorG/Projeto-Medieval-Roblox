-- ReplicatedStorage > Modulos > Cliente > Equipamento > EquipmentHelpers.luau

local EquipmentHelpers = {}

--- Lê Tipo do Tool
function EquipmentHelpers.LerTipo(tool: Tool): string?
	local dados = tool:FindFirstChild("Dados")
	if not dados then
		return nil
	end
	local tipoValue = dados:FindFirstChild("Tipo")
	if tipoValue and tipoValue:IsA("StringValue") then
		return tipoValue.Value
	end
	return nil
end

--- Lê Nome amigável do Tool
function EquipmentHelpers.LerNome(tool: Tool): string
	local dados = tool:FindFirstChild("Dados")
	if dados then
		local nomeValue = dados:FindFirstChild("Nome")
		if nomeValue and nomeValue:IsA("StringValue") and nomeValue.Value ~= "" then
			return nomeValue.Value
		end
	end
	return tool.Name
end

--- Verifica se um Tool deve ser interceptado pelo sistema de equipamento
function EquipmentHelpers.DeveInterceptar(tool: Tool): boolean
	local tipo = EquipmentHelpers.LerTipo(tool)
	return tipo == "Armas" or tipo == "Armaduras"
end

return EquipmentHelpers
