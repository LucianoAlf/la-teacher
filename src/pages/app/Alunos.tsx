import { useMemo, useState } from 'react'
import { Button, Card, EmptyState, Skeleton, Toast, useToast } from '../../components/ui'
import { useCarteira } from '../../features/alunos/useCarteira'
import { agruparPorCurso, normalizar } from '../../features/alunos/carteira'
import { AlunoRow } from '../../features/alunos/AlunoRow'
import { AppFrame } from './AppFrame'
import { AppHeader } from './AppHeader'
import { AppNav } from './AppNav'

/** /app/alunos — carteira do professor, busca por nome, agrupada por curso. */
export default function AlunosPage() {
  const { message, visible, show } = useToast()
  const { estado, recarregar } = useCarteira()
  const [busca, setBusca] = useState('')

  const alunos = estado.fase === 'ok' ? estado.alunos : []
  const grupos = useMemo(() => {
    const q = normalizar(busca)
    const filtrados = q ? alunos.filter((a) => normalizar(a.aluno_nome).includes(q)) : alunos
    return agruparPorCurso(filtrados)
  }, [alunos, busca])

  const totalFiltrado = grupos.reduce((n, g) => n + g.alunos.length, 0)

  return (
    <AppFrame>
      <AppHeader />

      <div className="flex-1 overflow-y-auto px-4 pb-24 pt-1">
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

        <ConteudoCarteira
          fase={estado.fase}
          grupos={grupos}
          temBusca={busca.trim().length > 0}
          totalFiltrado={totalFiltrado}
          onRetry={recarregar}
          onLimparBusca={() => setBusca('')}
        />
      </div>

      <AppNav onFabio={() => show('Chat com o Fábio chega no Sprint 4 🤖')} />
      <Toast message={message} visible={visible} />
    </AppFrame>
  )
}

// ---------------------------------------------------------------------------

function ConteudoCarteira({
  fase,
  grupos,
  temBusca,
  totalFiltrado,
  onRetry,
  onLimparBusca,
}: {
  fase: ReturnType<typeof useCarteira>['estado']['fase']
  grupos: ReturnType<typeof agruparPorCurso>
  temBusca: boolean
  totalFiltrado: number
  onRetry: () => void
  onLimparBusca: () => void
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
            <AlunoRow key={`${a.aluno_id}-${a.curso}-${i}`} aluno={a} />
          ))}
        </Card>
      ))}
    </div>
  )
}
