import type { ButtonHTMLAttributes, ReactNode } from 'react'
import { cx } from '../../lib/cx'

export interface FabProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  /** Ícone FontAwesome (default: microfone). Ignorado se `node` vier. */
  icon?: string
  /** Ícone custom (SVG) — tem prioridade sobre `icon`. */
  node?: ReactNode
  label?: string
  /**
   * Posição do botão:
   *  · 'center' = bolota elevada no vão central da TabBar (o herói);
   *  · 'right'  = FAB flutuante no canto direito, acima da barra (utilitário).
   */
  placement?: 'center' | 'right'
}

const PLACEMENT: Record<'center' | 'right', string> = {
  center: 'bottom-[30px] left-1/2 -translate-x-1/2 h-[64px] w-[64px] text-[23px]',
  right: 'bottom-[88px] right-4 h-[54px] w-[54px] text-[19px]',
}

/**
 * Botão de ação flutuante (protótipo .fab). Posiciona-se em relação ao
 * ancestral `relative` mais próximo (o frame da tela). Serve tanto pro herói
 * central (Fábio) quanto pro utilitário flutuante (microfone/gravar).
 */
export function Fab({
  icon = 'fa-solid fa-microphone',
  node,
  label = 'Registrar por voz',
  placement = 'center',
  className,
  ...rest
}: FabProps) {
  return (
    <button
      aria-label={label}
      className={cx(
        'absolute z-50 flex items-center justify-center rounded-full border-4 border-solid border-bg-app bg-brand text-on-brand shadow-fab transition-transform duration-100 active:scale-[.93]',
        PLACEMENT[placement],
        className,
      )}
      {...rest}
    >
      {node ?? <i className={icon} aria-hidden="true" />}
    </button>
  )
}
