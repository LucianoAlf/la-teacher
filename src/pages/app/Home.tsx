import { useState } from 'react'
import { Fab, ScreenHeader, TabBar, Toast, useToast, Button, FabioCard } from '../../components/ui'
import { useAuth } from '../../lib/auth'
import { useTheme } from '../../lib/theme'
import { AppFrame } from './AppFrame'

const TABS = [
  { id: 'inicio', label: 'Início', icon: 'fa-solid fa-house' },
  { id: 'alunos', label: 'Alunos', icon: 'fa-solid fa-user-group' },
  { id: 'agenda', label: 'Agenda', icon: 'fa-solid fa-calendar' },
  { id: 'fabio', label: 'Fábio', icon: 'fa-solid fa-robot' },
]

/**
 * /app — landing autenticada. Placeholder do P2: prova que o login entrou
 * e que dá pra sair. A Home com dados vivos (agenda real) chega no P3.
 */
export default function HomePage() {
  const { session, signOut } = useAuth()
  const { theme, toggle } = useTheme()
  const { message, visible, show } = useToast()
  const [tab, setTab] = useState('inicio')

  return (
    <AppFrame>
      <ScreenHeader
        title="Você está dentro 🎉"
        subtitle={session?.user.email ?? undefined}
        right={
          <Button variant="ghost" size="sm" onClick={toggle}>
            <i className="fa-solid fa-circle-half-stroke" aria-hidden="true" />
            {theme === 'dark' ? 'Claro' : 'Escuro'}
          </Button>
        }
      />

      <div className="flex-1 space-y-3 overflow-y-auto px-4 pb-32 pt-2">
        <FabioCard tag="em breve">
          <p>
            Seu login e vínculo estão ok ✅. A <b>Home com a agenda real do dia</b> chega no próximo passo
            (P3) — junto com o briefing de verdade e as pendências de ontem.
          </p>
          <p>Por ora, dá pra alternar o tema no topo e conferir que o logout funciona 👇</p>
        </FabioCard>

        <Button block variant="ghost" onClick={signOut}>
          <i className="fa-solid fa-arrow-right-from-bracket" aria-hidden="true" /> Sair
        </Button>
      </div>

      <TabBar
        items={TABS}
        activeId={tab}
        onSelect={(id) => {
          setTab(id)
          if (id === 'agenda') show('Agenda entra no P4 📅')
          if (id === 'alunos') show('Alunos entra no P4 👥')
          if (id === 'fabio') show('Chat com o Fábio chega no Sprint 4 🤖')
        }}
      />
      <Fab onClick={() => show('Registro por voz chega no Sprint 3 🎙️')} />
      <Toast message={message} visible={visible} />
    </AppFrame>
  )
}
