// transcrever-observacao — Áudio → texto, e nada mais.
//
// NÃO PERSISTE NADA de propósito: o dado só nasce quando o professor salva o
// texto que ele revisou. Guardar o áudio (ou o texto cru) criaria uma segunda
// cópia da observação, fora da fronteira que a 074 fechou. Esta função é só
// uma ponte pro Whisper — sem tabela, sem storage, sem log do conteúdo.
//
// NOME: chamava-se `transcrever-audio` até 09/08 — sobrescreveu, no projeto
// Supabase COMPARTILHADO, a função homônima do LA Report (que transcreve
// áudio de WhatsApp via UAZAPI pro pré-atendimento, existia desde 13/02).
// Renomeada pra não colidir de novo. Antes de nomear função neste projeto,
// `list_edge_functions` (MCP) ou `npx supabase functions list` — não só
// `git grep` neste repo, o projeto é maior que este repo.
//
// PUBLICAR SEMPRE SEM a flag `--no-verify-jwt` (ou seja, COM verify_jwt
// ligado — é o default do CLI quando a flag não é passada):
//   npx supabase functions deploy transcrever-observacao --project-ref ouqwbbermlzqqvtqwlul
// A checagem de identidade abaixo (revalida o token no /auth/v1/user) é a
// SEGUNDA camada, não a única — sem a primeira (o gate da plataforma), um
// `Bearer qualquercoisa` só seria barrado depois de já ter entrado na função.

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

// 25 MB é o teto do próprio endpoint de transcrição da OpenAI — abaixo disso
// não adianta recusar aqui, e acima disso não adianta encaminhar. O gravador
// já para sozinho em 5 minutos (LIMITE_SEGUNDOS): 5 min de AAC do iPhone dá
// ~5 MB, de webm/opus dá ~1,2 MB. O limite antigo (8 MB) descrevia "~2
// minutos de webm/opus" e podia recusar uma gravação legítima de iPhone.
const LIMITE_BYTES = 25 * 1024 * 1024

/**
 * Extensão a partir do mime — o Whisper escolhe o decoder pela EXTENSÃO do
 * arquivo, não pelo Content-Type. iOS/Safari grava `audio/mp4`; mandar isso
 * como `.webm` (que era o nome cravado aqui) falha em 100% dos iPhones.
 *
 * Deriva do mime do arquivo recebido, não do nome que o cliente mandou: um
 * cliente que erre o nome continua funcionando. Espelha
 * `src/lib/audio.ts` — os dois lados precisam concordar.
 */
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
    // Critical da revisão: antes só se checava que o header EXISTIA —
    // `Bearer qualquercoisa` passava, e cada chamada gasta crédito real da
    // OPENAI_API_KEY da escola. Mesmo padrão de coordenacao-recado e
    // professor-liberar-acesso: revalida o token de verdade contra o Auth,
    // com a apikey anon — só um JWT que o Supabase reconhece passa daqui.
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

    // O mime do File vem do blob que o MediaRecorder produziu, então ele diz
    // a verdade sobre o container. Se vier vazio (browser exótico), o nome
    // que o cliente mandou é o segundo palpite.
    const ext = arquivo.type
      ? extensaoDoMime(arquivo.type)
      : (arquivo.name.split('.').pop() || 'webm').toLowerCase()

    const envio = new FormData()
    envio.append('file', arquivo, `observacao.${ext}`)
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
