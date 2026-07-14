import { cx } from '../../lib/cx'

/**
 * Blocos de renderização do relato pedagógico — usados na ficha do aluno E no
 * histórico da turma. "Rótulo em destaque + valor embaixo" (mesmo estilo dos
 * títulos de card); "Dever de casa" ganha fundo âmbar + ícone de casa (mesmo
 * tratamento do CampoEditavel da Confirmação).
 */

/** Remove acentos/caixa pra comparar rótulo ("Dever de casa" → "dever de casa"). */
export function normalizarRotulo(s: string): string {
  return s
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
    .trim()
}

export function ehDever(rotulo: string): boolean {
  return normalizarRotulo(rotulo) === 'dever de casa'
}

/** Rótulo de seção (uppercase pequeno). dever = âmbar + ícone de casa. */
export function LabelSecao({ rotulo, dever = false }: { rotulo: string; dever?: boolean }) {
  return (
    <b
      className={cx(
        'mb-[3px] flex items-center gap-[6px] text-[11px] font-bold uppercase tracking-[.5px]',
        dever ? 'text-warning-text' : 'text-text-secondary',
      )}
    >
      {dever && <i className="fa-solid fa-house text-[10px]" aria-hidden="true" />}
      {rotulo}
    </b>
  )
}

/** Uma seção "Rótulo: valor". "Dever de casa" ganha o destaque âmbar. */
export function SecaoRegistro({ rotulo, valor }: { rotulo: string; valor: string }) {
  const dever = ehDever(rotulo)
  return (
    <div className={cx(dever && 'rounded-md bg-warning-soft px-[10px] py-2')}>
      <LabelSecao rotulo={rotulo} dever={dever} />
      <p className="whitespace-pre-line text-[13px] leading-relaxed text-text-primary">{valor}</p>
    </div>
  )
}

/** Parágrafo simples (legado emusys / linha que não casa "rótulo: valor"). */
export function ParagrafoRegistro({ texto }: { texto: string }) {
  return <p className="whitespace-pre-line text-[13px] leading-relaxed text-text-primary">{texto}</p>
}
