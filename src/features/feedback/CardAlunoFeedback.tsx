import { useId, useRef, useState } from 'react'
import { Card } from '../../components/ui'
import {
  feedbackSalvar, CORACOES, PRATICA, EVOLUCAO, ANIMO,
  type FeedbackAluno, type Coracao, type Pratica, type Evolucao, type Animo,
} from '../../lib/api'
import { CampoObservacao } from './CampoObservacao'

/** A cor do coração escolhido — usada aberto (ícone grande) e fechado (resumo). */
const COR_CORACAO: Record<string, string> = {
  verde: 'text-success-text',
  amarelo: 'text-warning-text',
  vermelho: 'text-danger-text',
}

/**
 * A linha de um aluno na mesa.
 *
 * Abre no toque do coração — independente da cor — e mostra as três perguntas
 * mais o convite de observação. Cada toque SALVA: não existe botão "Salvar".
 * Com 38 alunos e cinco campos, um botão no fim é convite a perder trabalho.
 *
 * ABRE E FECHA. Um card aberto tem ~5 campos e passa de 300px; um professor
 * com 40 alunos rolaria uma tela de 12 mil pixels se todos ficassem abertos —
 * e quem já respondeu no começo do mês abriria a mesa nesse estado. Por isso
 * o card NASCE FECHADO e o chevron manda: fechado mostra o essencial (nome,
 * o coração que ele escolheu, o ✓) e abre de novo pra corrigir.
 *
 * Fechado, quem AINDA não tem coração continua mostrando os três — a mesa
 * inteira continua a um toque de distância, sem precisar abrir card por card.
 * Quem já tem vira uma linha de resumo.
 *
 * O ✓ só aparece quando o aluno está COMPLETO (coração + as três perguntas).
 * Um card com coração e perguntas vazias fica visivelmente começado — é o que
 * o Fábio vai cobrar.
 *
 * DUAS VERDADES, DE PROPÓSITO. `estado` é o que a tela mostra (muda no toque,
 * sem esperar a rede — é o que faz "cada toque salva" parecer instantâneo);
 * `confirmado` é o que o servidor **respondeu que gravou**. O ✓ sai de
 * `confirmado`, nunca de `estado`. Antes saía de `estado`, e o resultado era o
 * pior defeito possível numa tela de coleta: com a rede ruim o professor via
 * 52 ✓ verdes, a barrinha em 0/52, e nada salvo. Um card que falhou mostra o
 * alerta e ele **vence o ✓** — inclusive quando o aluno já estava completo
 * antes e só a última mudança se perdeu.
 *
 * O toque que falhou NÃO é desfeito na tela: a escolha do professor continua
 * visível pra ele reenviar (tocando no alerta) em vez de ter que lembrar o que
 * tinha respondido.
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
  const [confirmado, setConfirmado] = useState(aluno)
  const [falhou, setFalhou] = useState(false)
  const [aberto, setAberto] = useState(false)
  const [salvando, setSalvando] = useState(false)
  const filaRef = useRef<Promise<void>>(Promise.resolve())
  const emVooRef = useRef(0)
  const detalheId = useId()

  // Sai de `confirmado`: o ✓ é recibo do servidor, não eco do toque.
  const completo =
    !!confirmado.feedback &&
    !!confirmado.pratica_em_casa &&
    !!confirmado.evolucao &&
    !!confirmado.animo

  function enviar(novo: FeedbackAluno) {
    if (!novo.feedback) return
    const feedback = novo.feedback
    setFalhou(false)
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
        .then((p) => {
          // A fila serializa as chamadas desta linha, então o último sucesso é
          // sempre o snapshot mais novo que o servidor aceitou.
          setConfirmado(novo)
          // Limpa um alerta de uma chamada ANTERIOR que falhou: se a mais nova
          // passou, o servidor está com o dado mais recente e o alerta viraria
          // mentira ao contrário (assustar sobre algo que foi salvo).
          setFalhou(false)
          aoSalvar({ total: p.total, respondidos: p.respondidos })
        })
        .catch(() => {
          setFalhou(true)
          aoFalhar('Não consegui salvar. Toca no alerta pra tentar de novo.')
        })
        .finally(() => {
          emVooRef.current -= 1
          if (emVooRef.current === 0) setSalvando(false)
        }),
    )
  }

  function salvar(mudanca: Partial<FeedbackAluno>) {
    const novo = { ...estado, ...mudanca }
    setEstado(novo)
    enviar(novo)
  }

  const coracao = CORACOES.find((c) => c.valor === estado.feedback)

  return (
    <Card className="mb-2 p-3.5">
      <div className="flex items-start justify-between gap-3">
        {/* O bloco do nome também abre e fecha: alvo grande no celular, do
            tamanho do card, em vez de exigir mira no chevron. */}
        <button
          type="button"
          onClick={() => setAberto((v) => !v)}
          aria-expanded={aberto}
          aria-controls={detalheId}
          className="min-w-0 flex-1 text-left"
        >
          <p className="truncate text-[15px] font-bold text-text-primary">{estado.nome}</p>
          <p className="text-[11.5px] text-text-muted">
            {estado.cursos ?? 'Sem curso'}
            {estado.dias_sem_aula != null
              ? ` · você não vê há ${estado.dias_sem_aula} ${estado.dias_sem_aula === 1 ? 'dia' : 'dias'}`
              : null}
          </p>
        </button>
        {salvando ? (
          <i className="fa-solid fa-circle-notch fa-spin text-text-muted" role="status" aria-label="salvando" />
        ) : falhou ? (
          // Vence o ✓ de propósito: se a última gravação não passou, o card não
          // pode se apresentar como pronto — nem quando já estava completo antes.
          <button
            type="button"
            onClick={() => enviar(estado)}
            aria-label="Não salvou. Tentar de novo"
            className="-m-1 p-1 text-danger-text"
          >
            <i className="fa-solid fa-triangle-exclamation" aria-hidden />
          </button>
        ) : completo ? (
          <i className="fa-solid fa-circle-check text-success-text" role="img" aria-label="respondido" />
        ) : null}

        <button
          type="button"
          onClick={() => setAberto((v) => !v)}
          aria-expanded={aberto}
          aria-controls={detalheId}
          aria-label={aberto ? `Fechar ${estado.nome}` : `Abrir ${estado.nome}`}
          className="-m-1 p-1 text-text-muted"
        >
          <i
            className={`fa-solid fa-chevron-down text-xs transition-transform ${aberto ? 'rotate-180' : ''}`}
            aria-hidden
          />
        </button>
      </div>

      {/* FECHADO e já com coração: uma linha de resumo no lugar dos três
          corações e das três perguntas. Sem isto, "fechado" viraria só "some
          com o que respondi" — o professor precisa reconhecer o card sem abrir. */}
      {!aberto && coracao ? (
        <button
          type="button"
          onClick={() => setAberto(true)}
          aria-label={`Abrir ${estado.nome}`}
          className="mt-2 flex w-full items-center gap-2 text-left"
        >
          <i className={`fa-solid fa-heart text-[13px] ${COR_CORACAO[coracao.valor]}`} aria-hidden />
          <span className="text-[12.5px] text-text-secondary">{coracao.rotulo}</span>
          {!completo ? (
            <span className="text-[11.5px] text-text-muted">· faltam as perguntas</span>
          ) : null}
        </button>
      ) : null}

      {/* Os três corações. Tocar em qualquer um abre o resto. */}
      {aberto || !coracao ? (
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
      ) : null}

      {aberto ? (
        <div id={detalheId} className="mt-3 space-y-3 border-t border-border-subtle pt-3">
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

          <CampoObservacao
            valor={estado.observacao ?? ''}
            aoConfirmar={(t) => salvar({ observacao: t })}
          />
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
