import { isSemVinculo, minhaAgendaSessao, type SessaoAula } from '../../lib/api'
import { addDias, hojeBRT } from '../../lib/date'
import { alunosPendentes, statusSessao } from './sessao'

export interface Pendencias {
  /** Data (YYYY-MM-DD) do dia com sessões pendentes encontrado. */
  data: string
  sessoes: SessaoAula[]
}

/**
 * Pendências = sessões sem registro do dia anterior COM aulas mais recente.
 * Varre para trás até `maxDias` até achar o último dia que teve aula.
 * Sessão onde só quem faltou ficou sem registro NÃO é pendência.
 */
export async function buscarPendencias(maxDias = 21): Promise<Pendencias | null> {
  const now = new Date()
  let data = addDias(hojeBRT(), -1)
  for (let i = 0; i < maxDias; i++, data = addDias(data, -1)) {
    const res = await minhaAgendaSessao(data)
    if (isSemVinculo(res)) return null
    if (res.length > 0) {
      const pendentes = res.filter(
        (s) => statusSessao(s, now) === 'pendente' && alunosPendentes(s, now).length > 0,
      )
      return pendentes.length > 0 ? { data, sessoes: pendentes } : null
    }
  }
  return null
}
