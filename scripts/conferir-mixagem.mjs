// Conferência da MIXAGEM do arquivo final: não pode existir silêncio nenhum.
//
// Por que existe: meu teste antigo de trilha só provava que havia som em ALGUM
// lugar do vídeo — e passou um render com três buracos de silêncio absoluto (o
// maior de 2,3s), causados pelo `<Audio loop>` numa trilha que tem fade e
// silêncio nas pontas. Provar "tem música" não é o mesmo que provar "não tem
// buraco". Este script prova a segunda coisa.
//
// Rodar: node scripts/conferir-mixagem.mjs [out/onboarding-professor.mp4] [--frames 6645]
import { spawnSync } from 'node:child_process'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { existsSync } from 'node:fs'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const argv = process.argv.slice(2)
const arquivo = resolve(root, argv.find((a) => !a.startsWith('--')) ?? 'out/onboarding-professor.mp4')
const i = argv.indexOf('--frames')
const framesEsperados = i >= 0 ? Number(argv[i + 1]) : null

if (!existsSync(arquivo)) { console.error(`sem arquivo: ${arquivo}`); process.exit(1) }

const LIMIAR = '-45dB' // abaixo disso é buraco: a trilha roda a 0,09 e fica bem acima
const MIN_S = 0.25

const r = spawnSync('npx', [
  'remotion', 'ffmpeg', '-i', arquivo, '-vn',
  '-af', `silencedetect=n=${LIMIAR}:d=${MIN_S}`, '-f', 'null', '-',
], { encoding: 'utf-8', shell: true })
const saida = `${r.stdout ?? ''}${r.stderr ?? ''}`

const d = saida.match(/Duration: (\d+):(\d+):([\d.]+)/)
if (!d) { console.error('não li a duração'); process.exit(1) }
const segundos = Number(d[1]) * 3600 + Number(d[2]) * 60 + Number(d[3])
const frames = Math.round(segundos * 30)
console.log(`${arquivo.replace(root, '.')}`)
console.log(`duração: ${Math.floor(segundos / 60)}min${(segundos % 60).toFixed(2)}s · ${frames} frames`)
if (!/Audio: aac|Audio: mp3/.test(saida)) { console.error('❌ sem faixa de áudio'); process.exit(1) }

let falhou = false
if (framesEsperados != null && Math.abs(frames - framesEsperados) > 2) {
  console.error(`❌ esperava ${framesEsperados} frames, achei ${frames}`)
  falhou = true
}

// O fade de saída do vídeo termina em zero de propósito — o rabinho mudo no
// fim é o desenho, não defeito. Só ele é tolerado, e com teto: buraco no MEIO
// reprova sempre, e um rabo longo demais quer dizer que a trilha morreu antes
// da hora (foi assim que o fim ficou 1,9s calado).
const RABO_OK_S = 1.0

const inicios = [...saida.matchAll(/silence_start: ([\d.]+)/g)].map((m) => Number(m[1]))
const duracoes = [...saida.matchAll(/silence_duration: ([\d.]+)/g)].map((m) => Number(m[1]))
const buracos = []
inicios.forEach((ini, k) => {
  const dur = duracoes[k] ?? segundos - ini
  const vaiAteOFim = ini + dur >= segundos - 0.08
  if (vaiAteOFim && dur <= RABO_OK_S) {
    console.log(`   (fade de saída: ${dur.toFixed(2)}s de silêncio no fim — dentro do previsto)`)
    return
  }
  buracos.push({ ini, dur })
})
if (buracos.length) {
  console.log(`❌ ${buracos.length} buraco(s) de silêncio:`)
  for (const b of buracos) {
    console.log(`   ${Math.floor(b.ini / 60)}:${(b.ini % 60).toFixed(2).padStart(5, '0')}  por ${b.dur.toFixed(2)}s`)
  }
  falhou = true
} else {
  console.log(`✅ som contínuo do início ao fim (nada abaixo de ${LIMIAR} por ${MIN_S}s+)`)
}

process.exit(falhou ? 1 : 0)
