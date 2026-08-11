import type { ReactNode } from 'react'
import { Avatar, Badge, Card } from '../../../components/ui'
import type { RadarLinha, RadarResposta } from '../../../lib/api'
import { dataDoDia, mesDoAno } from '../../../lib/datas'
import { nomeCurto } from '../../../lib/nomes'
import {
  BADGE_STATUS,
  COR_CORACAO,
  COR_STATUS,
  FUNDO_STATUS,
  ROTULO_CORACAO,
  ROTULO_STATUS,
  pct,
} from '../sinaisRadar'
import { DecomposicaoNotaTooltip } from './DecomposicaoNotaTooltip'
import { FRASE_SEMAFORO } from './LinhaSemaforo'
import { TooltipRadar } from './TooltipRadar'

/**
 * Uma linha da mesa do Radar (coordenação) — UM cartão, dois arranjos.
 *
 * Histórico curto, porque as duas correções vieram do mesmo lugar: em
 * 10/08/2026 o Alf viu a tela no celular ("não ficou bacana") e depois no
 * desktop ("copia o do celular pra cá; dá pra melhorar essa tabelinha").
 * Antes disso eram duas árvores de JSX diferentes, e era assim que o celular
 * ganhava um cuidado que o desktop não recebia — e vice-versa.
 *
 * Agora as PEÇAS são as mesmas (foto, selo da nota, identidade, células,
 * status) e o que muda por breakpoint é só ONDE cada uma cai no grid:
 *
 * • celular/tablet — foto, selo e nome na primeira fileira; as células numa
 *   faixa própria embaixo, com a largura inteira do cartão.
 * • `lg`+ — tudo numa fileira, as células viram as colunas da mesa (alinhadas
 *   entre as linhas porque o grid é o mesmo em todas).
 * • `xl`+ — cabe a 4ª célula (Prática). Entre 1024 e 1279 ela sai em vez de
 *   espremer as outras três; medido, não estimado.
 *
 * A FOTO (089) é o que o Alf pediu pra "trazer do banco": 290 dos 311 alunos
 * da coorte têm, e reconhecer o aluno pela cara é mais rápido que ler o nome
 * numa lista de 311. Sem foto, o `Avatar` do DS cai nas iniciais.
 *
 * SEM OS PONTINHOS. Os números vinham sublinhados de pontinhos (o gancho do
 * tooltip) e o Alf achou ruim, com razão: sublinhado pontilhado em número lê
 * como erro de digitação. A base de cada número passou a viver NO TEXTO
 * ("1 de 2", "100% · 1/1", "enchendo 0/4") — que é o que o celular já fazia
 * por não ter hover. O tooltip continua só no selo da nota, onde tem conteúdo
 * que não caberia inline (a decomposição), e o card do aluno tem tudo.
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
    : null

  const feedbackExtra = [linha.evolucao, linha.animo]
    .filter(Boolean)
    .map((v) => FRASE_SEMAFORO[v as string] ?? v)
    .join(' · ')

  // Nome de cadastro do professor come a linha inteira ("Daiana Pacifico da
  // Silva dos Anjos"). O aluno continua inteiro: ele é o assunto da linha.
  const origem = [linha.curso, linha.unidade].filter(Boolean).join(' · ')
  const professor = nomeCurto(linha.professor)

  const badgeStatus = (
    <Badge
      variant={BADGE_STATUS[linha.status]}
      className="whitespace-nowrap text-[10px] uppercase tracking-[.5px] lg:text-[11px]"
    >
      {ROTULO_STATUS[linha.status]}
    </Badge>
  )

  const badgeSaida = linha.avisou_que_sai ? (
    <Badge variant="warn" className="whitespace-nowrap uppercase tracking-[.4px]">
      avisou que sai
      {/* Era `2026-09-01` na tela — data crua, com um dia que não diz nada
          (competência é sempre o dia 1 do mês). */}
      {linha.mes_saida ? ` · ${mesDoAno(linha.mes_saida)}` : ''}
    </Badge>
  ) : null

  const selo = (
    <TooltipRadar conteudo={<DecomposicaoNotaTooltip linha={linha} />}>
      <span
        className={`flex h-[48px] w-[48px] flex-col items-center justify-center rounded-md lg:h-[54px] lg:w-[54px] ${FUNDO_STATUS[linha.status]}`}
      >
        <span
          className={`text-[18px] font-extrabold leading-none tracking-[-.5px] tabular-nums lg:text-[20px] ${COR_STATUS[linha.status]}`}
        >
          {linha.nota.nota ?? '—'}
        </span>
        <span className="mt-1 text-[8.5px] font-bold uppercase tracking-[.5px] text-text-muted">
          score
        </span>
      </span>
    </TooltipRadar>
  )

  // ── As células, uma vez só ────────────────────────────────────────────────
  // Cada número traz a base junto, porque é a base que impede o "21% de
  // presença" do LA Report (o número sem denominador que escondeu por meses
  // que ele vinha de linhas dobradas).
  const celulas = (
    <>
      <Celula rotulo="Faltas">
        <span className="tabular-nums">{linha.faltas_mes}</span>
        {linha.aulas_mes > 0 ? (
          <span className="font-normal text-text-muted"> de {linha.aulas_mes}</span>
        ) : null}
      </Celula>

      <Celula rotulo="Absenteísmo">
        {/* O único número da linha cujo sentido depende de comparação: 50% é
            ruim se o professor está em 20% e é a régua da casa se ele está em
            48%. A taxa e a base ficam no texto; a comparação, que não caberia,
            fica no hover — e inteira no card do aluno, pra quem está no
            celular. */}
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
            // "0 de 4 aulas" sozinho lê como "0 faltas em 4 aulas" — o oposto
            // do que é. A palavra vem primeiro.
            <Fraco>
              enchendo {linha.aulas_medidas}/{minimo}
            </Fraco>
          ) : (
            <>
              <span className="tabular-nums">{pct(linha.absenteismo_pct)}</span>
              <span className="font-normal tabular-nums text-text-muted">
                {' '}
                · {linha.faltas_janela}/{linha.aulas_medidas}
              </span>
            </>
          )}
        </TooltipRadar>
      </Celula>

      {/* Prática é a única que sai fora entre 1024 e 1279: quatro células com
          rótulo não caibam ali sem cortar "Absenteísmo" no meio. Ela continua
          no card do aluno, a um clique. */}
      <Celula rotulo="Prática" className="hidden xl:block">
        {pratica ? (
          <span
            className={
              linha.pratica_em_casa === 'nao' ? 'text-warning-text' : 'text-text-secondary'
            }
          >
            {pratica}
          </span>
        ) : (
          <Fraco>sem resposta</Fraco>
        )}
      </Celula>

      <Celula rotulo="Feedback">
        {linha.feedback || pratica ? (
          <span className="flex items-center gap-1.5">
            {linha.feedback ? (
              <i
                className={`fa-solid fa-heart shrink-0 text-[11px] ${COR_CORACAO[linha.feedback] ?? 'text-text-muted'}`}
                aria-hidden
              />
            ) : null}
            {/* Uma palavra no celular (a célula tem um terço de 390px) e a
                frase inteira quando há largura — mesma informação, densidade
                diferente. Sem feedback, sobra a prática, que é o outro lado do
                semáforo. */}
            <span className="truncate text-text-secondary">
              <span className="lg:hidden">
                {linha.feedback ? (ROTULO_CORACAO[linha.feedback] ?? '—') : pratica}
              </span>
              <span className="hidden lg:inline">
                {linha.feedback
                  ? feedbackExtra || ROTULO_CORACAO[linha.feedback] || '—'
                  : pratica}
              </span>
            </span>
          </span>
        ) : (
          <Fraco>sem resposta</Fraco>
        )}
      </Celula>
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
      <Card className="p-3.5 transition-colors hover:bg-bg-hover lg:px-4">
        {/*
          UM grid, dois arranjos. As colunas 1-3 (foto, selo, identidade) e o
          status ficam sempre na primeira fileira; o que muda é onde a faixa de
          células cai — fileira de baixo no celular, quarta coluna no desktop.

          Posição EXPLÍCITA (`row-start`/`col-start`) e não posicionamento
          automático: a faixa de células ocupa as 4 colunas da fileira 2 no
          celular, e sem `col-start-4 row-start-1` no status ele seria empurrado
          pra uma terceira fileira.

          O corte é `lg`, não `md`: medido em 10/08/2026, a 820px de janela a
          mesa de colunas vazava 235px pra fora do `<main>` — a sidebar já
          aparece no `md` e come 228px.
        */}
        <div className="grid grid-cols-[auto_auto_minmax(0,1fr)] items-start gap-x-3 gap-y-2.5 lg:grid-cols-[auto_auto_minmax(0,2fr)_minmax(0,2.1fr)_auto] lg:items-center lg:gap-x-4">
          <Avatar
            fotoUrl={linha.foto}
            nome={linha.aluno}
            tamanho="h-10 w-10 text-[13px] lg:h-[46px] lg:w-[46px] lg:text-[14px]"
          />

          {selo}

          <div className="min-w-0">
            <p className="text-[14.5px] font-bold leading-snug text-text-primary lg:text-[15px]">
              {linha.aluno}
            </p>
            <p className="mt-0.5 text-[11.5px] leading-snug text-text-muted">
              {origem}
              {professor ? ` · com ${professor}` : null}
            </p>

            {/* No celular o status desce pra cá em vez de disputar a linha do
                nome: com foto, selo e pílula na mesma fileira sobravam 140px
                pro nome e "Anna Clara Ferreira Brito" quebrava em duas linhas.
                No desktop ele volta pra ponta direita, onde a coluna alinha
                entre as linhas e o olho varre a lista por status. */}
            <div className="mt-1.5 flex flex-wrap items-center gap-1.5 lg:hidden">
              {badgeStatus}
              {badgeSaida}
            </div>
            {badgeSaida ? <div className="mt-1.5 hidden lg:block">{badgeSaida}</div> : null}
          </div>

          <div className="col-span-3 col-start-1 row-start-2 grid grid-cols-3 gap-2 border-t border-border-subtle pt-2 lg:col-span-1 lg:col-start-4 lg:row-start-1 lg:gap-3 lg:border-0 lg:pt-0 xl:grid-cols-4">
            {celulas}
          </div>

          <div className="hidden lg:col-start-5 lg:row-start-1 lg:block lg:text-right">
            {badgeStatus}
          </div>
        </div>
      </Card>
    </div>
  )
}

/**
 * Célula da mesa: rótulo miúdo em cima, número embaixo. É a mesma peça no
 * celular e no desktop — só o rótulo cresce meio ponto.
 */
function Celula({
  rotulo,
  className,
  children,
}: {
  rotulo: string
  className?: string
  children: ReactNode
}) {
  return (
    <div className={`min-w-0 ${className ?? ''}`}>
      <p className="text-[9.5px] font-bold uppercase tracking-[.5px] text-text-muted lg:text-[10px]">
        {rotulo}
      </p>
      {/* Sem `truncate` na linha inteira: "enchendo 0/4" quebra em duas linhas e
          continua legível — cortado ele viraria "enchendo 0…". */}
      <p className="mt-0.5 text-[12.5px] font-bold leading-snug text-text-primary lg:text-[13px]">
        {children}
      </p>
    </div>
  )
}

/** Estado (não número) dentro da célula: miúdo, apagado e sem negrito. */
function Fraco({ children }: { children: ReactNode }) {
  return <span className="text-[11.5px] font-normal text-text-muted">{children}</span>
}
