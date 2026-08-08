import { cx } from '../../lib/cx'

/**
 * Foto de uma pessoa; iniciais quando não tem. Nunca um boneco genérico.
 *
 * Terceiro lugar do app a precisar disso (header do professor, perfil da
 * coordenação, fila do painel) — por isso virou componente em vez de um quarto
 * `<div>` com gradiente. Os tokens `--avatar-grad` / `--avatar-fg` são os
 * mesmos nos três: uma pessoa não pode ter duas caras conforme a tela.
 *
 * `tamanho` é classe de Tailwind e não número porque quem chama também precisa
 * escolher a fonte das iniciais junto — 92px com texto de 15px fica ridículo.
 */
export function Avatar({
  fotoUrl,
  nome,
  tamanho = 'h-10 w-10 text-[15px]',
  className,
}: {
  fotoUrl?: string | null
  nome?: string | null
  tamanho?: string
  className?: string
}) {
  if (fotoUrl) {
    return (
      <img
        src={fotoUrl}
        alt={nome ?? ''}
        draggable={false}
        className={cx(tamanho, 'shrink-0 rounded-full object-cover', className)}
      />
    )
  }
  return (
    <div
      className={cx(
        tamanho,
        'flex shrink-0 items-center justify-center rounded-full bg-[var(--avatar-grad)] font-extrabold text-[color:var(--avatar-fg)]',
        className,
      )}
      aria-hidden
    >
      {iniciais(nome)}
    </div>
  )
}

/** Duas letras: o primeiro e o segundo nome. "·" quando nem nome existe. */
export function iniciais(nome?: string | null) {
  if (!nome) return '·'
  const partes = nome.trim().split(/\s+/)
  return ((partes[0]?.[0] ?? '') + (partes[1]?.[0] ?? '')).toUpperCase()
}
