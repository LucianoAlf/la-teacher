import { useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { AppFrame } from './AppFrame'
import { Button, EmptyState, ScreenHeader, Skeleton, Toast, useToast } from '../../components/ui'
import { useExperimental } from '../../features/experimental/useExperimental'
import { declararFaltaExperimental, type ResultadoFalta } from '../../lib/api'
import { dataBRTDoTimestamp, formatDiaCurto } from '../../lib/date'

/**
 * O aluno não veio.
 *
 * SEM CAMPOS DE PROPÓSITO. Aula que não aconteceu não tem capítulo pedagógico —
 * é por isso que a 035 recusa registro de vínculo em 'faltou'. Um formulário de
 * quatro campos aqui só teria uma serventia: fazer alguém inventar o que
 * escrever.
 *
 * Mas também não é um toque solto. Confirmar aqui manda WhatsApp pro consultor
 * comercial, e mensagem que sai pra outra pessoa não pode nascer de um toque
 * torto na lista. Então: um toque pra abrir esta tela, um pra confirmar — e a
 * tela diz, antes, exatamente o que vai acontecer.
 */
export default function ExperimentalFaltaPage() {
  const { vinculoId } = useParams<{ vinculoId: string }>()
  const navigate = useNavigate()
  const { estado } = useExperimental(vinculoId ? Number(vinculoId) : null)
  const { message, visible, show } = useToast()
  const [enviando, setEnviando] = useState(false)
  const [feito, setFeito] = useState<ResultadoFalta | null>(null)

  if (estado.fase === 'carregando') {
    return (
      <AppFrame>
        <ScreenHeader title="O aluno não veio" onBack={() => navigate(-1)} />
        <div className="px-4">
          <Skeleton className="h-32 w-full rounded-lg" />
        </div>
      </AppFrame>
    )
  }

  if (estado.fase === 'erro') {
    return (
      <AppFrame>
        <ScreenHeader title="O aluno não veio" onBack={() => navigate(-1)} />
        <EmptyState
          icon="fa-solid fa-circle-exclamation"
          title="Não deu pra abrir"
          description={estado.mensagem}
        />
      </AppFrame>
    )
  }

  const dados = estado.dados

  async function confirmar() {
    if (enviando) return
    setEnviando(true)
    try {
      setFeito(await declararFaltaExperimental(dados.vinculo_id))
    } catch (e: unknown) {
      const msg = String((e as { message?: string })?.message ?? e)
      show(
        msg.includes('ja_registrada_como_realizada')
          ? 'Essa aula já foi registrada como realizada. Se ela não aconteceu, fala com a coordenação.'
          : msg.includes('aula_de_outro_professor')
            ? 'Essa aula não é da sua agenda.'
            : msg.includes('gravacao_ainda_nao_disponivel')
              ? 'Ainda não deu o horário da aula.'
              : msg.includes('experimental_cancelada')
                ? 'Essa experimental foi cancelada.'
                : 'Não consegui registrar agora. Tenta de novo.',
      )
      setEnviando(false)
    }
  }

  if (feito) {
    return (
      <AppFrame>
        <ScreenHeader title="Falta registrada" onBack={() => navigate('/app/agenda')} />
        <div className="flex-1 space-y-3 px-4">
          <EmptyState
            icon="fa-solid fa-circle-check"
            title="Pronto, falta registrada"
            description={
              feito.aviso_motivo === 'sem_destinatario'
                ? 'A presença está marcada. O aviso pro comercial ficou na fila: esta unidade ainda não tem consultor cadastrado, e ele sai sozinho assim que alguém cadastrar.'
                : 'A presença está marcada e o consultor comercial já foi avisado — ele consegue falar com a família enquanto está fresco.'
            }
            action={
              <Button size="sm" variant="ghost" onClick={() => navigate('/app/agenda')}>
                Voltar pra agenda
              </Button>
            }
          />
        </div>
      </AppFrame>
    )
  }

  return (
    <AppFrame>
      <ScreenHeader
        title="O aluno não veio"
        subtitle={`${dados.nome_aluno} · ${formatDiaCurto(dataBRTDoTimestamp(dados.data_hora_inicio))} · ${dados.hora}`}
        onBack={() => navigate(-1)}
      />

      <div className="flex-1 space-y-4 px-4 pb-[calc(24px_+_env(safe-area-inset-bottom))]">
        <div className="flex flex-col items-center gap-3 rounded-lg border border-border-subtle bg-bg-surface px-4 py-6 text-center">
          <div className="flex h-14 w-14 items-center justify-center rounded-full bg-warning-soft text-2xl text-warning-text">
            <i className="fa-solid fa-user-slash" aria-hidden="true" />
          </div>
          <b className="text-[16px]">{dados.nome_aluno} não apareceu?</b>
          <p className="max-w-[300px] text-[13px] leading-relaxed text-text-secondary">
            Nada de formulário: aula que não aconteceu não tem o que contar.
          </p>
        </div>

        {/* Dizer ANTES o que o toque faz. O professor não descobre depois que
            saiu mensagem no WhatsApp de outra pessoa. */}
        <div className="rounded-md border border-border-subtle bg-bg-inset px-3 py-3">
          <span className="mb-2 block text-[11.5px] font-bold uppercase tracking-[.5px] text-text-secondary">
            O que acontece quando você confirmar
          </span>
          <ul className="space-y-[7px] text-[13px] leading-relaxed text-text-primary">
            <li className="flex gap-2">
              <i className="fa-solid fa-user-check mt-[3px] text-xs text-brand-text" aria-hidden="true" />
              A falta fica marcada por você — e você não é cobrado por esta aula.
            </li>
            <li className="flex gap-2">
              <i className="fa-brands fa-whatsapp mt-[3px] text-xs text-brand-text" aria-hidden="true" />
              O consultor comercial recebe um aviso curto pra tentar remarcar.
            </li>
            <li className="flex gap-2">
              <i className="fa-solid fa-lock mt-[3px] text-xs text-text-muted" aria-hidden="true" />
              A família não recebe nada.
            </li>
          </ul>
        </div>

        <div className="space-y-2">
          <Button onClick={() => void confirmar()} disabled={enviando}>
            {enviando ? 'Registrando…' : 'Confirmar — o aluno não veio'}
          </Button>
          <Button variant="ghost" block onClick={() => navigate(-1)}>
            Voltar
          </Button>
        </div>
      </div>

      <Toast message={message} visible={visible} />
    </AppFrame>
  )
}
