// Monta uma trilha que EMENDA SOZINHA a partir de um mp3 com fade próprio.
//
// Por que existe: o tom-theme.mp3 (herdado do estúdio do TOM) tem 60s com
// fade-in e fade-out de ~2s e silêncio nas pontas. Emendado ponta com ponta —
// que é o que `<Audio loop>` faz — cada volta abre um buraco de 4,4s de
// silêncio ABSOLUTO. No vídeo de 3min42 saíram três, o maior com 2,3s de nada.
//
// A receita é a clássica: joga a CAUDA por cima da CABEÇA com fades opostos, e
// o ponto de emenda vira um cruzamento em vez de um corte.
//
//   [ fade-in ][            corpo            ][ fade-out ]
//                ↓ vira ↓
//   [ cauda↘ + cabeça↗ ][            corpo            ]
//
// O ffmpeg do Remotion não tem `afade` nem `acrossfade` (build com
// --disable-filters), mas tem `volume` com expressão em `t` — dá no mesmo.
// Também não tem `asplit`, por isso o arquivo entra três vezes como -i.
//
// Rodar: node scripts/montar-trilha.mjs public/music/tom-theme.mp3
import { spawnSync } from 'node:child_process'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { existsSync } from 'node:fs'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const entrada = resolve(root, process.argv[2] ?? 'public/music/tom-theme.mp3')
if (!existsSync(entrada)) { console.error(`sem arquivo: ${entrada}`); process.exit(1) }
const saida = entrada.replace(/\.mp3$/, '-loop.mp3')

const ffmpeg = (args) => {
  const r = spawnSync('npx', ['remotion', 'ffmpeg', ...args], { encoding: 'utf-8', shell: true })
  return `${r.stdout ?? ''}${r.stderr ?? ''}`
}

/**
 * Bordas do trecho em que a música está CHEIA.
 * ⚠️ O limiar importa: a −45dB acha onde o som acaba (fim do fade), e cruzar
 * dois trechos já sumindo abre uma cova no meio da emenda. A −25dB acha onde o
 * fade COMEÇA, que é o ponto certo pra cruzar.
 */
function bordas(arquivo, limiar = -25) {
  const s = ffmpeg(['-i', arquivo, '-af', `silencedetect=n=${limiar}dB:d=0.2`, '-f', 'null', '-'])
  const d = s.match(/Duration: (\d+):(\d+):([\d.]+)/)
  const total = Number(d[1]) * 3600 + Number(d[2]) * 60 + Number(d[3])
  const inicios = [...s.matchAll(/silence_start: ([\d.]+)/g)].map((m) => Number(m[1]))
  const fins = [...s.matchAll(/silence_end: ([\d.]+)/g)].map((m) => Number(m[1]))
  // silêncio que começa em 0 → é a cabeça; o que vai até o fim → é a cauda
  const comeca = inicios[0] === 0 && fins.length ? fins[0] : 0
  const ultimo = inicios.length ? inicios[inicios.length - 1] : total
  const termina = ultimo > comeca && ultimo < total - 0.05 ? ultimo : total
  return { total, comeca, termina }
}

const CRUZ = 2.0 // segundos de cruzamento — o mesmo tamanho dos fades do arquivo
const { total, comeca, termina } = bordas(entrada)
const ini = comeca
const fim = termina
const util = fim - ini
if (util < CRUZ * 3) { console.error(`trecho útil curto demais (${util.toFixed(1)}s)`); process.exit(1) }

console.log(`${entrada.replace(root, '.')}  ${total.toFixed(2)}s`)
console.log(`música cheia de ${ini.toFixed(2)}s a ${fim.toFixed(2)}s · cruzamento de ${CRUZ}s`)

const f = (n) => n.toFixed(3)
ffmpeg([
  '-y', '-i', entrada, '-i', entrada, '-i', entrada,
  '-filter_complex',
  `"[0:a]atrim=${f(ini)}:${f(ini + CRUZ)},asetpts=PTS-STARTPTS,volume=volume='t/${CRUZ}':eval=frame[cabeca];` +
    `[1:a]atrim=${f(fim - CRUZ)}:${f(fim)},asetpts=PTS-STARTPTS,volume=volume='1-t/${CRUZ}':eval=frame[cauda];` +
    `[cabeca][cauda]amix=inputs=2:normalize=0[emenda];` +
    `[2:a]atrim=${f(ini + CRUZ)}:${f(fim)},asetpts=PTS-STARTPTS[corpo];` +
    `[emenda][corpo]concat=n=2:v=0:a=1[saida]"`,
  '-map', '"[saida]"', '-c:a', 'libmp3lame', '-b:a', '192k', saida,
])

const conferida = bordas(saida)
console.log(`${saida.replace(root, '.')}  ${conferida.total.toFixed(2)}s  (${Math.round(conferida.total * 30)} frames)`)
const s = ffmpeg(['-i', saida, '-af', 'silencedetect=n=-30dB:d=0.15', '-f', 'null', '-'])
if (/silence_start/.test(s)) {
  console.error('❌ ainda tem ponto abaixo de −30dB — a emenda não fechou')
  process.exit(1)
}
console.log('✅ nenhum ponto abaixo de −30dB: emenda limpa')
console.log(`\nAtualizar TRILHA_FRAMES em video/Onboarding.tsx para ${Math.floor(conferida.total * 30)}`)
