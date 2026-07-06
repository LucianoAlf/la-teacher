import { useState } from 'react'
import { Button, ScreenHeader, Toast, useToast } from '../../components/ui'
import { useTheme } from '../../lib/theme'
import { hojeBRT } from '../../lib/date'
import { DateNav } from '../../features/agenda/DateNav'
import { CardAulasDoDia } from '../../features/agenda/CardAulasDoDia'
import { SemanaStrip } from '../../features/agenda/SemanaStrip'
import { useAgenda } from '../../features/agenda/useAgenda'
import { useSemana } from '../../features/agenda/useSemana'
import { AppFrame } from './AppFrame'
import { AppNav } from './AppNav'

const TOAST_S3 = 'Registro por voz chega no Sprint 3 🎙️'

/** /app/agenda — semana compacta + dia selecionado (reusa app_minha_agenda). */
export default function AgendaPage() {
  const { toggle } = useTheme()
  const { message, visible, show } = useToast()
  const [data, setData] = useState<string>(hojeBRT())

  const { estado, recarregar } = useAgenda(data)
  const { dias, contagem } = useSemana(data)

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

      <div className="flex-1 overflow-y-auto pb-32">
        <SemanaStrip dias={dias} contagem={contagem} selecionado={data} onSelect={setData} />

        <div className="mx-4 mb-2 overflow-hidden rounded-lg border border-border-subtle bg-bg-surface">
          <DateNav value={data} onChange={setData} />
        </div>

        <div className="px-4">
          <CardAulasDoDia data={data} estado={estado} onRetry={recarregar} onRegistrar={() => show(TOAST_S3)} />
        </div>
      </div>

      <AppNav onFabMic={() => show(TOAST_S3)} onFabio={() => show('Chat com o Fábio chega no Sprint 4 🤖')} />
      <Toast message={message} visible={visible} />
    </AppFrame>
  )
}
