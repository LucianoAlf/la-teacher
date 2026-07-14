import { useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Button, Card, EmptyState, Skeleton, Toast, useToast } from '../../components/ui'
import { cx } from '../../lib/cx'
import { useCarteira } from '../../features/alunos/useCarteira'
import { agruparPorCurso, contarPorUnidade, normalizar, type UnidadeContagem } from '../../features/alunos/carteira'
import { AlunoRow } from '../../features/alunos/AlunoRow'
import type { CarteiraAluno } from '../../lib/api'
import { AppFrame } from './AppFrame'
import { AppHeader } from './AppHeader'
import { AppNav } from './AppNav'

/** /app/alunos — carteira do professor, busca por nome, agrupada por curso. */
export default function AlunosPage() {
  const { message, visible, show } = useToast()
  const navigate = useNavigate()
  const { estado, recarregar } = useCarteira()
  const [busca, setBusca] = useState('')
  // null = "Todas"; string = unidade escolhida.
  const [unidade, setUnidade] = useState<string | null>(null)

  const abrirAluno = (aluno: CarteiraAluno) =>
    navigate(`/app/aluno/${aluno.aluno_id}`, { state: { aluno } })

  const alunos = estado.fase === 'ok' ? estado.alunos : []
  const unidades = useMemo(() => contarPorUnidade(alunos), [alunos])
  // Filtro de unidade só faz sentido pra quem dá aula em mais de uma.
  const multiUnidade = unidades.length > 1

  const grupos = useMemo(() => {
    const q = normalizar(busca)
    let filtrados = alunos
    if (unidade) filtrados = filtrados.filter((a) => (a.unidade ?? 'Sem unidade') === unidade)
    if (q) filtrados = filtrados.filter((a) => normalizar(a.aluno_nome).includes(q))
    return agruparPorCurso(filtrados)
  }, [alunos, busca, unidade])

  const totalFiltrado = grupos.reduce((n, g) => n + g.alunos.length, 0)
  // Na visão "Todas" com múltiplas unidades, mostra a unidade na linha (Canto aparece
  // em duas unidades — sem isso o professor não sabe de qual unidade é cada aluno).
  const mostrarUnidadeNaLinha = multiUnidade && unidade === null

  return (
    <AppFrame>
      <AppHeader />

      <div className="flex-1 overflow-y-auto px-4 pb-[calc(96px_+_env(safe-area-inset-bottom))] pt-1">
        {/* Busca */}
        <div className="relative mb-3">
          <i
            className="fa-solid fa-magnifying-glass pointer-events-none absolute left-[14px] top-1/2 -translate-y-1/2 text-text-muted"
            aria-hidden="true"
          />
          <input
            type="search"
            value={busca}
            onChange={(e) => setBusca(e.target.value)}
            placeholder="Buscar aluno pelo nome…"
            className="w-full rounded-md border border-border-strong bg-bg-inset py-[11px] pl-10 pr-3 text-sm text-text-primary placeholder:text-text-muted focus-visible:border-brand"
          />
        </div>

        {/* Filtro por unidade — só aparece pra professor multiunidade */}
        {multiUnidade && (
          <FiltroUnidades
            unidades={unidades}
            total={alunos.length}
            selecionada={unidade}
            onSelecionar={setUnidade}
          />
        )}

        <ConteudoCarteira
          fase={estado.fase}
          grupos={grupos}
          temBusca={busca.trim().length > 0}
          totalFiltrado={totalFiltrado}
          mostrarUnidade={mostrarUnidadeNaLinha}
          onRetry={recarregar}
          onLimparBusca={() => setBusca('')}
          onAbrirAluno={abrirAluno}
        />
      </div>

      <AppNav onMais={() => show('Mais ferramentas chegam em breve 🧰')} />
      <Toast message={message} visible={visible} />
    </AppFrame>
  )
}

// ---------------------------------------------------------------------------

/** Fileira de chips pra filtrar a carteira por unidade (rola na horizontal). */
function FiltroUnidades({
  unidades,
  total,
  selecionada,
  onSelecionar,
}: {
  unidades: UnidadeContagem[]
  total: number
  selecionada: string | null
  onSelecionar: (unidade: string | null) => void
}) {
  return (
    <div className="mb-3 -mx-4 flex gap-2 overflow-x-auto px-4 pb-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
      <ChipUnidade
        rotulo="Todas"
        total={total}
        ativo={selecionada === null}
        onClick={() => onSelecionar(null)}
      />
      {unidades.map((u) => (
        <ChipUnidade
          key={u.unidade}
          rotulo={u.unidade}
          total={u.total}
          ativo={selecionada === u.unidade}
          onClick={() => onSelecionar(u.unidade)}
        />
      ))}
    </div>
  )
}

function ChipUnidade({
  rotulo,
  total,
  ativo,
  onClick,
}: {
  rotulo: string
  total: number
  ativo: boolean
  onClick: () => void
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={ativo}
      className={cx(
        'inline-flex flex-none items-center gap-[7px] rounded-full border px-[13px] py-[7px] text-[12.5px] font-bold transition-colors',
        ativo
          ? 'border-brand bg-brand text-on-brand'
          : 'border-border-strong bg-bg-surface text-text-secondary',
      )}
    >
      {rotulo}
      <span className={cx('text-[11px] font-semibold', ativo ? 'text-on-brand' : 'text-text-muted')}>
        {total}
      </span>
    </button>
  )
}

// ---------------------------------------------------------------------------

function ConteudoCarteira({
  fase,
  grupos,
  temBusca,
  totalFiltrado,
  mostrarUnidade,
  onRetry,
  onLimparBusca,
  onAbrirAluno,
}: {
  fase: ReturnType<typeof useCarteira>['estado']['fase']
  grupos: ReturnType<typeof agruparPorCurso>
  temBusca: boolean
  totalFiltrado: number
  mostrarUnidade: boolean
  onRetry: () => void
  onLimparBusca: () => void
  onAbrirAluno: (aluno: CarteiraAluno) => void
}) {
  if (fase === 'carregando') {
    return (
      <div className="space-y-3">
        {[0, 1, 2].map((i) => (
          <div key={i} className="flex items-center gap-3 px-1">
            <Skeleton className="h-9 w-9 rounded-full" />
            <div className="flex-1 space-y-[6px]">
              <Skeleton className="h-[14px] w-1/2" />
              <Skeleton className="h-3 w-1/3" />
            </div>
          </div>
        ))}
      </div>
    )
  }

  if (fase === 'erro') {
    return (
      <EmptyState
        icon="fa-solid fa-triangle-exclamation"
        title="Não consegui carregar"
        description="Deu um problema ao buscar sua carteira. Verifica a conexão e tenta de novo."
        action={
          <Button size="sm" onClick={onRetry}>
            <i className="fa-solid fa-rotate-right" aria-hidden="true" /> Tentar de novo
          </Button>
        }
      />
    )
  }

  if (fase === 'sem_vinculo') {
    return (
      <EmptyState
        icon="fa-solid fa-id-badge"
        title="Acesso não ativado"
        description="Fala com a coordenação pra vincular seu login a um professor."
      />
    )
  }

  // Sem resultados de busca
  if (temBusca && totalFiltrado === 0) {
    return (
      <EmptyState
        icon="fa-solid fa-magnifying-glass"
        title="Nenhum aluno com esse nome"
        description="Tente outro nome ou limpe a busca pra ver a carteira toda."
        action={
          <Button size="sm" variant="ghost" onClick={onLimparBusca}>
            Limpar busca
          </Button>
        }
      />
    )
  }

  // Carteira vazia
  if (grupos.length === 0) {
    return (
      <EmptyState
        icon="fa-solid fa-user-group"
        title="Carteira vazia por enquanto"
        description="Assim que houver alunos vinculados a você, eles aparecem aqui agrupados por curso."
      />
    )
  }

  return (
    <div className="space-y-3">
      {grupos.map((g) => (
        <Card key={g.curso} title={g.curso} icon="fa-solid fa-graduation-cap" right={`${g.alunos.length}`}>
          {g.alunos.map((a, i) => (
            <AlunoRow
              key={`${a.aluno_id}-${a.curso}-${i}`}
              aluno={a}
              onAbrir={onAbrirAluno}
              mostrarUnidade={mostrarUnidade}
            />
          ))}
        </Card>
      ))}
    </div>
  )
}
