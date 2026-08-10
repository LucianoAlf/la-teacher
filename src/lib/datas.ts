/**
 * "Sábado, 8 de agosto" — dia da semana por extenso, primeira letra maiúscula.
 *
 * Estava inline no `AppHeader` e foi extraído quando o painel da coordenação
 * precisou da mesma data. Não é preciosismo: eu tinha escrito `weekday: 'short'`
 * no painel, e "sáb." ao lado de "Sábado" na outra tela do mesmo app é o tipo de
 * diferença que ninguém sabe explicar depois.
 */
export function dataLonga(quando: Date = new Date()): string {
  const d = quando.toLocaleDateString('pt-BR', {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
  })
  return d.charAt(0).toUpperCase() + d.slice(1)
}

/**
 * "2026-08-01" → "1 de agosto". Data que vem do banco não vai crua pra tela: o
 * cabeçalho do Radar dizia "Absenteísmo desde 2026-08-01".
 *
 * Parse pelos pedaços, não `new Date(iso)`: com a string ISO o JS assume UTC e
 * no fuso do Brasil o dia 01 vira 31 do mês anterior.
 */
export function dataDoDia(iso: string | null | undefined): string {
  if (!iso) return '—'
  const [ano, mes, dia] = iso.slice(0, 10).split('-').map(Number)
  if (!ano || !mes || !dia) return iso
  return new Date(ano, mes - 1, dia).toLocaleDateString('pt-BR', {
    day: 'numeric',
    month: 'long',
  })
}

/**
 * "2026-09-01" → "setembro". Mês de competência do banco é sempre o dia 1, e o
 * dia não quer dizer nada — o selo do Radar mostrava "avisou que sai ·
 * 2026-09-01", que é data crua com precisão que ninguém pediu.
 *
 * O ano entra só quando NÃO é o ano corrente ("janeiro de 2027"): quem lê a
 * tela em agosto de 2026 não precisa que a tela repita 2026 em cada selo.
 */
export function mesDoAno(iso: string | null | undefined): string {
  if (!iso) return '—'
  const [ano, mes] = iso.slice(0, 7).split('-').map(Number)
  if (!ano || !mes) return iso
  const nome = new Date(ano, mes - 1, 1).toLocaleDateString('pt-BR', { month: 'long' })
  return ano === new Date().getFullYear() ? nome : `${nome} de ${ano}`
}
