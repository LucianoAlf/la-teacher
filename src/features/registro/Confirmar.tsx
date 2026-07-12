import { useCallback, useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { Badge, Button, EmptyState, FabioMark, Fatia, ScreenHeader, Skeleton, Toast, useToast } from '../../components/ui'
import {
  atualizarFatia,
  confirmarRegistro,
  ErroEscolhaModo,
  registroCompleto,
  type AulaContexto,
  type ConfirmacaoResultado,
  type ModoRegistro,
  type PendenciaConfirmacao,
  type RegistroJaFeito,
  type RegistroRow,
} from '../../lib/api'
import { cx } from '../../lib/cx'
import { formatDiaCurto, formatHoraBRT } from '../../lib/date'
import { AppFrame } from '../../pages/app/AppFrame'
import { CampoEditavel } from './CampoEditavel'
import { presencaDaFatia, textoFatia, textoTronco } from './texto'

// Campos extras do tronco (narrativa do professor) — mostrados só quando têm
// conteúdo, pra não poluir. Nenhum campo preenchido fica escondido.
const EXTRAS_TRONCO: Array<{ chave: string; label: string; icon: string; cutucada: string }> = [
  { chave: 'materiais', label: 'Materiais', icon: 'fa-solid fa-guitar', cutucada: 'Materiais usados na aula? (opcional)' },
  { chave: 'repertorio', label: 'Repertório', icon: 'fa-solid fa-list-ol', cutucada: 'Repertório trabalhado? (opcional)' },
  { chave: 'marco_ref', label: 'Marco de referência', icon: 'fa-solid fa-flag', cutucada: 'Algum marco de referência? (opcional)' },
]

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
  // Prontuário: esta aula já tem relatório? (o banco recusa 'novo' sobre texto existente)
  const [jaReg, setJaReg] = useState<{ ja: boolean; itens: RegistroJaFeito[] }>({ ja: false, itens: [] })
  const [escolhendoModo, setEscolhendoModo] = useState(false)

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
        setJaReg({ ja: res.aula_ja_registrada === true, itens: res.ja_registrados ?? [] })
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

  async function confirmar(modo: ModoRegistro) {
    if (!tronco) return
    setEscolhendoModo(false)
    setFase('confirmando')
    setPendencias([])
    try {
      // garante que TODA fatia presente vai gravar comum + individual
      // (regenera e persiste os textos finais antes da RPC de confirmação)
      await atualizarFatia(tronco.id, textoTronco(aula, tronco.campos), null)
      for (const f of fatias.filter((f) => presencaDaFatia(f) === 'presente')) {
        await atualizarFatia(f.id, textoFatia(aula, tronco.campos, f.campos), null)
      }
      const res = await confirmarRegistro(tronco.id, modo)
      if (res.pendencias.length > 0) {
        setPendencias(res.pendencias)
        setFase('ok')
        show('Algumas fatias precisam de atenção 👇')
        return
      }
      if (res.gravadas === 0) {
        // sucesso falso: registro sem conteúdo gravável (ex.: turma sem fatias)
        setFase('ok')
        show('Nada foi gravado — este registro não tem conteúdo por aluno. Fala com a coordenação ou regrave.')
        return
      }
      setSucesso(res)
      setFase('sucesso')
    } catch (e) {
      setFase('ok')
      // Defesa em profundidade: se o banco RECUSOU 'novo' sobre texto existente
      // (registro_ja_existe_escolha_modo), abre a escolha em vez de falhar seco —
      // nada é perdido, o professor decide substituir ou complementar.
      if (e instanceof ErroEscolhaModo) {
        setJaReg((r) => ({ ...r, ja: true }))
        setEscolhendoModo(true)
        show('Esta aula já tem relatório — escolha substituir ou complementar 👇')
        return
      }
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
  const temFatias = fatias.length > 0
  const sub = [aula?.curso, aula?.turma, aula?.data_aula && formatDiaCurto(aula.data_aula), aula?.hora && formatHoraBRT(aula.hora), `Molde ${tronco.molde}`]
    .filter(Boolean)
    .join(' · ')

  return (
    <AppFrame>
      <ScreenHeader title="Confere aí 👇" subtitle={sub} onBack={() => navigate('/app')} />

      <div className="flex-1 overflow-y-auto pb-36">
        {/* selo do Fábio */}
        <div className="mx-4 mb-3 flex items-center gap-2 rounded-md border border-[color:var(--brand-border)] bg-brand-soft px-3 py-2 text-[12px] font-semibold text-brand-text">
          <FabioMark className="h-[17px] w-[17px] flex-none" knockout="var(--brand-soft)" />
          Fábio organizou seu áudio — confira e confirme. Eu nunca invento: campo vazio é convite ✋
        </div>

        {/* prontuário: esta aula já tem relatório → confirmar exige escolher */}
        {jaReg.ja && (
          <div className="mx-4 mb-3 rounded-md border border-border-subtle bg-warning-soft px-3 py-[10px] text-[12.5px] leading-relaxed text-warning-text">
            <b className="mb-1 flex items-center gap-1.5">
              <i className="fa-solid fa-clipboard-check" aria-hidden="true" /> Esta aula já tem relatório
            </b>
            <span>
              Ao confirmar, você escolhe <b>substituir</b> (apaga o anterior) ou <b>complementar</b> (anexa ao que já
              existe). Nada é apagado sem você mandar. ✋
            </span>
          </div>
        )}

        {/* pendências da tentativa de confirmação */}
        {pendencias.length > 0 && (
          <div className="mx-4 mb-3 rounded-md border border-border-subtle bg-danger-soft px-3 py-[10px] text-[12.5px]">
            <b className="mb-1 block font-bold text-danger-text">
              <i className="fa-solid fa-triangle-exclamation" aria-hidden="true" /> Não gravei ainda — falta resolver:
            </b>
            <ul className="list-inside list-disc text-text-secondary">
              {pendencias.map((p) => {
                const nome = (fatias.find((f) => f.id === p.fatia_id)?.aluno_nome as string | null) ?? 'Aluno'
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
            label="Observações"
            icon="fa-solid fa-comment-dots"
            value={(tronco.campos.obs_gerais as string | null) ?? null}
            cutucada="Alguma observação geral da aula? (ex.: o que fazer na próxima) (opcional)"
            onSave={(v) => void salvarCampoTronco('obs_gerais', v)}
          />
          {EXTRAS_TRONCO.filter((e) => (tronco.campos[e.chave] as string | null)?.trim()).map((e) => (
            <CampoEditavel
              key={e.chave}
              label={e.label}
              icon={e.icon}
              value={(tronco.campos[e.chave] as string | null) ?? null}
              cutucada={e.cutucada}
              onSave={(v) => void salvarCampoTronco(e.chave, v)}
            />
          ))}
          <CampoEditavel
            label="Dever de casa"
            icon="fa-solid fa-house"
            value={(tronco.campos.dever_casa as string | null) ?? null}
            cutucada="Quer mandar um dever de casa? (opcional)"
            dever
            onSave={(v) => void salvarCampoTronco('dever_casa', v)}
          />
          {/* eixos NÃO é exibido: é classificação de sistema (fica em campos.eixos,
              gravado no backend, nunca renderizado pro professor — decisão do Alf). */}
        </div>

        {/* FATIAS — um card por aluno (só quando há) */}
        {temFatias && (
          <div className="mx-4 mb-2 flex items-center gap-2 text-[12.5px] font-bold uppercase tracking-[.5px] text-text-secondary">
            <i className="fa-solid fa-user-group text-brand-text" aria-hidden="true" />
            Fatias por aluno · {fatias.length}
          </div>
        )}
        <div className="mx-4 space-y-[9px]">
          {fatias.map((f) => {
            // Nome completo no header (controle de qualidade do fatiamento — o
            // professor precisa ver de quem é a fatia); primeiro nome + foto nas
            // cutucadas e no avatar. Tudo vem da RPC por fatia (não de campos).
            const nomeCompleto = (f.aluno_nome as string | null) ?? 'Aluno'
            const primeiro = (f.aluno_primeiro_nome as string | null) ?? nomeCompleto
            const foto = (f.aluno_foto_url as string | null) ?? null
            const ausente = presencaDaFatia(f) === 'ausente'
            return (
              <div key={f.id} className={cx(ausente && 'opacity-60')}>
                <Fatia nome={nomeCompleto} fotoUrl={foto} presenca={ausente ? 'faltou' : 'presente'} defaultOpen={!ausente}>
                  {ausente ? (
                    <p className="px-[14px] py-[11px] text-sm text-text-secondary">
                      Ausente — nada será gravado pra {primeiro}. Nada foi inventado. ✋
                    </p>
                  ) : (
                    <>
                      <CampoEditavel
                        label="Progresso"
                        icon="fa-solid fa-arrow-trend-up"
                        value={(f.campos.progresso as string | null) ?? null}
                        cutucada={`Não ouvi o progresso de ${primeiro} no áudio — toque pra completar (eu nunca invento ✋)`}
                        onSave={(v) => void salvarCampoFatia(f.id, 'progresso', v)}
                      />
                      <CampoEditavel
                        label="Próximo passo"
                        icon="fa-solid fa-route"
                        value={(f.campos.proximo_passo as string | null) ?? null}
                        cutucada={`Quer adicionar um próximo passo pra ${primeiro}? (opcional)`}
                        onSave={(v) => void salvarCampoFatia(f.id, 'proximo_passo', v)}
                      />
                      <CampoEditavel
                        label="Observação"
                        icon="fa-solid fa-eye"
                        value={(f.campos.observacao as string | null) ?? null}
                        cutucada={`Alguma observação sobre ${primeiro}? (opcional)`}
                        onSave={(v) => void salvarCampoFatia(f.id, 'observacao', v)}
                      />
                    </>
                  )}
                </Fatia>
              </div>
            )
          })}
        </div>

        {!temFatias && (
          <div className="mx-4 rounded-md border border-border-subtle bg-bg-inset px-3 py-[10px] text-[12.5px] leading-relaxed text-text-secondary">
            <i className="fa-solid fa-circle-info text-brand-text" aria-hidden="true" /> Esta aula não tem observações
            por aluno separadas — o texto abaixo é o que será gravado. (Se era pra ter aluno individual, fala com a
            coordenação.)
          </div>
        )}

        {/* PREVIEW — o texto final que será gravado */}
        <div className="mx-4 mt-3">
          <button
            type="button"
            className="flex w-full items-center gap-2 rounded-md border border-dashed border-[color:var(--brand-border)] bg-transparent px-3 py-2 text-[12.5px] font-bold text-brand-text"
            onClick={() => setVerTextoFinal((v) => !v)}
          >
            <i className={cx('fa-solid fa-chevron-down transition-transform', verTextoFinal && 'rotate-180')} aria-hidden="true" />
            {verTextoFinal
              ? 'Esconder texto final'
              : temFatias
                ? 'Ver o texto final que será gravado (por aluno)'
                : 'Ver o texto final que será gravado'}
          </button>
          {verTextoFinal && (
            <div className="mt-2 space-y-2">
              {temFatias ? (
                presentes.map((f) => (
                  <div key={f.id} className="rounded-md border border-border-subtle bg-bg-inset px-3 py-[10px]">
                    <div className="mb-1 text-[11px] font-bold uppercase tracking-[.5px] text-text-secondary">
                      aula do(a) {(f.aluno_nome as string | null) ?? 'aluno'}
                    </div>
                    <pre className="whitespace-pre-wrap font-mono text-[11.5px] leading-relaxed text-text-primary">
                      {textoFatia(aula, tronco.campos, f.campos)}
                    </pre>
                  </div>
                ))
              ) : (
                <div className="rounded-md border border-border-subtle bg-bg-inset px-3 py-[10px]">
                  <pre className="whitespace-pre-wrap font-mono text-[11.5px] leading-relaxed text-text-primary">
                    {textoTronco(aula, tronco.campos)}
                  </pre>
                </div>
              )}
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
        <Button
          className="flex-1"
          disabled={fase === 'confirmando'}
          onClick={() => (jaReg.ja ? setEscolhendoModo(true) : void confirmar('novo'))}
        >
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

      {escolhendoModo && (
        <div
          className="absolute inset-0 z-50 flex items-end"
          role="dialog"
          aria-modal="true"
          aria-label="Substituir ou complementar o relatório"
        >
          <button className="absolute inset-0 bg-black/50" aria-label="Fechar" onClick={() => setEscolhendoModo(false)} />
          <div className="relative w-full rounded-t-2xl border-t border-border-subtle bg-bg-surface p-5 pb-[calc(20px+env(safe-area-inset-bottom))]">
            <b className="block text-[15px]">Esta aula já tem relatório</b>
            <p className="mt-1 text-[12.5px] leading-relaxed text-text-secondary">
              O que fazer com o que já está gravado
              {jaReg.itens.length > 0
                ? ` (${jaReg.itens.map((i) => (i.aluno_nome ?? '').split(' ')[0]).filter(Boolean).join(', ')})`
                : ''}
              ? Nada acontece até você escolher.
            </p>
            <div className="mt-4 flex flex-col gap-2">
              <Button block onClick={() => void confirmar('complementar')}>
                <i className="fa-solid fa-plus" aria-hidden="true" /> Complementar — anexa ao anterior
              </Button>
              <Button block variant="ghost" onClick={() => void confirmar('substituir')}>
                <i className="fa-solid fa-arrows-rotate" aria-hidden="true" /> Substituir — apaga e regrava
              </Button>
              <Button block variant="ghost" onClick={() => setEscolhendoModo(false)}>
                Cancelar
              </Button>
            </div>
          </div>
        </div>
      )}

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
