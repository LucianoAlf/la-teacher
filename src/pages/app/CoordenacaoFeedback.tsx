import { useCallback, useEffect, useState } from 'react'
import { CoordenacaoFrame } from './CoordenacaoFrame'
import { EmptyState, Select, Skeleton, type OpcaoSelect } from '../../components/ui'
import { PainelNumero } from '../../features/coordenacao/components/PainelNumero'
import { LinhaSemaforo } from '../../features/coordenacao/components/LinhaSemaforo'
import { coordenacaoFeedbackMes, type CoordenacaoFeedbackMes } from '../../lib/api'

/**
 * Painel da coordenação — bloco 2: o semáforo do mês.
 *
 * POR QUE ESTA TELA EXISTE. O campo de observação da mesa do professor convida
 * assim: "Algo que vale a coordenação saber". Até a 077 esse texto não era lido
 * por NINGUÉM — nem aqui, nem no LA Report. A coordenação via só cumprimento
 * (quem respondeu) e o coração diluído em 20% do health_score. Pedir que alguém
 * escreva pra um leitor que não existe gasta o tempo dele e ensina que o app
 * não serve pra nada.
 *
 * A tela mostra o RESUMO e SÓ quem precisa de olho — a RPC decide (vermelho,
 * amarelo, ou qualquer coração com recado escrito). Verde calado não vem: é o
 * caso em que não há o que fazer, e listar a escola inteira é a mesma parede de
 * texto que já deixou o escalonamento diário ilegível.
 *
 * Compõe, não estiliza (`docs/frontend-tokens.md`): mesma moldura, mesmos KPIs
 * e o mesmo Select do bloco 1.
 */
export default function CoordenacaoFeedbackPage() {
  const [dados, setDados] = useState<CoordenacaoFeedbackMes | null>(null)
  const [erro, setErro] = useState<string | null>(null)
  const [unidade, setUnidade] = useState<string | null>(null)

  const carregar = useCallback(() => {
    setErro(null)
    coordenacaoFeedbackMes(unidade)
      .then(setDados)
      .catch((e: unknown) => {
        const msg = String((e as { message?: string })?.message ?? e)
        setErro(
          msg.includes('apenas_admin')
            ? 'Essa área é da coordenação.'
            : 'Não consegui carregar o semáforo agora.',
        )
      })
  }, [unidade])

  useEffect(carregar, [carregar])

  const r = dados?.resumo
  const carregando = !dados
  const unidades: OpcaoSelect[] = [
    { valor: '', rotulo: 'Todas as unidades' },
    ...(dados?.filtros.unidades ?? []).map((u) => ({
      valor: u.unidade_id,
      rotulo: u.nome,
      sufixo: u.alunos,
    })),
  ]

  return (
    <CoordenacaoFrame titulo="Feedback do mês" icone="fa-solid fa-heart-pulse">
      <div className="px-5 pb-5 pt-3">
        {erro ? (
          <EmptyState
            icon="fa-solid fa-triangle-exclamation"
            title={erro}
            description="Recarrega a página e tenta de novo."
          />
        ) : (
          <>
            <div className="mb-6 grid grid-cols-2 gap-2.5 md:grid-cols-4">
              {/* Crítico primeiro: a faixa tem que dizer por onde começar, não
                  virar placar. */}
              <PainelNumero
                rotulo="Crítico"
                valor={r?.vermelho}
                tom="perigo"
                carregando={carregando}
              />
              <PainelNumero
                rotulo="Atenção"
                valor={r?.amarelo}
                tom="atencao"
                carregando={carregando}
              />
              <PainelNumero rotulo="Com recado do professor" valor={r?.com_recado} carregando={carregando} />
              <PainelNumero
                rotulo="Respondidos"
                valor={r?.respondidos}
                sufixo={r ? ` de ${r.alunos}` : undefined}
                carregando={carregando}
              />
            </div>

            <div className="mb-6 flex flex-wrap items-center gap-2">
              <span className="flex items-center gap-2 text-[11px] font-bold uppercase tracking-[.5px] text-text-secondary">
                <i className="fa-solid fa-filter text-[10px] text-brand-text" aria-hidden />
                Filtrar
              </span>
              <Select
                opcoes={unidades}
                valor={unidade ?? ''}
                aoEscolher={(v) => setUnidade(v === '' ? null : String(v))}
                rotuloAcessivel="Filtrar por unidade"
                size="sm"
              />
            </div>

            {carregando ? (
              <div className="space-y-2">
                <Skeleton className="h-[92px] w-full rounded-lg" />
                <Skeleton className="h-[92px] w-full rounded-lg" />
              </div>
            ) : dados.alunos.length === 0 ? (
              // Duas ausências MUITO diferentes: ninguém respondeu ainda, ou
              // respondeu e está tudo verde. Um texto só pra ambas faria a
              // coordenação achar que está tudo bem no mês em que ninguém
              // respondeu.
              <EmptyState
                icon={r && r.respondidos > 0 ? 'fa-solid fa-heart' : 'fa-regular fa-clock'}
                title={
                  r && r.respondidos > 0
                    ? 'Nenhum aluno precisando de olho'
                    : 'Os professores ainda não responderam'
                }
                description={
                  r && r.respondidos > 0
                    ? 'Quem está em atenção, crítico ou com recado do professor aparece aqui.'
                    : `A janela do mês ${dados.janela_aberta ? 'está aberta' : 'abre na última semana'} — a cobrança do Fábio sai na régua.`
                }
              />
            ) : (
              <>
                <span className="mb-3 flex items-center gap-2 text-[13px] font-bold uppercase tracking-[.5px] text-text-secondary">
                  <i className="fa-solid fa-user-group text-xs text-brand-text" aria-hidden />
                  Precisam de olho
                </span>
                {dados.alunos.map((a) => (
                  <LinhaSemaforo key={`${a.aluno_id}-${a.professor_id}`} aluno={a} />
                ))}
                {/* Corte que se anuncia — a RPC devolve no máximo 200. */}
                {dados.truncado ? (
                  <p className="mt-3 text-[11.5px] text-text-muted">
                    Mostrando {dados.alunos.length} de {dados.precisam_de_olho}. Filtra por
                    unidade pra ver o resto.
                  </p>
                ) : null}
              </>
            )}
          </>
        )}
      </div>
    </CoordenacaoFrame>
  )
}
