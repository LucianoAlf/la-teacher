import type { ReactNode } from 'react'
import { Card } from '../../../components/ui'
import type { RadarLinha, RadarResposta } from '../../../lib/api'
import { dataDoDia } from '../../../lib/datas'
import {
  COR_CORACAO,
  COR_STATUS,
  FUNDO_STATUS,
  ROTULO_CORACAO,
  ROTULO_STATUS,
  motivoSemDado,
  pct,
  rotuloSinal,
  valorSinal,
} from '../sinaisRadar'
import { FRASE_SEMAFORO } from './LinhaSemaforo'
import { TooltipRadar } from './TooltipRadar'

/**
 * Uma linha da mesa do Radar (coordenação) — em DOIS layouts, não em um que se
 * dobra.
 *
 * As sete colunas da spec (Aluno · Health Score · Faltas · Absenteísmo ·
 * Prática · Feedback · Status) são um jeito de VARRER: valem no desktop, onde
 * cabem lado a lado e alinham entre as linhas. No celular a mesma fileira
 * quebrava em três faixas de rótulos maiúsculos com "—" embaixo — o Alf viu a
 * tela em 10/08/2026 e o veredito foi "não ficou bacana", com razão.
 *
 * No celular a linha é um CARTÃO: selo da nota à esquerda (a cor já diz o
 * estado), nome e professor, e três números que caibam de verdade — faltas,
 * absenteísmo e semáforo. O resto está a um toque de distância, no card do
 * aluno, que no celular é a tela de detalhe. Isso também resolve o que tooltip
 * não resolve: **não existe hover no celular**, então todo número que só
 * explicava a base ali dentro precisava de outro caminho.
 */
export function LinhaRadar({
  linha,
  config,
  medias,
  baseDesde,
  aoAbrir,
}: {
  linha: RadarLinha
  config: Record<string, number>
  medias: RadarResposta['medias']
  /** Início da janela de absenteísmo, do `resumo` — era "01/08" no código. */
  baseDesde: string | null
  aoAbrir: (linha: RadarLinha) => void
}) {
  const minimo = config.minimo_aulas_para_taxa ?? 4
  const mediaProf =
    linha.professor_id == null
      ? null
      : (medias.professores.find((p) => p.professor_id === linha.professor_id)
          ?.absenteismo_media ?? null)
  const mediaUni =
    medias.unidades.find((u) => u.unidade === linha.unidade)?.absenteismo_media ?? null

  const pratica = linha.pratica_em_casa
    ? (FRASE_SEMAFORO[linha.pratica_em_casa] ?? linha.pratica_em_casa)
    : '—'

  const feedbackExtra = [linha.evolucao, linha.animo]
    .filter(Boolean)
    .map((v) => FRASE_SEMAFORO[v as string] ?? v)
    .join(' · ')

  const origem = [linha.curso, linha.unidade].filter(Boolean).join(' · ')

  const tooltipNota = (
    <>
      <strong>
        {linha.nota.nota ?? '—'} · {ROTULO_STATUS[linha.status]}
      </strong>
      <ul className="mt-2 space-y-1">
        {linha.nota.decomposicao.map((d) => {
          // Sinal fora da conta mostra o MOTIVO, não o valor: "0 faltas
          // seguidas" ao lado de "fora da conta" afirma o que a guarda da 088
          // se recusa a afirmar.
          const detalhe = d.sem_dado
            ? motivoSemDado(d.sinal)
            : valorSinal(d.sinal, linha, d.valor)
          return (
            <li key={d.sinal} className="flex justify-between gap-3">
              <span className={d.sem_dado ? 'text-text-muted' : undefined}>
                {rotuloSinal(d.sinal)}
                {detalhe ? ` · ${detalhe}` : ''}
              </span>
              <span>
                {d.sem_dado ? 'fora da conta' : `contribuiu ${d.contribuiu} de ${d.de}`}
              </span>
            </li>
          )
        })}
      </ul>
      <p className="mt-2 text-text-muted">
        apurada em {linha.nota.sinais_apurados} de {linha.nota.sinais_totais} sinais
        {!linha.nota.suficiente ? ' · insuficiente' : ''}
      </p>
    </>
  )

  return (
    <div
      role="button"
      tabIndex={0}
      onClick={() => aoAbrir(linha)}
      onKeyDown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault()
          aoAbrir(linha)
        }
      }}
      className="mb-2 cursor-pointer rounded-lg outline-none focus-visible:ring-2 focus-visible:ring-brand"
    >
      <Card className="p-3.5 transition-colors hover:bg-bg-hover">
        {/* ── Cartão: celular E tablet ────────────────────────────────────
            O corte é `lg`, não `md`. Medido em 10/08/2026: a 820px de janela a
            mesa de sete colunas vazava 235px pra fora do `<main>` — a sidebar
            já aparece no `md` e come 228px, e as colunas não cabem no que
            sobra. Melhor cartão largo que mesa cortada. ─────────────────── */}
        <div className="flex items-start gap-3 lg:hidden">
          <div
            className={`flex h-[52px] w-[52px] shrink-0 flex-col items-center justify-center rounded-md ${FUNDO_STATUS[linha.status]}`}
          >
            <span
              className={`text-[19px] font-extrabold leading-none tracking-[-.5px] ${COR_STATUS[linha.status]}`}
            >
              {linha.nota.nota ?? '—'}
            </span>
            <span className="mt-1 text-[8.5px] font-bold uppercase tracking-[.5px] text-text-muted">
              score
            </span>
          </div>

          <div className="min-w-0 flex-1">
            <div className="flex items-start justify-between gap-2">
              <p className="min-w-0 text-[14.5px] font-bold leading-snug text-text-primary">
                {linha.aluno}
              </p>
              <span
                className={`shrink-0 whitespace-nowrap pt-0.5 text-[10px] font-bold uppercase tracking-[.5px] ${COR_STATUS[linha.status]}`}
              >
                {ROTULO_STATUS[linha.status]}
              </span>
            </div>
            <p className="mt-0.5 text-[11.5px] leading-snug text-text-muted">
              {origem}
              {linha.professor ? ` · com ${linha.professor}` : null}
            </p>
            {linha.avisou_que_sai ? (
              <span className="mt-1.5 inline-flex items-center rounded-sm bg-warning-soft px-1.5 py-0.5 text-[9.5px] font-bold uppercase tracking-[.5px] text-warning-text">
                avisou que sai
                {linha.mes_saida ? ` · ${linha.mes_saida}` : ''}
              </span>
            ) : null}

            {/* Três números com a base no próprio texto — no celular não há
                tooltip pra guardar "de quantas aulas". */}
            <div className="mt-2.5 grid grid-cols-3 gap-2 border-t border-border-subtle pt-2">
              <Celula rotulo="Faltas">
                {linha.faltas_mes}
                {linha.aulas_mes > 0 ? (
                  <span className="font-normal text-text-muted"> de {linha.aulas_mes}</span>
                ) : null}
              </Celula>
              <Celula rotulo="Absenteísmo">
                {linha.absenteismo_pct == null ? (
                  // "0 de 4 aulas" sozinho lê como "0 faltas em 4 aulas" — o
                  // oposto do que é. A palavra vem primeiro.
                  <span className="text-[11.5px] font-normal text-text-muted">
                    enchendo {linha.aulas_medidas}/{minimo}
                  </span>
                ) : (
                  <>
                    {pct(linha.absenteismo_pct)}
                    <span className="font-normal text-text-muted">
                      {' '}
                      · {linha.faltas_janela}/{linha.aulas_medidas}
                    </span>
                  </>
                )}
              </Celula>
              <Celula rotulo="Semáforo">
                {linha.feedback || linha.pratica_em_casa ? (
                  <span className="flex items-center gap-1.5">
                    {linha.feedback ? (
                      <i
                        className={`fa-solid fa-heart text-[11px] ${COR_CORACAO[linha.feedback] ?? 'text-text-muted'}`}
                        aria-hidden
                      />
                    ) : null}
                    {/* O coração primeiro, e em UMA palavra: a célula tem um
                        terço de 390px. "pratica às vezes" quebrava em duas
                        linhas e não é o que o rótulo "Semáforo" promete —
                        prática detalhada está no card, a um toque. */}
                    <span className="text-[11.5px] font-normal text-text-secondary">
                      {linha.feedback ? (ROTULO_CORACAO[linha.feedback] ?? '—') : pratica}
                    </span>
                  </span>
                ) : (
                  <span className="text-[11.5px] font-normal text-text-muted">sem resposta</span>
                )}
              </Celula>
            </div>
          </div>
        </div>

        {/* ── Desktop: a mesa de varrer, em grid pra as colunas baterem entre
            as linhas (com flex-wrap + min-width elas dançavam).

            Colunas em `fr`, não em px: com largura fixa a soma mínima (792px)
            era maior que o miolo disponível em 1024px e a linha estourava. Cada
            célula leva `min-w-0` — sem isso o item de grid se recusa a encolher
            abaixo do conteúdo e o `fr` não serve pra nada. ───────────────── */}
        <div className="hidden lg:grid lg:grid-cols-[2.6fr_0.5fr_0.45fr_0.9fr_0.9fr_1.1fr_0.7fr] lg:items-start lg:gap-x-3">
          <div className="min-w-0">
            <p className="text-[15px] font-bold text-text-primary">
              {linha.aluno}
              {linha.avisou_que_sai ? (
                <span className="ml-2 inline-flex items-center rounded-sm bg-warning-soft px-1.5 py-0.5 text-[10px] font-bold uppercase tracking-[.5px] text-warning-text">
                  avisou que sai
                  {linha.mes_saida ? ` · ${linha.mes_saida}` : ''}
                </span>
              ) : null}
            </p>
            <p className="text-[11.5px] text-text-muted">
              {origem}
              {linha.professor ? ` · com ${linha.professor}` : null}
            </p>
          </div>

          <div className="min-w-0" onClick={(e) => e.stopPropagation()}>
            <Rotulo>Score</Rotulo>
            <TooltipRadar conteudo={tooltipNota}>
              <span className={`text-[15px] font-extrabold ${COR_STATUS[linha.status]}`}>
                {linha.nota.nota ?? '—'}
              </span>
            </TooltipRadar>
          </div>

          <div className="min-w-0" onClick={(e) => e.stopPropagation()}>
            <Rotulo>Faltas</Rotulo>
            <TooltipRadar
              conteudo={
                <>
                  <strong>
                    {linha.faltas_mes === 1 ? '1 falta' : `${linha.faltas_mes} faltas`} no mês
                  </strong>
                  <p className="mt-1 text-text-muted">
                    {linha.faltas_mes} de {linha.aulas_mes} aulas do mês ·{' '}
                    {valorSinal('faltas_consecutivas', linha, null)}
                  </p>
                </>
              }
            >
              <span className="text-[15px] font-bold text-text-primary">{linha.faltas_mes}</span>
            </TooltipRadar>
          </div>

          <div className="min-w-0" onClick={(e) => e.stopPropagation()}>
            <Rotulo>Absenteísmo</Rotulo>
            <TooltipRadar
              conteudo={
                <>
                  <strong>
                    {linha.absenteismo_pct == null
                      ? `sem taxa ainda: ${linha.aulas_medidas} de ${minimo} aulas`
                      : `${pct(linha.absenteismo_pct)} · ${linha.faltas_janela} de ${linha.aulas_medidas}`}
                  </strong>
                  <p className="mt-1">
                    Janela desde {dataDoDia(baseDesde)} · {linha.faltas_janela} faltas em{' '}
                    {linha.aulas_medidas} aulas medidas
                  </p>
                  <p className="mt-1 text-text-muted">
                    professor {pct(mediaProf)} · unidade {pct(mediaUni)}
                  </p>
                </>
              }
            >
              {linha.absenteismo_pct == null ? (
                // "enchendo: 0 de 4" em 15px bold estourava a coluna e entrava
                // na de Prática (grid não corta o que passa). Estado se escreve
                // como estado: miúdo, apagado e curto.
                <span className="whitespace-nowrap text-[12.5px] font-semibold text-text-muted">
                  enchendo {linha.aulas_medidas}/{minimo}
                </span>
              ) : (
                <span className="text-[15px] font-bold text-text-primary">
                  {pct(linha.absenteismo_pct)}
                </span>
              )}
            </TooltipRadar>
          </div>

          <div className="min-w-0">
            <Rotulo>Prática</Rotulo>
            <p
              className={`text-[12.5px] ${
                linha.pratica_em_casa === 'nao'
                  ? 'font-semibold text-warning-text'
                  : 'text-text-secondary'
              }`}
            >
              {pratica}
            </p>
          </div>

          <div className="min-w-0">
            <Rotulo>Feedback</Rotulo>
            {linha.feedback ? (
              <p className="flex items-center gap-1.5 text-[12.5px] text-text-secondary">
                <i
                  className={`fa-solid fa-heart shrink-0 text-[12px] ${COR_CORACAO[linha.feedback] ?? 'text-text-muted'}`}
                  aria-hidden
                />
                <span className="truncate">
                  {feedbackExtra || ROTULO_CORACAO[linha.feedback] || '—'}
                </span>
              </p>
            ) : (
              <p className="text-[12.5px] text-text-muted">—</p>
            )}
          </div>

          <div className="min-w-0 text-right">
            <span
              className={`whitespace-nowrap text-[11px] font-bold uppercase tracking-[.5px] ${COR_STATUS[linha.status]}`}
            >
              {ROTULO_STATUS[linha.status]}
            </span>
          </div>
        </div>
      </Card>
    </div>
  )
}

/** Rótulo de coluna da mesa (desktop) — a receita de rótulo do DS, em 10px. */
function Rotulo({ children }: { children: ReactNode }) {
  return (
    <p className="mb-0.5 text-[10px] font-bold uppercase tracking-[.5px] text-text-secondary">
      {children}
    </p>
  )
}

/** Célula do cartão de celular: rótulo miúdo em cima, número em baixo. */
function Celula({ rotulo, children }: { rotulo: string; children: ReactNode }) {
  return (
    <div className="min-w-0">
      <p className="text-[9.5px] font-bold uppercase tracking-[.5px] text-text-muted">{rotulo}</p>
      {/* Sem `truncate`: "enchendo · 0/4" quebra em duas linhas e continua
          legível — cortado ele viraria "enchendo · 0…". */}
      <p className="mt-0.5 text-[13px] font-bold leading-snug text-text-primary">{children}</p>
    </div>
  )
}
