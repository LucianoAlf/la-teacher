import { useCallback, useEffect, useRef, useState } from 'react'
import { useLocation, useNavigate, useParams } from 'react-router-dom'
import { Avatar, Button, EmptyState, ScreenHeader, Skeleton, Toast, useToast } from '../../components/ui'
import {
  abrirRascunhoManual,
  ErroConflitoRascunho,
  prepararRascunhoManual,
  salvarRascunhoManual,
  type RegistroRow,
  type SessaoAula,
} from '../../lib/api'
import { useAuth } from '../../lib/auth'
import { cx } from '../../lib/cx'
import { formatDiaCurto, formatHoraBRT } from '../../lib/date'
import { AppFrame } from '../../pages/app/AppFrame'
import {
  aplicarCopia,
  CAMPOS_MANUAIS,
  contarDiferencasRascunho,
  detectarSobrescritas,
  limparCamposManuais,
  mesclarCacheComRoster,
  type CampoManual,
  type FatiaManual,
  type OperacaoCopia,
} from './modelo'
import {
  buscarCacheManual,
  chaveCacheManual,
  removerCacheManual,
  salvarCacheManual,
  type CacheRascunhoManual,
} from './rascunhoLocal'

const CAMPOS: Array<{ chave: CampoManual; label: string; dica: string; icon: string }> = [
  { chave: 'repertorio', label: 'Repertório', dica: 'Música ou peça deste aluno', icon: 'fa-solid fa-list-ol' },
  { chave: 'atividades', label: 'Atividades', dica: 'O que vocês fizeram na aula', icon: 'fa-solid fa-music' },
  { chave: 'objetivo', label: 'Objetivo', dica: 'O que foi trabalhado', icon: 'fa-solid fa-bullseye' },
  { chave: 'observacao', label: 'Observações', dica: 'Algo importante sobre esta aula', icon: 'fa-solid fa-comment-dots' },
  { chave: 'dever_casa', label: 'Dever de casa', dica: 'O que este aluno vai praticar', icon: 'fa-solid fa-house' },
  { chave: 'progresso', label: 'Progresso individual', dica: 'Como este aluno avançou', icon: 'fa-solid fa-arrow-trend-up' },
]

const CAMPOS_TRONCO = [
  { chave: 'repertorio', label: 'Repertório em comum', dica: 'Só se foi igual para toda a turma' },
  { chave: 'atividades', label: 'Atividades em comum', dica: 'Atividade realmente feita por todos' },
  { chave: 'objetivo', label: 'Objetivo em comum', dica: 'Objetivo realmente compartilhado' },
  { chave: 'obs_gerais', label: 'Observação geral', dica: 'Uma observação sobre a turma inteira' },
  { chave: 'dever_casa', label: 'Dever em comum', dica: 'Só se foi o mesmo para todos' },
] as const

function camposDoTronco(campos: Record<string, unknown>): Record<string, string> {
  return CAMPOS_TRONCO.reduce<Record<string, string>>((resultado, campo) => {
    const valor = campos[campo.chave]
    if (typeof valor === 'string') resultado[campo.chave] = valor
    return resultado
  }, {})
}

type Fase = 'carregando' | 'erro' | 'ok'
type EstadoSalvamento = 'salvo' | 'salvando' | 'local' | 'nao_salvo' | 'conflito'
type ResultadoSalvamento = 'salvo' | 'desatualizado' | 'ocupado' | 'erro' | 'conflito'

interface RecuperacaoConflito {
  servidor: RegistroRow
  troncoCampos: Record<string, string>
  fatias: FatiaManual[]
  diferencas: number
}

function fatiaDaApi(fatia: RegistroRow): FatiaManual {
  return {
    id: fatia.id,
    alunoId: fatia.aluno_id ?? 0,
    alunoNome: fatia.aluno_nome ?? 'Aluno',
    alunoFotoUrl: fatia.aluno_foto_url,
    versao: fatia.versao ?? 1,
    campos: limparCamposManuais(fatia.campos),
  }
}

function troncoDoCache(cache: CacheRascunhoManual): RegistroRow {
  return {
    id: cache.registroId,
    aula_id: cache.aulaId,
    aluno_id: null,
    parent_id: null,
    audio_id: null,
    molde: 'C',
    campos: cache.troncoCampos,
    texto_consolidado: null,
    status: 'rascunho',
    origem: 'app',
    modo_entrada: 'manual',
    versao: cache.versao,
    criado_em: cache.atualizadoEm,
  }
}

function falhaTransitoriaDeRede(erro: unknown): boolean {
  if (typeof navigator !== 'undefined' && navigator.onLine === false) return true
  const texto = erro instanceof Error ? erro.message : String(erro)
  return /failed to fetch|networkerror|network request failed|load failed|fetch failed|connection/i.test(texto)
}

/** /app/registro-manual/:aulaId — caderno contínuo, uma ficha por aluno. */
export default function RegistroManualPage() {
  const { aulaId } = useParams()
  const idAula = Number(aulaId)
  const navigate = useNavigate()
  const location = useLocation()
  const sessao = (location.state as { sessao?: SessaoAula } | null)?.sessao
  const { session } = useAuth()
  const { message, visible, show } = useToast()

  const [fase, setFase] = useState<Fase>('carregando')
  const [erro, setErro] = useState('')
  const [tronco, setTronco] = useState<RegistroRow | null>(null)
  const [troncoCampos, setTroncoCampos] = useState<Record<string, string>>({})
  const [troncoAberto, setTroncoAberto] = useState(false)
  const [fatias, setFatias] = useState<FatiaManual[]>([])
  const [audioAberto, setAudioAberto] = useState<string | null>(null)
  const [contexto, setContexto] = useState<{ curso?: string | null; turma?: string | null; data?: string | null; hora?: string | null }>({})
  const [salvamento, setSalvamento] = useState<EstadoSalvamento>('salvo')
  const [edicao, setEdicao] = useState(0)
  const [preparando, setPreparando] = useState(false)
  const [copia, setCopia] = useState<OperacaoCopia | null>(null)
  const [recuperacao, setRecuperacao] = useState<RecuperacaoConflito | null>(null)

  const troncoRef = useRef<RegistroRow | null>(null)
  const troncoCamposRef = useRef<Record<string, string>>({})
  const fatiasRef = useRef<FatiaManual[]>([])
  const versaoRef = useRef(1)
  const geracaoRef = useRef(0)
  const geracaoSalvaRef = useRef(0)
  const salvandoRef = useRef(false)
  const salvarPendenteRef = useRef(false)

  const carregar = useCallback(async () => {
    if (!Number.isInteger(idAula) || idAula <= 0) {
      setErro('A aula informada não é válida.')
      setFase('erro')
      return
    }
    setFase('carregando')
    const owner = session?.user.id
    const cache = owner
      ? await buscarCacheManual(owner, idAula).catch(() => null)
      : null
    try {
      const res = await abrirRascunhoManual(idAula)
      const doServidor = res.fatias.map(fatiaDaApi)
      let escolhidas = doServidor
      let camposComuns = camposDoTronco(res.tronco.campos)
      let estado: EstadoSalvamento = 'salvo'
      let proximaRecuperacao: RecuperacaoConflito | null = null
      if (cache?.registroId === res.tronco.id) {
        const mescladas = mesclarCacheComRoster(cache.fatias, doServidor)
        if (cache.versao === (res.tronco.versao ?? 1)) {
          escolhidas = mescladas
          camposComuns = cache.troncoCampos
          estado = 'local'
        } else {
          escolhidas = mescladas
          camposComuns = cache.troncoCampos
          estado = 'conflito'
          proximaRecuperacao = {
            servidor: res.tronco,
            troncoCampos: camposDoTronco(res.tronco.campos),
            fatias: doServidor,
            diferencas: contarDiferencasRascunho(
              cache.troncoCampos,
              camposDoTronco(res.tronco.campos),
              mescladas,
              doServidor,
            ),
          }
        }
      }
      troncoRef.current = res.tronco
      fatiasRef.current = escolhidas
      troncoCamposRef.current = camposComuns
      versaoRef.current = res.tronco.versao ?? 1
      geracaoRef.current = estado === 'local' ? 1 : 0
      geracaoSalvaRef.current = 0
      setTronco(res.tronco)
      setFatias(escolhidas)
      setTroncoCampos(camposComuns)
      setTroncoAberto(Object.values(camposComuns).some((valor) => valor.trim()))
      setAudioAberto(res.audio_aberto_registro_id ?? null)
      setContexto({ curso: res.aula?.curso, turma: res.aula?.turma, data: res.aula?.data_aula, hora: res.aula?.hora })
      setSalvamento(estado)
      setRecuperacao(proximaRecuperacao)
      setFase('ok')
    } catch (e) {
      if (cache && falhaTransitoriaDeRede(e)) {
        const raizLocal = troncoDoCache(cache)
        troncoRef.current = raizLocal
        fatiasRef.current = cache.fatias
        troncoCamposRef.current = cache.troncoCampos
        versaoRef.current = cache.versao
        geracaoRef.current = 1
        geracaoSalvaRef.current = 0
        setTronco(raizLocal)
        setFatias(cache.fatias)
        setTroncoCampos(cache.troncoCampos)
        setTroncoAberto(Object.values(cache.troncoCampos).some((valor) => valor.trim()))
        setSalvamento('local')
        setRecuperacao(null)
        setFase('ok')
        return
      }
      const texto = e instanceof Error ? e.message : String(e)
      const mensagem = texto.includes('registro_ainda_nao_disponivel')
        ? 'O caderno abre 15 minutos antes da aula.'
        : texto.includes('roster')
          ? 'A lista de alunos desta aula ainda não sincronizou. Tenta de novo mais tarde.'
          : texto.includes('janela_de_gravacao_encerrada')
            ? 'O prazo desta aula encerrou. Fala com a coordenação.'
            : 'Não consegui abrir a ficha agora. Verifica a conexão e tenta de novo.'
      setErro(mensagem)
      setFase('erro')
    }
  }, [idAula, session?.user.id])

  useEffect(() => { void carregar() }, [carregar])

  async function guardarLocal(proximas: FatiaManual[]): Promise<boolean> {
    const raiz = troncoRef.current
    const owner = session?.user.id
    if (!raiz || !owner) return false
    return salvarCacheManual({
      id: chaveCacheManual(owner, idAula),
      ownerUserId: owner,
      aulaId: idAula,
      registroId: raiz.id,
      versao: versaoRef.current,
      troncoCampos: troncoCamposRef.current,
      fatias: proximas,
      atualizadoEm: new Date().toISOString(),
      estado: 'local',
    }).then(() => true).catch(() => false)
  }

  function alterarFatias(proximas: FatiaManual[]) {
    fatiasRef.current = proximas
    setFatias(proximas)
    geracaoRef.current += 1
    const geracao = geracaoRef.current
    setSalvamento('nao_salvo')
    setEdicao((valor) => valor + 1)
    void guardarLocal(proximas).then((guardado) => {
      if (geracao === geracaoRef.current && geracao > geracaoSalvaRef.current && !salvandoRef.current) {
        setSalvamento(guardado ? 'local' : 'nao_salvo')
      }
    })
  }

  async function salvarAgora(): Promise<ResultadoSalvamento> {
    const raiz = troncoRef.current
    if (!raiz) return 'erro'
    if (geracaoSalvaRef.current === geracaoRef.current) return 'salvo'
    if (salvandoRef.current) {
      salvarPendenteRef.current = true
      return 'ocupado'
    }
    salvandoRef.current = true
    const geracao = geracaoRef.current
    const snapshot = fatiasRef.current
    setSalvamento('salvando')
    try {
      const res = await salvarRascunhoManual(
        raiz.id,
        versaoRef.current,
        troncoCamposRef.current,
        snapshot.map((fatia) => ({ id: fatia.id, campos: fatia.campos as Record<string, string> })),
      )
      const novaVersao = res.tronco.versao ?? versaoRef.current + 1
      versaoRef.current = novaVersao
      troncoRef.current = { ...raiz, versao: novaVersao }
      geracaoSalvaRef.current = Math.max(geracaoSalvaRef.current, geracao)
      setTronco((atual) => atual ? { ...atual, versao: novaVersao } : atual)
      setFatias((atuais) => atuais.map((fatia) => ({ ...fatia, versao: novaVersao })))
      if (geracao === geracaoRef.current) {
        setSalvamento('salvo')
        if (session?.user.id) await removerCacheManual(session.user.id, idAula).catch(() => {})
      } else {
        setSalvamento('local')
        salvarPendenteRef.current = true
      }
      return geracao === geracaoRef.current ? 'salvo' : 'desatualizado'
    } catch (e) {
      if (e instanceof ErroConflitoRascunho) {
        setSalvamento('conflito')
        show('Esta ficha mudou em outra aba. Recarregue antes de continuar.')
        return 'conflito'
      } else {
        setSalvamento('local')
        return 'erro'
      }
    } finally {
      salvandoRef.current = false
      if (salvarPendenteRef.current) {
        salvarPendenteRef.current = false
        setEdicao((valor) => valor + 1)
      }
    }
  }

  async function salvarAteAEdicaoAtual(): Promise<boolean> {
    for (let tentativa = 0; tentativa < 8; tentativa += 1) {
      while (salvandoRef.current) {
        await new Promise((resolve) => window.setTimeout(resolve, 30))
      }
      if (geracaoSalvaRef.current === geracaoRef.current) return true
      const resultado = await salvarAgora()
      if (resultado === 'erro' || resultado === 'conflito') return false
      if (resultado === 'salvo' && geracaoSalvaRef.current === geracaoRef.current) return true
    }
    show('Ainda estou salvando as últimas alterações. Tenta revisar novamente em alguns segundos.')
    return false
  }

  useEffect(() => {
    if (edicao === 0 || fase !== 'ok' || salvamento === 'conflito') return
    const timer = window.setTimeout(() => { void salvarAgora() }, 800)
    return () => window.clearTimeout(timer)
    // salvarAgora lê refs intencionalmente: o snapshot mais novo vence o debounce.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [edicao, fase, salvamento === 'conflito'])

  useEffect(() => {
    const aoVoltar = () => { if (salvamento === 'local' || salvamento === 'nao_salvo') setEdicao((valor) => valor + 1) }
    window.addEventListener('online', aoVoltar)
    return () => window.removeEventListener('online', aoVoltar)
  }, [salvamento])

  function editarCampo(fatiaId: string, chave: CampoManual, valor: string) {
    alterarFatias(fatiasRef.current.map((fatia) =>
      fatia.id === fatiaId ? { ...fatia, campos: { ...fatia.campos, [chave]: valor } } : fatia,
    ))
  }

  function editarTronco(chave: string, valor: string) {
    const proximos = { ...troncoCamposRef.current, [chave]: valor }
    troncoCamposRef.current = proximos
    setTroncoCampos(proximos)
    geracaoRef.current += 1
    const geracao = geracaoRef.current
    setSalvamento('nao_salvo')
    setEdicao((atual) => atual + 1)
    void guardarLocal(fatiasRef.current).then((guardado) => {
      if (geracao === geracaoRef.current && geracao > geracaoSalvaRef.current && !salvandoRef.current) {
        setSalvamento(guardado ? 'local' : 'nao_salvo')
      }
    })
  }

  async function usarVersaoDoServidor() {
    if (!recuperacao) return
    troncoRef.current = recuperacao.servidor
    troncoCamposRef.current = recuperacao.troncoCampos
    fatiasRef.current = recuperacao.fatias
    versaoRef.current = recuperacao.servidor.versao ?? 1
    geracaoRef.current = 0
    geracaoSalvaRef.current = 0
    setTronco(recuperacao.servidor)
    setTroncoCampos(recuperacao.troncoCampos)
    setFatias(recuperacao.fatias)
    setSalvamento('salvo')
    setRecuperacao(null)
    if (session?.user.id) await removerCacheManual(session.user.id, idAula).catch(() => {})
    show('Versão do servidor carregada.')
  }

  function manterMinhaVersao() {
    if (!recuperacao) return
    versaoRef.current = recuperacao.servidor.versao ?? 1
    troncoRef.current = recuperacao.servidor
    setTronco(recuperacao.servidor)
    geracaoRef.current += 1
    setRecuperacao(null)
    setSalvamento('local')
    setEdicao((valor) => valor + 1)
    show('Sua versão local será salva sobre a versão mais recente.')
  }

  function concluirCopia() {
    if (!copia) return
    alterarFatias(aplicarCopia(fatiasRef.current, copia))
    setCopia(null)
    show(copia.campos.length === 1 ? 'Campo copiado ✓' : 'Ficha duplicada ✓')
  }

  async function revisar() {
    if (!troncoRef.current || salvamento === 'conflito') return
    setPreparando(true)
    try {
      if (!(await salvarAteAEdicaoAtual())) return
      const res = await prepararRascunhoManual(troncoRef.current.id, versaoRef.current)
      if (session?.user.id) await removerCacheManual(session.user.id, idAula).catch(() => {})
      navigate(`/app/confirmar/${res.tronco.id}`)
    } catch (e) {
      if (e instanceof ErroConflitoRascunho) {
        setSalvamento('conflito')
        show('A ficha mudou em outra aba. Recarregue para comparar.')
      } else show('Não consegui abrir a revisão. Seu rascunho continua guardado.')
    } finally {
      setPreparando(false)
    }
  }

  const subtitulo = [
    contexto.curso ?? sessao?.curso,
    contexto.turma ?? sessao?.turma_nome,
    contexto.data && formatDiaCurto(contexto.data),
    contexto.hora && formatHoraBRT(contexto.hora),
  ].filter(Boolean).join(' · ')

  if (fase === 'carregando') return (
    <AppFrame>
      <ScreenHeader title="Preencher durante a aula" onBack={() => navigate(-1)} />
      <div className="space-y-3 px-4 pt-3"><Skeleton className="h-20 w-full" /><Skeleton className="h-80 w-full" /></div>
    </AppFrame>
  )

  if (fase === 'erro' || !tronco) return (
    <AppFrame>
      <ScreenHeader title="Preencher durante a aula" onBack={() => navigate(-1)} />
      <div className="flex flex-1 flex-col justify-center">
        <EmptyState icon="fa-solid fa-book-open" title="O caderno não abriu" description={erro} action={<Button size="sm" onClick={() => void carregar()}>Tentar de novo</Button>} />
      </div>
    </AppFrame>
  )

  return (
    <AppFrame>
      <ScreenHeader
        title="Caderno da aula"
        subtitle={subtitulo}
        onBack={() => navigate(-1)}
        right={<EstadoSalvo estado={salvamento} />}
      />

      <div className="flex-1 overflow-y-auto px-4 pb-32">
        <div className="mb-3 rounded-lg border border-[color:var(--brand-border)] bg-brand-soft px-3 py-[11px] text-[12.5px] leading-relaxed text-brand-text">
          <b className="block">Uma ficha por aluno.</b>
          Preencha aos poucos. Nada daqui marca presença até você revisar e confirmar.
        </div>

        {audioAberto && (
          <div className="mb-3 rounded-lg border border-border-subtle bg-warning-soft px-3 py-[11px] text-[12.5px] leading-relaxed text-warning-text">
            <b className="block"><i className="fa-solid fa-wave-square mr-1.5" aria-hidden="true" />Há um áudio aberto nesta aula</b>
            Os dois rascunhos ficam separados; nada será mesclado ou apagado.
            <button type="button" className="mt-2 block font-bold underline" onClick={() => navigate(`/app/confirmar/${audioAberto}`)}>Abrir o áudio</button>
          </div>
        )}

        {salvamento === 'conflito' && (
          <div className="mb-3 rounded-lg border border-danger-text bg-danger-soft px-3 py-[11px] text-[12.5px] text-danger-text">
            <b>Outra aba salvou esta ficha.</b> Seus campos locais não foram apagados.
            {recuperacao ? (
              <>
                <p className="mt-1">Encontramos {recuperacao.diferencas} {recuperacao.diferencas === 1 ? 'campo diferente' : 'campos diferentes'}.</p>
                <div className="mt-2 flex flex-wrap gap-2">
                  <button type="button" className="rounded-md border border-danger-text px-2.5 py-1.5 font-bold" onClick={() => void usarVersaoDoServidor()}>Usar servidor</button>
                  <button type="button" className="rounded-md bg-danger-text px-2.5 py-1.5 font-bold text-white" onClick={manterMinhaVersao}>Manter o que digitei</button>
                </div>
              </>
            ) : (
              <button type="button" className="mt-2 block font-bold underline" onClick={() => void carregar()}>Comparar com o servidor</button>
            )}
          </div>
        )}

        {fatias.length > 1 && (
          <section className="mb-3 overflow-hidden rounded-xl border border-dashed border-[color:var(--brand-border)] bg-bg-surface">
            <button type="button" className="flex w-full items-center gap-3 px-3 py-3 text-left" onClick={() => setTroncoAberto((aberto) => !aberto)}>
              <span className="flex h-9 w-9 items-center justify-center rounded-full bg-brand-soft text-brand-text"><i className="fa-solid fa-users" aria-hidden="true" /></span>
              <span className="min-w-0 flex-1"><b className="block text-sm">Algo foi igual para toda a turma?</b><span className="block text-[11.5px] text-text-secondary">Opcional · nunca preenche os alunos sozinho</span></span>
              <i className={cx('fa-solid fa-chevron-down text-xs text-text-muted transition-transform', troncoAberto && 'rotate-180')} aria-hidden="true" />
            </button>
            {troncoAberto && <div className="divide-y divide-border-subtle border-t border-border-subtle">
              {CAMPOS_TRONCO.map((campo) => <label key={campo.chave} className="block px-3 py-[10px]"><span className="mb-1.5 block text-[10.5px] font-bold uppercase tracking-[.5px] text-text-secondary">{campo.label}</span><textarea value={troncoCampos[campo.chave] ?? ''} rows={2} placeholder={campo.dica} className="min-h-[52px] w-full resize-y rounded-md border border-border-subtle bg-bg-app px-3 py-2 text-[13px] leading-relaxed text-text-primary outline-none placeholder:text-text-muted focus:border-brand" onChange={(evento) => editarTronco(campo.chave, evento.target.value)} /></label>)}
              <p className="bg-brand-soft px-3 py-2 text-[11px] leading-relaxed text-brand-text">O texto comum será combinado no preview. Os cartões abaixo continuam individuais e não serão alterados.</p>
            </div>}
          </section>
        )}

        <div className="mb-2 flex items-end justify-between">
          <div><span className="text-[11px] font-bold uppercase tracking-[.8px] text-brand-text">Alunos da turma</span><h2 className="text-lg font-extrabold">{fatias.length} {fatias.length === 1 ? 'ficha' : 'fichas'}</h2></div>
          <span className="text-[11px] text-text-muted">role para preencher ↓</span>
        </div>

        <div className="space-y-3">
          {fatias.map((fatia, indice) => (
            <article key={fatia.id} className="overflow-hidden rounded-xl border border-border-subtle bg-bg-surface shadow-sm">
              <header className="flex items-center gap-3 border-b border-border-subtle bg-bg-inset px-3 py-3">
                <Avatar nome={fatia.alunoNome} fotoUrl={fatia.alunoFotoUrl} tamanho="h-10 w-10 text-[13px]" />
                <div className="min-w-0 flex-1"><span className="block text-[10px] font-bold uppercase tracking-[.7px] text-text-muted">Ficha {indice + 1}</span><b className="block truncate text-[15px]">{fatia.alunoNome}</b></div>
                {fatias.length > 1 && <button type="button" className="rounded-md border border-border-strong px-2.5 py-2 text-[11.5px] font-bold text-brand-text" onClick={() => setCopia({ origemId: fatia.id, destinos: [], campos: [...CAMPOS_MANUAIS] })}><i className="fa-regular fa-clone mr-1.5" aria-hidden="true" />Duplicar</button>}
              </header>

              <div className="divide-y divide-border-subtle">
                {CAMPOS.map((campo) => (
                  <label key={campo.chave} className="block px-3 py-[11px]">
                    <span className="mb-1.5 flex items-center gap-2 text-[11px] font-bold uppercase tracking-[.55px] text-text-secondary">
                      <i className={cx(campo.icon, 'w-3 text-brand-text')} aria-hidden="true" />{campo.label}
                      {fatias.length > 1 && <button type="button" aria-label={`Copiar ${campo.label} de ${fatia.alunoNome}`} title={`Copiar ${campo.label}`} className="ml-auto flex h-7 w-7 items-center justify-center rounded-full text-brand-text active:bg-brand-soft" onClick={(evento) => { evento.preventDefault(); setCopia({ origemId: fatia.id, destinos: [], campos: [campo.chave] }) }}><i className="fa-regular fa-copy" aria-hidden="true" /></button>}
                    </span>
                    <textarea
                      value={fatia.campos[campo.chave] ?? ''}
                      rows={2}
                      placeholder={campo.dica}
                      className="min-h-[54px] w-full resize-y rounded-md border border-border-subtle bg-bg-app px-3 py-2 text-[13.5px] leading-relaxed text-text-primary outline-none transition-colors placeholder:text-text-muted focus:border-brand"
                      onChange={(evento) => editarCampo(fatia.id, campo.chave, evento.target.value)}
                    />
                  </label>
                ))}
              </div>
            </article>
          ))}
        </div>
      </div>

      <div className="absolute inset-x-0 bottom-0 border-t border-border-subtle bg-bg-app/95 px-4 pb-[calc(14px_+_env(safe-area-inset-bottom))] pt-3 backdrop-blur">
        <Button block disabled={preparando || salvamento === 'salvando' || salvamento === 'conflito'} onClick={() => void revisar()}>
          <i className="fa-solid fa-clipboard-check" aria-hidden="true" />{preparando ? 'Abrindo revisão…' : 'Revisar e confirmar'}
        </Button>
      </div>

      {copia && <ModalCopia fatias={fatias} operacao={copia} onChange={setCopia} onClose={() => setCopia(null)} onConfirm={concluirCopia} />}
      <Toast message={message} visible={visible} />
    </AppFrame>
  )
}

function EstadoSalvo({ estado }: { estado: EstadoSalvamento }) {
  const config = {
    salvo: ['fa-circle-check', 'Salvo', 'text-success-text'],
    salvando: ['fa-rotate fa-spin', 'Salvando', 'text-brand-text'],
    local: ['fa-mobile-screen', 'Só neste aparelho', 'text-warning-text'],
    nao_salvo: ['fa-cloud-arrow-up', 'Não salvo', 'text-warning-text'],
    conflito: ['fa-triangle-exclamation', 'Conflito', 'text-danger-text'],
  }[estado]
  return <span className={cx('flex items-center gap-1.5 text-[11px] font-bold', config[2])}><i className={`fa-solid ${config[0]}`} aria-hidden="true" />{config[1]}</span>
}

function ModalCopia({ fatias, operacao, onChange, onClose, onConfirm }: { fatias: FatiaManual[]; operacao: OperacaoCopia; onChange: (op: OperacaoCopia) => void; onClose: () => void; onConfirm: () => void }) {
  const botaoFecharRef = useRef<HTMLButtonElement>(null)
  const origem = fatias.find((fatia) => fatia.id === operacao.origemId)
  const sobrescritas = detectarSobrescritas(fatias, operacao)
  const ehFicha = operacao.campos.length > 1
  const campo = CAMPOS.find((item) => item.chave === operacao.campos[0])
  const alternar = (id: string) => onChange({ ...operacao, destinos: operacao.destinos.includes(id) ? operacao.destinos.filter((item) => item !== id) : [...operacao.destinos, id] })
  useEffect(() => {
    botaoFecharRef.current?.focus()
    const fecharComEscape = (evento: KeyboardEvent) => { if (evento.key === 'Escape') onClose() }
    window.addEventListener('keydown', fecharComEscape)
    return () => window.removeEventListener('keydown', fecharComEscape)
  }, [onClose])
  return (
    <div className="absolute inset-0 z-50 flex items-end bg-black/55 p-3" role="dialog" aria-modal="true" aria-labelledby="titulo-copia-manual">
      <div className="w-full rounded-2xl border border-border-subtle bg-bg-surface p-4 shadow-2xl">
        <div className="mb-3 flex items-start gap-3"><div className="flex h-9 w-9 items-center justify-center rounded-full bg-brand-soft text-brand-text"><i className={ehFicha ? 'fa-regular fa-clone' : 'fa-regular fa-copy'} aria-hidden="true" /></div><div className="min-w-0 flex-1"><b id="titulo-copia-manual" className="block text-base">{ehFicha ? 'Duplicar a ficha inteira' : `Copiar ${campo?.label ?? 'campo'}`}</b><span className="text-[12px] text-text-secondary">De {origem?.alunoNome} para:</span></div><button ref={botaoFecharRef} type="button" aria-label="Fechar" className="h-8 w-8 text-text-muted" onClick={onClose}><i className="fa-solid fa-xmark" aria-hidden="true" /></button></div>
        <div className="max-h-52 space-y-2 overflow-y-auto">
          {fatias.filter((fatia) => fatia.id !== operacao.origemId).map((fatia) => <label key={fatia.id} className="flex items-center gap-3 rounded-lg border border-border-subtle px-3 py-2.5"><input type="checkbox" className="h-4 w-4 accent-[color:var(--brand)]" checked={operacao.destinos.includes(fatia.id)} onChange={() => alternar(fatia.id)} /><Avatar nome={fatia.alunoNome} fotoUrl={fatia.alunoFotoUrl} tamanho="h-7 w-7 text-[10px]" /><span className="min-w-0 flex-1 truncate text-sm font-semibold">{fatia.alunoNome}</span></label>)}
        </div>
        {sobrescritas.length > 0 && <div className="mt-3 rounded-md bg-warning-soft px-3 py-2 text-[11.5px] leading-relaxed text-warning-text"><b>Vai substituir conteúdo já preenchido:</b> {sobrescritas.map((item) => `${item.destinoNome} (${item.campos.map((chave) => CAMPOS.find((campoItem) => campoItem.chave === chave)?.label).join(', ')})`).join('; ')}.</div>}
        <div className="mt-4 flex gap-2"><Button variant="ghost" className="flex-1" onClick={onClose}>Cancelar</Button><Button className="flex-1" disabled={operacao.destinos.length === 0} onClick={onConfirm}>{sobrescritas.length > 0 ? 'Substituir e copiar' : 'Copiar'}</Button></div>
      </div>
    </div>
  )
}
