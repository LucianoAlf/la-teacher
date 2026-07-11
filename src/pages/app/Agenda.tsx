import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Button, ScreenHeader, Toast, useToast } from '../../components/ui'
import { useTheme } from '../../lib/theme'
import { hojeBRT } from '../../lib/date'
import type { SessaoAula } from '../../lib/api'
import { DateNav } from '../../features/agenda/DateNav'
import { CardSessoesDoDia } from '../../features/agenda/CardSessoesDoDia'
import { SemanaStrip } from '../../features/agenda/SemanaStrip'
import { useSessoes } from '../../features/agenda/useSessoes'
import { useSemana } from '../../features/agenda/useSemana'
import { AppFrame } from './AppFrame'
import { AppNav } from './AppNav'

/** /app/agenda — semana compacta + dia selecionado (app_minha_agenda_sessao). */
export default function AgendaPage() {
  const { toggle } = useTheme()
  const { message, visible, show } = useToast()
  const navigate = useNavigate()
  const [data, setData] = useState<string>(hojeBRT())

  const { estado, recarregar } = useSessoes(data)
  const { dias, contagem } = useSemana(data)
  const abrirChamada = (sessao: SessaoAula) =>
    navigate(`/app/chamada/${sessao.aula_id_ancora}`, { state: { sessao } })

  return (
    <AppFrame>
      <ScreenHeader
        title="Agenda"
        subtitle="Sua semana de aulas"
        right={
          <Button variant="ghost" size="sm" onClick={toggle}>
            <i className="fa-solid fa-circle-half-stroke" aria-hidden="true" /> Tema
          </Button>
        }
      />

      <div className="flex-1 overflow-y-auto pb-24">
        <SemanaStrip dias={dias} contagem={contagem} selecionado={data} onSelect={setData} />

        <div className="mx-4 mb-2 overflow-hidden rounded-lg border border-border-subtle bg-bg-surface">
          <DateNav value={data} onChange={setData} />
        </div>

        <div className="px-4">
          <CardSessoesDoDia data={data} estado={estado} onRetry={recarregar} onAbrir={abrirChamada} />
        </div>
      </div>

      <AppNav onFabio={() => show('Chat com o Fábio chega no Sprint 4 🤖')} />
      <Toast message={message} visible={visible} />
    </AppFrame>
  )
}
