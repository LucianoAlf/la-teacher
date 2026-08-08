import { useState } from 'react'
import { Button } from '../../../components/ui'
import { coordenacaoRecado, type CoordenacaoLinha } from '../../../lib/api'

type Estado = 'parado' | 'enviando' | 'enviado' | 'ja_cobrado' | 'pausa' | 'erro'

/**
 * Cobrar um professor pelo WhatsApp do Fábio.
 *
 * O botão NUNCA diz "enviado" antes do banco confirmar: quem clica está olhando
 * a tela e vai embora achando que resolveu. Reservar não é enviar.
 *
 * E cada recusa tem texto PRÓPRIO. "Já cobrado hoje", "de férias" e "número
 * errado" são três situações com três desfechos diferentes — se virarem um "não
 * deu" genérico, a coordenação tenta de novo achando que foi conexão.
 *
 * Não existe estado "fora de horário": cobrança é categoria `governanca`, e a
 * `fn_fabio_pode_notificar` dá bypass estrutural nela — só férias barra.
 */
export function BotaoRecado({
  professor,
  aviso,
}: {
  professor: CoordenacaoLinha
  aviso: (m: string) => void
}) {
  const [estado, setEstado] = useState<Estado>('parado')

  async function mandar() {
    setEstado('enviando')
    try {
      const r = await coordenacaoRecado(professor.professor_id, textoDaCobranca(professor))

      if (!r.ok) {
        setEstado('erro')
        aviso(r.erro === 'apenas_admin' ? 'Só a coordenação manda recado.' : 'Não consegui agora.')
        return
      }
      if (r.enviado) {
        setEstado('enviado')
        aviso(`${primeiroNome(professor.professor_nome)} recebeu o recado no WhatsApp.`)
        return
      }
      if (r.motivo === 'ja_cobrado_hoje') {
        setEstado('ja_cobrado')
        aviso('O Fábio já cobrou esse professor hoje. Amanhã dá pra insistir.')
      } else if (r.motivo === 'professor_em_pausa') {
        setEstado('pausa')
        aviso('Esse professor está de férias no Fábio.')
      } else if (r.motivo === 'sem_whatsapp') {
        setEstado('erro')
        aviso('Esse professor não tem WhatsApp no cadastro.')
      } else {
        setEstado('erro')
        aviso('A mensagem não saiu no WhatsApp. Confere o número.')
      }
    } catch {
      setEstado('erro')
      aviso('Não consegui agora. Tenta de novo.')
    }
  }

  if (estado === 'enviado') return <Selo icone="fa-solid fa-check" tom="ok">enviado</Selo>
  if (estado === 'ja_cobrado') return <Selo icone="fa-regular fa-clock">já cobrado hoje</Selo>
  if (estado === 'pausa') return <Selo icone="fa-solid fa-umbrella-beach">de férias</Selo>

  return (
    <Button
      size="sm"
      variant="ghost"
      onClick={mandar}
      disabled={estado === 'enviando'}
      className="disabled:opacity-60"
      aria-label={`Mandar recado para ${professor.professor_nome}`}
    >
      <i
        className={estado === 'erro' ? 'fa-solid fa-rotate-right' : 'fa-brands fa-whatsapp'}
        aria-hidden
      />
      {estado === 'enviando' ? 'enviando…' : estado === 'erro' ? 'tentar de novo' : 'Cobrar'}
    </Button>
  )
}

/** Desfecho não é botão desabilitado: é informação, e fica legível. */
function Selo({
  icone,
  tom,
  children,
}: {
  icone: string
  tom?: 'ok'
  children: React.ReactNode
}) {
  return (
    <span
      className={`inline-flex items-center gap-1.5 whitespace-nowrap text-[12px] ${
        tom === 'ok' ? 'text-success-text' : 'text-text-muted'
      }`}
    >
      <i className={icone} aria-hidden />
      {children}
    </span>
  )
}

/**
 * O texto que chega no WhatsApp. Traz o NÚMERO e o pior atraso porque cobrança
 * sem tamanho vira aviso genérico — o professor precisa saber se são duas aulas
 * ou cinquenta antes de decidir quando sentar.
 *
 * E o número precisa ser o do TRABALHO DELE. Até a 070 isso dizia "50
 * lançamentos em aberto" pra quem tinha 21 aulas pra lançar: a fonte contava
 * pares aluno-aula, não aulas. Cobrança com tamanho inflado é pior do que
 * cobrança sem tamanho — é ela que decide quando o professor senta, e um número
 * que ele sabe que está errado ensina a ignorar o Fábio.
 */
function textoDaCobranca(p: CoordenacaoLinha) {
  const quantas = p.aulas === 1 ? '*1 aula sem lançamento*' : `*${p.aulas} aulas sem lançamento*`
  const desde =
    p.pior_atraso === 1 ? 'a mais antiga é de ontem' : `a mais antiga tem ${p.pior_atraso} dias`
  return (
    `Oi! Aqui é o Fábio 🎧\n\n` +
    `Ficaram ${quantas} na sua agenda (${desde}). Consegue dar uma olhada hoje?\n\n` +
    `É rapidinho pelo app: https://la-teacher.vercel.app`
  )
}

function primeiroNome(nome: string) {
  return nome.trim().split(' ')[0]
}
