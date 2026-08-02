import React from 'react'
import { interpolate, useCurrentFrame, Easing } from 'remotion'
import { Sfx, SFX } from './sfx'

/**
 * O DEDINHO — mão apontando que caminha pela tela e aperta os botões.
 * (Antes era uma bolinha translúcida herdada do estúdio do TOM; o Alf pediu
 * dedo, e dedo faz sentido: o LA Teacher é PWA de celular, o professor toca.)
 *
 * • A PONTA DO DEDO é o ponto de toque — as coordenadas dos keyframes são
 *   sempre onde o dedo encosta, não onde a mão fica.
 * • Caminhando: inclina levemente pro lado do movimento e balança de leve.
 * • No toque: a mão desce na direção do dedo, encolhe um tico e solta o anel.
 * Coordenadas no espaço do pai (position:relative).
 */

export type CursorKeyframe = { frame: number; x: number; y: number; click?: boolean }

// posição da ponta do dedo dentro do desenho (viewBox 120×160)
const PONTA_X = 41 / 120
const PONTA_Y = 10 / 160

const MaoSVG: React.FC<{ largura: number }> = ({ largura }) => {
  const altura = (largura * 160) / 120
  // as MESMAS formas desenhadas 2×: dark por baixo (contorno) e claro por cima
  const formas = (
    <>
      <rect x="30" y="6" width="22" height="72" rx="11" /> {/* dedo indicador */}
      <rect x="26" y="60" width="72" height="90" rx="30" /> {/* punho */}
      <circle cx="68" cy="68" r="14" /> {/* dedos dobrados */}
      <circle cx="86" cy="80" r="13" />
      <circle cx="93" cy="97" r="12" />
      <rect x="14" y="84" width="50" height="22" rx="11" transform="rotate(-14 39 95)" /> {/* polegar */}
    </>
  )
  return (
    <svg width={largura} height={altura} viewBox="0 0 120 160" style={{ display: 'block' }}>
      <g fill="#0E1614" stroke="#0E1614" strokeWidth="9" strokeLinejoin="round">
        {formas}
      </g>
      <g fill="#F4F1EC">{formas}</g>
      {/* unha, pra leitura rápida de "isso é um dedo" */}
      <rect x="35" y="13" width="12" height="15" rx="6" fill="#D9CFC4" />
    </svg>
  )
}

export const Dedo: React.FC<{
  keyframes: CursorKeyframe[]
  /** largura da mão em px (no espaço do telefone) */
  tamanho?: number
  clickSound?: boolean
}> = ({ keyframes, tamanho = 76, clickSound = true }) => {
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

  // aperto: a mão desce ~5px no eixo do dedo e encolhe um tico
  const aperto = noClique
    ? interpolate(frame - noClique.frame, [0, 4, 12], [0, 1, 0], {
        extrapolateLeft: 'clamp',
        extrapolateRight: 'clamp',
      })
    : 0

  // caminhando: inclina pro lado pra onde vai + balanço leve (o "passo")
  const inclinacao = interpolate(vx, [-14, 0, 14], [-13, 0, 13], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  })
  const balanco = velocidade > 0.6 ? Math.sin(frame / 3.4) * 2.6 : 0
  const giro = -8 + inclinacao + balanco + aperto * 2
  const escala = 1 - aperto * 0.07

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

      <div
        style={{
          position: 'absolute',
          left: x,
          top: y + aperto * 5,
          transform: `translate(${-PONTA_X * 100}%, ${-PONTA_Y * 100}%) rotate(${giro}deg) scale(${escala})`,
          transformOrigin: `${PONTA_X * 100}% ${PONTA_Y * 100}%`,
          filter: 'drop-shadow(0 10px 16px rgba(0,0,0,.55))',
          zIndex: 50,
          pointerEvents: 'none',
        }}
      >
        <MaoSVG largura={tamanho} />
      </div>
    </>
  )
}
