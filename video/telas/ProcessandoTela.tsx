import React from 'react'
import { staticFile, useCurrentFrame } from 'remotion'
import { C, FONT } from '../tokens'
import { Ico } from '../ui/Icones'

/**
 * "O Fábio está montando seu relatório… 🎼" — réplica do Processando:
 * Fábio COLORIDO 112px com bob, e a trilha de 3 passos cujo marcador (26px,
 * borda 2) vira ✓ verde ao concluir. `p2Frame`/`p3Frame` avançam os passos;
 * o passo em curso mostra o spinner teal girando.
 */

const PASSOS = ['Na fila do Fábio', 'Transcrevendo seu áudio', 'Organizando por aluno — tronco + fatias']

export const ProcessandoTela: React.FC<{ p2Frame: number; p3Frame: number; fimFrame: number }> = ({
  p2Frame,
  p3Frame,
  fimFrame,
}) => {
  const frame = useCurrentFrame()
  const bob = Math.sin((frame / (2.2 * 30)) * Math.PI * 2) * -7
  // qual passo está em curso (0..2); depois de fimFrame, todos concluídos
  const emCurso = frame >= fimFrame ? 3 : frame >= p3Frame ? 2 : frame >= p2Frame ? 1 : 0

  return (
    <div style={{ height: '100%', background: C.bgApp, fontFamily: FONT, display: 'flex', flexDirection: 'column' }}>
      <div style={{ padding: '14px 18px', borderBottom: `1px solid ${C.border}` }}>
        <div style={{ fontSize: 17, fontWeight: 700, color: C.text }}>Áudio enviado ✓</div>
        <div style={{ fontSize: 12, color: C.textDim, marginTop: 1 }}>Canto — Valentina · 11h</div>
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
        <img
          src={staticFile('brand/fabio-avatar.svg')}
          alt="Fábio"
          style={{ width: 112, height: 'auto', transform: `translateY(${bob}px)` }}
        />
        <div style={{ marginTop: 22, fontSize: 18, fontWeight: 700, color: C.text, textAlign: 'center' }}>
          O Fábio está montando seu relatório… 🎼
        </div>
        <div style={{ marginTop: 8, fontSize: 13, color: C.textDim, textAlign: 'center' }}>
          Pode sair — sua gravação está guardada e nada se perde.
        </div>

        <div style={{ marginTop: 30, width: '100%', maxWidth: 300, display: 'flex', flexDirection: 'column', gap: 13 }}>
          {PASSOS.map((p, i) => {
            const feito = i < emCurso
            const fazendo = i === emCurso
            return (
              <div key={p} style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                <div
                  style={{
                    width: 26,
                    height: 26,
                    borderRadius: 999,
                    border: `2px solid ${feito ? C.success : fazendo ? C.brand : C.borderStrong}`,
                    background: feito ? 'rgba(34,197,94,.12)' : 'transparent',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    color: feito ? '#4ADE80' : C.brandLight,
                    flexShrink: 0,
                  }}
                >
                  {feito ? (
                    <Ico n="check" t={12} />
                  ) : fazendo ? (
                    <span
                      style={{
                        width: 11,
                        height: 11,
                        border: `2px solid ${C.brandSoft}`,
                        borderTopColor: C.brand,
                        borderRadius: 999,
                        display: 'inline-block',
                        transform: `rotate(${frame * 14}deg)`,
                      }}
                    />
                  ) : null}
                </div>
                <span
                  style={{
                    fontSize: 13.5,
                    fontWeight: fazendo || feito ? 600 : 500,
                    color: feito ? C.text : fazendo ? C.text : C.textMuted,
                  }}
                >
                  {p}
                </span>
              </div>
            )
          })}
        </div>

        <div
          style={{
            marginTop: 34,
            borderRadius: 12,
            padding: '11px 22px',
            border: `1px solid ${C.borderStrong}`,
            color: C.textDim,
            fontSize: 13.5,
            fontWeight: 600,
            display: 'flex',
            alignItems: 'center',
            gap: 8,
          }}
        >
          <Ico n="house" t={13} /> Voltar ao início
        </div>
      </div>
    </div>
  )
}
