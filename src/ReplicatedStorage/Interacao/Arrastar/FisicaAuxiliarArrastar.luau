local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CatalogoItens = require(ReplicatedStorage:WaitForChild("Dados"):WaitForChild("Itens"):WaitForChild("CatalogoItens"))

local FisicaHelpers = {}

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

function FisicaHelpers.EhArrastavel(objeto: Instance): boolean
	local attr = objeto:GetAttribute("Arrastavel")
	if attr ~= nil then
		return attr == true
	end
	local id = objeto:GetAttribute("Id")
	local dados = id and CatalogoItens.Get(id)
	if dados and dados.Arrastavel ~= nil then
		return dados.Arrastavel == true
	end
	return false
end

function FisicaHelpers.ObterPeso(objeto: Instance): number
	local id = objeto:GetAttribute("Id")
	local dados = id and CatalogoItens.Get(id)
	if dados then
		local p = dados.Peso
		if typeof(p) == "number" and p > 0 then
			if p < 1 then
				p = 0.8
			end
			return p
		end
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
