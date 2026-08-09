import { Toast, useToast } from '../../components/ui'
import { MesaFeedback } from '../../features/feedback'
import { AppFrame } from './AppFrame'
import { AppHeader } from './AppHeader'
import { AppNav } from './AppNav'

/**
 * /app/feedback — a mesa do mês: coração + as três perguntas de cada aluno.
 *
 * `AppFrame` não tem props de título/ícone (só `children`) — a moldura e o
 * cabeçalho seguem exatamente a composição de `Alunos.tsx`
 * (`AppHeader` + conteúdo rolável + `AppNav` + `Toast`). O padding horizontal
 * do conteúdo é `px-5` (não o `px-4` de Alunos.tsx) porque a barrinha
 * sticky de `MesaFeedback` usa `-mx-5`/`px-5` para sangrar até a borda da
 * moldura — os dois precisam bater.
 *
 * Um único `useToast()` aqui (padrão de `Devolutivas.tsx`): `show` desce por
 * prop pra `MesaFeedback`, que repassa pro `aoFalhar` de cada card — não um
 * `useToast()` por componente, que empilharia toasts na mesma posição fixa.
 */
export default function FeedbackPage() {
  const { message, visible, show } = useToast()

  return (
    <AppFrame>
      <AppHeader />

      <div className="flex-1 overflow-y-auto px-5 pb-[calc(96px_+_env(safe-area-inset-bottom))] pt-3">
        <h1 className="mb-3 text-[17px] font-bold text-text-primary">Feedback do mês</h1>
        <MesaFeedback show={show} />
      </div>

      <AppNav onMais={() => show('Mais ferramentas chegam em breve 🧰')} />
      <Toast message={message} visible={visible} />
    </AppFrame>
  )
}
