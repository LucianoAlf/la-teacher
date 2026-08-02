import React from 'react'
import { interpolate, spring, useCurrentFrame, useVideoConfig } from 'remotion'
import { C } from '../tokens'

/** Agenda real do Matheus em 03/08 — os dados vêm da fabio_briefing_matinal. */
export const AULAS = [
  { hora: '11:00', curso: 'Canto', alunos: 'Valentina', sala: 'Palavra Cantada', feito: false },
  { hora: '15:00', curso: 'Canto', alunos: 'Amanda', sala: 'Palavra Cantada', feito: false },
  { hora: '17:00', curso: 'Musicalização', alunos: 'Gustavo e Maria Isabel', sala: 'Palavra Cantada', feito: false },
  { hora: '18:00', curso: 'Musicalização', alunos: 'Arthur', sala: 'Balão Mágico', feito: false },
]

const Cabecalho: React.FC<{ op: number }> = ({ op }) => (
  <div style={{ padding: '18px 20px 12px', opacity: op }}>
    <div style={{ fontSize: 13, color: C.textDim, letterSpacing: 0.3 }}>Segunda, 3 de agosto</div>
    <div style={{ fontSize: 26, fontWeight: 700, color: C.text, marginTop: 3 }}>Minha agenda</div>
  </div>
)

export const CardAula: React.FC<{
  aula: (typeof AULAS)[number]
  destaque?: number
  gravado?: boolean
}> = ({ aula, destaque = 0, gravado = false }) => (
  <div
    style={{
      background: C.bgSurface,
      border: `1px solid ${destaque > 0 ? C.brand : C.border}`,
      borderRadius: 14,
      padding: 14,
      marginBottom: 10,
      display: 'flex',
      gap: 13,
      alignItems: 'center',
      transform: `scale(${1 + destaque * 0.02})`,
      boxShadow: destaque > 0 ? `0 0 0 ${destaque * 3}px ${C.brandSoft}` : 'none',
    }}
  >
    <div
      style={{
        width: 54,
        textAlign: 'center',
        fontSize: 17,
        fontWeight: 700,
        color: destaque > 0 ? C.brandLight : C.text,
      }}
    >
      {aula.hora}
    </div>
    <div style={{ flex: 1, minWidth: 0 }}>
      <div style={{ fontSize: 15, fontWeight: 600, color: C.text }}>{aula.curso}</div>
      <div
        style={{
          fontSize: 12.5,
          color: C.textDim,
          marginTop: 2,
          whiteSpace: 'nowrap',
          overflow: 'hidden',
          textOverflow: 'ellipsis',
        }}
      >
        {aula.alunos} · {aula.sala}
      </div>
    </div>
    {gravado ? (
      <div
        style={{
          fontSize: 11,
          fontWeight: 700,
          color: C.success,
          background: 'rgba(34,197,94,.14)',
          border: '1px solid rgba(34,197,94,.35)',
          borderRadius: 999,
          padding: '4px 9px',
          whiteSpace: 'nowrap',
        }}
      >
        ✓ registrada
      </div>
    ) : (
      <div
        style={{
          width: 30,
          height: 30,
          borderRadius: 999,
          border: `1px solid ${destaque > 0 ? C.brand : C.borderStrong}`,
          background: destaque > 0 ? C.brandSoft : 'transparent',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          fontSize: 13,
          color: destaque > 0 ? C.brandLight : C.textDim,
        }}
      >
        ›
      </div>
    )}
  </div>
)

/** Tela da agenda: os cards entram em cascata e o card-alvo pulsa. */
export const Agenda: React.FC<{ alvo?: number; gravadas?: number[] }> = ({
  alvo = -1,
  gravadas = [],
}) => {
  const frame = useCurrentFrame()
  const { fps } = useVideoConfig()
  const op = interpolate(frame, [0, 12], [0, 1], { extrapolateRight: 'clamp' })

  return (
    <div style={{ height: '100%', background: C.bgApp, display: 'flex', flexDirection: 'column' }}>
      <Cabecalho op={op} />
      <div style={{ padding: '0 16px', flex: 1 }}>
        {AULAS.map((aula, i) => {
          const entrada = spring({ frame: frame - 6 - i * 4, fps, config: { damping: 200 } })
          const pulso =
            alvo === i
              ? Math.max(0, Math.sin((frame - 20) / 6)) * interpolate(frame, [20, 34], [0, 1], {
                  extrapolateLeft: 'clamp',
                  extrapolateRight: 'clamp',
                })
              : 0
          return (
            <div
              key={aula.hora}
              style={{
                opacity: entrada,
                transform: `translateY(${(1 - entrada) * 14}px)`,
              }}
            >
              <CardAula aula={aula} destaque={pulso} gravado={gravadas.includes(i)} />
            </div>
          )
        })}
      </div>
    </div>
  )
}
