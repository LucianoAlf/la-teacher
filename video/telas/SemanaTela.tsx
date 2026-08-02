import React from 'react'
import { spring, useCurrentFrame, useVideoConfig } from 'remotion'
import { C, FONT } from '../tokens'
import { Card, TituloCard } from '../ui/Cartoes'
import { ScreenHeader } from '../ui/AppShell'
import { Ico } from '../ui/Icones'

/**
 * "Minha semana" (Ponto.tsx): navegação de semana, card Semana com o total
 * no canto e as linhas por dia — as horas nascem da chamada, sozinhas.
 * As linhas entram com stagger enquanto a narração fala.
 */

const DIAS = [
  { dia: 'Seg, 03/08', detalhe: '4 aula(s) · 11:00–19:00', horas: '4h' },
  { dia: 'Ter, 04/08', detalhe: '3 aula(s) · 14:00–17:00', horas: '3h' },
  { dia: 'Qua, 05/08', detalhe: '2 aula(s) · 15:00–17:00', horas: '2h' },
  { dia: 'Qui, 06/08', detalhe: 'sem chamada registrada', horas: '' },
  { dia: 'Sex, 07/08', detalhe: '3 aula(s) · 14:00–17:00', horas: '3h' },
]

export const SemanaTela: React.FC = () => {
  const frame = useCurrentFrame()
  const { fps } = useVideoConfig()

  return (
    <div style={{ height: '100%', background: C.bgApp, fontFamily: FONT }}>
      <ScreenHeader titulo="Minha semana" subtitulo="Suas aulas dadas, dia a dia — só leitura" />

      <div style={{ padding: '0 16px', display: 'flex', flexDirection: 'column', gap: 12 }}>
        {/* navegação de semana */}
        <Card style={{ padding: '10px 14px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
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
                fontSize: 14,
              }}
            >
              ‹
            </div>
            <div style={{ flex: 1, textAlign: 'center', fontSize: 14, fontWeight: 700, color: C.text }}>
              Seg, 03/08 — Dom, 09/08
            </div>
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
                fontSize: 14,
              }}
            >
              ›
            </div>
          </div>
        </Card>

        {/* card Semana */}
        <Card>
          <TituloCard
            icone="calendarCheck"
            texto="Semana"
            direita={<span style={{ fontSize: 14, fontWeight: 800, color: C.brandLight }}>12h</span>}
          />
          {DIAS.map((d, i) => {
            const s = spring({ frame: frame - 10 - i * 6, fps, config: { damping: 200 } })
            return (
              <div
                key={d.dia}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: 10,
                  padding: '9px 2px',
                  borderBottom: i < DIAS.length - 1 ? `1px solid ${C.border}` : 'none',
                  opacity: s,
                  transform: `translateY(${(1 - s) * 8}px)`,
                }}
              >
                <span style={{ width: 74, fontSize: 12.5, fontWeight: 700, color: C.text, flexShrink: 0 }}>
                  {d.dia}
                </span>
                <span style={{ flex: 1, fontSize: 12.5, color: d.horas ? C.textDim : C.textMuted }}>
                  {d.detalhe}
                </span>
                <span style={{ fontSize: 14, fontWeight: 700, color: C.text }}>{d.horas}</span>
              </div>
            )
          })}
        </Card>

        {/* rodapé informativo */}
        <div style={{ display: 'flex', gap: 7, fontSize: 12, color: C.textDim, lineHeight: 1.5, padding: '0 2px' }}>
          <span style={{ color: C.brandLight, marginTop: 1 }}>
            <Ico n="circleInfo" t={12} />
          </span>
          <span>
            Os dias aqui nascem da chamada que você faz nas aulas — é{' '}
            <b style={{ color: C.text }}>só leitura</b>. Achou divergência? Fala com a coordenação.
          </span>
        </div>
      </div>
    </div>
  )
}
