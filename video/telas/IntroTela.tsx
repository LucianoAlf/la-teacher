import React from 'react'
import { staticFile, useCurrentFrame } from 'remotion'
import { C, FONT } from '../tokens'
import { Ico } from '../ui/Icones'

/**
 * Intro pré-login (3 passos, fundo dark FIXO com halftone rosa) — réplica de
 * src/pages/app/Intro.tsx + DemoMorph.tsx:
 *  1. "Oi. Eu sou o Fábio." (avatar 150 bob) / "Você fala. Eu escrevo."
 *  2. DemoMorph: pílula "Fábio ouvindo…" → fala palavra a palavra → gustavo/
 *     ritmo/agudo/maria acendem em teal → vira os 2 cards + "Fábio estruturou"
 *  3. Escudo 76px: "Eu nunca invento." / "Campo vazio é convite…"
 * Dirigida por props; a saída de palavras usa o frame local.
 */

const ACCENT = '#66CEC4' // teal-300 da capa dark
const INTRO = { bg: '#0A0F0E', muted: '#9E9E9E', pilInativa: '#243430', cardBg: '#1A2421', cardBorda: '#243430' }

const FALA = 'o gustavo foi bem no ritmo mas desafina no agudo, a maria é o contrário…'.split(' ')
const ACENDE = new Set(['gustavo', 'ritmo', 'agudo,', 'maria'])

const CARDS = [
  { nome: 'Gustavo', linhas: [['Progresso', 'Foi bem no ritmo'], ['Próximo passo', 'Afinar no agudo']] },
  { nome: 'Maria', linhas: [['Progresso', 'Afina bem no agudo'], ['Próximo passo', 'Trabalhar o ritmo']] },
]

const Pilulas: React.FC<{ ativa: number }> = ({ ativa }) => (
  <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
    {[0, 1, 2].map((i) => (
      <div
        key={i}
        style={{
          height: 6,
          width: i === ativa ? 22 : 6,
          borderRadius: 999,
          background: i === ativa ? ACCENT : INTRO.pilInativa,
        }}
      />
    ))}
  </div>
)

const Cta: React.FC<{ texto: string; primario?: boolean }> = ({ texto, primario = false }) => (
  <div
    style={{
      borderRadius: 12,
      padding: '13px 18px',
      textAlign: 'center',
      fontSize: 14.5,
      fontWeight: 700,
      background: primario ? C.brand : 'transparent',
      color: primario ? '#0A0F0E' : '#F5F5F5',
      border: primario ? 'none' : `1px solid ${INTRO.cardBorda}`,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      gap: 8,
    }}
  >
    {texto} <Ico n="arrowRight" t={13} />
  </div>
)

export const IntroTela: React.FC<{
  passo: 1 | 2 | 3
  /** fase da demo (passo 2): 1 = fala saindo · 2 = palavras acesas · 3 = cards */
  faseDemo?: 1 | 2 | 3
  /** frame local em que a fase 1 começou (pro word-by-word) */
  demoDesde?: number
}> = ({ passo, faseDemo = 1, demoDesde = 0 }) => {
  const frame = useCurrentFrame()
  const bob = Math.sin((frame / (2.2 * 30)) * Math.PI * 2) * -7

  return (
    <div
      style={{
        height: '100%',
        background: INTRO.bg,
        color: '#F5F5F5',
        fontFamily: FONT,
        display: 'flex',
        flexDirection: 'column',
        position: 'relative',
        overflow: 'hidden',
      }}
    >
      <div
        style={{
          position: 'absolute',
          inset: 0,
          backgroundImage: 'radial-gradient(rgb(233 20 81 / .20) 1px, transparent 1.2px)',
          backgroundSize: '14px 14px',
        }}
      />

      {/* topo: progresso + Pular */}
      <div
        style={{
          position: 'relative',
          zIndex: 5,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          padding: '18px 22px 0',
        }}
      >
        <Pilulas ativa={passo - 1} />
        {passo < 3 ? (
          <span style={{ fontSize: 13, fontWeight: 600, color: INTRO.muted }}>Pular</span>
        ) : (
          <span />
        )}
      </div>

      {/* miolo */}
      <div
        style={{
          position: 'relative',
          zIndex: 5,
          flex: 1,
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          padding: '0 26px',
          textAlign: 'center',
        }}
      >
        {passo === 1 ? (
          <>
            <img
              src={staticFile('brand/fabio-avatar.svg')}
              alt="Fábio"
              style={{ width: 150, height: 'auto', transform: `translateY(${bob}px)` }}
            />
            <div style={{ marginTop: 26, fontSize: 26, fontWeight: 800, letterSpacing: '-.3px' }}>
              Oi. Eu sou o Fábio.
            </div>
            <div style={{ marginTop: 10, fontSize: 15, color: INTRO.muted }}>
              Você fala. Eu escrevo.
            </div>
          </>
        ) : null}

        {passo === 2 ? (
          <>
            <div style={{ fontSize: 15, color: INTRO.muted, marginBottom: 28, maxWidth: 300 }}>
              Sem digitar. Você só fala como a aula foi —
            </div>

            {/* pílula de status */}
            <div
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                gap: 7,
                background: INTRO.cardBg,
                borderRadius: 999,
                padding: '6px 13px',
                fontSize: 11,
                fontWeight: 700,
                color: ACCENT,
                marginBottom: 20,
              }}
            >
              <span
                style={{
                  width: 7,
                  height: 7,
                  borderRadius: 999,
                  background: ACCENT,
                  opacity: faseDemo < 3 ? 0.45 + Math.abs(Math.sin(frame / 8)) * 0.55 : 1,
                }}
              />
              {faseDemo < 3 ? 'Fábio ouvindo…' : 'Fábio estruturou'}
            </div>

            {/* fala crua, palavra por palavra */}
            <div
              style={{
                fontSize: 15.5,
                lineHeight: 1.6,
                maxWidth: 300,
                opacity: faseDemo === 3 ? 0.4 : 1,
                transform: faseDemo === 3 ? 'scale(.92)' : 'scale(1)',
              }}
            >
              <span style={{ color: INTRO.muted }}>“</span>
              {FALA.map((p, i) => {
                const visivel = faseDemo >= 2 || frame - demoDesde >= i * 2.5
                const acesa = faseDemo >= 2 && ACENDE.has(p)
                return (
                  <span
                    key={i}
                    style={{
                      opacity: visivel ? 1 : 0,
                      color: acesa ? ACCENT : '#F5F5F5',
                      fontWeight: acesa ? 700 : 400,
                    }}
                  >
                    {p}{' '}
                  </span>
                )
              })}
              <span style={{ color: INTRO.muted }}>”</span>
            </div>

            {/* cards estruturados */}
            {faseDemo === 3 ? (
              <div style={{ marginTop: 18, width: '100%', maxWidth: 330, display: 'flex', flexDirection: 'column', gap: 10 }}>
                {CARDS.map((card, i) => {
                  const t = Math.min(1, Math.max(0, (frame - demoDesde - i * 5) / 15))
                  return (
                    <div
                      key={card.nome}
                      style={{
                        background: INTRO.cardBg,
                        border: `1px solid ${INTRO.cardBorda}`,
                        borderRadius: 14,
                        padding: 12,
                        display: 'flex',
                        gap: 11,
                        alignItems: 'center',
                        textAlign: 'left',
                        opacity: t,
                        transform: `translateY(${(1 - t) * 14}px)`,
                      }}
                    >
                      <div
                        style={{
                          width: 36,
                          height: 36,
                          borderRadius: 999,
                          background: C.brandSoft,
                          border: `1px solid ${C.brandBorder}`,
                          display: 'flex',
                          alignItems: 'center',
                          justifyContent: 'center',
                          color: ACCENT,
                          fontWeight: 700,
                          fontSize: 14,
                          flexShrink: 0,
                        }}
                      >
                        {card.nome.charAt(0)}
                      </div>
                      <div style={{ minWidth: 0 }}>
                        <div style={{ fontSize: 13.5, fontWeight: 700 }}>{card.nome}</div>
                        {card.linhas.map(([rotulo, valor]) => (
                          <div key={rotulo} style={{ fontSize: 12, marginTop: 2 }}>
                            <span style={{ color: ACCENT, fontWeight: 600 }}>{rotulo}</span>
                            <span style={{ color: INTRO.muted }}> · {valor}</span>
                          </div>
                        ))}
                      </div>
                    </div>
                  )
                })}
              </div>
            ) : null}
          </>
        ) : null}

        {passo === 3 ? (
          <>
            <div
              style={{
                width: 76,
                height: 76,
                borderRadius: 999,
                background: C.brandSoft,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                color: ACCENT,
              }}
            >
              <Ico n="shieldHeart" t={30} />
            </div>
            <div style={{ marginTop: 24, fontSize: 26, fontWeight: 800, letterSpacing: '-.3px' }}>
              Eu nunca invento.
            </div>
            <div style={{ marginTop: 12, fontSize: 15, color: INTRO.muted, maxWidth: 300, lineHeight: 1.55 }}>
              Campo vazio é convite. Nada vai pro diário do seu aluno sem você confirmar.
            </div>
          </>
        ) : null}
      </div>

      {/* CTA */}
      <div style={{ position: 'relative', zIndex: 5, padding: '0 26px 34px' }}>
        {passo < 3 ? <Cta texto="Continuar" /> : <Cta texto="Entrar" primario />}
      </div>
    </div>
  )
}
