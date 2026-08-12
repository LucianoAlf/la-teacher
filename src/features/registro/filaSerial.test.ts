import { describe, expect, it, vi } from 'vitest'
import { continuarFila } from './filaSerial'

describe('fila serial recuperavel', () => {
  it('executa uma nova tentativa depois de a anterior falhar', async () => {
    const novaTentativa = vi.fn().mockResolvedValue('salvo')
    const anterior = Promise.reject(new Error('rede indisponivel'))

    await expect(continuarFila(anterior, novaTentativa)).resolves.toBe('salvo')
    expect(novaTentativa).toHaveBeenCalledOnce()
  })

  it('executa a proxima tentativa mesmo quando a cauda anterior resolveu false', async () => {
    const novaTentativa = vi.fn().mockResolvedValue(true)

    await expect(continuarFila(Promise.resolve(false), novaTentativa)).resolves.toBe(true)
    expect(novaTentativa).toHaveBeenCalledOnce()
  })
})
