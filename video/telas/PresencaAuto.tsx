import React from 'react'
import { spring, useCurrentFrame, useVideoConfig } from 'remotion'
import { C, FONT } from '../tokens'
import { AulaRow, Card, TituloCard } from '../ui/Cartoes'

/**
 * Cena "presença automática": a aula da Valentina com os badges virando
 * verde (Chamada ✓ / Registrada) e a tirinha de presença acendendo bolinha
 * a bolinha, com o selo "Presença lançada automaticamente" pulsando.
 */

// histórico da tirinha: verde=presente, âmbar=não conferida, vermelho=falta
const TIRINHA: ('ok' | 'warn' | 'danger')[] = ['ok', 'ok', 'warn', 'ok', 'ok', 'danger', 'ok', 'ok', 'warn', 'ok', 'ok']
const COR = { ok: '#22C55E', warn: '#EAB308', danger: '#EF4444' }

export const PresencaAuto: React.FC<{ seloFrame: number }> = ({ seloFrame }) => {
  const frame = useCurrentFrame()
  const { fps } = useVideoConfig()
  const selo = spring({ frame: frame - seloFrame, fps, config: { damping: 12, stiffness: 90 } })
  const pulso = 1 + Math.abs(Math.sin(Math.max(0, frame - seloFrame) / 14)) * 0.03

  return (
    <div style={{ height: '100%', background: C.bgApp, fontFamily: FONT, padding: '14px 16px' }}>
      <div style={{ fontSize: 17, fontWeight: 700, color: C.text, marginBottom: 2 }}>Registro gravado</div>
      <div style={{ fontSize: 12, color: C.textDim, marginBottom: 14 }}>Canto · Valentina · Seg, 03/08 · 11h</div>

      <Card>
        <AulaRow
          aula={{
            hora: '11:00',
            titulo: 'Valentina',
            detalhe: 'Canto · Individual',
            badges: [
              { tom: 'ok', texto: 'Chamada' },
              { tom: 'ok', texto: 'Registrada' },
            ],
          }}
        />
      </Card>

      {/* selo verde */}
      <div
        style={{
          marginTop: 12,
          background: 'rgba(34,197,94,.12)',
          border: '1px solid rgba(34,197,94,.6)',
          borderRadius: 12,
          padding: '13px 14px',
          display: 'flex',
          alignItems: 'center',
          gap: 11,
          opacity: selo,
          transform: `scale(${(0.9 + selo * 0.1) * pulso})`,
          boxShadow: '0 0 32px rgba(34,197,94,.20)',
        }}
      >
        <div style={{ fontSize: 20 }}>✅</div>
        <div>
          <div style={{ fontSize: 14, fontWeight: 700, color: '#4ADE80' }}>
            Presença lançada automaticamente
          </div>
          <div style={{ fontSize: 11.5, color: C.textDim, marginTop: 2 }}>
            Você gravou o conteúdo — o resto é comigo.
          </div>
        </div>
      </div>

      {/* tirinha de presença acendendo */}
      <Card style={{ marginTop: 12 }}>
        <TituloCard icone="calendarCheck" texto="Presença" />
        <div style={{ display: 'flex', gap: 6, alignItems: 'center', flexWrap: 'wrap' }}>
          {TIRINHA.map((t, i) => {
            const e = spring({ frame: frame - 8 - i * 2, fps, config: { damping: 200 } })
            return (
              <span
                key={i}
                style={{
                  width: 11,
                  height: 11,
                  borderRadius: 999,
                  background: COR[t],
                  opacity: 0.25 + e * 0.75,
                  transform: `scale(${0.6 + e * 0.4})`,
                }}
              />
            )
          })}
          {/* a bolinha de HOJE, nascendo verde */}
          <span
            style={{
              width: 11,
              height: 11,
              borderRadius: 999,
              background: COR.ok,
              boxShadow: `0 0 0 ${3 * selo}px rgba(34,197,94,.25)`,
              opacity: selo,
              transform: `scale(${0.4 + selo * 0.6})`,
            }}
          />
        </div>
        <div style={{ marginTop: 10, fontSize: 11.5, color: C.textDim }}>
          <b style={{ color: '#F87171' }}>1</b> falta confirmada ·{' '}
          <b style={{ color: '#FACC15' }}>2</b> não conferidas (aula sem chamada real)
        </div>
      </Card>
    </div>
  )
}
