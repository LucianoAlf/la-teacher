import { useState, type ReactNode } from 'react'
import { cx } from '../../lib/cx'
import { Badge } from './Badge'

export interface FatiaProps {
  /** Nome do aluno. */
  nome: string
  /** Inicial do avatar (default: primeira letra do nome). */
  inicial?: string
  /** Foto do aluno — quando presente, vira o avatar (fallback: inicial). */
  fotoUrl?: string | null
  /**
   * 'perguntar' = ninguém declarou presença. Não é 'presente' com outro nome:
   * o selo tem que dizer que o dado falta, senão o professor confirma achando
   * que o sistema sabe (migration 019).
   */
  presenca?: 'presente' | 'faltou' | 'perguntar'
  /** Ação no cabeçalho — os botões Esteve/Faltou quando presença é 'perguntar'. */
  acao?: ReactNode
  defaultOpen?: boolean
  /** Corpo do accordion — FieldCards, sugestões etc. */
  children: ReactNode
}

// Regra visual do app: PREENCHIDO = estado gravado no banco; CONTORNO = ainda
// depende do professor. 'perguntar' é o segundo caso — por isso vai outline.
const SELO = {
  presente: { texto: 'presente', variante: 'ok' as const, outline: false },
  faltou: { texto: 'faltou', variante: 'danger' as const, outline: false },
  perguntar: { texto: 'presença?', variante: 'warn' as const, outline: true },
}

/** Accordion por aluno da tela de Confirmação (protótipo .fatia). */
export function Fatia({ nome, inicial, fotoUrl, presenca = 'presente', acao, defaultOpen = false, children }: FatiaProps) {
  const [open, setOpen] = useState(defaultOpen)
  const faltou = presenca === 'faltou'
  const selo = SELO[presenca]

  return (
    <div className="overflow-hidden rounded-lg border border-border-subtle bg-bg-surface">
      <button
        type="button"
        className="flex w-full items-center gap-[10px] border-0 bg-transparent px-[14px] py-3 text-left text-text-primary"
        onClick={() => setOpen((o) => !o)}
        aria-expanded={open}
      >
        {fotoUrl ? (
          <img
            src={fotoUrl}
            alt=""
            className="h-[34px] w-[34px] flex-none rounded-full object-cover"
            onError={(e) => {
              e.currentTarget.style.display = 'none'
            }}
          />
        ) : (
          <span
            className={cx(
              'flex h-[34px] w-[34px] flex-none items-center justify-center rounded-full text-[13px] font-extrabold',
              faltou ? 'bg-danger-soft text-danger-text' : 'bg-brand-soft text-brand-text',
            )}
          >
            {inicial ?? nome.charAt(0).toUpperCase()}
          </span>
        )}
        <b className="flex-1 text-[14.5px]">{nome}</b>
        <Badge variant={selo.variante} outline={selo.outline}>
          {selo.texto}
        </Badge>
        <i
          className={cx('fa-solid fa-chevron-down text-text-muted transition-transform duration-200', open && 'rotate-180')}
          aria-hidden="true"
        />
      </button>
      {/* A pergunta fica FORA do botão do accordion: clicar em "Esteve" não pode
          abrir/fechar o card sem querer. E fica antes do corpo, porque é o que
          bloqueia a confirmação. */}
      {acao && <div className="border-t border-border-subtle px-[14px] py-[10px]">{acao}</div>}
      {open && <div className="border-t border-border-subtle">{children}</div>}
    </div>
  )
}
