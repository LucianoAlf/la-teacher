import { useEffect, useState } from 'react'
import { isSemVinculo, minhaAgendaSessao } from '../../lib/api'
import { diasDaSemana } from '../../lib/date'

/** Mapa data(YYYY-MM-DD) → nº de SESSÕES, para a strip da semana. */
export type ContagemSemana = Record<string, number>

/**
 * Conta as sessões de cada dia da semana que contém `dataRef` (7 chamadas em
 * paralelo). Degrada em silêncio: dia que falhar fica sem contagem, não quebra.
 */
export function useSemana(dataRef: string) {
  const [contagem, setContagem] = useState<ContagemSemana>({})
  const dias = diasDaSemana(dataRef)
  const chave = dias[0] // segunda da semana identifica a semana

  useEffect(() => {
    let vivo = true
    Promise.all(
      dias.map((d) =>
        minhaAgendaSessao(d)
          .then((res) => (isSemVinculo(res) ? 0 : res.length))
          .catch(() => 0),
      ),
    ).then((totais) => {
      if (!vivo) return
      const map: ContagemSemana = {}
      dias.forEach((d, i) => (map[d] = totais[i]))
      setContagem(map)
    })
    return () => {
      vivo = false
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [chave])

  return { dias, contagem }
}
