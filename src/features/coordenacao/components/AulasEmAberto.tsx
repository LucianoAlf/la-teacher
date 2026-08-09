import { useEffect, useState } from 'react'
import { Skeleton } from '../../../components/ui'
import { formatDiaCurto, formatHoraBRT } from '../../../lib/date'
import { coordenacaoProfessorDetalhe, type CoordenacaoDetalhe } from '../../../lib/api'
import type { FiltroPainel } from './FiltrosPainel'

/**
 * O que exatamente está em aberto de um professor (070).
 *
 * Existe porque a coordenação cobrava às cegas: a fila dizia "21 aulas" e a
 * primeira pergunta de quem vai ligar é "quais?". Sem isso, o botão Cobrar era
 * o único verbo da tela.
 *
 * Agrupado por DIA, mais antigo primeiro, porque é assim que o professor
 * resolve — ele senta e lança o dia inteiro. Uma lista corrida de 21 aulas não
 * diz por onde começar.
 *
 * Carrega SÓ ao abrir: são 38 professores na fila e ninguém abre os 38.
 */
export function AulasEmAberto({
  professorId,
  filtro,
}: {
  professorId: number
  filtro: FiltroPainel
}) {
  const [detalhe, setDetalhe] = useState<CoordenacaoDetalhe | null>(null)
  const [erro, setErro] = useState(false)

  useEffect(() => {
    let vivo = true
    // Os mesmos filtros da fila: o selo da linha e esta lista contam a mesma
    // coisa, então têm que ver o mesmo recorte.
    coordenacaoProfessorDetalhe(professorId, 7, filtro.unidadeId, filtro.curso)
      .then((d) => vivo && setDetalhe(d))
      .catch(() => vivo && setErro(true))
    return () => {
      vivo = false
    }
  }, [professorId, filtro.unidadeId, filtro.curso])

  if (erro) {
    return (
      <p className="px-3.5 py-3 text-[12.5px] text-text-secondary">
        Não consegui abrir o detalhe. Fecha e abre de novo.
      </p>
    )
  }

  if (!detalhe) {
    return (
      <div className="space-y-2 px-3.5 py-3">
        <Skeleton className="h-4 w-40" />
        <Skeleton className="h-4 w-full" />
        <Skeleton className="h-4 w-2/3" />
      </div>
    )
  }

  return (
    <div className="bg-bg-inset px-3.5 py-3">
      {detalhe.dias.map((dia) => (
        <div key={dia.data_aula} className="mb-3 last:mb-0">
          <div className="mb-1 flex flex-wrap items-baseline gap-x-2">
            <span className="text-[11px] font-bold uppercase tracking-[.5px] text-text-secondary">
              {formatDiaCurto(dia.data_aula)}
            </span>
            <span className="text-[11.5px] text-text-muted">
              {dia.aulas === 1 ? '1 aula' : `${dia.aulas} aulas`} · parado há{' '}
              {dia.dias_em_atraso === 1 ? '1 dia' : `${dia.dias_em_atraso} dias`}
            </span>
          </div>

          {dia.itens.map((aula) => (
            <div
              key={aula.aula_id}
              className="flex items-baseline gap-3 border-b border-border-subtle py-[5px] last:border-b-0"
            >
              {/* Coluna mono da hora — a mesma do AulaRow na agenda do professor. */}
              <span className="w-10 flex-none font-mono text-[12px] font-semibold text-text-secondary">
                {formatHoraBRT(aula.hora)}
              </span>
              <span className="min-w-0 flex-1 truncate text-[13px] text-text-primary">
                {aula.curso_nome ?? 'Aula'}
                {aula.turma_nome ? (
                  <span className="text-text-secondary"> · {aula.turma_nome}</span>
                ) : null}
                {/* O selo da linha diz "N no Emusys"; é aqui que se vê QUAIS —
                    a coordenação precisa saber o que é falta e o que é
                    migração antes de qualquer conversa. */}
                {aula.no_emusys ? (
                  <span className="ml-2 inline-flex items-center gap-1 text-[11px] text-info-text">
                    <i className="fa-solid fa-right-left text-[9px]" aria-hidden />
                    no Emusys
                  </span>
                ) : null}
              </span>
              {/* Quem está esperando. Turma mostra os nomes: "aula de 5" sem
                  nome nenhum é o tipo de linha que a coordenação não consegue
                  usar numa conversa. */}
              <span className="min-w-0 max-w-[45%] truncate text-[12px] text-text-secondary">
                {aula.alunos_nomes ?? '—'}
              </span>
            </div>
          ))}
        </div>
      ))}
    </div>
  )
}
