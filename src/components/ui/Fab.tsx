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
  /**
   * Peso visual:
   *  · 'primary'   = bolota teal cheia (o herói — Fábio);
   *  · 'secondary' = fundo neutro + ícone teal (utilitário — microfone),
   *    pra não competir com o herói.
   */
  variant?: 'primary' | 'secondary'
}

const PLACEMENT: Record<'center' | 'right', string> = {
  center: 'bottom-[calc(30px_+_env(safe-area-inset-bottom))] left-1/2 -translate-x-1/2 h-[64px] w-[64px] text-[23px]',
  right: 'bottom-[calc(100px_+_env(safe-area-inset-bottom))] right-[16px] h-[64px] w-[64px] text-[23px]',
}

const VARIANT: Record<'primary' | 'secondary', string> = {
  primary: 'border-4 border-solid border-bg-app bg-brand text-on-brand shadow-fab',
  secondary: 'border border-border-subtle bg-bg-surface text-brand-text shadow-fab',
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
  variant = 'primary',
  className,
  ...rest
}: FabProps) {
  return (
    <button
      aria-label={label}
      className={cx(
        'absolute z-50 flex items-center justify-center rounded-full transition-transform duration-100 active:scale-[.93]',
        PLACEMENT[placement],
        VARIANT[variant],
        className,
      )}
      {...rest}
    >
      {node ?? <i className={icon} aria-hidden="true" />}
    </button>
  )
}
