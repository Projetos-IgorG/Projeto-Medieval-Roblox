# Sistema de Animação com Eventos de Animação para Parkour

Implementar um sistema completo de animações para o parkour existente, com eventos de animação (markers) que controlam o momento exato do movimento, sistema de alternância de braços ao subir, e integração total com o `ControladorEstado` para bloquear combate/dash/equip durante parkour.

## Proposed Changes

### Dados de Animação

#### [MODIFY] [Modulo_ModosAnimacao.luau](file:///c:/Users/Igor/Projetos/Pessoal/Medieval/RobloxStudio/src/ReplicatedStorage/Modulos/Combate/Modulo_ModosAnimacao.luau)

Adicionar uma seção `Parkour` com todas as 14 animações e metadados de eventos. Essa seção fica **separada** dos modos de combate, pois é independente do modo equipado:

```lua
-- ═══════════════════════════════════════════════════════════════
-- PARKOUR (Independente do modoAnimacao — usado sempre)
-- ═══════════════════════════════════════════════════════════════
Parkour = {
    tipo = "Parkour",
    animacoes = {
        -- Idles (Loop)
        IdleSuporte    = "rbxassetid://0000000000",
        IdleSuspenso   = "rbxassetid://0000000000",
        -- Subir (Ação)
        SubirDireita   = "rbxassetid://0000000000",
        SubirEsquerda  = "rbxassetid://0000000000",
        SubirSalto     = "rbxassetid://0000000000",
        -- Descer
        Descer         = "rbxassetid://0000000000",
        -- PuloTras
        PuloTras       = "rbxassetid://0000000000",
        -- Lateral
        DireitaSuporte   = "rbxassetid://0000000000",
        EsquerdaSuporte  = "rbxassetid://0000000000",
        DireitaSuspenso  = "rbxassetid://0000000000",
        EsquerdaSuspenso = "rbxassetid://0000000000",
        -- Finalizar
        Escalar        = "rbxassetid://0000000000",
        VaultMedio     = "rbxassetid://0000000000",
        VaultBaixo     = "rbxassetid://0000000000",
    },
    -- Mapeamento: nome da animação → nome do evento (marker)
    -- Animações sem entrada aqui executam ação IMEDIATAMENTE
    eventos = {
        SubirDireita     = "SubirParkour",
        SubirEsquerda    = "SubirParkour",
        SubirSalto       = "SubirSaltoParkour",
        Descer           = "Descer",
        DireitaSuporte   = "DireitaParkour",
        EsquerdaSuporte  = "EsquerdaParkour",
        DireitaSuspenso  = "DireitaParkour",
        EsquerdaSuspenso = "EsquerdaParkour",
    },
},
```

---

### Novo Módulo de Animação

#### [NEW] [AnimacaoParkour.luau](file:///c:/Users/Igor/Projetos/Pessoal/Medieval/RobloxStudio/src/StarterPlayer/StarterPlayerScripts/Parkour/AnimacaoParkour.luau)

Módulo autocontido responsável por:

1. **Carregar/cachear** `AnimationTrack` via o `Animator` do personagem
2. **Tocar animações** de parkour com prioridade `Action2` (acima de combate)
3. **Escutar eventos** (`GetMarkerReachedSignal`) e invocar callbacks do [Movimento.luau](file:///c:/Users/Igor/Projetos/Pessoal/Medieval/RobloxStudio/src/StarterPlayer/StarterPlayerScripts/Parkour/Movimento.luau)
4. **Gerenciar idle loops** (`IdleSuporte` / `IdleSuspenso`) baseado no `IdleMode` do grab
5. **Alternar braços** ao subir (`SubirDireita` ↔ `SubirEsquerda`)
6. **Cleanup** de conexões e tracks ao sair do parkour

**API pública:**

```lua
-- Inicializa com o character/animator
AnimacaoParkour.Inicializar(character: Model)

-- Toca animação de ação com possível evento
-- Se a animação tem evento, onEvento é chamado quando o marker dispara
-- onCompleto é chamado quando a animação termina
AnimacaoParkour.TocarAcao(
    nomeAnimacao: string,
    onEvento: (() -> ())?,
    onCompleto: (() -> ())?
): boolean

-- Toca idle loop (IdleSuporte ou IdleSuspenso)
AnimacaoParkour.TocarIdle(idleMode: string)

-- Para todas as animações de parkour com fade suave
AnimacaoParkour.PararTudo(fadeTime: number?)

-- Obtém o nome da animação de subir baseado na alternância
AnimacaoParkour.ObterAnimacaoSubir(): string -- "SubirDireita" | "SubirEsquerda"

-- Reseta alternância de braços (ao finalizar parkour)
AnimacaoParkour.ResetarBraco()

-- Cleanup total
AnimacaoParkour.Destruir()
```

**Fluxo de evento (exemplo: Subir):**
1. `Movimento.TentarSubir()` confirma que há superfície acima
2. `AnimacaoParkour.TocarAcao("SubirDireita", executarMovimentoSubir, onSubirCompleto)` é chamado
3. Animação começa imediatamente → `EmAcao = true`
4. Quando marker `"SubirParkour"` dispara → `executarMovimentoSubir()` move o personagem via constraints
5. Quando animação termina → `onSubirCompleto()` marca `EmAcao = false`, toca idle

**Alternância de braços:**
- Estado interno: `proximoBraco = "Direita"` (default)
- Cada `SubirDireita` ou `SubirEsquerda` alterna para o oposto
- `ResetarBraco()` volta para `"Direita"` — chamado em: Escalar, Soltar, PuloTras, ao morrer

---

### Integração com Sistema de Estado

#### [MODIFY] [ClientBridge.luau](file:///c:/Users/Igor/Projetos/Pessoal/Medieval/RobloxStudio/src/ReplicatedStorage/Modulos/Core/ClientBridge.luau)

Adicionar novas declarations:

```lua
-- ═══ Parkour ═══
ClientBridge.EstaEmParkour = nil :: (() -> boolean)?
ClientBridge.EntrarParkour = nil :: (() -> ())?
ClientBridge.SairParkour = nil :: (() -> ())?
```

---

#### [MODIFY] [ControladorEstado.client.luau](file:///c:/Users/Igor/Projetos/Pessoal/Medieval/RobloxStudio/src/StarterPlayer/StarterCharacterScripts/Estado/ControladorEstado.client.luau)

Alterações mínimas e cirúrgicas:

1. **Bloquear ações durante parkour** — adicionar guard no início de:
   - `TocarAnimacaoAcao()` — retornar sem tocar se `ClientBridge.EstaEmParkour and ClientBridge.EstaEmParkour()`
   - `AtualizarAnimacaoMovimento()` — skip update se em parkour (parkour controla suas próprias animações)
   - `AtualizarEstadoMovimento()` — skip se em parkour

2. **Ao sair do parkour** — o `SairParkour` (implementado no Parkour) chamará `AtualizarAnimacaoMovimento()` e `AtualizarBaseIdle()` via `ClientBridge` para retomar naturalmente

---

### Refatoração do Movimento

#### [MODIFY] [Movimento.luau](file:///c:/Users/Igor/Projetos/Pessoal/Medieval/RobloxStudio/src/StarterPlayer/StarterPlayerScripts/Parkour/Movimento.luau)

Refatorar cada função de execução para integrar animações:

**`executarAgarrar()`:**
- Ao completar transição → `AnimacaoParkour.TocarIdle(result.IdleMode)`
- `ClientBridge.EntrarParkour()` para notificar ControladorEstado

**`executarSubir()` / `executarDescer()` / `executarLateral()`:**
- Separa em duas fases: **animação** e **movimento**
- Fase 1: Toca animação imediatamente via `AnimacaoParkour.TocarAcao`
- Fase 2: Quando evento de animação dispara → executa constraints de movimento
- Fase 3: Quando animação termina → marca `EmAcao = false`, toca idle

**`executarPuloTras()` / `executarEscalar()` / `executarVault()`:**
- Sem evento de animação → ação e animação começam juntas (imediatamente)
- `AnimacaoParkour.PararTudo()` antes de cleanup
- `ClientBridge.SairParkour()` ao finalizar

**`fullCleanup()`:**
- Adicionar `AnimacaoParkour.PararTudo()` e `AnimacaoParkour.ResetarBraco()`
- Adicionar `ClientBridge.SairParkour()`

---

#### [MODIFY] [init.client.luau](file:///c:/Users/Igor/Projetos/Pessoal/Medieval/RobloxStudio/src/StarterPlayer/StarterPlayerScripts/Parkour/init.client.luau)

- Adicionar `require` do `AnimacaoParkour`
- Em `setupCharacter()` → chamar `AnimacaoParkour.Inicializar(character)`
- Em cleanup → chamar `AnimacaoParkour.Destruir()`

---

## Resumo dos Arquivos

| Arquivo | Ação | Descrição |
|---------|------|-----------|
| [Modulo_ModosAnimacao.luau](file:///c:/Users/Igor/Projetos/Pessoal/Medieval/RobloxStudio/src/ReplicatedStorage/Modulos/Combate/Modulo_ModosAnimacao.luau) | MODIFY | Adicionar seção `Parkour` com 14 animações + eventos |
| `AnimacaoParkour.luau` | NEW | Módulo de animação do parkour |
| [ClientBridge.luau](file:///c:/Users/Igor/Projetos/Pessoal/Medieval/RobloxStudio/src/ReplicatedStorage/Modulos/Core/ClientBridge.luau) | MODIFY | 3 novas declarations para parkour |
| [ControladorEstado.client.luau](file:///c:/Users/Igor/Projetos/Pessoal/Medieval/RobloxStudio/src/StarterPlayer/StarterCharacterScripts/Estado/ControladorEstado.client.luau) | MODIFY | Guards de `EstaEmParkour` para bloquear ações |
| [Movimento.luau](file:///c:/Users/Igor/Projetos/Pessoal/Medieval/RobloxStudio/src/StarterPlayer/StarterPlayerScripts/Parkour/Movimento.luau) | MODIFY | Integrar animações em cada ação |
| [init.client.luau](file:///c:/Users/Igor/Projetos/Pessoal/Medieval/RobloxStudio/src/StarterPlayer/StarterPlayerScripts/Parkour/init.client.luau) | MODIFY | Setup/cleanup do `AnimacaoParkour` |

## Verification Plan

### Manual Verification

> [!IMPORTANT]
> Como este é um jogo Roblox, a verificação é manual no Roblox Studio.

**Passos para teste:**

1. **Sincronizar o projeto** com `rojo serve` ou equivalente
2. **Verificar que placeholders não causam crash** — IDs `0000000000` devem ser tratados graciosamente
3. **Testar bloqueio de ações durante parkour:**
   - Agarrar → M1 (atacar) → não deve funcionar
   - Agarrar → M2 (defender) → não deve funcionar
   - Agarrar → dash → não deve funcionar
4. **Testar alternância de braços** — subir várias vezes e verificar nos prints do console a alternância
5. **Testar transição suave** — ao escalar/soltar/PuloTras, a animação deve voltar suavemente ao idle
6. **Testar cleanup** — morrer agarrado, verificar que constraints e animações são limpas
