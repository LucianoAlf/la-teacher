import React from 'react'
import { interpolate, staticFile, useCurrentFrame, Easing, Img } from 'remotion'
import { Sfx, SFX } from './sfx'

/**
 * A MÃOZINHA — mão gerada no Higgsfield/Nano Banana e recortada, em
 * public/brand/mao-dedo.png. Ela vem DE CIMA, com o indicador apontando pra
 * baixo-esquerda, que é como se toca uma tela de verdade.
 *
 * Duas versões anteriores foram reprovadas pelo Alf, com razão: a 1ª era um
 * desenho meu em SVG (parecia luva); a 2ª era uma mão 3D boa mas apontando pra
 * CIMA — ou seja, encostando na tela com as costas do dedo, de baixo pra cima.
 *
 * • A PONTA DO DEDO é o ponto de toque — as coordenadas dos keyframes são
 *   sempre onde a mão encosta, não onde ela fica.
 * • Caminhando: inclina pro lado do movimento e balança de leve.
 * • No toque: avança na direção do dedo, encolhe um tico e solta o anel teal.
 * Coordenadas no espaço do pai (position:relative).
 */

export type CursorKeyframe = { frame: number; x: number; y: number; click?: boolean }

// Onde está a ponta do dedo dentro do PNG (1024×1024) — MEDIDO pixel a pixel
// (pixel opaco mais baixo da imagem), não estimado no olho.
const PONTA_X = 0.1792
const PONTA_Y = 0.8701
const RAZAO = 1

export const Dedo: React.FC<{
  keyframes: CursorKeyframe[]
  /** largura da mão em px (no espaço do telefone) */
  tamanho?: number
  clickSound?: boolean
}> = ({ keyframes, tamanho = 168, clickSound = true }) => {
  const frame = useCurrentFrame()
  if (keyframes.length < 2) return null

  const ordenados = [...keyframes].sort((a, b) => a.frame - b.frame)

  // POUSAR E SEGURAR: depois de apertar, a mão fica no botão POUSADA_F frames
  // (~0,5s) e só então viaja, com VIAGEM_MIN de folga pra não "teleportar".
  // Sem isso ela toca e foge no mesmo instante — o toque não assenta e o olho
  // não acompanha o que foi apertado.
  //
  // Se a cena não deu espaço suficiente entre o clique e o destino seguinte,
  // a própria mão EMPURRA os keyframes seguintes pra frente. Os keyframes pós-
  // clique são só "sair da frente", não têm significado — adiá-los é seguro, e
  // evita ter que reequilibrar à mão as ~25 janelas curtas da coreografia.
  const POUSADA_F = 14
  const VIAGEM_MIN = 12

  // Só o keyframe de SAÍDA (o logo após um clique) é adiado — nunca um clique,
  // senão a mão descasa das mudanças de tela, que são presas a frames fixos.
  // O adiamento respeita o keyframe seguinte, então nada atropela nada.
  const espacados = ordenados.map((k, i) => {
    const anterior = ordenados[i - 1]
    if (!anterior?.click || k.click) return k
    const depois = ordenados[i + 1]
    const desejado = anterior.frame + POUSADA_F + VIAGEM_MIN
    const teto = depois ? depois.frame - 4 : desejado
    return { ...k, frame: Math.max(k.frame, Math.min(desejado, teto)) }
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
  const vy = y - anterior.y
  const velocidade = Math.hypot(vx, vy)

  const cliques = ordenados.filter((k) => k.click)
  const noClique = cliques.find((k) => frame >= k.frame && frame <= k.frame + 12)

  // aperto: a mão avança um tico no eixo do dedo (baixo-esquerda) e encolhe
  const aperto = noClique
    ? interpolate(frame - noClique.frame, [0, 4, 12], [0, 1, 0], {
        extrapolateLeft: 'clamp',
        extrapolateRight: 'clamp',
      })
    : 0

  // caminhando: inclina pro lado pra onde vai + balanço leve (o "passo")
  const inclinacao = interpolate(vx, [-14, 0, 14], [-9, 0, 9], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  })
  const balanco = velocidade > 0.6 ? Math.sin(frame / 3.6) * 2 : 0
  const giro = inclinacao + balanco + aperto * 3
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
        src={staticFile('brand/mao-dedo.png')}
        style={{
          position: 'absolute',
          left: x - aperto * 3,
          top: y + aperto * 4,
          width: tamanho,
          height: tamanho * RAZAO,
          transform: `translate(${-PONTA_X * 100}%, ${-PONTA_Y * 100}%) rotate(${giro}deg) scale(${escala})`,
          transformOrigin: `${PONTA_X * 100}% ${PONTA_Y * 100}%`,
          filter: 'drop-shadow(0 14px 22px rgba(0,0,0,.55))',
          zIndex: 50,
          pointerEvents: 'none',
        }}
      />
    </>
  )
}
