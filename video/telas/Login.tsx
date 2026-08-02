import React from 'react'
import { interpolate, staticFile, useCurrentFrame } from 'remotion'
import { C } from '../tokens'

/**
 * Tela de login — réplica fiel de src/pages/app/Login.tsx.
 * Medidas auditadas: moldura 430px, avatar 120px com glow rosa 24px, título
 * Prompt 900/32px ("LA" rosa + "Teacher" off-white), labels uppercase 11px,
 * inputs raio 12px sobre ink-800, botão teal 14.5px.
 *
 * Só a atmosfera muda: aqui os pontinhos e a marca d'água entram junto,
 * porque no vídeo a tela aparece pronta.
 */

const LOGIN = {
  bg: '#0A0F0E',
  inputBg: '#1A2421',
  inputBorder: '#243430',
  text: '#F5F5F5',
  muted: '#9E9E9E',
  dots: 'rgb(233 20 81 / .20)',
  glow: 'rgb(233 20 81 / .28)',
  watermark: 'rgba(245,245,245,.05)',
}

const Campo: React.FC<{
  label: string
  valor: string
  placeholder: string
  focado?: boolean
  senha?: boolean
}> = ({ label, valor, placeholder, focado = false, senha = false }) => (
  <label style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
    <span
      style={{
        fontSize: 11,
        fontWeight: 600,
        textTransform: 'uppercase',
        letterSpacing: '.5px',
        color: LOGIN.muted,
      }}
    >
      {label}
    </span>
    <div
      style={{
        borderRadius: 12,
        padding: '12px 14px',
        fontSize: 14,
        background: LOGIN.inputBg,
        border: `1px solid ${focado ? C.brand : LOGIN.inputBorder}`,
        color: valor ? LOGIN.text : 'rgba(245,245,245,.45)',
        boxShadow: focado ? `0 0 0 2px ${LOGIN.bg}, 0 0 0 4px #48BFB3` : 'none',
        minHeight: 20,
        display: 'flex',
        alignItems: 'center',
      }}
    >
      {valor ? (senha ? '•'.repeat(valor.length) : valor) : placeholder}
    </div>
  </label>
)

export const Login: React.FC<{
  /** quantos caracteres do e-mail já foram "digitados" */
  emailDigitado?: number
  senhaDigitada?: number
  focoEmail?: boolean
  focoSenha?: boolean
  entrando?: boolean
}> = ({
  emailDigitado = 0,
  senhaDigitada = 0,
  focoEmail = false,
  focoSenha = false,
  entrando = false,
}) => {
  const frame = useCurrentFrame()
  const EMAIL = 'matheus.felipe@lamusic.com.br'
  const SENHA = '••••••••'

  return (
    <div
      style={{
        height: '100%',
        background: LOGIN.bg,
        color: LOGIN.text,
        display: 'flex',
        flexDirection: 'column',
        position: 'relative',
        overflow: 'hidden',
      }}
    >
      {/* atmosfera: pontinhos rosa nos 60% do topo + marca d'água LA girada -6° */}
      <div style={{ position: 'absolute', inset: 0, top: 0, height: '60%', zIndex: 0 }}>
        <div
          style={{
            position: 'absolute',
            inset: 0,
            backgroundImage: `radial-gradient(${LOGIN.dots} 1px, transparent 1.2px)`,
            backgroundSize: '14px 14px',
          }}
        />
        <div
          style={{
            position: 'absolute',
            left: '50%',
            top: 0,
            width: 470,
            transform: 'translateX(-50%) rotate(-6deg)',
            color: LOGIN.watermark,
            fontSize: 400,
            fontWeight: 900,
            fontFamily: 'Prompt, sans-serif',
            lineHeight: 0.9,
            userSelect: 'none',
          }}
        >
          LA
        </div>
      </div>

      {/* identidade */}
      <div
        style={{
          position: 'relative',
          zIndex: 10,
          flex: 1,
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          padding: '32px 28px 0',
          textAlign: 'center',
        }}
      >
        <img
          src={staticFile('brand/fabio-avatar.svg')}
          alt="Fábio"
          style={{ width: 120, height: 'auto', filter: `drop-shadow(0 0 24px ${LOGIN.glow})` }}
        />
        <div
          style={{
            marginTop: 16,
            fontFamily: 'Prompt, sans-serif',
            fontSize: 32,
            fontWeight: 900,
            lineHeight: 1,
            letterSpacing: '-.5px',
          }}
        >
          <span style={{ color: C.pink }}>LA</span> <span style={{ color: LOGIN.text }}>Teacher</span>
        </div>
        <div style={{ marginTop: 8, fontSize: 13, lineHeight: 1.45, color: LOGIN.muted }}>
          Suas aulas registradas em segundos, sem digitar.
        </div>
      </div>

      {/* formulário */}
      <div style={{ position: 'relative', zIndex: 10, padding: '0 28px 40px' }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          <Campo
            label="E-mail"
            valor={EMAIL.slice(0, emailDigitado)}
            placeholder="voce@lamusic.com.br"
            focado={focoEmail}
          />
          <Campo
            label="Senha"
            valor={SENHA.slice(0, senhaDigitada)}
            placeholder="••••••••"
            focado={focoSenha}
          />
          <div
            style={{
              marginTop: 8,
              borderRadius: 12,
              padding: '13px 18px',
              background: C.brand,
              color: '#0A0F0E',
              fontWeight: 700,
              fontSize: 14.5,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: 8,
              transform: entrando ? 'scale(.97)' : 'scale(1)',
            }}
          >
            {entrando ? (
              <>
                <span
                  style={{
                    display: 'inline-block',
                    width: 13,
                    height: 13,
                    border: '2px solid rgba(10,15,14,.35)',
                    borderTopColor: '#0A0F0E',
                    borderRadius: 999,
                    transform: `rotate(${frame * 12}deg)`,
                  }}
                />
                Entrando…
              </>
            ) : (
              <>→ Entrar</>
            )}
          </div>
        </div>
        <div
          style={{
            marginTop: 20,
            textAlign: 'center',
            fontSize: 12,
            lineHeight: 1.625,
            color: LOGIN.muted,
          }}
        >
          Sem acesso ainda? Fala com a coordenação da sua unidade pra ativar seu login.
        </div>
      </div>
    </div>
  )
}
