import React from 'react'
import { interpolate, useCurrentFrame } from 'remotion'
import { C } from '../tokens'

/** Tela de gravação: o professor fala, o Fábio escuta. O coração do produto. */
export const Gravando: React.FC<{ segundos?: number }> = ({ segundos = 8 }) => {
  const frame = useCurrentFrame()
  const op = interpolate(frame, [0, 10], [0, 1], { extrapolateRight: 'clamp' })
  const s = Math.floor(interpolate(frame, [0, 30 * segundos], [0, segundos], { extrapolateRight: 'clamp' }))

  return (
    <div
      style={{
        height: '100%',
        background: C.bgApp,
        opacity: op,
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        padding: 28,
      }}
    >
      <div style={{ fontSize: 13, color: C.textDim, marginBottom: 6 }}>11:00 · Canto</div>
      <div style={{ fontSize: 21, fontWeight: 700, color: C.text, marginBottom: 40 }}>Valentina</div>

      {/* onda de áudio reagindo à fala */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 5, height: 90, marginBottom: 34 }}>
        {Array.from({ length: 26 }).map((_, i) => {
          const h =
            18 +
            Math.abs(Math.sin(frame / 5 + i / 1.6)) * 52 * Math.abs(Math.sin(frame / 22 + i / 9))
          return (
            <div
              key={i}
              style={{
                width: 5,
                height: h,
                borderRadius: 3,
                background: i % 3 === 0 ? C.brandLight : C.brand,
                opacity: 0.55 + (h / 70) * 0.45,
              }}
            />
          )
        })}
      </div>

      {/* botão gravando (pulsa) */}
      <div
        style={{
          width: 84,
          height: 84,
          borderRadius: 999,
          background: C.danger,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          boxShadow: `0 0 0 ${8 + Math.sin(frame / 7) * 5}px rgba(239,68,68,.16)`,
        }}
      >
        <div style={{ width: 26, height: 26, borderRadius: 5, background: '#fff' }} />
      </div>

      <div style={{ marginTop: 20, fontSize: 15, fontWeight: 600, color: C.text }}>
        Gravando · 0:{String(s).padStart(2, '0')}
      </div>
      <div style={{ marginTop: 6, fontSize: 12.5, color: C.textMuted, textAlign: 'center' }}>
        Fala naturalmente. O Fábio organiza depois.
      </div>
    </div>
  )
}
