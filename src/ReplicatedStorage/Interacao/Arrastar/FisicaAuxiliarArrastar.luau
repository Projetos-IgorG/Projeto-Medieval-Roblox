-- ReplicatedStorage > Modulos > Cliente > Fisica > FisicaHelpers.luau

local FisicaHelpers = {}

-- Obtém a parte principal de um objeto
function FisicaHelpers.ObterPartePrincipal(objeto: Instance): BasePart?
	if objeto:IsA("BasePart") then
		return objeto
	elseif objeto:IsA("Model") then
		return objeto.PrimaryPart or objeto:FindFirstChildWhichIsA("BasePart", true)
	elseif objeto:IsA("Tool") then
		return objeto:FindFirstChild("Handle") :: BasePart?
	end
	return nil
end

-- Verifica se o objeto é arrastável
function FisicaHelpers.EhArrastavel(objeto: Instance): boolean
	if objeto:IsA("Tool") then
		local dados = objeto:FindFirstChild("Dados")
		if dados and dados:IsA("Folder") then
			local draggableValue = dados:FindFirstChild("Draggable")
			if draggableValue and draggableValue:IsA("BoolValue") then
				return draggableValue.Value == true
			end
		end
		return false
	end

	return objeto:GetAttribute("Draggable") == true
end

-- Obtém o peso do objeto
function FisicaHelpers.ObterPeso(objeto: Instance): number
	if objeto:IsA("Tool") then
		local dados = objeto:FindFirstChild("Dados")
		if dados and dados:IsA("Folder") then
			local pesoValue = dados:FindFirstChild("Peso")
			if pesoValue and pesoValue:IsA("NumberValue") then
				local p = pesoValue.Value
				if typeof(p) == "number" and p > 0 then
					if p < 1 then
						p = 0.8
					end
					return p
				end
			end
		end
		return 1.0
	end

	local peso = objeto:GetAttribute("Peso")
	if typeof(peso) == "number" and peso > 0 then
		if peso < 1 then
			peso = 0.8
		end
		return peso
	end
	return 1.0
end

-- Encontra o objeto arrastável pai (subindo na hierarquia)
function FisicaHelpers.EncontrarObjetoArrastavel(instancia: Instance): Instance?
	local atual = instancia

	while atual and atual ~= workspace do
		if FisicaHelpers.EhArrastavel(atual) then
			return atual
		end
		atual = atual.Parent
	end

	return nil
end

return FisicaHelpers
