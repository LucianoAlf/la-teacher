import React from 'react'
import { interpolate, spring, useCurrentFrame, useVideoConfig } from 'remotion'
import { C, FONT } from '../tokens'

/** O Fábio como assinatura visual — anel teal que respira, igual ao app. */
const Selo: React.FC<{ escala: number }> = ({ escala }) => (
  <div
    style={{
      width: 132,
      height: 132,
      borderRadius: 999,
      background: C.brandSoft,
      border: `2px solid ${C.brandBorder}`,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      fontSize: 62,
      transform: `scale(${escala})`,
      boxShadow: `0 0 70px rgba(42,157,143,.35)`,
    }}
  >
    🎧
  </div>
)

export const Abertura: React.FC = () => {
  const frame = useCurrentFrame()
  const { fps } = useVideoConfig()
  const e = spring({ frame, fps, config: { damping: 14, stiffness: 90 } })
  const t = interpolate(frame, [8, 22], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  })
  return (
    <div
      style={{
        width: '100%',
        height: '100%',
        background: '#05080A',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        fontFamily: FONT,
        gap: 30,
      }}
    >
      <div
        style={{
          position: 'absolute',
          inset: 0,
          background:
            'radial-gradient(ellipse 50% 38% at 50% 46%, rgba(42,157,143,.22), transparent 70%)',
        }}
      />
      <Selo escala={0.6 + e * 0.4} />
      <div style={{ textAlign: 'center', opacity: t, transform: `translateY(${(1 - t) * 12}px)` }}>
        <div style={{ fontSize: 58, fontWeight: 800, color: C.text, letterSpacing: -1 }}>
          LA Teacher
        </div>
        <div style={{ fontSize: 27, color: C.brandLight, marginTop: 8, fontWeight: 600 }}>
          sua aula registrada em 30 segundos
        </div>
      </div>
    </div>
  )
}

export const Fecho: React.FC = () => {
  const frame = useCurrentFrame()
  const { fps } = useVideoConfig()
  const e = spring({ frame, fps, config: { damping: 16 } })
  return (
    <div
      style={{
        width: '100%',
        height: '100%',
        background: '#05080A',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        fontFamily: FONT,
        gap: 26,
      }}
    >
      <div
        style={{
          position: 'absolute',
          inset: 0,
          background:
            'radial-gradient(ellipse 50% 38% at 50% 50%, rgba(42,157,143,.20), transparent 70%)',
        }}
      />
      <Selo escala={0.75 + e * 0.25} />
      <div
        style={{
          fontSize: 46,
          fontWeight: 800,
          color: C.text,
          textAlign: 'center',
          opacity: e,
          lineHeight: 1.25,
        }}
      >
        Grava o conteúdo.
        <br />
        <span style={{ color: C.brandLight }}>O resto é comigo.</span>
      </div>
    </div>
  )
}
