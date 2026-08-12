import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Toast, useToast } from '../../components/ui'
import { hojeBRT } from '../../lib/date'
import type { SessaoAula } from '../../lib/api'
import { DateNav } from '../../features/agenda/DateNav'
import { CardSessoesDoDia } from '../../features/agenda/CardSessoesDoDia'
import { SemanaStrip } from '../../features/agenda/SemanaStrip'
import { useSessoes } from '../../features/agenda/useSessoes'
import { useSemana } from '../../features/agenda/useSemana'
import { AppFrame } from './AppFrame'
import { AppHeader } from './AppHeader'
import { AppNav } from './AppNav'

/** /app/agenda — semana compacta + dia selecionado (app_minha_agenda_sessao). */
export default function AgendaPage() {
  const { message, visible, show } = useToast()
  const navigate = useNavigate()
  const [data, setData] = useState<string>(hojeBRT())

  const { estado, recarregar } = useSessoes(data)
  const { dias, contagem } = useSemana(data)
  /**
   * Tocar numa linha abre o que aquela aula PEDE.
   *
   * Experimental não tem chamada: o roster é um lead, não um aluno conciliado,
   * e a presença nasce da confirmação do registro (038) — não de marcar
   * presente numa lista. Levar o professor pra chamada aqui seria oferecer uma
   * porta que o banco recusa.
   *
   * Sem vínculo, nem a ficha abre: o reconciliador ainda não casou o lead com
   * esta aula. Dizer isso é melhor que uma tela de erro — mas sem prometer
   * prazo. Medido em 08/08/2026: das 23 experimentais da semana, 12 estavam
   * sem vínculo, e algumas a 2 dias da aula. "Tenta em alguns minutos" manda o
   * professor voltar num lugar que pode não abrir hoje. O que ele precisa
   * saber é o que AINDA dá pra fazer.
   */
  const abrirSessao = (sessao: SessaoAula) => {
    if (sessao.experimental) {
      if (sessao.vinculo_id == null) {
        // Sem promessa de prazo NEM de aviso: hoje nada notifica quando o
        // vínculo aparece. Diz o que é, o que segue funcionando, e a quem
        // recorrer se o dia da aula chegar assim.
        show('Essa experimental ainda não casou com a agenda, então o registro dela não abre. A aula acontece normal — se chegar o dia assim, fala com a coordenação.')
        return
      }
      navigate(`/app/experimental/${sessao.vinculo_id}`)
      return
    }
    navigate(`/app/chamada/${sessao.aula_id_ancora}`, { state: { sessao } })
  }
  const gravarAula = (sessao: SessaoAula) =>
    navigate(`/app/gravar/${sessao.aula_id_ancora}`, { state: { sessao } })
  const preencherAula = (sessao: SessaoAula) =>
    navigate(`/app/registro-manual/${sessao.aula_id_ancora}`, { state: { sessao } })

  return (
    <AppFrame>
      <AppHeader />

      <div className="flex-1 overflow-y-auto pb-[calc(96px_+_env(safe-area-inset-bottom))]">
        <SemanaStrip dias={dias} contagem={contagem} selecionado={data} onSelect={setData} />

        <div className="mx-4 mb-2 overflow-hidden rounded-lg border border-border-subtle bg-bg-surface">
          <DateNav value={data} onChange={setData} />
        </div>

        <div className="px-4">
          <CardSessoesDoDia
            data={data}
            estado={estado}
            onRetry={recarregar}
            onAbrir={abrirSessao}
            onGravar={gravarAula}
            onManual={preencherAula}
          />
        </div>
      </div>

      <AppNav onMais={() => show('Mais ferramentas chegam em breve 🧰')} />
      <Toast message={message} visible={visible} />
    </AppFrame>
  )
}
