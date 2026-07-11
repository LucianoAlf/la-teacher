import { useEffect, useRef, useState } from 'react'
import { useLocation, useNavigate, useParams } from 'react-router-dom'
import { Button, ScreenHeader } from '../../components/ui'
import { registrosPendentes } from '../../lib/api'
import { AppFrame } from '../../pages/app/AppFrame'

const INTERVALO_MS = 3_000
const AVISO_DEMORA_MS = 90_000

/**
 * /app/processando/:audioId — o app entregou o áudio; o Fábio (Hermes, fora do
 * app) transcreve e monta o relatório. Esta tela ACOMPANHA o progresso real por
 * polling de app_registros_pendentes (RPC guardada) casando pelo audio_id — e,
 * quando o relatório fica pronto (status aguardando_confirmacao), leva direto
 * pra tela de revisão/confirmação. Sem simular passos que não pode observar.
 *
 * Nota (reportado ao Claude Web): pra mostrar as sub-etapas reais da fila
 * (transcrevendo/normalizando) e um estado de ERRO explícito, falta uma RPC
 * guardada de leitura do status em fabio_fila_audios. Sem ela, o app só observa
 * "recebido" e "relatório pronto"; o resto é coberto por um aviso de tempo.
 */
export default function ProcessandoPage() {
  const { audioId } = useParams()
  const navigate = useNavigate()
  const { state } = useLocation() as { state?: { aulaLabel?: string } }
  const [demorando, setDemorando] = useState(false)
  const jaNavegou = useRef(false)

  // Polling do relatório pronto (casa pelo audio_id desta gravação).
  useEffect(() => {
    if (!audioId) return
    let vivo = true
    let timer: number | undefined

    const checar = async () => {
      try {
        const pendentes = await registrosPendentes()
        const meu = pendentes.find((r) => r.audio_id === audioId && r.parent_id == null)
        if (meu && vivo && !jaNavegou.current) {
          jaNavegou.current = true
          navigate(`/app/confirmar/${meu.id}`, { replace: true })
          return
        }
      } catch {
        // rede instável: ignora e tenta de novo no próximo ciclo
      }
      if (vivo && !jaNavegou.current) timer = window.setTimeout(checar, INTERVALO_MS)
    }

    void checar()
    return () => {
      vivo = false
      if (timer) window.clearTimeout(timer)
    }
  }, [audioId, navigate])

  // Se demorar mais que o normal, tranquiliza (mas segue observando).
  useEffect(() => {
    const t = window.setTimeout(() => setDemorando(true), AVISO_DEMORA_MS)
    return () => window.clearTimeout(t)
  }, [])

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
            Pode sair — sua gravação está guardada e nada se perde. Levo cerca de 1 minuto.
          </p>
        </div>

        <div className="flex items-center gap-[10px] text-sm text-text-primary">
          <span className="flex h-[26px] w-[26px] flex-none items-center justify-center rounded-full border-2 border-brand text-[11px] text-brand-text">
            <i className="fa-solid fa-spinner fa-spin" aria-hidden="true" />
          </span>
          Transcrevendo e organizando por aluno
        </div>

        {demorando && (
          <p className="max-w-[300px] text-[12px] leading-relaxed text-text-muted">
            <i className="fa-solid fa-circle-info" aria-hidden="true" /> Está levando um pouco mais que o normal —
            seu áudio está seguro. Pode voltar à Home: assim que ficar pronto, o relatório aparece em
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
