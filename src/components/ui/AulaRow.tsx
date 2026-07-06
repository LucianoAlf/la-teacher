import type { ReactNode } from 'react'
import { cx } from '../../lib/cx'

export type AulaStatus = 'ok' | 'now' | 'next'

const DOT_CLASS: Record<AulaStatus, string> = {
  ok: 'bg-success',
  now: 'bg-brand shadow-[0_0_0_4px_var(--brand-soft)] animate-pulse-soft',
  next: 'bg-border-strong',
}

export interface AulaRowProps {
  /** Hora da aula (ex.: "17h") — coluna mono à esquerda. */
  hora: string
  /** Nome da aula/turma/aluno. */
  titulo: string
  /** Linha secundária (ex.: "Turma Qua/Sex · 4 crianças"). */
  detalhe?: string
  /** Slot de badge (ex.: <Badge variant="ok">Registrada</Badge>). */
  badge?: ReactNode
  /** Dot de status à direita: registrada (ok) / agora (now) / futura (next). */
  status?: AulaStatus
  onClick?: () => void
}

/** Linha de aula da Home/Agenda (protótipo .aula). */
export function AulaRow({ hora, titulo, detalhe, badge, status, onClick }: AulaRowProps) {
  return (
    <div
      className={cx(
        'flex items-center gap-3 border-b border-border-subtle px-1 py-[11px] last:border-b-0',
        onClick && 'cursor-pointer',
      )}
      onClick={onClick}
    >
      <span className="w-11 flex-none font-mono text-[12.5px] font-semibold text-text-secondary">
        {hora}
      </span>
      <div className="min-w-0 flex-1">
        <b className="block truncate text-sm font-semibold">{titulo}</b>
        {detalhe && <span className="text-xs text-text-secondary">{detalhe}</span>}
      </div>
      {badge}
      {status && (
        <span className={cx('h-[9px] w-[9px] flex-none rounded-full', DOT_CLASS[status])} aria-hidden="true" />
      )}
    </div>
  )
}
