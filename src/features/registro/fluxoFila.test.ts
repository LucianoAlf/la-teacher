import { describe, expect, it } from 'vitest'
import { destinoAceiteFila, estadoProcessamento, pollingAtivo, rotuloPendencia } from './fluxoFila'

describe('fluxo autoritativo da fila de audio', () => {
  it('abre o rascunho existente em vez de iniciar outra gravacao', () => {
    expect(destinoAceiteFila({ audio_id: null, status: null, modo: 'novo', registro_id: 'registro-1', rascunho_existente: true })).toEqual({ tela: 'confirmar', registroId: 'registro-1' })
  })

  it('acompanha tanto a nova fila como a fila ja em processamento', () => {
    expect(destinoAceiteFila({ audio_id: 'audio-1', status: 'pendente', modo: 'novo', registro_id: null, ja_em_processamento: true })).toEqual({ tela: 'processando', audioId: 'audio-1' })
  })

  it('nao considera erro historico como falha atual', () => {
    expect(estadoProcessamento({ status: 'normalizado', temErro: false })).toBe('andamento')
    expect(estadoProcessamento({ status: 'erro', temErro: true })).toBe('erro_recuperavel')
    expect(estadoProcessamento({ status: 'erro_terminal', temErro: false })).toBe('erro_terminal')
  })

  it('rotula pendencias somente com contexto textual ja presente', () => {
    expect(rotuloPendencia({ turma: 'Bateria', horario: '15:00' })).toBe('Bateria · 15:00')
    expect(rotuloPendencia({ curso: 'Piano', hora: '16:00' })).toBe('Piano · 16:00')
    expect(rotuloPendencia({ turma: '123', aula_id: 42 })).toBe('Rascunho de aula')
    expect(rotuloPendencia({ turma: 'aulaId=42' })).toBe('Rascunho de aula')
    expect(rotuloPendencia({ curso: 'Bateria', hora: 'registroId=42' })).toBe('Bateria')
    expect(rotuloPendencia({ turma: '550e8400-e29b-41d4-a716-446655440000', horario: '15:00' })).toBe('Aula · 15:00')
    expect(rotuloPendencia({ turma: 'aula_id=42', horario: '15:00' })).toBe('Aula · 15:00')
  })

  it('nao permite efeito do polling depois que a tela foi desmontada ou navegou', () => {
    expect(pollingAtivo(false, false)).toBe(true)
    expect(pollingAtivo(true, false)).toBe(false)
    expect(pollingAtivo(false, true)).toBe(false)
  })
})
