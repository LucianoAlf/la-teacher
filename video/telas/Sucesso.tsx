import React from 'react'
import { interpolate, spring, useCurrentFrame, useVideoConfig, Easing } from 'remotion'
import { C } from '../tokens'

/**
 * Tela de sucesso — réplica fiel: 16 confetes caindo (2.6s, 5 cores, rotate
 * 0→560°), check verde 92px (ícone 36, borda 2) com o pop elástico do app
 * (scale .4→1 overshoot), badges do que foi gravado e a assinatura mono.
 */

const CORES_CONFETE = ['#2A9D8F', '#E97B55', '#E91451', '#FACC15', '#60A5FA']

const Confete: React.FC<{ i: number }> = ({ i }) => {
  const frame = useCurrentFrame()
  // determinístico por índice — sem Math.random (quebraria o resume do render)
  const x = ((i * 137) % 100) / 100 // 0..1 da largura
  const delay = (i % 6) * 3
  const dur = 78 // 2.6s
  const t = interpolate(frame - delay, [0, dur], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.in(Easing.quad),
  })
  if (t >= 1) return null
  const tamanho = 7 + ((i * 31) % 6)
  return (
    <div
      style={{
        position: 'absolute',
        left: `${6 + x * 88}%`,
        top: -14,
        width: tamanho,
        height: tamanho * (i % 3 === 0 ? 0.5 : 1),
        borderRadius: i % 4 === 0 ? 999 : 2,
        background: CORES_CONFETE[i % CORES_CONFETE.length],
        transform: `translateY(${t * 620}px) rotate(${t * 560}deg)`,
        opacity: 1 - t * 0.35,
      }}
    />
  )
}

const Badge: React.FC<{ texto: string; desde: number }> = ({ texto, desde }) => {
  const frame = useCurrentFrame()
  const { fps } = useVideoConfig()
  const e = spring({ frame: frame - desde, fps, config: { damping: 200 } })
  return (
    <div
      style={{
        border: `1px solid ${C.borderStrong}`,
        background: C.bgSurface,
        borderRadius: 999,
        padding: '7px 14px',
        fontSize: 12.5,
        fontWeight: 600,
        color: C.text,
        opacity: e,
        transform: `translateY(${(1 - e) * 8}px)`,
      }}
    >
      {texto}
    </div>
  )
}

export const Sucesso: React.FC<{ badges?: string[]; sub?: string }> = ({
  badges = ['1 tronco', '1 fatia', '1 dever de casa'],
  sub = '1 aluno recebeu a aula no diário. Visível pra coordenação.',
}) => {
  const frame = useCurrentFrame()
  const { fps } = useVideoConfig()
  // pop do app: scale .4 → 1 com overshoot (cubic-bezier(.2,1.6,.4,1))
  const pop = spring({ frame: frame - 6, fps, config: { damping: 9, stiffness: 130 } })
  const texto = interpolate(frame, [16, 28], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  })

  return (
    <div
      style={{
        height: '100%',
        background: C.bgApp,
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        padding: '0 28px',
        position: 'relative',
        overflow: 'hidden',
      }}
    >
      {Array.from({ length: 16 }).map((_, i) => (
        <Confete key={i} i={i} />
      ))}

      {/* check verde 92px, ícone 36, borda 2 */}
      <div
        style={{
          width: 92,
          height: 92,
          borderRadius: 999,
          background: 'rgba(34,197,94,.12)',
          border: `2px solid ${C.success}`,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          transform: `scale(${0.4 + pop * 0.6})`,
          opacity: Math.min(1, pop * 2),
        }}
      >
        <svg width={36} height={36} viewBox="0 0 24 24" fill="none">
          <path
            d="M4.5 12.5l5 5 10-11"
            stroke="#4ADE80"
            strokeWidth="2.6"
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        </svg>
      </div>

      <div
        style={{
          marginTop: 26,
          fontSize: 21,
          fontWeight: 800,
          color: C.text,
          opacity: texto,
          transform: `translateY(${(1 - texto) * 10}px)`,
        }}
      >
        Registro gravado! 🎉
      </div>
      <div
        style={{
          marginTop: 8,
          fontSize: 13,
          color: C.textDim,
          textAlign: 'center',
          lineHeight: 1.5,
          opacity: texto,
        }}
      >
        {sub}
      </div>

      <div style={{ marginTop: 24, display: 'flex', gap: 8, flexWrap: 'wrap', justifyContent: 'center' }}>
        {badges.map((b, i) => (
          <Badge key={b} texto={b} desde={24 + i * 6} />
        ))}
      </div>

      <div
        style={{
          marginTop: 30,
          fontSize: 10.5,
          color: C.textMuted,
          fontFamily: 'ui-monospace, "Cascadia Mono", Consolas, monospace',
          opacity: interpolate(frame, [40, 52], [0, 1], {
            extrapolateLeft: 'clamp',
            extrapolateRight: 'clamp',
          }),
        }}
      >
        registrar_aula_fabio · 1 aula · origem áudio
      </div>
    </div>
  )
}
