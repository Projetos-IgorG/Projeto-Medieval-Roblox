# Itens e Equipamentos

<aside>
🧰

**Integração com Estações de Trabalho**

Esta página explica os **dados fixos dos itens** e como eles são montados pelo sistema. Sempre que o assunto for **criar, aprimorar, reparar, customizar ou transformar itens**, a referência principal é [Estações de Trabalho](https://app.notion.com/p/Esta-es-de-Trabalho-8dfa1a20d3b34274adf9d6eb7c86ba5b?pvs=21).

</aside>

---

# 🗂️ Tipos de Item

<aside>
🪨

**Material**

*Recursos brutos ou refinados, usados como insumo em ações de estações (produção, reparo, processamento, etc.).*

#### Exemplos:

- Lingote de Ferro
- Minério de Ferro
- Couro
- Pele de Lobo
- Tronco de Carvalho
</aside>

<aside>
🧪

**Ingredient**

*Itens usados em receitas de estações — culinária, poções, produção, customização e afins.*

#### Exemplos:

- A definir
</aside>

<aside>
🥽

**Equipment**

*Itens vestíveis no corpo do personagem.*

#### Subtipos:

- Roupa
- Acessório

#### Exemplos:

- Peitoral de Ferro
- Cachecol
</aside>

<aside>
📖

**Book**

*Livros e manuais que ensinam receitas ou concedem XP ao ler.*

#### Exemplos:

- Manual: Espada de Aço
</aside>

<aside>
⛏️

**Tool**

*Ferramentas e armas equipáveis para realizar ações.*

#### Subtipos:

- Arma
- Ferramenta

#### Exemplos:

- Picareta de Ferro
- Espada de Ferro
</aside>

<aside>
🧪

**Consumable**

*Itens consumidos ao usar, com efeito imediato (comida, poções, etc.).*

#### Exemplos:

- Pão
- Poção de Cura
</aside>

<aside>
📦

**Misc**

*Coringa — itens que não se encaixam nos outros tipos.*

#### Exemplos:

- Item de Quest
- Troféu
</aside>

---

# 🧱 Estruturas (.luau)

<aside>
🎯

**Regra de ouro (Data-Driven):** tendo o `Id` (+ `QualidadeNum`), o sistema calcula todo o resto. Nada que dá pra derivar entra no banco.

Ex.: `DanoFinal = Catalogo[Id].StatBase * multiplicador(QualidadeNum)`

</aside>

<aside>
🧩

**Duas camadas.** O **Catálogo** (ModuleScript no ReplicatedStorage) guarda tudo que é fixo e igual pra todos. O **estado salvo** é o pouco que muda por instância — e vive como **Attributes no Tool**. Ao instanciar, o Tool junta: *Attributes salvos* + *dados do Catálogo* + *modelo do ReplicatedStorage*.

</aside>

## 📦 Item padrão — o que todo item tem

*Campos fixos do catálogo, presentes em qualquer item.*

```lua
-- Catalogo de Itens (ModuleScript no ReplicatedStorage) — dado FIXO, nunca vai pro save
["id_do_item"] = {
	-- 1) Padrao (todo item tem)
	Nome = "Nome do Item",
	Tipo = "Material",     -- Material | Ingredient | Tool | Consumable | Book | Equipment | Misc
	Subtipo = nil,         -- opcional (ex.: "Ferramenta", "Arma", "Roupa", "Escudo")
	Peso = 1,              -- kg por unidade
	ValorBase = 10,        -- preco base em moedas
	MaxQuantidade = 99,    -- teto da pilha
	Arrastavel = false,    -- true so quando dropado no chao, pra arrastar com o mouse
	Modelo = "IdDoModelo", -- nome do modelo no ReplicatedStorage
}
```

## 🗂️ Estrutura por tipo

*Cada item junta 3 grupos separados por comentário: (1) padrão que todo item tem, (2) só daquele tipo, (3) salvo no banco (muda por instância).*

```lua
-- MATERIAL / INGREDIENT / MISC (empilhavel, sem estado proprio)
["minerio_ferro"] = {
	-- 1) Padrao (todo item tem)
	Nome = "Minerio de Ferro",
	Tipo = "Material",
	Peso = 1.2,
	ValorBase = 6,
	MaxQuantidade = 99,
	Arrastavel = false,
	Modelo = "MinerioFerro",

	-- 2) So deste tipo: (nenhum)

	-- 3) Salvo no banco:
	Quantidade = 30,
}

-- TOOL (Ferramenta)
["picareta_ferro"] = {
	-- 1) Padrao (todo item tem)
	Nome = "Picareta de Ferro",
	Tipo = "Tool",
	Subtipo = "Ferramenta",
	Peso = 2.8,
	ValorBase = 45,
	MaxQuantidade = 99,
	Arrastavel = false,
	Modelo = "PicaretaFerro",

	-- 2) So deste tipo (Tool)
	StatBase = 5,                      -- Eficiencia base (escala com QualidadeNum)
	DurabilidadeMax = 150,
	MaterialBase = "Lingote de Ferro", -- reparo e aprimoramento
	QualidadeNumBase = 10, -- qualidade padrao ao fabricar
	ModoAnimacao = "Picareta",

	-- 3) Salvo no banco (muda por instancia)
	Quantidade = 1,
	QualidadeNum = 10,   -- 0-100 atual; deriva a Qualidade (rotulo) e escala os stats
	Durabilidade = 150,  -- atual (teto = DurabilidadeMax)
}

-- TOOL (Arma)
["espada_ferro"] = {
	-- 1) Padrao (todo item tem)
	Nome = "Espada de Ferro",
	Tipo = "Tool",
	Subtipo = "Arma",
	Peso = 3.5,
	ValorBase = 80,
	MaxQuantidade = 99,
	Arrastavel = false,
	Modelo = "EspadaFerro",

	-- 2) So deste tipo (Tool)
	StatBase = 12,                     -- Dano base (escala com QualidadeNum)
	DurabilidadeMax = 200,
	MaterialBase = "Lingote de Ferro",
	QualidadeNumBase = 20, -- qualidade padrao ao fabricar
	ModoAnimacao = "UmaMao",

	-- 3) Salvo no banco (muda por instancia)
	Quantidade = 1,
	QualidadeNum = 20,   -- 0-100 atual; deriva a Qualidade (rotulo) e escala os stats
	Durabilidade = 200,  -- atual (teto = DurabilidadeMax)
}

-- EQUIPMENT (Roupas, Acessorios)
["peitoral_ferro"] = {
	-- 1) Padrao (todo item tem)
	Nome = "Peitoral de Ferro",
	Tipo = "Equipment",
	Subtipo = "Roupa",
	Peso = 8,
	ValorBase = 90,
	MaxQuantidade = 99,
	Arrastavel = false,
	Modelo = "PeitoralFerro",

	-- 2) So deste tipo (Equipment)
	Slot = "Torso",                    -- Cabeca | Torso | Pernas | Pes | Cosmetico
	StatBase = 10,                     -- Resistencia base (escala com QualidadeNum)
	DurabilidadeMax = 200,
	MaterialBase = "Lingote de Ferro",
	QualidadeNumBase = 15, -- qualidade padrao ao fabricar

	-- 3) Salvo no banco (muda por instancia)
	Quantidade = 1,
	QualidadeNum = 15,   -- 0-100 atual; deriva a Qualidade (rotulo) e escala os stats
	Durabilidade = 200,  -- atual (teto = DurabilidadeMax)
}

-- CONSUMABLE
["pao"] = {
	-- 1) Padrao (todo item tem)
	Nome = "Pao",
	Tipo = "Consumable",
	Peso = 0.3,
	ValorBase = 3,
	MaxQuantidade = 99,
	Arrastavel = false,
	Modelo = "Pao",

	-- 2) So deste tipo (Consumable)
	Efeito = "RestaurarFome",
	Potencia = 25,

	-- 3) Salvo no banco:
	Quantidade = 5,
}

-- BOOK
["manual_espada_aco"] = {
	-- 1) Padrao (todo item tem)
	Nome = "Manual: Espada de Aco",
	Tipo = "Book",
	Peso = 0.5,
	ValorBase = 60,
	MaxQuantidade = 99,
	Arrastavel = false,
	Modelo = "Livro",

	-- 2) So deste tipo (Book)
	Efeito = "EnsinarReceita",
	Alvo = "espada_aco",

	-- 3) Salvo no banco:
	Quantidade = 1,
}
```

## ⭐ QualidadeNum → Qualidade & Stats

`*QualidadeNum` mede quão bem o item foi feito ou refinado: escala os stats e define o rótulo `Qualidade`. A produção normal fica até 100; valores acima disso são Obra-Prima e só devem vir de aprimoramento avançado em [Estações de Trabalho](https://app.notion.com/p/Esta-es-de-Trabalho-8dfa1a20d3b34274adf9d6eb7c86ba5b?pvs=21).*

| QualidadeNum | Qualidade | Multiplicador de stat |
| --- | --- | --- |
| 0 – 19 | Comum | 1.00x – 1.19x |
| 20 – 39 | Regular | 1.20x – 1.39x |
| 40 – 59 | Refinado | 1.40x – 1.59x |
| 60 – 79 | Superior | 1.60x – 1.79x |
| 80 – 100 | Lendário | 1.80x – 2.00x |
| 101 – 120 | Obra-Prima | 2.01x – 2.20x |

```lua
-- Derivado de QualidadeNum — NUNCA se salva (calcula na hora).
local function multiplicador(qNum)
	return 1 + qNum / 100          -- 0 -> 1.00x  |  100 -> 2.00x
end

local function qualidade(qNum)
	if qNum > 100 then return "Obra-Prima"
	elseif qNum >= 80 then return "Lendario"
	elseif qNum >= 60 then return "Superior"
	elseif qNum >= 40 then return "Refinado"
	elseif qNum >= 20 then return "Regular"
	else return "Comum" end
end

-- Ex.: Espada de Ferro com QualidadeNum = 55
--   qualidade(55) -> "Refinado"
--   DanoFinal     -> StatBase(12) * multiplicador(55) = 12 * 1.55 = 18.6
```

[ConstrutorTools (ReplicatedStorage)](https://app.notion.com/p/ConstrutorTools-ReplicatedStorage-88b95c026afd44718cce974af29a05fc?pvs=21)