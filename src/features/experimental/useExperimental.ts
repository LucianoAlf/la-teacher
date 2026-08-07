import { useCallback, useEffect, useState } from 'react'
import { experimentalDoProfessor, type ExperimentalDoProfessor } from '../../lib/api'

export type EstadoExperimental =
  | { fase: 'carregando' }
  | { fase: 'pronto'; dados: ExperimentalDoProfessor }
  | { fase: 'erro'; mensagem: string }

/**
 * Carrega a experimental do professor logado.
 *
 * A RPC (045) LEVANTA EXCEÇÃO quando a aula é de outro professor, em vez de
 * devolver vazio — a posse mora no JOIN. Aqui isso vira mensagem, não tela
 * branca: "não é sua" é uma resposta, e o professor precisa entender que não
 * foi bug.
 */
export function useExperimental(vinculoId: number | null): {
  estado: EstadoExperimental
  recarregar: () => void
} {
  const [estado, setEstado] = useState<EstadoExperimental>({ fase: 'carregando' })
  const [tick, setTick] = useState(0)

  const recarregar = useCallback(() => setTick((t) => t + 1), [])

  useEffect(() => {
    if (vinculoId == null || Number.isNaN(vinculoId)) {
      setEstado({ fase: 'erro', mensagem: 'Experimental não encontrada.' })
      return
    }
    let vivo = true
    setEstado({ fase: 'carregando' })
    experimentalDoProfessor(vinculoId)
      .then((dados) => {
        if (vivo) setEstado({ fase: 'pronto', dados })
      })
      .catch((e: unknown) => {
        if (!vivo) return
        const msg = String((e as { message?: string })?.message ?? e)
        setEstado({
          fase: 'erro',
          mensagem: msg.includes('outro_professor') || msg.includes('nao_encontrada')
            ? 'Esta experimental não é da sua agenda.'
            : msg.includes('sem_professor_vinculado')
              ? 'Seu login ainda não está ligado a um professor. Fala com a coordenação.'
              : 'Não consegui carregar agora. Tenta de novo em instantes.',
        })
      })
    return () => {
      vivo = false
    }
  }, [vinculoId, tick])

  return { estado, recarregar }
}
