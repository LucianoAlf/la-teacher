/**
 * Nome de gente do jeito que se fala, não do jeito que o Emusys guardou.
 *
 * Pedido do Alf em 10/08/2026, olhando a mesa do Radar: "o nome do professor
 * não precisa ser o nome todo — igual Daiana Pacífico da Silva dos Anjos; só
 * Daiana Pacífico tá ótimo". Nome de cadastro tem quatro, cinco palavras e
 * come a linha inteira numa lista de 311 alunos, empurrando curso e unidade
 * pra fora.
 *
 * NÃO é `split(' ')[0] + ' ' + split(' ')[1]`, e é por causa do dado real: em
 * "Letícia de Almeida Palmeira" as duas primeiras palavras são "Letícia de",
 * que não é nome de ninguém. A partícula gruda no que vem depois dela.
 */
const PARTICULAS = new Set([
  'de',
  'da',
  'do',
  'das',
  'dos',
  'e',
  'di',
  'del',
  'della',
  'du',
  'la',
  'le',
  'van',
  'von',
  'y',
])

/**
 * Primeiro nome + o sobrenome seguinte. Apelido entre parênteses cai fora
 * ("Rafael Alves Souza (Akeem)" → "Rafael Alves") e partícula não conta como
 * sobrenome ("Letícia de Almeida Palmeira" → "Letícia de Almeida").
 */
export function nomeCurto(nome: string | null | undefined): string {
  if (!nome) return ''
  const partes = nome
    .replace(/\([^)]*\)/g, ' ')
    .trim()
    .split(/\s+/)
    .filter(Boolean)
  if (partes.length <= 2) return partes.join(' ')

  const curto = [partes[0]]
  for (const parte of partes.slice(1)) {
    curto.push(parte)
    if (!PARTICULAS.has(parte.toLowerCase())) break
  }
  return curto.join(' ')
}
