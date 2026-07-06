import { useEffect, useRef, useState } from 'react'
import { cx } from '../../lib/cx'

export interface FieldCardProps {
  /** Rótulo em caixa alta (ex.: "Atividades", "Dever de casa"). */
  label: string
  /** Classe de ícone do rótulo (ex.: "fa-solid fa-music"). */
  icon?: string
  /** Valor inicial do campo. */
  value: string
  /** Variante dever de casa — fundo warning-soft (protótipo .campo.dever). */
  dever?: boolean
  /** Estilo de "campo não dito" — cutucada do Fábio (muted + itálico). */
  placeholder?: boolean
  /** Permite edição inline (contenteditable, como no protótipo). */
  editable?: boolean
  /** Chamado no blur com o texto final. */
  onChange?: (value: string) => void
}

/** Campo do molde de registro (protótipo .campo — label + valor editável). */
export function FieldCard({
  label,
  icon = 'fa-solid fa-pen',
  value,
  dever = false,
  placeholder = false,
  editable = false,
  onChange,
}: FieldCardProps) {
  const [text, setText] = useState(value)
  const [editing, setEditing] = useState(false)
  const valRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (editing) valRef.current?.focus()
  }, [editing])

  return (
    <div
      className={cx(
        'border-b border-border-subtle px-[14px] py-[11px] last:border-b-0',
        dever && 'bg-warning-soft',
      )}
    >
      <label className="mb-1 flex items-center gap-[7px] text-[11px] font-bold uppercase tracking-[.5px] text-text-secondary">
        <i
          className={cx(icon, 'text-[10px]', dever ? 'text-warning-text' : 'text-brand-text')}
          aria-hidden="true"
        />
        {label}
      </label>
      <div
        ref={valRef}
        contentEditable={editing}
        suppressContentEditableWarning
        className={cx(
          '-mx-1 -my-[2px] rounded-sm px-1 py-[2px] text-sm leading-normal',
          placeholder && 'italic text-text-muted',
          editable && !editing && 'cursor-text',
          editing && 'bg-bg-inset shadow-[var(--focus-ring)] outline-none',
        )}
        onClick={() => editable && setEditing(true)}
        onBlur={(e) => {
          if (!editing) return
          const next = e.currentTarget.textContent ?? ''
          setText(next)
          setEditing(false)
          onChange?.(next)
        }}
      >
        {text}
      </div>
    </div>
  )
}
