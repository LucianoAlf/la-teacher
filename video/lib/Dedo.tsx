import React from 'react'
import { interpolate, staticFile, useCurrentFrame, Easing, Img } from 'remotion'
import { Sfx, SFX } from './sfx'

/**
 * A MÃOZINHA — quatro diagonais, desenhadas pelo Alf (public/brand/mao-*.png).
 *
 * A mão é escolhida pelo QUADRANTE do alvo: o dedo aponta pra fora e o corpo
 * da mão fica virado pro centro da tela. Alvo no rodapé → mão apontando pra
 * baixo (corpo sobe); alvo no topo → mão apontando pra cima (corpo desce);
 * mesma coisa na horizontal. Assim ela nunca sobra do quadro e ainda chega de
 * quatro direções diferentes, em vez de sempre do mesmo lado.
 *
 * ⚠️ Foi essa a lição das três reprovações seguidas: a regra NÃO é "de onde a
 * mão viria na vida real", é ONDE O CORPO DELA CABE. Com o celular grande
 * (escala 2,08) não existe folga — uma mão apontando pra cima tocando a
 * TabBar sobra 63px pro lado de fora do quadro, sempre. Vira um borrão
 * cortado em cima do botão, não uma mão. O `conferir-video.mjs` calcula a
 * caixa da mão em cada toque e REPROVA antes de renderizar se ela vazar.
 *
 * • A PONTA DO DEDO é o ponto de toque — as coordenadas dos keyframes são
 *   sempre onde a mão encosta, não onde ela fica.
 * • Entre um toque e outro ela sai de cena (parada no meio da tela ela lê como
 *   toque errado).
 * • A troca de mão é CORTE SECO, feito no descanso, com ela fora de cena.
 * Coordenadas no espaço do pai (position:relative).
 */

export type CursorKeyframe = { frame: number; x: number; y: number; click?: boolean }

/** Onde está a ponta do dedo dentro de cada PNG, em fração da imagem — MEDIDO
 *  pixel a pixel por scripts/medir-mao.mjs, que apara a moldura e cospe uma
 *  prova visual com a cruz na unha. Nunca estimar no olho. */
const MAOS = {
  'baixo-esq': { arquivo: 'brand/mao-baixo-esq.png', pontaX: 0.1128, pontaY: 0.9968, razao: 0.8608 },
  'baixo-dir': { arquivo: 'brand/mao-baixo-dir.png', pontaX: 0.8839, pontaY: 0.9968, razao: 0.8641 },
  'cima-esq': { arquivo: 'brand/mao-cima-esq.png', pontaX: 0.1128, pontaY: 0.0, razao: 0.8581 },
  'cima-dir': { arquivo: 'brand/mao-cima-dir.png', pontaX: 0.8839, pontaY: 0.0, razao: 0.8613 },
} as const

type Mao = keyof typeof MAOS

/** Meio da tela (conteúdo 410×816): acima disso o corpo tem que descer. */
const Y_VIRA = 408
/** Passando daqui o corpo não caberia indo pra direita, então o dedo vira. O
 *  padrão é apontar pra esquerda — mão direita chegando pela direita, que é o
 *  gesto mais comum de quem segura o celular. */
const X_VIRA = 277

const maoDe = (k: CursorKeyframe): Mao =>
  `${k.y < Y_VIRA ? 'cima' : 'baixo'}-${k.x > X_VIRA ? 'dir' : 'esq'}` as Mao

/**
 * DESCANSO — onde a mão espera entre um toque e outro: FORA de cena, pro lado
 * onde o corpo dela aponta. Parada dentro da tela ela fica com a unha do lado
 * do botão apontando pro nada, e lê como toque errado (o Alf flagrou assim no
 * "Continuar" da abertura).
 */
const FORA_CIMA = 860 // mão que aponta pra cima (corpo embaixo): desce e some
const FORA_BAIXO = -80 // mão que aponta pra baixo (corpo em cima): sobe e some

export const Dedo: React.FC<{
  keyframes: CursorKeyframe[]
  /** largura da mão em px (no espaço do telefone). 125 e não 150: estas mãos
   *  são mais altas que as antigas (razão 0,86 contra 1,13), e a 150 o corpo
   *  cobria o conteúdo atrás do alvo — o cronômetro da gravação sumia. */
  tamanho?: number
  clickSound?: boolean
}> = ({ keyframes, tamanho = 125, clickSound = true }) => {
  const frame = useCurrentFrame()
  if (keyframes.length < 2) return null

  const ordenados = [...keyframes].sort((a, b) => a.frame - b.frame)
  const cliques = ordenados.filter((k) => k.click)

  // POUSAR E SEGURAR: depois de apertar, a mão fica no botão POUSADA_F frames
  // (~0,5s) e só então viaja, com VIAGEM_MIN de folga pra não "teleportar".
  // Sem isso ela toca e foge no mesmo instante — o toque não assenta e o olho
  // não acompanha o que foi apertado.
  const POUSADA_F = 14
  const VIAGEM_MIN = 12

  // Só o keyframe de SAÍDA (o logo após um clique) é adiado — nunca um clique,
  // senão a mão descasa das mudanças de tela, que são presas a frames fixos.
  // E todo keyframe que não é toque vira descanso fora de cena, no sentido do
  // corpo da mão do toque mais recente. Cena sem toque fica como foi escrita.
  const espacados = ordenados.map((k, i) => {
    if (k.click) return k
    const referencia = [...cliques].reverse().find((c) => c.frame <= k.frame) ?? cliques[0]
    if (!referencia) return k
    const y = maoDe(referencia).startsWith('cima') ? FORA_CIMA : FORA_BAIXO
    const anterior = ordenados[i - 1]
    if (!anterior?.click) return { ...k, y }
    const depois = ordenados[i + 1]
    const desejado = anterior.frame + POUSADA_F + VIAGEM_MIN
    const teto = depois ? depois.frame - 4 : desejado
    return { ...k, y, frame: Math.max(k.frame, Math.min(desejado, teto)) }
  })

  const comPousada: CursorKeyframe[] = []
  espacados.forEach((k, i) => {
    comPousada.push(k)
    const proximo = espacados[i + 1]
    if (!k.click || !proximo) return
    const janela = proximo.frame - k.frame
    if (janela < 8) return
    comPousada.push({ frame: k.frame + Math.min(POUSADA_F, janela - 6), x: k.x, y: k.y })
  })

  // interpolate exige inputRange crescente; keyframes repetidos (chega e clica
  // no mesmo frame) são deduplicados pro cálculo de posição.
  const pos = comPousada.filter((k, i) => i === 0 || k.frame > comPousada[i - 1].frame)
  const frames = pos.map((k) => k.frame)
  const opts = {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.inOut(Easing.cubic),
  } as const

  const em = (f: number) =>
    pos.length < 2
      ? { x: pos[0].x, y: pos[0].y }
      : {
          x: interpolate(f, frames, pos.map((k) => k.x), opts),
          y: interpolate(f, frames, pos.map((k) => k.y), opts),
        }

  const { x, y } = em(frame)
  const anterior = em(frame - 2)
  const vx = x - anterior.x
  const velocidade = Math.hypot(vx, y - anterior.y)

  /**
   * QUAL MÃO ESTÁ EM CENA. Corte seco no descanso, com ela fora do quadro —
   * nunca cross-fade: as quatro silhuetas são diferentes e cruzar duas mostra
   * DUAS MÃOS na tela (defeito que apareceu no quadro agenda@100).
   */
  const trocas: { frame: number; mao: Mao }[] = []
  if (cliques.length) {
    trocas.push({ frame: -Infinity, mao: maoDe(cliques[0]) })
    for (let i = 0; i < cliques.length - 1; i++) {
      const para = maoDe(cliques[i + 1])
      if (para === maoDe(cliques[i])) continue
      const descanso = espacados.find(
        (k) => !k.click && k.frame > cliques[i].frame && k.frame < cliques[i + 1].frame,
      )
      const corte = descanso
        ? descanso.frame
        : Math.round((cliques[i].frame + POUSADA_F + cliques[i + 1].frame) / 2)
      trocas.push({ frame: corte, mao: para })
    }
  }
  const qual: Mao = trocas.filter((t) => frame >= t.frame).pop()?.mao ?? 'baixo-esq'
  const m = MAOS[qual]

  const noClique = cliques.find((k) => frame >= k.frame && frame <= k.frame + 12)
  // aperto: a mão avança um tico NO EIXO DO DEDO (na direção da ponta) e encolhe
  const aperto = noClique
    ? interpolate(frame - noClique.frame, [0, 4, 12], [0, 1, 0], {
        extrapolateLeft: 'clamp',
        extrapolateRight: 'clamp',
      })
    : 0
  const sentidoY = qual.startsWith('cima') ? -1 : 1
  const sentidoX = qual.endsWith('esq') ? -1 : 1

  // caminhando: inclina pro lado pra onde vai + balanço leve (o "passo")
  const inclinacao = interpolate(vx, [-14, 0, 14], [-9, 0, 9], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  })
  const balanco = velocidade > 0.6 ? Math.sin(frame / 3.6) * 2 : 0
  const giro = inclinacao + balanco + aperto * 3 * sentidoY
  const escala = 1 - aperto * 0.05

  return (
    <>
      {clickSound &&
        cliques.map((k) => <Sfx key={`snd-${k.frame}`} file={SFX.tap} at={k.frame} volume={0.45} />)}

      {/* anel do toque, saindo da ponta do dedo */}
      {cliques.map((k) => {
        if (frame < k.frame || frame > k.frame + 16) return null
        const t = (frame - k.frame) / 16
        const d = 30 * (1 + t * 2.1)
        return (
          <div
            key={k.frame}
            style={{
              position: 'absolute',
              left: k.x,
              top: k.y,
              width: d,
              height: d,
              transform: 'translate(-50%, -50%)',
              borderRadius: '50%',
              border: '3px solid rgba(72,191,179,0.95)',
              opacity: 1 - t,
              zIndex: 49,
            }}
          />
        )
      })}

      <Img
        src={staticFile(m.arquivo)}
        style={{
          position: 'absolute',
          left: x + aperto * 3 * sentidoX,
          top: y + aperto * 4 * sentidoY,
          width: tamanho,
          height: tamanho / m.razao,
          transform: `translate(${-m.pontaX * 100}%, ${-m.pontaY * 100}%) rotate(${giro}deg) scale(${escala})`,
          transformOrigin: `${m.pontaX * 100}% ${m.pontaY * 100}%`,
          filter: 'drop-shadow(0 14px 22px rgba(0,0,0,.55))',
          zIndex: 50,
          pointerEvents: 'none',
        }}
      />
    </>
  )
}
