import React from 'react'
import { C, FONT } from '../tokens'
import { AppHeader, TabBarComFabs } from '../ui/AppShell'
import { AULAS_0308, AulaRow, Card, TituloCard } from '../ui/Cartoes'
import { Ico } from '../ui/Icones'
import { FabioIcon } from '../../src/components/ui/FabioIcon'

/**
 * Home do professor em 03/08 (dados reais do Matheus): FabioCard ("em breve",
 * fiel ao app de hoje), DateNav, card Hoje com as 4 aulas, Chamadas pendentes
 * em dia e o card Minha semana. `scrollY` desloca o miolo (o dedo "rola").
 */
export const Home: React.FC<{ scrollY?: number }> = ({ scrollY = 0 }) => (
  <div style={{ height: '100%', background: C.bgApp, position: 'relative', overflow: 'hidden', fontFamily: FONT }}>
    <div style={{ transform: `translateY(${-scrollY}px)` }}>
      <AppHeader />

      <div style={{ padding: '4px 16px 120px', display: 'flex', flexDirection: 'column', gap: 12 }}>
        {/* FabioCard — briefing (fiel ao app: tag EM BREVE) */}
        <div
          style={{
            borderRadius: 16,
            border: `1px solid ${C.brandBorder}`,
            background: `linear-gradient(150deg, ${C.brandSoft}, transparent 70%)`,
            padding: 14,
            display: 'flex',
            gap: 11,
            alignItems: 'flex-start',
          }}
        >
          <div
            style={{
              width: 30,
              height: 30,
              borderRadius: 999,
              background: C.brand,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              flexShrink: 0,
            }}
          >
            <FabioIcon
              style={{ width: 19, height: 19, '--fabio-fill': '#F5F5F5', '--fabio-traco': '#1B6E64' } as React.CSSProperties}
            />
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <span style={{ fontSize: 13.5, fontWeight: 700, color: C.text, flex: 1 }}>
                Briefing do Fábio
              </span>
              <span
                style={{
                  fontSize: 10.5,
                  fontWeight: 700,
                  textTransform: 'uppercase',
                  letterSpacing: '.5px',
                  color: C.brandLight,
                }}
              >
                em breve
              </span>
            </div>
            <div style={{ fontSize: 13, color: C.text, marginTop: 4 }}>
              Seu copiloto chega no próximo sprint 🎙️
            </div>
            <div style={{ fontSize: 12, color: C.textDim, marginTop: 2, lineHeight: 1.45 }}>
              Aqui vão entrar o briefing pré-aula e os toques sobre cada aluno.
            </div>
          </div>
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

        {/* card do dia */}
        <Card>
          <TituloCard
            icone="calendarDay"
            texto="Hoje"
            direita={<span style={{ fontSize: 11.5, color: C.textDim }}>0 de 4 chamadas</span>}
          />
          <div style={{ display: 'flex', flexDirection: 'column' }}>
            {AULAS_0308.map((a) => (
              <AulaRow key={a.hora} aula={a} />
            ))}
          </div>
        </Card>

        {/* pendências */}
        <Card>
          <TituloCard icone="bell" texto="Pendências" />
          <div style={{ textAlign: 'center', padding: '6px 0 4px' }}>
            <div style={{ fontSize: 14, fontWeight: 700, color: C.text }}>Tudo em dia! 🎉</div>
            <div style={{ fontSize: 12, color: C.textDim, marginTop: 3, lineHeight: 1.5 }}>
              Nenhuma chamada pendente de ontem. As de hoje aparecem no card acima.
            </div>
          </div>
        </Card>

        {/* Minha semana */}
        <Card>
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
              <Ico n="calendarCheck" t={16} />
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 14, fontWeight: 700, color: C.text }}>Minha semana</div>
              <div style={{ fontSize: 12, color: C.textDim, marginTop: 1 }}>
                nenhuma aula registrada hoje ainda
              </div>
            </div>
            <span style={{ color: C.textMuted }}>
              <Ico n="chevronRight" t={13} />
            </span>
          </div>
        </Card>
      </div>
    </div>

    <TabBarComFabs ativa="inicio" />
  </div>
)
