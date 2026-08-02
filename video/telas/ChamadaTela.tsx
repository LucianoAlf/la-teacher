import React from 'react'
import { spring, useCurrentFrame, useVideoConfig } from 'remotion'
import { C, FONT } from '../tokens'
import { Ico } from '../ui/Icones'
import { AvatarInicial, Card } from '../ui/Cartoes'
import { ScreenHeader } from '../ui/AppShell'

/**
 * Chamada manual — o fluxo INTEIRO, sem pular etapa (réplica de Chamada.tsx):
 * todo mundo presente → dedo toca na Maria Isabel (pílula vira "Faltou" âmbar)
 * → Enviar chamada → card "Confirma a chamada?" → Enviar agora →
 * "Enviando a chamada…" → EmptyState "Chamada enviada ✓".
 * Turma real: Musicalização · 17h · Gustavo e Maria Isabel.
 */

export const ChamadaTela: React.FC<{
  faltouFrame: number
  enviarFrame: number
  agoraFrame: number
  enviadaFrame: number
}> = ({ faltouFrame, enviarFrame, agoraFrame, enviadaFrame }) => {
  const frame = useCurrentFrame()
  const { fps } = useVideoConfig()
  const faltou = frame >= faltouFrame + 4
  const confirmando = frame >= enviarFrame + 4 && frame < agoraFrame + 4
  const enviando = frame >= agoraFrame + 4 && frame < enviadaFrame
  const enviada = frame >= enviadaFrame
  const cardConfirma = spring({ frame: frame - enviarFrame - 4, fps, config: { damping: 15 } })
  const popEnviada = spring({ frame: frame - enviadaFrame, fps, config: { damping: 11, stiffness: 110 } })

  const Pilula: React.FC<{ nome: string; estaFaltando: boolean }> = ({ nome, estaFaltando }) => (
    <div
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: 10,
        padding: '10px 12px',
        borderRadius: 14,
        border: `1px solid ${C.border}`,
        background: C.bgSurface,
        marginBottom: 8,
      }}
    >
      <AvatarInicial nome={nome} />
      <span style={{ flex: 1, fontSize: 14, fontWeight: 600, color: C.text }}>{nome}</span>
      {estaFaltando ? (
        <span
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            gap: 5,
            fontSize: 11,
            fontWeight: 700,
            padding: '5px 11px',
            borderRadius: 999,
            border: '1px solid rgba(234,179,8,.5)',
            color: '#FACC15',
          }}
        >
          <Ico n="userXmark" t={11} /> Faltou
        </span>
      ) : (
        <span
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            gap: 5,
            fontSize: 11,
            fontWeight: 700,
            padding: '5px 11px',
            borderRadius: 999,
            border: `1px solid ${C.borderStrong}`,
            color: C.textDim,
          }}
        >
          <Ico n="check" t={10} /> Presente
        </span>
      )}
    </div>
  )

  if (enviada) {
    return (
      <div
        style={{
          height: '100%',
          background: C.bgApp,
          fontFamily: FONT,
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          padding: '0 34px',
          textAlign: 'center',
        }}
      >
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
            transform: `scale(${0.4 + popEnviada * 0.6})`,
            opacity: Math.min(1, popEnviada * 2),
          }}
        >
          <Ico n="clipboardCheck" t={20} />
        </div>
        <div style={{ marginTop: 18, fontSize: 17, fontWeight: 700, color: C.text, opacity: popEnviada }}>
          Chamada enviada ✓
        </div>
        <div style={{ marginTop: 8, fontSize: 13, color: C.textDim, lineHeight: 1.55, opacity: popEnviada }}>
          1 presente(s) e 1 falta(s) registradas. Correções, só com a coordenação.
        </div>
        <div
          style={{
            marginTop: 22,
            borderRadius: 12,
            padding: '11px 26px',
            border: `1px solid ${C.borderStrong}`,
            color: C.textDim,
            fontSize: 13.5,
            fontWeight: 600,
            opacity: popEnviada,
          }}
        >
          Voltar
        </div>
      </div>
    )
  }

  return (
    <div style={{ height: '100%', background: C.bgApp, fontFamily: FONT, position: 'relative', overflow: 'hidden' }}>
      <ScreenHeader titulo="Chamada" />

      <div style={{ padding: '0 16px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        {/* contexto */}
        <Card bordaTeal style={{ padding: 12 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 11 }}>
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
              }}
            >
              <Ico n="users" t={16} />
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 14.5, fontWeight: 700, color: C.text }}>
                Musicalização · turma de 2
              </div>
              <div style={{ fontSize: 12, color: C.textDim, marginTop: 1 }}>Musicalização · 17h</div>
            </div>
          </div>
          <div
            style={{
              marginTop: 9,
              display: 'flex',
              alignItems: 'center',
              gap: 6,
              fontSize: 12,
              fontWeight: 600,
              color: C.brandLight,
            }}
          >
            <Ico n="historyClock" t={11} /> Ver histórico da turma
          </div>
        </Card>

        {/* faixa âmbar */}
        <div
          style={{
            borderRadius: 12,
            padding: '9px 12px',
            background: 'rgba(234,179,8,.12)',
            border: '1px solid rgba(234,179,8,.3)',
            display: 'flex',
            alignItems: 'center',
            gap: 8,
            fontSize: 12.5,
            fontWeight: 700,
            color: '#FACC15',
            lineHeight: 1.4,
          }}
        >
          <Ico n="clock" t={13} />
          Chamada ainda não enviada — marque quem faltou e toque em Enviar chamada.
        </div>

        {/* alunos */}
        <div>
          <Pilula nome="Gustavo" estaFaltando={false} />
          <Pilula nome="Maria Isabel" estaFaltando={faltou} />
        </div>

        {/* dica */}
        <div style={{ display: 'flex', gap: 7, fontSize: 12, color: C.textDim, lineHeight: 1.5, padding: '0 2px' }}>
          <span style={{ color: C.brandLight, marginTop: 1 }}>
            <Ico n="handPointer" t={12} />
          </span>
          <span>
            Todo mundo começa como <b style={{ color: C.text }}>presente</b> — toca em quem faltou.
            Depois de enviar, não dá pra editar pelo app.
          </span>
        </div>

        {/* card de confirmação */}
        {confirmando ? (
          <Card bordaTeal style={{ opacity: cardConfirma, transform: `translateY(${(1 - cardConfirma) * 14}px)` }}>
            <div style={{ fontSize: 14.5, fontWeight: 700, color: C.text }}>Confirma a chamada?</div>
            <div style={{ marginTop: 6, fontSize: 12.5, color: C.textDim, lineHeight: 1.55 }}>
              1 presente(s), 1 falta(s) — falta de <b style={{ color: C.text }}>Maria Isabel</b>.
              Depois de enviar, <b style={{ color: C.text }}>não dá pra editar pelo app</b> —
              correção é com a coordenação.
            </div>
            <div style={{ marginTop: 12, display: 'flex', gap: 10 }}>
              <div
                style={{
                  borderRadius: 12,
                  padding: '11px 16px',
                  color: C.textDim,
                  fontSize: 13.5,
                  fontWeight: 600,
                }}
              >
                Voltar
              </div>
              <div
                style={{
                  flex: 1,
                  borderRadius: 12,
                  padding: '11px 16px',
                  background: C.brand,
                  color: '#0A0F0E',
                  fontSize: 13.5,
                  fontWeight: 700,
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  gap: 7,
                }}
              >
                <Ico n="check" t={13} /> Enviar agora
              </div>
            </div>
          </Card>
        ) : null}

        {enviando ? (
          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: 8,
              fontSize: 13,
              color: C.textDim,
              padding: '10px 0',
            }}
          >
            <span style={{ color: C.brandLight, transform: `translateY(${Math.sin(frame / 4) * 3}px)` }}>
              <Ico n="cloudUp" t={16} />
            </span>
            Enviando a chamada…
          </div>
        ) : null}
      </div>

      {/* rodapé: contagem + enviar */}
      {!confirmando && !enviando ? (
        <div
          style={{
            position: 'absolute',
            left: 0,
            right: 0,
            bottom: 0,
            padding: '20px 16px 18px',
            background: `linear-gradient(to top, ${C.bgApp} 60%, transparent)`,
            display: 'flex',
            alignItems: 'center',
            gap: 10,
          }}
        >
          <span style={{ flex: 1, fontSize: 13, fontWeight: 600, color: C.textDim }}>
            {faltou ? '1 presente(s) · 1 falta(s)' : '2 presente(s) · 0 falta(s)'}
          </span>
          <div
            style={{
              borderRadius: 12,
              padding: '12px 18px',
              background: C.brand,
              color: '#0A0F0E',
              fontSize: 13.5,
              fontWeight: 700,
              display: 'flex',
              alignItems: 'center',
              gap: 7,
            }}
          >
            <Ico n="paperPlane" t={13} /> Enviar chamada
          </div>
        </div>
      ) : null}
    </div>
  )
}
