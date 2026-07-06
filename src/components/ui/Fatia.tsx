import { useState, type ReactNode } from 'react'
import { cx } from '../../lib/cx'
import { Badge } from './Badge'

export interface FatiaProps {
  /** Nome do aluno. */
  nome: string
  /** Inicial do avatar (default: primeira letra do nome). */
  inicial?: string
  presenca?: 'presente' | 'faltou'
  defaultOpen?: boolean
  /** Corpo do accordion — FieldCards, sugestões etc. */
  children: ReactNode
}

/** Accordion por aluno da tela de Confirmação (protótipo .fatia). */
export function Fatia({ nome, inicial, presenca = 'presente', defaultOpen = false, children }: FatiaProps) {
  const [open, setOpen] = useState(defaultOpen)
  const faltou = presenca === 'faltou'

  return (
    <div className="overflow-hidden rounded-lg border border-border-subtle bg-bg-surface">
      <button
        type="button"
        className="flex w-full items-center gap-[10px] border-0 bg-transparent px-[14px] py-3 text-left text-text-primary"
        onClick={() => setOpen((o) => !o)}
        aria-expanded={open}
      >
        <span
          className={cx(
            'flex h-[34px] w-[34px] flex-none items-center justify-center rounded-full text-[13px] font-extrabold',
            faltou ? 'bg-danger-soft text-danger-text' : 'bg-brand-soft text-brand-text',
          )}
        >
          {inicial ?? nome.charAt(0).toUpperCase()}
        </span>
        <b className="flex-1 text-[14.5px]">{nome}</b>
        <Badge variant={faltou ? 'danger' : 'ok'}>{presenca}</Badge>
        <i
          className={cx('fa-solid fa-chevron-down text-text-muted transition-transform duration-200', open && 'rotate-180')}
          aria-hidden="true"
        />
      </button>
      {open && <div className="border-t border-border-subtle">{children}</div>}
    </div>
  )
}
