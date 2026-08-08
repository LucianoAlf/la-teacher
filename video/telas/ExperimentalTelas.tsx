import React from 'react'
import { staticFile } from 'remotion'
import { C, FONT } from '../tokens'
import { ScreenHeader } from '../ui/AppShell'
import { Badge, Card, TituloCard } from '../ui/Cartoes'
import { Ico } from '../ui/Icones'

/**
 * As quatro telas do ciclo da aula experimental — réplicas de
 * src/pages/app/Experimental*.tsx.
 *
 * POR QUE A EXPERIMENTAL GANHOU CENA PRÓPRIA NO VÍDEO
 * Ela não é uma aula a menos nem a mais: é a única em que a pessoa do outro
 * lado ainda está decidindo se fica na escola. O professor precisa saber ANTES
 * de entrar na sala quem vem, que idade tem e o que a família procurou —
 * coisa que, até o app existir, ele descobria quando o aluno chegava.
 *
 * A FRONTEIRA QUE ESTAS TELAS PRECISAM MOSTRAR
 * O que o professor dita vai pra dois lugares diferentes: a anotação
 * pedagógica fica na escola, e a devolutiva vai pra família. São campos
 * separados na tela de propósito — a fronteira mora no banco, e a tela tem que
 * deixar isso óbvio pra quem dita.
 *
 * `leitura_de_conversao` NÃO aparece aqui, e é intencional: é sinal comercial
 * (migration 055), não é do professor. Mostrar no vídeo ensinaria a procurar
 * um campo que ele nunca vai ver.
 */

const MOLDURA: React.CSSProperties = {
  height: '100%',
  background: C.bgApp,
  position: 'relative',
  overflow: 'hidden',
  fontFamily: FONT,
  display: 'flex',
  flexDirection: 'column',
}

const Corpo: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <div
    style={{
      flex: 1,
      padding: '4px 16px 16px',
      display: 'flex',
      flexDirection: 'column',
      gap: 12,
      overflow: 'hidden',
    }}
  >
    {children}
  </div>
)

const Rotulo: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <div
    style={{
      fontSize: 11,
      fontWeight: 700,
      textTransform: 'uppercase',
      letterSpacing: '.5px',
      color: C.textMuted,
      marginBottom: 6,
    }}
  >
    {children}
  </div>
)

const Botao: React.FC<{
  children: React.ReactNode
  tom?: 'primario' | 'fantasma'
  pressionado?: boolean
}> = ({ children, tom = 'primario', pressionado = false }) => (
  <div
    style={{
      borderRadius: 12,
      padding: '13px 18px',
      background: tom === 'primario' ? C.brand : 'transparent',
      border: tom === 'primario' ? 'none' : `1px solid ${C.borderStrong}`,
      color: tom === 'primario' ? '#0A0F0E' : C.textDim,
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

/* ------------------------------------------------------------------ 1/4 */

/**
 * A ficha: o que o professor sabe ANTES da aula. Tudo aqui vem do lead — a
 * conversa que o comercial já teve com a família — e é a diferença entre
 * "chegou uma criança" e "chegou a Helena, 7 anos, que a mãe quer que faça
 * teclado porque a irmã faz".
 */
export const ExperimentalFicha: React.FC<{ destacarContexto?: boolean }> = ({
  destacarContexto = false,
}) => (
  <div style={MOLDURA}>
    <ScreenHeader titulo="Aula experimental" />
    <Corpo>
      <Card bordaTeal>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <div
            style={{
              width: 46,
              height: 46,
              borderRadius: 999,
              background: C.brandSoft,
              border: `1px solid ${C.brandBorder}`,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              color: C.brandLight,
              fontSize: 19,
              fontWeight: 700,
              flexShrink: 0,
            }}
          >
            H
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 17, fontWeight: 800, color: C.text, letterSpacing: '-.2px' }}>
              Helena Duarte
            </div>
            <div style={{ fontSize: 12.5, color: C.textDim, marginTop: 2 }}>
              7 anos · Teclado · hoje, 16:00
            </div>
          </div>
          <Badge tom="info">★ Experimental</Badge>
        </div>
      </Card>

      <Card bordaTeal={destacarContexto}>
        <TituloCard icone="wand" texto="O que eu já sei dela" />
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          <Linha rotulo="Quem procurou" valor="Camila, mãe da Helena" />
          <Linha rotulo="O que a família quer" valor="A irmã faz teclado aqui. A Helena pediu pra fazer também." />
          <Linha rotulo="Já teve contato com música?" valor="Nunca estudou. Canta o dia inteiro em casa." />
          <Linha rotulo="Atenção" valor="Tímida no começo — a mãe avisou que ela demora a soltar." />
        </div>
      </Card>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginTop: 'auto' }}>
        <Botao>
          <Ico n="mic" t={15} /> Registrar a experimental
        </Botao>
        <Botao tom="fantasma">Ela não veio</Botao>
      </div>
    </Corpo>
  </div>
)

const Linha: React.FC<{ rotulo: string; valor: string }> = ({ rotulo, valor }) => (
  <div>
    <Rotulo>{rotulo}</Rotulo>
    <div style={{ fontSize: 13.5, lineHeight: 1.5, color: C.text }}>{valor}</div>
  </div>
)

/* ------------------------------------------------------------------ 2/4 */

/**
 * Registrar: o MESMO gesto da aula normal — fala e pronto. O que muda é o que
 * o Fábio faz com o áudio: em vez de separar por aluno, ele separa por
 * DESTINO (o que fica na escola × o que vai pra família).
 */
export const ExperimentalRegistrar: React.FC<{
  /** 0 = só o botão; 1 = gravando; 2 = os campos preenchidos */
  etapa?: 0 | 1 | 2
  segundos?: number
}> = ({ etapa = 0, segundos = 0 }) => (
  <div style={MOLDURA}>
    <ScreenHeader titulo="Registrar experimental" />
    <Corpo>
      <div style={{ fontSize: 12.5, color: C.textDim, lineHeight: 1.5 }}>
        Helena Duarte · 7 anos · Teclado
      </div>

      {etapa < 2 ? (
        // Centralizado: com o card colado no topo sobrava meia tela preta
        // embaixo (visto no still), e tela vazia lê como tela quebrada.
        <Card bordaTeal={etapa === 1} style={{ padding: 20, marginTop: 'auto', marginBottom: 'auto' }}>
          <div
            style={{
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
              gap: 14,
              padding: '18px 0',
            }}
          >
            <div
              style={{
                width: 88,
                height: 88,
                borderRadius: 999,
                background: etapa === 1 ? C.brand : C.brandSoft,
                border: `2px solid ${C.brandBorder}`,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                color: etapa === 1 ? '#0A0F0E' : C.brandLight,
                boxShadow: etapa === 1 ? `0 0 0 12px ${C.brandSoft}` : 'none',
              }}
            >
              <Ico n="mic" t={34} />
            </div>
            <div style={{ fontSize: 14.5, fontWeight: 700, color: C.text }}>
              {etapa === 1 ? formatarSegundos(segundos) : 'Toca e conta como foi'}
            </div>
            <div
              style={{
                fontSize: 12.5,
                color: C.textDim,
                textAlign: 'center',
                lineHeight: 1.5,
                maxWidth: 260,
              }}
            >
              {etapa === 1
                ? 'Fala do teu jeito — eu separo depois.'
                : 'O que ela fez, como reagiu, e o que você diria pra família.'}
            </div>
          </div>
        </Card>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          <CampoPreenchido
            rotulo="Como foi a aula"
            selo="fica na escola"
            tom="teal"
            texto="Reconheceu as notas pelo nome depois de duas rodadas. Timidez sumiu no primeiro exercício de imitação."
          />
          <CampoPreenchido
            rotulo="Devolutiva pra família"
            selo="vai pra Camila"
            tom="info"
            texto="A Helena se soltou rápido e saiu tocando as cinco primeiras notas sozinha. Muito ouvido pra idade."
          />
          <CampoPreenchido
            rotulo="Próximos passos"
            selo="fica na escola"
            tom="teal"
            texto="Começar por repertório cantado — ela aprende mais rápido pelo ouvido que pela partitura."
          />
        </div>
      )}
    </Corpo>
  </div>
)

const formatarSegundos = (s: number) =>
  `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(Math.floor(s % 60)).padStart(2, '0')}`

/**
 * O selo ao lado do rótulo é o coração da tela: quem dita precisa VER que
 * "como foi a aula" e "devolutiva" vão pra lugares diferentes. Sem isso o
 * professor escreve pra família num campo que a família nunca lê — ou pior,
 * escreve pra escola num campo que a mãe vai receber.
 */
const CampoPreenchido: React.FC<{
  rotulo: string
  selo: string
  tom: 'teal' | 'info'
  texto: string
}> = ({ rotulo, selo, tom, texto }) => (
  <Card>
    <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
      <span style={{ fontSize: 12.5, fontWeight: 700, color: C.text, flex: 1 }}>{rotulo}</span>
      <Badge tom={tom}>{selo}</Badge>
    </div>
    <div style={{ fontSize: 13, lineHeight: 1.55, color: C.textDim }}>{texto}</div>
  </Card>
)

/* ------------------------------------------------------------------ 3/4 */

/**
 * Confirmar: nada sai sem o OK do professor. Depois do toque acontecem três
 * coisas de uma vez — presença lançada, comercial avisado, prontuário
 * guardado — e a tela conta as três, porque "pronto" genérico não diz a quem
 * a informação chegou.
 */
export const ExperimentalConfirmar: React.FC<{ confirmado?: boolean; pressionado?: boolean }> = ({
  confirmado = false,
  pressionado = false,
}) => (
  <div style={MOLDURA}>
    <ScreenHeader titulo="Conferir e enviar" />
    <Corpo>
      {!confirmado ? (
        <>
          <Card>
            <TituloCard icone="clipboardCheck" texto="Helena Duarte · Teclado" />
            <div style={{ fontSize: 13, lineHeight: 1.55, color: C.textDim }}>
              Reconheceu as notas pelo nome depois de duas rodadas. Timidez sumiu no primeiro
              exercício de imitação.
            </div>
          </Card>
          <Card bordaTeal>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
              <span style={{ fontSize: 12.5, fontWeight: 700, color: C.text, flex: 1 }}>
                Isto aqui a Camila vai receber
              </span>
              <Badge tom="info">vai pra família</Badge>
            </div>
            <div style={{ fontSize: 13, lineHeight: 1.55, color: C.text }}>
              A Helena se soltou rápido e saiu tocando as cinco primeiras notas sozinha. Muito
              ouvido pra idade.
            </div>
          </Card>
          <div style={{ marginTop: 'auto', display: 'flex', flexDirection: 'column', gap: 10 }}>
            <Botao pressionado={pressionado}>✓ Está certo, pode enviar</Botao>
            <Botao tom="fantasma">Voltar e ajustar</Botao>
          </div>
        </>
      ) : (
        <div
          style={{
            flex: 1,
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            justifyContent: 'center',
            gap: 16,
            textAlign: 'center',
          }}
        >
          <img
            src={staticFile('brand/fabio-avatar.svg')}
            alt="Fábio"
            style={{ width: 92, height: 'auto' }}
          />
          <div style={{ fontSize: 19, fontWeight: 800, color: C.text }}>Registrado!</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10, width: '100%' }}>
            <Feito texto="Presença da Helena lançada" />
            <Feito texto="Devolutiva a caminho da Camila" />
            <Feito texto="Comercial já sabe como foi" />
          </div>
        </div>
      )}
    </Corpo>
  </div>
)

const Feito: React.FC<{ texto: string }> = ({ texto }) => (
  <div
    style={{
      display: 'flex',
      alignItems: 'center',
      gap: 10,
      background: C.bgSurface,
      border: `1px solid ${C.border}`,
      borderRadius: 12,
      padding: '11px 14px',
    }}
  >
    <span style={{ color: '#4ADE80' }}>
      <Ico n="check" t={14} />
    </span>
    <span style={{ fontSize: 13, color: C.text }}>{texto}</span>
  </div>
)

/* ------------------------------------------------------------------ 4/4 */

/**
 * Não veio: uma tela, um toque. A experimental que não acontece é informação
 * COMERCIAL urgente — quanto antes o time souber, mais chance de remarcar
 * antes de a família desistir. Por isso não tem formulário: tem um botão.
 */
export const ExperimentalFalta: React.FC<{ pressionado?: boolean; feito?: boolean }> = ({
  pressionado = false,
  feito = false,
}) => (
  <div style={MOLDURA}>
    <ScreenHeader titulo="Helena não veio" />
    <Corpo>
      <div
        style={{
          flex: 1,
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          gap: 16,
          textAlign: 'center',
        }}
      >
        {feito ? (
          <>
            <span style={{ color: '#4ADE80' }}>
              <Ico n="check" t={44} />
            </span>
            <div style={{ fontSize: 19, fontWeight: 800, color: C.text }}>Avisei o comercial</div>
            <div style={{ fontSize: 13.5, lineHeight: 1.6, color: C.textDim, maxWidth: 280 }}>
              Eles já podem falar com a Camila hoje pra remarcar.
            </div>
          </>
        ) : (
          <>
            <div
              style={{
                width: 78,
                height: 78,
                borderRadius: 999,
                background: 'rgba(239,68,68,.12)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                color: '#F87171',
              }}
            >
              <Ico n="userXmark" t={32} />
            </div>
            <div style={{ fontSize: 16.5, fontWeight: 700, color: C.text }}>
              A Helena não apareceu?
            </div>
            <div style={{ fontSize: 13.5, lineHeight: 1.6, color: C.textDim, maxWidth: 280 }}>
              Eu aviso o comercial na hora, e eles correm atrás de remarcar antes que a família
              esfrie.
            </div>
          </>
        )}
      </div>
      {!feito && (
        <Botao pressionado={pressionado}>Confirmar que ela não veio</Botao>
      )}
    </Corpo>
  </div>
)
