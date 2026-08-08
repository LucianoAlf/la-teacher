import React from 'react'
import { C } from '../tokens'
import { Ico } from './Icones'

/** Peças recorrentes das telas: card com borda, badge, linha de aula, avatar-inicial. */

export const Card: React.FC<{
  children: React.ReactNode
  bordaTeal?: boolean
  style?: React.CSSProperties
}> = ({ children, bordaTeal = false, style }) => (
  <div
    style={{
      background: C.bgSurface,
      border: `1px solid ${bordaTeal ? C.brandBorder : C.border}`,
      borderRadius: 16,
      padding: 14,
      ...style,
    }}
  >
    {children}
  </div>
)

export const TituloCard: React.FC<{
  icone: string
  texto: string
  direita?: React.ReactNode
}> = ({ icone, texto, direita }) => (
  <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 10 }}>
    <span style={{ color: C.brandLight }}>
      <Ico n={icone} t={13} />
    </span>
    <span style={{ fontSize: 13, fontWeight: 700, color: C.text, flex: 1 }}>{texto}</span>
    {direita}
  </div>
)

export type BadgeTom = 'ok' | 'warn' | 'danger' | 'info' | 'teal'
const BADGE_CORES: Record<BadgeTom, { bg: string; cor: string; borda: string }> = {
  ok: { bg: 'rgba(34,197,94,.12)', cor: '#4ADE80', borda: 'transparent' },
  warn: { bg: 'transparent', cor: '#FACC15', borda: 'rgba(234,179,8,.45)' },
  danger: { bg: 'rgba(239,68,68,.12)', cor: '#F87171', borda: 'transparent' },
  info: { bg: 'rgba(59,130,246,.12)', cor: '#60A5FA', borda: 'transparent' },
  teal: { bg: C.brandSoft, cor: C.brandLight, borda: 'transparent' },
}

export const Badge: React.FC<{ tom: BadgeTom; children: React.ReactNode }> = ({ tom, children }) => {
  const c = BADGE_CORES[tom]
  return (
    <span
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        gap: 4,
        fontSize: 10.5,
        fontWeight: 700,
        padding: '3px 8px',
        borderRadius: 999,
        background: c.bg,
        color: c.cor,
        border: `1px solid ${c.borda}`,
        whiteSpace: 'nowrap',
      }}
    >
      {children}
    </span>
  )
}

export const AvatarInicial: React.FC<{ nome: string; t?: number }> = ({ nome, t = 36 }) => (
  <div
    style={{
      width: t,
      height: t,
      borderRadius: 999,
      background: C.brandSoft,
      border: `1px solid ${C.brandBorder}`,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      color: C.brandLight,
      fontSize: t * 0.4,
      fontWeight: 700,
      flexShrink: 0,
    }}
  >
    {nome.charAt(0)}
  </div>
)

export type Aula = {
  hora: string
  titulo: string
  detalhe: string
  badges?: { tom: BadgeTom; texto: string }[]
  mic?: boolean
}

/** Linha de sessão (AulaRow): hora mono 44px fixos · título/detalhe · badges · mic 32. */
export const AulaRow: React.FC<{ aula: Aula; destacada?: boolean }> = ({ aula, destacada }) => (
  <div
    style={{
      display: 'flex',
      alignItems: 'center',
      gap: 10,
      padding: '10px 4px',
      borderRadius: 12,
      background: destacada ? C.brandSoft : 'transparent',
      border: destacada ? `1px solid ${C.brandBorder}` : '1px solid transparent',
    }}
  >
    <span
      style={{
        width: 44,
        fontSize: 12.5,
        color: C.textDim,
        fontFamily: 'ui-monospace, "Cascadia Mono", Consolas, monospace',
        flexShrink: 0,
      }}
    >
      {aula.hora}
    </span>
    <div style={{ flex: 1, minWidth: 0 }}>
      <div style={{ fontSize: 14, fontWeight: 700, color: C.text }}>{aula.titulo}</div>
      <div style={{ fontSize: 12, color: C.textDim, marginTop: 1 }}>{aula.detalhe}</div>
    </div>
    <div style={{ display: 'flex', flexDirection: 'column', gap: 4, alignItems: 'flex-end' }}>
      {(aula.badges ?? []).map((b) => (
        <Badge key={b.texto} tom={b.tom}>
          {b.texto}
        </Badge>
      ))}
    </div>
    {aula.mic ? (
      <div
        style={{
          width: 32,
          height: 32,
          borderRadius: 999,
          background: C.brandSoft,
          border: `1px solid ${C.brandBorder}`,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          color: C.brandLight,
          flexShrink: 0,
        }}
      >
        <Ico n="mic" t={14} />
      </div>
    ) : null}
  </div>
)

/** As 4 aulas REAIS do Matheus em 03/08 (banco, prof 25). */
export const AULAS_0308: Aula[] = [
  {
    hora: '11:00',
    titulo: 'Valentina',
    detalhe: 'Canto · Individual',
    badges: [{ tom: 'warn', texto: 'Sem chamada' }],
    mic: true,
  },
  {
    hora: '15:00',
    titulo: 'Amanda',
    detalhe: 'Canto · Individual',
    badges: [{ tom: 'warn', texto: 'Sem chamada' }],
    mic: true,
  },
  // A experimental entra na ORDEM DO DIA, entre a Amanda e a musicalização —
  // agenda fora de ordem cronológica é a primeira coisa que um professor
  // estranha. Ela se anuncia por duas diferenças ao mesmo tempo: o badge de
  // estrela e o título ser o nome de uma PESSOA, não de uma turma (é o que o
  // app faz — SessaoRow, migration 047).
  //
  // E não tem microfone na linha, de propósito: a experimental não se grava
  // por aqui. Ela tem tela própria, porque o que o professor dita nela vai
  // pra dois destinos diferentes (escola × família).
  {
    hora: '16:00',
    titulo: 'Helena Duarte',
    detalhe: 'Teclado · primeira vez aqui',
    badges: [{ tom: 'info', texto: '★ Experimental' }],
  },
  {
    hora: '17:00',
    titulo: 'Musicalização · turma de 2',
    detalhe: 'Gustavo e Maria Isabel',
    badges: [{ tom: 'warn', texto: 'Sem chamada' }],
    mic: true,
  },
  {
    hora: '18:00',
    titulo: 'Arthur',
    detalhe: 'Musicalização · Balão Mágico',
    badges: [{ tom: 'warn', texto: 'Sem chamada' }],
    mic: true,
  },
]
