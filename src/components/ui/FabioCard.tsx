import type { ReactNode } from 'react'
import { cx } from '../../lib/cx'

export interface FabioCardProps {
  title?: string
  /** Tag em caixa alta à direita (ex.: "pré-aula · 17h"). */
  tag?: string
  className?: string
  children: ReactNode
}

/** Card do briefing do Fábio — gradiente brand-soft (protótipo .fabio-card). */
export function FabioCard({ title = 'Briefing do Fábio', tag, className, children }: FabioCardProps) {
  return (
    <section
      className={cx(
        'rounded-lg border border-[color:var(--brand-border)] bg-[linear-gradient(150deg,var(--brand-soft),transparent_70%)] p-[14px]',
        className,
      )}
    >
      <div className="mb-2 flex items-center gap-[9px]">
        <div className="flex h-[30px] w-[30px] flex-none items-center justify-center rounded-full bg-brand text-[13px] text-on-brand">
          <i className="fa-solid fa-robot" aria-hidden="true" />
        </div>
        <b className="text-[13.5px]">{title}</b>
        {tag && (
          <span className="ml-auto text-[10.5px] font-bold uppercase tracking-[.5px] text-brand-text">
            {tag}
          </span>
        )}
      </div>
      <div className="space-y-[7px] text-[13.5px] leading-[1.55] text-text-primary">{children}</div>
    </section>
  )
}
