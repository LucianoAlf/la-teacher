import type { ButtonHTMLAttributes } from 'react'
import { cx } from '../../lib/cx'

export interface FabProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  /** Classe de ícone (default: microfone — aprovado como está). */
  icon?: string
  label?: string
}

/**
 * Botão central de microfone (protótipo .fab). Posiciona-se em relação ao
 * ancestral `relative` mais próximo (o frame da tela).
 */
export function Fab({ icon = 'fa-solid fa-microphone', label = 'Registrar por voz', className, ...rest }: FabProps) {
  return (
    <button
      aria-label={label}
      className={cx(
        'absolute bottom-[34px] left-1/2 z-50 flex h-[62px] w-[62px] -translate-x-1/2 items-center justify-center rounded-full border-4 border-solid border-bg-app bg-brand text-[22px] text-on-brand shadow-fab transition-transform duration-100 active:scale-[.93]',
        className,
      )}
      {...rest}
    >
      <i className={icon} aria-hidden="true" />
    </button>
  )
}
