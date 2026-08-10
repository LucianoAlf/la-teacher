import type { RadarLinha } from '../../lib/api'

/**
 * O vocabulário do Radar — o único lugar onde chave de banco vira português.
 *
 * A nota abre em `decomposicao`, e o que vem de lá é chave (`faltas_mes`) e
 * valor formatado em SQL (`2 falta(s) seguida(s)`, `verde`, `as_vezes`). Isso
 * apareceu cru no card do aluno até o Alf ver a tela em 10/08/2026. Traduzir na
 * hora, dentro do JSX, era o caminho pra três telas com três nomes pro mesmo
 * sinal — então o vocabulário mora aqui e a tela só consome.
 *
 * Os rótulos são os MESMOS da tela de Réguas (`radar_config.rotulo`, migrations
 * 082 e 088): quem afina o peso de "Faltas do mês" tem que reconhecer a linha
 * que ele afinou dentro do card.
 */
const ROTULO_SINAL: Record<string, string> = {
  absenteismo: 'Absenteísmo',
  feedback: 'Feedback do professor',
  pratica: 'Prática em casa',
  faltas_mes: 'Faltas do mês',
  faltas_consecutivas: 'Faltas seguidas',
}

/** `verde` é dado; "saudável" é o que a coordenação lê na tela. */
export const ROTULO_CORACAO: Record<string, string> = {
  verde: 'saudável',
  amarelo: 'atenção',
  vermelho: 'crítico',
}

export const COR_CORACAO: Record<string, string> = {
  verde: 'text-success-text',
  amarelo: 'text-warning-text',
  vermelho: 'text-danger-text',
}

/** "não" sozinho não diz de que pergunta veio (mesma regra do semáforo). */
const VALOR_PRATICA: Record<string, string> = {
  sim: 'pratica em casa',
  as_vezes: 'pratica às vezes',
  nao: 'não pratica',
}

export const COR_STATUS: Record<RadarLinha['status'], string> = {
  critico: 'text-danger-text',
  atencao: 'text-warning-text',
  saudavel: 'text-success-text',
  sem_nota: 'text-text-muted',
}

/** Fundo do selo da nota — o par `-soft` do mesmo token da cor do texto. */
export const FUNDO_STATUS: Record<RadarLinha['status'], string> = {
  critico: 'bg-danger-soft',
  atencao: 'bg-warning-soft',
  saudavel: 'bg-success-soft',
  sem_nota: 'bg-bg-inset',
}

/** Preenchimento das barras de contribuição (cor cheia, não a `-soft`). */
const BARRA_STATUS: Record<RadarLinha['status'], string> = {
  critico: 'bg-danger',
  atencao: 'bg-warning',
  saudavel: 'bg-success',
  sem_nota: 'bg-border-strong',
}

export const ROTULO_STATUS: Record<RadarLinha['status'], string> = {
  critico: 'Crítico',
  atencao: 'Atenção',
  saudavel: 'Saudável',
  sem_nota: 'Sem nota',
}

export function pct(n: number | null | undefined): string {
  if (n == null) return '—'
  return `${Math.round(n)}%`
}

export function rotuloSinal(sinal: string): string {
  const conhecido = ROTULO_SINAL[sinal]
  if (conhecido) return conhecido
  // Sinal novo no backend não pode aparecer como `chave_crua`: vira frase até
  // alguém dar um nome de gente pra ele aqui.
  const frase = sinal.replace(/_/g, ' ')
  return frase.charAt(0).toUpperCase() + frase.slice(1)
}

/**
 * O valor do sinal em português, montado dos campos TIPADOS da linha — não do
 * texto que o SQL formatou.
 *
 * Reaproveitar `d.valor` seria mais curto e é justamente o que trouxe
 * `100.0% (2 de 2)` e `2 falta(s) seguida(s)` pra tela. O fallback (sinal que
 * eu não conheço) usa o texto do banco só limpando o `(s)`.
 */
export function valorSinal(
  sinal: string,
  linha: RadarLinha,
  bruto: string | null,
): string | null {
  switch (sinal) {
    case 'absenteismo':
      if (linha.absenteismo_pct == null) return null
      return `${pct(linha.absenteismo_pct)} · ${linha.faltas_janela} de ${linha.aulas_medidas} ${
        linha.aulas_medidas === 1 ? 'aula' : 'aulas'
      }`
    case 'feedback':
      return linha.feedback ? (ROTULO_CORACAO[linha.feedback] ?? linha.feedback) : null
    case 'pratica':
      return linha.pratica_em_casa
        ? (VALOR_PRATICA[linha.pratica_em_casa] ?? linha.pratica_em_casa)
        : null
    case 'faltas_mes':
      if (linha.aulas_mes === 0) return null
      return `${linha.faltas_mes === 1 ? '1 falta' : `${linha.faltas_mes} faltas`} em ${
        linha.aulas_mes
      } ${linha.aulas_mes === 1 ? 'aula' : 'aulas'} do mês`
    case 'faltas_consecutivas':
      return linha.faltas_consecutivas === 1
        ? '1 falta seguida'
        : `${linha.faltas_consecutivas} faltas seguidas`
    default:
      return bruto == null ? null : bruto.replace(/\(s\)/g, 's')
  }
}

/**
 * POR QUE o sinal ficou fora da conta — e são dois motivos diferentes.
 *
 * "Sem resposta ainda" só vale pro que depende do professor responder. Dizer
 * isso do absenteísmo é errado duas vezes: ninguém responde absenteísmo, e o
 * que falta ali é aula medida. Pior: com o motivo genérico a tela mostrava
 * "Faltas seguidas · fora da conta" e, embaixo, "0 faltas seguidas" — o número
 * que a guarda da 088 existe pra NÃO afirmar.
 */
export function motivoSemDado(sinal: string): string {
  switch (sinal) {
    case 'feedback':
    case 'pratica':
      return 'professor ainda não respondeu'
    case 'absenteismo':
    case 'faltas_mes':
    case 'faltas_consecutivas':
      return 'ainda sem aula medida'
    default:
      return 'sem dado'
  }
}

/**
 * A cor de um sinal segue as MESMAS faixas da nota (`radar_config`), não uma
 * régua minha: 0-100 onde mais é melhor, então crítico/atenção/saudável valem
 * igual pro sinal e pro total. Faixa vinda do banco, com o padrão de fábrica
 * como rede.
 */
export function statusDoScore(
  score: number | null,
  config: Record<string, number>,
): RadarLinha['status'] {
  if (score == null) return 'sem_nota'
  if (score < (config.faixa_critico ?? 40)) return 'critico'
  if (score < (config.faixa_saudavel ?? 70)) return 'atencao'
  return 'saudavel'
}

export function corDaBarra(status: RadarLinha['status']): string {
  return BARRA_STATUS[status]
}
