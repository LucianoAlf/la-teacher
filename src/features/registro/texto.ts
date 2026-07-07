import type { AulaContexto, RegistroRow } from '../../lib/api'

/**
 * Regeneração DETERMINÍSTICA do texto_consolidado no formato da Tese
 * (mesma estrutura da Alma v1.1). Usa os campos VERBATIM — o app formata,
 * nunca inventa conteúdo. É o texto que registrar_aula_fabio grava na aula
 * de cada aluno (bloco comum + bloco individual).
 */

export const CUTUCADA_LINHA = '— (a completar com o professor)'

function str(v: unknown): string | null {
  const s = typeof v === 'string' ? v.trim() : ''
  return s ? s : null
}

function cabecalho(aula: AulaContexto | null): string {
  const data = aula?.data_aula ? aula.data_aula.slice(8, 10) + '/' + aula.data_aula.slice(5, 7) : null
  const onde = aula?.turma || aula?.curso || 'Aula'
  return `AULA — ${data ? `${data} · ` : ''}${onde}`
}

/** Bloco comum da turma, com rótulos universais e campos verbatim. */
export function blocoComum(troncoCampos: Record<string, unknown>): string {
  const linhas: string[] = []
  const atividades = str(troncoCampos.atividades)
  const objetivo = str(troncoCampos.objetivo)
  if (atividades) linhas.push(`Atividades: ${atividades}`)
  if (objetivo) linhas.push(`Objetivo trabalhado: ${objetivo}`)
  return linhas.join('\n')
}

/** Texto final de UMA fatia: cabeçalho + bloco comum + bloco do aluno + dever. */
export function textoFatia(
  aula: AulaContexto | null,
  troncoCampos: Record<string, unknown>,
  fatiaCampos: Record<string, unknown>,
): string {
  const nome = str(fatiaCampos.aluno_nome) ?? 'Aluno'
  const dever = str(troncoCampos.dever_casa)

  const blocos: string[] = [cabecalho(aula)]
  const comum = blocoComum(troncoCampos)
  if (comum) blocos.push(comum)

  blocos.push(
    [
      nome,
      `Progresso: ${str(fatiaCampos.progresso) ?? CUTUCADA_LINHA}`,
      `Próximo passo: ${str(fatiaCampos.proximo_passo) ?? CUTUCADA_LINHA}`,
      `Observação: ${str(fatiaCampos.observacao) ?? CUTUCADA_LINHA}`,
    ].join('\n'),
  )

  if (dever) blocos.push(`🏠 Dever de casa: ${dever}`)
  return blocos.join('\n\n')
}

/** Versão TURMA (conferência do professor) — o comum + dever, sem fatias. */
export function textoTronco(aula: AulaContexto | null, troncoCampos: Record<string, unknown>): string {
  const dever = str(troncoCampos.dever_casa)
  const blocos: string[] = [cabecalho(aula)]
  const comum = blocoComum(troncoCampos)
  if (comum) blocos.push(comum)
  if (dever) blocos.push(`🏠 Dever de casa: ${dever}`)
  return blocos.join('\n\n')
}

export function presencaDaFatia(f: RegistroRow): 'presente' | 'ausente' {
  return (f.campos.presenca as string) === 'ausente' ? 'ausente' : 'presente'
}
