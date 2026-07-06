import { useCallback, useEffect, useState } from 'react'
import { isSemVinculo, minhaCarteira, type CarteiraAluno } from '../../lib/api'

export type EstadoCarteira =
  | { fase: 'carregando' }
  | { fase: 'ok'; alunos: CarteiraAluno[] }
  | { fase: 'sem_vinculo' }
  | { fase: 'erro' }

/** Carrega a carteira do professor (app_minha_carteira) com estados de UI. */
export function useCarteira() {
  const [estado, setEstado] = useState<EstadoCarteira>({ fase: 'carregando' })
  const [tentativa, setTentativa] = useState(0)

  const recarregar = useCallback(() => setTentativa((t) => t + 1), [])

  useEffect(() => {
    let vivo = true
    setEstado({ fase: 'carregando' })
    minhaCarteira()
      .then((res) => {
        if (!vivo) return
        if (isSemVinculo(res)) setEstado({ fase: 'sem_vinculo' })
        else setEstado({ fase: 'ok', alunos: res })
      })
      .catch(() => vivo && setEstado({ fase: 'erro' }))
    return () => {
      vivo = false
    }
  }, [tentativa])

  return { estado, recarregar }
}
