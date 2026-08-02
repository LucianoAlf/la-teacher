// PNG mínimo em Node puro (ler/escrever RGBA 8 bits).
//
// Por que não usar o ffmpeg: o binário que vem com o Remotion é compilado com
// `--disable-muxers`/`--disable-filters` e uma lista curta de exceções — não
// tem muxer `rawvideo` nem os filtros `crop`/`drawbox`. Descobri tentando.
import { inflateSync, deflateSync } from 'node:zlib'

const ASSINATURA = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])

const TABELA_CRC = (() => {
  const t = new Int32Array(256)
  for (let n = 0; n < 256; n++) {
    let c = n
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
    t[n] = c
  }
  return t
})()

function crc32(buf) {
  let c = -1
  for (let i = 0; i < buf.length; i++) c = TABELA_CRC[(c ^ buf[i]) & 0xff] ^ (c >>> 8)
  return (c ^ -1) >>> 0
}

const paeth = (a, b, c) => {
  const p = a + b - c
  const pa = Math.abs(p - a); const pb = Math.abs(p - b); const pc = Math.abs(p - c)
  return pa <= pb && pa <= pc ? a : pb <= pc ? b : c
}

/** Lê um PNG e devolve { largura, altura, px } com px em RGBA (4 bytes/pixel). */
export function lerPNG(buffer) {
  if (!buffer.subarray(0, 8).equals(ASSINATURA)) throw new Error('não é PNG')
  let pos = 8
  let largura = 0; let altura = 0; let profundidade = 0; let tipoCor = 0; let entrelacado = 0
  const idat = []
  while (pos < buffer.length) {
    const tam = buffer.readUInt32BE(pos)
    const tipo = buffer.toString('ascii', pos + 4, pos + 8)
    const dados = buffer.subarray(pos + 8, pos + 8 + tam)
    if (tipo === 'IHDR') {
      largura = dados.readUInt32BE(0)
      altura = dados.readUInt32BE(4)
      profundidade = dados[8]
      tipoCor = dados[9]
      entrelacado = dados[12]
    } else if (tipo === 'IDAT') idat.push(dados)
    else if (tipo === 'IEND') break
    pos += 12 + tam
  }
  if (profundidade !== 8) throw new Error(`profundidade ${profundidade} não suportada`)
  if (entrelacado) throw new Error('PNG entrelaçado não suportado')
  if (tipoCor !== 6 && tipoCor !== 2) throw new Error(`tipo de cor ${tipoCor} não suportado`)

  const canais = tipoCor === 6 ? 4 : 3
  const bpp = canais
  const linha = largura * bpp
  const bruto = inflateSync(Buffer.concat(idat))
  const saida = Buffer.alloc(altura * linha)

  for (let y = 0; y < altura; y++) {
    const filtro = bruto[y * (linha + 1)]
    const org = y * (linha + 1) + 1
    const dst = y * linha
    const ant = dst - linha
    for (let i = 0; i < linha; i++) {
      const x = bruto[org + i]
      const a = i >= bpp ? saida[dst + i - bpp] : 0
      const b = y > 0 ? saida[ant + i] : 0
      const c = y > 0 && i >= bpp ? saida[ant + i - bpp] : 0
      let v
      if (filtro === 0) v = x
      else if (filtro === 1) v = x + a
      else if (filtro === 2) v = x + b
      else if (filtro === 3) v = x + ((a + b) >> 1)
      else if (filtro === 4) v = x + paeth(a, b, c)
      else throw new Error(`filtro ${filtro} desconhecido`)
      saida[dst + i] = v & 0xff
    }
  }

  if (canais === 4) return { largura, altura, px: saida }
  // RGB → RGBA opaco
  const rgba = Buffer.alloc(largura * altura * 4)
  for (let i = 0, j = 0; i < saida.length; i += 3, j += 4) {
    rgba[j] = saida[i]; rgba[j + 1] = saida[i + 1]; rgba[j + 2] = saida[i + 2]; rgba[j + 3] = 255
  }
  return { largura, altura, px: rgba }
}

const chunk = (tipo, dados) => {
  const cab = Buffer.alloc(8)
  cab.writeUInt32BE(dados.length, 0)
  cab.write(tipo, 4, 'ascii')
  const crc = Buffer.alloc(4)
  crc.writeUInt32BE(crc32(Buffer.concat([cab.subarray(4), dados])), 0)
  return Buffer.concat([cab, dados, crc])
}

/** Escreve RGBA como PNG (filtro 0 em todas as linhas — simples e suficiente). */
export function escreverPNG({ largura, altura, px }) {
  const ihdr = Buffer.alloc(13)
  ihdr.writeUInt32BE(largura, 0)
  ihdr.writeUInt32BE(altura, 4)
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0
  const linha = largura * 4
  const cru = Buffer.alloc(altura * (linha + 1))
  for (let y = 0; y < altura; y++) {
    cru[y * (linha + 1)] = 0
    px.copy(cru, y * (linha + 1) + 1, y * linha, (y + 1) * linha)
  }
  return Buffer.concat([
    ASSINATURA,
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(cru, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ])
}

/** Recorta um retângulo. */
export function recortar({ largura, altura, px }, x0, y0, w, h) {
  const saida = Buffer.alloc(w * h * 4)
  for (let y = 0; y < h; y++) {
    px.copy(saida, y * w * 4, ((y0 + y) * largura + x0) * 4, ((y0 + y) * largura + x0 + w) * 4)
  }
  return { largura: w, altura: h, px: saida }
}
