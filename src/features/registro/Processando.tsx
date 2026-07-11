import { useEffect, useRef, useState } from 'react'
import { useLocation, useNavigate, useParams } from 'react-router-dom'
import { Button, ScreenHeader } from '../../components/ui'
import { registrosPendentes, statusAudioFila, type StatusFila } from '../../lib/api'
import { cx } from '../../lib/cx'
import { AppFrame } from '../../pages/app/AppFrame'

const INTERVALO_MS = 3_000
const AVISO_DEMORA_MS = 90_000

// Passos visuais mapeados nos valores REAIS de fabio_fila_audios.status
// (constraint: pendente → transcrevendo → transcrito → normalizado → erro).
const PASSOS: Array<{ chave: string; rotulo: string; feitoQuando: StatusFila[] }> = [
  { chave: 'fila', rotulo: 'Na fila do Fábio', feitoQuando: ['transcrevendo', 'transcrito', 'normalizado'] },
  { chave: 'stt', rotulo: 'Transcrevendo seu áudio', feitoQuando: ['transcrito', 'normalizado'] },
  { chave: 'molde', rotulo: 'Organizando por aluno — tronco + fatias', feitoQuando: ['normalizado'] },
]

/**
 * /app/processando/:audioId — o app entregou o áudio; o Fábio (Hermes, fora do
 * app) transcreve e monta o relatório. Esta tela ACOMPANHA o status real:
 *  · app_status_audio_fila(audioId) → move as 3 etapas e detecta erro;
 *  · app_registros_pendentes (casa pelo audio_id) → quando o relatório fica
 *    pronto, leva direto pra tela de revisão/confirmação.
 * Ambas guardadas; nada de simular progresso.
 */
export default function ProcessandoPage() {
  const { audioId } = useParams()
  const navigate = useNavigate()
  const { state } = useLocation() as { state?: { aulaLabel?: string } }
  const [status, setStatus] = useState<StatusFila>('pendente')
  const [erro, setErro] = useState(false)
  const [demorando, setDemorando] = useState(false)
  const jaNavegou = useRef(false)

  useEffect(() => {
    if (!audioId) return
    let parar = false
    let timer: number | undefined

    const checar = async () => {
      if (parar || jaNavegou.current) return
      // relatório pronto? (sinal autoritativo — traz o id pra navegar)
      const [st, pend] = await Promise.all([
        statusAudioFila(audioId).catch(() => null),
        registrosPendentes().catch(() => []),
      ])
      const meu = pend.find((r) => r.audio_id === audioId && r.parent_id == null)
      if (meu && !jaNavegou.current) {
        jaNavegou.current = true
        navigate(`/app/confirmar/${meu.id}`, { replace: true })
        return
      }
      if (st) {
        setStatus(st.status)
        if (st.tem_erro || st.status === 'erro') {
          setErro(true)
          parar = true
          return
        }
      }
      if (!parar && !jaNavegou.current) timer = window.setTimeout(checar, INTERVALO_MS)
    }

    void checar()
    return () => {
      parar = true
      if (timer) window.clearTimeout(timer)
    }
  }, [audioId, navigate])

  // Se ficar parado na fila além do normal, tranquiliza (mas segue observando).
  useEffect(() => {
    if (status !== 'pendente' || erro) {
      setDemorando(false)
      return
    }
    const t = window.setTimeout(() => setDemorando(true), AVISO_DEMORA_MS)
    return () => window.clearTimeout(t)
  }, [status, erro])

  return (
    <AppFrame>
      <ScreenHeader title="Áudio enviado ✓" subtitle={state?.aulaLabel} onBack={() => navigate('/app')} />

      <div className="flex flex-1 flex-col items-center justify-center gap-6 px-6 text-center">
        <div className="flex h-[84px] w-[84px] animate-bob items-center justify-center rounded-full border border-[color:var(--brand-border)] bg-brand-soft text-3xl text-brand-text">
          <i className="fa-solid fa-robot" aria-hidden="true" />
        </div>

        <div>
          <b className="block text-lg">O Fábio está montando seu relatório… 🎼</b>
          <p className="mt-1 text-[13px] text-text-secondary">
            Pode sair — sua gravação está guardada e nada se perde.
          </p>
        </div>

        {erro ? (
          <div className="flex max-w-[300px] flex-col items-center gap-2 rounded-md border border-border-subtle bg-danger-soft px-4 py-3 text-[13px] font-semibold text-danger-text">
            <span>
              <i className="fa-solid fa-triangle-exclamation" aria-hidden="true" /> Deu um tropeço no processamento.
            </span>
            <span className="font-normal text-text-secondary">
              O sistema tenta de novo sozinho em alguns minutos — não precisa reenviar. Se persistir, fala com a
              coordenação.
            </span>
          </div>
        ) : (
          <div className="flex w-full max-w-[300px] flex-col gap-[13px] text-left">
            {PASSOS.map((p, i) => {
              const feito = p.feitoQuando.includes(status)
              const fazendo = !feito && (i === 0 ? status === 'pendente' : PASSOS[i - 1].feitoQuando.includes(status))
              return (
                <div
                  key={p.chave}
                  className={cx(
                    'flex items-center gap-[11px] text-sm',
                    feito ? 'text-text-secondary' : fazendo ? 'text-text-primary' : 'text-text-muted',
                  )}
                >
                  <span
                    className={cx(
                      'flex h-[26px] w-[26px] flex-none items-center justify-center rounded-full border-2 text-[11px]',
                      feito
                        ? 'border-success bg-success-soft text-success-text'
                        : fazendo
                          ? 'border-brand text-brand-text'
                          : 'border-border-strong text-transparent',
                    )}
                  >
                    <i className={feito ? 'fa-solid fa-check' : 'fa-solid fa-spinner fa-spin'} aria-hidden="true" />
                  </span>
                  {p.rotulo}
                </div>
              )
            })}
          </div>
        )}

        {demorando && !erro && (
          <p className="max-w-[300px] text-[12px] leading-relaxed text-text-muted">
            <i className="fa-solid fa-circle-info" aria-hidden="true" /> Está levando um pouco mais que o normal — seu
            áudio está seguro. Pode voltar à Home: assim que ficar pronto, o relatório aparece em
            <b> aguardando confirmação</b> pra você revisar.
          </p>
        )}

        <Button variant="ghost" onClick={() => navigate('/app')}>
          <i className="fa-solid fa-house" aria-hidden="true" /> Voltar ao início
        </Button>
      </div>
    </AppFrame>
  )
}
