import { describe, expect, it } from 'vitest'
import { lerResultadoEnfileirar } from './enfileirarResultado'

describe('lerResultadoEnfileirar', () => {
  const audioId = '550e8400-e29b-41d4-a716-446655440000'
  const registroId = '6ba7b810-9dad-11d1-80b4-00c04fd430c8'

  it('rejeita audio_id que nao seja UUID antes de descartar o blob local', () => {
    expect(() => lerResultadoEnfileirar({
      audio_id: 'x',
      status: 'pendente',
      modo: 'novo',
      registro_id: null,
    })).toThrow('Resposta inv')
  })

  it('rejeita registro_id invalido no reaproveitamento de rascunho', () => {
    expect(() => lerResultadoEnfileirar({
      audio_id: null,
      status: null,
      modo: 'novo',
      registro_id: 'rascunho-1',
      rascunho_existente: true,
    })).toThrow('Resposta inv')
  })

  it('rejeita rascunho com campos de fila contraditorios', () => {
    expect(() => lerResultadoEnfileirar({
      audio_id: 'nao-e-um-audio',
      status: 'pendente',
      modo: 'novo',
      registro_id: registroId,
      rascunho_existente: true,
    })).toThrow('Resposta inv')
  })

  it('aceita UUIDs validos para fila e rascunho', () => {
    expect(lerResultadoEnfileirar({
      audio_id: audioId,
      status: 'pendente',
      modo: 'novo',
      registro_id: null,
    })).toMatchObject({ audio_id: audioId })

    expect(lerResultadoEnfileirar({
      audio_id: null,
      status: null,
      modo: 'novo',
      registro_id: registroId,
      rascunho_existente: true,
    })).toMatchObject({ registro_id: registroId, rascunho_existente: true })
  })
})
