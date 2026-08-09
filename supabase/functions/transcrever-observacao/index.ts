// transcrever-observacao — Áudio → texto, e nada mais.
//
// NÃO PERSISTE NADA de propósito: o dado só nasce quando o professor salva o
// texto que ele revisou. Esta função é só uma ponte pro Whisper — sem
// tabela, sem storage, sem log do conteúdo.
//
// PUBLICAR SEMPRE COM verify_jwt ligado (default do CLI sem --no-verify-jwt).

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}

// 25 MB é o teto do próprio endpoint de transcrição da OpenAI.
const LIMITE_BYTES = 25 * 1024 * 1024

// MEDIDO EM 09/08/2026, mandando um AAC/MP4 real (o que o iPhone grava) pra
// esta função em produção:
//
//   bytes mp4 · sem Content-Type · nome "observacao.webm"  -> 502
//   bytes mp4 · sem Content-Type · nome "observacao.m4a"   -> 502
//   bytes mp4 · Content-Type audio/mp4 · nome "...webm"    -> 200, transcreveu
//   bytes mp4 · Content-Type audio/webm (mentindo)          -> 502
//
// Quem manda é o **Content-Type da parte multipart**, NÃO a extensão do nome.
// E nem o `type` nem o nome são confiáveis: um Blob sem type vira
// `application/octet-stream` na travessia multipart (então `if (arquivo.type)`
// nunca enxerga "vazio" do lado do servidor), e um type pode mentir sobre o
// conteúdo.
//
// Os BYTES não mentem. A função identifica o contêiner pela assinatura e
// reembrulha com o tipo verdadeiro. iPhone, Android, cliente com nome errado
// e cliente sem type nenhum caem todos no mesmo caminho certo.

/** Mime a partir da extensão — último recurso, quando os bytes não dizem. */
const MIME_POR_EXT: Record<string, string> = {
  m4a: 'audio/mp4', mp4: 'audio/mp4', aac: 'audio/mp4',
  webm: 'audio/webm', ogg: 'audio/ogg', oga: 'audio/ogg', opus: 'audio/ogg',
  wav: 'audio/wav', flac: 'audio/flac', mp3: 'audio/mpeg', mpeg: 'audio/mpeg',
}

/**
 * Contêiner pela assinatura dos primeiros bytes (magic number).
 * `null` quando não reconhece — aí o palpite volta a ser o `type`/extensão.
 */
async function mimePelosBytes(f: File): Promise<string | null> {
  const b = new Uint8Array(await f.slice(0, 16).arrayBuffer())
  if (b.length < 12) return null
  const txt = (i: number, n: number) =>
    String.fromCharCode(...Array.from(b.slice(i, i + n)))
  if (txt(4, 4) === 'ftyp') return 'audio/mp4'
  if (b[0] === 0x1a && b[1] === 0x45 && b[2] === 0xdf && b[3] === 0xa3)
    return 'audio/webm'
  if (txt(0, 4) === 'OggS') return 'audio/ogg'
  if (txt(0, 4) === 'RIFF') return 'audio/wav'
  if (txt(0, 4) === 'fLaC') return 'audio/flac'
  if (txt(0, 3) === 'ID3') return 'audio/mpeg'
  if (b[0] === 0xff && (b[1] & 0xe0) === 0xe0) return 'audio/mpeg'
  return null
}

/** Extensão a partir do mime. Espelha `src/lib/audio.ts`. */
function extensaoDoMime(mime: string): string {
  const m = (mime || '').toLowerCase()
  if (m.includes('mp4') || m.includes('m4a') || m.includes('aac')) return 'm4a'
  if (m.includes('webm')) return 'webm'
  if (m.includes('ogg') || m.includes('oga') || m.includes('opus')) return 'ogg'
  if (m.includes('wav')) return 'wav'
  if (m.includes('flac')) return 'flac'
  if (m.includes('mpeg') || m.includes('mp3')) return 'mp3'
  return 'webm'
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  try {
    // Revalida o token de verdade contra o Auth — cada chamada gasta crédito
    // real da OPENAI_API_KEY da escola.
    const auth = req.headers.get('Authorization')
    if (!auth) return json({ erro: 'sem_token' }, 401)

    const SB_URL = Deno.env.get('SUPABASE_URL')!
    const ANON = Deno.env.get('SUPABASE_ANON_KEY')!
    const meRes = await fetch(`${SB_URL}/auth/v1/user`, {
      headers: { Authorization: auth, apikey: ANON },
    })
    if (!meRes.ok) return json({ erro: 'sem_token' }, 401)

    const form = await req.formData()
    const arquivo = form.get('audio')
    if (!(arquivo instanceof File)) return json({ erro: 'sem_audio' }, 400)
    if (arquivo.size > LIMITE_BYTES) return json({ erro: 'audio_longo_demais' }, 413)

    // Ordem de confiança: BYTES > `type` declarado > extensão do nome.
    const declarado = (arquivo.type || '').toLowerCase()
    const declaradoServe = declarado.startsWith('audio/') || declarado.startsWith('video/')
    const extDoNome = (arquivo.name.split('.').pop() || '').toLowerCase()
    const mime =
      (await mimePelosBytes(arquivo)) ??
      (declaradoServe ? declarado : (MIME_POR_EXT[extDoNome] || 'audio/mp4'))
    const ext = extensaoDoMime(mime)

    // Reembrulha sempre que o que vai sair difere do que entrou — é o passo
    // que garante o Content-Type certo na parte multipart.
    const corpo = declarado === mime
      ? arquivo
      : new Blob([await arquivo.arrayBuffer()], { type: mime })

    const envio = new FormData()
    envio.append('file', corpo, `observacao.${ext}`)
    envio.append('model', 'whisper-1')
    envio.append('language', 'pt')

    const r = await fetch('https://api.openai.com/v1/audio/transcriptions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${Deno.env.get('OPENAI_API_KEY')}` },
      body: envio,
    })

    if (!r.ok) {
      console.error('[transcrever-observacao] OpenAI falhou:', r.status, (await r.text()).slice(0, 300))
      return json({ erro: 'transcricao_falhou' }, 502)
    }

    const dados = await r.json()
    return json({ texto: dados.text ?? '' })
  } catch (e) {
    console.error('[transcrever-observacao] erro nao tratado:', e)
    return json({ erro: 'indisponivel' }, 500)
  }
})
