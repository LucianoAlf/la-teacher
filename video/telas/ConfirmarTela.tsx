import React from 'react'
import { useCurrentFrame } from 'remotion'
import { C, FONT } from '../tokens'
import { Ico } from '../ui/Icones'
import { AvatarInicial, Badge } from '../ui/Cartoes'
import { FabioIcon } from '../../src/components/ui/FabioIcon'

/**
 * "Confere aí 👇" — réplica do Confirmar: selo do Fábio, TRONCO ("O que a
 * turma trabalhou" + campos com rótulo uppercase; vazio = cutucada em
 * itálico), fatia da Valentina (accordion aberto, badge presente) e o rodapé
 * fixo com gradiente. O dedo toca em Observações → halo teal duplo + texto
 * digitado (`obsDigitada` chars) → toast "Campo atualizado ✓".
 */

export const OBS_TEXTO = 'Preparar a apresentação do fim do mês.'

const Rotulo: React.FC<{ icone: string; texto: string }> = ({ icone, texto }) => (
  <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 4 }}>
    <span style={{ color: C.brandLight }}>
      <Ico n={icone} t={10} />
    </span>
    <span
      style={{
        fontSize: 11,
        fontWeight: 700,
        textTransform: 'uppercase',
        letterSpacing: '.5px',
        color: C.textDim,
        flex: 1,
      }}
    >
      {texto}
    </span>
    <span style={{ color: C.textMuted }}>
      <Ico n="pen" t={9} />
    </span>
  </div>
)

const Campo: React.FC<{
  icone: string
  rotulo: string
  valor?: string
  cutucada?: string
  ambar?: boolean
  halo?: boolean
}> = ({ icone, rotulo, valor, cutucada, ambar = false, halo = false }) => (
  <div
    style={{
      padding: '10px 12px',
      borderRadius: 12,
      background: ambar ? 'rgba(234,179,8,.12)' : C.bgApp,
      border: `1px solid ${ambar ? 'rgba(234,179,8,.35)' : C.border}`,
      boxShadow: halo ? `0 0 0 2px ${C.bgApp}, 0 0 0 4px #48BFB3` : 'none',
      marginBottom: 8,
    }}
  >
    <Rotulo icone={icone} texto={rotulo} />
    {valor ? (
      <div style={{ fontSize: 14, color: C.text, lineHeight: 1.45 }}>{valor}</div>
    ) : (
      <div style={{ fontSize: 13, color: C.textMuted, fontStyle: 'italic', lineHeight: 1.45 }}>
        {cutucada}
      </div>
    )}
  </div>
)

export const ConfirmarTela: React.FC<{
  scrollY?: number
  /** quantos caracteres da observação já foram digitados (0 = cutucada) */
  obsDigitada?: number
  obsFoco?: boolean
  toastVisivel?: boolean
  gravando?: boolean
}> = ({ scrollY = 0, obsDigitada = 0, obsFoco = false, toastVisivel = false, gravando = false }) => {
  const frame = useCurrentFrame()
  const obs = OBS_TEXTO.slice(0, obsDigitada)

  return (
    <div style={{ height: '100%', background: C.bgApp, fontFamily: FONT, position: 'relative', overflow: 'hidden' }}>
      <div style={{ transform: `translateY(${-scrollY}px)` }}>
        <div style={{ padding: '14px 18px 8px' }}>
          <div style={{ fontSize: 17, fontWeight: 700, color: C.text }}>Confere aí 👇</div>
          <div style={{ fontSize: 12, color: C.textDim, marginTop: 1 }}>
            Canto · Valentina · Seg, 03/08 · 11h
          </div>
        </div>

        <div style={{ padding: '0 16px 150px', display: 'flex', flexDirection: 'column', gap: 12 }}>
          {/* selo do Fábio */}
          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: 9,
              background: C.brandSoft,
              border: `1px solid ${C.brandBorder}`,
              borderRadius: 12,
              padding: '9px 12px',
            }}
          >
            <FabioIcon
              style={{ width: 17, height: 17, flexShrink: 0, '--fabio-fill': C.brandLight, '--fabio-traco': C.bgSurface } as React.CSSProperties}
            />
            <span style={{ fontSize: 12, fontWeight: 600, color: C.text, lineHeight: 1.45 }}>
              Fábio organizou seu áudio — confira e confirme. Eu nunca invento: campo vazio é
              convite ✋
            </span>
          </div>

          {/* TRONCO */}
          <div style={{ borderRadius: 16, border: `1px solid ${C.brandBorder}`, overflow: 'hidden' }}>
            <div
              style={{
                background: C.brandSoft,
                padding: '10px 12px',
                display: 'flex',
                alignItems: 'center',
                gap: 8,
              }}
            >
              <span style={{ color: C.brandLight }}>
                <Ico n="music" t={13} />
              </span>
              <span
                style={{
                  flex: 1,
                  fontSize: 13,
                  fontWeight: 700,
                  textTransform: 'uppercase',
                  letterSpacing: '.5px',
                  color: C.text,
                }}
              >
                O que a turma trabalhou
              </span>
              <Badge tom="teal">tronco</Badge>
            </div>
            <div style={{ padding: 10, background: C.bgSurface }}>
              <Campo
                icone="music"
                rotulo="Atividades"
                valor="“Temos que Pegar” (Pokémon) + vocalizes e respiração."
              />
              <Campo
                icone="bullseye"
                rotulo="Objetivo trabalhado"
                valor="Decorar a letra, com preparação vocal e respiratória."
              />
              <Campo
                icone="commentDots"
                rotulo="Observações"
                valor={obs || undefined}
                cutucada="Alguma observação geral da aula? (ex.: o que fazer na próxima) (opcional)"
                halo={obsFoco}
              />
              <Campo icone="house" rotulo="Dever de casa" valor="Ouvir a música para decorar a letra." ambar />
            </div>
          </div>

          {/* FATIAS */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 7, marginTop: 2 }}>
            <span style={{ color: C.brandLight }}>
              <Ico n="users" t={13} />
            </span>
            <span
              style={{
                fontSize: 12.5,
                fontWeight: 700,
                textTransform: 'uppercase',
                letterSpacing: '.4px',
                color: C.textDim,
              }}
            >
              Fatias por aluno · 1
            </span>
          </div>

          <div style={{ borderRadius: 16, border: `1px solid ${C.border}`, background: C.bgSurface, padding: 10 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '2px 2px 10px' }}>
              <AvatarInicial nome="Valentina" t={34} />
              <span style={{ fontSize: 14.5, fontWeight: 700, color: C.text, flex: 1 }}>Valentina</span>
              <Badge tom="ok">presente</Badge>
              <span style={{ color: C.textMuted, transform: 'rotate(90deg)' }}>
                <Ico n="chevronRight" t={12} />
              </span>
            </div>
            <Campo
              icone="trendUp"
              rotulo="Progresso"
              valor="Cantou a música inteira sem apoio no refrão."
            />
            <Campo
              icone="route"
              rotulo="Próximo passo"
              valor="Sustentar o agudo do final sem forçar."
            />
            <Campo
              icone="eye"
              rotulo="Observação"
              cutucada="Alguma observação sobre Valentina? (opcional)"
            />
          </div>

          {/* preview do texto final */}
          <div
            style={{
              borderRadius: 12,
              border: `1px dashed ${C.brandBorder}`,
              padding: '11px 14px',
              textAlign: 'center',
              fontSize: 12.5,
              fontWeight: 600,
              color: C.brandLight,
            }}
          >
            Ver o texto final que será gravado
          </div>
        </div>
      </div>

      {/* toast */}
      {toastVisivel ? (
        <div
          style={{
            position: 'absolute',
            left: '50%',
            bottom: 118,
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
          Campo atualizado ✓
        </div>
      ) : null}

      {/* rodapé fixo com gradiente */}
      <div
        style={{
          position: 'absolute',
          left: 0,
          right: 0,
          bottom: 0,
          padding: '28px 16px 18px',
          background: `linear-gradient(to top, ${C.bgApp} 55%, transparent)`,
          display: 'flex',
          gap: 10,
          zIndex: 30,
        }}
      >
        <div
          style={{
            flex: 1,
            borderRadius: 12,
            padding: '13px 10px',
            border: `1px solid ${C.borderStrong}`,
            color: C.textDim,
            fontSize: 13.5,
            fontWeight: 600,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            gap: 7,
          }}
        >
          <Ico n="mic" t={13} /> Corrigir por voz
        </div>
        <div
          style={{
            flex: 1,
            borderRadius: 12,
            padding: '13px 10px',
            background: C.brand,
            color: '#0A0F0E',
            fontSize: 13.5,
            fontWeight: 700,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            gap: 7,
          }}
        >
          {gravando ? (
            <>
              <span
                style={{
                  width: 12,
                  height: 12,
                  border: '2px solid rgba(10,15,14,.35)',
                  borderTopColor: '#0A0F0E',
                  borderRadius: 999,
                  display: 'inline-block',
                  transform: `rotate(${frame * 12}deg)`,
                }}
              />
              Gravando…
            </>
          ) : (
            <>
              <Ico n="check" t={13} /> Confirmar e gravar
            </>
          )}
        </div>
      </div>
    </div>
  )
}
