import { Button, Card, EmptyState, Skeleton } from '../../components/ui'
import type { SessaoAula } from '../../lib/api'
import { formatDiaCurto, isHoje } from '../../lib/date'
import { contarChamadasFeitas } from './sessao'
import { SessaoRow } from './SessaoRow'
import type { EstadoSessoes } from './useSessoes'

interface Props {
  data: string
  estado: EstadoSessoes
  onRetry: () => void
  /** Abrir a sessão tocada (chamada). */
  onAbrir: (sessao: SessaoAula) => void
  /** Gravar a aula direto da linha (botão de microfone quando na janela). */
  onGravar?: (sessao: SessaoAula) => void
  titulo?: string
}

/** Card com as SESSÕES de um dia (skeleton/erro/vazio/lista). Home e Agenda. */
export function CardSessoesDoDia({ data, estado, onRetry, onAbrir, onGravar, titulo }: Props) {
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
                <Skeleton className="h-3 w-2/3" />
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

  const { sessoes } = estado

  if (sessoes.length === 0) {
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

  const feitas = contarChamadasFeitas(sessoes)

  return (
    <Card
      title={tit}
      icon="fa-solid fa-calendar-day"
      right={`${feitas} de ${sessoes.length} chamadas`}
    >
      {sessoes.map((s) => (
        <SessaoRow key={s.aula_id_ancora} sessao={s} onAbrir={onAbrir} onGravar={onGravar} />
      ))}
    </Card>
  )
}
