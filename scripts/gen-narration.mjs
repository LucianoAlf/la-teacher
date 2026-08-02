// Gera a narração do vídeo com a VOZ DO FÁBIO, com cache por hash do texto.
// Adaptado do estúdio do TOM (D:\la-organizer\video-studio) — mesmo motor, outra voz.
// Rodar: node scripts/gen-narration.mjs
//
// Settings de voz: as MESMAS do TOM (homologadas). O que faltava no meu 1º teste e
// deixava a fala robótica/arrastada: `use_speaker_boost` e `speed: 1.05`.
import { readFileSync, writeFileSync, mkdirSync, readdirSync, unlinkSync, existsSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
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

for (const g of plan.generate) {
  const res = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${VOICE_ID}`, {
    method: 'POST',
    headers: { 'xi-api-key': API_KEY, 'Content-Type': 'application/json', Accept: 'audio/mpeg' },
    body: JSON.stringify({
      text: g.narracao,
      model_id: MODEL_ID,
      voice_settings: { stability: 0.5, similarity_boost: 0.75, style: 0.4, use_speaker_boost: true, speed: 1.05 },
    }),
  })
  if (!res.ok) { console.error(`HTTP ${res.status} na cena ${g.id}:`, (await res.text()).slice(0, 200)); process.exit(1) }
  const buf = Buffer.from(await res.arrayBuffer())
  writeFileSync(resolve(audioDir, g.file), buf)
  console.log(`gerado: ${g.file} (${(buf.length / 1024).toFixed(0)} KB)`)
}

writeFileSync(
  resolve(audioDir, 'manifest.json'),
  JSON.stringify(Object.fromEntries(cenas.map(c => [c.id, audioFileName(c.id, c.narracao)])), null, 2),
)
console.log('manifest.json escrito com', cenas.length, 'cenas')
