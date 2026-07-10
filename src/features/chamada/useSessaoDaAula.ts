import { useCallback, useEffect, useState } from 'react'
import { isSemVinculo, minhaAgendaSessao, type SessaoAula } from '../../lib/api'
import { addDias, dataBRTDoTimestamp, hojeBRT } from '../../lib/date'
import { agruparSessoes } from '../agenda/sessao'

export type EstadoSessaoAula =
  | { fase: 'carregando' }
  | { fase: 'ok'; sessao: SessaoAula; data: string }
  | { fase: 'nao_encontrada' }
  | { fase: 'sem_vinculo' }
  | { fase: 'erro' }

/**
 * Sessão AGRUPADA que contém a aula (âncora ou paralela). Quando a navegação
 * já trouxe a sessão (state), usa direto — recarregar() rebusca no banco pela
 * data dela. Em deep link (sem state), procura em hoje e ontem — o alcance
 * útil da janela de chamada (24h).
 */
export function useSessaoDaAula(aulaId: number, inicial?: SessaoAula) {
  const [estado, setEstado] = useState<EstadoSessaoAula>(() =>
    inicial
      ? { fase: 'ok', sessao: inicial, data: dataBRTDoTimestamp(inicial.data_hora_inicio) }
      : { fase: 'carregando' },
  )
  const [tentativa, setTentativa] = useState(0)

  const recarregar = useCallback(() => setTentativa((t) => t + 1), [])

  useEffect(() => {
    if (tentativa === 0 && inicial) return // sessão veio da navegação — sem fetch
    let vivo = true
    setEstado({ fase: 'carregando' })
    const datas = inicial
      ? [dataBRTDoTimestamp(inicial.data_hora_inicio)]
      : [hojeBRT(), addDias(hojeBRT(), -1)]
    ;(async () => {
      for (const data of datas) {
        const res = await minhaAgendaSessao(data)
        if (!vivo) return
        if (isSemVinculo(res)) {
          setEstado({ fase: 'sem_vinculo' })
          return
        }
        const sessao = agruparSessoes(res).find(
          (s) => s.aula_id_ancora === aulaId || s.aulas_agrupadas?.includes(aulaId),
        )
        if (sessao) {
          setEstado({ fase: 'ok', sessao, data })
          return
        }
      }
      if (vivo) setEstado({ fase: 'nao_encontrada' })
    })().catch(() => vivo && setEstado({ fase: 'erro' }))
    return () => {
      vivo = false
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [aulaId, tentativa])

  return { estado, recarregar }
}
