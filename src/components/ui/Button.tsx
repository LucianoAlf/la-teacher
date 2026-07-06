import type { ButtonHTMLAttributes } from 'react'
import { cx } from '../../lib/cx'

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'primary' | 'ghost'
  size?: 'md' | 'sm'
  block?: boolean
}

/** Botão do Fábio DS — primary / ghost / sm / block (protótipo .btn). */
export function Button({
  variant = 'primary',
  size = 'md',
  block = false,
  className,
  children,
  ...rest
}: ButtonProps) {
  return (
    <button
      className={cx(
        'inline-flex items-center justify-center gap-2 font-sans font-bold transition-transform duration-75 active:scale-[.97]',
        size === 'md' ? 'rounded-md px-[18px] py-[13px] text-[14.5px]' : 'rounded-sm px-[13px] py-2 text-[12.5px]',
        variant === 'primary'
          ? 'border-0 bg-brand text-on-brand'
          : 'border border-border-strong bg-transparent text-text-primary',
        block && 'w-full',
        className,
      )}
      {...rest}
    >
      {children}
    </button>
  )
}
