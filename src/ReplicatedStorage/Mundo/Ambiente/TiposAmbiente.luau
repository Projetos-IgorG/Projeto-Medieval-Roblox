local TiposAmbiente = {}

export type Propriedades = { [string]: any }

export type TransicaoAmbiente = {
	duracao: number?,
	estilo: Enum.EasingStyle?,
	direcao: Enum.EasingDirection?,
	pesoClima: number?,
}

export type EfeitosAmbiente = {
	Atmosphere: Propriedades?,
	BloomEffect: Propriedades?,
	DepthOfFieldEffect: Propriedades?,
	SunRaysEffect: Propriedades?,
	ColorCorrectionEffect: Propriedades?,
}

export type TemplateClima = {
	id: string,
	nome: string,
	descricao: string?,
	pesoClima: number?,
	transicao: TransicaoAmbiente?,
	lighting: Propriedades?,
	efeitos: EfeitosAmbiente?,
	clouds: Propriedades?,
}

export type TemplateAmbiente = {
	id: string,
	nome: string,
	descricao: string?,
	ordem: number?,
	base: TemplateClima?,
	ordemClimas: { string }?,
	climas: { [string]: TemplateClima },
}

export type EstadoAmbienteResolvido = {
	ambienteId: string,
	ambienteNome: string,
	climaId: string,
	climaNome: string,
	minutosDoDia: number,
	horaTexto: string,
	faseDia: string,
	transicao: TransicaoAmbiente,
	lighting: Propriedades,
	efeitos: EfeitosAmbiente,
	clouds: Propriedades,
}

TiposAmbiente.EfeitosSuportados = table.freeze({
	"Atmosphere",
	"BloomEffect",
	"DepthOfFieldEffect",
	"SunRaysEffect",
	"ColorCorrectionEffect",
})

TiposAmbiente.PropriedadesLighting = table.freeze({
	"Brightness",
	"ExposureCompensation",
	"Ambient",
	"OutdoorAmbient",
	"FogColor",
	"FogStart",
	"FogEnd",
	"EnvironmentDiffuseScale",
	"EnvironmentSpecularScale",
})

TiposAmbiente.PropriedadesClouds = table.freeze({
	"Enabled",
	"Cover",
	"Density",
	"Color",
})

return TiposAmbiente