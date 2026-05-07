--[[
    Script: PonteCliente.luau
    Caminho: src/ReplicatedStorage/Jogador/ComunicacaoCliente
    Responsabilidade: Centraliza ponte de comunicacao do cliente com sistemas compartilhados.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao roda sozinho nem cria fluxo de jogo por conta propria; depende dos scripts que importam este modulo.
]]
local ClientBridge = {}

ClientBridge.MarcarContinuarCombo = nil :: (() -> boolean)?

ClientBridge.EstaJanelaComboAtiva = nil :: (() -> boolean)?

ClientBridge.EstaComboAtivo = nil :: (() -> boolean)?

ClientBridge.ContinuarAtaquePesado = nil :: (() -> boolean)?

ClientBridge.EstaAtaquePesadoAtivo = nil :: (() -> boolean)?

ClientBridge.EstaAguardandoSoltarPesado = nil :: (() -> boolean)?

ClientBridge.TentarCancelarAtaquePorDefesa = nil :: (() -> (boolean, string?))?

ClientBridge.ResolverCancelPendente = nil :: (() -> ())?

ClientBridge.CancelarCancelPendente = nil :: (() -> ())?

ClientBridge.EstaEmAnimacaoEquip = nil :: (() -> boolean)?

ClientBridge.PodeAlterarTool = nil :: (() -> boolean)?

ClientBridge.OnEquipAnimacaoTerminou = nil :: ((number) -> ())?

ClientBridge.CalcularDirecaoDash = nil :: (() -> string)?

ClientBridge.EstaEmDash = nil :: (() -> boolean)?

ClientBridge.EstaEmParkour = nil :: (() -> boolean)?

ClientBridge.EntrarParkour = nil :: (() -> ())?

ClientBridge.SairParkour = nil :: (() -> ())?

ClientBridge.AplicarImpulsoAtaque = nil :: ((string) -> ())?

ClientBridge.EstaSegurandoM1 = nil :: (() -> boolean)?

ClientBridge.EstaCarregandoPesado = nil :: (() -> boolean)?

ClientBridge.ObterEquipamentoBraco = nil :: ((string) -> Tool?)?

ClientBridge.ObterCategoriaRightArm = nil :: (() -> string?)?

ClientBridge.ObterEquipamentoCorpo = nil :: ((string) -> Tool?)?

ClientBridge.ObterStatusLocal = nil :: (() -> Folder?)?

ClientBridge.AtualizarStatusLocal = nil :: ((string, any) -> ())?

ClientBridge.LerStatusLocal = nil :: ((string) -> any)?

ClientBridge.EstaEmPrimeiraPessoa = nil :: (() -> boolean)?

return ClientBridge
