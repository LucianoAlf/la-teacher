// Gera a narração do vídeo com a VOZ DO FÁBIO, com cache por hash do texto.
// Adaptado do estúdio do TOM (D:\la-organizer\video-studio) — mesmo motor, outra voz.
// Rodar: node scripts/gen-narration.mjs
//
// Settings de voz: as MESMAS do TOM (homologadas). O que faltava no meu 1º teste e
// deixava a fala robótica/arrastada: `use_speaker_boost` e `speed: 1.05`.
import { readFileSync, writeFileSync, mkdirSync, readdirSync, unlinkSync, existsSync, renameSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { spawnSync } from 'node:child_process'
import { planFiles, audioFileName } from './narration-lib.mjs'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')

const VOICE_ID = process.env.ELEVENLABS_VOICE_ID || 'n5v3Z2TRRdx6ixolQQMW' // voz do Fábio (criada pelo Alf)
const MODEL_ID = 'eleven_multilingual_v2'

// Qual vídeo gerar: node scripts/gen-narration.mjs [--video teaser-efeitos --roteiro video/roteiroTeaser.ts]
const argv = process.argv.slice(2)
const arg = (nome, padrao) => {
  const i = argv.indexOf(nome)
  return i >= 0 && argv[i + 1] ? argv[i + 1] : padrao
}
const VIDEO_ID = arg('--video', 'onboarding-professor')
const ROTEIRO_PATH = arg('--roteiro', 'video/roteiro.ts')

function loadEnv() {
  const envPath = resolve(root, '.env')
  if (!existsSync(envPath)) { console.error('sem .env'); process.exit(1) }
  for (const line of readFileSync(envPath, 'utf-8').split('\n')) {
    const m = line.match(/^([A-Z0-9_]+)=(.*)$/)
    if (m) process.env[m[1]] = m[2].trim()
  }
}

/** O roteiro vive num .ts; aqui lemos os campos sem compilar TS. */
function lerRoteiro() {
  const src = readFileSync(resolve(root, ROTEIRO_PATH), 'utf-8')
  const cenas = []
  const re = /\{\s*id:\s*'([^']+)'[\s\S]*?narracao:\s*'((?:[^'\\]|\\.)*)'/g
  let m
  while ((m = re.exec(src))) cenas.push({ id: m[1], narracao: m[2].replace(/\\'/g, "'") })
  return cenas
}

const cenas = lerRoteiro()
const ids = cenas.map(c => c.id)
if (new Set(ids).size !== ids.length) { console.error('ids duplicados no roteiro'); process.exit(1) }
loadEnv()
const API_KEY = process.env.ELEVENLABS_API_KEY
if (!API_KEY) { console.error('ELEVENLABS_API_KEY ausente no .env'); process.exit(1) }

const audioDir = resolve(root, 'public', 'audio', VIDEO_ID)
mkdirSync(audioDir, { recursive: true })
const existing = readdirSync(audioDir).filter(f => f.endsWith('.mp3'))
const plan = planFiles(cenas, existing)
console.log(`cache: ${plan.keep.length} mantidos · ${plan.generate.length} a gerar · ${plan.stale.length} obsoletos`)
for (const f of plan.stale) unlinkSync(resolve(audioDir, f))

/**
 * A ElevenLabs entrega o MP3 terminando no ÚLTIMO SOM — sem decaimento, o que
 * soa como palavra cortada (11 dos 20 áudios do 1º corte, flagrado pelo Alf).
 * Receita: pedir uma pausa no fim (`<break>`, suportada pelo multilingual_v2)
 * pra voz completar a palavra, e depois aparar o silêncio sobrando pra CAUDA_S.
 */
const BREAK_FINAL = ' <break time="0.8s" />'
// 0,6s: com 0,35 sobravam só ~0,2s de cauda audível em algumas falas — perto
// demais do limite pra arriscar "palavra comida". Folga custa nada.
const CAUDA_S = 0.6

// O ffmpeg escreve TUDO (duração, silencedetect) em stderr — por isso spawnSync
// com stderr capturado, e não execFileSync (que devolve só o stdout, vazio).
const ffmpeg = (args) => {
  const r = spawnSync('npx', ['remotion', 'ffmpeg', ...args], {
    encoding: 'utf-8',
    shell: true,
  })
  return `${r.stdout ?? ''}${r.stderr ?? ''}`
}

/**
 * Onde a fala termina: início do silêncio FINAL — o que vai até o fim do arquivo.
 * ⚠️ Não basta pegar o último `silence_start`: se o arquivo terminar seco (sem
 * pausa no fim), o último silêncio é uma pausa NO MEIO da frase — cortar ali
 * decepa a narração (aconteceu com a cena "gravar": 6,3s viraram 2,1s).
 * Só existe cauda quando o último silêncio não fecha antes do fim.
 */
function fimDaFala(caminho, limiar) {
  const saida = ffmpeg(['-i', caminho, '-vn', '-af', `silencedetect=n=${limiar}dB:d=0.12`, '-f', 'null', '-'])
  const dur = saida.match(/Duration: 00:00:(\d+\.\d+)/)
  const duracao = dur ? Number(dur[1]) : null
  const inicios = [...saida.matchAll(/silence_start: ([\d.]+)/g)].map((m) => Number(m[1]))
  const fins = [...saida.matchAll(/silence_end: ([\d.]+)/g)].map((m) => Number(m[1]))
  if (duracao == null || !inicios.length) return { duracao, cauda: null }
  const ultimoInicio = Math.max(...inicios)
  const ultimoFim = fins.length ? Math.max(...fins) : -1
  // silêncio aberto (sem fim) OU fechando junto com o arquivo = é a cauda
  const ehCauda = inicios.length > fins.length || ultimoFim >= duracao - 0.06
  return { duracao, cauda: ehCauda ? ultimoInicio : null }
}

// A pausa que eu peço no fim rende no máximo ~1,8s de rabo. Nunca cortar antes
// disso — é a trava que impede o corte de decepar frase (bug da v2).
const MAX_CAUDA_S = 2.2

/** Corta o excesso de silêncio do fim, deixando exatamente CAUDA_S. */
function ajustarCauda(caminho) {
  // -45dB pega silêncio limpo; se a cauda tiver ruído de sala, -38dB acha —
  // e a trava MAX_CAUDA_S garante que só o rabo é cortado, nunca a fala.
  let { duracao, cauda } = fimDaFala(caminho, -45)
  if (duracao == null) return null
  if (cauda == null || cauda < duracao - MAX_CAUDA_S) {
    const brando = fimDaFala(caminho, -38)
    cauda = brando.cauda != null && brando.cauda >= duracao - MAX_CAUDA_S ? brando.cauda : null
  }
  if (cauda == null) {
    console.warn(`  ⚠️ ${caminho.split(/[\\/]/).pop()}: sem cauda detectável — NÃO cortei`)
    return duracao
  }
  const alvo = cauda + CAUDA_S
  if (alvo >= duracao - 0.05) return duracao // já está curta: não mexe
  const tmp = `${caminho}.tmp.mp3`
  ffmpeg(['-y', '-i', caminho, '-t', alvo.toFixed(3), '-c:a', 'libmp3lame', '-b:a', '128k', tmp])
  unlinkSync(caminho)
  renameSync(tmp, caminho)
  return alvo
}

// `--aparar`: só normaliza a cauda dos MP3 que já existem (sem gastar API).
if (argv.includes('--aparar')) {
  for (const f of plan.keep) {
    const alvo = ajustarCauda(resolve(audioDir, f))
    console.log(`aparado: ${f} → ${alvo ? `${alvo.toFixed(2)}s` : 'sem ajuste'}`)
  }
}

for (const g of plan.generate) {
  const res = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${VOICE_ID}`, {
    method: 'POST',
    headers: { 'xi-api-key': API_KEY, 'Content-Type': 'application/json', Accept: 'audio/mpeg' },
    body: JSON.stringify({
      text: g.narracao + BREAK_FINAL,
      model_id: MODEL_ID,
      voice_settings: { stability: 0.5, similarity_boost: 0.75, style: 0.4, use_speaker_boost: true, speed: 1.05 },
    }),
  })
  if (!res.ok) { console.error(`HTTP ${res.status} na cena ${g.id}:`, (await res.text()).slice(0, 200)); process.exit(1) }
  const buf = Buffer.from(await res.arrayBuffer())
  const caminho = resolve(audioDir, g.file)
  writeFileSync(caminho, buf)
  const final = ajustarCauda(caminho)
  console.log(`gerado: ${g.file} (${(buf.length / 1024).toFixed(0)} KB → ${final ? `${final.toFixed(2)}s` : 'sem ajuste'})`)
}

writeFileSync(
  resolve(audioDir, 'manifest.json'),
  JSON.stringify(Object.fromEntries(cenas.map(c => [c.id, audioFileName(c.id, c.narracao)])), null, 2),
)
console.log('manifest.json escrito com', cenas.length, 'cenas')
