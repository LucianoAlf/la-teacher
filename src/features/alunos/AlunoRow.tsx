import { cx } from '../../lib/cx'
import type { CarteiraAluno } from '../../lib/api'
import { Badge } from '../../components/ui'
import { horarioAluno, qualidadeLabel } from './carteira'

/** Célula de aluno na carteira: avatar, nome, dia/horário e badge de qualidade. */
export function AlunoRow({
  aluno,
  onAbrir,
}: {
  aluno: CarteiraAluno
  /** Abre o detalhe do aluno. Só clicável quando há aluno_id (conciliado). */
  onAbrir?: (aluno: CarteiraAluno) => void
}) {
  const qualidade = qualidadeLabel(aluno.qualidade)
  const horario = horarioAluno(aluno)
  const clicavel = onAbrir != null && aluno.aluno_id != null

  return (
    <div
      className={cx(
        'flex items-center gap-3 border-b border-border-subtle px-1 py-[11px] last:border-b-0',
        clicavel && 'cursor-pointer',
      )}
      role={clicavel ? 'button' : undefined}
      tabIndex={clicavel ? 0 : undefined}
      onClick={clicavel ? () => onAbrir!(aluno) : undefined}
      onKeyDown={
        clicavel
          ? (e) => {
              if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault()
                onAbrir!(aluno)
              }
            }
          : undefined
      }
    >
      <span className="flex h-9 w-9 flex-none items-center justify-center rounded-full bg-brand-soft text-[13px] font-extrabold text-brand-text">
        {aluno.aluno_nome.charAt(0).toUpperCase()}
      </span>
      <div className="min-w-0 flex-1">
        <b className="block truncate text-sm font-semibold">{aluno.aluno_nome}</b>
        <span className="block truncate text-xs text-text-secondary">
          {[horario, aluno.jornada_label].filter(Boolean).join(' · ')}
        </span>
      </div>
      {qualidade && (
        <Badge variant="warn" icon="fa-solid fa-circle-info">
          {qualidade}
        </Badge>
      )}
      {clicavel && (
        <i className="fa-solid fa-chevron-right flex-none text-[11px] text-text-muted" aria-hidden="true" />
      )}
    </div>
  )
}
