import React from 'react'
import { useCurrentFrame } from 'remotion'
import { C, FONT } from '../tokens'
import { Card } from '../ui/Cartoes'
import { ScreenHeader } from '../ui/AppShell'
import { Ico } from '../ui/Icones'

/**
 * "Meu perfil" (Perfil.tsx + PreferenciasFabio): informações da conta,
 * "Como o Fábio te conhece" (apelido + Bio com contador /400) e
 * "Como o Fábio te avisa" (App/WhatsApp/Ambos + lembretes no domingo).
 * A bio é digitada pelo dedo (`bioDigitada` chars) e salva com toast.
 */

export const BIO = 'Baterista, 12 anos de palco. Gosto de aula com groove e do repertório que o aluno ama.'

const Cabecalho: React.FC<{ texto: string }> = ({ texto }) => (
  <div
    style={{
      fontSize: 11,
      fontWeight: 700,
      textTransform: 'uppercase',
      letterSpacing: '.5px',
      color: C.textDim,
      margin: '2px 2px 8px',
    }}
  >
    {texto}
  </div>
)

export const PerfilTela: React.FC<{
  scrollY?: number
  bioDigitada?: number
  bioFoco?: boolean
  toastVisivel?: boolean
}> = ({ scrollY = 0, bioDigitada = 0, bioFoco = false, toastVisivel = false }) => {
  const frame = useCurrentFrame()
  const bio = BIO.slice(0, bioDigitada)

  const Linha: React.FC<{ rotulo: string; valor: string }> = ({ rotulo, valor }) => (
    <div style={{ display: 'flex', gap: 10, padding: '7px 0', alignItems: 'baseline' }}>
      <span style={{ width: 76, fontSize: 12.5, fontWeight: 700, color: C.textDim, flexShrink: 0 }}>
        {rotulo}
      </span>
      <span style={{ fontSize: 14, color: C.text, minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
        {valor}
      </span>
    </div>
  )

  const Segmento: React.FC<{ icone: string; texto: string; ativo?: boolean }> = ({ icone, texto, ativo }) => (
    <div
      style={{
        flex: 1,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        gap: 6,
        padding: '9px 4px',
        borderRadius: 10,
        background: ativo ? C.bgSurface : 'transparent',
        color: ativo ? C.brandLight : C.textDim,
        fontSize: 12.5,
        fontWeight: 700,
        boxShadow: ativo ? '0 2px 8px rgba(0,0,0,.35)' : 'none',
      }}
    >
      <Ico n={icone} t={12} /> {texto}
    </div>
  )

  return (
    <div style={{ height: '100%', background: C.bgApp, fontFamily: FONT, position: 'relative', overflow: 'hidden' }}>
      <div style={{ transform: `translateY(${-scrollY}px)` }}>
        <ScreenHeader titulo="Meu perfil" subtitulo="O que o Fábio usa pra te conhecer melhor" />

        <div style={{ padding: '0 16px 60px', display: 'flex', flexDirection: 'column', gap: 12 }}>
          {/* foto */}
          <Card style={{ textAlign: 'center', padding: '18px 14px' }}>
            <div
              style={{
                width: 92,
                height: 92,
                borderRadius: 999,
                margin: '0 auto',
                background: 'linear-gradient(135deg,#2A9D8F,#1B6E64)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                color: '#F5F5F5',
                fontSize: 32,
                fontWeight: 800,
              }}
            >
              M
            </div>
            <div style={{ marginTop: 10, fontSize: 12.5, color: C.textDim }}>
              Trocar foto chega em breve 📸
            </div>
          </Card>

          {/* informações da conta */}
          <div>
            <Cabecalho texto="Informações da conta" />
            <Card style={{ padding: '8px 14px' }}>
              <Linha rotulo="Nome" valor="Matheus Felipe" />
              <Linha rotulo="E-mail" valor="matheus.felipe@lamusic.com.br" />
              <Linha rotulo="WhatsApp" valor="(21) 9 8127-…" />
              <Linha rotulo="Unidade" valor="Campo Grande" />
            </Card>
          </div>

          {/* como o Fábio te conhece */}
          <div>
            <Cabecalho texto="Como o Fábio te conhece" />
            <Card>
              <div style={{ fontSize: 12.5, fontWeight: 700, color: C.textDim, marginBottom: 5 }}>
                Como quer ser chamado
              </div>
              <div
                style={{
                  borderRadius: 12,
                  padding: '11px 13px',
                  background: C.bgHover,
                  border: `1px solid ${C.borderStrong}`,
                  fontSize: 14,
                  color: C.text,
                }}
              >
                Matheus
              </div>

              <div style={{ fontSize: 12.5, fontWeight: 700, color: C.textDim, margin: '13px 0 5px' }}>Bio</div>
              <div
                style={{
                  borderRadius: 12,
                  padding: '11px 13px',
                  background: C.bgHover,
                  border: `1px solid ${bioFoco ? C.brand : C.borderStrong}`,
                  boxShadow: bioFoco ? `0 0 0 2px ${C.bgApp}, 0 0 0 4px #48BFB3` : 'none',
                  fontSize: 14,
                  color: bio ? C.text : C.textMuted,
                  lineHeight: 1.5,
                  minHeight: 76,
                }}
              >
                {bio ||
                  'Instrumento, estilo de aula, preferências… o que o Fábio deve saber sobre você.'}
              </div>
              <div style={{ textAlign: 'right', fontSize: 11, color: C.textMuted, marginTop: 4 }}>
                {bio.length}/400
              </div>

              <div
                style={{
                  marginTop: 8,
                  borderRadius: 12,
                  padding: '12px 16px',
                  background: C.brand,
                  color: '#0A0F0E',
                  fontSize: 13.5,
                  fontWeight: 700,
                  textAlign: 'center',
                }}
              >
                Salvar perfil
              </div>
            </Card>
          </div>

          {/* como o Fábio te avisa */}
          <div>
            <Cabecalho texto="Como o Fábio te avisa" />
            <Card>
              <div style={{ fontSize: 12.5, fontWeight: 700, color: C.textDim, marginBottom: 6 }}>
                Onde quero receber
              </div>
              <div
                style={{
                  display: 'flex',
                  gap: 4,
                  background: C.bgApp,
                  border: `1px solid ${C.border}`,
                  borderRadius: 12,
                  padding: 4,
                }}
              >
                <Segmento icone="mobile" texto="App" />
                <Segmento icone="whatsapp" texto="WhatsApp" />
                <Segmento icone="bell" texto="Ambos" ativo />
              </div>

              <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginTop: 14 }}>
                <div style={{ flex: 1 }}>
                  <div style={{ fontSize: 13.5, fontWeight: 600, color: C.text }}>
                    Lembretes no domingo
                  </div>
                  <div style={{ fontSize: 12, color: C.textDim, marginTop: 2 }}>
                    Receber avisos do Fábio também aos domingos
                  </div>
                </div>
                <div
                  style={{
                    width: 46,
                    height: 26,
                    borderRadius: 999,
                    background: C.brand,
                    position: 'relative',
                    flexShrink: 0,
                  }}
                >
                  <div
                    style={{
                      position: 'absolute',
                      top: 3,
                      right: 3,
                      width: 20,
                      height: 20,
                      borderRadius: 999,
                      background: '#F5F5F5',
                    }}
                  />
                </div>
              </div>
            </Card>
          </div>

          <div style={{ textAlign: 'center', fontSize: 11, color: C.textMuted }}>
            LA Teacher · v1.12 · 03/08/2026 07:58
          </div>
        </div>
      </div>

      {/* toast */}
      {toastVisivel ? (
        <div
          style={{
            position: 'absolute',
            left: '50%',
            bottom: 26,
            transform: 'translateX(-50%)',
            background: C.bgRaised,
            border: `1px solid ${C.borderStrong}`,
            borderRadius: 999,
            padding: '8px 16px',
            fontSize: 12.5,
            fontWeight: 600,
            color: C.text,
            zIndex: 40,
            whiteSpace: 'nowrap',
          }}
        >
          Perfil atualizado ✓
        </div>
      ) : null}
    </div>
  )
}
