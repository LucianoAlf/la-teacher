import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Card, EmptyState, FabioCard, Skeleton, Toast, useToast } from '../../components/ui'
import { useAuth } from '../../lib/auth'
import { useTheme } from '../../lib/theme'
import { formatDiaCurto, hojeBRT } from '../../lib/date'
import type { AgendaAula } from '../../lib/api'
import { AgendaAulaRow } from '../../features/agenda/AgendaAulaRow'
import { CardAulasDoDia } from '../../features/agenda/CardAulasDoDia'
import { DateNav } from '../../features/agenda/DateNav'
import { useAgenda } from '../../features/agenda/useAgenda'
import { buscarPendencias, type Pendencias } from '../../features/agenda/pendencias'
import { useFilaOfflineCount } from '../../features/registro/filaOffline'
import { AppFrame } from './AppFrame'
import { AppNav } from './AppNav'

function primeiroNome(email?: string, nome?: string): string {
  if (nome) return nome.split(' ')[0]
  if (!email) return 'professor'
  const local = email.split('@')[0].split(/[._-]/)[0]
  return local.charAt(0).toUpperCase() + local.slice(1)
}

/** /app — Home do professor (tela 1 do protótipo) com dados vivos do LA Report. */
export default function HomePage() {
  const { session } = useAuth()
  const { toggle } = useTheme()
  const { message, visible, show } = useToast()
  const navigate = useNavigate()
  const [data, setData] = useState<string>(hojeBRT())

  const { estado, recarregar } = useAgenda(data)
  const filaOffline = useFilaOfflineCount()
  const abrirGravacao = (aula: AgendaAula) =>
    navigate(`/app/gravar/${aula.aula_local_id}`, { state: { aula } })
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
        {/* Áudios aguardando conexão (fila offline) */}
        {filaOffline > 0 && (
          <div className="mb-3 flex items-center gap-2 rounded-md border border-border-subtle bg-warning-soft px-3 py-[10px] text-[12.5px] font-semibold text-warning-text">
            <i className="fa-solid fa-cloud-arrow-up" aria-hidden="true" />
            {filaOffline === 1 ? '1 áudio na fila' : `${filaOffline} áudios na fila`} — envio automático
            quando a conexão voltar
          </div>
        )}

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
          <CardAulasDoDia data={data} estado={estado} onRetry={recarregar} onGravar={abrirGravacao} />
        </div>

        {/* 4 · Pendências */}
        <PendenciasCard onGravar={abrirGravacao} />
      </div>

      <AppNav onFabio={() => show('Chat com o Fábio chega no Sprint 4 🤖')} />
      <Toast message={message} visible={visible} />
    </AppFrame>
  )
}

// ---------------------------------------------------------------------------

function PendenciasCard({ onGravar }: { onGravar: (aula: AgendaAula) => void }) {
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
        <AgendaAulaRow key={a.aula_local_id} aula={a} onGravar={onGravar} />
      ))}
      <p className="mt-[9px] flex items-start gap-2 text-[12.5px] leading-relaxed text-text-secondary">
        <i className="fa-solid fa-robot mt-[3px] text-brand-text" aria-hidden="true" />
        <span>Me manda um áudio de 30s dessas aulas que eu monto o registro pra você 😉</span>
      </p>
    </Card>
  )
}
