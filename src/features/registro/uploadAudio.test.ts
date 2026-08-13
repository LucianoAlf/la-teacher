import { describe, expect, it, vi } from 'vitest'

vi.mock('../../lib/supabase', () => ({
  supabase: {
    auth: { getSession: vi.fn() },
    storage: { from: vi.fn() },
    rpc: vi.fn(),
  },
}))
import { retryAutomaticoPermitido } from './camposCanonicos'
import { estadoTerminalFila, itemPodeSerReenviado, normalizarDestinoFila } from './filaOffline'
import {
  classificarFalhaFila,
  criarItemFilaLocal,
  destinoRetomadaFila,
  enfileirarDestinoFila,
} from './uploadAudio'

const blob = new Blob(['audio de teste'], { type: 'audio/webm' })

function itemExperimental() {
  return criarItemFilaLocal({
    id: 'item-experimental',
    ownerUserId: 'professor-1',
    aulaLabel: 'Experimental',
    blob,
    mime: 'audio/webm',
    duracaoSegundos: 12,
    chaveIntencao: 'intencao-estavel',
    destino: { tipo: 'experimental', vinculoId: 42 },
  })
}

function itemAulaComplementar() {
  return criarItemFilaLocal({
    id: 'item-aula',
    ownerUserId: 'professor-1',
    aulaLabel: 'Piano · Ana',
    blob,
    mime: 'audio/webm',
    duracaoSegundos: 18,
    chaveIntencao: 'intencao-aula',
    destino: { tipo: 'aula', aulaId: 77, registroId: 'registro-complementar' },
  })
}

describe('fila durável para áudio experimental', () => {
  it('persiste o destino experimental com um path estável antes do envio', () => {
    const item = itemExperimental()

    expect(item.destino).toEqual({ tipo: 'experimental', vinculoId: 42 })
    expect(item.storagePath).toBe('professor-1/exp-42/intencao-estavel.webm')
  })

  it('encaminha o replay experimental somente para a RPC experimental', async () => {
    const enfileirarAula = vi.fn()
    const enfileirarExperimental = vi.fn().mockResolvedValue({
      audio_id: 'audio-experimental-1',
      status: 'pendente',
      vinculo_id: 42,
    })

    await expect(enfileirarDestinoFila(itemExperimental(), { enfileirarAula, enfileirarExperimental })).resolves.toEqual({
      tipo: 'experimental',
      audioId: 'audio-experimental-1',
      vinculoId: 42,
    })
    expect(enfileirarExperimental).toHaveBeenCalledWith(42, 'professor-1/exp-42/intencao-estavel.webm', 12)
    expect(enfileirarAula).not.toHaveBeenCalled()
  })

  it('preserva o complemento da aula comum e não chama a porta experimental', async () => {
    const enfileirarAula = vi.fn().mockResolvedValue({
      audio_id: 'audio-aula-1', status: 'pendente', modo: 'complementar', registro_id: 'registro-complementar',
    })
    const enfileirarExperimental = vi.fn()

    await expect(enfileirarDestinoFila(itemAulaComplementar(), { enfileirarAula, enfileirarExperimental })).resolves.toEqual({
      tipo: 'aula',
      resultado: { audio_id: 'audio-aula-1', status: 'pendente', modo: 'complementar', registro_id: 'registro-complementar' },
    })
    expect(enfileirarAula).toHaveBeenCalledWith(77, 'professor-1/77/intencao-aula.webm', 18, 'registro-complementar')
    expect(enfileirarExperimental).not.toHaveBeenCalled()
  })

  it('mantém falha de transporte experimental recuperável', () => {
    const falha = classificarFalhaFila(itemExperimental(), new TypeError('Failed to fetch'))

    expect(falha).toEqual({ tipo: 'transitoria' })
    expect(retryAutomaticoPermitido({ transitoria: falha.tipo === 'transitoria', tentativas: 1 })).toBe(true)
    expect(itemPodeSerReenviado({ falhaTerminal: false })).toBe(true)
  })

  it('marca recusa semântica experimental como terminal, sem retry automático', () => {
    const falha = classificarFalhaFila(itemExperimental(), new Error('experimental_cancelada'))
    if (falha.tipo !== 'terminal') throw new Error('A recusa semântica precisa ser terminal')
    const estado = estadoTerminalFila({
      codigo: falha.codigo,
      mensagem: 'experimental_cancelada',
      tentativas: 0,
    })

    expect(falha).toEqual({ tipo: 'terminal', codigo: 'experimental_cancelada' })
    expect(estado.retryAutomatico).toBe(false)
    expect(itemPodeSerReenviado(estado)).toBe(false)
  })

  it('lê item legado sem destino como aula, nunca como experimental', () => {
    expect(normalizarDestinoFila(undefined, 77, 'registro-legado')).toEqual({
      tipo: 'aula',
      aulaId: 77,
      registroId: 'registro-legado',
    })
  })

  it('não adivinha experimental para item legado sem aula', () => {
    expect(normalizarDestinoFila(undefined, undefined, null)).toBeNull()
  })

  it('retoma a ficha experimental após aceite, sem destino da aula comum', () => {
    expect(destinoRetomadaFila({ tipo: 'experimental', audioId: 'audio-experimental-1', vinculoId: 42 })).toEqual({
      tela: 'experimental',
      audioId: 'audio-experimental-1',
      vinculoId: 42,
    })
  })
})
