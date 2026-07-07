import { useState, type ReactNode } from 'react'
import {
  AulaRow,
  Badge,
  Button,
  Card,
  EmptyState,
  Fab,
  FabioCard,
  Fatia,
  FieldCard,
  ScreenHeader,
  TabBar,
  Toast,
  useToast,
} from '../../components/ui'
import { useTheme } from '../../lib/theme'

const TABS = [
  { id: 'inicio', label: 'Início', icon: 'fa-solid fa-house' },
  { id: 'alunos', label: 'Alunos', icon: 'fa-solid fa-user-group' },
  { id: 'agenda', label: 'Agenda', icon: 'fa-solid fa-calendar' },
  { id: 'fabio', label: 'Fábio', icon: 'fa-solid fa-robot' },
]

function Section({ n, title, children }: { n: number; title: string; children: ReactNode }) {
  return (
    <section className="space-y-2">
      <h2 className="flex items-center gap-2 text-[12.5px] font-bold uppercase tracking-[.5px] text-text-secondary">
        <span className="flex h-5 w-5 items-center justify-center rounded-full bg-brand-soft text-[10.5px] text-brand-text">
          {n}
        </span>
        {title}
      </h2>
      {children}
    </section>
  )
}

/** /dev/ds — vitrine viva do Fábio DS v1.0: os 12 componentes base nos 2 temas. */
export default function DesignSystemPage() {
  const { theme, toggle } = useTheme()
  const { message, visible, show } = useToast()
  const [tab, setTab] = useState('inicio')

  return (
    <div className="flex h-dvh justify-center overflow-hidden bg-bg-app">
      <div className="relative flex h-dvh w-full max-w-[430px] flex-col overflow-hidden border-x border-border-subtle bg-bg-app">
        {/* 11 · ScreenHeader (com voltar + slot direito) */}
        <ScreenHeader
          title="Fábio DS v1.0"
          subtitle={`/dev/ds · tema ${theme}`}
          onBack={() => show('Você já está na vitrine do DS 😉')}
          right={
            <Button variant="ghost" size="sm" onClick={toggle}>
              <i className="fa-solid fa-circle-half-stroke" aria-hidden="true" />
              {theme === 'dark' ? 'Claro' : 'Escuro'}
            </Button>
          }
        />

        <div className="flex-1 space-y-6 overflow-y-auto px-4 pb-32 pt-2">
          <Section n={1} title="Button">
            <div className="flex flex-wrap items-center gap-2">
              <Button onClick={() => show('Ação primária ✓')}>
                <i className="fa-solid fa-check" aria-hidden="true" /> Confirmar
              </Button>
              <Button variant="ghost">
                <i className="fa-solid fa-microphone" aria-hidden="true" /> Corrigir por voz
              </Button>
              <Button size="sm">Aceitar</Button>
              <Button variant="ghost" size="sm">
                Agora não
              </Button>
            </div>
            <Button block variant="ghost">
              Botão block
            </Button>
          </Section>

          <Section n={2} title="Badge">
            <div className="flex flex-wrap gap-2">
              <Badge variant="ok" icon="fa-solid fa-check">
                Registrada
              </Badge>
              <Badge variant="warn" icon="fa-solid fa-clock">
                1 dia
              </Badge>
              <Badge variant="danger">faltou</Badge>
              <Badge variant="brand" icon="fa-solid fa-microphone">
                Registrar
              </Badge>
              <Badge variant="info">1 checkpoint</Badge>
            </div>
          </Section>

          <Section n={3} title="Card + 4 · AulaRow">
            <Card title="Hoje" icon="fa-solid fa-calendar-day" right="2 de 5 registradas">
              <AulaRow
                hora="14h"
                titulo="Baby Class 1"
                detalhe="Turma · 5 bebês"
                badge={
                  <Badge variant="ok" icon="fa-solid fa-check">
                    Registrada
                  </Badge>
                }
                status="ok"
              />
              <AulaRow
                hora="17h"
                titulo="Musicalização Prep"
                detalhe="Turma Qua/Sex · 4 crianças"
                badge={
                  <Badge variant="brand" icon="fa-solid fa-microphone" onClick={() => show('Registro por voz chega no Sprint 3 🎙️')}>
                    Registrar
                  </Badge>
                }
                status="now"
              />
              <AulaRow hora="18h" titulo="Bateria · Theo" detalhe="Individual · Molde C" status="next" />
            </Card>
          </Section>

          <Section n={5} title="FabioCard">
            <FabioCard tag="pré-aula · 17h">
              <p>
                🥁 O <b>Gael</b> vem brilhando na condução rítmica há 2 aulas — hoje cabe um desafio novo.
              </p>
              <p>
                💛 A <b>Alice</b> faltou 2 das últimas 4. Se ela vier, um cuidado extra faz diferença.
              </p>
            </FabioCard>
          </Section>

          <Section n={6} title="FieldCard (normal · editável · dever · cutucada)">
            <div className="overflow-hidden rounded-lg border border-border-subtle bg-bg-surface">
              <FieldCard
                label="Atividades"
                icon="fa-solid fa-music"
                value="Trem rítmico com copos e revezamento de andamento (rápido ⇄ lento)."
                editable
                onChange={() => show('Campo atualizado ✓')}
              />
              <FieldCard
                label="Dever de casa"
                icon="fa-solid fa-house"
                value="Praticar a sequência de palmas acompanhando o vídeo enviado no grupo."
                dever
                editable
                onChange={() => show('Campo atualizado ✓')}
              />
              <FieldCard
                label="Próximo passo"
                icon="fa-solid fa-route"
                value="Não ouvi esse ponto no áudio — toque pra completar (eu nunca invento ✋)"
                placeholder
              />
            </div>
          </Section>

          <Section n={7} title="Fatia (presente aberta · faltou)">
            <div className="space-y-[9px]">
              <Fatia nome="Gael" defaultOpen>
                <FieldCard
                  label="Progresso"
                  icon="fa-solid fa-arrow-trend-up"
                  value="Conduziu o grupo no trem rítmico com segurança — assumiu a liderança com naturalidade."
                  editable
                  onChange={() => show('Campo atualizado ✓')}
                />
              </Fatia>
              <Fatia nome="Bento" presenca="faltou">
                <FieldCard
                  label="Presença"
                  icon="fa-solid fa-circle-info"
                  value="Ausente — sem registro de conteúdo. Nada foi inventado. ✋"
                />
              </Fatia>
            </div>
          </Section>

          <Section n={8} title="EmptyState">
            <Card title="Pendências" icon="fa-solid fa-bell">
              <EmptyState
                icon="fa-solid fa-mug-hot"
                title="Tudo em dia! 🎉"
                description="Nenhuma aula pendente de registro. Aproveita o café — o Fábio te avisa quando a próxima terminar."
                action={
                  <Button size="sm" variant="ghost" onClick={() => show('Agenda completa entra no P4 📅')}>
                    Ver agenda da semana
                  </Button>
                }
              />
            </Card>
          </Section>

          <Section n={9} title="Toast">
            <Button variant="ghost" onClick={() => show('Fábio: registro de hoje no capricho 👏')}>
              <i className="fa-solid fa-bell" aria-hidden="true" /> Disparar toast
            </Button>
          </Section>

          <p className="text-center text-[10.5px] tracking-[.3px] text-text-muted">
            10 · Fab e 12 · TabBar fixos abaixo — tema atual: {theme}
          </p>
        </div>

        {/* 12 · TabBar + 10 · Fab + Toast overlay */}
        <TabBar
          items={TABS}
          activeId={tab}
          onSelect={(id) => {
            setTab(id)
            if (id === 'fabio') show('Chat com o Fábio chega no Sprint 4 🤖')
          }}
        />
        <Fab onClick={() => show('Registro por voz chega no Sprint 3 🎙️')} />
        <Toast message={message} visible={visible} />
      </div>
    </div>
  )
}
