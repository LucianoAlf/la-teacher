import { supabase } from '../../lib/supabase'
import { enfileirarAudio } from '../../lib/api'
import { extensaoDoMime } from './useRecorder'
import { listarFila, removerDaFila, salvarNaFila } from './filaOffline'

const BUCKET = 'fabio-audios'

export interface DadosEnvio {
  aulaId: number
  aulaLabel: string
  blob: Blob
  mime: string
  duracaoSegundos: number
}

export type ResultadoEnvio =
  | { ok: true; audioId: string }
  | { ok: false; guardadoOffline: boolean }

/**
 * Sobe o áudio pro bucket `fabio-audios` e enfileira via app_enfileirar_audio.
 * Path: {auth.uid()}/{aulaId}/{timestamp}.{ext} — o 1º nível TEM que ser o
 * auth.uid() (RLS do bucket). Falhou (rede)? Guarda na fila local (IndexedDB)
 * e o iniciarSincronizacaoFila() reenvia quando a conexão voltar.
 */
export async function enviarAudio(dados: DadosEnvio): Promise<ResultadoEnvio> {
  try {
    const audioId = await subirEEnfileirar(dados)
    return { ok: true, audioId }
  } catch {
    try {
      await salvarNaFila({
        id: `${dados.aulaId}-${Date.now()}`,
        aulaId: dados.aulaId,
        aulaLabel: dados.aulaLabel,
        blob: dados.blob,
        mime: dados.mime,
        duracaoSegundos: dados.duracaoSegundos,
        criadoEm: new Date().toISOString(),
      })
      return { ok: false, guardadoOffline: true }
    } catch {
      return { ok: false, guardadoOffline: false }
    }
  }
}

async function subirEEnfileirar(dados: DadosEnvio): Promise<string> {
  const { data: sess } = await supabase.auth.getSession()
  const uid = sess.session?.user.id
  if (!uid) throw new Error('sem sessão')

  const path = `${uid}/${dados.aulaId}/${Date.now()}.${extensaoDoMime(dados.mime)}`
  const { error: upErro } = await supabase.storage.from(BUCKET).upload(path, dados.blob, {
    contentType: dados.mime.split(';')[0] || 'audio/webm',
  })
  if (upErro) throw upErro

  const res = await enfileirarAudio(dados.aulaId, path, dados.duracaoSegundos)
  return res.audio_id
}

// ---------------------------------------------------------------------------
// Sincronização em background da fila local
// ---------------------------------------------------------------------------

let sincronizando = false
let listenerLigado = false

/** Tenta subir tudo que está na fila local (sequencial; para no 1º erro de rede). */
export async function esvaziarFilaLocal(): Promise<number> {
  if (sincronizando) return 0
  sincronizando = true
  let enviados = 0
  try {
    const itens = await listarFila()
    for (const item of itens.sort((a, b) => a.criadoEm.localeCompare(b.criadoEm))) {
      try {
        await subirEEnfileirar({
          aulaId: item.aulaId,
          aulaLabel: item.aulaLabel,
          blob: item.blob,
          mime: item.mime,
          duracaoSegundos: item.duracaoSegundos,
        })
        await removerDaFila(item.id)
        enviados++
      } catch {
        break // ainda sem rede — tenta de novo no próximo 'online'
      }
    }
  } finally {
    sincronizando = false
  }
  return enviados
}

/**
 * Liga o reenvio automático (idempotente): tenta agora e a cada evento
 * 'online'. Chamado uma vez na área autenticada do app.
 */
export function iniciarSincronizacaoFila(): void {
  if (listenerLigado) return
  listenerLigado = true
  window.addEventListener('online', () => void esvaziarFilaLocal())
  void esvaziarFilaLocal()
}
