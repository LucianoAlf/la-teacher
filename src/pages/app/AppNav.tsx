import { useLocation, useNavigate } from 'react-router-dom'
import { Fab, FabioIcon, TabBar } from '../../components/ui'

const TABS = [
  { id: 'inicio', label: 'Início', icon: 'fa-solid fa-house' },
  { id: 'alunos', label: 'Alunos', icon: 'fa-solid fa-user-group' },
  { id: 'agenda', label: 'Agenda', icon: 'fa-solid fa-calendar' },
  { id: 'fabio', label: 'Fábio', node: <FabioIcon className="h-[22px] w-[22px]" /> },
]

const ROTA: Record<string, string> = {
  inicio: '/app',
  alunos: '/app/alunos',
  agenda: '/app/agenda',
}

interface Props {
  /** Toque na aba Fábio (chat é do Sprint 4). */
  onFabio: () => void
}

/** TabBar + FAB do app; o FAB de microfone abre a gravação (P5). */
export function AppNav({ onFabio }: Props) {
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
          if (id === 'fabio') onFabio()
          else if (ROTA[id]) nav(ROTA[id])
        }}
      />
      <Fab onClick={() => nav('/app/gravar')} />
    </>
  )
}
