import { Card, Skeleton } from '../../../components/ui'

/**
 * Número da faixa executiva do painel.
 *
 * O tom não é decoração: `perigo` e `atencao` marcam o que exige ação hoje. Se
 * todos os números ficassem na cor neutra, a faixa viraria placar — e placar não
 * diz por onde começar.
 *
 * A superfície é o `Card` do DS, não uma div minha. A primeira versão era
 * `rounded-md bg-bg-surface p-3`: sem borda, sem `shadow-card` e com raio de
 * 12px onde o app inteiro usa 16px. No tema escuro passava despercebido (lá a
 * sombra é `none`); no claro os KPIs ficavam achatados no meio de uma tela de
 * cards elevados.
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
    <Card>
      {/* Receita de rótulo do DS (a mesma do FieldCard e das seções do Meu
          perfil): 11px, bold, caixa alta, tracking .5px. */}
      <p className="mb-1 text-[11px] font-bold uppercase tracking-[.5px] text-text-secondary">
        {rotulo}
      </p>
      {carregando ? (
        <Skeleton className="h-7 w-16" />
      ) : (
        <p className={`text-[23px] font-extrabold leading-tight tracking-[-.3px] ${cor}`}>
          {valor ?? '—'}
          {sufixo ? (
            <span className="text-[12px] font-normal tracking-normal text-text-muted">{sufixo}</span>
          ) : null}
        </p>
      )}
    </Card>
  )
}
