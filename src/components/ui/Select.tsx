import type { SelectHTMLAttributes } from 'react'
import { cx } from '../../lib/cx'

// `size` nativo do <select> é NÚMERO (quantas linhas aparecem abertas) e
// ninguém usa. Fica omitido pra que o `size` do DS ("md" | "sm") continue
// significando a mesma coisa aqui e no Button.
export interface SelectProps extends Omit<SelectHTMLAttributes<HTMLSelectElement>, 'size'> {
  size?: 'md' | 'sm'
}

/**
 * Campo de escolha — o primeiro do app, por isso nasce no DS e não na tela.
 *
 * A caixa é a MESMA receita dos inputs do Meu perfil (`rounded-md`, borda
 * `border-strong`, fundo `bg-inset`, foco em `border-brand`); só o tamanho `sm`
 * é novo, pra caber na faixa flutuante do painel ao lado da data e do avatar.
 *
 * `appearance-none` + seta própria de propósito: a seta nativa não segue os
 * tokens e, no tema escuro, o Windows desenha um triângulo claro numa caixa
 * escura. O `pr-8` reserva o espaço dela.
 */
export function Select({ size = 'md', className, children, ...rest }: SelectProps) {
  return (
    <span className="relative inline-flex items-center">
      <select
        className={cx(
          'w-full appearance-none rounded-md border border-border-strong bg-bg-inset text-text-primary transition-colors focus-visible:border-brand focus-visible:outline-none',
          size === 'md' ? 'px-[14px] py-[11px] pr-9 text-sm' : 'px-[10px] py-[6px] pr-8 text-[12.5px]',
          className,
        )}
        {...rest}
      >
        {children}
      </select>
      <i
        className={cx(
          'pointer-events-none absolute text-[10px] text-text-secondary',
          size === 'md' ? 'right-[14px]' : 'right-[10px]',
          'fa-solid fa-chevron-down',
        )}
        aria-hidden="true"
      />
    </span>
  )
}
