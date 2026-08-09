// transcrever-audio — Áudio → texto, e nada mais.
//
// NÃO PERSISTE NADA de propósito: o dado só nasce quando o professor salva o
// texto que ele revisou. Guardar o áudio (ou o texto cru) criaria uma segunda
// cópia da observação, fora da fronteira que a 074 fechou. Esta função é só
// uma ponte pro Whisper — sem tabela, sem storage, sem log do conteúdo.

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

const LIMITE_BYTES = 8 * 1024 * 1024 // ~2 minutos de webm/opus

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  try {
    // Este projeto roda com verify_jwt desligado (mesmo padrão de
    // coordenacao-recado e professor-liberar-acesso: confirmado por teste
    // direto — POST sem header chega aqui, não é barrado pela plataforma
    // antes). Por isso a checagem de presença do token é a ÚNICA porta.
    const auth = req.headers.get('Authorization')
    if (!auth) return json({ erro: 'sem_token' }, 401)

    const form = await req.formData()
    const arquivo = form.get('audio')
    if (!(arquivo instanceof File)) return json({ erro: 'sem_audio' }, 400)
    if (arquivo.size > LIMITE_BYTES) return json({ erro: 'audio_longo_demais' }, 413)

    const envio = new FormData()
    envio.append('file', arquivo, 'observacao.webm')
    envio.append('model', 'whisper-1')
    envio.append('language', 'pt')

    const r = await fetch('https://api.openai.com/v1/audio/transcriptions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${Deno.env.get('OPENAI_API_KEY')}` },
      body: envio,
    })

    if (!r.ok) {
      console.error('[transcrever-audio] OpenAI falhou:', r.status, (await r.text()).slice(0, 300))
      return json({ erro: 'transcricao_falhou' }, 502)
    }

    const dados = await r.json()
    return json({ texto: dados.text ?? '' })
  } catch (e) {
    console.error('[transcrever-audio] erro nao tratado:', e)
    return json({ erro: 'indisponivel' }, 500)
  }
})
