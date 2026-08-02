import React from 'react'
import { staticFile } from 'remotion'
import { FabioIcon } from '../../src/components/ui/FabioIcon'
import { C, FONT } from '../tokens'
import { Ico, ListPlusIco } from './Icones'

/**
 * O chrome do app dentro do telefone: AppHeader (Fábio 44 + saudação),
 * ScreenHeader (voltar + título), TabBar de 4 abas + FAB central do Fábio
 * (robozinho REAL importado do app) + FAB do microfone. Medidas auditadas.
 */

export const AppHeader: React.FC<{ nome?: string; data?: string }> = ({
  nome = 'Matheus',
  data = 'Segunda, 3 de agosto',
}) => (
  <div style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '14px 16px 10px' }}>
    <img src={staticFile('brand/fabio-avatar.svg')} alt="Fábio" style={{ width: 44, height: 'auto' }} />
    <div style={{ flex: 1, minWidth: 0 }}>
      <div style={{ fontSize: 17, fontWeight: 800, letterSpacing: '-.3px', color: C.text }}>
        E aí, {nome}! 👋
      </div>
      <div style={{ fontSize: 12.5, color: C.textDim, marginTop: 1 }}>{data}</div>
    </div>
    <div
      style={{
        width: 32,
        height: 32,
        borderRadius: 999,
        border: `1px solid ${C.borderStrong}`,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        color: C.textDim,
      }}
    >
      <Ico n="sun" t={14} />
    </div>
    <div
      style={{
        width: 40,
        height: 40,
        borderRadius: 999,
        background: 'linear-gradient(135deg,#2A9D8F,#1B6E64)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        color: '#F5F5F5',
        fontSize: 15,
        fontWeight: 700,
      }}
    >
      M
    </div>
  </div>
)

export const ScreenHeader: React.FC<{ titulo: string; subtitulo?: string }> = ({
  titulo,
  subtitulo,
}) => (
  <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '14px 16px 10px' }}>
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
    <div style={{ minWidth: 0 }}>
      <div style={{ fontSize: 17, fontWeight: 700, color: C.text }}>{titulo}</div>
      {subtitulo ? (
        <div style={{ fontSize: 12, color: C.textDim, marginTop: 1 }}>{subtitulo}</div>
      ) : null}
    </div>
  </div>
)

const Aba: React.FC<{ icone: React.ReactNode; label: string; ativa?: boolean }> = ({
  icone,
  label,
  ativa = false,
}) => (
  <div
    style={{
      flex: 1,
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      justifyContent: 'center',
      gap: 4,
      color: ativa ? C.brandLight : C.textMuted,
      paddingTop: 10,
    }}
  >
    {icone}
    <span style={{ fontSize: 10.5, fontWeight: 600 }}>{label}</span>
  </div>
)

/** TabBar (4 abas + vão central) + os 2 FABs. Renderizar por último na tela. */
export const TabBarComFabs: React.FC<{ ativa?: 'inicio' | 'alunos' | 'agenda' | 'mais' }> = ({
  ativa = 'inicio',
}) => (
  <>
    {/* FAB do microfone (direita, acima da barra) */}
    <div
      style={{
        position: 'absolute',
        right: 16,
        bottom: 100,
        width: 64,
        height: 64,
        borderRadius: 999,
        background: C.bgSurface,
        border: `1px solid ${C.borderStrong}`,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        color: C.brand,
        boxShadow: '0 10px 25px -5px rgba(0,0,0,.5)',
        zIndex: 30,
      }}
    >
      <Ico n="mic" t={23} />
    </div>

    {/* barra */}
    <div
      style={{
        position: 'absolute',
        left: 0,
        right: 0,
        bottom: 0,
        height: 72,
        background: C.bgSurface,
        borderTop: `1px solid ${C.border}`,
        display: 'flex',
        zIndex: 20,
        fontFamily: FONT,
      }}
    >
      <Aba icone={<Ico n="house" t={17} />} label="Início" ativa={ativa === 'inicio'} />
      <Aba icone={<Ico n="users" t={17} />} label="Alunos" ativa={ativa === 'alunos'} />
      <div style={{ flex: 1 }} />
      <Aba icone={<Ico n="calendar" t={17} />} label="Agenda" ativa={ativa === 'agenda'} />
      <Aba icone={<ListPlusIco t={19} />} label="Mais" ativa={ativa === 'mais'} />
    </div>

    {/* FAB central — o Fábio herói (robozinho REAL do app) */}
    <div
      style={{
        position: 'absolute',
        left: '50%',
        bottom: 30,
        transform: 'translateX(-50%)',
        width: 64,
        height: 64,
        borderRadius: 999,
        background: C.brand,
        border: `4px solid ${C.bgApp}`,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        boxShadow: '0 10px 25px -5px rgba(42,157,143,.45)',
        zIndex: 30,
      }}
    >
      <FabioIcon
        style={
          { width: 32, height: 32, '--fabio-fill': '#F5F5F5', '--fabio-traco': '#1B6E64' } as React.CSSProperties
        }
      />
    </div>
  </>
)
