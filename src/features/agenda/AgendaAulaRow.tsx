import type { ReactNode } from 'react'
import type { AgendaAula } from '../../lib/api'
import { AulaRow, Badge, type AulaStatus } from '../../components/ui'
import { detalheAula, horaAula, nomeAula, statusAula } from './aula'

interface Props {
  aula: AgendaAula
  now?: Date
  /** Abrir a gravação desta aula (P5) — linha e badge navegam pra /app/gravar/:id. */
  onGravar?: (aula: AgendaAula) => void
}

/** AulaRow já com nome/detalhe/hora e badge+dot derivados do status. */
export function AgendaAulaRow({ aula, now, onGravar }: Props) {
  const status = statusAula(aula, now)

  let dot: AulaStatus | undefined
  let badge: ReactNode

  if (status === 'registrada') {
    dot = 'ok'
    badge = (
      <Badge variant="ok" icon="fa-solid fa-check">
        Registrada
      </Badge>
    )
  } else if (status === 'agora') {
    dot = 'now'
    badge = (
      <Badge variant="brand" icon="fa-solid fa-microphone">
        Registrar
      </Badge>
    )
  } else if (status === 'sem_registro') {
    badge = (
      <Badge variant="warn" icon="fa-solid fa-clock">
        Sem registro
      </Badge>
    )
  } else {
    dot = 'next'
  }

  // Aula sem registro (passada, agora ou futura) é tocável → gravação.
  const clicavel = status !== 'registrada' && onGravar ? () => onGravar(aula) : undefined

  return (
    <AulaRow
      hora={horaAula(aula)}
      titulo={nomeAula(aula)}
      detalhe={detalheAula(aula)}
      badge={badge}
      status={dot}
      onClick={clicavel}
    />
  )
}
