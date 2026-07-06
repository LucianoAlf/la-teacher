import type { AgendaAula } from '../../lib/api'
import { AulaRow, Badge, type AulaStatus } from '../../components/ui'
import { detalheAula, horaAula, nomeAula, statusAula } from './aula'

interface Props {
  aula: AgendaAula
  now?: Date
  /** Disparado ao tocar no badge "Registrar" (fluxo real é do Sprint 3). */
  onRegistrar?: () => void
}

/** AulaRow já com nome/detalhe/hora e badge+dot derivados do status. */
export function AgendaAulaRow({ aula, now, onRegistrar }: Props) {
  const status = statusAula(aula, now)

  let dot: AulaStatus | undefined
  let badge: React.ReactNode

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
      <Badge variant="brand" icon="fa-solid fa-microphone" onClick={onRegistrar}>
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

  return (
    <AulaRow hora={horaAula(aula)} titulo={nomeAula(aula)} detalhe={detalheAula(aula)} badge={badge} status={dot} />
  )
}
