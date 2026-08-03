// Harness de conferência do vídeo — renderiza EXATAMENTE os frames dos toques
// direto da composição e monta folhas de contato. Bar do Alf: 9,5 — conferir
// TODOS os toques, não amostrar.
//
// Por que não extrai do MP4 (como a 1ª versão, em PowerShell):
//  1. buscar num H.264 com B-frames devolvia quadros ~8 frames adiantados, o
//     que fez toques CERTOS parecerem errados;
//  2. eu recalculava a linha do tempo à mão e ela desviava do arquivo real,
//     porque o Remotion mede os MP3 diferente do ffmpeg.
// Agora o próprio Remotion resolve a composição (`selectComposition` roda o
// calculateMetadata de verdade) e renderiza o frame pedido. Sem busca, sem
// calibração, sem tabela de durações escrita à mão que envelhece.
//
// Rodar: node scripts/conferir-video.mjs
import { readFileSync, writeFileSync, mkdirSync, rmSync, existsSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { bundle } from '@remotion/bundler'
import { selectComposition, renderStill, openBrowser } from '@remotion/renderer'
import { lerPNG, escreverPNG } from './lib-png.mjs'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const argv = process.argv.slice(2)
const arg = (n, p) => { const i = argv.indexOf(n); return i >= 0 && argv[i + 1] ? argv[i + 1] : p }
const COMPOSICAO = arg('--video', 'onboarding-professor')
const SAIDA = arg('--saida', resolve(process.env.TEMP ?? '/tmp', 'claude', 'conf'))
const OLHAR = 8 // frames após o clique: meio da pousada, com o anel ainda visível

/* ---------- 1. de onde vêm os toques: a PRÓPRIA coreografia ---------- */

const fonte = readFileSync(resolve(root, 'video/Onboarding.tsx'), 'utf-8')

/* ---------- 0. a geometria da mão, lida do Dedo.tsx ---------- */
// Duplicar esses números aqui seria o mesmo erro da tabela de durações: eles
// envelhecem calados. Leio da fonte.
const dedoSrc = readFileSync(resolve(root, 'video/lib/Dedo.tsx'), 'utf-8')
const Y_VIRA = Number(dedoSrc.match(/^const Y_VIRA = (\d+)/m)?.[1])
const TAMANHO = Number(dedoSrc.match(/tamanho = (\d+)/)?.[1])
const cmp = dedoSrc.match(/const ehCima = \(k: CursorKeyframe\) => k\.y (<|>=) Y_VIRA/)?.[1]
const maosBloco = dedoSrc.slice(dedoSrc.indexOf('const MAOS = {'))
// eslint-disable-next-line no-eval
const MAOS = eval(`(${maosBloco.slice(maosBloco.indexOf('{'), maosBloco.indexOf('} as const') + 1).replace(/\/\/[^\n]*/g, '')})`)
if (!Y_VIRA || !TAMANHO || !cmp || !MAOS?.cima) throw new Error('não li a geometria da mão no Dedo.tsx')
const ehCima = (y) => (cmp === '<' ? y < Y_VIRA : y >= Y_VIRA)

// A tela do telefone, em coordenadas do conteúdo (o mesmo espaço dos keyframes).
const TELA_W = 410
const TELA_H = 816

/** Retângulo que a mão ocupa quando a ponta está em (x,y). */
function caixaDaMao(x, y) {
  const m = ehCima(y) ? MAOS.cima : MAOS.baixo
  const largura = TAMANHO
  const altura = TAMANHO / m.razao
  return {
    qual: ehCima(y) ? 'cima' : 'baixo',
    esq: x - m.pontaX * largura,
    dir: x - m.pontaX * largura + largura,
    topo: y - m.pontaY * altura,
    base: y - m.pontaY * altura + altura,
  }
}

// Constantes usadas dentro dos keyframes (GRAVAR_MIC, MENU, ...). Sem resolver
// isso o eval quebra — e quebrar é o certo: melhor falhar do que conferir frame
// errado calado.
const constantes = {}
for (const m of fonte.matchAll(/^\s*const ([A-Za-z_][A-Za-z0-9_]*) = (-?\d+)\s*$/gm)) {
  constantes[m[1]] = Number(m[2])
}

// id da cena → nome do componente, lido do registro CENAS
const bloco = fonte.slice(fonte.indexOf('const CENAS: Record<string, React.FC> = {'))
const registro = bloco.slice(0, bloco.indexOf('\n}'))
const componentePorCena = {}
for (const m of registro.matchAll(/^\s{2}(\w+):\s*(Cena\w+),?\s*$/gm)) componentePorCena[m[1]] = m[2]

function keyframesDe(componente) {
  const i = fonte.indexOf(`const ${componente}: React.FC = () => {`)
  if (i < 0) return []
  // ⚠️ Limitar ao corpo DESTE componente. Sem isso, uma cena sem coreografia
  // rouba a da seguinte e o harness confere a tela errada achando que está
  // certo — foi o que aconteceu: `whatsapp` (que não tinha mão nenhuma) saiu
  // com os toques de `semana`. Só `\nconst ` no início da linha é topo de
  // arquivo; dentro do componente tudo é indentado.
  const seguinte = fonte.indexOf('\nconst ', i + 10)
  const corpo = fonte.slice(i, seguinte < 0 ? undefined : seguinte)
  if (!corpo.includes('dedo={kfs}')) return []
  const j = corpo.indexOf('const kfs: CursorKeyframe[] = [')
  if (j < 0) return []
  const fim = corpo.indexOf('\n  ]', j)
  let texto = corpo.slice(corpo.indexOf('[', j), fim + 4)
  texto = texto.replace(/\/\/[^\n]*/g, '')
  for (const [nome, valor] of Object.entries(constantes)) {
    texto = texto.replace(new RegExp(`\\b${nome}\\b`, 'g'), String(valor))
  }
  const sobrou = texto.match(/\b[A-Za-z_]\w*\b(?!\s*:)/g)?.filter((s) => !['frame', 'x', 'y', 'click', 'true', 'false'].includes(s))
  if (sobrou?.length) throw new Error(`não resolvi ${sobrou.join(', ')} nos keyframes de ${componente}`)
  // eslint-disable-next-line no-eval
  return eval(texto)
}

/* ---------- 2. a linha do tempo REAL, dita pelo Remotion ---------- */

console.log('empacotando o estúdio…')
const serveUrl = await bundle({ entryPoint: resolve(root, 'video/index.ts') })
const composicao = await selectComposition({ serveUrl, id: COMPOSICAO, inputProps: {} })
const cenas = composicao.props.scenes
if (!Array.isArray(cenas) || !cenas.length) throw new Error('composição sem scenes — calculateMetadata não rodou?')

let acumulado = 0
const inicioDaCena = {}
for (const c of cenas) { inicioDaCena[c.id] = acumulado; acumulado += c.durationInFrames }
console.log(`${cenas.length} cenas · ${acumulado} frames (${(acumulado / 30).toFixed(1)}s)`)
if (acumulado !== composicao.durationInFrames) {
  throw new Error(`soma das cenas ${acumulado} ≠ duração da composição ${composicao.durationInFrames}`)
}

// `--so agenda,perfil`: confere só essas cenas (pra iterar rápido em ajuste
// visual). Sem o filtro, confere TUDO — que é o gate de entrega.
const soCenas = arg('--so', '').split(',').filter(Boolean)

const alvos = []
for (const c of cenas) {
  const comp = componentePorCena[c.id]
  if (!comp) continue
  if (soCenas.length && !soCenas.includes(c.id)) continue
  for (const k of keyframesDe(comp)) {
    if (!k.click) continue
    const caixa = caixaDaMao(k.x, k.y)
    alvos.push({
      nome: `${c.id}+${k.frame}`,
      cena: c.id,
      alvoX: k.x,
      alvoY: k.y,
      mao: caixa.qual,
      caixa,
      frame: Math.min(inicioDaCena[c.id] + k.frame + OLHAR, acumulado - 1),
    })
  }
}

/**
 * A MÃO NÃO PODE VAZAR DA TELA. Um punho cortado pela borda do quadro não lê
 * como mão entrando em cena — lê como borrão em cima do botão. Eu vi isso nas
 * folhas de contato e julguei que estava bom; o Alf reprovou e estava certo.
 * Julgamento meu não serve aqui, então virou conta.
 */
const vazando = alvos.filter((a) => a.caixa.topo < -2 || a.caixa.base > TELA_H + 2)
if (vazando.length) {
  console.error(`\n❌ ${vazando.length} toque(s) com a mão saindo da tela (0..${TELA_H}):`)
  for (const a of vazando) {
    console.error(
      `   ${a.nome.padEnd(16)} alvo y=${a.alvoY} · mão ${a.caixa.qual} ocupa ` +
        `${a.caixa.topo.toFixed(0)}..${a.caixa.base.toFixed(0)}`,
    )
  }
  console.error('\nNÃO renderizar — corrigir Y_VIRA/tamanho ou a altura do alvo.\n')
  process.exit(1)
}
console.log(`mão dentro da tela nos ${alvos.length} toques ✅`)
// Quadros extras que não são toque, mas que eu quero olhar (estado da tela
// depois da ação): --tambem whatsapp:250,whatsapp:320
for (const par of arg('--tambem', '').split(',').filter(Boolean)) {
  const [cena, f] = par.split(':')
  if (!(cena in inicioDaCena)) throw new Error(`cena "${cena}" não existe`)
  alvos.push({ nome: `${cena}@${f}`, cena, mao: '—', frame: inicioDaCena[cena] + Number(f) })
}
console.log(`toques a conferir: ${alvos.filter((a) => a.mao !== '—').length}  (${alvos.filter((a) => a.mao === 'cima').length} com a mão de baixo pra cima)`)

/* ---------- 3. renderiza cada toque ---------- */

if (existsSync(SAIDA)) rmSync(SAIDA, { recursive: true, force: true })
mkdirSync(SAIDA, { recursive: true })

const navegador = await openBrowser('chrome')
const ESCALA = 1 / 3 // 1080×1920 → 360×640
let n = 0
for (const a of alvos) {
  a.arquivo = resolve(SAIDA, `${a.nome}.png`)
  await renderStill({
    composition: composicao,
    serveUrl,
    output: a.arquivo,
    frame: a.frame,
    inputProps: {},
    scale: ESCALA,
    puppeteerInstance: navegador,
  })
  n++
  process.stdout.write(`\r  [${n}/${alvos.length}] ${a.nome}            `)
}
await navegador.close({ silent: true })
console.log('')

/* ---------- 4. folhas de contato ---------- */

const COLS = 3
const POR_FOLHA = 6
for (let i = 0, folha = 1; i < alvos.length; i += POR_FOLHA, folha++) {
  const lote = alvos.slice(i, i + POR_FOLHA)
  const imgs = lote.map((a) => lerPNG(readFileSync(a.arquivo)))
  const tw = imgs[0].largura
  const th = imgs[0].altura
  const linhas = Math.ceil(lote.length / COLS)
  const W = COLS * tw
  const H = linhas * th
  const px = Buffer.alloc(W * H * 4)
  for (let p = 3; p < px.length; p += 4) px[p] = 255
  imgs.forEach((img, j) => {
    const ox = (j % COLS) * tw
    const oy = Math.floor(j / COLS) * th
    for (let y = 0; y < img.altura; y++) {
      img.px.copy(px, ((oy + y) * W + ox) * 4, y * img.largura * 4, (y + 1) * img.largura * 4)
    }
  })
  writeFileSync(resolve(SAIDA, `folha-${folha}.png`), escreverPNG({ largura: W, altura: H, px }))
  console.log(`folha-${folha}.png  ${lote.map((a) => `${a.nome}[${a.mao}]`).join(' · ')}`)
}
console.log(`\nem ${SAIDA}`)
