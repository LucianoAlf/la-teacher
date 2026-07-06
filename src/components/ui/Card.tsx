import type { ReactNode } from 'react'
import { cx } from '../../lib/cx'

export interface CardProps {
  /** Título em caixa alta do cabeçalho (opcional). */
  title?: ReactNode
  /** Classe de ícone (ex.: "fa-solid fa-calendar-day"). */
  icon?: string
  /** Slot à direita do título (ex.: contador "2 de 5 registradas"). */
  right?: ReactNode
  className?: string
  children: ReactNode
}

/** Superfície padrão do app (protótipo .card). */
export function Card({ title, icon, right, className, children }: CardProps) {
  return (
    <section
      className={cx(
        'rounded-lg border border-border-subtle bg-bg-surface p-[14px] shadow-card',
        className,
      )}
    >
      {title && (
        <h3 className="mb-[10px] flex items-center gap-2 text-[13px] font-bold uppercase tracking-[.5px] text-text-secondary">
          {icon && <i className={cx(icon, 'text-xs text-brand-text')} aria-hidden="true" />}
          {title}
          {right && (
            <span className="ml-auto text-[11.5px] font-semibold normal-case tracking-normal text-text-muted">
              {right}
            </span>
          )}
        </h3>
      )}
      {children}
    </section>
  )
}
