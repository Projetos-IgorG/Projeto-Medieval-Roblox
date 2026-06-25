--[[
    Script: PonteCliente.luau
    Caminho: src/ReplicatedStorage/Jogador/ComunicacaoCliente
    Responsabilidade: Centraliza ponte de comunicacao do cliente com sistemas compartilhados.
    Uso: ModuleScript; use require(caminho) e chame as funcoes ou tabelas retornadas.
    Nao faz: Nao roda sozinho nem cria fluxo de jogo por conta propria; depende dos scripts que importam este modulo.
]]

export type ClientBridgeType = {
	MarcarContinuarCombo: (() -> boolean)?,
	EstaJanelaComboAtiva: (() -> boolean)?,
	EstaComboAtivo: (() -> boolean)?,
	TentarFintar: (() -> (boolean, string?))?,
	ResolverFintaPendente: (() -> ())?,
	CancelarFintaPendente: (() -> ())?,
	EstaEmAnimacaoEquip: (() -> boolean)?,
	PodeAlterarTool: (() -> boolean)?,
	OnEquipAnimacaoTerminou: ((number) -> ())?,
	CalcularDirecaoRoll: ((boolean?) -> string)?,
	EstaEmRoll: (() -> boolean)?,
	PreRollActive: boolean?,
	CFrameRotacaoRoll: CFrame?,
	CFrameRotacaoOriginalRoll: CFrame?,
	DirecaoMovimentoRoll: Vector3?,
	UltimoRollTime: number,
	CalcularDirecaoDash: (() -> string)?,
	EstaEmDash: (() -> boolean)?,
	PreDashActive: boolean?,
	CFrameRotacaoDash: CFrame?,
	UltimoDashTime: number,
	EstaEmParkour: (() -> boolean)?,
	EntrarParkour: (() -> ())?,
	SairParkour: (() -> ())?,
	AplicarImpulsoAtaque: ((string) -> ())?,
	EstaSegurandoM1: (() -> boolean)?,
	EstaSegurandoM2: (() -> boolean)?,
	SoltouM1: (() -> ())?,
	PodeAtacar: (() -> boolean)?,
	PredictAnimation: ((nomeAnimacao: string, loop: boolean, velocidade: number) -> ())?,
	PredictStopAnimation: (() -> ())?,
	PredictCancel: (() -> ())?,
	ObterEquipamentoBraco: ((string) -> Tool?)?,
	ObterCategoriaRightArm: (() -> string?)?,
	ObterEquipamentoCorpo: ((string) -> Tool?)?,
	ObterStatusLocal: (() -> Folder?)?,
	AtualizarStatusLocal: ((string, any) -> ())?,
	LerStatusLocal: ((string) -> any)?,
	EstaEmPrimeiraPessoa: (() -> boolean)?,
}

local ClientBridge = {} :: ClientBridgeType

ClientBridge.MarcarContinuarCombo = nil
ClientBridge.EstaJanelaComboAtiva = nil
ClientBridge.EstaComboAtivo = nil
ClientBridge.TentarFintar = nil
ClientBridge.ResolverFintaPendente = nil
ClientBridge.CancelarFintaPendente = nil
ClientBridge.EstaEmAnimacaoEquip = nil
ClientBridge.PodeAlterarTool = nil
ClientBridge.OnEquipAnimacaoTerminou = nil
ClientBridge.CalcularDirecaoRoll = nil
ClientBridge.EstaEmRoll = nil
ClientBridge.PreRollActive = nil
ClientBridge.CFrameRotacaoRoll = nil
ClientBridge.CFrameRotacaoOriginalRoll = nil
ClientBridge.DirecaoMovimentoRoll = nil
ClientBridge.UltimoRollTime = 0
ClientBridge.CalcularDirecaoDash = nil
ClientBridge.EstaEmDash = nil
ClientBridge.PreDashActive = nil
ClientBridge.CFrameRotacaoDash = nil
ClientBridge.UltimoDashTime = 0
ClientBridge.EstaEmParkour = nil
ClientBridge.EntrarParkour = nil
ClientBridge.SairParkour = nil
ClientBridge.AplicarImpulsoAtaque = nil
ClientBridge.EstaSegurandoM1 = nil
ClientBridge.EstaSegurandoM2 = nil
ClientBridge.SoltouM1 = nil
ClientBridge.PodeAtacar = nil
ClientBridge.PredictAnimation = nil
ClientBridge.PredictStopAnimation = nil
ClientBridge.PredictCancel = nil
ClientBridge.ObterEquipamentoBraco = nil
ClientBridge.ObterCategoriaRightArm = nil
ClientBridge.ObterEquipamentoCorpo = nil
ClientBridge.ObterStatusLocal = nil
ClientBridge.AtualizarStatusLocal = nil
ClientBridge.LerStatusLocal = nil
ClientBridge.EstaEmPrimeiraPessoa = nil

return ClientBridge
