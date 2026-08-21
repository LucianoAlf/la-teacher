import { useCallback } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { Toast, useToast } from '../../components/ui'
import { hojeBRT } from '../../lib/date'
import { diaDaUrl } from '../../features/agenda/diaSelecionado'
import type { SessaoAula } from '../../lib/api'
import { DateNav } from '../../features/agenda/DateNav'
import { CardSessoesDoDia } from '../../features/agenda/CardSessoesDoDia'
import { SemanaStrip } from '../../features/agenda/SemanaStrip'
import { useSessoes } from '../../features/agenda/useSessoes'
import { useSemana } from '../../features/agenda/useSemana'
import { destinoSessao, type AcaoSessao } from '../../features/agenda/sessao'
import { AppFrame } from './AppFrame'
import { AppHeader } from './AppHeader'
import { AppNav } from './AppNav'

/** /app/agenda — semana compacta + dia selecionado (app_minha_agenda_sessao). */
export default function AgendaPage() {
  const { message, visible, show } = useToast()
  const navigate = useNavigate()
  // O dia vive na URL, não em useState: assim o voltar do navegador devolve o
  // professor ao dia que ele estava vendo. Ver features/agenda/diaSelecionado.
  const [params, setParams] = useSearchParams()
  const data = diaDaUrl(params.get('dia'), hojeBRT())
  // `replace` de propósito: trocar de dia na tira da semana não empilha uma
  // entrada no histórico por toque — senão o voltar viraria "desfazer dia a
  // dia" em vez de sair da agenda.
  const setData = useCallback(
    (novo: string) => {
      setParams(novo === hojeBRT() ? {} : { dia: novo }, { replace: true })
    },
    [setParams],
  )

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
  /**
   * Abrir/gravar/preencher passam pela MESMA régua de rota — `destinoSessao`
   * em features/agenda/sessao. A régua mora LÁ, não aqui: Home e AlunoDetalhe
   * abrem as mesmas portas da mesma linha, e deixá-la local a esta tela foi o
   * que deixou o microfone da Home mandar a experimental pela porta do aluno em
   * 20/08 (`/app/gravar` → `aula_experimental_usa_porta_propria`).
   */
  const irPara = (sessao: SessaoAula, acao: AcaoSessao) => {
    const destino = destinoSessao(sessao, acao)
    if (destino.tipo === 'aviso') {
      show(destino.texto)
      return
    }
    navigate(destino.rota, { state: { sessao } })
  }
  const abrirSessao = (sessao: SessaoAula) => irPara(sessao, 'chamada')
  const gravarAula = (sessao: SessaoAula) => irPara(sessao, 'gravar')
  const preencherAula = (sessao: SessaoAula) => irPara(sessao, 'manual')

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
