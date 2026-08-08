import React from 'react'
import { staticFile, useCurrentFrame } from 'remotion'
import { C } from '../tokens'
import { MarcaLA } from '../ui/MarcaLA'

/**
 * Tela de login — réplica fiel de src/pages/app/Login.tsx.
 *
 * ⚠️ REFEITA EM 08/08/2026. A versão anterior mostrava e-mail + senha, e a
 * narração mandava usar "a senha que a coordenação te passou". O login virou
 * WhatsApp + código de 8 dígitos (migrations 056/057, edge `professor-entrar`)
 * e não existe senha nenhuma no caminho do professor. Um vídeo de onboarding
 * que ensina o passo errado é pior que vídeo nenhum: a pessoa tenta, não
 * consegue, e conclui que o app não funciona no aparelho dela.
 *
 * São DUAS telas na mesma cena, como no app: pedir o código e digitar o
 * código. O campo do código tem 8 zeros de placeholder de propósito — o
 * mesmo detalhe que eu tinha errado no app (o Auth gera 8, não 6).
 *
 * Medidas auditadas: moldura 430px, avatar 120px com glow rosa 24px, título
 * Prompt 900/32px ("LA" rosa + "Teacher" off-white), labels uppercase 11px,
 * inputs raio 12px sobre ink-800, botão teal 14.5px.
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
  /** o campo do código é grande, centralizado e espaçado */
  codigo?: boolean
}> = ({ label, valor, placeholder, focado = false, codigo = false }) => (
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
        padding: codigo ? '14px' : '12px 14px',
        fontSize: codigo ? 22 : 14,
        background: LOGIN.inputBg,
        border: `1px solid ${focado ? C.brand : LOGIN.inputBorder}`,
        color: valor ? LOGIN.text : 'rgba(245,245,245,.45)',
        boxShadow: focado ? `0 0 0 2px ${LOGIN.bg}, 0 0 0 4px #48BFB3` : 'none',
        minHeight: 20,
        display: 'flex',
        alignItems: 'center',
        justifyContent: codigo ? 'center' : 'flex-start',
        letterSpacing: codigo ? '.35em' : undefined,
      }}
    >
      {valor || placeholder}
    </div>
  </label>
)

const Botao: React.FC<{ children: React.ReactNode; pressionado?: boolean }> = ({
  children,
  pressionado = false,
}) => (
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
      transform: pressionado ? 'scale(.97)' : 'scale(1)',
    }}
  >
    {children}
  </div>
)

export const Login: React.FC<{
  /** quantos caracteres do WhatsApp já foram "digitados" */
  telefoneDigitado?: number
  focoTelefone?: boolean
  /** a partir daqui a tela troca pro passo do código */
  modoCodigo?: boolean
  codigoDigitado?: number
  focoCodigo?: boolean
  entrando?: boolean
}> = ({
  telefoneDigitado = 0,
  focoTelefone = false,
  modoCodigo = false,
  codigoDigitado = 0,
  focoCodigo = false,
  entrando = false,
}) => {
  const frame = useCurrentFrame()

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
            transform: 'translateX(-50%) rotate(-6deg)',
          }}
        >
          <MarcaLA largura={470} cor={LOGIN.watermark} />
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
        {!modoCodigo ? (
          <>
            <div style={{ marginBottom: 12, fontSize: 13, lineHeight: 1.5, color: LOGIN.muted }}>
              Coloca teu WhatsApp que eu te mando um código de acesso. Sem senha pra decorar.
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
              <Campo
                label="WhatsApp"
                valor={TELEFONE.slice(0, telefoneDigitado)}
                placeholder="21 99999-9999"
                focado={focoTelefone}
              />
              <Botao pressionado={entrando}>
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
                    Mandando…
                  </>
                ) : (
                  <>✆ Receber código</>
                )}
              </Botao>
            </div>
            <div
              style={{
                marginTop: 16,
                textAlign: 'center',
                fontSize: 12.5,
                color: LOGIN.muted,
                textDecoration: 'underline',
                textUnderlineOffset: 3,
              }}
            >
              Entrar com e-mail e senha
            </div>
          </>
        ) : (
          <>
            <div style={{ marginBottom: 12, fontSize: 13, lineHeight: 1.5, color: LOGIN.muted }}>
              Boa, Matheus! Mandei um código no WhatsApp{' '}
              <b style={{ color: LOGIN.text }}>5521·····47</b>. Ele vale por 1 hora.
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
              <Campo
                label="Código"
                valor={CODIGO.slice(0, codigoDigitado)}
                placeholder="00000000"
                focado={focoCodigo}
                codigo
              />
              <Botao pressionado={entrando}>
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
                    Conferindo…
                  </>
                ) : (
                  <>→ Entrar</>
                )}
              </Botao>
            </div>
          </>
        )}
      </div>
    </div>
  )
}

/** O número do Matheus, do jeito que ele digitaria — sem o 55. */
export const TELEFONE = '21 98127-8047'
/** 8 dígitos: é o que o Supabase Auth gera (mailer_otp_length = 8, medido). */
export const CODIGO = '48210673'
