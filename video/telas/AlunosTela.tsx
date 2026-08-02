import React from 'react'
import { C, FONT } from '../tokens'
import { AppHeader, TabBarComFabs } from '../ui/AppShell'
import { AvatarInicial, Card } from '../ui/Cartoes'
import { Ico } from '../ui/Icones'

/**
 * A carteira (Alunos.tsx): busca, cards por curso (título CAIXA ALTA +
 * capelo teal + contador) e as linhas de aluno com "{dia} · {hora} · Aula N/M".
 * Os 5 alunos reais do Matheus. `destacado` acende quem o dedo vai tocar.
 */

const CURSOS: { curso: string; alunos: { nome: string; sub: string }[] }[] = [
  {
    curso: 'CANTO',
    alunos: [
      { nome: 'Valentina', sub: 'Segunda · 11h · Aula 21/40' },
      { nome: 'Amanda', sub: 'Segunda · 15h · Aula 12/40' },
    ],
  },
  {
    curso: 'MUSICALIZAÇÃO',
    alunos: [
      { nome: 'Gustavo', sub: 'Segunda · 17h · Aula 8/40' },
      { nome: 'Maria Isabel', sub: 'Segunda · 17h · Aula 8/40' },
      { nome: 'Arthur', sub: 'Segunda · 18h · Aula 15/40' },
    ],
  },
]

export const AlunosTela: React.FC<{ destacado?: string }> = ({ destacado }) => (
  <div style={{ height: '100%', background: C.bgApp, fontFamily: FONT, position: 'relative', overflow: 'hidden' }}>
    <AppHeader />

    <div style={{ padding: '2px 16px 120px', display: 'flex', flexDirection: 'column', gap: 12 }}>
      {/* busca */}
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: 9,
          borderRadius: 12,
          padding: '11px 13px',
          background: C.bgHover,
          border: `1px solid ${C.borderStrong}`,
          color: C.textMuted,
          fontSize: 14,
        }}
      >
        <Ico n="search" t={14} />
        Buscar aluno pelo nome…
      </div>

      {CURSOS.map((c) => (
        <Card key={c.curso} style={{ padding: '12px 12px 6px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
            <span style={{ color: C.brandLight }}>
              <Ico n="graduation" t={14} />
            </span>
            <span
              style={{
                flex: 1,
                fontSize: 13,
                fontWeight: 700,
                letterSpacing: '.5px',
                color: C.text,
              }}
            >
              {c.curso}
            </span>
            <span style={{ fontSize: 11.5, color: C.textDim }}>{c.alunos.length}</span>
          </div>
          {c.alunos.map((a) => (
            <div
              key={a.nome}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 10,
                padding: '9px 6px',
                borderRadius: 12,
                background: destacado === a.nome ? C.brandSoft : 'transparent',
                border: destacado === a.nome ? `1px solid ${C.brandBorder}` : '1px solid transparent',
              }}
            >
              <AvatarInicial nome={a.nome} />
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 14, fontWeight: 700, color: C.text }}>{a.nome}</div>
                <div style={{ fontSize: 12, color: C.textDim, marginTop: 1 }}>{a.sub}</div>
              </div>
              <span style={{ color: C.textMuted }}>
                <Ico n="chevronRight" t={12} />
              </span>
            </div>
          ))}
        </Card>
      ))}
    </div>

    <TabBarComFabs ativa="alunos" />
  </div>
)
