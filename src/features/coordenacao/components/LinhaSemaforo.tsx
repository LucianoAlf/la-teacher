import { Card } from '../../../components/ui'
import type { CoordenacaoFeedbackAluno } from '../../../lib/api'

const COR: Record<string, string> = {
  verde: 'text-success-text',
  amarelo: 'text-warning-text',
  vermelho: 'text-danger-text',
}

const ROTULO: Record<string, string> = {
  verde: 'Saudável',
  amarelo: 'Atenção',
  vermelho: 'Crítico',
}

/** "não" vira "não pratica" — chip solto não diz de que pergunta veio. */
export const FRASE_SEMAFORO: Record<string, string> = {
  sim: 'pratica em casa',
  as_vezes: 'pratica às vezes',
  nao: 'não pratica',
  evoluindo: 'evoluindo',
  parado: 'parado',
  regredindo: 'regredindo',
  animado: 'animado',
  neutro: 'ânimo neutro',
  desanimado: 'desanimado',
}

/** @deprecated use FRASE_SEMAFORO — mantido pra não quebrar imports locais. */
const FRASE = FRASE_SEMAFORO

/**
 * Um aluno na lista do semáforo, do lado da COORDENAÇÃO.
 *
 * O que manda na hierarquia é a OBSERVAÇÃO, não o coração. O coração já existia
 * de outro jeito (vale 20% do `health_score` desde sempre); o texto do professor
 * é o que nunca teve leitor — e é a única parte que não dá pra reduzir a um
 * número. Por isso ele vem em bloco, com aspas e sem corte: quem escreveu
 * escreveu pra ser lido inteiro.
 *
 * O nome do PROFESSOR aparece junto porque a ação da coordenação é falar com
 * ele, não com o aluno. Sem isso a lista vira uma lista de nomes soltos e
 * alguém tem que ir procurar de quem é cada um.
 */
export function LinhaSemaforo({ aluno }: { aluno: CoordenacaoFeedbackAluno }) {
  const cor = aluno.feedback ? COR[aluno.feedback] : 'text-text-muted'
  const respostas = [aluno.pratica_em_casa, aluno.evolucao, aluno.animo]
    .filter(Boolean)
    .map((v) => FRASE[v as string] ?? v)
    .join(' · ')

  return (
    <Card className="mb-2 p-3.5">
      <div className="flex items-start gap-3">
        <i className={`fa-solid fa-heart mt-0.5 text-[15px] ${cor}`} aria-hidden />
        <div className="min-w-0 flex-1">
          <p className="text-[15px] font-bold text-text-primary">{aluno.aluno_nome}</p>
          <p className="text-[11.5px] text-text-muted">
            {[aluno.cursos, aluno.unidade_nome].filter(Boolean).join(' · ')}
            {aluno.professor_nome ? ` · com ${aluno.professor_nome}` : null}
          </p>
        </div>
        {aluno.feedback ? (
          <span className={`whitespace-nowrap text-[11px] font-bold uppercase tracking-[.5px] ${cor}`}>
            {ROTULO[aluno.feedback]}
          </span>
        ) : null}
      </div>

      {respostas ? <p className="mt-2 text-[12.5px] text-text-secondary">{respostas}</p> : null}

      {aluno.observacao ? (
        // Barra à esquerda, não um card dentro do card: é citação do professor,
        // e a cor da marca marca que ali tem texto humano no meio dos rótulos.
        <p className="mt-2 border-l-2 border-brand pl-3 text-[13px] italic text-text-primary">
          “{aluno.observacao}”
        </p>
      ) : null}
    </Card>
  )
}
