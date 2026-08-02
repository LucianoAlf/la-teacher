import React from 'react'
import { interpolate, staticFile, useCurrentFrame, Easing, Img } from 'remotion'
import { Sfx, SFX } from './sfx'

/**
 * A MÃOZINHA — mão 3D de verdade (gerada no Higgsfield/Nano Banana e recortada,
 * em public/brand/mao-dedo.png) que caminha pela tela e aperta os botões.
 * A 1ª versão era um desenho meu em SVG e ficou ridícula (palavras do Alf, e
 * ele tinha razão): parecia luva de desenho animado, não mão.
 *
 * • A PONTA DO DEDO é o ponto de toque — as coordenadas dos keyframes são
 *   sempre onde a mão encosta, não onde ela fica.
 * • Caminhando: inclina pro lado do movimento e balança de leve.
 * • No toque: desce na direção do dedo, encolhe um tico e solta o anel teal.
 * Coordenadas no espaço do pai (position:relative).
 */

export type CursorKeyframe = { frame: number; x: number; y: number; click?: boolean }

// onde está a ponta do dedo dentro do PNG (896×1200), em fração da imagem
const PONTA_X = 0.44
const PONTA_Y = 0.135
const RAZAO = 1200 / 896

export const Dedo: React.FC<{
  keyframes: CursorKeyframe[]
  /** largura da mão em px (no espaço do telefone) */
  tamanho?: number
  clickSound?: boolean
}> = ({ keyframes, tamanho = 132, clickSound = true }) => {
  const frame = useCurrentFrame()
  if (keyframes.length < 2) return null

  // interpolate exige inputRange crescente; keyframes repetidos (chega e clica
  // no mesmo frame) são deduplicados pro cálculo de posição.
  const ordenados = [...keyframes].sort((a, b) => a.frame - b.frame)
  const pos = ordenados.filter((k, i) => i === 0 || k.frame > ordenados[i - 1].frame)
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

  // aperto: a mão desce um tico no eixo do dedo e encolhe
  const aperto = noClique
    ? interpolate(frame - noClique.frame, [0, 4, 12], [0, 1, 0], {
        extrapolateLeft: 'clamp',
        extrapolateRight: 'clamp',
      })
    : 0

  // caminhando: inclina pro lado pra onde vai + balanço leve (o "passo")
  const inclinacao = interpolate(vx, [-14, 0, 14], [-11, 0, 11], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  })
  const balanco = velocidade > 0.6 ? Math.sin(frame / 3.6) * 2.2 : 0
  const giro = -4 + inclinacao + balanco + aperto * 2
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
          left: x,
          top: y + aperto * 5,
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
