import { cx } from '../../lib/cx'
import { diaDoMes, inicialDiaSemana, isHoje } from '../../lib/date'
import type { ContagemSemana } from './useSemana'

interface Props {
  dias: string[]
  contagem: ContagemSemana
  selecionado: string
  onSelect: (iso: string) => void
}

/** Strip compacta da semana (seg→dom): seleciona o dia; ponto = tem aula. */
export function SemanaStrip({ dias, contagem, selecionado, onSelect }: Props) {
  return (
    <div className="flex gap-1 px-4 py-2">
      {dias.map((d) => {
        const ativo = d === selecionado
        const hoje = isHoje(d)
        const tem = (contagem[d] ?? 0) > 0
        return (
          <button
            key={d}
            type="button"
            onClick={() => onSelect(d)}
            aria-current={ativo ? 'date' : undefined}
            className={cx(
              'flex flex-1 flex-col items-center gap-1 rounded-md border py-2 transition-colors',
              ativo
                ? 'border-brand bg-brand-soft text-brand-text'
                : 'border-border-subtle bg-bg-surface text-text-secondary',
            )}
          >
            <span className="text-[10px] font-bold uppercase">{inicialDiaSemana(d)}</span>
            <span className={cx('text-[15px] font-bold', hoje && !ativo && 'text-brand-text')}>
              {diaDoMes(d)}
            </span>
            <span
              className={cx(
                'h-[5px] w-[5px] rounded-full',
                tem ? 'bg-brand' : 'bg-transparent',
              )}
              aria-hidden="true"
            />
          </button>
        )
      })}
    </div>
  )
}
