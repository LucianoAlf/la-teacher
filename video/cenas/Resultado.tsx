import React from 'react'
import { interpolate, spring, useCurrentFrame, useVideoConfig } from 'remotion'
import { C } from '../tokens'

/** O que o áudio virou: prontuário organizado + a presença que sai de brinde. */
const CAMPOS = [
  { rotulo: 'Foco', valor: 'Decorar a letra, com preparação vocal e respiratória.' },
  { rotulo: 'Trabalho feito', valor: '“Temos que Pegar” (Pokémon) + vocalizes e respiração.' },
  { rotulo: 'Música', valor: '“Temos que Pegar” — abertura do Pokémon' },
  { rotulo: 'Dever de casa', valor: 'Ouvir a música para decorar a letra' },
]

/** `destaquePresenca`: a cena seguinte reusa o mesmo prontuário, já montado,
 *  e joga a luz no selo verde — que é o ponto da narração ali. */
export const Resultado: React.FC<{ destaquePresenca?: boolean }> = ({
  destaquePresenca = false,
}) => {
  const frameReal = useCurrentFrame()
  const { fps } = useVideoConfig()
  const frame = destaquePresenca ? frameReal + 70 : frameReal

  return (
    <div style={{ height: '100%', background: C.bgApp, padding: '20px 18px' }}>
      {/* o Fábio assinando o trabalho */}
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: 10,
          marginBottom: 16,
          opacity: interpolate(frame, [0, 10], [0, 1], { extrapolateRight: 'clamp' }),
        }}
      >
        <div
          style={{
            width: 34,
            height: 34,
            borderRadius: 999,
            background: C.brandSoft,
            border: `1px solid ${C.brandBorder}`,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            fontSize: 16,
          }}
        >
          🎧
        </div>
        <div>
          <div style={{ fontSize: 14, fontWeight: 700, color: C.text }}>Fábio organizou</div>
          <div style={{ fontSize: 11.5, color: C.textDim }}>a partir do seu áudio</div>
        </div>
      </div>

      {/* campos aparecendo um a um */}
      {CAMPOS.map((c, i) => {
        const e = spring({ frame: frame - 12 - i * 9, fps, config: { damping: 200 } })
        return (
          <div
            key={c.rotulo}
            style={{
              background: C.bgSurface,
              border: `1px solid ${C.border}`,
              borderRadius: 12,
              padding: '11px 13px',
              marginBottom: 9,
              opacity: e,
              transform: `translateX(${(1 - e) * -16}px)`,
            }}
          >
            <div
              style={{
                fontSize: 10.5,
                fontWeight: 700,
                color: C.brandLight,
                textTransform: 'uppercase',
                letterSpacing: 0.7,
              }}
            >
              {c.rotulo}
            </div>
            <div style={{ fontSize: 13.5, color: C.text, marginTop: 4, lineHeight: 1.45 }}>
              {c.valor}
            </div>
          </div>
        )
      })}

      {/* o pulo do gato: presença automática */}
      {(() => {
        const e = spring({ frame: frame - 56, fps, config: { damping: 12, stiffness: 90 } })
        // na cena dedicada, o selo pulsa pra puxar o olho enquanto a voz fala dele
        const pulso = destaquePresenca ? 1 + Math.abs(Math.sin(frameReal / 14)) * 0.035 : 1
        return (
          <div
            style={{
              marginTop: 8,
              background: 'rgba(34,197,94,.12)',
              border: `1px solid rgba(34,197,94,${destaquePresenca ? 0.7 : 0.4})`,
              borderRadius: 12,
              padding: '13px 14px',
              display: 'flex',
              alignItems: 'center',
              gap: 11,
              opacity: e,
              transform: `scale(${(0.9 + e * 0.1) * pulso})`,
              boxShadow: destaquePresenca ? '0 0 32px rgba(34,197,94,.22)' : 'none',
            }}
          >
            <div style={{ fontSize: 20 }}>✅</div>
            <div>
              <div style={{ fontSize: 14, fontWeight: 700, color: C.success }}>
                Presença lançada automaticamente
              </div>
              <div style={{ fontSize: 11.5, color: C.textDim, marginTop: 2 }}>
                Você gravou o conteúdo — o resto é comigo.
              </div>
            </div>
          </div>
        )
      })()}
    </div>
  )
}
