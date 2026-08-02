import React from 'react'
import { interpolate, spring, useCurrentFrame, useVideoConfig } from 'remotion'
import { C, FONT } from '../tokens'
import { Card, TituloCard, Badge } from '../ui/Cartoes'
import { Ico } from '../ui/Icones'
import { ScreenHeader } from '../ui/AppShell'

/**
 * Ficha da Valentina (AlunoDetalhe): identidade com chips, bloco "aula de
 * hoje registrada", Jornada com a barra animando, Presença com a tirinha
 * honesta e o Histórico pedagógico com o selo "última aula".
 * `scrollY` rola; a barra de progresso anima na entrada.
 */

const TIRINHA: ('ok' | 'warn' | 'danger' | 'off')[] = ['ok', 'ok', 'warn', 'ok', 'ok', 'danger', 'ok', 'ok', 'warn', 'ok', 'ok', 'ok']
const COR = { ok: '#22C55E', warn: '#EAB308', danger: '#EF4444', off: '#2C3B36' }

export const FichaTela: React.FC<{ scrollY?: number }> = ({ scrollY = 0 }) => {
  const frame = useCurrentFrame()
  const { fps } = useVideoConfig()
  const barra = interpolate(frame, [14, 44], [0, 52.5], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' })

  const Chip: React.FC<{ children: React.ReactNode; ambar?: boolean }> = ({ children, ambar }) => (
    <span
      style={{
        fontSize: 12,
        padding: '4px 10px',
        borderRadius: 999,
        border: `1px solid ${ambar ? 'rgba(234,179,8,.45)' : C.border}`,
        background: ambar ? 'rgba(234,179,8,.12)' : C.bgApp,
        color: ambar ? '#FACC15' : C.textDim,
        display: 'inline-flex',
        alignItems: 'center',
        gap: 5,
      }}
    >
      {children}
    </span>
  )

  return (
    <div style={{ height: '100%', background: C.bgApp, fontFamily: FONT, position: 'relative', overflow: 'hidden' }}>
      <div style={{ transform: `translateY(${-scrollY}px)` }}>
        <ScreenHeader titulo="Valentina" subtitulo="Campo Grande" />

        <div style={{ padding: '0 16px 40px', display: 'flex', flexDirection: 'column', gap: 12 }}>
          {/* identidade */}
          <Card style={{ textAlign: 'center', padding: '18px 14px' }}>
            <div
              style={{
                width: 84,
                height: 84,
                borderRadius: 999,
                margin: '0 auto',
                background: 'linear-gradient(135deg,#2A9D8F,#1B6E64)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                color: '#F5F5F5',
                fontSize: 30,
                fontWeight: 800,
              }}
            >
              V
            </div>
            <div style={{ marginTop: 12, fontSize: 18, fontWeight: 800, color: C.text }}>Valentina</div>
            <div style={{ marginTop: 10, display: 'flex', gap: 6, justifyContent: 'center', flexWrap: 'wrap' }}>
              <Chip>8 anos · Kids</Chip>
              <Chip>Campo Grande</Chip>
              <Chip>1 ano e 2 meses de casa</Chip>
            </div>
          </Card>

          {/* aula de hoje — registrada (continuidade da história) */}
          <div
            style={{
              borderRadius: 16,
              background: 'rgba(34,197,94,.12)',
              border: '1px solid rgba(34,197,94,.35)',
              padding: 13,
              display: 'flex',
              alignItems: 'center',
              gap: 11,
            }}
          >
            <span style={{ color: '#4ADE80' }}>
              <Ico n="check" t={16} />
            </span>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 13.5, fontWeight: 700, color: '#4ADE80' }}>Aula de hoje registrada</div>
              <div style={{ fontSize: 12, color: C.textDim, marginTop: 1 }}>Canto · 11h</div>
            </div>
            <span style={{ fontSize: 12.5, fontWeight: 600, color: C.textDim }}>Regravar</span>
          </div>

          {/* jornada */}
          <Card>
            <TituloCard icone="graduation" texto="Jornada" />
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <div style={{ flex: 1 }}>
                <span style={{ fontSize: 14, fontWeight: 700, color: C.text }}>Canto</span>
                <span style={{ fontSize: 12, color: C.textDim }}> · Segunda · 11:00</span>
              </div>
              <span style={{ fontSize: 13, fontWeight: 600, color: C.text }}>Aula 21/40</span>
            </div>
            <div style={{ marginTop: 10, height: 6, borderRadius: 999, background: C.bgApp, overflow: 'hidden' }}>
              <div style={{ width: `${barra}%`, height: '100%', borderRadius: 999, background: C.brand }} />
            </div>
          </Card>

          {/* presença */}
          <Card>
            <TituloCard icone="calendarCheck" texto="Presença" />
            <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
              {TIRINHA.map((t, i) => {
                const e = spring({ frame: frame - 20 - i * 2, fps, config: { damping: 200 } })
                return (
                  <span
                    key={i}
                    style={{
                      width: 11,
                      height: 11,
                      borderRadius: 999,
                      background: COR[t],
                      opacity: 0.25 + e * 0.75,
                    }}
                  />
                )
              })}
            </div>
            <div style={{ marginTop: 10, fontSize: 11.5, color: C.textDim }}>
              <b style={{ color: '#F87171' }}>1</b> falta confirmada ·{' '}
              <b style={{ color: '#FACC15' }}>2</b> não conferidas (aula sem chamada real)
            </div>
            <div style={{ marginTop: 8, display: 'flex', justifyContent: 'space-between', fontSize: 12.5 }}>
              <span style={{ color: C.textDim }}>Presença confirmada</span>
              <b style={{ color: C.text }}>92%</b>
            </div>
            <div style={{ marginTop: 4, display: 'flex', justifyContent: 'space-between', fontSize: 12.5 }}>
              <span style={{ color: C.textDim }}>Última aula</span>
              <b style={{ color: C.text }}>hoje</b>
            </div>
          </Card>

          {/* histórico pedagógico */}
          <Card>
            <TituloCard
              icone="historyClock"
              texto="Histórico pedagógico"
              direita={<span style={{ fontSize: 11.5, color: C.textDim }}>21 aulas</span>}
            />

            <div style={{ borderRadius: 12, border: `1px solid ${C.border}`, padding: 11, marginBottom: 8 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 7, marginBottom: 6 }}>
                <span style={{ fontSize: 12.5, fontWeight: 700, color: C.text }}>3 ago · Canto</span>
                <span
                  style={{
                    fontSize: 10,
                    fontWeight: 700,
                    textTransform: 'uppercase',
                    letterSpacing: '.4px',
                    color: C.brandLight,
                    background: C.brandSoft,
                    borderRadius: 999,
                    padding: '2px 8px',
                  }}
                >
                  última aula
                </span>
                <span style={{ color: C.brandLight, marginLeft: 'auto' }}>
                  <Ico n="wand" t={11} />
                </span>
                <Badge tom="teal">você</Badge>
              </div>
              <div style={{ fontSize: 12.5, color: C.textDim, lineHeight: 1.5 }}>
                “Temos que Pegar” (Pokémon) + vocalizes e respiração. Cantou a música inteira sem
                apoio no refrão.
              </div>
              <div
                style={{
                  marginTop: 8,
                  borderRadius: 10,
                  background: 'rgba(234,179,8,.12)',
                  border: '1px solid rgba(234,179,8,.3)',
                  padding: '7px 10px',
                  fontSize: 12,
                  color: '#FACC15',
                  display: 'flex',
                  alignItems: 'center',
                  gap: 7,
                }}
              >
                <Ico n="house" t={11} /> Ouvir a música para decorar a letra.
              </div>
            </div>

            <div style={{ borderRadius: 12, border: `1px solid ${C.border}`, padding: 11 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 7, marginBottom: 6 }}>
                <span style={{ fontSize: 12.5, fontWeight: 700, color: C.text }}>27 jul · Canto</span>
                <span style={{ color: C.brandLight, marginLeft: 'auto' }}>
                  <Ico n="wand" t={11} />
                </span>
                <Badge tom="teal">você</Badge>
              </div>
              <div style={{ fontSize: 12.5, color: C.textDim, lineHeight: 1.5 }}>
                Aquecimento vocal e primeira leitura da letra. Afinação firme no registro médio.
              </div>
            </div>

            <div
              style={{
                marginTop: 10,
                textAlign: 'center',
                fontSize: 12.5,
                fontWeight: 600,
                color: C.brandLight,
              }}
            >
              Ver 19 aulas anteriores
            </div>
          </Card>
        </div>
      </div>
    </div>
  )
}
