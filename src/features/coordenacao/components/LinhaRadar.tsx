import { Card } from '../../../components/ui'
import type { RadarLinha, RadarResposta } from '../../../lib/api'
import { FRASE_SEMAFORO } from './LinhaSemaforo'
import { TooltipRadar } from './TooltipRadar'

const COR_STATUS: Record<RadarLinha['status'], string> = {
  critico: 'text-danger-text',
  atencao: 'text-warning-text',
  saudavel: 'text-success-text',
  sem_nota: 'text-text-muted',
}

const ROTULO_STATUS: Record<RadarLinha['status'], string> = {
  critico: 'Crítico',
  atencao: 'Atenção',
  saudavel: 'Saudável',
  sem_nota: 'Sem nota',
}

const COR_CORACAO: Record<string, string> = {
  verde: 'text-success-text',
  amarelo: 'text-warning-text',
  vermelho: 'text-danger-text',
}

function pct(n: number | null | undefined): string {
  if (n == null) return '—'
  return `${Math.round(n)}%`
}

/**
 * Uma linha da mesa do Radar (coordenação).
 *
 * Sete colunas da spec: Aluno · Health Score · Faltas · Absenteísmo · Prática ·
 * Feedback · Status. Todo número carrega a base no tooltip — número sem base
 * é o erro que o LA Report já cometeu uma vez.
 */
export function LinhaRadar({
  linha,
  config,
  medias,
  aoAbrir,
}: {
  linha: RadarLinha
  config: Record<string, number>
  medias: RadarResposta['medias']
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
      <div className="flex flex-wrap items-start gap-x-4 gap-y-2">
        <div className="min-w-[140px] flex-1">
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
            {[linha.curso, linha.unidade].filter(Boolean).join(' · ')}
            {linha.professor ? ` · com ${linha.professor}` : null}
          </p>
        </div>

        <div className="min-w-[72px]" onClick={(e) => e.stopPropagation()}>
          <p className="mb-0.5 text-[10px] font-bold uppercase tracking-[.5px] text-text-secondary">
            Score
          </p>
          <TooltipRadar
            conteudo={
              <>
                <strong>
                  {linha.nota.nota ?? '—'} · {ROTULO_STATUS[linha.status]}
                </strong>
                <ul className="mt-2 space-y-1">
                  {linha.nota.decomposicao.map((d) => (
                    <li key={d.sinal} className="flex justify-between gap-3">
                      <span className={d.sem_dado ? 'text-text-muted' : undefined}>
                        {d.sinal} {d.valor ? `· ${d.valor}` : ''}
                      </span>
                      <span>
                        {d.sem_dado
                          ? 'sem dado (fora da conta)'
                          : `contribuiu ${d.contribuiu} de ${d.de}`}
                      </span>
                    </li>
                  ))}
                </ul>
                <p className="mt-2 text-text-muted">
                  apurada em {linha.nota.sinais_apurados} de {linha.nota.sinais_totais}{' '}
                  sinais
                  {!linha.nota.suficiente ? ' · insuficiente' : ''}
                </p>
              </>
            }
          >
            <span className={`text-[15px] font-extrabold ${COR_STATUS[linha.status]}`}>
              {linha.nota.nota ?? '—'}
            </span>
          </TooltipRadar>
        </div>

        <div className="min-w-[56px]" onClick={(e) => e.stopPropagation()}>
          <p className="mb-0.5 text-[10px] font-bold uppercase tracking-[.5px] text-text-secondary">
            Faltas
          </p>
          <TooltipRadar
            conteudo={
              <>
                <strong>{linha.faltas_mes} faltas no mês</strong>
                <p className="mt-1 text-text-muted">
                  {linha.faltas_mes} de {linha.aulas_mes} aulas do mês ·{' '}
                  {linha.faltas_consecutivas} seguida(s)
                </p>
              </>
            }
          >
            <span className="text-[15px] font-bold text-text-primary">{linha.faltas_mes}</span>
          </TooltipRadar>
        </div>

        <div className="min-w-[88px]" onClick={(e) => e.stopPropagation()}>
          <p className="mb-0.5 text-[10px] font-bold uppercase tracking-[.5px] text-text-secondary">
            Absenteísmo
          </p>
          <TooltipRadar
            conteudo={
              <>
                <strong>
                  {linha.absenteismo_pct == null
                    ? `enchendo: ${linha.aulas_medidas} de ${minimo}`
                    : `${pct(linha.absenteismo_pct)} · ${linha.faltas_janela} de ${linha.aulas_medidas}`}
                </strong>
                <p className="mt-1">
                  Janela desde 01/08 · {linha.faltas_janela} faltas em{' '}
                  {linha.aulas_medidas} aulas medidas
                </p>
                <p className="mt-1 text-text-muted">
                  professor {pct(mediaProf)} · unidade {pct(mediaUni)}
                </p>
              </>
            }
          >
            <span className="text-[15px] font-bold text-text-primary">
              {linha.absenteismo_pct == null
                ? `enchendo: ${linha.aulas_medidas} de ${minimo}`
                : pct(linha.absenteismo_pct)}
            </span>
          </TooltipRadar>
        </div>

        <div className="min-w-[88px]">
          <p className="mb-0.5 text-[10px] font-bold uppercase tracking-[.5px] text-text-secondary">
            Prática
          </p>
          <p
            className={`text-[12.5px] ${
              linha.pratica_em_casa === 'nao' ? 'font-semibold text-warning-text' : 'text-text-secondary'
            }`}
          >
            {pratica}
          </p>
        </div>

        <div className="min-w-[100px]">
          <p className="mb-0.5 text-[10px] font-bold uppercase tracking-[.5px] text-text-secondary">
            Feedback
          </p>
          {linha.feedback ? (
            <p className="flex items-center gap-1.5 text-[12.5px] text-text-secondary">
              <i
                className={`fa-solid fa-heart text-[12px] ${COR_CORACAO[linha.feedback] ?? 'text-text-muted'}`}
                aria-hidden
              />
              <span>{feedbackExtra || '—'}</span>
            </p>
          ) : (
            <p className="text-[12.5px] text-text-muted">—</p>
          )}
        </div>

        <div className="ml-auto min-w-[72px] text-right">
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
