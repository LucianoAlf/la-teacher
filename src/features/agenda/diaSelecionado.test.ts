import { describe, expect, it } from 'vitest'
import { diaDaUrl } from './diaSelecionado'

/**
 * Bug do Isaque (17/08/2026, gravado em vídeo): ele navegou pro sábado 15/08,
 * abriu uma aula, e ao tocar em voltar a agenda reapareceu em HOJE (segunda,
 * 17/08). Pra conferir a aula seguinte ele tinha que percorrer o calendário de
 * novo — a cada aula.
 *
 * A causa era `useState(hojeBRT())` na Agenda: o dia escolhido só existia na
 * memória daquele componente. `navigate(-1)` remonta a tela, o estado renasce
 * com o valor inicial, e o sábado some. Levar o dia pra URL faz o voltar, o
 * refresh e o histórico do navegador funcionarem sem código nenhum de memória.
 *
 * Esta função é o pedaço decidível: dado o que veio na URL, que dia mostrar.
 */
describe('diaDaUrl', () => {
  const HOJE = '2026-08-17'

  it('sem parâmetro na URL, mostra hoje', () => {
    expect(diaDaUrl(null, HOJE)).toBe(HOJE)
    expect(diaDaUrl('', HOJE)).toBe(HOJE)
  })

  it('preserva o dia que o professor estava vendo', () => {
    // O caso do Isaque: sábado 15/08 tem que sobreviver ao voltar.
    expect(diaDaUrl('2026-08-15', HOJE)).toBe('2026-08-15')
  })

  it('aceita dia futuro e de outro ano', () => {
    expect(diaDaUrl('2027-01-31', HOJE)).toBe('2027-01-31')
  })

  it('lixo na URL não quebra a tela: cai em hoje', () => {
    // URL é editável pelo usuário e sobrevive a link colado errado. Nenhuma
    // dessas formas pode virar tela quebrada nem dia sem sentido.
    for (const ruim of ['ontem', '15/08/2026', '2026-8-5', '20260815', '2026-08']) {
      expect(diaDaUrl(ruim, HOJE)).toBe(HOJE)
    }
  })

  it('data impossível não é aceita só por ter o formato certo', () => {
    // 31 de fevereiro casa com o formato e NÃO existe: o JS "corrigiria" pra
    // 03/03 silenciosamente, e o professor veria um dia que ele não pediu.
    expect(diaDaUrl('2026-02-31', HOJE)).toBe(HOJE)
    expect(diaDaUrl('2026-13-01', HOJE)).toBe(HOJE)
    expect(diaDaUrl('2026-00-10', HOJE)).toBe(HOJE)
  })
})
