--[[
	ClientBridge.luau

	Registro central de funções compartilhadas entre scripts client-side.
	Substitui o uso de _G para comunicação entre scripts, oferecendo:
	  - Tipagem explícita dos campos
	  - Rastreabilidade de dependências (quem require este módulo)
	  - Sem race conditions (campos começam nil, checados antes de uso)

	Cada script que DEFINE uma função atribui ela ao campo correspondente.
	Cada script que LÊ faz: if ClientBridge.X then ClientBridge.X(...) end

	Organizado por domínio funcional.
]]

local ClientBridge = {}

-- ═══════════════════════════════════════════════════════════════════
-- DIÁLOGO
-- ═══════════════════════════════════════════════════════════════════
--- Retorna se o jogador está em diálogo ativo
--- Definido por: DialogoClient
ClientBridge.EmDialogo = nil :: (() -> boolean)?

-- ═══════════════════════════════════════════════════════════════════
-- COMBO (Sistema de ataque leve encadeado)
-- ═══════════════════════════════════════════════════════════════════
--- Marca que o jogador quer continuar o combo. Retorna true se consumiu input.
--- Definido por: ControladorEstado
ClientBridge.MarcarContinuarCombo = nil :: (() -> boolean)?

--- Verifica se está na janela de input do combo
--- Definido por: ControladorEstado
ClientBridge.EstaJanelaComboAtiva = nil :: (() -> boolean)?

--- Verifica se há combo ativo (animação tocando)
--- Definido por: ControladorEstado
ClientBridge.EstaComboAtivo = nil :: (() -> boolean)?

-- ═══════════════════════════════════════════════════════════════════
-- ATAQUE PESADO
-- ═══════════════════════════════════════════════════════════════════
--- Continua animação de ataque pesado ao soltar M1
--- Definido por: ControladorEstado
ClientBridge.ContinuarAtaquePesado = nil :: (() -> boolean)?

--- Verifica se está em ataque pesado ativo
--- Definido por: ControladorEstado
ClientBridge.EstaAtaquePesadoAtivo = nil :: (() -> boolean)?

--- Verifica se está aguardando soltar M1 no ataque pesado
--- Definido por: ControladorEstado
ClientBridge.EstaAguardandoSoltarPesado = nil :: (() -> boolean)?

-- ═══════════════════════════════════════════════════════════════════
-- CANCELAMENTO POR DEFESA
-- ═══════════════════════════════════════════════════════════════════
--- Tenta cancelar ataque por defesa. Retorna (sucesso, tipoAtaque?)
--- Definido por: ControladorEstado
ClientBridge.TentarCancelarAtaquePorDefesa = nil :: (() -> (boolean, string?))?

--- Resolve cancel pendente — volta para animação de movimento
--- Definido por: ControladorEstado
ClientBridge.ResolverCancelPendente = nil :: (() -> ())?

--- Cancela o cancel pendente — vai para defesa em vez de Idle
--- Definido por: ControladorEstado
ClientBridge.CancelarCancelPendente = nil :: (() -> ())?

-- ═══════════════════════════════════════════════════════════════════
-- EQUIP / DESEQUIP
-- ═══════════════════════════════════════════════════════════════════
--- Verifica se está em animação de equipar/desequipar
--- Definido por: ControladorEstado e EntradaJogador (redundante, ambos definem)
ClientBridge.EstaEmAnimacaoEquip = nil :: (() -> boolean)?

--- Verifica se o jogador pode alterar Tool (sem ação, sem animação, sem diálogo)
--- Definido por: ControladorEstado
ClientBridge.PodeAlterarTool = nil :: (() -> boolean)?

--- Callback quando animação de equip/desequip termina
--- Definido por: EntradaJogador
ClientBridge.OnEquipAnimacaoTerminou = nil :: ((number) -> ())?

-- ═══════════════════════════════════════════════════════════════════
-- DASH
-- ═══════════════════════════════════════════════════════════════════
--- Calcula direção do dash baseado no input de movimento
--- Definido por: ControladorEstado
ClientBridge.CalcularDirecaoDash = nil :: (() -> string)?

--- Verifica se está em dash
--- Definido por: ControladorEstado
ClientBridge.EstaEmDash = nil :: (() -> boolean)?

-- ═══════════════════════════════════════════════════════════════════
-- PARKOUR
-- ═══════════════════════════════════════════════════════════════════
--- Verifica se está em lock de parkour
--- Definido por: ControladorEstado
ClientBridge.EstaEmParkour = nil :: (() -> boolean)?

--- Entra no lock de parkour (bloqueia ações de combate/dash/equip)
--- Definido por: ControladorEstado
ClientBridge.EntrarParkour = nil :: (() -> ())?

--- Sai do lock de parkour e retoma atualização normal de animação
--- Definido por: ControladorEstado
ClientBridge.SairParkour = nil :: (() -> ())?

-- ═══════════════════════════════════════════════════════════════════
-- IMPULSO DE ATAQUE
-- ═══════════════════════════════════════════════════════════════════
--- Aplica impulso físico na direção do ataque
--- Definido por: ControladorEstado
ClientBridge.AplicarImpulsoAtaque = nil :: ((string) -> ())?

-- ═══════════════════════════════════════════════════════════════════
-- INPUT (EntradaJogador)
-- ═══════════════════════════════════════════════════════════════════
--- Verifica se M1 está sendo pressionado
--- Definido por: EntradaJogador
ClientBridge.EstaSegurandoM1 = nil :: (() -> boolean)?

--- Verifica se está carregando ataque pesado
--- Definido por: EntradaJogador
ClientBridge.EstaCarregandoPesado = nil :: (() -> boolean)?

-- ═══════════════════════════════════════════════════════════════════
-- EQUIPAMENTO (EquipamentoController)
-- ═══════════════════════════════════════════════════════════════════
--- Retorna o Tool equipado em um slot de braço
--- Definido por: EquipamentoController
ClientBridge.ObterEquipamentoBraco = nil :: ((string) -> Tool?)?

--- Retorna a Categoria da arma equipada no RightArm
--- Definido por: EquipamentoController
ClientBridge.ObterCategoriaRightArm = nil :: (() -> string?)?

--- Retorna o Tool equipado em um slot do corpo
--- Definido por: EquipamentoController
ClientBridge.ObterEquipamentoCorpo = nil :: ((string) -> Tool?)?

-- ═══════════════════════════════════════════════════════════════════
-- STATUS LOCAL (GerenciadorStatusLocal)
-- ═══════════════════════════════════════════════════════════════════
--- Obtém a pasta StatusLocal do character atual
--- Definido por: GerenciadorStatusLocal
ClientBridge.ObterStatusLocal = nil :: (() -> Folder?)?

--- Atualiza um valor na pasta StatusLocal
--- Definido por: GerenciadorStatusLocal
ClientBridge.AtualizarStatusLocal = nil :: ((string, any) -> ())?

--- Lê um valor da pasta StatusLocal
--- Definido por: GerenciadorStatusLocal
ClientBridge.LerStatusLocal = nil :: ((string) -> any)?

return ClientBridge
