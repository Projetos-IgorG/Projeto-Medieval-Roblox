--!strict

--[[
    Script: LeitorEntidade.luau
    Caminho: src/ReplicatedStorage/Entidades
    Responsabilidade: Helpers de leitura no cliente (le atributos replicados via Roblox Attributes do Model da entidade).
    Uso: ModuleScript; use no cliente para alimentar UIs de status.
    Nao faz: Nao escreve no model nem aplica regras de jogo.
    Funcoes principais: ObterEspecie, ObterAtributo, ListarAtributos, AssistirAtributo
]]

local Atributos = require(script.Parent:WaitForChild("Atributos"))
local Especies = require(script.Parent:WaitForChild("Especies"))
local Entidade = require(script.Parent:WaitForChild("Entidade"))

local LeitorEntidade = {}

export type EstadoAtributo = Entidade.EstadoAtributo

function LeitorEntidade.ObterEspecieId(modelo: Model?): string?
	if not modelo then
		return nil
	end
	local valor = modelo:GetAttribute(Entidade.CHAVE_ESPECIE)
	if typeof(valor) == "string" then
		return valor
	end
	return nil
end

function LeitorEntidade.ObterEspecie(modelo: Model?): Especies.DefinicaoEspecie?
	local id = LeitorEntidade.ObterEspecieId(modelo)
	if not id then
		return nil
	end
	return Especies.Obter(id)
end

function LeitorEntidade.ObterAtributo(modelo: Model?, id: string): number?
	if not modelo then
		return nil
	end
	local valor = modelo:GetAttribute(Entidade.chaveAtributo(id))
	if typeof(valor) == "number" then
		return valor
	end
	return nil
end

function LeitorEntidade.ListarAtributos(modelo: Model?): { EstadoAtributo }
	local lista: { EstadoAtributo } = {}
	if not modelo then
		return lista
	end
	local especie = LeitorEntidade.ObterEspecie(modelo)
	local idsAtributos: { string }
	if especie then
		idsAtributos = especie.atributos
	else
		-- fallback: varre todos os atributos com prefixo
		idsAtributos = {}
		for chave, _ in modelo:GetAttributes() do
			if string.sub(chave, 1, #Entidade.PREFIXO_ATRIBUTO) == Entidade.PREFIXO_ATRIBUTO
				and chave ~= Entidade.CHAVE_ESPECIE then
				table.insert(idsAtributos, string.sub(chave, #Entidade.PREFIXO_ATRIBUTO + 1))
			end
		end
	end

	for _, id in idsAtributos do
		local def = Atributos.Obter(id)
		if not def then
			continue
		end
		local valorLido = modelo:GetAttribute(Entidade.chaveAtributo(id))
		local valorFinal: number
		if typeof(valorLido) == "number" then
			valorFinal = valorLido
		else
			valorFinal = def.padrao
		end
		table.insert(lista, {
			id = id,
			nome = def.nome,
			valor = valorFinal,
			min = def.min,
			max = def.max,
			deltaPorSegundo = def.deltaPorSegundo,
			formato = def.formato,
			cor = def.cor,
		})
	end

	table.sort(lista, function(a, b)
		return a.nome < b.nome
	end)
	return lista
end

function LeitorEntidade.AssistirAtributo(modelo: Model, id: string, callback: (valor: any) -> ()): RBXScriptConnection
	return modelo:GetAttributeChangedSignal(Entidade.chaveAtributo(id)):Connect(function()
		callback(modelo:GetAttribute(Entidade.chaveAtributo(id)))
	end)
end

return LeitorEntidade
