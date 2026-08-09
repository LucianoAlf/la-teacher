import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { Card } from '../../components/ui'
import { feedbackProgresso, type FeedbackProgresso } from '../../lib/api'

/**
 * O card que sobe na Home na última semana do mês.
 *
 * Some sozinho quando o professor fecha 100% — tarefa terminada não fica
 * ocupando a tela inicial. Fora da janela ele não existe; a entrada
 * permanente é dentro de Alunos.
 */
export function CardFeedbackHome() {
  const [p, setP] = useState<FeedbackProgresso | null>(null)

  useEffect(() => {
    feedbackProgresso().then(setP).catch(() => setP(null))
  }, [])

  if (!p || !p.janela_aberta || p.total === 0 || p.respondidos >= p.total) return null

  const pct = Math.round((p.respondidos / p.total) * 100)

  return (
    <Link to="/app/feedback" className="mb-4 block">
      <Card className="p-4">
        <span className="mb-2 flex items-center gap-2 text-[13px] font-bold uppercase tracking-[.5px] text-text-secondary">
          <i className="fa-solid fa-heart-pulse text-xs text-brand-text" aria-hidden />
          Feedback do mês
        </span>
        <p className="mb-3 text-[13px] text-text-secondary">
          Como estão seus alunos? É o que a coordenação usa pra chegar antes da
          evasão — e tem gente perto da renovação.
        </p>
        <div className="flex items-center gap-3">
          <div className="h-2 flex-1 overflow-hidden rounded-full bg-bg-inset">
            <div className="h-full bg-brand transition-all" style={{ width: `${pct}%` }} />
          </div>
          <span className="whitespace-nowrap text-[11.5px] text-text-muted">
            {p.respondidos}/{p.total}
          </span>
        </div>
      </Card>
    </Link>
  )
}
