import type { ReactNode } from 'react'

export interface EmptyStateProps {
  /** Classe de ícone (ex.: "fa-solid fa-mug-hot"). */
  icon?: string
  title: string
  /** Direção obrigatória — nunca só "sem dados" (frontend-tokens.md §4). */
  description: string
  /** Ação opcional (ex.: <Button>…</Button>). */
  action?: ReactNode
}

/** Estado vazio com direção. */
export function EmptyState({ icon = 'fa-solid fa-seedling', title, description, action }: EmptyStateProps) {
  return (
    <div className="flex flex-col items-center justify-center gap-3 px-6 py-10 text-center">
      <div className="flex h-14 w-14 items-center justify-center rounded-full bg-brand-soft text-xl text-brand-text">
        <i className={icon} aria-hidden="true" />
      </div>
      <b className="text-[15px] font-bold">{title}</b>
      <p className="max-w-[280px] text-[13px] leading-relaxed text-text-secondary">{description}</p>
      {action}
    </div>
  )
}
