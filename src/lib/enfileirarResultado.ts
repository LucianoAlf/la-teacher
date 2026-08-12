export type StatusFilaResultado = 'pendente' | 'transcrevendo' | 'transcrito' | 'normalizado' | 'erro' | 'erro_terminal'

export interface ResultadoEnfileirado {
  audio_id: string | null
  status: StatusFilaResultado | null
  modo: 'novo' | 'complementar'
  registro_id: string | null
  ja_em_processamento?: boolean
  rascunho_existente?: boolean
  deduplicado?: boolean
}

const UUID_PADRAO = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

function uuidObrigatorio(valor: unknown): string | null {
  return typeof valor === 'string' && UUID_PADRAO.test(valor) ? valor : null
}

function statusFilaValido(valor: unknown): valor is StatusFilaResultado {
  return valor === 'pendente' || valor === 'transcrevendo' || valor === 'transcrito' || valor === 'normalizado' || valor === 'erro' || valor === 'erro_terminal'
}

/** Rejeita contrato incompleto antes que o upload local seja descartado. */
export function lerResultadoEnfileirar(res: unknown): ResultadoEnfileirado {
  if (!res || typeof res !== 'object' || Array.isArray(res)) throw new Error('Resposta inválida ao enfileirar o áudio')
  const bruto = res as Record<string, unknown>
  const modo = bruto.modo
  if (modo !== 'novo' && modo !== 'complementar') throw new Error('Resposta inválida ao enfileirar o áudio')
  const audioId = uuidObrigatorio(bruto.audio_id)
  const registroId = uuidObrigatorio(bruto.registro_id)
  if (bruto.rascunho_existente === true && registroId) {
    if ((bruto.audio_id !== undefined && bruto.audio_id !== null) || (bruto.status !== undefined && bruto.status !== null)) {
      throw new Error('Resposta invÃ¡lida ao enfileirar o Ã¡udio')
    }
    return { audio_id: null, status: null, modo, registro_id: registroId, rascunho_existente: true }
  }
  if (!audioId || !statusFilaValido(bruto.status)) throw new Error('Resposta inválida ao enfileirar o áudio')
  return {
    audio_id: audioId,
    status: bruto.status,
    modo,
    registro_id: registroId,
    ja_em_processamento: bruto.ja_em_processamento === true,
    deduplicado: bruto.deduplicado === true,
  }
}
