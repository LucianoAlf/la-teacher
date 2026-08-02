import React from 'react'
import { spring, staticFile, useCurrentFrame, useVideoConfig } from 'remotion'
import { Sfx, SFX } from '../lib/sfx'

/**
 * WhatsApp dark (moldura fiel: #0B141A fundo, #202C33 header/bolha recebida,
 * #005C4B enviada) com o FÁBIO na conversa — adaptado do WhatsAppChat do
 * estúdio do TOM. Cada bolha entra com spring e toca o msg-pop sozinha.
 */

const WA = {
  bg: '#0B141A',
  panel: '#202C33',
  out: '#005C4B',
  text: '#E9EDEF',
  muted: '#8696A0',
  tealName: '#00A884',
  hora: 'rgba(233,237,239,.55)',
}

export type MsgWA = { texto: React.ReactNode; atFrame: number; enviada?: boolean; hora?: string }

export const WhatsAppFabio: React.FC<{ mensagens: MsgWA[] }> = ({ mensagens }) => {
  const frame = useCurrentFrame()
  const { fps } = useVideoConfig()
  return (
    <div
      style={{
        position: 'absolute',
        inset: 0,
        background: WA.bg,
        display: 'flex',
        flexDirection: 'column',
        fontFamily:
          '-apple-system, "Segoe UI", "Helvetica Neue", Helvetica, Arial, sans-serif',
      }}
    >
      {mensagens.map((m, i) => (
        <Sfx key={`snd-${i}`} file={SFX.msgPop} at={m.atFrame} volume={0.45} rate={m.enviada ? 1.12 : 1} />
      ))}

      {/* header do WhatsApp */}
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: 12,
          padding: '12px 16px',
          background: WA.panel,
        }}
      >
        <span style={{ color: WA.muted, fontSize: 18, marginRight: 2 }}>←</span>
        <div
          style={{
            width: 38,
            height: 38,
            borderRadius: 999,
            background: '#111916',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            overflow: 'hidden',
          }}
        >
          <img src={staticFile('brand/fabio-avatar.svg')} alt="Fábio" style={{ width: 30, height: 'auto' }} />
        </div>
        <div style={{ flex: 1 }}>
          <div style={{ color: WA.text, fontSize: 15, fontWeight: 600 }}>Fábio · LA Music</div>
          <div style={{ color: WA.muted, fontSize: 11.5 }}>online</div>
        </div>
        <span style={{ color: WA.muted, fontSize: 15, letterSpacing: 2 }}>⋮</span>
      </div>

      {/* conversa */}
      <div style={{ flex: 1, padding: '14px 12px', display: 'flex', flexDirection: 'column', gap: 8 }}>
        <div style={{ alignSelf: 'center', marginBottom: 4 }}>
          <span
            style={{
              background: WA.panel,
              color: WA.muted,
              fontSize: 11,
              padding: '5px 12px',
              borderRadius: 8,
              fontWeight: 500,
              textTransform: 'uppercase',
              letterSpacing: '.4px',
            }}
          >
            Hoje
          </span>
        </div>
        {mensagens.map((m, i) => {
          if (frame < m.atFrame) return null
          const s = spring({ frame: frame - m.atFrame, fps, config: { damping: 14 } })
          return (
            <div
              key={i}
              style={{
                maxWidth: '84%',
                alignSelf: m.enviada ? 'flex-end' : 'flex-start',
                background: m.enviada ? WA.out : WA.panel,
                color: WA.text,
                borderRadius: 10,
                padding: '8px 10px 6px',
                fontSize: 13.5,
                lineHeight: 1.45,
                transform: `translateY(${(1 - s) * 18}px) scale(${0.92 + s * 0.08})`,
                opacity: s,
                boxShadow: '0 1px 1px rgba(0,0,0,.25)',
              }}
            >
              {m.texto}
              <div style={{ textAlign: 'right', fontSize: 10, color: WA.hora, marginTop: 3 }}>
                {m.hora ?? '7:58'}
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}
