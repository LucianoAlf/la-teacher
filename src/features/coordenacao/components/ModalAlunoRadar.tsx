import { useEffect, type ReactNode } from 'react'
import { createPortal } from 'react-dom'
import { Link } from 'react-router-dom'
import type { RadarLinha, RadarResposta } from '../../../lib/api'
import { dataDoDia } from '../../../lib/datas'
import {
  COR_CORACAO,
  COR_STATUS,
  FUNDO_STATUS,
  ROTULO_STATUS,
  corDaBarra,
  motivoSemDado,
  pct,
  rotuloSinal,
  statusDoScore,
  valorSinal,
} from '../sinaisRadar'
import { FRASE_SEMAFORO } from './LinhaSemaforo'

/**
 * Card do aluno no Radar — a nota ABERTA, com a base declarada.
 *
 * Três coisas que a primeira versão errou, e por que cada conserto é assim:
 *
 * 1. **Ficava debaixo da TabBar.** Era `z-40`, o mesmo da TabBar do celular, e
 *    empate no z-index se decide por ordem no DOM — a barra vinha depois e
 *    comia o rodapé do card (o "ver o mês inteiro" simplesmente não existia no
 *    celular). Agora vai em `createPortal` pro `<body>`, fora do `<main>` que
 *    rola, com `z-50`.
 * 2. **Mostrava chave de banco.** `absenteismo`, `pratica`,
 *    `2 falta(s) seguida(s)`, `verde`. O vocabulário virou `../sinaisRadar` e a
 *    tela só consome.
 * 3. **Era uma pilha de linhas iguais.** A nota é o assunto do card, então ela
 *    tem tamanho de manchete e cada sinal ganha barra: quanto ele PODIA valer
 *    (peso efetivo) e quanto trouxe. Sem a barra, "contribuiu 13.3 de 26.7" é
 *    aritmética que o leitor tem que fazer de cabeça.
 *
 * No celular é folha de baixo (nasce colada no rodapé, cantos de cima
 * arredondados, `safe-area` no pé); no desktop, diálogo centrado. Mesmo
 * conteúdo, esqueleto diferente — a regra do `CoordenacaoFrame` × `AppFrame`
 * valendo dentro do card.
 */
export function ModalAlunoRadar({
  linha,
  medias,
  config,
  baseDesde,
  aoFechar,
}: {
  linha: RadarLinha
  medias: RadarResposta['medias']
  config: Record<string, number>
  baseDesde: string | null
  aoFechar: () => void
}) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') aoFechar()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [aoFechar])

  const mediaProf =
    linha.professor_id == null
      ? null
      : (medias.professores.find((p) => p.professor_id === linha.professor_id)
          ?.absenteismo_media ?? null)
  const mediaUni =
    medias.unidades.find((u) => u.unidade === linha.unidade)?.absenteismo_media ?? null

  const respostas = [linha.pratica_em_casa, linha.evolucao, linha.animo]
    .filter(Boolean)
    .map((v) => FRASE_SEMAFORO[v as string] ?? v)
    .join(' · ')

  const desde = dataDoDia(baseDesde)

  return createPortal(
    <div
      className="fixed inset-0 z-50 flex items-end justify-center bg-black/50 md:items-center md:p-4"
      onClick={aoFechar}
      role="presentation"
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-label={linha.aluno}
        onClick={(e) => e.stopPropagation()}
        className="flex max-h-[92svh] w-full flex-col overflow-hidden rounded-t-xl border border-border-subtle bg-bg-surface shadow-card md:max-h-[86svh] md:max-w-[520px] md:rounded-xl"
      >
        {/* ── Cabeçalho: quem é, com quem, em que estado ─────────────────── */}
        <header className="flex shrink-0 items-start gap-3 border-b border-border-subtle px-5 pb-3.5 pt-4">
          <div className="min-w-0 flex-1">
            <p className="text-[17px] font-extrabold leading-tight tracking-[-.3px] text-text-primary">
              {linha.aluno}
            </p>
            <p className="mt-0.5 text-[12.5px] leading-snug text-text-muted">
              {[linha.curso, linha.unidade].filter(Boolean).join(' · ')}
              {linha.professor ? (
                <>
                  {' · com '}
                  <span className="text-text-secondary">{linha.professor}</span>
                </>
              ) : null}
            </p>
            {linha.avisou_que_sai ? (
              <span className="mt-2 inline-flex items-center gap-1.5 rounded-full bg-warning-soft px-2 py-0.5 text-[10.5px] font-bold uppercase tracking-[.5px] text-warning-text">
                <i className="fa-solid fa-door-open text-[10px]" aria-hidden />
                avisou que sai
                {linha.mes_saida ? ` · ${linha.mes_saida}` : ''}
              </span>
            ) : null}
          </div>
          {/* 36px de alvo: no celular isto é dedo, não ponteiro. */}
          <button
            type="button"
            onClick={aoFechar}
            aria-label="Fechar"
            className="-mr-1.5 -mt-1 flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-text-muted hover:bg-bg-hover hover:text-text-secondary"
          >
            <i className="fa-solid fa-xmark text-[15px]" aria-hidden />
          </button>
        </header>

        {/* ── Miolo: só ele rola ─────────────────────────────────────────── */}
        <div className="min-h-0 flex-1 overflow-y-auto px-5 py-4">
          {/* A nota como manchete: número grande no selo da própria faixa, e do
              lado o que ela significa — inclusive quando ela se cala. */}
          <div className="flex items-center gap-4">
            <div
              className={`flex h-[68px] w-[68px] shrink-0 items-center justify-center rounded-lg ${FUNDO_STATUS[linha.status]}`}
            >
              <span
                className={`text-[30px] font-extrabold leading-none tracking-[-1px] ${COR_STATUS[linha.status]}`}
              >
                {linha.nota.nota ?? '—'}
              </span>
            </div>
            <div className="min-w-0">
              <p className="text-[11px] font-bold uppercase tracking-[.5px] text-text-secondary">
                Health score
              </p>
              <p
                className={`text-[15px] font-extrabold leading-tight ${COR_STATUS[linha.status]}`}
              >
                {ROTULO_STATUS[linha.status]}
              </p>
              <p className="mt-1 text-[11.5px] leading-snug text-text-muted">
                {linha.nota.sinais_apurados} de {linha.nota.sinais_totais} sinais apurados
                {linha.nota.suficiente
                  ? ` · crítico abaixo de ${config.faixa_critico ?? 40}, saudável de ${config.faixa_saudavel ?? 70}`
                  : ''}
              </p>
            </div>
          </div>

          {!linha.nota.suficiente ? (
            // Não é erro nem "aguarde": é a nota se recusando a dar uma resposta
            // que ela não tem. Dizer isso em uma frase evita a leitura de que o
            // aluno está bem.
            <p className="mt-3 flex gap-2 rounded-md bg-bg-inset px-3 py-2 text-[12px] leading-snug text-text-secondary">
              <i className="fa-solid fa-circle-info mt-0.5 text-[11px] text-text-muted" aria-hidden />
              <span>
                Sinais insuficientes pra fechar nota — a decomposição abaixo mostra o que já
                existe, sem virar média.
              </span>
            </p>
          ) : null}

          <Secao titulo="De onde vem a nota">
            <ul className="space-y-3">
              {linha.nota.decomposicao.map((d) => (
                <SinalDaNota key={d.sinal} d={d} linha={linha} config={config} />
              ))}
            </ul>
          </Secao>

          <Secao titulo="Absenteísmo">
            <div className="grid grid-cols-3 gap-2">
              <Comparativo rotulo="Aluno" valor={pct(linha.absenteismo_pct)} destaque />
              <Comparativo rotulo="Professor" valor={pct(mediaProf)} />
              <Comparativo rotulo="Unidade" valor={pct(mediaUni)} />
            </div>
            <p className="mt-2.5 text-[12px] leading-snug text-text-muted">
              {/* Zero de zero não é "0 faltas": é janela vazia, e a taxa do aluno
                  aparece como "—" justamente por isso (migration 081). */}
              {linha.aulas_medidas === 0
                ? 'Nenhuma aula medida nesta janela'
                : `${linha.faltas_janela === 1 ? '1 falta' : `${linha.faltas_janela} faltas`} em ${
                    linha.aulas_medidas
                  } ${linha.aulas_medidas === 1 ? 'aula medida' : 'aulas medidas'}`}
              {baseDesde ? ` · desde ${desde}` : ''}
            </p>
          </Secao>

          <Secao titulo="Semáforo do mês">
            <div className="flex items-start gap-3">
              <i
                className={`fa-solid fa-heart mt-0.5 text-[16px] ${
                  linha.feedback ? (COR_CORACAO[linha.feedback] ?? 'text-text-muted') : 'text-text-muted'
                }`}
                aria-hidden
              />
              <div className="min-w-0 flex-1">
                {respostas ? (
                  <p className="text-[12.5px] leading-snug text-text-secondary">{respostas}</p>
                ) : (
                  <p className="text-[12.5px] text-text-muted">
                    Professor ainda não respondeu este mês
                  </p>
                )}
                {linha.observacao ? (
                  // Barra da marca à esquerda: no meio de rótulo e número, ali
                  // tem texto escrito por uma pessoa. Sem corte.
                  <p className="mt-2.5 border-l-2 border-brand pl-3 text-[13px] italic leading-snug text-text-primary">
                    “{linha.observacao}”
                  </p>
                ) : null}
              </div>
            </div>
          </Secao>
        </div>

        {/* ── Rodapé fixo: a saída pra ação. `safe-area` porque no celular a
            folha encosta na barra de gestos do iPhone. ─────────────────── */}
        <footer className="shrink-0 border-t border-border-subtle px-5 pb-[calc(14px_+_env(safe-area-inset-bottom))] pt-3.5">
          <Link
            to="/app/coordenacao/feedback"
            className="inline-flex items-center gap-2 text-[13px] font-semibold text-brand-text hover:underline"
          >
            ver o mês inteiro
            <i className="fa-solid fa-arrow-right text-[11px]" aria-hidden />
          </Link>
        </footer>
      </div>
    </div>,
    document.body,
  )
}

function Secao({ titulo, children }: { titulo: string; children: ReactNode }) {
  return (
    <section className="mt-5 border-t border-border-subtle pt-4 first-of-type:mt-5">
      <p className="mb-2.5 text-[11px] font-bold uppercase tracking-[.5px] text-text-secondary">
        {titulo}
      </p>
      {children}
    </section>
  )
}

/**
 * Um sinal da nota: rótulo, o que ele diz do aluno, e a barra do quanto ele
 * podia pesar × quanto trouxe.
 *
 * Sinal SEM DADO não ganha barra de propósito. Barra vazia lê como "zero",
 * e zero é exatamente o que ele não é — ele saiu da conta e o peso dele foi
 * redistribuído (migration 085).
 */
function SinalDaNota({
  d,
  linha,
  config,
}: {
  d: RadarLinha['nota']['decomposicao'][number]
  linha: RadarLinha
  config: Record<string, number>
}) {
  const valor = valorSinal(d.sinal, linha, d.valor)
  const status = statusDoScore(d.score, config)
  const teto = d.de ?? 0
  const fatia = teto > 0 ? Math.max(0, Math.min(100, ((d.contribuiu ?? 0) / teto) * 100)) : 0

  return (
    <li>
      <div className="flex items-baseline justify-between gap-3">
        <span
          className={`text-[13px] font-semibold ${d.sem_dado ? 'text-text-muted' : 'text-text-primary'}`}
        >
          {rotuloSinal(d.sinal)}
        </span>
        <span className="shrink-0 text-[11.5px] tabular-nums text-text-muted">
          {d.sem_dado ? 'fora da conta' : `${d.contribuiu} de ${d.de} pts`}
        </span>
      </div>
      <p className="mt-0.5 text-[12px] leading-snug text-text-secondary">
        {d.sem_dado ? motivoSemDado(d.sinal) : (valor ?? '—')}
      </p>
      {d.sem_dado ? null : (
        // A borda não é enfeite: sinal que contribuiu ZERO (como absenteísmo de
        // 100%) tem barra vazia, e sem a borda a trilha desaparece dentro da
        // superfície — "0 de 53.3 pts" perde o desenho de quanto ele PODIA valer.
        <div className="mt-1.5 h-1.5 overflow-hidden rounded-full border border-border-subtle bg-bg-inset">
          {/* Largura é DADO (fração da contribuição), não estilo: é o único
              valor daqui que não cabe em classe de token. */}
          <div
            className={`h-full rounded-full ${corDaBarra(status)}`}
            style={{ width: `${fatia}%` }}
          />
        </div>
      )}
    </li>
  )
}

function Comparativo({
  rotulo,
  valor,
  destaque,
}: {
  rotulo: string
  valor: string
  destaque?: boolean
}) {
  return (
    <div className="rounded-md bg-bg-inset px-2.5 py-2">
      <p className="text-[10px] font-bold uppercase tracking-[.5px] text-text-muted">{rotulo}</p>
      <p
        className={`text-[15px] font-extrabold tabular-nums leading-tight ${
          destaque ? 'text-text-primary' : 'text-text-secondary'
        }`}
      >
        {valor}
      </p>
    </div>
  )
}
