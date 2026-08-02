import React from 'react'
import { interpolate, useCurrentFrame } from 'remotion'
import { C, FONT } from '../tokens'
import { Ico } from '../ui/Icones'

/**
 * Preview antes de mandar — réplica do estado "parado" do GravarAula:
 * fone 56px teal-soft, "Gravado — 0:38", player de 32 barras (as tocadas
 * acendem em teal), botões Enviar pro Fábio / Re-gravar.
 * `playFrame` inicia a reprodução; `enviarFrame` vira "Subindo seu áudio…".
 */
export const Ouvir: React.FC<{ playFrame: number; enviarFrame: number }> = ({
  playFrame,
  enviarFrame,
}) => {
  const frame = useCurrentFrame()
  const enviando = frame >= enviarFrame + 8
  const DURACAO = 38
  const tocado = Math.max(0, Math.min(1, (frame - playFrame) / (30 * 6))) // 6s de "escuta" viram a barra toda
  const tempoTocado = Math.floor(tocado * DURACAO)

  return (
    <div
      style={{
        height: '100%',
        background: C.bgApp,
        fontFamily: FONT,
        display: 'flex',
        flexDirection: 'column',
      }}
    >
      {/* header + contexto */}
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
          }}
        >
          <Ico n="arrowLeft" t={14} />
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

      <div
        style={{
          flex: 1,
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          padding: '0 28px',
        }}
      >
        {enviando ? (
          <div style={{ textAlign: 'center', color: C.textDim, fontSize: 13 }}>
            <div style={{ color: C.brandLight, marginBottom: 12, transform: `translateY(${Math.sin(frame / 4) * 4}px)` }}>
              <Ico n="cloudUp" t={30} />
            </div>
            Subindo seu áudio…
          </div>
        ) : (
          <>
            <div
              style={{
                width: 56,
                height: 56,
                borderRadius: 999,
                background: C.brandSoft,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                color: C.brandLight,
              }}
            >
              <Ico n="headphones" t={22} />
            </div>
            <div style={{ marginTop: 16, fontSize: 17, fontWeight: 700, color: C.text }}>
              Gravado — 0:38
            </div>
            <div style={{ marginTop: 6, fontSize: 12.5, color: C.textDim }}>
              Confere se ficou bom antes de mandar 👇
            </div>

            {/* player: 32 barras, tocadas acendem em teal */}
            <div style={{ marginTop: 26, width: '100%', maxWidth: 320 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 3, height: 44 }}>
                {Array.from({ length: 32 }).map((_, i) => {
                  const h = 10 + Math.abs(Math.sin(i * 2.7)) * 30
                  const acesa = i / 32 <= tocado
                  return (
                    <div
                      key={i}
                      style={{
                        flex: 1,
                        height: h,
                        borderRadius: 2,
                        background: acesa ? C.brand : C.bgRaised,
                      }}
                    />
                  )
                })}
              </div>
              <div
                style={{
                  marginTop: 8,
                  fontSize: 11.5,
                  color: C.textDim,
                  fontFamily: 'ui-monospace, "Cascadia Mono", Consolas, monospace',
                  textAlign: 'center',
                }}
              >
                0:{String(tempoTocado).padStart(2, '0')} / 0:38
              </div>
            </div>

            {/* botões */}
            <div style={{ marginTop: 28, width: '100%', maxWidth: 300, display: 'flex', flexDirection: 'column', gap: 10 }}>
              <div
                style={{
                  borderRadius: 12,
                  padding: '13px 18px',
                  background: C.brand,
                  color: '#0A0F0E',
                  fontWeight: 700,
                  fontSize: 14.5,
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  gap: 8,
                  transform: frame >= enviarFrame && frame <= enviarFrame + 8 ? 'scale(.97)' : 'scale(1)',
                }}
              >
                <Ico n="paperPlane" t={14} /> Enviar pro Fábio
              </div>
              <div
                style={{
                  borderRadius: 12,
                  padding: '12px 18px',
                  border: `1px solid ${C.borderStrong}`,
                  color: C.textDim,
                  fontWeight: 600,
                  fontSize: 14,
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  gap: 8,
                }}
              >
                <Ico n="rotateLeft" t={13} /> Re-gravar
              </div>
            </div>
          </>
        )}
      </div>
    </div>
  )
}
