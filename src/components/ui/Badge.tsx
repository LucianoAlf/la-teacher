import type { ReactNode } from 'react'
import { cx } from '../../lib/cx'

export type BadgeVariant = 'ok' | 'warn' | 'danger' | 'brand' | 'info'

const VARIANT_CLASS: Record<BadgeVariant, string> = {
  ok: 'bg-success-soft text-success-text',
  warn: 'bg-warning-soft text-warning-text',
  danger: 'bg-danger-soft text-danger-text',
  brand: 'bg-brand-soft text-brand-text',
  info: 'bg-info-soft text-info-text',
}

export interface BadgeProps {
  variant?: BadgeVariant
  /** Classe de ícone opcional (ex.: "fa-solid fa-check"). */
  icon?: string
  className?: string
  onClick?: () => void
  children: ReactNode
}

/** Selo de status (protótipo .badge — ok/warn/danger/brand/info). */
export function Badge({ variant = 'brand', icon, className, onClick, children }: BadgeProps) {
  return (
    <span
      className={cx(
        'inline-flex items-center gap-[5px] rounded-full px-[9px] py-[3px] text-[11px] font-bold',
        VARIANT_CLASS[variant],
        onClick && 'cursor-pointer',
        className,
      )}
      onClick={onClick}
    >
      {icon && <i className={icon} aria-hidden="true" />}
      {children}
    </span>
  )
}
