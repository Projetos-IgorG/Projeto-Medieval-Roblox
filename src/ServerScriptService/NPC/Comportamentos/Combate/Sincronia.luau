--!strict

--[[
	Script: Sincronia.luau (filho de Combate)
	Responsabilidade: UNICO escritor dos atributos replicados NPC_*.

	Regras:
	- NPC_Acao / NPC_AcaoIndice / NPC_AcaoTick: escritos APENAS via DefinirAcao
	  (chamado por Acoes). O hook da maquina NUNCA toca nesses atributos.
	- NPC_Estado: escrito pelo hook da maquina (mapeamento unico) e pela
	  locomocao via DefinirEstadoLocomocao (guardado por estadoAcao == "Nenhuma").
	- "Morto" e terminal: so o Gerenciamento escreve, ninguem sobrescreve.

	Correcoes:
	- Aceita maquina com :ObterDados() OU campo .dados (o resto do sistema usa
	  o campo; a incompatibilidade quebrava a conclusao do equipar).
	- Hook protegido por pcall: erro em uma transicao nao derruba todas as
	  sincronizacoes seguintes do NPC.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TiposNPC = require(ReplicatedStorage:WaitForChild("Entidades"):WaitForChild("NPC"):WaitForChild("Tipos"))

local Estado = require(script.Parent:WaitForChild("Estado"))

type EstadoNPC = Estado.EstadoNPC

local Sincronia = {}

-- FIX: o resto do sistema (Decisao) le `maquina.dados` direto, enquanto este
-- modulo chamava `maquina:ObterDados()`. Se a MaquinaDeEstados nao expuser esse
-- metodo, o hook estourava a cada transicao e NPC_ArmaPronta nunca era setado
-- (equip pendurado -> NPC congelado). Agora aceita as duas formas.
local function obterDados(maquina: any): any?
	if not maquina then
		return nil
	end
	if maquina.ObterDados then
		local ok, dados = pcall(maquina.ObterDados, maquina)
		if ok and dados then
			return dados
		end
	end
	return maquina.dados
end

local function setAttr(modelo: Model, chave: string, valor: any)
	if modelo:GetAttribute(chave) ~= valor then
		modelo:SetAttribute(chave, valor)
	end
end

-- =============================================================================
-- Escritores publicos.
-- =============================================================================

-- Define NPC_Acao (+ indice) e gera um NOVO NPC_AcaoTick. Retorna o tick,
-- que e exatamente a chave usada no historico de swings.
function Sincronia.DefinirAcao(s: EstadoNPC, acao: string, indice: number?): number
	if s.destruido then
		return s.acaoTick
	end
	local tick = os.clock()
	s.acaoTick = tick
	s.modelo:SetAttribute(TiposNPC.Chaves.Acao, acao)
	if indice ~= nil then
		s.modelo:SetAttribute(TiposNPC.Chaves.AcaoIndice, indice)
	end
	s.modelo:SetAttribute(TiposNPC.Chaves.AcaoTick, tick)
	return tick
end

function Sincronia.DefinirLocomocao(s: EstadoNPC, nome: string, velocidade: number?)
	if s.destruido then
		return
	end
	setAttr(s.modelo, TiposNPC.Chaves.LocomocaoNome, nome)
	setAttr(s.modelo, TiposNPC.Chaves.LocomocaoVelocidade, velocidade or 1)
end

function Sincronia.DefinirArmaPronta(s: EstadoNPC, pronta: boolean)
	if s.destruido then
		return
	end
	setAttr(s.modelo, TiposNPC.Chaves.ArmaPronta, pronta)
end

function Sincronia.DefinirEstado(modelo: Model, estado: string)
	local atual = modelo:GetAttribute(TiposNPC.Chaves.Estado)
	if atual == TiposNPC.Estado.Morto then
		return -- morte e terminal
	end
	if atual ~= estado then
		modelo:SetAttribute(TiposNPC.Chaves.Estado, estado)
	end
end

-- Estado de locomocao (Idle/Andando/Correndo): so escreve quando a maquina
-- nao esta impondo um estado de acao (nao sobrescreve Atacando/Defendendo/etc).
function Sincronia.DefinirEstadoLocomocao(s: EstadoNPC, maquina: any, estado: string)
	if s.destruido then
		return
	end
	local dados = obterDados(maquina)
	if dados and (dados.estadoAcao ~= "Nenhuma" or dados.bloqueando) then
		return
	end
	Sincronia.DefinirEstado(s.modelo, estado)
end

-- =============================================================================
-- Mapeamento unico maquina -> NPC_Estado.
-- =============================================================================

local function mapearEstado(dados: any): string
	local acao = dados.estadoAcao
	if acao == "Aparado" then
		return TiposNPC.Estado.Aparado
	elseif acao == "Aparando" then
		return TiposNPC.Estado.Aparando
	elseif acao == "Stunado" then
		return TiposNPC.Estado.Stunado
	elseif acao == "DefesaQuebrada" then
		return TiposNPC.Estado.DefesaQuebrada
	elseif acao == "Defendendo" then
		return TiposNPC.Estado.Defendendo
	elseif acao == "Atacando" then
		return TiposNPC.Estado.Atacando
	end
	if dados.bloqueando then
		return TiposNPC.Estado.Defendendo
	end
	local mov = dados.estadoMov
	if mov == "Correndo" then
		return TiposNPC.Estado.Correndo
	elseif mov == "Andando" then
		return TiposNPC.Estado.Andando
	end
	return TiposNPC.Estado.Idle
end

local function aoMudarMaquina(s: EstadoNPC, maquina: any)
	if s.destruido then
		return
	end
	local dados = obterDados(maquina)
	if not dados then
		warn("[NPC.Sincronia] Maquina sem dados; equip/estado nao serao sincronizados em", s.modelo:GetFullName())
		return
	end

	Sincronia.DefinirEstado(s.modelo, mapearEstado(dados))

	-- Conclusao de equipar/desequipar (a maquina voltou para "Nenhuma").
	if s.equipando and dados.estadoAcao == "Nenhuma" then
		if s.desequipando then
			s.armaPronta = false
			s.desequipando = false
			s.armaEquipada = nil
			Sincronia.DefinirArmaPronta(s, false)
		else
			s.armaPronta = true
			Sincronia.DefinirArmaPronta(s, true)
		end
		s.equipando = false
		if not s.atacando then
			Sincronia.DefinirAcao(s, TiposNPC.Acao.Idle, 0)
		end
	end
end

-- Instala UM unico conjunto de hooks por NPC (antes eram dois conjuntos,
-- um em cada modulo). `aoMudarEstadoAcao` e o callback da IA (Decisao),
-- chamado APOS a sincronizacao de atributos.
function Sincronia.InstalarHooks(
	s: EstadoNPC,
	maquina: any,
	aoMudarEstadoAcao: ((novo: string, anterior: string) -> ())?
)
	-- FIX: erro dentro do hook nao pode derrubar o callback da maquina. Se isso
	-- acontecer, o NPC perde TODAS as sincronizacoes seguintes (inclusive a
	-- conclusao do equipar).
	local function sincronizar()
		local ok, err = (pcall :: any)(aoMudarMaquina, s, maquina)
		if not ok then
			warn("[NPC.Sincronia] Erro ao sincronizar maquina:", err)
		end
	end

	if maquina.AoMudarEstadoAcao then
		local disc = maquina:AoMudarEstadoAcao(function(novo: string, anterior: string)
			sincronizar()
			if aoMudarEstadoAcao and not s.destruido then
				aoMudarEstadoAcao(novo, anterior)
			end
		end)
		if typeof(disc) == "function" then
			table.insert(s.desconectarHooks, disc)
		end
	end
	if maquina.AoMudarEstadoMov then
		local disc = maquina:AoMudarEstadoMov(function()
			sincronizar()
		end)
		if typeof(disc) == "function" then
			table.insert(s.desconectarHooks, disc)
		end
	end
	if maquina.AoMudarModo then
		local disc = maquina:AoMudarModo(function()
			sincronizar()
		end)
		if typeof(disc) == "function" then
			table.insert(s.desconectarHooks, disc)
		end
	end
end

return Sincronia
