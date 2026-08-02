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
// turbo_v2_5 (pedido do Alf): fala mais pausada que o multilingual_v2, que
// atropelava (3,6 palavras/s contra 3,05). Medido na mesma frase, mesma voz.
const MODEL_ID = process.env.ELEVENLABS_MODEL_ID || 'eleven_turbo_v2_5'

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
// Trava contra leitura silenciosamente errada: o regex casa `narracao:` seguido
// da string, e um comentário no meio faz a cena inteira ser pulada — a fala
// seguinte é colada na cena errada e ninguém percebe. Conta os ids do arquivo.
const idsNoArquivo = (readFileSync(resolve(root, ROTEIRO_PATH), 'utf-8').match(/^\s*id:\s*'/gm) || []).length
if (idsNoArquivo !== cenas.length) {
  console.error(`roteiro tem ${idsNoArquivo} cenas mas li ${cenas.length} — comentário entre 'narracao:' e o texto?`)
  process.exit(1)
}
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
 * CAUDA DO ÁUDIO — nunca mais mexer no texto enviado à API.
 *
 * A ElevenLabs entrega o MP3 terminando no último som, o que soa como palavra
 * comida. Minha 1ª receita anexava `<break time="0.8s" />` ao texto: o modelo
 * VOCALIZOU a tag em várias falas e o resultado virou "um ET falando língua
 * esquisita" (palavras do Alf). Sintoma mensurável: a velocidade caiu de ~3,3
 * pra ~2,0 palavras/s — som que não é palavra.
 *
 * Agora o texto vai PURO e o silêncio é acrescentado DEPOIS, por ffmpeg
 * (`apad`), que é silêncio digital e não pode contaminar a voz.
 */
const CAUDA_S = 0.5

const VOZ = { stability: 0.5, similarity_boost: 0.75, style: 0.4, use_speaker_boost: true, speed: 1.05 }

/**
 * Ajuste fino por cena. `stability` baixa deixa a voz expressiva mas às vezes
 * sai PICOTADA (micro-pausas a cada palavra) — soa estranho mesmo sem ruído.
 * Subir a estabilidade nessa cena resolve sem mudar a voz das outras.
 */
const AJUSTE_POR_CENA = {
  semana: { stability: 0.8, style: 0.25 },
}

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

/** Acrescenta CAUDA_S de silêncio DIGITAL no fim. Não toca na fala. */
function ajustarCauda(caminho) {
  const { duracao } = fimDaFala(caminho, -45)
  if (duracao == null) return null
  const alvo = duracao + CAUDA_S
  const tmp = `${caminho}.tmp.mp3`
  ffmpeg([
    '-y', '-i', caminho,
    '-af', `apad=pad_dur=${CAUDA_S}`,
    '-t', alvo.toFixed(3),
    '-c:a', 'libmp3lame', '-b:a', '128k', tmp,
  ])
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
      text: g.narracao,
      model_id: MODEL_ID,
      voice_settings: { ...VOZ, ...(AJUSTE_POR_CENA[g.id] ?? {}) },
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
