import React from 'react'
import { spring, useCurrentFrame, useVideoConfig } from 'remotion'
import { C, FONT } from '../tokens'
import { Card, TituloCard, Badge } from '../ui/Cartoes'
import { ScreenHeader } from '../ui/AppShell'
import { Ico } from '../ui/Icones'

/**
 * Histórico da turma — a linha do tempo das aulas registradas da turma
 * Balão Mágico (Musicalização · 18h · Arthur). Entradas nascem com stagger;
 * a mais antiga é de professor anterior — nada se perde na troca.
 */

const ENTRADAS = [
  {
    data: '28 jul · Musicalização',
    ultima: true,
    quem: 'você' as const,
    texto: 'Pulsação com o Balão Mágico — marchinha e palmas no refrão. Arthur firmou o tempo forte.',
  },
  {
    data: '21 jul · Musicalização',
    ultima: false,
    quem: 'você' as const,
    texto: 'Jogo de pergunta e resposta rítmica com o tambor. Trabalhado forte/fraco.',
  },
  {
    data: '14 jul · Musicalização',
    ultima: false,
    quem: 'prof. anterior' as const,
    texto: 'Apresentação dos instrumentos da bandinha. Explorou timbres livremente.',
  },
]

export const TurmaTela: React.FC = () => {
  const frame = useCurrentFrame()
  const { fps } = useVideoConfig()

  return (
    <div style={{ height: '100%', background: C.bgApp, fontFamily: FONT }}>
      <ScreenHeader titulo="Balão Mágico" subtitulo="Musicalização · Segunda · 18h" />

      <div style={{ padding: '0 16px' }}>
        <Card>
          <TituloCard
            icone="historyClock"
            texto="Últimas aulas da turma"
            direita={<span style={{ fontSize: 11.5, color: C.textDim }}>15 aulas</span>}
          />
          {ENTRADAS.map((e, i) => {
            const s = spring({ frame: frame - 8 - i * 7, fps, config: { damping: 200 } })
            return (
              <div
                key={e.data}
                style={{
                  borderRadius: 12,
                  border: `1px solid ${C.border}`,
                  padding: 11,
                  marginBottom: 8,
                  opacity: s,
                  transform: `translateY(${(1 - s) * 10}px)`,
                }}
              >
                <div style={{ display: 'flex', alignItems: 'center', gap: 7, marginBottom: 6 }}>
                  <span style={{ fontSize: 12.5, fontWeight: 700, color: C.text }}>{e.data}</span>
                  {e.ultima ? (
                    <span
                      style={{
                        fontSize: 10,
                        fontWeight: 700,
                        textTransform: 'uppercase',
                        letterSpacing: '.4px',
                        color: C.brandLight,
                        background: C.brandSoft,
                        borderRadius: 999,
                        padding: '2px 8px',
                      }}
                    >
                      última aula
                    </span>
                  ) : null}
                  <span style={{ marginLeft: 'auto', color: C.brandLight }}>
                    <Ico n="wand" t={11} />
                  </span>
                  {e.quem === 'você' ? (
                    <Badge tom="teal">você</Badge>
                  ) : (
                    <span
                      style={{
                        fontSize: 10.5,
                        fontWeight: 700,
                        padding: '3px 8px',
                        borderRadius: 999,
                        border: `1px solid ${C.borderStrong}`,
                        color: C.textDim,
                      }}
                    >
                      prof. anterior
                    </span>
                  )}
                </div>
                <div style={{ fontSize: 12.5, color: C.textDim, lineHeight: 1.5 }}>{e.texto}</div>
              </div>
            )
          })}
        </Card>
      </div>
    </div>
  )
}
