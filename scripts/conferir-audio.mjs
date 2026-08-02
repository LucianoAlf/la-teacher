// Conferência de SANIDADE da narração — o teste que faltava.
//
// Medir silêncio não prova nada sobre a QUALIDADE da voz: os áudios com a tag
// `<break>` vocalizada passaram em todos os testes de cauda e soavam como
// "um ET falando língua esquisita" (Alf, 02/08). O que denuncia som que não é
// palavra é a VELOCIDADE DA FALA: a voz do Fábio fala ~3,3 palavras/s; abaixo
// de 2,7 tem coisa estranha no arquivo.
//
// Rodar: node scripts/conferir-audio.mjs [--video onboarding-professor]
import { readFileSync, readdirSync, existsSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { spawnSync } from 'node:child_process'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const argv = process.argv.slice(2)
const arg = (n, p) => { const i = argv.indexOf(n); return i >= 0 && argv[i + 1] ? argv[i + 1] : p }
const VIDEO_ID = arg('--video', 'onboarding-professor')
const ROTEIRO_PATH = arg('--roteiro', 'video/roteiro.ts')

const PS_MIN = 2.7   // abaixo disso: som que não é palavra
const PS_MAX = 4.6   // acima disso: fala atropelada (ou texto perdido)
const CAUDA_MIN = 0.25 // silêncio no fim, pra palavra não sair comida

const src = readFileSync(resolve(root, ROTEIRO_PATH), 'utf-8')
const cenas = []
const re = /\{\s*id:\s*'([^']+)'[\s\S]*?narracao:\s*'((?:[^'\\]|\\.)*)'/g
let m
while ((m = re.exec(src))) cenas.push({ id: m[1], texto: m[2].replace(/\\'/g, "'") })

const dir = resolve(root, 'public', 'audio', VIDEO_ID)
if (!existsSync(dir)) { console.error(`sem áudio em ${dir}`); process.exit(1) }
const arquivos = readdirSync(dir).filter((f) => f.endsWith('.mp3'))

const ffmpeg = (args) => {
  const r = spawnSync('npx', ['remotion', 'ffmpeg', ...args], { encoding: 'utf-8', shell: true })
  return `${r.stdout ?? ''}${r.stderr ?? ''}`
}

let reprovadas = 0
console.log('cena          palavras   dur     pal/s   cauda   veredito')
for (const c of cenas) {
  const arq = arquivos.find((f) => f.startsWith(`${c.id}.`))
  if (!arq) { console.log(`${c.id.padEnd(13)} SEM ÁUDIO`); reprovadas++; continue }
  const saida = ffmpeg(['-i', resolve(dir, arq), '-vn', '-af', 'silencedetect=n=-35dB:d=0.10', '-f', 'null', '-'])
  const d = saida.match(/Duration: 00:00:(\d+\.\d+)/)
  const dur = d ? Number(d[1]) : 0
  const inicios = [...saida.matchAll(/silence_start: ([\d.]+)/g)].map((x) => Number(x[1]))
  const cauda = inicios.length ? dur - Math.max(...inicios) : 0
  const palavras = c.texto.trim().split(/\s+/).length
  const ps = palavras / dur

  const problemas = []
  if (ps < PS_MIN) problemas.push('LENTO (som que não é palavra?)')
  if (ps > PS_MAX) problemas.push('RÁPIDO DEMAIS')
  if (cauda < CAUDA_MIN) problemas.push('sem cauda (palavra pode sair comida)')
  if (problemas.length) reprovadas++

  console.log(
    `${c.id.padEnd(13)} ${String(palavras).padStart(4)}   ${dur.toFixed(2).padStart(6)}   ` +
      `${ps.toFixed(2).padStart(5)}   ${cauda.toFixed(2).padStart(5)}   ` +
      (problemas.length ? `❌ ${problemas.join(' · ')}` : '✅'),
  )
}

console.log('')
if (reprovadas) {
  console.log(`❌ ${reprovadas} de ${cenas.length} cenas reprovadas — NÃO entregar`)
  process.exit(1)
}
console.log(`✅ ${cenas.length}/${cenas.length} cenas aprovadas`)
