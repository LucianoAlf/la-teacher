import { useCallback, useEffect, useState } from 'react'
import { isSemVinculo, minhaAgenda, type Agenda } from '../../lib/api'

type Estado =
  | { fase: 'carregando' }
  | { fase: 'ok'; agenda: Agenda }
  | { fase: 'sem_vinculo' }
  | { fase: 'erro' }

/** Busca a agenda de uma data (app_minha_agenda) com estados de UI. */
export function useAgenda(data: string) {
  const [estado, setEstado] = useState<Estado>({ fase: 'carregando' })
  const [tentativa, setTentativa] = useState(0)

  const recarregar = useCallback(() => setTentativa((t) => t + 1), [])

  useEffect(() => {
    let vivo = true
    setEstado({ fase: 'carregando' })
    minhaAgenda(data)
      .then((res) => {
        if (!vivo) return
        if (isSemVinculo(res)) setEstado({ fase: 'sem_vinculo' })
        else setEstado({ fase: 'ok', agenda: res })
      })
      .catch(() => vivo && setEstado({ fase: 'erro' }))
    return () => {
      vivo = false
    }
  }, [data, tentativa])

  return { estado, recarregar }
}
