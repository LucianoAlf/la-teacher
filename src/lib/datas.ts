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
