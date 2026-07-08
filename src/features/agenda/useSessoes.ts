import { useCallback, useEffect, useState } from 'react'
import { isSemVinculo, minhaAgendaSessao, type SessaoAula } from '../../lib/api'

export type EstadoSessoes =
  | { fase: 'carregando' }
  | { fase: 'ok'; sessoes: SessaoAula[] }
  | { fase: 'sem_vinculo' }
  | { fase: 'erro' }

/** Sessões de um dia (app_minha_agenda_sessao) com estados de UI. */
export function useSessoes(data: string) {
  const [estado, setEstado] = useState<EstadoSessoes>({ fase: 'carregando' })
  const [tentativa, setTentativa] = useState(0)

  const recarregar = useCallback(() => setTentativa((t) => t + 1), [])

  useEffect(() => {
    let vivo = true
    setEstado({ fase: 'carregando' })
    minhaAgendaSessao(data)
      .then((res) => {
        if (!vivo) return
        if (isSemVinculo(res)) setEstado({ fase: 'sem_vinculo' })
        else setEstado({ fase: 'ok', sessoes: res })
      })
      .catch(() => vivo && setEstado({ fase: 'erro' }))
    return () => {
      vivo = false
    }
  }, [data, tentativa])

  return { estado, recarregar }
}
