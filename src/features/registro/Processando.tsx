import { useEffect, useState } from 'react'
import { useLocation, useNavigate, useParams } from 'react-router-dom'
import { Button, ScreenHeader } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { cx } from '../../lib/cx'
import { AppFrame } from '../../pages/app/AppFrame'

type StatusFila = 'pendente' | 'transcrevendo' | 'transcrito' | 'normalizado' | 'erro'

const PASSOS: Array<{ chave: string; rotulo: string; feitoQuando: StatusFila[] }> = [
  { chave: 'fila', rotulo: 'Na fila do Fábio', feitoQuando: ['transcrevendo', 'transcrito', 'normalizado'] },
  { chave: 'stt', rotulo: 'Transcrevendo seu áudio', feitoQuando: ['transcrito', 'normalizado'] },
  { chave: 'molde', rotulo: 'Separando por aluno — tronco + fatias', feitoQuando: ['normalizado'] },
]

/**
 * /app/processando/:audioId — o app já entregou o áudio; daqui em diante o
 * trabalho é do Fábio (Hermes, fora do app). Esta tela só OBSERVA a fila via
 * Realtime — nada de simulação de progresso.
 */
export default function ProcessandoPage() {
  const { audioId } = useParams()
  const navigate = useNavigate()
  const { state } = useLocation() as { state?: { aulaLabel?: string } }
  const [status, setStatus] = useState<StatusFila>('pendente')
  const [demorando, setDemorando] = useState(false)

  // Realtime: status do áudio na fila + surgimento do registro estruturado
  useEffect(() => {
    if (!audioId) return
    const canal = supabase
      .channel(`fabio-audio-${audioId}`)
      .on(
        'postgres_changes',
        { event: 'UPDATE', schema: 'public', table: 'fabio_fila_audios', filter: `id=eq.${audioId}` },
        (payload) => {
          const novo = (payload.new as { status?: StatusFila }).status
          if (novo) setStatus(novo)
        },
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'fabio_registros_aula', filter: `audio_id=eq.${audioId}` },
        (payload) => {
          const reg = payload.new as { id?: string; parent_id?: string | null; status?: string }
          if (reg.id && reg.parent_id == null && reg.status === 'aguardando_confirmacao') {
            navigate(`/app/confirmar/${reg.id}`, { replace: true })
          }
        },
      )
      .subscribe()
    return () => {
      void supabase.removeChannel(canal)
    }
  }, [audioId, navigate])

  // Honestidade: motor ainda em configuração → avisar se ficar parado na fila
  useEffect(() => {
    if (status !== 'pendente') {
      setDemorando(false)
      return
    }
    const t = window.setTimeout(() => setDemorando(true), 30_000)
    return () => window.clearTimeout(t)
  }, [status])

  return (
    <AppFrame>
      <ScreenHeader title="Áudio enviado ✓" subtitle={state?.aulaLabel} onBack={() => navigate('/app')} />

      <div className="flex flex-1 flex-col items-center justify-center gap-6 px-6 text-center">
        <div className="flex h-[84px] w-[84px] animate-bob items-center justify-center rounded-full border border-[color:var(--brand-border)] bg-brand-soft text-3xl text-brand-text">
          <i className="fa-solid fa-robot" aria-hidden="true" />
        </div>

        <div>
          <b className="block text-lg">O Fábio está ouvindo sua aula… 🎼</b>
          <p className="mt-1 text-[13px] text-text-secondary">Pode sair — sua gravação está guardada e nada se perde.</p>
        </div>

        {status === 'erro' ? (
          <div className="flex max-w-[300px] flex-col items-center gap-2 rounded-md border border-border-subtle bg-danger-soft px-4 py-3 text-[13px] font-semibold text-danger-text">
            <span>
              <i className="fa-solid fa-triangle-exclamation" aria-hidden="true" /> Deu um tropeço no processamento.
            </span>
            <span className="font-normal text-text-secondary">
              O sistema tenta de novo sozinho em alguns minutos — não precisa reenviar.
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

        {demorando && status === 'pendente' && (
          <p className="max-w-[300px] text-[12px] leading-relaxed text-text-muted">
            <i className="fa-solid fa-circle-info" aria-hidden="true" /> Aguardando o Fábio — o motor de
            processamento ainda está em configuração. Seu áudio está seguro na fila e será processado
            assim que ele ligar.
          </p>
        )}

        <Button variant="ghost" onClick={() => navigate('/app')}>
          <i className="fa-solid fa-house" aria-hidden="true" /> Voltar ao início
        </Button>
      </div>
    </AppFrame>
  )
}
