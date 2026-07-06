import { addDias, formatExtenso, hojeBRT, isHoje } from '../../lib/date'

export interface DateNavProps {
  value: string
  onChange: (iso: string) => void
}

/** Seletor de dia: ‹ voltar · data por extenso (+ "hoje") · avançar ›. */
export function DateNav({ value, onChange }: DateNavProps) {
  const hoje = isHoje(value)
  return (
    <div className="flex items-center gap-2 px-4 pb-1 pt-1">
      <button
        type="button"
        aria-label="Dia anterior"
        className="flex h-9 w-9 flex-none items-center justify-center rounded-full border border-border-subtle bg-bg-surface text-text-secondary"
        onClick={() => onChange(addDias(value, -1))}
      >
        <i className="fa-solid fa-chevron-left" aria-hidden="true" />
      </button>

      <div className="min-w-0 flex-1 text-center">
        <div className="truncate text-[13px] font-bold">{formatExtenso(value)}</div>
        {!hoje && (
          <button
            type="button"
            className="mt-[2px] text-[11px] font-bold uppercase tracking-[.5px] text-brand-text"
            onClick={() => onChange(hojeBRT())}
          >
            <i className="fa-solid fa-arrow-rotate-left" aria-hidden="true" /> voltar pra hoje
          </button>
        )}
        {hoje && <div className="text-[11px] font-semibold uppercase tracking-[.5px] text-text-muted">hoje</div>}
      </div>

      <button
        type="button"
        aria-label="Próximo dia"
        className="flex h-9 w-9 flex-none items-center justify-center rounded-full border border-border-subtle bg-bg-surface text-text-secondary"
        onClick={() => onChange(addDias(value, 1))}
      >
        <i className="fa-solid fa-chevron-right" aria-hidden="true" />
      </button>
    </div>
  )
}
