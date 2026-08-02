import React from 'react'
import { spring, staticFile, useCurrentFrame, useVideoConfig } from 'remotion'
import { C, FONT } from '../tokens'
import { Ico } from '../ui/Icones'
import { FabioIcon } from '../../src/components/ui/FabioIcon'

/**
 * Chat do Fábio (ChatFabio.tsx): header com o Fábio colorido 40px e
 * "seu assistente · também no WhatsApp", bolhas raio 16 sem rabinho
 * (professor à direita teal-soft), "Fábio está digitando" com o robozinho
 * 18px + 3 pontinhos defasados, e a resposta chegando sozinha.
 * Frames: `digitaFrame` (pergunta sendo digitada no input), `enviaFrame`
 * (bolha do professor sobe), `digitandoFrame`→`respostaFrame` (Fábio).
 */

export const PERGUNTA = 'Como foi a aula do Arthur?'
const RESPOSTA =
  'O Arthur mandou bem! Na última aula ele firmou o tempo forte na marchinha do Balão Mágico, e ficou de treinar as palmas no refrão. 🥁'

export const ChatTela: React.FC<{
  digitaFrame: number
  enviaFrame: number
  digitandoFrame: number
  respostaFrame: number
}> = ({ digitaFrame, enviaFrame, digitandoFrame, respostaFrame }) => {
  const frame = useCurrentFrame()
  const { fps } = useVideoConfig()
  const digitado = frame < digitaFrame ? 0 : Math.min(PERGUNTA.length, Math.floor(((frame - digitaFrame) * 12) / 30))
  const enviada = frame >= enviaFrame + 6
  const digitando = frame >= digitandoFrame && frame < respostaFrame
  const bolhaProf = spring({ frame: frame - enviaFrame - 6, fps, config: { damping: 14 } })
  const bolhaFabio = spring({ frame: frame - respostaFrame, fps, config: { damping: 14 } })

  return (
    <div style={{ height: '100%', background: C.bgApp, fontFamily: FONT, display: 'flex', flexDirection: 'column' }}>
      {/* header */}
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: 12,
          padding: '14px 16px',
          borderBottom: `1px solid ${C.border}`,
        }}
      >
        <div
          style={{
            width: 36,
            height: 36,
            borderRadius: 999,
            border: `1px solid ${C.borderStrong}`,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            color: C.textDim,
          }}
        >
          <Ico n="arrowLeft" t={14} />
        </div>
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 17, fontWeight: 700, color: C.text }}>Fábio</div>
          <div style={{ fontSize: 12, color: C.textDim, marginTop: 1 }}>
            seu assistente · também no WhatsApp
          </div>
        </div>
        <img src={staticFile('brand/fabio-avatar.svg')} alt="Fábio" style={{ width: 40, height: 'auto' }} />
      </div>

      {/* conversa */}
      <div style={{ flex: 1, padding: '14px 16px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        <div style={{ alignSelf: 'center' }}>
          <span
            style={{
              background: C.bgSurface,
              border: `1px solid ${C.border}`,
              color: C.textMuted,
              fontSize: 11,
              fontWeight: 600,
              padding: '4px 12px',
              borderRadius: 999,
            }}
          >
            Hoje
          </span>
        </div>

        {enviada ? (
          <div
            style={{
              alignSelf: 'flex-end',
              maxWidth: '80%',
              background: C.brandSoft,
              border: `1px solid ${C.brandBorder}`,
              borderRadius: 16,
              padding: '9px 12px',
              fontSize: 13.5,
              color: C.text,
              lineHeight: 1.45,
              opacity: bolhaProf,
              transform: `translateY(${(1 - bolhaProf) * 14}px)`,
            }}
          >
            {PERGUNTA}
            <div style={{ fontSize: 10.5, color: C.textMuted, textAlign: 'right', marginTop: 3 }}>7:58</div>
          </div>
        ) : null}

        {digitando ? (
          <div
            style={{
              alignSelf: 'flex-start',
              display: 'flex',
              alignItems: 'center',
              gap: 8,
              background: C.bgSurface,
              border: `1px solid ${C.border}`,
              borderRadius: 16,
              padding: '9px 13px',
            }}
          >
            <FabioIcon
              style={{ width: 18, height: 18, '--fabio-fill': C.brandLight, '--fabio-traco': C.bgSurface } as React.CSSProperties}
            />
            <span style={{ fontSize: 12.5, color: C.textDim }}>Fábio está digitando</span>
            <span style={{ display: 'flex', gap: 3 }}>
              {[0, 1, 2].map((i) => (
                <span
                  key={i}
                  style={{
                    width: 5,
                    height: 5,
                    borderRadius: 999,
                    background: C.textDim,
                    opacity: 0.35 + Math.abs(Math.sin((frame - i * 7.5) / 9)) * 0.65,
                  }}
                />
              ))}
            </span>
          </div>
        ) : null}

        {frame >= respostaFrame ? (
          <div
            style={{
              alignSelf: 'flex-start',
              maxWidth: '80%',
              background: C.bgSurface,
              border: `1px solid ${C.border}`,
              borderRadius: 16,
              padding: '9px 12px',
              fontSize: 13.5,
              color: C.text,
              lineHeight: 1.5,
              opacity: bolhaFabio,
              transform: `translateY(${(1 - bolhaFabio) * 14}px)`,
            }}
          >
            {RESPOSTA}
            <div style={{ fontSize: 10.5, color: C.textMuted, textAlign: 'right', marginTop: 3 }}>7:58</div>
          </div>
        ) : null}
      </div>

      {/* input */}
      <div style={{ display: 'flex', gap: 9, padding: '10px 14px 16px', alignItems: 'center' }}>
        <div
          style={{
            flex: 1,
            height: 40,
            borderRadius: 999,
            background: C.bgHover,
            border: `1px solid ${C.borderStrong}`,
            display: 'flex',
            alignItems: 'center',
            padding: '0 15px',
            fontSize: 13.5,
            color: !enviada && digitado > 0 ? C.text : C.textMuted,
          }}
        >
          {!enviada && digitado > 0 ? PERGUNTA.slice(0, digitado) : 'Mensagem pro Fábio…'}
        </div>
        <div
          style={{
            width: 40,
            height: 40,
            borderRadius: 999,
            background: C.brand,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            color: '#0A0F0E',
            flexShrink: 0,
          }}
        >
          <Ico n="paperPlane" t={15} />
        </div>
      </div>
    </div>
  )
}
