import { useEffect } from 'react'
import { Link } from 'react-router-dom'
import type { RadarLinha, RadarResposta } from '../../../lib/api'
import { FRASE_SEMAFORO } from './LinhaSemaforo'

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
 * Modal do aluno no Radar — a nota aberta, com base declarada.
 *
 * Aqui a decomposição NÃO fica em tooltip: é o conteúdo principal. Clique fora
 * ou Escape fecha.
 */
export function ModalAlunoRadar({
  linha,
  medias,
  aoFechar,
}: {
  linha: RadarLinha
  medias: RadarResposta['medias']
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

  return (
    <div
      className="fixed inset-0 z-40 flex items-end justify-center bg-black/40 p-4 md:items-center"
      onClick={aoFechar}
      role="presentation"
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-label={linha.aluno}
        className="max-h-[90svh] w-full max-w-lg overflow-y-auto rounded-lg border border-border-subtle bg-bg-surface p-5 shadow-card"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-4 flex items-start justify-between gap-3">
          <div className="min-w-0">
            <p className="text-[18px] font-extrabold tracking-[-.3px] text-text-primary">
              {linha.aluno}
            </p>
            <p className="text-[12.5px] text-text-muted">
              {[linha.curso, linha.unidade].filter(Boolean).join(' · ')}
              {linha.professor ? ` · com ${linha.professor}` : null}
            </p>
          </div>
          <div className="flex shrink-0 flex-col items-end gap-1">
            <span
              className={`text-[11px] font-bold uppercase tracking-[.5px] ${COR_STATUS[linha.status]}`}
            >
              {ROTULO_STATUS[linha.status]}
            </span>
            {linha.avisou_que_sai ? (
              <span className="rounded-sm bg-warning-soft px-1.5 py-0.5 text-[10px] font-bold uppercase tracking-[.5px] text-warning-text">
                avisou que sai
                {linha.mes_saida ? ` · ${linha.mes_saida}` : ''}
              </span>
            ) : null}
            <button
              type="button"
              onClick={aoFechar}
              className="mt-1 text-[12px] text-text-muted hover:text-text-secondary"
              aria-label="Fechar"
            >
              <i className="fa-solid fa-xmark" aria-hidden />
            </button>
          </div>
        </div>

        <section className="mb-5">
          <p className="mb-2 text-[11px] font-bold uppercase tracking-[.5px] text-text-secondary">
            Health Score
          </p>
          <p className={`mb-3 text-[28px] font-extrabold leading-none ${COR_STATUS[linha.status]}`}>
            {linha.nota.nota ?? '—'}
          </p>
          <ul className="space-y-1.5 text-[12.5px]">
            {linha.nota.decomposicao.map((d) => (
              <li key={d.sinal} className="flex justify-between gap-3">
                <span className={d.sem_dado ? 'text-text-muted' : 'text-text-primary'}>
                  {d.sinal}
                  {d.valor ? ` · ${d.valor}` : ''}
                </span>
                <span className="text-text-secondary">
                  {d.sem_dado
                    ? 'fora da conta'
                    : `contribuiu ${d.contribuiu} de ${d.de}`}
                </span>
              </li>
            ))}
          </ul>
          <p className="mt-2 text-[11.5px] text-text-muted">
            apurada em {linha.nota.sinais_apurados} de {linha.nota.sinais_totais} sinais
            {!linha.nota.suficiente ? ' · insuficiente' : ''}
          </p>
        </section>

        <section className="mb-5">
          <p className="mb-2 text-[11px] font-bold uppercase tracking-[.5px] text-text-secondary">
            Absenteísmo
          </p>
          <p className="text-[13px] text-text-primary">
            {linha.faltas_janela} faltas em {linha.aulas_medidas} aulas medidas · desde 01/08
          </p>
          <p className="mt-1 text-[12px] text-text-muted">
            professor {pct(mediaProf)} · unidade {pct(mediaUni)}
            {linha.absenteismo_pct != null ? ` · aluno ${pct(linha.absenteismo_pct)}` : ''}
          </p>
        </section>

        <section className="mb-5">
          <p className="mb-2 text-[11px] font-bold uppercase tracking-[.5px] text-text-secondary">
            Semáforo do mês
          </p>
          <div className="flex items-start gap-3">
            <i
              className={`fa-solid fa-heart mt-0.5 text-[15px] ${
                linha.feedback ? COR_CORACAO[linha.feedback] : 'text-text-muted'
              }`}
              aria-hidden
            />
            <div className="min-w-0 flex-1">
              {respostas ? (
                <p className="text-[12.5px] text-text-secondary">{respostas}</p>
              ) : (
                <p className="text-[12.5px] text-text-muted">Professor ainda não respondeu</p>
              )}
              {linha.observacao ? (
                <p className="mt-2 border-l-2 border-brand pl-3 text-[13px] italic text-text-primary">
                  “{linha.observacao}”
                </p>
              ) : null}
            </div>
          </div>
        </section>

        <Link
          to="/app/coordenacao/feedback"
          className="inline-flex items-center gap-2 text-[13px] font-semibold text-brand-text hover:underline"
        >
          ver o mês inteiro
          <i className="fa-solid fa-arrow-right text-[11px]" aria-hidden />
        </Link>
      </div>
    </div>
  )
}
