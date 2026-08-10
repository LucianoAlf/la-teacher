import { useCallback, useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { CoordenacaoFrame } from './CoordenacaoFrame'
import { EmptyState, Skeleton } from '../../components/ui'
import { PainelNumero } from '../../features/coordenacao/components/PainelNumero'
import { LinhaSemaforo } from '../../features/coordenacao/components/LinhaSemaforo'
import { FiltrosSemaforo } from '../../features/coordenacao/components/FiltrosSemaforo'
import {
  coordenacaoFeedbackMes,
  SEM_FILTRO_SEMAFORO,
  type CoordenacaoFeedbackMes,
  type FiltroSemaforo,
} from '../../lib/api'

/** O título da lista tem que dizer o que ela É — o filtro muda a regra, não só o recorte. */
const TITULO_LISTA: Record<string, string> = {
  vermelho: 'Alunos em crítico',
  amarelo: 'Alunos em atenção',
  verde: 'Alunos saudáveis',
  sem_resposta: 'Sem resposta do professor',
}

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
 * Por padrão a tela mostra o RESUMO e SÓ quem precisa de olho — a RPC decide
 * (vermelho, amarelo, ou qualquer coração com recado escrito). Verde calado não
 * vem: é o caso em que não há o que fazer, e listar a escola inteira é a mesma
 * parede de texto que já deixou o escalonamento diário ilegível.
 *
 * Escolher um coração no filtro TROCA essa regra pela do grupo inteiro (079) —
 * e o título da lista troca junto, senão a tela mostraria os saudáveis embaixo
 * de "Precisam de olho".
 *
 * Compõe, não estiliza (`docs/frontend-tokens.md`): mesma moldura, mesmos KPIs
 * e os mesmos Selects do bloco 1.
 */
export default function CoordenacaoFeedbackPage() {
  const nav = useNavigate()
  const [dados, setDados] = useState<CoordenacaoFeedbackMes | null>(null)
  const [erro, setErro] = useState<string | null>(null)
  const [filtro, setFiltro] = useState<FiltroSemaforo>(SEM_FILTRO_SEMAFORO)

  const carregar = useCallback(() => {
    setErro(null)
    coordenacaoFeedbackMes(filtro)
      .then(setDados)
      .catch((e: unknown) => {
        const msg = String((e as { message?: string })?.message ?? e)
        setErro(
          msg.includes('apenas_admin')
            ? 'Essa área é da coordenação.'
            : 'Não consegui carregar o semáforo agora.',
        )
      })
  }, [filtro])

  useEffect(carregar, [carregar])

  const r = dados?.resumo
  // Ao trocar o filtro os dados antigos ficam na tela até a resposta nova
  // chegar — zerar aqui faria a lista piscar em branco a cada escolha (mesma
  // decisão do bloco 1).
  const carregando = !dados
  const titulo = filtro.coracao ? TITULO_LISTA[filtro.coracao] : 'Precisam de olho'

  return (
    <CoordenacaoFrame
      titulo="Feedback do mês"
      icone="fa-solid fa-heart-pulse"
      aoVoltar={() => nav('/app/coordenacao/radar')}
    >
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
              <PainelNumero
                rotulo="Com recado do professor"
                valor={r?.com_recado}
                carregando={carregando}
              />
              <PainelNumero
                rotulo="Respondidos"
                valor={r?.respondidos}
                sufixo={r ? ` de ${r.alunos}` : undefined}
                carregando={carregando}
              />
            </div>

            <FiltrosSemaforo
              opcoes={dados?.filtros ?? null}
              filtro={filtro}
              aoMudar={setFiltro}
            />

            {carregando ? (
              <div className="space-y-2">
                <Skeleton className="h-[92px] w-full rounded-lg" />
                <Skeleton className="h-[92px] w-full rounded-lg" />
              </div>
            ) : dados.alunos.length === 0 ? (
              // Três ausências MUITO diferentes: o filtro não achou ninguém,
              // ninguém respondeu ainda, ou respondeu e está tudo tranquilo. Um
              // texto só pras três faria a coordenação achar que está tudo bem
              // no mês em que ninguém respondeu.
              <EmptyState
                icon={
                  filtro.coracao || filtro.unidadeId || filtro.professorId != null
                    ? 'fa-solid fa-filter-circle-xmark'
                    : r && r.respondidos > 0
                      ? 'fa-solid fa-heart'
                      : 'fa-regular fa-clock'
                }
                title={
                  filtro.coracao || filtro.unidadeId || filtro.professorId != null
                    ? 'Ninguém neste recorte'
                    : r && r.respondidos > 0
                      ? 'Nenhum aluno precisando de olho'
                      : 'Os professores ainda não responderam'
                }
                description={
                  filtro.coracao || filtro.unidadeId || filtro.professorId != null
                    ? 'Tenta afrouxar um dos filtros acima.'
                    : r && r.respondidos > 0
                      ? 'Quem está em atenção, crítico ou com recado do professor aparece aqui.'
                      : `A janela do mês ${dados.janela_aberta ? 'está aberta' : 'abre na última semana'} — a cobrança do Fábio sai na régua.`
                }
              />
            ) : (
              <>
                <span className="mb-3 flex items-center gap-2 text-[13px] font-bold uppercase tracking-[.5px] text-text-secondary">
                  <i className="fa-solid fa-user-group text-xs text-brand-text" aria-hidden />
                  {titulo}
                  <span className="font-normal normal-case tracking-normal text-text-muted">
                    {dados.total_lista}
                  </span>
                </span>
                {dados.alunos.map((a) => (
                  <LinhaSemaforo key={`${a.aluno_id}-${a.professor_id}`} aluno={a} />
                ))}
                {/* Corte que se anuncia — a RPC devolve no máximo 200. */}
                {dados.truncado ? (
                  <p className="mt-3 text-[11.5px] text-text-muted">
                    Mostrando {dados.alunos.length} de {dados.total_lista}. Usa os filtros pra
                    ver o resto.
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
