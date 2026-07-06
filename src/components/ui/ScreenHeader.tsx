import type { ReactNode } from 'react'

export interface ScreenHeaderProps {
  title: string
  subtitle?: string
  /** Mostra o botão de voltar quando definido (protótipo .conf-head .back). */
  onBack?: () => void
  /** Slot à direita (ex.: botão de tema). */
  right?: ReactNode
}

/** Cabeçalho de tela com voltar (protótipo .rec-top / .conf-head). */
export function ScreenHeader({ title, subtitle, onBack, right }: ScreenHeaderProps) {
  return (
    <header className="flex items-center gap-[10px] px-4 pb-2 pt-[14px]">
      {onBack && (
        <button
          type="button"
          aria-label="Voltar"
          className="flex h-9 w-9 flex-none items-center justify-center rounded-full border border-border-subtle bg-bg-surface text-text-secondary"
          onClick={onBack}
        >
          <i className="fa-solid fa-arrow-left" aria-hidden="true" />
        </button>
      )}
      <div className="min-w-0">
        <b className="block text-[17px] tracking-[-.2px]">{title}</b>
        {subtitle && <span className="block text-xs text-text-secondary">{subtitle}</span>}
      </div>
      {right && <div className="ml-auto flex-none">{right}</div>}
    </header>
  )
}
