import { useCallback, useEffect, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { Badge, Button, EmptyState, FabioMark, Fatia, ScreenHeader, Skeleton, Toast, useToast } from '../../components/ui'
import {
  atualizarFatia,
  ErroConflitoRascunho,
  responderPresenca,
  confirmarRegistro,
  ErroEscolhaModo,
  registroCompleto,
  salvarRascunhoManual,
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
import { continuarFila } from './filaSerial'
import { repertorioIndividualVisivel } from './camposCanonicos'
import { presencaDaFatia } from './texto'
import { limparCamposManuais } from '../registroManual/modelo'

// Campos extras do tronco (narrativa do professor) — mostrados só quando têm
// conteúdo, pra não poluir. Nenhum campo preenchido fica escondido.
const EXTRAS_TRONCO: Array<{ chave: string; label: string; icon: string; cutucada: string }> = [
  { chave: 'materiais', label: 'Materiais', icon: 'fa-solid fa-guitar', cutucada: 'Materiais usados na aula? (opcional)' },
  { chave: 'repertorio', label: 'Repertório', icon: 'fa-solid fa-list-ol', cutucada: 'Repertório trabalhado? (opcional)' },
  { chave: 'marco_ref', label: 'Marco de referência', icon: 'fa-solid fa-flag', cutucada: 'Algum marco de referência? (opcional)' },
]

const CAMPOS_TRONCO_MANUAL = ['atividades', 'objetivo', 'obs_gerais', 'repertorio', 'dever_casa'] as const

function limparTroncoManual(campos: Record<string, unknown>): Record<string, string> {
  return CAMPOS_TRONCO_MANUAL.reduce<Record<string, string>>((resultado, chave) => {
    const valor = campos[chave]
    if (typeof valor === 'string') resultado[chave] = valor
    return resultado
  }, {})
}

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
  const [salvandoManual, setSalvandoManual] = useState(false)
  const troncoAtualRef = useRef<RegistroRow | null>(null)
  const fatiasAtuaisRef = useRef<RegistroRow[]>([])
  const geracaoManualRef = useRef(0)
  const filaManualRef = useRef<Promise<boolean>>(Promise.resolve(true))
  const salvamentosManuaisRef = useRef(0)
  const erroManualRef = useRef(false)

  const carregar = useCallback((silencioso = false) => {
    if (!registroId) return
    if (!silencioso) setFase('carregando')
    registroCompleto(registroId)
      .then((res) => {
        if ('erro' in res) {
          setFase('nao_encontrado')
          return
        }
        troncoAtualRef.current = res.tronco
        fatiasAtuaisRef.current = res.fatias
        setTronco(res.tronco)
        setFatias(res.fatias)
        setAula(res.aula)
        setJaReg({ ja: res.aula_ja_registrada === true, itens: res.ja_registrados ?? [] })
        setFase('ok')
      })
      .catch(() => setFase('erro'))
  }, [registroId])

  useEffect(() => {
    void carregar()
  }, [carregar])

  // ---- persistência das edições (regenera o texto no formato da Tese) ----

  function enfileirarSalvamentoManual(): Promise<boolean> {
    salvamentosManuaisRef.current += 1
    setSalvandoManual(true)
    const tarefa = continuarFila(filaManualRef.current, async () => {
      const raiz = troncoAtualRef.current
      if (!raiz) return false
      const geracao = geracaoManualRef.current
      const res = await salvarRascunhoManual(
        raiz.id,
        raiz.versao ?? 1,
        limparTroncoManual(raiz.campos),
        fatiasAtuaisRef.current.map((fatia) => ({
          id: fatia.id,
          campos: limparCamposManuais(fatia.campos) as Record<string, string>,
        })),
      )
      erroManualRef.current = false
      if (geracao === geracaoManualRef.current) {
        troncoAtualRef.current = res.tronco
        fatiasAtuaisRef.current = res.fatias
        setTronco(res.tronco)
        setFatias(res.fatias)
      } else {
        const novaVersao = res.tronco.versao ?? (raiz.versao ?? 1) + 1
        troncoAtualRef.current = troncoAtualRef.current
          ? { ...troncoAtualRef.current, versao: novaVersao }
          : res.tronco
        fatiasAtuaisRef.current = fatiasAtuaisRef.current.map((fatia) => ({ ...fatia, versao: novaVersao }))
        setTronco((atual) => atual ? { ...atual, versao: novaVersao } : res.tronco)
        setFatias((atuais) => atuais.map((fatia) => ({ ...fatia, versao: novaVersao })))
      }
      return true
    }).catch((erro: unknown) => {
      erroManualRef.current = true
      show(erro instanceof ErroConflitoRascunho
        ? 'A ficha mudou em outra aba. Sua edição continua na tela; volte ao caderno para comparar antes de confirmar.'
        : 'Não consegui salvar esta edição. Ela continua na tela e não será confirmada até salvar.')
      return false
    }).finally(() => {
      salvamentosManuaisRef.current -= 1
      if (salvamentosManuaisRef.current === 0) setSalvandoManual(false)
    })
    filaManualRef.current = tarefa
    return tarefa
  }

  async function salvarCampoTronco(chave: string, valor: string | null) {
    const atual = troncoAtualRef.current ?? tronco
    if (!atual) return
    const novosCampos = { ...atual.campos, [chave]: valor }
    const proximoTronco = { ...atual, campos: novosCampos }
    troncoAtualRef.current = proximoTronco
    setTronco(proximoTronco)
    if (atual.modo_entrada === 'manual') {
      geracaoManualRef.current += 1
      erroManualRef.current = false
      void enfileirarSalvamentoManual()
      return
    }
    try {
      await atualizarFatia(atual.id, null, { [chave]: valor })
      // o comum mudou → o texto final de TODAS as fatias presentes muda junto
      await carregar(true)
      show('Campo atualizado ✓')
    } catch {
      show('Não consegui salvar — recarregando')
      carregar()
    }
  }

  /** Marca uma falta declarada pelo professor antes da confirmação. */
  async function responder(registroAlvoId: string, presenca: 'presente' | 'ausente') {
    const aplicarLocal = () => {
      setFatias((atual) =>
        atual.map((f) => (f.id === registroAlvoId ? { ...f, campos: { ...f.campos, presenca } } : f)),
      )
      fatiasAtuaisRef.current = fatiasAtuaisRef.current.map((f) =>
        f.id === registroAlvoId ? { ...f, campos: { ...f.campos, presenca } } : f)
      if (troncoAtualRef.current?.id === registroAlvoId) {
        const atual = troncoAtualRef.current
        const proximoTronco = { ...atual, campos: { ...atual.campos, presenca } }
        troncoAtualRef.current = proximoTronco
        setTronco(proximoTronco)
      }
      setPendencias((atual) => atual.filter((p) => p.registro_alvo_id !== registroAlvoId))
      show(presenca === 'presente' ? 'Marcado como presente ✓' : 'Marcado como falta ✓')
    }

    const ehManual = (troncoAtualRef.current ?? tronco)?.modo_entrada === 'manual'
    if (ehManual) {
      salvamentosManuaisRef.current += 1
      setSalvandoManual(true)
      const tarefa = continuarFila(filaManualRef.current, async () => {
        const raiz = troncoAtualRef.current
        if (!raiz) return false
        const res = await salvarRascunhoManual(
          raiz.id,
          raiz.versao ?? 1,
          limparTroncoManual(raiz.campos),
          fatiasAtuaisRef.current.map((fatia) => ({
            id: fatia.id,
            campos: limparCamposManuais(fatia.campos) as Record<string, string>,
          })),
        )
        const novaVersao = res.tronco.versao ?? (raiz.versao ?? 1) + 1
        troncoAtualRef.current = { ...raiz, versao: novaVersao }
        fatiasAtuaisRef.current = fatiasAtuaisRef.current.map((fatia) => ({ ...fatia, versao: novaVersao }))
        setTronco((atual) => atual ? { ...atual, versao: novaVersao } : res.tronco)
        setFatias((atuais) => atuais.map((fatia) => ({ ...fatia, versao: novaVersao })))
        await responderPresenca(registroAlvoId, presenca)
        erroManualRef.current = false
        aplicarLocal()
        return true
      }).catch(() => {
        erroManualRef.current = true
        show('Não consegui salvar a presença. Nada será confirmado até tentar novamente.')
        return false
      }).finally(() => {
        salvamentosManuaisRef.current -= 1
        if (salvamentosManuaisRef.current === 0) setSalvandoManual(false)
      })
      filaManualRef.current = tarefa
      await tarefa
      return
    }

    try {
      await responderPresenca(registroAlvoId, presenca)
      aplicarLocal()
    } catch {
      show('Não consegui salvar a presença — tenta de novo')
    }
  }

  async function salvarCampoFatia(fatiaId: string, chave: string, valor: string | null) {
    const raiz = troncoAtualRef.current ?? tronco
    if (!raiz) return
    const atuais = fatiasAtuaisRef.current.length > 0 ? fatiasAtuaisRef.current : fatias
    const alvo = atuais.find((f) => f.id === fatiaId)
    if (!alvo) return
    const novosCampos = { ...alvo.campos, [chave]: valor }
    const proximasFatias = atuais.map((f) => (f.id === fatiaId ? { ...f, campos: novosCampos } : f))
    fatiasAtuaisRef.current = proximasFatias
    setFatias(proximasFatias)
    if (raiz.modo_entrada === 'manual') {
      geracaoManualRef.current += 1
      erroManualRef.current = false
      void enfileirarSalvamentoManual()
      return
    }
    try {
      await atualizarFatia(fatiaId, null, { [chave]: valor })
      await carregar(true)
      show('Campo atualizado ✓')
    } catch {
      show('Não consegui salvar — recarregando')
      carregar()
    }
  }

  // ---- confirmar e gravar (por aluno) ----

  async function confirmar(modo: ModoRegistro) {
    const raiz = troncoAtualRef.current ?? tronco
    if (!raiz) return
    setEscolhendoModo(false)
    setFase('confirmando')
    setPendencias([])
    try {
      if (raiz.modo_entrada === 'manual') {
        const tudoSalvo = await filaManualRef.current
        if (!tudoSalvo || erroManualRef.current) {
          setFase('ok')
          show('Não confirmei: há uma edição que ainda não foi salva. Seu texto continua na tela.')
          return
        }
      }
      // garante que TODA fatia presente vai gravar comum + individual
      // (regenera e persiste os textos finais antes da RPC de confirmação)
      const res = await confirmarRegistro(raiz.id, modo)
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
                <Button size="sm" onClick={() => void carregar()}>
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
    const temDever = Boolean(tronco.campos.dever_casa)
      || fatias.some((fatia) => Boolean(String(fatia.campos.dever_casa ?? '').trim()))
    return <TelaSucesso resultado={sucesso} fatias={fatias} temDever={temDever} entradaManual={tronco.modo_entrada === 'manual'} />
  }

  const temFatias = fatias.length > 0
  const entradaManual = tronco.modo_entrada === 'manual'
  const temTroncoManual = entradaManual && ['atividades', 'objetivo', 'obs_gerais', 'repertorio', 'dever_casa']
    .some((chave) => typeof tronco.campos[chave] === 'string' && String(tronco.campos[chave]).trim())
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
          {entradaManual
            ? 'Você preencheu durante a aula — confira cada aluno antes de gravar. Campo vazio continua opcional. ✋'
            : 'Fábio organizou seu áudio — confira e confirme. Eu nunca invento: campo vazio é convite ✋'}
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
            <ul className="space-y-2 text-text-secondary">
              {pendencias.map((p) => {
                // O nome vem do BANCO. Antes a tela procurava o id na lista de
                // fatias — e em aula 1:1 não existe fatia, então saía "Aluno".
                const nome =
                  p.aluno_nome ??
                  (fatias.find((f) => f.id === p.registro_alvo_id)?.aluno_nome as string | null) ??
                  'Aluno'
                const pergunta = p.campo_obrigatorio === 'presenca'
                return (
                  <li key={p.registro_alvo_id}>
                    <b className="text-text-primary">{nome}</b>{' '}
                    {p.motivo === 'sem texto' ? 'sem conteúdo pra gravar' : p.motivo}
                    {pergunta && (
                      <p className="mt-[6px] text-[12px] leading-relaxed text-text-secondary">
                        A presença sem falta declarada é materializada pelo motor na confirmação. Atualize o rascunho
                        antes de tentar de novo; nada foi marcado nesta tentativa.
                      </p>
                    )}
                  </li>
                )
              })}
            </ul>
          </div>
        )}

        {/* TRONCO — bloco comum da turma */}
        {(!entradaManual || temTroncoManual) && <div className="mx-4 mb-3 overflow-hidden rounded-lg border border-[color:var(--brand-border)] bg-bg-surface">
          <div className="flex items-center gap-[9px] border-b border-[color:var(--brand-border)] bg-brand-soft px-[14px] py-3">
            <i className="fa-solid fa-music text-brand-text" aria-hidden="true" />
            <b className="text-[13px] uppercase tracking-[.5px]">{entradaManual ? 'Em comum para a turma' : 'O que a turma trabalhou'}</b>
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
        </div>}

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
            const declarada = presencaDaFatia(f)
            const ausente = declarada === 'ausente'
            const semFaltaDeclarada = declarada === 'nao_informada'
            const repertorioDaTurma = typeof tronco.campos.repertorio === 'string' ? tronco.campos.repertorio : null
            const repertorioIndividual = typeof f.campos.repertorio === 'string' ? f.campos.repertorio : null
            const repertorioParaEditar = repertorioIndividualVisivel(repertorioDaTurma, repertorioIndividual)
              ? repertorioIndividual
              : null
            return (
              <div key={f.id} className={cx(ausente && 'opacity-60')}>
                <Fatia
                  nome={nomeCompleto}
                  fotoUrl={foto}
                  presenca={ausente ? 'faltou' : 'presente'}
                  defaultOpen={!ausente}
                  acao={
                    semFaltaDeclarada ? <PresencaPadrao nome={primeiro} onMarcarFalta={() => void responder(f.id, 'ausente')} /> : undefined
                  }
                >
                  {ausente ? (
                    <div className="px-[14px] py-[11px] text-sm text-text-secondary">
                      <p>Falta declarada — nada será gravado pra {primeiro}. Nada foi inventado. ✋</p>
                      <button
                        type="button"
                        className="mt-2 text-[12.5px] font-bold text-brand-text underline"
                        onClick={() => void responder(f.id, 'presente')}
                      >
                        Desfazer falta
                      </button>
                    </div>
                  ) : (
                    entradaManual ? (
                      <>
                        <CampoEditavel label="Repertório" icon="fa-solid fa-list-ol" value={(f.campos.repertorio as string | null) ?? null} cutucada={`Repertório de ${primeiro} (opcional)`} onSave={(v) => void salvarCampoFatia(f.id, 'repertorio', v)} />
                        <CampoEditavel label="Atividades" icon="fa-solid fa-music" value={(f.campos.atividades as string | null) ?? null} cutucada={`Atividades de ${primeiro} (opcional)`} onSave={(v) => void salvarCampoFatia(f.id, 'atividades', v)} />
                        <CampoEditavel label="Objetivo" icon="fa-solid fa-bullseye" value={(f.campos.objetivo as string | null) ?? null} cutucada={`Objetivo de ${primeiro} (opcional)`} onSave={(v) => void salvarCampoFatia(f.id, 'objetivo', v)} />
                        <CampoEditavel label="Observações" icon="fa-solid fa-comment-dots" value={(f.campos.observacao as string | null) ?? null} cutucada={`Observações sobre ${primeiro} (opcional)`} onSave={(v) => void salvarCampoFatia(f.id, 'observacao', v)} />
                        <CampoEditavel label="Dever de casa" icon="fa-solid fa-house" value={(f.campos.dever_casa as string | null) ?? null} cutucada={`Dever de casa de ${primeiro} (opcional)`} dever onSave={(v) => void salvarCampoFatia(f.id, 'dever_casa', v)} />
                        <CampoEditavel label="Progresso individual" icon="fa-solid fa-arrow-trend-up" value={(f.campos.progresso as string | null) ?? null} cutucada={`Progresso de ${primeiro} (opcional)`} onSave={(v) => void salvarCampoFatia(f.id, 'progresso', v)} />
                      </>
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
                          label="Repertório individual"
                          icon="fa-solid fa-list-ol"
                          value={repertorioParaEditar}
                          cutucada={`Repertório individual de ${primeiro} não informado (opcional)`}
                          onSave={(v) => void salvarCampoFatia(f.id, 'repertorio', v)}
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
                    )
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
              ? 'Esconder prévia canônica'
              : temFatias
                ? 'Ver a prévia canônica (por aluno)'
                : 'Ver a prévia canônica'}
          </button>
          {verTextoFinal && (
            <div className="mt-2 space-y-2">
                <PreviaCanonico
                  titulo="Tronco da turma"
                  registro={tronco}
                  presenca={temFatias ? undefined : presencaDaFatia(tronco)}
                />
              {temFatias &&
                fatias.map((f) => (
                  <PreviaCanonico
                    key={f.id}
                    titulo={`Aula de ${(f.aluno_nome as string | null) ?? 'aluno'}`}
                    registro={f}
                    presenca={presencaDaFatia(f)}
                    repertorioTurma={typeof tronco.campos.repertorio === 'string' ? tronco.campos.repertorio : null}
                  />
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
        <Button
          className="flex-1"
          disabled={fase === 'confirmando'}
          onClick={() => (jaReg.ja ? setEscolhendoModo(true) : void confirmar('novo'))}
        >
          {fase === 'confirmando' ? (
            <>
              <i className="fa-solid fa-spinner fa-spin" aria-hidden="true" /> {salvandoManual ? 'Salvando e gravando…' : 'Gravando…'}
            </>
          ) : salvandoManual ? (
            <>
              <i className="fa-solid fa-spinner fa-spin" aria-hidden="true" /> Salvar e confirmar
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
          <button className="absolute inset-0 bg-scrim" aria-label="Fechar" onClick={() => setEscolhendoModo(false)} />
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

function PreviaCanonico({
  titulo,
  registro,
  presenca,
  repertorioTurma,
}: {
  titulo: string
  registro: RegistroRow
  presenca?: ReturnType<typeof presencaDaFatia>
  repertorioTurma?: string | null
}) {
  const destino = typeof registro.campos.destino_devolutiva === 'string' ? registro.campos.destino_devolutiva : null
  const situacaoPresenca =
    presenca === 'presente'
      ? 'Presente'
      : presenca === 'ausente'
        ? 'Faltou — este aluno não receberá lançamento'
        : presenca
          ? 'Será marcada como presente ao confirmar'
          : null
  const camposEsperados = registro.parent_id
    ? [
        ['progresso', 'progresso'],
        ['repertorio', 'repertório individual'],
        ['proximo_passo', 'próximo passo'],
        ['observacao', 'observação'],
      ]
    : [
        ['atividades', 'atividades'],
        ['objetivo', 'objetivo'],
        ['materiais', 'materiais'],
        ['repertorio', 'repertório'],
        ['obs_gerais', 'observações'],
        ['dever_casa', 'dever de casa'],
      ]
  const camposVazios = camposEsperados
    .filter(([chave]) => {
      const valor = typeof registro.campos[chave] === 'string' ? String(registro.campos[chave]) : null
      return chave === 'repertorio' && registro.parent_id
        ? !repertorioIndividualVisivel(repertorioTurma, valor)
        : !valor?.trim()
    })
    .map(([, rotulo]) => rotulo)

  return (
    <div className="rounded-md border border-border-subtle bg-bg-inset px-3 py-[10px]">
      <div className="mb-1 text-[11px] font-bold uppercase tracking-[.5px] text-text-secondary">{titulo}</div>
      <pre className="whitespace-pre-wrap font-mono text-[11.5px] leading-relaxed text-text-primary">
        {registro.texto_consolidado?.trim() || '— sem conteúdo no rascunho canônico —'}
      </pre>
      {situacaoPresenca && <p className="mt-2 text-[11.5px] text-text-secondary">Presença: {situacaoPresenca}</p>}
      {camposVazios.length > 0 && <p className="mt-1 text-[11.5px] text-text-secondary">Em branco: {camposVazios.join(', ')}</p>}
      <p className="mt-1 text-[11.5px] text-text-secondary">
        Devolutiva: {destino ?? 'rascunho para sua revisão; nunca é enviada automaticamente'}
      </p>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Sucesso (tela 5 do protótipo) — com o retorno REAL da RPC
// ---------------------------------------------------------------------------

function TelaSucesso({
  resultado,
  fatias,
  temDever,
  entradaManual,
}: {
  resultado: ConfirmacaoResultado
  fatias: RegistroRow[]
  temDever: boolean
  entradaManual: boolean
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
          {temDever && <Badge variant="warn">Dever de casa registrado</Badge>}
          {resultado.ausentes_puladas > 0 && <Badge variant="danger">{resultado.ausentes_puladas} ausente</Badge>}
        </div>
        <Button block className="max-w-[290px]" onClick={() => navigate('/app')}>
          Voltar ao início
        </Button>
        <span className="font-mono text-[10.5px] tracking-[.3px] text-text-muted">
          registrar_aula_fabio · {resultado.gravadas} {resultado.gravadas === 1 ? 'aula' : 'aulas'} · {entradaManual ? 'preenchimento manual' : 'origem áudio'}
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

/**
 * O motor 093 torna presente toda fatia sem falta declarada apenas no commit.
 * A UI explica o efeito e oferece a única exceção explícita; ela nunca pergunta
 * se o aluno esteve nem faz uma segunda regra de presença.
 */
function PresencaPadrao({ nome, onMarcarFalta }: { nome: string; onMarcarFalta: () => void }) {
  return (
    <div>
      <p className="mb-[7px] text-[13px] text-text-secondary">
        Sem falta declarada — <b className="text-text-primary">{nome}</b> será marcado como presente ao confirmar.
      </p>
      <button
        type="button"
        onClick={onMarcarFalta}
        className="rounded-md border border-danger-text px-3 py-[8px] text-[12.5px] font-bold text-danger-text hover:bg-danger-soft"
      >
        <i className="fa-solid fa-xmark" aria-hidden="true" /> Marcar falta
      </button>
    </div>
  )
}
