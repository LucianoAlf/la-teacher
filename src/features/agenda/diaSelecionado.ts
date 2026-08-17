/**
 * O dia que a agenda mostra mora na URL (`/app/agenda?dia=2026-08-15`), não no
 * estado do componente.
 *
 * Por quê: o professor navega pra um dia passado, abre uma aula e volta. Com o
 * dia em `useState`, `navigate(-1)` remonta a tela e o dia renasce em "hoje" —
 * foi o que o Isaque gravou em 17/08/2026, tendo que reencontrar o sábado a
 * cada aula que ia conferir. Na URL, o voltar do navegador restaura o dia
 * sozinho, o refresh mantém, e o link pode ser mandado pra alguém.
 *
 * A URL é digitável e colável, então o valor é DADO DE FORA: só entra depois de
 * provado que é uma data real.
 */

const FORMATO = /^\d{4}-\d{2}-\d{2}$/

/** A data existe de verdade? ("2026-02-31" casa com o formato e não existe.) */
function dataReal(iso: string): boolean {
  const [ano, mes, dia] = iso.split('-').map(Number)
  if (mes < 1 || mes > 12 || dia < 1) return false
  const d = new Date(Date.UTC(ano, mes - 1, dia))
  // Se o JS teve que "consertar" (31/02 → 03/03), não era data válida.
  return (
    d.getUTCFullYear() === ano && d.getUTCMonth() === mes - 1 && d.getUTCDate() === dia
  )
}

/**
 * Qual dia a agenda deve mostrar, dado o `?dia=` da URL.
 * Ausente ou inválido → hoje (nunca tela quebrada, nunca dia inventado).
 */
export function diaDaUrl(param: string | null | undefined, hoje: string): string {
  if (!param || !FORMATO.test(param)) return hoje
  return dataReal(param) ? param : hoje
}
