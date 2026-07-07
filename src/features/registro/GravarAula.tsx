import { useMemo, useState } from 'react'
import { useLocation, useNavigate, useParams } from 'react-router-dom'
import { Button, Card, EmptyState, ScreenHeader, Skeleton } from '../../components/ui'
import type { AgendaAula } from '../../lib/api'
import { hojeBRT } from '../../lib/date'
import { detalheAula, horaAula, nomeAula, temRegistro } from '../agenda/aula'
import { AgendaAulaRow } from '../agenda/AgendaAulaRow'
import { useAgenda } from '../agenda/useAgenda'
import { AppFrame } from '../../pages/app/AppFrame'
import { enviarAudio } from './uploadAudio'
import { useRecorder, LIMITE_SEGUNDOS } from './useRecorder'

function fmt(seg: number): string {
  const m = Math.floor(seg / 60)
  return `${m}:${String(seg % 60).padStart(2, '0')}`
}

/** /app/gravar[/:aulaId] — grava o áudio da aula (turma = UM áudio só). */
export default function GravarAulaPage() {
  const { aulaId } = useParams()
  if (!aulaId) return <EscolherAula />
  return <Gravador aulaId={Number(aulaId)} />
}

// ---------------------------------------------------------------------------
// Modo seletor (entrada pelo FAB, sem aula definida)
// ---------------------------------------------------------------------------

function EscolherAula() {
  const navigate = useNavigate()
  const { estado } = useAgenda(hojeBRT())
  const aulas = estado.fase === 'ok' ? estado.agenda.aulas.filter((a) => !temRegistro(a)) : []

  return (
    <AppFrame>
      <ScreenHeader title="Registrar qual aula?" subtitle="Aulas de hoje sem registro" onBack={() => navigate(-1)} />
      <div className="flex-1 overflow-y-auto px-4 pb-8 pt-1">
        {estado.fase === 'carregando' && (
          <div className="space-y-3 py-2">
            {[0, 1, 2].map((i) => (
              <Skeleton key={i} className="h-12 w-full" />
            ))}
          </div>
        )}
        {estado.fase === 'ok' && aulas.length === 0 && (
          <EmptyState
            icon="fa-solid fa-music"
            title="Nada pra registrar hoje 🎵"
            description="Nenhuma aula de hoje está sem registro. Quer gravar uma aula de outro dia? Acha ela na agenda."
            action={
              <Button size="sm" variant="ghost" onClick={() => navigate('/app/agenda')}>
                <i className="fa-solid fa-calendar" aria-hidden="true" /> Abrir agenda
              </Button>
            }
          />
        )}
        {estado.fase === 'ok' && aulas.length > 0 && (
          <Card title="Hoje" icon="fa-solid fa-calendar-day">
            {aulas.map((a) => (
              <AgendaAulaRow
                key={a.aula_local_id}
                aula={a}
                onGravar={(aula) => navigate(`/app/gravar/${aula.aula_local_id}`, { state: { aula } })}
              />
            ))}
          </Card>
        )}
        {estado.fase === 'erro' && (
          <EmptyState
            icon="fa-solid fa-triangle-exclamation"
            title="Não consegui carregar"
            description="Verifica a conexão e tenta de novo pela Home ou Agenda."
          />
        )}
      </div>
    </AppFrame>
  )
}

// ---------------------------------------------------------------------------
// Gravador
// ---------------------------------------------------------------------------

type FaseEnvio = 'nao_enviado' | 'enviando' | 'fila_offline' | 'erro_envio'

function Gravador({ aulaId }: { aulaId: number }) {
  const navigate = useNavigate()
  const { state } = useLocation() as { state?: { aula?: AgendaAula } }
  const aula = state?.aula
  const rec = useRecorder()
  const [envio, setEnvio] = useState<FaseEnvio>('nao_enviado')

  const titulo = aula ? nomeAula(aula) : `Aula #${aulaId}`
  const sub = aula ? [detalheAula(aula), horaAula(aula)].filter(Boolean).join(' · ') : undefined
  const previewUrl = useMemo(() => (rec.blob ? URL.createObjectURL(rec.blob) : null), [rec.blob])

  async function enviar() {
    if (!rec.blob) return
    setEnvio('enviando')
    const r = await enviarAudio({
      aulaId,
      aulaLabel: titulo,
      blob: rec.blob,
      mime: rec.mime || rec.blob.type,
      duracaoSegundos: rec.segundos,
    })
    if (r.ok) {
      navigate(`/app/processando/${r.audioId}`, { state: { aulaLabel: titulo } })
    } else {
      setEnvio(r.guardadoOffline ? 'fila_offline' : 'erro_envio')
    }
  }

  return (
    <AppFrame>
      <ScreenHeader title="Registrar aula" onBack={() => navigate(-1)} />

      {/* contexto da aula (protótipo .ctx-card) */}
      <div className="mx-4 flex items-center gap-[11px] rounded-lg border border-[color:var(--brand-border)] bg-bg-surface px-[14px] py-[13px]">
        <div className="flex h-[38px] w-[38px] flex-none items-center justify-center rounded-md bg-brand-soft text-base text-brand-text">
          <i className={aula?.aula_tipo === 'individual' ? 'fa-solid fa-user' : 'fa-solid fa-users'} aria-hidden="true" />
        </div>
        <div className="min-w-0">
          <b className="block truncate text-[14.5px]">{titulo}</b>
          {sub && <span className="block truncate text-xs text-text-secondary">{sub}</span>}
        </div>
      </div>

      <div className="flex flex-1 flex-col items-center justify-center gap-6 px-5 text-center">
        {rec.estado === 'erro' && (
          <EmptyState
            icon="fa-solid fa-microphone-slash"
            title="Sem acesso ao microfone"
            description={rec.erro ?? 'Libera o microfone nas permissões do navegador e tenta de novo.'}
            action={
              <Button size="sm" onClick={() => void rec.start()}>
                <i className="fa-solid fa-rotate-right" aria-hidden="true" /> Tentar de novo
              </Button>
            }
          />
        )}

        {rec.estado === 'idle' && envio === 'nao_enviado' && (
          <>
            <p className="max-w-[280px] text-[13px] leading-relaxed text-text-secondary">
              Fala pra mim como foi a aula 🎧 — pode ser natural, do seu jeito. Eu organizo.
            </p>
            <button
              type="button"
              aria-label="Começar a gravar"
              onClick={() => void rec.start()}
              className="flex h-[88px] w-[88px] items-center justify-center rounded-full bg-brand text-3xl text-on-brand shadow-fab transition-transform active:scale-[.93]"
            >
              <i className="fa-solid fa-microphone" aria-hidden="true" />
            </button>
            <span className="text-[11px] font-semibold uppercase tracking-[.5px] text-text-muted">
              toque pra começar · máx. {Math.floor(LIMITE_SEGUNDOS / 60)} min
            </span>
          </>
        )}

        {rec.estado === 'pedindo_permissao' && (
          <p className="text-[13px] text-text-secondary">
            <i className="fa-solid fa-microphone" aria-hidden="true" /> Pedindo acesso ao microfone…
          </p>
        )}

        {rec.estado === 'gravando' && (
          <>
            <div
              className="flex h-16 items-center gap-1"
              style={{ opacity: 0.55 + rec.nivel * 0.45 }}
              aria-hidden="true"
            >
              {Array.from({ length: 18 }, (_, i) => (
                <i
                  key={i}
                  className="block h-3 w-[5px] animate-wave rounded-[3px] bg-brand"
                  style={{ animationDelay: `${(i % 5) * 0.15}s` }}
                />
              ))}
            </div>
            <div className="font-mono text-[38px] font-semibold tracking-[1px]" role="timer">
              {fmt(rec.segundos)}
            </div>
            <p className="max-w-[280px] text-[13px] leading-relaxed text-text-secondary">
              Como cada um foi, o que trabalharam, e o dever de casa. O Fábio separa por aluno. 🎙️
            </p>
            <button
              type="button"
              aria-label="Parar gravação"
              onClick={rec.stop}
              className="flex h-[74px] w-[74px] items-center justify-center rounded-full bg-danger text-2xl text-[color:var(--on-danger)] shadow-fab transition-transform active:scale-[.93]"
            >
              <i className="fa-solid fa-stop" aria-hidden="true" />
            </button>
          </>
        )}

        {rec.estado === 'parado' && envio === 'nao_enviado' && (
          <>
            <div className="flex h-14 w-14 items-center justify-center rounded-full bg-brand-soft text-xl text-brand-text">
              <i className="fa-solid fa-headphones" aria-hidden="true" />
            </div>
            <div>
              <b className="block text-[17px]">Gravado — {fmt(rec.segundos)}</b>
              <span className="text-[12.5px] text-text-secondary">Confere se ficou bom antes de mandar 👇</span>
            </div>
            {previewUrl && <audio controls src={previewUrl} className="w-full max-w-[300px]" />}
            <div className="flex w-full max-w-[300px] flex-col gap-2">
              <Button block onClick={() => void enviar()}>
                <i className="fa-solid fa-paper-plane" aria-hidden="true" /> Enviar pro Fábio
              </Button>
              <Button block variant="ghost" onClick={rec.reset}>
                <i className="fa-solid fa-rotate-left" aria-hidden="true" /> Re-gravar
              </Button>
            </div>
          </>
        )}

        {envio === 'enviando' && (
          <p className="text-[13px] text-text-secondary">
            <i className="fa-solid fa-cloud-arrow-up fa-bounce" aria-hidden="true" /> Subindo seu áudio…
          </p>
        )}

        {envio === 'fila_offline' && (
          <EmptyState
            icon="fa-solid fa-cloud-arrow-up"
            title="Guardei sua gravação 💾"
            description="Sem conexão agora. O áudio está na fila local e sobe sozinho assim que a internet voltar — pode seguir o dia."
            action={
              <Button size="sm" variant="ghost" onClick={() => navigate('/app')}>
                Voltar ao início
              </Button>
            }
          />
        )}

        {envio === 'erro_envio' && (
          <EmptyState
            icon="fa-solid fa-triangle-exclamation"
            title="Não consegui enviar"
            description="Deu um problema no envio e não consegui nem guardar localmente. Sua gravação ainda está aqui — tenta de novo."
            action={
              <Button size="sm" onClick={() => void enviar()}>
                <i className="fa-solid fa-rotate-right" aria-hidden="true" /> Tentar de novo
              </Button>
            }
          />
        )}
      </div>
    </AppFrame>
  )
}
