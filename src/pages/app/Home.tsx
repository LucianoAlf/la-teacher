import { useEffect, useState } from 'react'
import {
  Button,
  Card,
  EmptyState,
  Fab,
  FabioCard,
  Skeleton,
  TabBar,
  Toast,
  useToast,
} from '../../components/ui'
import { useAuth } from '../../lib/auth'
import { useTheme } from '../../lib/theme'
import { formatDiaCurto, hojeBRT, isHoje } from '../../lib/date'
import { contarRegistradas } from '../../features/agenda/aula'
import { AgendaAulaRow } from '../../features/agenda/AgendaAulaRow'
import { DateNav } from '../../features/agenda/DateNav'
import { useAgenda } from '../../features/agenda/useAgenda'
import { buscarPendencias, type Pendencias } from '../../features/agenda/pendencias'
import { AppFrame } from './AppFrame'

const TABS = [
  { id: 'inicio', label: 'Início', icon: 'fa-solid fa-house' },
  { id: 'alunos', label: 'Alunos', icon: 'fa-solid fa-user-group' },
  { id: 'agenda', label: 'Agenda', icon: 'fa-solid fa-calendar' },
  { id: 'fabio', label: 'Fábio', icon: 'fa-solid fa-robot' },
]

const TOAST_S3 = 'Registro por voz chega no Sprint 3 🎙️'

function primeiroNome(email?: string, nome?: string): string {
  if (nome) return nome.split(' ')[0]
  if (!email) return 'professor'
  const local = email.split('@')[0].split(/[._-]/)[0]
  return local.charAt(0).toUpperCase() + local.slice(1)
}

/** /app — Home do professor (tela 1 do protótipo) com dados vivos do LA Report. */
export default function HomePage() {
  const { session, signOut } = useAuth()
  const { toggle } = useTheme()
  const { message, visible, show } = useToast()
  const [tab, setTab] = useState('inicio')
  const [data, setData] = useState<string>(hojeBRT())

  const { estado, recarregar } = useAgenda(data)
  const nome = primeiroNome(
    session?.user.email,
    (session?.user.user_metadata?.name as string | undefined) ?? undefined,
  )

  return (
    <AppFrame>
      {/* 1 · Header: saudação + tema */}
      <header className="flex items-center gap-3 px-4 pb-1 pt-[14px]">
        <div className="flex h-10 w-10 flex-none items-center justify-center rounded-full bg-[var(--avatar-grad)] text-[15px] font-extrabold text-[color:var(--avatar-fg)]">
          {nome.charAt(0).toUpperCase()}
        </div>
        <div className="min-w-0">
          <b className="block text-xl font-extrabold tracking-[-.3px]">E aí, {nome}! 👋</b>
          <span className="block truncate text-[12.5px] text-text-secondary">{session?.user.email}</span>
        </div>
        <button
          type="button"
          aria-label="Alternar tema"
          className="ml-auto flex h-[38px] w-[38px] flex-none items-center justify-center rounded-full border border-border-subtle bg-bg-surface text-text-secondary"
          onClick={toggle}
        >
          <i className="fa-solid fa-circle-half-stroke" aria-hidden="true" />
        </button>
      </header>

      <div className="flex-1 overflow-y-auto px-4 pb-32 pt-2">
        {/* 2 · Briefing do Fábio (estático nesta fase) */}
        <div className="mb-3">
          <FabioCard tag="em breve">
            <p>Seu copiloto chega no próximo sprint 🎙️</p>
            <p className="text-text-secondary">
              Aqui vão entrar o briefing pré-aula e os toques sobre cada aluno — direto da cabeça do Fábio.
            </p>
          </FabioCard>
        </div>

        {/* Seletor de dia */}
        <div className="mb-2 overflow-hidden rounded-lg border border-border-subtle bg-bg-surface">
          <DateNav value={data} onChange={setData} />
        </div>

        {/* 3 · Aulas do dia */}
        <div className="mb-3">
          <CardAulasDoDia data={data} estado={estado} onRetry={recarregar} onToastS3={() => show(TOAST_S3)} />
        </div>

        {/* 4 · Pendências */}
        <PendenciasCard onToastS3={() => show(TOAST_S3)} />

        <div className="mt-3">
          <Button block variant="ghost" onClick={signOut}>
            <i className="fa-solid fa-arrow-right-from-bracket" aria-hidden="true" /> Sair
          </Button>
        </div>
      </div>

      <TabBar
        items={TABS}
        activeId={tab}
        onSelect={(id) => {
          setTab(id)
          if (id === 'agenda') show('Agenda entra no P4 📅')
          if (id === 'alunos') show('Alunos entra no P4 👥')
          if (id === 'fabio') show('Chat com o Fábio chega no Sprint 4 🤖')
        }}
      />
      <Fab onClick={() => show(TOAST_S3)} />
      <Toast message={message} visible={visible} />
    </AppFrame>
  )
}

// ---------------------------------------------------------------------------

function CardAulasDoDia({
  data,
  estado,
  onRetry,
  onToastS3,
}: {
  data: string
  estado: ReturnType<typeof useAgenda>['estado']
  onRetry: () => void
  onToastS3: () => void
}) {
  const titulo = isHoje(data) ? 'Hoje' : formatDiaCurto(data)

  if (estado.fase === 'carregando') {
    return (
      <Card title={titulo} icon="fa-solid fa-calendar-day">
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
      <Card title={titulo} icon="fa-solid fa-calendar-day">
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
    // O guard já trata isso; fallback defensivo pra nunca renderizar vazio.
    return (
      <Card title={titulo} icon="fa-solid fa-calendar-day">
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
      <Card title={titulo} icon="fa-solid fa-calendar-day">
        <EmptyState
          icon="fa-solid fa-music"
          title="Nenhuma aula neste dia 🎵"
          description={
            isHoje(data)
              ? 'Dia livre por aqui. Use as setas acima pra ver outro dia da sua agenda.'
              : 'Sem aulas nesta data. Navegue pelos dias com as setas acima.'
          }
        />
      </Card>
    )
  }

  return (
    <Card
      title={titulo}
      icon="fa-solid fa-calendar-day"
      right={`${registradas} de ${total} registradas`}
    >
      {aulas.map((a) => (
        <AgendaAulaRow key={a.aula_local_id} aula={a} onRegistrar={onToastS3} />
      ))}
    </Card>
  )
}

function PendenciasCard({ onToastS3 }: { onToastS3: () => void }) {
  const [estado, setEstado] = useState<'carregando' | 'ok' | 'erro'>('carregando')
  const [pend, setPend] = useState<Pendencias | null>(null)

  useEffect(() => {
    let vivo = true
    setEstado('carregando')
    buscarPendencias()
      .then((p) => {
        if (!vivo) return
        setPend(p)
        setEstado('ok')
      })
      .catch(() => vivo && setEstado('erro'))
    return () => {
      vivo = false
    }
  }, [])

  if (estado === 'carregando') {
    return (
      <Card title="Pendências" icon="fa-solid fa-bell">
        <div className="space-y-2 py-1">
          <Skeleton className="h-[14px] w-2/3" />
          <Skeleton className="h-3 w-1/2" />
        </div>
      </Card>
    )
  }

  if (estado === 'erro' || !pend) {
    return (
      <Card title="Pendências" icon="fa-solid fa-bell">
        <EmptyState
          icon="fa-solid fa-mug-hot"
          title="Tudo em dia! 🎉"
          description="Nenhuma aula sem registro por aqui. Quando terminar uma aula, ela aparece pra você registrar."
        />
      </Card>
    )
  }

  return (
    <Card title="Pendências" icon="fa-solid fa-bell" right={formatDiaCurto(pend.data)}>
      {pend.aulas.map((a) => (
        <AgendaAulaRow key={a.aula_local_id} aula={a} onRegistrar={onToastS3} />
      ))}
      <p className="mt-[9px] flex items-start gap-2 text-[12.5px] leading-relaxed text-text-secondary">
        <i className="fa-solid fa-robot mt-[3px] text-brand-text" aria-hidden="true" />
        <span>Me manda um áudio de 30s dessas aulas que eu monto o registro pra você 😉</span>
      </p>
    </Card>
  )
}
