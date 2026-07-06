import { isSemVinculo, minhaAgenda, type AgendaAula } from '../../lib/api'
import { addDias, hojeBRT } from '../../lib/date'
import { temRegistro } from './aula'

export interface Pendencias {
  /** Data (YYYY-MM-DD) do dia com aulas pendentes encontrado. */
  data: string
  aulas: AgendaAula[]
}

/**
 * Pendências = aulas sem registro do dia anterior COM aulas mais recente.
 * O espelho de aulas pode estar defasado (ex.: "ontem" vazio), então
 * varremos para trás até `maxDias` até achar o último dia que teve aula.
 * Retorna null se nada pendente na janela.
 */
export async function buscarPendencias(maxDias = 21): Promise<Pendencias | null> {
  let data = addDias(hojeBRT(), -1)
  for (let i = 0; i < maxDias; i++, data = addDias(data, -1)) {
    const res = await minhaAgenda(data)
    if (isSemVinculo(res)) return null
    if (res.total > 0) {
      // Primeiro dia (mais recente) com aulas: as sem registro são as pendências.
      const pendentes = res.aulas.filter((a) => !temRegistro(a) && !a.cancelada)
      return pendentes.length > 0 ? { data, aulas: pendentes } : null
    }
  }
  return null
}
