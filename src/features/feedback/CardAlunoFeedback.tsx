import { useRef, useState } from 'react'
import { Card } from '../../components/ui'
import {
  feedbackSalvar, CORACOES, PRATICA, EVOLUCAO, ANIMO,
  type FeedbackAluno, type Coracao, type Pratica, type Evolucao, type Animo,
} from '../../lib/api'

/**
 * A linha de um aluno na mesa.
 *
 * Abre no toque do coração — independente da cor — e mostra as três perguntas
 * mais o convite de observação. Cada toque SALVA: não existe botão "Salvar".
 * Com 38 alunos e cinco campos, um botão no fim é convite a perder trabalho.
 *
 * O ✓ só aparece quando o aluno está COMPLETO (coração + as três perguntas).
 * Um card com coração e perguntas vazias fica visivelmente começado — é o que
 * o Fábio vai cobrar.
 *
 * `salvar()` manda o SNAPSHOT LOCAL inteiro (os 5 campos) — o `on conflict do
 * update` da 074 sobrescreve a linha inteira, sem coalesce (`observacao`
 * precisa poder ser apagada, e coalesce tornaria isso impossível). Os botões
 * continuam clicáveis durante o salvamento de propósito — travar a UI
 * contrariaria o "cada toque salva" — então dois toques rápidos disparam duas
 * chamadas. Sem serialização, a resposta mais velha podia chegar por último e
 * sobrescrever o campo mais novo (perda silenciosa). `filaRef` encadeia as
 * chamadas desta LINHA: a próxima só sai depois que a anterior respondeu, e
 * o `.catch` interno garante que o elo nunca rejeita — se rejeitasse, a fila
 * travaria pra sempre pros próximos toques.
 */
export function CardAlunoFeedback({
  aluno,
  aoSalvar,
  aoFalhar,
}: {
  aluno: FeedbackAluno
  aoSalvar: (progresso: { total: number; respondidos: number }) => void
  aoFalhar: (mensagem: string) => void
}) {
  const [estado, setEstado] = useState(aluno)
  const [aberto, setAberto] = useState(false)
  const [salvando, setSalvando] = useState(false)
  const filaRef = useRef<Promise<void>>(Promise.resolve())
  const emVooRef = useRef(0)

  const completo =
    !!estado.feedback && !!estado.pratica_em_casa && !!estado.evolucao && !!estado.animo

  function salvar(mudanca: Partial<FeedbackAluno>) {
    const novo = { ...estado, ...mudanca }
    setEstado(novo)
    if (!novo.feedback) return
    const feedback = novo.feedback
    setSalvando(true)
    emVooRef.current += 1
    filaRef.current = filaRef.current.then(() =>
      feedbackSalvar({
        alunoId: novo.aluno_id,
        feedback,
        praticaEmCasa: novo.pratica_em_casa,
        evolucao: novo.evolucao,
        animo: novo.animo,
        observacao: novo.observacao,
      })
        .then((p) => aoSalvar({ total: p.total, respondidos: p.respondidos }))
        .catch(() => aoFalhar('Não consegui salvar. Toca de novo.'))
        .finally(() => {
          emVooRef.current -= 1
          if (emVooRef.current === 0) setSalvando(false)
        }),
    )
  }

  return (
    <Card className="mb-2 p-3.5">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="truncate text-[15px] font-bold text-text-primary">{estado.nome}</p>
          <p className="text-[11.5px] text-text-muted">
            {estado.cursos ?? 'Sem curso'}
            {estado.dias_sem_aula != null
              ? ` · você não vê há ${estado.dias_sem_aula} ${estado.dias_sem_aula === 1 ? 'dia' : 'dias'}`
              : null}
          </p>
        </div>
        {completo ? (
          <i className="fa-solid fa-circle-check text-success-text" role="img" aria-label="respondido" />
        ) : salvando ? (
          <i className="fa-solid fa-circle-notch fa-spin text-text-muted" role="status" aria-label="salvando" />
        ) : null}
      </div>

      {/* Os três corações. Tocar em qualquer um abre o resto. */}
      <div className="mt-3 flex items-center gap-2">
        {CORACOES.map((c) => (
          <button
            key={c.valor}
            type="button"
            onClick={() => {
              setAberto(true)
              salvar({ feedback: c.valor as Coracao })
            }}
            aria-pressed={estado.feedback === c.valor}
            className={`flex flex-1 flex-col items-center gap-1 rounded-xl border py-2 transition-colors ${
              estado.feedback === c.valor
                ? 'border-transparent bg-bg-inset'
                : 'border-border-subtle'
            }`}
          >
            <i
              className={`fa-heart text-lg ${
                estado.feedback === c.valor ? 'fa-solid' : 'fa-regular text-text-muted'
              } ${
                estado.feedback === c.valor && c.valor === 'verde' ? 'text-success-text' : ''
              } ${
                estado.feedback === c.valor && c.valor === 'amarelo' ? 'text-warning-text' : ''
              } ${
                estado.feedback === c.valor && c.valor === 'vermelho' ? 'text-danger-text' : ''
              }`}
              aria-hidden
            />
            <span className="text-[11px] font-bold uppercase tracking-[.5px] text-text-secondary">
              {c.rotulo}
            </span>
          </button>
        ))}
      </div>

      {aberto || estado.feedback ? (
        <div className="mt-3 space-y-3 border-t border-border-subtle pt-3">
          <Pergunta
            rotulo="Prática em casa?"
            opcoes={PRATICA}
            valor={estado.pratica_em_casa}
            aoEscolher={(v) => salvar({ pratica_em_casa: v as Pratica })}
          />
          <Pergunta
            rotulo="Está evoluindo?"
            opcoes={EVOLUCAO}
            valor={estado.evolucao}
            aoEscolher={(v) => salvar({ evolucao: v as Evolucao })}
          />
          <Pergunta
            rotulo="Como está o ânimo?"
            opcoes={ANIMO}
            valor={estado.animo}
            aoEscolher={(v) => salvar({ animo: v as Animo })}
          />

          <div>
            <span className="mb-1 block text-[11px] font-bold uppercase tracking-[.5px] text-text-secondary">
              Observação
            </span>
            <textarea
              rows={2}
              defaultValue={estado.observacao ?? ''}
              onBlur={(e) => salvar({ observacao: e.target.value })}
              placeholder="Algo que vale a coordenação saber — um elogio, um ponto de melhoria, uma mudança que você notou."
              className="w-full resize-none rounded-lg border border-border-subtle bg-bg-inset px-3 py-2 text-[13px] text-text-primary placeholder:text-text-muted"
            />
          </div>
        </div>
      ) : null}
    </Card>
  )
}

/** Uma pergunta de três chips. O rótulo usa a receita de rótulo do DS. */
function Pergunta({
  rotulo,
  opcoes,
  valor,
  aoEscolher,
}: {
  rotulo: string
  opcoes: { valor: string; rotulo: string }[]
  valor: string | null
  aoEscolher: (v: string) => void
}) {
  return (
    <div>
      <span className="mb-1 block text-[11px] font-bold uppercase tracking-[.5px] text-text-secondary">
        {rotulo}
      </span>
      <div className="flex gap-2">
        {opcoes.map((o) => (
          <button
            key={o.valor}
            type="button"
            onClick={() => aoEscolher(o.valor)}
            aria-pressed={valor === o.valor}
            className={`flex-1 rounded-lg border px-2 py-1.5 text-[12.5px] transition-colors ${
              valor === o.valor
                ? 'border-transparent bg-brand text-on-brand'
                : 'border-border-subtle text-text-secondary'
            }`}
          >
            {o.rotulo}
          </button>
        ))}
      </div>
    </div>
  )
}
