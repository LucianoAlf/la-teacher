import React from 'react'
import { interpolate, spring, staticFile, useCurrentFrame, useVideoConfig } from 'remotion'
import { C, FONT, FONT_MARCA } from '../tokens'

/**
 * Vinhetas de marca em tela cheia (1080×1920). O personagem é o FÁBIO COLORIDO
 * de verdade (public/brand/fabio-avatar.svg) com o glow rosa do login — nunca
 * emoji (decisão do Alf, 02/08). Título na Prompt 900, "LA" no rosa da família.
 */

const Fabio: React.FC<{ tamanho: number; escala: number; flutua?: boolean }> = ({
  tamanho,
  escala,
  flutua = false,
}) => {
  const frame = useCurrentFrame()
  // bob do app: translateY 0 → −7 → 0 em 2.2s (aqui ampliado pro palco grande)
  const bob = flutua ? Math.sin((frame / (2.2 * 30)) * Math.PI * 2) * -12 : 0
  return (
    <img
      src={staticFile('brand/fabio-avatar.svg')}
      alt="Fábio"
      style={{
        width: tamanho,
        height: 'auto',
        transform: `scale(${escala}) translateY(${bob}px)`,
        filter: 'drop-shadow(0 0 54px rgb(233 20 81 / .30))',
      }}
    />
  )
}

export const Abertura: React.FC = () => {
  const frame = useCurrentFrame()
  const { fps } = useVideoConfig()
  const e = spring({ frame, fps, config: { damping: 14, stiffness: 90 } })
  const t = interpolate(frame, [10, 26], [0, 1], {
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
        gap: 56,
      }}
    >
      <div
        style={{
          position: 'absolute',
          inset: 0,
          background:
            'radial-gradient(ellipse 52% 34% at 50% 44%, rgba(42,157,143,.22), transparent 70%)',
        }}
      />
      <Fabio tamanho={330} escala={0.6 + e * 0.4} flutua />
      <div style={{ textAlign: 'center', opacity: t, transform: `translateY(${(1 - t) * 26}px)` }}>
        <div
          style={{
            fontFamily: FONT_MARCA,
            fontSize: 104,
            fontWeight: 900,
            letterSpacing: -2,
            lineHeight: 1,
          }}
        >
          <span style={{ color: C.pink }}>LA</span> <span style={{ color: C.text }}>Teacher</span>
        </div>
        <div style={{ fontSize: 40, color: C.brandLight, marginTop: 24, fontWeight: 600 }}>
          suas aulas registradas em segundos
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
        gap: 52,
      }}
    >
      <div
        style={{
          position: 'absolute',
          inset: 0,
          background:
            'radial-gradient(ellipse 52% 34% at 50% 50%, rgba(42,157,143,.20), transparent 70%)',
        }}
      />
      <Fabio tamanho={300} escala={0.75 + e * 0.25} flutua />
      <div
        style={{
          fontSize: 76,
          fontWeight: 800,
          color: C.text,
          textAlign: 'center',
          opacity: e,
          lineHeight: 1.3,
          letterSpacing: -1,
        }}
      >
        Grava o conteúdo.
        <br />
        <span style={{ color: C.brandLight }}>O resto é comigo.</span>
      </div>
      <div
        style={{
          fontFamily: FONT_MARCA,
          fontSize: 44,
          fontWeight: 900,
          opacity: interpolate(frame, [28, 44], [0, 1], {
            extrapolateLeft: 'clamp',
            extrapolateRight: 'clamp',
          }),
        }}
      >
        <span style={{ color: C.pink }}>LA</span> <span style={{ color: C.text }}>Teacher</span>
      </div>
    </div>
  )
}
