import { useCallback, useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { Badge, Button, EmptyState, Fatia, ScreenHeader, Skeleton, Toast, useToast } from '../../components/ui'
import {
  atualizarFatia,
  confirmarRegistro,
  registroCompleto,
  type AulaContexto,
  type ConfirmacaoResultado,
  type PendenciaConfirmacao,
  type RegistroRow,
} from '../../lib/api'
import { cx } from '../../lib/cx'
import { formatDiaCurto, formatHoraBRT } from '../../lib/date'
import { AppFrame } from '../../pages/app/AppFrame'
import { CampoEditavel } from './CampoEditavel'
import { presencaDaFatia, textoFatia, textoTronco } from './texto'

type Fase = 'carregando' | 'erro' | 'nao_encontrado' | 'ok' | 'confirmando' | 'sucesso'

/**
 * /app/confirmar/:registroId — a tela mais importante do app: o professor vê
 * o que o Fábio entendeu (tronco comum + fatia de cada aluno), ajusta inline,
 * e confirma → app_confirmar_registro grava POR ALUNO via registrar_aula_fabio.
 */
export default function ConfirmarPage() {
  const { registroId } = useParams()
  const navigate = useNavigate()
  const { message, visible, show } = useToast()

  const [fase, setFase] = useState<Fase>('carregando')
  const [tronco, setTronco] = useState<RegistroRow | null>(null)
  const [fatias, setFatias] = useState<RegistroRow[]>([])
  const [aula, setAula] = useState<AulaContexto | null>(null)
  const [pendencias, setPendencias] = useState<PendenciaConfirmacao[]>([])
  const [sucesso, setSucesso] = useState<ConfirmacaoResultado | null>(null)
  const [verTextoFinal, setVerTextoFinal] = useState(false)

  const carregar = useCallback(() => {
    if (!registroId) return
    setFase('carregando')
    registroCompleto(registroId)
      .then((res) => {
        if ('erro' in res) {
          setFase('nao_encontrado')
          return
        }
        setTronco(res.tronco)
        setFatias(res.fatias)
        setAula(res.aula)
        setFase('ok')
      })
      .catch(() => setFase('erro'))
  }, [registroId])

  useEffect(carregar, [carregar])

  // ---- persistência das edições (regenera o texto no formato da Tese) ----

  async function salvarCampoTronco(chave: string, valor: string | null) {
    if (!tronco) return
    const novosCampos = { ...tronco.campos, [chave]: valor }
    setTronco({ ...tronco, campos: novosCampos })
    try {
      await atualizarFatia(tronco.id, textoTronco(aula, novosCampos), { [chave]: valor })
      // o comum mudou → o texto final de TODAS as fatias presentes muda junto
      for (const f of fatias.filter((f) => presencaDaFatia(f) === 'presente')) {
        await atualizarFatia(f.id, textoFatia(aula, novosCampos, f.campos), null)
      }
      show('Campo atualizado ✓')
    } catch {
      show('Não consegui salvar — recarregando')
      carregar()
    }
  }

  async function salvarCampoFatia(fatiaId: string, chave: string, valor: string | null) {
    if (!tronco) return
    const alvo = fatias.find((f) => f.id === fatiaId)
    if (!alvo) return
    const novosCampos = { ...alvo.campos, [chave]: valor }
    setFatias(fatias.map((f) => (f.id === fatiaId ? { ...f, campos: novosCampos } : f)))
    try {
      await atualizarFatia(fatiaId, textoFatia(aula, tronco.campos, novosCampos), { [chave]: valor })
      show('Campo atualizado ✓')
    } catch {
      show('Não consegui salvar — recarregando')
      carregar()
    }
  }

  // ---- confirmar e gravar (por aluno) ----

  async function confirmar() {
    if (!tronco) return
    setFase('confirmando')
    setPendencias([])
    try {
      // garante que TODA fatia presente vai gravar comum + individual
      // (regenera e persiste os textos finais antes da RPC de confirmação)
      await atualizarFatia(tronco.id, textoTronco(aula, tronco.campos), null)
      for (const f of fatias.filter((f) => presencaDaFatia(f) === 'presente')) {
        await atualizarFatia(f.id, textoFatia(aula, tronco.campos, f.campos), null)
      }
      const res = await confirmarRegistro(tronco.id)
      if (res.pendencias.length > 0) {
        setPendencias(res.pendencias)
        setFase('ok')
        show('Algumas fatias precisam de atenção 👇')
        return
      }
      setSucesso(res)
      setFase('sucesso')
    } catch {
      setFase('ok')
      show('Não consegui confirmar — tenta de novo')
    }
  }

  // ---------------------------------------------------------------------------

  if (fase === 'carregando') {
    return (
      <AppFrame>
        <ScreenHeader title="Confirmação" onBack={() => navigate('/app')} />
        <div className="space-y-3 px-4 pt-2">
          <Skeleton className="h-28 w-full" />
          <Skeleton className="h-20 w-full" />
          <Skeleton className="h-20 w-full" />
        </div>
      </AppFrame>
    )
  }

  if (fase === 'erro' || fase === 'nao_encontrado' || !tronco) {
    return (
      <AppFrame>
        <ScreenHeader title="Confirmação" onBack={() => navigate('/app')} />
        <div className="flex flex-1 flex-col justify-center">
          <EmptyState
            icon={fase === 'erro' ? 'fa-solid fa-triangle-exclamation' : 'fa-solid fa-file-circle-question'}
            title={fase === 'erro' ? 'Não consegui carregar' : 'Registro não encontrado'}
            description={
              fase === 'erro'
                ? 'Verifica a conexão e tenta de novo.'
                : 'Esse registro não existe ou não é seu. Se ele já foi confirmado, a aula aparece como Registrada na Home.'
            }
            action={
              fase === 'erro' ? (
                <Button size="sm" onClick={carregar}>
                  <i className="fa-solid fa-rotate-right" aria-hidden="true" /> Tentar de novo
                </Button>
              ) : (
                <Button size="sm" variant="ghost" onClick={() => navigate('/app')}>
                  Voltar ao início
                </Button>
              )
            }
          />
        </div>
      </AppFrame>
    )
  }

  if (fase === 'sucesso' && sucesso) {
    return <TelaSucesso resultado={sucesso} fatias={fatias} temDever={Boolean(tronco.campos.dever_casa)} />
  }

  const presentes = fatias.filter((f) => presencaDaFatia(f) === 'presente')
  const sub = [aula?.curso, aula?.turma, aula?.data_aula && formatDiaCurto(aula.data_aula), aula?.hora && formatHoraBRT(aula.hora), `Molde ${tronco.molde}`]
    .filter(Boolean)
    .join(' · ')

  return (
    <AppFrame>
      <ScreenHeader title="Confere aí 👇" subtitle={sub} onBack={() => navigate('/app')} />

      <div className="flex-1 overflow-y-auto pb-36">
        {/* selo do Fábio */}
        <div className="mx-4 mb-3 flex items-center gap-2 rounded-md border border-[color:var(--brand-border)] bg-brand-soft px-3 py-2 text-[12px] font-semibold text-brand-text">
          <i className="fa-solid fa-robot" aria-hidden="true" />
          Fábio organizou seu áudio — confira e confirme. Eu nunca invento: campo vazio é convite ✋
        </div>

        {/* pendências da tentativa de confirmação */}
        {pendencias.length > 0 && (
          <div className="mx-4 mb-3 rounded-md border border-border-subtle bg-danger-soft px-3 py-[10px] text-[12.5px]">
            <b className="mb-1 block font-bold text-danger-text">
              <i className="fa-solid fa-triangle-exclamation" aria-hidden="true" /> Não gravei ainda — falta resolver:
            </b>
            <ul className="list-inside list-disc text-text-secondary">
              {pendencias.map((p) => {
                const nome = (fatias.find((f) => f.id === p.fatia_id)?.campos.aluno_nome as string) ?? 'Aluno'
                return (
                  <li key={p.fatia_id}>
                    {nome}: {p.motivo === 'sem texto' ? 'sem conteúdo pra gravar' : p.motivo}
                  </li>
                )
              })}
            </ul>
          </div>
        )}

        {/* TRONCO — bloco comum da turma */}
        <div className="mx-4 mb-3 overflow-hidden rounded-lg border border-[color:var(--brand-border)] bg-bg-surface">
          <div className="flex items-center gap-[9px] border-b border-[color:var(--brand-border)] bg-brand-soft px-[14px] py-3">
            <i className="fa-solid fa-music text-brand-text" aria-hidden="true" />
            <b className="text-[13px] uppercase tracking-[.5px]">O que a turma trabalhou</b>
            <Badge variant="brand" className="ml-auto">
              tronco
            </Badge>
          </div>
          <CampoEditavel
            label="Atividades"
            icon="fa-solid fa-music"
            value={(tronco.campos.atividades as string | null) ?? null}
            cutucada="Quer registrar as atividades da aula? (opcional)"
            onSave={(v) => void salvarCampoTronco('atividades', v)}
          />
          <CampoEditavel
            label="Objetivo trabalhado"
            icon="fa-solid fa-bullseye"
            value={(tronco.campos.objetivo as string | null) ?? null}
            cutucada="Quer registrar o objetivo trabalhado? (opcional)"
            onSave={(v) => void salvarCampoTronco('objetivo', v)}
          />
          <CampoEditavel
            label="Dever de casa"
            icon="fa-solid fa-house"
            value={(tronco.campos.dever_casa as string | null) ?? null}
            cutucada="Quer mandar um dever de casa? (opcional)"
            dever
            onSave={(v) => void salvarCampoTronco('dever_casa', v)}
          />
        </div>

        {/* FATIAS — um card por aluno */}
        <div className="mx-4 mb-2 flex items-center gap-2 text-[12.5px] font-bold uppercase tracking-[.5px] text-text-secondary">
          <i className="fa-solid fa-user-group text-brand-text" aria-hidden="true" />
          Fatias por aluno · {fatias.length}
        </div>
        <div className="mx-4 space-y-[9px]">
          {fatias.map((f) => {
            const nome = (f.campos.aluno_nome as string) ?? 'Aluno'
            const ausente = presencaDaFatia(f) === 'ausente'
            return (
              <div key={f.id} className={cx(ausente && 'opacity-60')}>
                <Fatia nome={nome} presenca={ausente ? 'faltou' : 'presente'} defaultOpen={!ausente}>
                  {ausente ? (
                    <p className="px-[14px] py-[11px] text-sm text-text-secondary">
                      Ausente — nada será gravado pra {nome}. Nada foi inventado. ✋
                    </p>
                  ) : (
                    <>
                      <CampoEditavel
                        label="Progresso"
                        icon="fa-solid fa-arrow-trend-up"
                        value={(f.campos.progresso as string | null) ?? null}
                        cutucada={`Não ouvi o progresso de ${nome} no áudio — toque pra completar (eu nunca invento ✋)`}
                        onSave={(v) => void salvarCampoFatia(f.id, 'progresso', v)}
                      />
                      <CampoEditavel
                        label="Próximo passo"
                        icon="fa-solid fa-route"
                        value={(f.campos.proximo_passo as string | null) ?? null}
                        cutucada={`Quer adicionar um próximo passo pra ${nome}? (opcional)`}
                        onSave={(v) => void salvarCampoFatia(f.id, 'proximo_passo', v)}
                      />
                      <CampoEditavel
                        label="Observação"
                        icon="fa-solid fa-eye"
                        value={(f.campos.observacao as string | null) ?? null}
                        cutucada={`Alguma observação sobre ${nome}? (opcional)`}
                        onSave={(v) => void salvarCampoFatia(f.id, 'observacao', v)}
                      />
                    </>
                  )}
                </Fatia>
              </div>
            )
          })}
        </div>

        {/* PREVIEW — o que será gravado por aluno */}
        <div className="mx-4 mt-3">
          <button
            type="button"
            className="flex w-full items-center gap-2 rounded-md border border-dashed border-[color:var(--brand-border)] bg-transparent px-3 py-2 text-[12.5px] font-bold text-brand-text"
            onClick={() => setVerTextoFinal((v) => !v)}
          >
            <i className={cx('fa-solid fa-chevron-down transition-transform', verTextoFinal && 'rotate-180')} aria-hidden="true" />
            {verTextoFinal ? 'Esconder texto final' : 'Ver o texto final que será gravado (por aluno)'}
          </button>
          {verTextoFinal && (
            <div className="mt-2 space-y-2">
              {presentes.map((f) => (
                <div key={f.id} className="rounded-md border border-border-subtle bg-bg-inset px-3 py-[10px]">
                  <div className="mb-1 text-[11px] font-bold uppercase tracking-[.5px] text-text-secondary">
                    aula do(a) {(f.campos.aluno_nome as string) ?? 'aluno'}
                  </div>
                  <pre className="whitespace-pre-wrap font-mono text-[11.5px] leading-relaxed text-text-primary">
                    {textoFatia(aula, tronco.campos, f.campos)}
                  </pre>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      {/* rodapé fixo */}
      <div className="absolute inset-x-0 bottom-0 z-40 flex gap-[10px] bg-[linear-gradient(transparent,var(--bg-app)_30%)] px-4 pb-[14px] pt-3">
        <Button
          variant="ghost"
          className="flex-1"
          onClick={() => navigate(`/app/gravar/${tronco.aula_id}?registro=${tronco.id}`)}
        >
          <i className="fa-solid fa-microphone" aria-hidden="true" /> Corrigir por voz
        </Button>
        <Button className="flex-1" disabled={fase === 'confirmando'} onClick={() => void confirmar()}>
          {fase === 'confirmando' ? (
            <>
              <i className="fa-solid fa-spinner fa-spin" aria-hidden="true" /> Gravando…
            </>
          ) : (
            <>
              <i className="fa-solid fa-check" aria-hidden="true" /> Confirmar e gravar
            </>
          )}
        </Button>
      </div>

      <Toast message={message} visible={visible} />
    </AppFrame>
  )
}

// ---------------------------------------------------------------------------
// Sucesso (tela 5 do protótipo) — com o retorno REAL da RPC
// ---------------------------------------------------------------------------

function TelaSucesso({
  resultado,
  fatias,
  temDever,
}: {
  resultado: ConfirmacaoResultado
  fatias: RegistroRow[]
  temDever: boolean
}) {
  const navigate = useNavigate()

  return (
    <AppFrame>
      <div className="relative flex flex-1 flex-col items-center justify-center gap-[18px] overflow-hidden px-6 text-center">
        <Confetes />
        <div className="flex h-[92px] w-[92px] animate-pop items-center justify-center rounded-full border-2 border-success bg-success-soft text-4xl text-success-text">
          <i className="fa-solid fa-check" aria-hidden="true" />
        </div>
        <h2 className="text-[22px] font-extrabold tracking-[-.3px]">Registro gravado! 🎉</h2>
        <p className="max-w-[290px] text-sm leading-relaxed text-text-secondary">
          {resultado.gravadas} {resultado.gravadas === 1 ? 'aluno recebeu' : 'alunos receberam'} a aula no
          diário{resultado.ausentes_puladas > 0 ? ` · ${resultado.ausentes_puladas} ausente(s) sem gravação (nada inventado ✋)` : ''}.
          Visível pra coordenação.
        </p>
        <div className="flex flex-wrap justify-center gap-[9px]">
          <Badge variant="brand">1 tronco</Badge>
          <Badge variant="brand">
            {fatias.length} {fatias.length === 1 ? 'fatia' : 'fatias'}
          </Badge>
          {temDever && <Badge variant="warn">1 dever de casa</Badge>}
          {resultado.ausentes_puladas > 0 && <Badge variant="danger">{resultado.ausentes_puladas} ausente</Badge>}
        </div>
        <Button block className="max-w-[290px]" onClick={() => navigate('/app')}>
          Voltar ao início
        </Button>
        <span className="font-mono text-[10.5px] tracking-[.3px] text-text-muted">
          registrar_aula_fabio · {resultado.gravadas} {resultado.gravadas === 1 ? 'aula' : 'aulas'} · origem áudio
        </span>
      </div>
    </AppFrame>
  )
}

const CORES_CONFETE = ['bg-[var(--confete-1)]', 'bg-[var(--confete-2)]', 'bg-[var(--confete-3)]', 'bg-[var(--confete-4)]', 'bg-[var(--confete-5)]']

function Confetes() {
  return (
    <div className="pointer-events-none absolute inset-0 motion-reduce:hidden" aria-hidden="true">
      {Array.from({ length: 16 }, (_, i) => (
        <span
          key={i}
          className={cx('absolute -top-2 h-[14px] w-[9px] animate-fall rounded-[2px] opacity-0', CORES_CONFETE[i % 5])}
          style={{ left: `${6 + Math.random() * 88}%`, animationDelay: `${Math.random() * 0.5}s` }}
        />
      ))}
    </div>
  )
}
