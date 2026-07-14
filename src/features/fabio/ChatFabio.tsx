import { useEffect, useRef, useState, type FormEvent } from 'react'
import { useNavigate } from 'react-router-dom'
import { Button, EmptyState, FabioAvatar, FabioMark, ScreenHeader, Skeleton, Toast, useToast } from '../../components/ui'
import { cx } from '../../lib/cx'
import { meuPerfil } from '../../lib/api'
import { SOMENTE_LEITURA } from '../../lib/config'
import { AppFrame } from '../../pages/app/AppFrame'
import { assinarMensagens, carregarMensagens, enviarMensagem, type ChatMensagem } from './chat'

type Estado = 'carregando' | 'erro' | 'ok'

/**
 * O Fábio processa (e às vezes consulta o banco) antes de responder — a
 * latência normal é ~15-30s. O "digitando" cobre essa espera; se passar de
 * 2 min sem resposta, some (deu ruim no backend — não fica mentindo pra sempre).
 */
const JANELA_DIGITANDO_MS = 2 * 60 * 1000

function horaMensagem(iso: string): string {
  return new Date(iso).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })
}

function rotuloDia(iso: string): string {
  const d = new Date(iso)
  if (d.toDateString() === new Date().toDateString()) return 'Hoje'
  return d.toLocaleDateString('pt-BR', { weekday: 'short', day: '2-digit', month: 'short' })
}

/**
 * /app/fabio — chat com o Fábio (dual-channel: a MESMA conversa do WhatsApp).
 * Leitura + Realtime na tabela fabio_chat_mensagens (ver ./chat.ts); envio é
 * insert direto guardado por RLS. Aberta pela bolota central da AppNav.
 */
export default function ChatFabioPage() {
  const navigate = useNavigate()
  const { message, visible, show } = useToast()
  const [estado, setEstado] = useState<Estado>('carregando')
  const [mensagens, setMensagens] = useState<ChatMensagem[]>([])
  const [professorId, setProfessorId] = useState<number | null>(null)
  const [texto, setTexto] = useState('')
  const [enviando, setEnviando] = useState(false)
  const [agora, setAgora] = useState(() => Date.now())
  const fimRef = useRef<HTMLDivElement>(null)
  const jaRolou = useRef(false)

  // Bootstrap: perfil (professor_id) → assina o Realtime ANTES do select
  // (nada se perde na janela entre carregar e assinar) → carrega o histórico
  // e mescla com o que o Realtime já tiver entregado.
  useEffect(() => {
    let vivo = true
    let cancelar: (() => void) | undefined
    meuPerfil()
      .then((perfil) => {
        if (!vivo) return
        if (!perfil) {
          setEstado('erro')
          return
        }
        setProfessorId(perfil.professor_id)
        cancelar = assinarMensagens(perfil.professor_id, (m) => {
          setMensagens((atual) => (atual.some((x) => x.id === m.id) ? atual : [...atual, m]))
        })
        return carregarMensagens(perfil.professor_id).then((historico) => {
          if (!vivo) return
          setMensagens((atual) => {
            const ids = new Set(historico.map((m) => m.id))
            return [...historico, ...atual.filter((m) => !ids.has(m.id))]
          })
          setEstado('ok')
        })
      })
      .catch(() => vivo && setEstado('erro'))
    return () => {
      vivo = false
      cancelar?.()
    }
  }, [])

  // "Fábio está digitando…" — a última mensagem é do professor e ainda está
  // dentro da janela de resposta. O tick de 5s só roda enquanto isso importa.
  const ultima = mensagens[mensagens.length - 1]
  const digitando =
    estado === 'ok' &&
    !!ultima &&
    ultima.role === 'professor' &&
    agora - new Date(ultima.criado_em).getTime() < JANELA_DIGITANDO_MS

  useEffect(() => {
    if (!ultima || ultima.role !== 'professor') return
    const id = window.setInterval(() => setAgora(Date.now()), 5000)
    return () => window.clearInterval(id)
  }, [ultima])

  // Cola no fim da conversa: salto seco na primeira pintura, suave nas novas.
  useEffect(() => {
    if (estado !== 'ok') return
    fimRef.current?.scrollIntoView({ behavior: jaRolou.current ? 'smooth' : 'auto', block: 'end' })
    jaRolou.current = true
  }, [estado, mensagens.length, digitando])

  const enviar = async (e: FormEvent) => {
    e.preventDefault()
    const t = texto.trim()
    if (!t || enviando || professorId == null) return
    if (SOMENTE_LEITURA) {
      show('Modo demonstração — envio desligado 🔒')
      return
    }
    setEnviando(true)
    try {
      const m = await enviarMensagem(professorId, t)
      setMensagens((atual) => (atual.some((x) => x.id === m.id) ? atual : [...atual, m]))
      setTexto('')
      setAgora(Date.now())
    } catch {
      show('Não consegui enviar — verifica a conexão e tenta de novo')
    } finally {
      setEnviando(false)
    }
  }

  return (
    <AppFrame>
      <ScreenHeader
        title="Fábio"
        subtitle="seu assistente · também no WhatsApp"
        onBack={() => navigate(-1)}
        right={<FabioAvatar className="h-10 w-10" />}
      />

      <div className="flex-1 overflow-y-auto px-4 py-2">
        {estado === 'carregando' && (
          <div className="flex flex-col gap-2 pt-2">
            <Skeleton className="h-10 w-3/5 self-start" />
            <Skeleton className="h-10 w-1/2 self-end" />
            <Skeleton className="h-10 w-2/3 self-start" />
          </div>
        )}

        {estado === 'erro' && (
          <EmptyState
            icon="fa-solid fa-triangle-exclamation"
            title="Não consegui abrir a conversa"
            description="Deu um problema ao buscar suas mensagens. Verifica a conexão e tenta de novo."
            action={
              <Button size="sm" onClick={() => navigate(0)}>
                <i className="fa-solid fa-rotate-right" aria-hidden="true" /> Tentar de novo
              </Button>
            }
          />
        )}

        {estado === 'ok' && mensagens.length === 0 && !digitando && (
          <div className="flex h-full flex-col items-center justify-center gap-3 px-6 text-center">
            <FabioAvatar className="h-20 w-20" />
            <b className="text-[15px] font-bold">Manda um oi pro Fábio 👋</b>
            <p className="max-w-[280px] text-[13px] leading-relaxed text-text-secondary">
              Ele também está no seu WhatsApp — a conversa é a mesma nos dois lugares.
            </p>
          </div>
        )}

        {estado === 'ok' && mensagens.length > 0 && (
          <div className="flex flex-col gap-2 pb-1">
            {mensagens.map((m, i) => {
              const anterior = mensagens[i - 1]
              const trocaDia =
                !anterior ||
                new Date(anterior.criado_em).toDateString() !== new Date(m.criado_em).toDateString()
              return (
                <div key={m.id} className="flex flex-col gap-2">
                  {trocaDia && (
                    <span className="self-center rounded-full bg-bg-surface px-3 py-[3px] text-[11px] font-semibold text-text-muted">
                      {rotuloDia(m.criado_em)}
                    </span>
                  )}
                  <Bolha m={m} />
                </div>
              )
            })}
            {digitando && <Digitando />}
          </div>
        )}
        <div ref={fimRef} />
      </div>

      <form
        className="flex items-center gap-2 border-t border-border-subtle bg-bg-surface px-3 pb-[calc(10px_+_env(safe-area-inset-bottom))] pt-[10px]"
        onSubmit={enviar}
      >
        <input
          type="text"
          value={texto}
          onChange={(e) => setTexto(e.target.value)}
          placeholder="Mensagem pro Fábio…"
          enterKeyHint="send"
          className="h-10 min-w-0 flex-1 rounded-full border border-border-subtle bg-bg-inset px-4 text-sm text-text-primary placeholder:text-text-muted focus:outline-none"
        />
        <button
          type="submit"
          aria-label="Enviar"
          disabled={!texto.trim() || enviando || estado !== 'ok'}
          className="flex h-10 w-10 flex-none items-center justify-center rounded-full bg-brand text-on-brand transition-transform duration-100 active:scale-[.93] disabled:opacity-40"
        >
          <i className="fa-solid fa-paper-plane" aria-hidden="true" />
        </button>
      </form>

      <Toast message={message} visible={visible} />
    </AppFrame>
  )
}

// ---------------------------------------------------------------------------

/** Bolha de mensagem: professor à direita (teal soft), Fábio à esquerda. */
function Bolha({ m }: { m: ChatMensagem }) {
  const minha = m.role === 'professor'
  return (
    <div className={cx('flex', minha ? 'justify-end' : 'justify-start')}>
      <div
        className={cx(
          'max-w-[80%] rounded-lg px-3 py-2',
          minha
            ? 'border border-[color:var(--brand-border)] bg-brand-soft'
            : 'border border-border-subtle bg-bg-surface',
        )}
      >
        {m.kind !== 'text' && (
          <p className="text-[13px] italic text-text-secondary">
            <i
              className={m.kind === 'audio' ? 'fa-solid fa-microphone' : 'fa-solid fa-image'}
              aria-hidden="true"
            />{' '}
            {m.kind === 'audio' ? 'Áudio' : 'Imagem'} — abre no WhatsApp
          </p>
        )}
        {m.content && (
          <p className="whitespace-pre-wrap text-[13.5px] leading-relaxed text-text-primary">
            {m.content}
          </p>
        )}
        <div className="mt-[3px] flex items-center justify-end gap-[6px] text-[10.5px] text-text-muted">
          {m.channel === 'whatsapp' && (
            <span className="inline-flex items-center gap-1">
              <i className="fa-brands fa-whatsapp" aria-hidden="true" /> via WhatsApp
            </span>
          )}
          <span>{horaMensagem(m.criado_em)}</span>
        </div>
      </div>
    </div>
  )
}

/** Indicador de resposta a caminho (latência normal do Fábio: ~15-30s). */
function Digitando() {
  return (
    <div className="flex justify-start">
      <div className="flex items-center gap-2 rounded-lg border border-border-subtle bg-bg-surface px-3 py-2">
        <FabioMark className="h-[18px] w-[18px]" />
        <span className="text-[12.5px] text-text-secondary">Fábio está digitando</span>
        <span className="flex gap-[3px]">
          {[0, 1, 2].map((i) => (
            <span
              key={i}
              className="h-[5px] w-[5px] animate-pulse-soft rounded-full bg-text-muted"
              style={{ animationDelay: `${i * 0.25}s` }}
            />
          ))}
        </span>
      </div>
    </div>
  )
}
