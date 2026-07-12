import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Card, EmptyState, FabioCard, Skeleton, Toast, useToast } from '../../components/ui'
import { AppHeader } from './AppHeader'
import { formatDiaCurto, hojeBRT } from '../../lib/date'
import { meuPonto, registrosPendentes, type PontoDia, type RegistroRow, type SessaoAula } from '../../lib/api'
import { fmtMinutos } from './Ponto'
import { SessaoRow } from '../../features/agenda/SessaoRow'
import { CardSessoesDoDia } from '../../features/agenda/CardSessoesDoDia'
import { DateNav } from '../../features/agenda/DateNav'
import { useSessoes } from '../../features/agenda/useSessoes'
import { buscarPendencias, type Pendencias } from '../../features/agenda/pendencias'
import { useFilaOfflineCount } from '../../features/registro/filaOffline'
import { AppFrame } from './AppFrame'
import { AppNav } from './AppNav'

/** /app — Home do professor (tela 1 do protótipo) com dados vivos do LA Report. */
export default function HomePage() {
  const { message, visible, show } = useToast()
  const navigate = useNavigate()
  const [data, setData] = useState<string>(hojeBRT())

  const { estado, recarregar } = useSessoes(data)
  const filaOffline = useFilaOfflineCount()
  const abrirChamada = (sessao: SessaoAula) =>
    navigate(`/app/chamada/${sessao.aula_id_ancora}`, { state: { sessao } })
  const gravarAula = (sessao: SessaoAula) =>
    navigate(`/app/gravar/${sessao.aula_id_ancora}`, { state: { sessao } })

  return (
    <AppFrame>
      {/* 1 · Header da família LA (avatar Fábio · saudação · tema · perfil) */}
      <AppHeader />

      <div className="flex-1 overflow-y-auto px-4 pb-24 pt-2">
        {/* Áudios aguardando conexão (fila offline) */}
        {filaOffline > 0 && (
          <div className="mb-3 flex items-center gap-2 rounded-md border border-border-subtle bg-warning-soft px-3 py-[10px] text-[12.5px] font-semibold text-warning-text">
            <i className="fa-solid fa-cloud-arrow-up" aria-hidden="true" />
            {filaOffline === 1 ? '1 áudio na fila' : `${filaOffline} áudios na fila`} — envio automático
            quando a conexão voltar
          </div>
        )}

        {/* Registros do Fábio esperando confirmação */}
        <AguardandoConfirmacao onAbrir={(id) => navigate(`/app/confirmar/${id}`)} />

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

        {/* 3 · Aulas do dia (sessões) */}
        <div className="mb-3">
          <CardSessoesDoDia
            data={data}
            estado={estado}
            onRetry={recarregar}
            onAbrir={abrirChamada}
            onGravar={gravarAula}
          />
        </div>

        {/* 4 · Chamadas pendentes de ontem */}
        <PendenciasCard onAbrir={abrirChamada} onGravar={gravarAula} />

        {/* 5 · Meu dia (atalho pra semana) */}
        <PontoHojeCard onAbrir={() => navigate('/app/ponto')} />
      </div>

      <AppNav
        onFabio={() => show('Chat com o Fábio chega no Sprint 4 🤖')}
        onMais={() => show('Mais ferramentas chegam em breve 🧰')}
      />
      <Toast message={message} visible={visible} />
    </AppFrame>
  )
}

// ---------------------------------------------------------------------------

/** Atalho: registros que o Fábio estruturou e esperam o "confere e confirma". */
function AguardandoConfirmacao({ onAbrir }: { onAbrir: (registroId: string) => void }) {
  const [regs, setRegs] = useState<RegistroRow[]>([])

  useEffect(() => {
    let vivo = true
    registrosPendentes()
      .then((r) => vivo && setRegs(r))
      .catch(() => {}) // atalho é bônus — nunca quebra a Home
    return () => {
      vivo = false
    }
  }, [])

  if (regs.length === 0) return null
  return (
    <div className="mb-3 overflow-hidden rounded-lg border border-[color:var(--brand-border)] bg-bg-surface">
      <div className="flex items-center gap-2 bg-brand-soft px-3 py-2 text-[12px] font-bold text-brand-text">
        <i className="fa-solid fa-clipboard-check" aria-hidden="true" />
        {regs.length === 1 ? '1 registro esperando sua confirmação' : `${regs.length} registros esperando sua confirmação`}
      </div>
      {regs.map((r) => (
        <button
          key={r.id}
          type="button"
          className="flex w-full items-center gap-2 border-t border-border-subtle bg-transparent px-3 py-[10px] text-left"
          onClick={() => onAbrir(r.id)}
        >
          <i className="fa-solid fa-robot text-brand-text" aria-hidden="true" />
          <span className="min-w-0 flex-1 truncate text-sm font-semibold text-text-primary">
            {(r.campos.turma as string) ?? 'Registro de aula'}
          </span>
          <span className="text-xs text-text-secondary">conferir</span>
          <i className="fa-solid fa-chevron-right text-[11px] text-text-muted" aria-hidden="true" />
        </button>
      ))}
    </div>
  )
}

/** Hoje até agora: o que o professor já deu — atalho pra semana completa. */
function PontoHojeCard({ onAbrir }: { onAbrir: () => void }) {
  // undefined = ainda carregando; null = carregou e não tem aula hoje.
  const [dia, setDia] = useState<PontoDia | null | undefined>(undefined)

  useEffect(() => {
    let vivo = true
    const hoje = hojeBRT()
    meuPonto(hoje, hoje)
      .then((dias) => vivo && setDia(dias[0] ?? null))
      .catch(() => {}) // atalho é bônus — nunca quebra a Home
    return () => {
      vivo = false
    }
  }, [])

  return (
    <button
      type="button"
      onClick={onAbrir}
      className="mt-3 flex w-full items-center gap-3 rounded-lg border border-border-subtle bg-bg-surface px-[14px] py-[13px] text-left"
    >
      <div className="flex h-[38px] w-[38px] flex-none items-center justify-center rounded-md bg-brand-soft text-base text-brand-text">
        <i className="fa-solid fa-calendar-check" aria-hidden="true" />
      </div>
      <div className="min-w-0 flex-1">
        <b className="block text-sm">Meu dia</b>
        <span className="block truncate text-xs text-text-secondary">
          {dia === undefined
            ? 'suas aulas dadas hoje'
            : dia && dia.aulas_creditadas > 0
              ? `${dia.aulas_creditadas} ${dia.aulas_creditadas === 1 ? 'aula dada' : 'aulas dadas'} hoje · ${fmtMinutos(dia.minutos_creditados)}`
              : 'nenhuma aula registrada hoje ainda'}
        </span>
      </div>
      <i className="fa-solid fa-chevron-right text-[11px] text-text-muted" aria-hidden="true" />
    </button>
  )
}

function PendenciasCard({
  onAbrir,
  onGravar,
}: {
  onAbrir: (sessao: SessaoAula) => void
  onGravar: (sessao: SessaoAula) => void
}) {
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
          description="Nenhuma chamada pendente de ontem. As de hoje aparecem no card acima."
        />
      </Card>
    )
  }

  return (
    <Card title="Chamadas pendentes" icon="fa-solid fa-bell" right={formatDiaCurto(pend.data)}>
      {pend.sessoes.map((s) => (
        <SessaoRow key={s.aula_id_ancora} sessao={s} onAbrir={onAbrir} onGravar={onGravar} />
      ))}
      <p className="mt-[9px] flex items-start gap-2 text-[12.5px] leading-relaxed text-text-secondary">
        <i className="fa-solid fa-clock mt-[3px] text-brand-text" aria-hidden="true" />
        <span>A chamada fecha 24h depois da aula — depois disso, só a coordenação lança. ⏳</span>
      </p>
    </Card>
  )
}
