import React from 'react'
import { interpolate, spring, useCurrentFrame, useVideoConfig } from 'remotion'
import { C } from '../tokens'

/**
 * Tela "Registrar aula" — réplica fiel (medidas de docs/video/REFERENCIA-telas.md):
 * mic teal 88px (ícone 30) · "toque pra começar · máx. 5 min" · 18 barras wave
 * (10→56px, delay (i%5)*0.15s, opacidade 0.55+nível*0.45) · timer mono 38px ·
 * stop vermelho 74px (quadrado branco 24).
 *
 * Dirigida por frames: antes de `micFrame` = repouso; 12f de "Pedindo acesso ao
 * microfone…"; depois grava até `stopFrame`; daí congela e mostra o chip Gravado.
 */

const MicGlyph: React.FC<{ tamanho: number; cor: string }> = ({ tamanho, cor }) => (
  <svg width={tamanho} height={tamanho} viewBox="0 0 24 24" fill="none">
    <rect x="9" y="2.5" width="6" height="11" rx="3" fill={cor} />
    <path
      d="M5.5 11a6.5 6.5 0 0 0 13 0"
      stroke={cor}
      strokeWidth="1.9"
      strokeLinecap="round"
      fill="none"
    />
    <line x1="12" y1="17.5" x2="12" y2="20.5" stroke={cor} strokeWidth="1.9" strokeLinecap="round" />
    <line x1="8.5" y1="21" x2="15.5" y2="21" stroke={cor} strokeWidth="1.9" strokeLinecap="round" />
  </svg>
)

export const Gravar: React.FC<{ micFrame: number; stopFrame: number }> = ({
  micFrame,
  stopFrame,
}) => {
  const frame = useCurrentFrame()
  const { fps } = useVideoConfig()

  const ACESSO_F = 12 // "Pedindo acesso ao microfone…"
  const POS_STOP_F = 10 // o stop fica na tela durante o aperto; só depois vira o chip
  const gravandoDesde = micFrame + ACESSO_F
  const fase: 'repouso' | 'pedindo' | 'gravando' | 'gravado' =
    frame < micFrame
      ? 'repouso'
      : frame < gravandoDesde
        ? 'pedindo'
        : frame < stopFrame + POS_STOP_F
          ? 'gravando'
          : 'gravado'

  const decorrido = Math.max(0, Math.floor((Math.min(frame, stopFrame) - gravandoDesde) / fps))
  const timer = `0:${String(decorrido).padStart(2, '0')}`

  const entrada = interpolate(frame, [0, 10], [0, 1], { extrapolateRight: 'clamp' })
  const chipGravado = spring({ frame: frame - stopFrame - 14, fps, config: { damping: 13 } })

  return (
    <div
      style={{
        height: '100%',
        background: C.bgApp,
        opacity: entrada,
        display: 'flex',
        flexDirection: 'column',
      }}
    >
      {/* cabeçalho com o contexto da sessão */}
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: 12,
          padding: '14px 18px',
          borderBottom: `1px solid ${C.border}`,
        }}
      >
        <div
          style={{
            width: 36,
            height: 36,
            borderRadius: 999,
            border: `1px solid ${C.border}`,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            color: C.textDim,
            fontSize: 15,
          }}
        >
          ←
        </div>
        <div
          style={{
            width: 38,
            height: 38,
            borderRadius: 12,
            background: C.brandSoft,
            border: `1px solid ${C.brandBorder}`,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            color: C.brandLight,
            fontSize: 16,
          }}
        >
          ♪
        </div>
        <div>
          <div style={{ fontSize: 15, fontWeight: 700, color: C.text }}>Canto — Valentina</div>
          <div style={{ fontSize: 12, color: C.textDim, marginTop: 1 }}>Canto · 11h</div>
        </div>
      </div>

      {/* palco da gravação */}
      <div
        style={{
          flex: 1,
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          padding: '0 28px',
          position: 'relative',
        }}
      >
        {fase === 'repouso' || fase === 'pedindo' ? (
          <>
            <div
              style={{
                fontSize: 17,
                fontWeight: 700,
                color: C.text,
                textAlign: 'center',
                lineHeight: 1.5,
              }}
            >
              Fala pra mim como foi a aula 🎧
            </div>
            <div
              style={{
                marginTop: 8,
                fontSize: 13,
                color: C.textDim,
                textAlign: 'center',
                lineHeight: 1.5,
              }}
            >
              Pode ser natural, do seu jeito. Eu organizo.
            </div>

            {/* mic teal 88px — o coração do produto */}
            <div
              style={{
                marginTop: 44,
                width: 88,
                height: 88,
                borderRadius: 999,
                background: C.brand,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                boxShadow: `0 10px 25px -5px rgba(42,157,143,.45), 0 0 0 ${
                  8 + Math.sin(frame / 9) * 4
                }px ${C.brandSoft}`,
              }}
            >
              <MicGlyph tamanho={30} cor="#0A0F0E" />
            </div>

            <div
              style={{
                marginTop: 26,
                fontSize: 11,
                fontWeight: 600,
                letterSpacing: '.5px',
                textTransform: 'uppercase',
                color: C.textMuted,
              }}
            >
              {fase === 'pedindo' ? (
                <span style={{ color: C.brandLight }}>Pedindo acesso ao microfone…</span>
              ) : (
                'toque pra começar · máx. 5 min'
              )}
            </div>
          </>
        ) : (
          <>
            {/* 18 barras animate-wave: 10→56px, delay (i%5)*0.15s */}
            <div style={{ display: 'flex', alignItems: 'center', gap: 6, height: 64 }}>
              {Array.from({ length: 18 }).map((_, i) => {
                const congela = frame >= stopFrame // parou de gravar no aperto
                const f = congela ? stopFrame : frame
                const faseBarra = ((f / fps - (i % 5) * 0.15) / 1) * Math.PI * 2
                const nivel = (Math.sin(faseBarra) + 1) / 2
                const h = 10 + nivel * 46
                return (
                  <div
                    key={i}
                    style={{
                      width: 5,
                      height: congela ? 14 : h,
                      borderRadius: 3,
                      background: C.brand,
                      opacity: congela ? 0.4 : 0.55 + nivel * 0.45,
                    }}
                  />
                )
              })}
            </div>

            {/* timer mono 38px */}
            <div
              style={{
                marginTop: 30,
                fontSize: 38,
                fontWeight: 700,
                color: C.text,
                fontFamily: 'ui-monospace, "Cascadia Mono", Consolas, monospace',
                fontVariantNumeric: 'tabular-nums',
              }}
            >
              {timer}
            </div>

            {fase === 'gravando' ? (
              <>
                {/* stop vermelho 74px */}
                <div
                  style={{
                    marginTop: 34,
                    width: 74,
                    height: 74,
                    borderRadius: 999,
                    background: C.danger,
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    boxShadow: `0 0 0 ${7 + Math.sin(frame / 7) * 4}px rgba(239,68,68,.16)`,
                  }}
                >
                  <div style={{ width: 24, height: 24, borderRadius: 5, background: '#fff' }} />
                </div>
                <div style={{ marginTop: 18, fontSize: 12.5, color: C.textMuted }}>
                  Fala naturalmente. O Fábio organiza depois.
                </div>
              </>
            ) : (
              <div
                style={{
                  marginTop: 34,
                  display: 'flex',
                  alignItems: 'center',
                  gap: 10,
                  background: C.brandSoft,
                  border: `1px solid ${C.brandBorder}`,
                  borderRadius: 999,
                  padding: '10px 20px',
                  opacity: chipGravado,
                  transform: `scale(${0.7 + chipGravado * 0.3})`,
                }}
              >
                <span style={{ color: C.brandLight, fontSize: 15 }}>✓</span>
                <span style={{ fontSize: 14, fontWeight: 700, color: C.text }}>
                  Gravado — {timer}
                </span>
              </div>
            )}
          </>
        )}
      </div>
    </div>
  )
}
