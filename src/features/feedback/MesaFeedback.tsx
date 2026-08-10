import { useEffect, useState } from 'react'
import { EmptyState, Skeleton } from '../../components/ui'
import { CardAlunoFeedback } from './CardAlunoFeedback'
import { feedbackMesa, type FeedbackMesa as Mesa } from '../../lib/api'

/**
 * A mesa do mês.
 *
 * Dois blocos de propósito: quem o professor viu no mês e quem ele NÃO viu.
 * Esconder quem sumiu esconderia justamente o aluno que mais importa — dias
 * desde a última aula é o sinal mais forte do modelo de evasão.
 *
 * `show` é o toast da PÁGINA (padrão de `Devolutivas.tsx`: um único
 * `useToast()` no dono, repassado por prop) — a mesa não abre um toast
 * próprio, senão duas superfícies de toast disputariam a mesma posição fixa
 * dentro do `AppFrame`.
 */
export function MesaFeedback({ show }: { show: (mensagem: string) => void }) {
  const [mesa, setMesa] = useState<Mesa | null>(null)
  const [erro, setErro] = useState(false)
  const [progresso, setProgresso] = useState({ total: 0, respondidos: 0 })

  useEffect(() => {
    feedbackMesa()
      .then((m) => {
        setMesa(m)
        setProgresso({ total: m.total, respondidos: m.respondidos })
      })
      .catch(() => setErro(true))
  }, [])

  if (erro) {
    return (
      <EmptyState
        icon="fa-solid fa-triangle-exclamation"
        title="Não consegui abrir o feedback"
        description="Recarrega a página e tenta de novo."
      />
    )
  }

  if (!mesa) {
    return (
      <div className="space-y-2">
        <Skeleton className="h-6 w-full rounded-lg" />
        <Skeleton className="h-[120px] w-full rounded-lg" />
        <Skeleton className="h-[120px] w-full rounded-lg" />
      </div>
    )
  }

  const viu = mesa.alunos.filter((a) => a.teve_aula_no_mes)
  const naoViu = mesa.alunos.filter((a) => !a.teve_aula_no_mes)
  const pct = progresso.total > 0 ? Math.round((progresso.respondidos / progresso.total) * 100) : 0

  return (
    <>
      {/* A barrinha. Conta aluno COMPLETO — coração e as três perguntas. */}
      <div className="sticky top-0 z-10 -mx-5 mb-4 bg-bg-app px-5 pb-3 pt-1">
        <div className="flex items-center gap-3">
          <div className="h-2 flex-1 overflow-hidden rounded-full bg-bg-inset">
            <div className="h-full bg-brand transition-all" style={{ width: `${pct}%` }} />
          </div>
          <span className="whitespace-nowrap text-[11.5px] text-text-muted">
            {progresso.respondidos}/{progresso.total}
          </span>
        </div>
      </div>

      {/* Não existe botão "Salvar" nesta tela, e ausência não se explica
          sozinha: sem esta linha o professor responde 38 alunos procurando
          onde confirmar — ou pior, sai achando que perdeu tudo. Fica no fluxo
          (não no sticky) porque é instrução de primeira vez: rola pra cima e
          sai da frente. Quem confirma aluno por aluno é o ✓ de cada card. */}
      {mesa.alunos.length > 0 ? (
        <>
          <p className="mb-4 flex items-center gap-2 text-[11.5px] text-text-muted">
            <i className="fa-solid fa-cloud-arrow-up text-brand-text" aria-hidden />
            Cada resposta salva sozinha — não tem botão de salvar.
          </p>
          <p className="mb-4 flex items-start gap-2 text-[11.5px] leading-relaxed text-text-muted">
            <i className="fa-solid fa-shield-halved mt-0.5 text-brand-text" aria-hidden />
            <span>
              Isto não é avaliação sua. O que você marcar aqui não vira número sobre
              você — serve pra coordenação chegar no aluno sabendo do que falar.
            </span>
          </p>
        </>
      ) : null}

      {mesa.alunos.length === 0 ? (
        <EmptyState
          icon="fa-solid fa-user-group"
          title="Sua carteira está vazia"
          description="Quando você tiver alunos, eles aparecem aqui."
        />
      ) : (
        <>
          {viu.length > 0 ? (
            <Bloco titulo="Você deu aula pra esses" icone="fa-solid fa-chalkboard-user">
              {viu.map((a) => (
                <CardAlunoFeedback
                  key={a.aluno_id}
                  aluno={a}
                  aoSalvar={(p) => setProgresso((atual) => progressoSeguro(atual, p))}
                  aoFalhar={show}
                />
              ))}
            </Bloco>
          ) : null}

          {naoViu.length > 0 ? (
            <Bloco titulo="Esses você não viu este mês" icone="fa-solid fa-user-clock">
              {naoViu.map((a) => (
                <CardAlunoFeedback
                  key={a.aluno_id}
                  aluno={a}
                  aoSalvar={(p) => setProgresso((atual) => progressoSeguro(atual, p))}
                  aoFalhar={show}
                />
              ))}
            </Bloco>
          ) : null}
        </>
      )}
    </>
  )
}

/**
 * `respondidos` só cresce nesta tela — não existe "desmarcar" um campo já
 * respondido. A fila de `CardAlunoFeedback` serializa por LINHA, não pela
 * mesa inteira: duas linhas diferentes ainda podem responder fora de ordem
 * entre si, e cada resposta carrega uma contagem GLOBAL recém-lida no banco
 * (074, `app_professor_feedback_progresso`). Sem este guard, uma resposta
 * atrasada de uma linha podia fazer a barrinha recuar na frente do professor.
 */
function progressoSeguro(
  atual: { total: number; respondidos: number },
  novo: { total: number; respondidos: number },
): { total: number; respondidos: number } {
  return novo.respondidos < atual.respondidos ? atual : novo
}

function Bloco({
  titulo,
  icone,
  children,
}: {
  titulo: string
  icone: string
  children: React.ReactNode
}) {
  return (
    <section className="mb-6">
      <span className="mb-3 flex items-center gap-2 text-[13px] font-bold uppercase tracking-[.5px] text-text-secondary">
        <i className={`${icone} text-xs text-brand-text`} aria-hidden />
        {titulo}
      </span>
      {children}
    </section>
  )
}
