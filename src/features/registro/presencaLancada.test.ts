import { describe, expect, it } from 'vitest'
import { lerPresencaLancada } from './presencaLancada'

describe('presença já lançada na tela de registro', () => {
  it('trava e carimba quando a secretaria já lançou a falta', () => {
    // O caso do Valdo: a secretaria lançou falta antes; o professor não mexe.
    expect(
      lerPresencaLancada({
        presenca_lancada: 'falta',
        presenca_fonte: 'agenda_secretaria',
        presenca_travada: true,
      }),
    ).toEqual({ travada: true, estado: 'faltou', carimbo: 'Lançada pela secretaria' })
  })

  it('trava e carimba quando a presença veio do Emusys', () => {
    expect(
      lerPresencaLancada({
        presenca_lancada: 'presente',
        presenca_fonte: 'emusys',
        presenca_travada: true,
      }),
    ).toEqual({ travada: true, estado: 'presente', carimbo: 'Lançada no Emusys' })
  })

  it('falta justificada aparece como falta, e continua travada', () => {
    expect(
      lerPresencaLancada({
        presenca_lancada: 'falta_justificada',
        presenca_fonte: 'agenda_secretaria',
        presenca_travada: true,
      }),
    ).toEqual({ travada: true, estado: 'faltou', carimbo: 'Lançada pela secretaria' })
  })

  it('não trava quando ninguém lançou — o professor segue podendo marcar', () => {
    expect(lerPresencaLancada({})).toEqual({ travada: false, estado: null, carimbo: null })
  })

  it('não trava com o "ausente" ambíguo do Emusys (a falta fantasma da migração)', () => {
    // O banco já devolve presenca_travada=false nesse caso; a tela respeita.
    expect(
      lerPresencaLancada({
        presenca_lancada: 'falta',
        presenca_fonte: 'emusys',
        presenca_travada: false,
      }),
    ).toEqual({ travada: false, estado: null, carimbo: null })
  })

  it('carimba como do próprio professor quando foi ele que lançou', () => {
    expect(
      lerPresencaLancada({
        presenca_lancada: 'presente',
        presenca_fonte: 'professor_la_teacher',
        presenca_travada: true,
      }),
    ).toEqual({ travada: true, estado: 'presente', carimbo: 'Lançada por você' })
  })
})
