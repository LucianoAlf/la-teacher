import { Skeleton } from '../../../components/ui'

/**
 * Número da faixa executiva do painel.
 *
 * O tom não é decoração: `perigo` e `atencao` marcam o que exige ação hoje. Se
 * todos os números ficassem na cor neutra, a faixa viraria placar — e placar não
 * diz por onde começar.
 */
export function PainelNumero({
  rotulo,
  valor,
  sufixo,
  tom,
  carregando,
}: {
  rotulo: string
  valor?: number
  sufixo?: string
  tom?: 'perigo' | 'atencao'
  carregando?: boolean
}) {
  const cor =
    tom === 'perigo'
      ? 'text-danger-text'
      : tom === 'atencao'
        ? 'text-warning-text'
        : 'text-text-primary'

  return (
    <div className="rounded-md bg-bg-surface p-3">
      <p className="mb-1 text-[10.5px] text-text-secondary">{rotulo}</p>
      {carregando ? (
        <Skeleton className="h-7 w-16" />
      ) : (
        <p className={`text-[23px] font-bold leading-tight ${cor}`}>
          {valor ?? '—'}
          {sufixo ? <span className="text-[12px] font-normal text-text-muted">{sufixo}</span> : null}
        </p>
      )}
    </div>
  )
}
