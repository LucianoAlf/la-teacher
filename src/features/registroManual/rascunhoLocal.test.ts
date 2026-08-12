import { describe, expect, it } from 'vitest'
import { chaveCacheManual, normalizarCacheManual } from './rascunhoLocal'

describe('cache de transporte da ficha manual', () => {
  it('isola conta e aula na chave local', () => {
    expect(chaveCacheManual('usuario-a', 123)).toBe('usuario-a:123')
    expect(chaveCacheManual('usuario-b', 123)).not.toBe(chaveCacheManual('usuario-a', 123))
  })

  it('nunca transforma cache local em confirmação canônica', () => {
    const item = normalizarCacheManual({
      id: 'usuario-a:123',
      ownerUserId: 'usuario-a',
      aulaId: 123,
      registroId: 'registro',
      versao: 2,
      troncoCampos: {},
      fatias: [],
      atualizadoEm: '2026-08-12T00:00:00.000Z',
      estado: 'salvo' as never,
    })
    expect(item.estado).toBe('local')
  })
})
