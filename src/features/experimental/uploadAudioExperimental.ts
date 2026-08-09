import { supabase } from '../../lib/supabase'
import { enfileirarAudioExperimental } from '../../lib/api'
import { extensaoDoMime } from '../../lib/audio'

const BUCKET = 'fabio-audios'

/** Motivos que a RPC 050 levanta e que a tela sabe explicar. */
export const ERROS_EXPERIMENTAL = [
  'aula_de_outro_professor',
  'aula_cancelada',
  'gravacao_ainda_nao_disponivel',
  'janela_de_gravacao_encerrada',
  'experimental_sem_aula_vinculada',
  'experimental_faltou_nao_tem_registro',
  'experimental_cancelada',
  'sem_professor_vinculado',
] as const
export type ErroExperimental = (typeof ERROS_EXPERIMENTAL)[number]

export type ResultadoEnvioExperimental =
  | { ok: true; audioId: string }
  | { ok: false; motivo: ErroExperimental }
  | { ok: false; motivo: 'rede' }

/**
 * Sobe o áudio da experimental e enfileira.
 *
 * O primeiro nível do path TEM que ser o auth.uid() (é o que a RLS do bucket
 * confere). O segundo é `exp-{vinculoId}` só pra dar pra achar depois olhando
 * o caminho — a RLS não olha pra ele.
 *
 * NÃO TEM FILA OFFLINE, ao contrário da gravação de aula. Se a rede cair, o
 * blob continua na tela e o professor toca em "tentar de novo"; fechar o app
 * perde a gravação. É uma lacuna conhecida: a fila local (`filaOffline`) é
 * modelada por `aulaId` e estender o esquema dela é mexer num caminho que já
 * funciona. Vale fazer quando a experimental sair do piloto.
 */
export async function enviarAudioExperimental(dados: {
  vinculoId: number
  blob: Blob
  mime: string
  duracaoSegundos: number
}): Promise<ResultadoEnvioExperimental> {
  try {
    const { data: sess } = await supabase.auth.getSession()
    const uid = sess.session?.user.id
    if (!uid) return { ok: false, motivo: 'rede' }

    const path = `${uid}/exp-${dados.vinculoId}/${Date.now()}.${extensaoDoMime(dados.mime)}`
    const { error: upErro } = await supabase.storage.from(BUCKET).upload(path, dados.blob, {
      contentType: dados.mime.split(';')[0] || 'audio/webm',
    })
    if (upErro) throw upErro

    const res = await enfileirarAudioExperimental(dados.vinculoId, path, dados.duracaoSegundos)
    return { ok: true, audioId: res.audio_id }
  } catch (e: unknown) {
    const msg = String((e as { message?: string })?.message ?? e)
    const conhecido = ERROS_EXPERIMENTAL.find((c) => msg.includes(c))
    // Erro de validação é PERMANENTE: re-tentar nunca vai passar, e a tela
    // precisa dizer o motivo em vez de oferecer um botão que não resolve.
    return conhecido ? { ok: false, motivo: conhecido } : { ok: false, motivo: 'rede' }
  }
}
