import { useEffect, useRef, useState } from 'react'
import { cx } from '../../lib/cx'

export interface CampoEditavelProps {
  /** Rótulo em caixa alta (ex.: "Progresso"). */
  label: string
  /** Classe de ícone do rótulo. */
  icon: string
  /** Valor atual — null = campo não dito pelo professor. */
  value: string | null
  /** Convite gentil mostrado quando value é null (a CUTUCADA do Fábio). */
  cutucada: string
  /** Variante dever de casa (fundo warning-soft). */
  dever?: boolean
  /** Salva o novo texto (string vazia limpa o campo de volta pra null). */
  onSave: (novo: string | null) => void
}

/**
 * Campo do registro na Confirmação. Campo null NUNCA aparece vazio silencioso:
 * vira convite clicável pra preencher (o Fábio nunca inventa — cutuca).
 */
export function CampoEditavel({ label, icon, value, cutucada, dever = false, onSave }: CampoEditavelProps) {
  const [editando, setEditando] = useState(false)
  const valRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (editando && valRef.current) {
      valRef.current.focus()
      // cursor no fim do texto existente
      const sel = window.getSelection()
      if (sel && valRef.current.lastChild) {
        sel.selectAllChildren(valRef.current)
        sel.collapseToEnd()
      }
    }
  }, [editando])

  const vazio = value == null || value.trim() === ''

  return (
    <div className={cx('border-b border-border-subtle px-[14px] py-[11px] last:border-b-0', dever && 'bg-warning-soft')}>
      <label className="mb-1 flex items-center gap-[7px] text-[11px] font-bold uppercase tracking-[.5px] text-text-secondary">
        <i className={cx(icon, 'text-[10px]', dever ? 'text-warning-text' : 'text-brand-text')} aria-hidden="true" />
        {label}
        {!editando && (
          <i className="fa-solid fa-pen ml-auto text-[9px] text-text-muted" aria-hidden="true" />
        )}
      </label>

      {editando ? (
        <div
          ref={valRef}
          contentEditable
          suppressContentEditableWarning
          className="-mx-1 -my-[2px] whitespace-pre-wrap rounded-sm bg-bg-inset px-1 py-[2px] text-sm leading-normal shadow-[var(--focus-ring)] outline-none"
          onBlur={(e) => {
            const novo = (e.currentTarget.textContent ?? '').trim()
            setEditando(false)
            if ((novo || null) !== (value?.trim() || null)) onSave(novo || null)
          }}
        >
          {vazio ? '' : value}
        </div>
      ) : (
        <div
          role="button"
          tabIndex={0}
          className={cx(
            '-mx-1 -my-[2px] cursor-text whitespace-pre-wrap rounded-sm px-1 py-[2px] text-sm leading-normal',
            vazio && 'italic text-text-muted',
          )}
          onClick={() => setEditando(true)}
          onKeyDown={(e) => e.key === 'Enter' && setEditando(true)}
        >
          {vazio ? cutucada : value}
        </div>
      )}
    </div>
  )
}
