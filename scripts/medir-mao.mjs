// Mede a PONTA DO DEDO de uma mão recortada, pixel a pixel, e apara a moldura.
//
// Por que existe: o Dedo.tsx precisa saber, em fração da imagem, onde fica a
// ponta — é ela que tem que pousar no botão, não o centro do PNG. Chutar isso
// põe a mão encostando "de lado" no alvo (aconteceu, o Alf reprovou).
//
// Rodar: node scripts/medir-mao.mjs public/brand/mao-baixo.png baixo
import { readFileSync, writeFileSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { lerPNG, escreverPNG, recortar } from './lib-png.mjs'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const [arquivo, direcao = 'baixo'] = process.argv.slice(2)
if (!arquivo) { console.error('uso: node scripts/medir-mao.mjs <png> <baixo|cima>'); process.exit(1) }
const entrada = resolve(root, arquivo)

const img = lerPNG(readFileSync(entrada))
const { largura: W, altura: H, px } = img
const A = (x, y) => px[(y * W + x) * 4 + 3]
const RGB = (x, y) => { const i = (y * W + x) * 4; return [px[i], px[i + 1], px[i + 2]] }

console.log(`${arquivo}  ${W}x${H}`)
const faixas = [0, 0, 0, 0, 0]
for (let i = 3; i < px.length; i += 4) faixas[Math.min(4, Math.floor(px[i] / 51))]++
console.log(`alfa  0-20%:${faixas[0]}  20-40%:${faixas[1]}  40-60%:${faixas[2]}  60-80%:${faixas[3]}  80-100%:${faixas[4]}`)

/** Sombra = cinza dessaturado. Se sobrou depois do recorte, ela é o pixel mais
 *  baixo da imagem e viraria a "ponta" — por isso não conta como conteúdo. */
const ehSombra = (x, y) => {
  const [r, g, b] = RGB(x, y)
  const max = Math.max(r, g, b); const min = Math.min(r, g, b)
  return max - min < 14 && max > 110 && max < 240
}

const OPACO = 200
let minX = W, maxX = -1, minY = H, maxY = -1
for (let y = 0; y < H; y++) {
  for (let x = 0; x < W; x++) {
    if (A(x, y) < OPACO || ehSombra(x, y)) continue
    if (x < minX) minX = x
    if (x > maxX) maxX = x
    if (y < minY) minY = y
    if (y > maxY) maxY = y
  }
}
console.log(`bbox da mão (sem sombra): x ${minX}..${maxX}  y ${minY}..${maxY}`)

const linhas = direcao === 'cima'
  ? Array.from({ length: H }, (_, i) => i)
  : Array.from({ length: H }, (_, i) => H - 1 - i)

let pontaY = -1; let pontaX = -1
for (const y of linhas) {
  const xs = []
  for (let x = 0; x < W; x++) if (A(x, y) >= OPACO && !ehSombra(x, y)) xs.push(x)
  if (xs.length >= 3) { pontaY = y; pontaX = Math.round(xs.reduce((a, b) => a + b, 0) / xs.length); break }
}
if (pontaY < 0) { console.error('não achei a ponta'); process.exit(1) }
console.log(`ponta na imagem: x=${pontaX} y=${pontaY}`)

// Apara pra bbox — assim `tamanho` no Dedo.tsx é a mão, não a moldura vazia.
const cropW = maxX - minX + 1
const cropH = maxY - minY + 1
const aparado = recortar(img, minX, minY, cropW, cropH)
const saidaCrop = entrada.replace(/\.png$/, '-crop.png')
writeFileSync(saidaCrop, escreverPNG(aparado))

const fx = (pontaX - minX) / cropW
const fy = (pontaY - minY) / cropH
console.log(`aparado: ${cropW}x${cropH} → ${saidaCrop}`)
console.log(`  pontaX: ${fx.toFixed(4)},  pontaY: ${fy.toFixed(4)},  razao: ${(cropW / cropH).toFixed(4)}`)

// Prova visual: cruz vermelha na ponta, pra eu OLHAR se acertei em vez de crer na conta.
const marca = { largura: cropW, altura: cropH, px: Buffer.from(aparado.px) }
const cx = pontaX - minX; const cy = pontaY - minY
const pinta = (x, y) => {
  if (x < 0 || y < 0 || x >= cropW || y >= cropH) return
  const i = (y * cropW + x) * 4
  marca.px[i] = 255; marca.px[i + 1] = 0; marca.px[i + 2] = 0; marca.px[i + 3] = 255
}
for (let d = -40; d <= 40; d++) { for (let e = -1; e <= 1; e++) { pinta(cx + d, cy + e); pinta(cx + e, cy + d) } }
writeFileSync(entrada.replace(/\.png$/, '-marca.png'), escreverPNG(marca))
console.log(`prova visual: ${entrada.replace(/\.png$/, '-marca.png')}`)
