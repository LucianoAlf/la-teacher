import { Button, Card, EmptyState, Skeleton } from '../../components/ui'
import { formatDiaCurto, isHoje } from '../../lib/date'
import { contarRegistradas } from './aula'
import type { AgendaAula } from '../../lib/api'
import { AgendaAulaRow } from './AgendaAulaRow'
import type { EstadoAgenda } from './useAgenda'

interface Props {
  data: string
  estado: EstadoAgenda
  onRetry: () => void
  /** Abrir a gravação da aula tocada (P5). */
  onGravar: (aula: AgendaAula) => void
  /** Título do card. Default: "Hoje" quando é hoje, senão o dia curto. */
  titulo?: string
}

/** Card com as aulas de um dia (skeleton/erro/vazio/lista). Usado na Home e na Agenda. */
export function CardAulasDoDia({ data, estado, onRetry, onGravar, titulo }: Props) {
  const tit = titulo ?? (isHoje(data) ? 'Hoje' : formatDiaCurto(data))

  if (estado.fase === 'carregando') {
    return (
      <Card title={tit} icon="fa-solid fa-calendar-day">
        <div className="space-y-3 py-1">
          {[0, 1, 2].map((i) => (
            <div key={i} className="flex items-center gap-3">
              <Skeleton className="h-4 w-9" />
              <div className="flex-1 space-y-[6px]">
                <Skeleton className="h-[14px] w-1/2" />
                <Skeleton className="h-3 w-1/3" />
              </div>
              <Skeleton className="h-4 w-16" />
            </div>
          ))}
        </div>
      </Card>
    )
  }

  if (estado.fase === 'erro') {
    return (
      <Card title={tit} icon="fa-solid fa-calendar-day">
        <EmptyState
          icon="fa-solid fa-triangle-exclamation"
          title="Não consegui carregar"
          description="Deu um problema ao buscar suas aulas. Verifica a conexão e tenta de novo."
          action={
            <Button size="sm" onClick={onRetry}>
              <i className="fa-solid fa-rotate-right" aria-hidden="true" /> Tentar de novo
            </Button>
          }
        />
      </Card>
    )
  }

  if (estado.fase === 'sem_vinculo') {
    return (
      <Card title={tit} icon="fa-solid fa-calendar-day">
        <EmptyState
          icon="fa-solid fa-id-badge"
          title="Acesso não ativado"
          description="Fala com a coordenação pra vincular seu login a um professor."
        />
      </Card>
    )
  }

  const { aulas, total } = estado.agenda
  const registradas = contarRegistradas(aulas)

  if (total === 0) {
    return (
      <Card title={tit} icon="fa-solid fa-calendar-day">
        <EmptyState
          icon="fa-solid fa-music"
          title="Nenhuma aula neste dia 🎵"
          description={
            isHoje(data)
              ? 'Dia livre por aqui. Use as setas pra ver outro dia da sua agenda.'
              : 'Sem aulas nesta data. Navegue pelos dias com as setas acima.'
          }
        />
      </Card>
    )
  }

  return (
    <Card title={tit} icon="fa-solid fa-calendar-day" right={`${registradas} de ${total} registradas`}>
      {aulas.map((a) => (
        <AgendaAulaRow key={a.aula_local_id} aula={a} onGravar={onGravar} />
      ))}
    </Card>
  )
}
