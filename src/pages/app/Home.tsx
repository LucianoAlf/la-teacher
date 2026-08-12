import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Button, Card, EmptyState, FabioMark, Skeleton, Toast, useToast } from '../../components/ui'
import { AppHeader } from './AppHeader'
import { useAuth } from '../../lib/auth'
import { formatDiaCurto, hojeBRT } from '../../lib/date'
import { devolutivasPendentes, meuPonto, registrosPendentes, type PontoDia, type RegistroRow, type SessaoAula } from '../../lib/api'
import { fmtMinutos } from './Ponto'
import { SessaoRow } from '../../features/agenda/SessaoRow'
import { CardSessoesDoDia } from '../../features/agenda/CardSessoesDoDia'
import { DateNav } from '../../features/agenda/DateNav'
import { useSessoes } from '../../features/agenda/useSessoes'
import { buscarPendencias, buscarPendentesHoje, type Pendencias } from '../../features/agenda/pendencias'
import { horaSessao, JANELA_POS_AULA_DIAS, tituloSessao } from '../../features/agenda/sessao'
import { descreverFalhaFila } from '../../features/registro/camposCanonicos'
import { itemPodeSerReenviado, type ItemFilaLocal, useFilaOffline } from '../../features/registro/filaOffline'
import { descartarItemFila, tentarNovamenteItemFila } from '../../features/registro/uploadAudio'
import { destinoAceiteFila, rotuloPendencia } from '../../features/registro/fluxoFila'
import { CardFeedbackHome } from '../../features/feedback'
import { AppFrame } from './AppFrame'
import { AppNav } from './AppNav'

/** /app — Home do professor (tela 1 do protótipo) com dados vivos do LA Report. */
export default function HomePage() {
  const { message, visible, show } = useToast()
  const { session } = useAuth()
  const navigate = useNavigate()
  const [data, setData] = useState<string>(hojeBRT())

  const { estado, recarregar } = useSessoes(data)
  const { itens: filaOffline } = useFilaOffline(session?.user.id)
  const [itemFilaEmAcao, setItemFilaEmAcao] = useState<string | null>(null)
  const abrirChamada = (sessao: SessaoAula) =>
    navigate(`/app/chamada/${sessao.aula_id_ancora}`, { state: { sessao } })
  const gravarAula = (sessao: SessaoAula) =>
    navigate(`/app/gravar/${sessao.aula_id_ancora}`, { state: { sessao } })

  const tentarFila = async (item: ItemFilaLocal) => {
    setItemFilaEmAcao(item.id)
    try {
      const resultado = await tentarNovamenteItemFila(item.id, session?.user.id)
      if (resultado.ok) {
        const destino = destinoAceiteFila(resultado.resultado)
        if (destino?.tela === 'confirmar') navigate(`/app/confirmar/${destino.registroId}`)
        else if (destino?.tela === 'processando') navigate(`/app/processando/${destino.audioId}`, { state: { aulaLabel: item.aulaLabel } })
        else show('O sistema aceitou o áudio, mas não informou onde acompanhá-lo.')
        return
      }
      show(`Ainda não enviei: ${resultado.mensagem}`)
    } catch {
      show('Não consegui acessar a fila local agora')
    } finally {
      setItemFilaEmAcao(null)
    }
  }

  const descartarFila = async (item: ItemFilaLocal) => {
    setItemFilaEmAcao(item.id)
    try {
      const descartado = await descartarItemFila(item.id, session?.user.id)
      if (!descartado.ok) {
        show(descartado.mensagem)
        return
      }
      show('Áudio descartado só deste aparelho')
    } catch {
      show('Não consegui descartar o áudio local agora')
    } finally {
      setItemFilaEmAcao(null)
    }
  }

  return (
    <AppFrame>
      {/* 1 · Header da família LA (avatar Fábio · saudação · tema · perfil) */}
      <AppHeader />

      <div className="flex-1 overflow-y-auto px-4 pb-[calc(96px_+_env(safe-area-inset-bottom))] pt-2">
        {/* Feedback do mês — só sobe na última semana, some sozinho quando fecha 100% */}
        <CardFeedbackHome />

        {/* Chamada de hoje ainda não enviada — não deixa passar despercebido */}
        <AlertaChamadaHoje onAbrir={abrirChamada} />

        {/* Áudios aguardando conexão (fila offline) */}
        {filaOffline.length > 0 && (
          <FilaAudios
            itens={filaOffline}
            itemEmAcao={itemFilaEmAcao}
            onTentar={(item) => void tentarFila(item)}
            onDescartar={(item) => void descartarFila(item)}
          />
        )}

        {/* Registros do Fábio esperando confirmação */}
        <AguardandoConfirmacao onAbrir={(id) => navigate(`/app/confirmar/${id}`)} />

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

        {/* Devolutivas que o Fábio escreveu e esperam o professor */}
        <DevolutivasCard onAbrir={() => navigate('/app/devolutivas')} />

        {/* 4 · Chamadas pendentes de ontem */}
        <PendenciasCard onAbrir={abrirChamada} onGravar={gravarAula} />

        {/* 5 · Minha semana (isca: o que já foi dado hoje) */}
        <PontoHojeCard onAbrir={() => navigate('/app/ponto')} />
      </div>

      <AppNav onMais={() => show('Mais ferramentas chegam em breve 🧰')} />
      <Toast message={message} visible={visible} />
    </AppFrame>
  )
}

// ---------------------------------------------------------------------------

function FilaAudios({
  itens,
  itemEmAcao,
  onTentar,
  onDescartar,
}: {
  itens: ItemFilaLocal[]
  itemEmAcao: string | null
  onTentar: (item: ItemFilaLocal) => void
  onDescartar: (item: ItemFilaLocal) => void
}) {
  return (
    <div className="mb-3 overflow-hidden rounded-md border border-border-subtle bg-warning-soft text-warning-text">
      <div className="flex items-center gap-2 px-3 py-[10px] text-[12.5px] font-semibold">
        <i className="fa-solid fa-cloud-arrow-up" aria-hidden="true" />
        {itens.length === 1 ? '1 áudio preservado neste aparelho' : `${itens.length} áudios preservados neste aparelho`}
      </div>
      <div className="border-t border-border-subtle bg-bg-surface">
        {itens.map((item) => {
          const emAcao = itemEmAcao === item.id
          const podeReenviar = itemPodeSerReenviado(item)
          return (
            <div key={item.id} className="border-b border-border-subtle px-3 py-[10px] last:border-b-0">
              <b className="block truncate text-[12.5px] text-text-primary">{item.aulaLabel}</b>
              <p className="mt-1 text-[11.5px] leading-relaxed text-text-secondary">
                {descreverFalhaFila(item)}
                {!podeReenviar
                  ? ` · o lançamento foi recusado${item.codigoFalhaTerminal ? ` (${item.codigoFalhaTerminal})` : ''}; o áudio está preservado para descarte consciente`
                  : item.retryAutomatico
                  ? ' · nova tentativa automática habilitada'
                  : ' · preciso da sua decisão; não vou tentar sozinho'}
              </p>
              <div className="mt-2 flex gap-2">
                {podeReenviar && (
                  <Button size="sm" disabled={emAcao} onClick={() => onTentar(item)}>
                    <i className="fa-solid fa-rotate-right" aria-hidden="true" /> {emAcao ? 'Tentando…' : 'Tentar agora'}
                  </Button>
                )}
                <Button size="sm" variant="ghost" disabled={emAcao} onClick={() => onDescartar(item)}>
                  Descartar
                </Button>
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}

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
          <FabioMark className="h-[18px] w-[18px] flex-none" />
          <span className="min-w-0 flex-1 truncate text-sm font-semibold text-text-primary">
            {rotuloPendencia(r.campos)}
          </span>
          <span className="text-xs text-text-secondary">conferir</span>
          <i className="fa-solid fa-chevron-right text-[11px] text-text-muted" aria-hidden="true" />
        </button>
      ))}
    </div>
  )
}

/**
 * Atalho pra "Minha semana": mostra hoje (o que já foi dado) como isca, mas o
 * título casa com o destino — evita abrir "Meu dia" e cair numa tela de semana.
 */
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
        <b className="block text-sm">Minha semana</b>
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

/** Alerta de topo: chamada(s) de HOJE já na janela e ainda sem envio. */
function AlertaChamadaHoje({ onAbrir }: { onAbrir: (sessao: SessaoAula) => void }) {
  const [pendentes, setPendentes] = useState<SessaoAula[]>([])

  useEffect(() => {
    let vivo = true
    buscarPendentesHoje()
      .then((s) => vivo && setPendentes(s))
      .catch(() => {}) // atalho é bônus — nunca quebra a Home
    return () => {
      vivo = false
    }
  }, [])

  if (pendentes.length === 0) return null
  const primeira = pendentes[0]

  return (
    <button
      type="button"
      onClick={() => onAbrir(primeira)}
      className="mb-3 flex w-full items-center gap-2 rounded-md border border-border-subtle bg-warning-soft px-3 py-[10px] text-left text-[12.5px] font-semibold text-warning-text"
    >
      <i className="fa-solid fa-bell" aria-hidden="true" />
      <span className="min-w-0 flex-1">
        {pendentes.length === 1
          ? `1 chamada de hoje ainda não enviada — ${horaSessao(primeira)} ${tituloSessao(primeira)}`
          : `${pendentes.length} chamadas de hoje ainda não enviadas`}
      </span>
      <i className="fa-solid fa-chevron-right text-[11px]" aria-hidden="true" />
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
        <span>
          A chamada fecha {JANELA_POS_AULA_DIAS} dias depois da aula — passado o prazo, só a coordenação
          libera. ⏳
        </span>
      </p>
    </Card>
  )
}

/**
 * Aviso de devolutivas prontas.
 *
 * A tela /app/devolutivas e o aviso do Fábio no WhatsApp ("abre o app em
 * Devolutivas") não servem de nada se não houver por onde chegar lá. Este
 * card é a porta — e só aparece quando existe algo esperando, pra não virar
 * mais um bloco morto na Home.
 */
function DevolutivasCard({ onAbrir }: { onAbrir: () => void }) {
  const [quantas, setQuantas] = useState<number | null>(null)

  useEffect(() => {
    let vivo = true
    devolutivasPendentes()
      .then((lista) => vivo && setQuantas(lista.length))
      .catch(() => vivo && setQuantas(0))
    return () => {
      vivo = false
    }
  }, [])

  if (!quantas) return null

  return (
    <button type="button" onClick={onAbrir} className="mb-3 w-full text-left">
      <Card title="Devolutivas prontas" icon="fa-solid fa-comment-dots" right={`${quantas}`}>
        <div className="flex items-center justify-between gap-3 px-1 py-2">
          <p className="text-[13px] text-text-secondary">
            {quantas === 1
              ? 'Escrevi 1 devolutiva a partir do seu registro.'
              : `Escrevi ${quantas} devolutivas a partir dos seus registros.`}{' '}
            Confere e manda quando quiser.
          </p>
          <i className="fa-solid fa-chevron-right text-text-muted" aria-hidden="true" />
        </div>
      </Card>
    </button>
  )
}
