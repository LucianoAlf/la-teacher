import type { EnfileirarResultado, StatusFila } from '../../lib/api'

/** Destino somente depois de uma aceitação autoritativa da RPC. */
export type DestinoAceiteFila =
  | { tela: 'confirmar'; registroId: string }
  | { tela: 'processando'; audioId: string }

/** A UI apenas retoma o áudio ou rascunho que a RPC devolveu. */
export function destinoAceiteFila(resultado: EnfileirarResultado): DestinoAceiteFila | null {
  if (resultado.rascunho_existente && resultado.registro_id) return { tela: 'confirmar', registroId: resultado.registro_id }
  if (resultado.audio_id) return { tela: 'processando', audioId: resultado.audio_id }
  return null
}

export type EstadoProcessamento = 'andamento' | 'erro_recuperavel' | 'erro_terminal'

/** Evita efeitos tardios quando a tela deixou de acompanhar a fila. */
export function pollingAtivo(parar: boolean, jaNavegou: boolean): boolean {
  return !parar && !jaNavegou
}

/** Erro histórico só importa se o status atual ainda for `erro`. */
export function estadoProcessamento({
  status,
  temErro,
  tentativas,
}: {
  status: StatusFila
  temErro: boolean
  tentativas: number
}): EstadoProcessamento {
  if (status === 'erro_terminal') return 'erro_terminal'
  if (status === 'erro' && temErro && tentativas >= 3) return 'erro_terminal'
  if (status === 'erro' && temErro) return 'erro_recuperavel'
  return 'andamento'
}

function textoHumano(valor: unknown): string | null {
  if (typeof valor !== 'string') return null
  const limpo = valor.trim().replace(/\s+/g, ' ')
  const pareceUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(limpo)
  const pareceIdentificadorTecnico = /(?:^|[_-])(id|uuid|aula|registro|audio)(?:id)?(?:[_=-]|$)/i.test(limpo)
  if (!limpo || /^\d+$/.test(limpo) || pareceUuid || pareceIdentificadorTecnico) return null
  return limpo
}

/** Rótulo conservador: só usa contexto textual que a RPC já devolveu. */
export function rotuloPendencia(campos: Record<string, unknown> | null | undefined): string {
  const dados = campos ?? {}
  const turma = textoHumano(dados.turma) ?? textoHumano(dados.curso)
  const horario = textoHumano(dados.hora) ?? textoHumano(dados.horario) ?? textoHumano(dados.horario_aula)
  if (turma && horario) return `${turma} · ${horario}`
  if (turma) return turma
  if (horario) return `Aula · ${horario}`
  return 'Rascunho de aula'
}
