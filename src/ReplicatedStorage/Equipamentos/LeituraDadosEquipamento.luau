--[[
    Script: LeituraDadosEquipamento.luau
    Caminho: src/ReplicatedStorage/Equipamentos
    Responsabilidade: Le atributos e metadados de equipamentos para outros sistemas.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao roda sozinho nem cria fluxo de jogo por conta propria; depende dos scripts que importam este modulo.
    Funcoes principais: LerTipo, LerNome, DeveInterceptar
]]
local EquipmentHelpers = {}

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

function EquipmentHelpers.DeveInterceptar(tool: Tool): boolean
	local tipo = EquipmentHelpers.LerTipo(tool)
	return tipo == "Armas" or tipo == "Armaduras"
end

return EquipmentHelpers
