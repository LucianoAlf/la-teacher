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

// Medimos SÍLABAS por segundo, não palavras: uma frase com palavras longas
// ("acompanha", "planilha") dá poucas palavras/s sem estar lenta — foi assim
// que eu quase "consertei" uma cena que estava boa. Fala de narração em
// português roda a ~5 sílabas/s enquanto a voz soa.
const SIL_MIN = 4.2    // abaixo: som que não é palavra
// 8,6: frases curtas e exclamativas ("É isso aí! ... Tamo junto!") saem
// naturalmente mais rápidas. As narrativas ficam em 5,5–7,5, bem longe daqui.
const SIL_MAX = 8.6    // acima: atropelado
const CAUDA_MIN = 0.25 // silêncio no fim, pra palavra não sair comida

/** Contagem aproximada de sílabas em português: grupos de vogais, com ditongos
 *  crescentes/decrescentes contando como um só. Serve pra comparar cenas. */
function silabas(texto) {
  return texto
    .toLowerCase()
    .replace(/[^a-záàâãéêíóôõúüç\s]/g, ' ')
    .split(/\s+/)
    .filter(Boolean)
    .reduce((total, palavra) => {
      const grupos = palavra.match(/[aeiouáàâãéêíóôõúü]+/g) || []
      return total + Math.max(1, grupos.length)
    }, 0)
}

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
console.log('cena          silabas  dur    sil/s  falando  cauda  paus/s  veredito')
for (const c of cenas) {
  const arq = arquivos.find((f) => f.startsWith(`${c.id}.`))
  if (!arq) { console.log(`${c.id.padEnd(13)} SEM ÁUDIO`); reprovadas++; continue }
  const saida = ffmpeg(['-i', resolve(dir, arq), '-vn', '-af', 'silencedetect=n=-35dB:d=0.10', '-f', 'null', '-'])
  const d = saida.match(/Duration: 00:00:(\d+\.\d+)/)
  const dur = d ? Number(d[1]) : 0
  const inicios = [...saida.matchAll(/silence_start: ([\d.]+)/g)].map((x) => Number(x[1]))
  const fins = [...saida.matchAll(/silence_end: ([\d.]+)/g)].map((x) => Number(x[1]))
  const cauda = inicios.length ? dur - Math.max(...inicios) : 0

  // Tempo em que a voz REALMENTE está soando (fora as pausas).
  // Separar isso de `dur` é o que distingue "pausa longa por pontuação"
  // (aceitável) de "som que não é palavra" (a tag vocalizada, o defeito real).
  let silencioTotal = 0
  inicios.forEach((ini, i) => { silencioTotal += (fins[i] ?? dur) - ini })
  const falando = Math.max(0.1, dur - silencioTotal)

  const sil = silabas(c.texto)
  const silBruto = sil / dur
  const silFalando = sil / falando

  // Fala PICOTADA: micro-pausas a cada palavra. Não é ruído nem pontuação —
  // é a voz gaguejando, e soa estranho igual. Cena boa fica em ~0,7 pausas/s.
  const pausasPorSeg = inicios.length / dur

  const problemas = []
  // O veredito de ruído usa a fala pura: se as sílabas saem no ritmo certo
  // ENQUANTO a voz soa, o áudio está são — o resto é pausa.
  if (silFalando < SIL_MIN) problemas.push('LENTO FALANDO (som que não é palavra)')
  if (pausasPorSeg > 0.95) problemas.push(`PICOTADA (${pausasPorSeg.toFixed(2)} pausas/s)`)
  if (silFalando > SIL_MAX) problemas.push('RÁPIDO DEMAIS')
  if (silBruto < 3.2) problemas.push('pausas longas demais pro vídeo')
  if (cauda < CAUDA_MIN) problemas.push('sem cauda (palavra pode sair comida)')
  if (problemas.length) reprovadas++

  console.log(
    `${c.id.padEnd(13)} ${String(sil).padStart(5)}  ${dur.toFixed(2).padStart(6)}  ` +
      `${silBruto.toFixed(2).padStart(5)}   ${silFalando.toFixed(2).padStart(5)}  ${cauda.toFixed(2).padStart(5)}  ` +
      `${pausasPorSeg.toFixed(2).padStart(5)}   ` +
      (problemas.length ? `❌ ${problemas.join(' · ')}` : '✅'),
  )
}

console.log('')
if (reprovadas) {
  console.log(`❌ ${reprovadas} de ${cenas.length} cenas reprovadas — NÃO entregar`)
  process.exit(1)
}
console.log(`✅ ${cenas.length}/${cenas.length} cenas aprovadas`)
