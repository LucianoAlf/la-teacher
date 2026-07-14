import type { CSSProperties } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { ListPlus } from 'lucide-react'
import { Fab, FabioIcon, TabBar } from '../../components/ui'

/** Abas planas (4) + vão central pro Fábio herói. */
const TABS = [
  { id: 'inicio', label: 'Início', icon: 'fa-solid fa-house' },
  { id: 'alunos', label: 'Alunos', icon: 'fa-solid fa-user-group' },
  { id: 'agenda', label: 'Agenda', icon: 'fa-solid fa-calendar' },
  // "Mais" = abrir as telas/ferramentas futuras (não "opções desta tela"),
  // por isso o list-plus nativo do Lucide, não o "•••".
  { id: 'mais', label: 'Mais', node: <ListPlus size={19} aria-hidden="true" /> },
]

const ROTA: Record<string, string> = {
  inicio: '/app',
  alunos: '/app/alunos',
  agenda: '/app/agenda',
}

/** Cores do Fábio dentro da bolota teal (silhueta clara + detalhe escuro). */
const FABIO_HERO_VARS = {
  '--fabio-fill': 'var(--fabio-hero-fill)',
  '--fabio-traco': 'var(--fabio-hero-traco)',
} as CSSProperties

interface Props {
  /** Toque em "Mais" (ferramentas futuras). */
  onMais: () => void
}

/**
 * Navegação inferior do app (Fase 3): 4 abas planas com o Fábio HERÓI na bolota
 * central (o coração — chat/dual-channel) e o microfone como FAB flutuante à
 * direita (ação de gravar aula, estilo LA Organizer).
 */
export function AppNav({ onMais }: Props) {
  const nav = useNavigate()
  const { pathname } = useLocation()
  const ativo = pathname.startsWith('/app/alunos')
    ? 'alunos'
    : pathname.startsWith('/app/agenda')
      ? 'agenda'
      : 'inicio'

  return (
    <>
      <TabBar
        items={TABS}
        activeId={ativo}
        onSelect={(id) => {
          if (ROTA[id]) nav(ROTA[id])
          else if (id === 'mais') onMais()
        }}
      />

      {/* Fábio herói — bolota central: abre o chat (espelhado no WhatsApp) */}
      <Fab
        placement="center"
        label="Fábio — seu assistente"
        node={<FabioIcon className="h-[32px] w-[32px]" />}
        style={FABIO_HERO_VARS}
        onClick={() => nav('/app/fabio')}
      />

      {/* Microfone — FAB utilitário flutuante à direita (gravar aula); fundo
          neutro + ícone teal pra não competir com o Fábio herói. */}
      <Fab
        placement="right"
        variant="secondary"
        icon="fa-solid fa-microphone"
        label="Registrar por voz"
        onClick={() => nav('/app/gravar')}
      />
    </>
  )
}
