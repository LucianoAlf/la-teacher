import React from 'react'
import { AbsoluteFill, interpolate, Sequence, useCurrentFrame } from 'remotion'
import { Telefone } from './ui/Telefone'
import { Agenda } from './cenas/Agenda'
import { Gravando } from './cenas/Gravando'
import { Resultado } from './cenas/Resultado'
import { C, FONT } from './tokens'

/** Legenda que acompanha a narração (o professor lê enquanto ouve). */
const Legenda: React.FC<{ texto: string; dur: number }> = ({ texto, dur }) => {
  const frame = useCurrentFrame()
  const op = interpolate(frame, [0, 8, dur - 8, dur], [0, 1, 1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  })
  return (
    <div
      style={{
        position: 'absolute',
        bottom: 40,
        left: 0,
        right: 0,
        textAlign: 'center',
        opacity: op,
        fontFamily: FONT,
      }}
    >
      <span
        style={{
          display: 'inline-block',
          background: 'rgba(10,15,14,.82)',
          border: `1px solid ${C.border}`,
          borderRadius: 999,
          padding: '11px 24px',
          fontSize: 25,
          fontWeight: 600,
          color: C.text,
          backdropFilter: 'blur(8px)',
        }}
      >
        {texto}
      </span>
    </div>
  )
}

/**
 * PILOTO (~18s) — valida a linguagem antes dos 3 minutos.
 * História: a agenda do dia → toca na aula → grava falando → vira prontuário
 * organizado + presença automática.
 */
export const Piloto: React.FC = () => {
  const frame = useCurrentFrame()

  // O aparelho ocupa a tela (nada de espaço morto) + zoom sutil que dá vida sem distrair.
  const escala = interpolate(frame, [0, 540], [1.28, 1.34])

  return (
    <AbsoluteFill style={{ background: '#05080A', fontFamily: FONT }}>
      {/* halo teal por trás do aparelho */}
      <AbsoluteFill
        style={{
          background: `radial-gradient(ellipse 62% 46% at 50% 42%, rgba(42,157,143,.20), transparent 70%)`,
        }}
      />

      <AbsoluteFill style={{ alignItems: 'center', justifyContent: 'center' }}>
        <div style={{ transform: `scale(${escala})` }}>
          <Telefone>
            <Sequence durationInFrames={150}>
              <Agenda alvo={0} />
            </Sequence>
            <Sequence from={150} durationInFrames={180}>
              <Gravando segundos={6} />
            </Sequence>
            <Sequence from={330}>
              <Resultado />
            </Sequence>
          </Telefone>
        </div>
      </AbsoluteFill>

      {/* narração legendada */}
      <Sequence durationInFrames={150}>
        <Legenda texto="Sua agenda do dia, já pronta." dur={150} />
      </Sequence>
      <Sequence from={150} durationInFrames={180}>
        <Legenda texto="Toque e fale. 30 segundos bastam." dur={180} />
      </Sequence>
      <Sequence from={330} durationInFrames={210}>
        <Legenda texto="O Fábio organiza — e a presença sai sozinha." dur={210} />
      </Sequence>
    </AbsoluteFill>
  )
}
