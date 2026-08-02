import React from 'react'
import { C, FONT } from '../tokens'

/** Moldura de celular — o LA Teacher é um PWA, o professor usa no telefone. */
export const Telefone: React.FC<{
  children: React.ReactNode
  hora?: string
}> = ({ children, hora = '7:58' }) => (
  <div
    style={{
      width: 430,
      height: 880,
      borderRadius: 52,
      background: C.bgApp,
      border: '10px solid #050807',
      boxShadow: '0 40px 120px rgba(0,0,0,.6), 0 0 0 2px rgba(42,157,143,.12)',
      overflow: 'hidden',
      position: 'relative',
      fontFamily: FONT,
      display: 'flex',
      flexDirection: 'column',
    }}
  >
    {/* status bar */}
    <div
      style={{
        height: 44,
        flexShrink: 0,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        padding: '0 26px',
        fontSize: 13,
        fontWeight: 600,
        color: C.text,
      }}
    >
      <span>{hora}</span>
      <div style={{ display: 'flex', gap: 5, alignItems: 'center' }}>
        {[0, 1, 2].map((i) => (
          <div
            key={i}
            style={{
              width: 3,
              height: 7 + i * 3,
              borderRadius: 1,
              background: C.text,
              opacity: 0.9,
            }}
          />
        ))}
        <div
          style={{
            marginLeft: 4,
            width: 22,
            height: 11,
            borderRadius: 3,
            border: `1.5px solid ${C.textDim}`,
            padding: 1.5,
          }}
        >
          <div style={{ width: '75%', height: '100%', borderRadius: 1, background: C.success }} />
        </div>
      </div>
    </div>
    <div style={{ flex: 1, overflow: 'hidden', position: 'relative' }}>{children}</div>
  </div>
)
