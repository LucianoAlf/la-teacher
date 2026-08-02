import React from 'react'
import { C, FONT } from '../tokens'
import { AppHeader, TabBarComFabs } from '../ui/AppShell'
import { AULAS_0308, AulaRow, Card, TituloCard } from '../ui/Cartoes'

/**
 * Agenda de 03/08 — SemanaStrip (7 botões, selecionado teal, ponto de 5px em
 * dia com aula), DateNav e o card do dia com as 4 aulas reais do Matheus.
 * `aulaDestacada` acende a linha que o dedo vai tocar.
 */

const DIAS = [
  { d: 'seg', n: 3, aula: true, hoje: true },
  { d: 'ter', n: 4, aula: true },
  { d: 'qua', n: 5, aula: true },
  { d: 'qui', n: 6, aula: true },
  { d: 'sex', n: 7, aula: true },
  { d: 'sáb', n: 8, aula: true },
  { d: 'dom', n: 9, aula: false },
]

export const AgendaTela: React.FC<{ aulaDestacada?: number }> = ({ aulaDestacada = -1 }) => (
  <div style={{ height: '100%', background: C.bgApp, position: 'relative', overflow: 'hidden', fontFamily: FONT }}>
    <AppHeader />

    <div style={{ padding: '4px 16px', display: 'flex', flexDirection: 'column', gap: 12 }}>
      {/* SemanaStrip */}
      <div style={{ display: 'flex', gap: 4 }}>
        {DIAS.map((dia) => (
          <div
            key={dia.d}
            style={{
              flex: 1,
              borderRadius: 12,
              padding: '8px 0 7px',
              textAlign: 'center',
              background: dia.hoje ? C.brandSoft : 'transparent',
              border: `1px solid ${dia.hoje ? C.brandBorder : C.border}`,
            }}
          >
            <div
              style={{
                fontSize: 10,
                textTransform: 'uppercase',
                letterSpacing: '.4px',
                color: dia.hoje ? C.brandLight : C.textMuted,
                fontWeight: 600,
              }}
            >
              {dia.d}
            </div>
            <div
              style={{
                fontSize: 14.5,
                fontWeight: 700,
                color: dia.hoje ? C.brandLight : C.text,
                marginTop: 2,
              }}
            >
              {dia.n}
            </div>
            <div
              style={{
                width: 5,
                height: 5,
                borderRadius: 999,
                background: dia.aula ? C.brand : 'transparent',
                margin: '4px auto 0',
              }}
            />
          </div>
        ))}
      </div>

      {/* DateNav */}
      <Card style={{ padding: '10px 14px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <span style={{ color: C.textDim, fontSize: 14 }}>‹</span>
          <div style={{ flex: 1, textAlign: 'center' }}>
            <div style={{ fontSize: 13, fontWeight: 700, color: C.text }}>
              Segunda, 3 de agosto de 2026
            </div>
            <div
              style={{
                fontSize: 11,
                textTransform: 'uppercase',
                letterSpacing: '.5px',
                color: C.textMuted,
                marginTop: 1,
              }}
            >
              hoje
            </div>
          </div>
          <span style={{ color: C.textDim, fontSize: 14 }}>›</span>
        </div>
      </Card>

      {/* aulas do dia */}
      <Card>
        <TituloCard
          icone="calendarDay"
          texto="Hoje"
          direita={<span style={{ fontSize: 11.5, color: C.textDim }}>0 de 4 chamadas</span>}
        />
        <div style={{ display: 'flex', flexDirection: 'column' }}>
          {AULAS_0308.map((a, i) => (
            <AulaRow key={a.hora} aula={a} destacada={i === aulaDestacada} />
          ))}
        </div>
      </Card>
    </div>

    <TabBarComFabs ativa="agenda" />
  </div>
)
