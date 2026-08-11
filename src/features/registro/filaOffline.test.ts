import { describe, expect, it } from 'vitest'
import { estadoTerminalFila, itemPodeSerReenviado } from './filaOffline'

describe('estado terminal da fila local', () => {
  it('preserva a causa semântica e bloqueia qualquer novo reenvio', () => {
    const estado = estadoTerminalFila({
      codigo: 'aula_cancelada',
      mensagem: 'aula_cancelada',
      tentativas: 2,
    })

    expect(estado).toEqual({
      codigoFalhaTerminal: 'aula_cancelada',
      falhaTerminal: true,
      retryAutomatico: false,
      tentativas: 3,
      ultimaFalha: 'aula_cancelada',
    })
    expect(itemPodeSerReenviado(estado)).toBe(false)
  })
})
