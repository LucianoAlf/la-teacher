import { useEffect, useMemo, useRef, useState } from 'react'
import { AudioPlayer, Button } from '../../components/ui'
import { JANELA_POS_AULA_DIAS } from '../agenda/sessao'
import { LIMITE_SEGUNDOS, useRecorder } from '../registro/useRecorder'
import { statusAudioFila } from '../../lib/api'
import { SOMENTE_LEITURA } from '../../lib/config'
import { enviarAudioExperimental, type ErroExperimental } from './uploadAudioExperimental'

/** Quanto tempo esperar o Fábio antes de dizer "não deu". O worker roda a cada
 *  20s e leva ~25s por áudio; 3 minutos cobre fila com mais de um na frente. */
const LIMITE_ESPERA_MS = 3 * 60 * 1000
const INTERVALO_POLL_MS = 3000

type Fase =
  | { nome: 'gravar' }
  | { nome: 'enviando' }
  | { nome: 'ouvindo'; audioId: string }
  | { nome: 'falhou'; motivo: string; permanente: boolean }

const MSG_ERRO: Record<ErroExperimental | 'rede' | 'demorou' | 'nao_entendi', string> = {
  aula_de_outro_professor: 'Essa aula não é da sua agenda.',
  aula_cancelada: 'Essa aula foi cancelada.',
  gravacao_ainda_nao_disponivel: 'A gravação abre 15 minutos antes da aula começar.',
  janela_de_gravacao_encerrada: `A gravação fecha ${JANELA_POS_AULA_DIAS} dias depois da aula. Passado o prazo, só a coordenação libera — fala com ela.`,
  experimental_sem_aula_vinculada: 'Essa experimental ainda não tem aula na agenda.',
  experimental_faltou_nao_tem_registro: 'Essa experimental está marcada como falta.',
  experimental_cancelada: 'Essa experimental foi cancelada.',
  sem_professor_vinculado: 'Seu login ainda não está ligado a um professor.',
  rede: 'Não consegui enviar. Sua gravação ainda está aqui — tenta de novo.',
  demorou: 'O Fábio está demorando mais que o normal. Você pode escrever nos campos e seguir.',
  nao_entendi: 'Não consegui entender o áudio. Tenta gravar de novo, mais perto do microfone.',
}

/**
 * Gravar a experimental por voz.
 *
 * A tela de login promete "sem digitar". Esta é a parte que cumpre: o professor
 * fala, e os quatro campos abaixo se preenchem. Os campos continuam ali, e
 * continuam editáveis — o áudio adianta o trabalho, não substitui o professor.
 *
 * Enquanto o Fábio ouve, o componente fica PERGUNTANDO o status em vez de
 * esperar um empurrão: a fila é um timer de 20s na VPS, não um websocket. Se
 * passar do limite, ele não trava a tela — devolve o controle e o professor
 * escreve. Bloquear alguém que acabou de dar aula porque uma fila atrasou é a
 * pior troca possível.
 */
export function GravadorExperimental({
  vinculoId,
  onPronto,
}: {
  vinculoId: number
  /** Chamado quando o Fábio terminou: a tela recarrega o registro e preenche. */
  onPronto: () => void
}) {
  const rec = useRecorder()
  const [fase, setFase] = useState<Fase>({ nome: 'gravar' })
  const previewUrl = useMemo(() => (rec.blob ? URL.createObjectURL(rec.blob) : null), [rec.blob])
  const onProntoRef = useRef(onPronto)
  onProntoRef.current = onPronto

  useEffect(() => () => { if (previewUrl) URL.revokeObjectURL(previewUrl) }, [previewUrl])

  // ── O Fábio ouvindo: pergunta a cada 3s até normalizar, dar erro, ou cansar
  useEffect(() => {
    if (fase.nome !== 'ouvindo') return
    let vivo = true
    const inicio = Date.now()
    const id = window.setInterval(async () => {
      if (!vivo) return
      try {
        const s = await statusAudioFila(fase.audioId)
        if (!vivo || !s) return
        if (s.status === 'normalizado') {
          vivo = false
          window.clearInterval(id)
          onProntoRef.current()
          setFase({ nome: 'gravar' })
          rec.reset()
          return
        }
        if (s.status === 'erro') {
          vivo = false
          window.clearInterval(id)
          setFase({ nome: 'falhou', motivo: MSG_ERRO.nao_entendi, permanente: false })
          return
        }
      } catch {
        /* falha de rede numa pergunta: a próxima tenta de novo */
      }
      if (Date.now() - inicio > LIMITE_ESPERA_MS) {
        vivo = false
        window.clearInterval(id)
        setFase({ nome: 'falhou', motivo: MSG_ERRO.demorou, permanente: false })
      }
    }, INTERVALO_POLL_MS)
    return () => {
      vivo = false
      window.clearInterval(id)
    }
    // rec.reset é estável (useCallback); fase.audioId é o que importa aqui.
  }, [fase, rec])

  async function enviar() {
    if (!rec.blob) return
    if (SOMENTE_LEITURA) {
      setFase({ nome: 'falhou', motivo: 'Ambiente de demonstração: o áudio não é enviado.', permanente: true })
      return
    }
    setFase({ nome: 'enviando' })
    const r = await enviarAudioExperimental({
      vinculoId,
      blob: rec.blob,
      mime: rec.mime || rec.blob.type,
      duracaoSegundos: rec.segundos,
    })
    if (r.ok) {
      setFase({ nome: 'ouvindo', audioId: r.audioId })
    } else {
      setFase({
        nome: 'falhou',
        motivo: MSG_ERRO[r.motivo],
        // Motivo de validação não melhora com insistência: a tela não oferece
        // "tentar de novo" pra um botão que nunca vai passar.
        permanente: r.motivo !== 'rede',
      })
    }
  }

  return (
    <section className="rounded-lg border border-[color:var(--brand-border)] bg-brand-soft/40 px-4 py-4">
      {rec.estado === 'erro' && (
        <Aviso
          icone="fa-solid fa-microphone-slash"
          titulo="Sem acesso ao microfone"
          texto={rec.erro ?? 'Libera o microfone nas permissões e tenta de novo.'}
          acao={<Button size="sm" variant="ghost" onClick={() => void rec.start()}>Tentar de novo</Button>}
        />
      )}

      {fase.nome === 'gravar' && rec.estado === 'idle' && (
        <div className="flex flex-col items-center gap-3 text-center">
          <button
            type="button"
            aria-label="Gravar como foi a experimental"
            onClick={() => void rec.start()}
            className="flex h-[72px] w-[72px] items-center justify-center rounded-full bg-brand text-2xl text-on-brand shadow-fab transition-transform active:scale-[.93]"
          >
            <i className="fa-solid fa-microphone" aria-hidden="true" />
          </button>
          <div>
            <b className="block text-[14.5px]">Conta como foi</b>
            <span className="text-[12.5px] leading-relaxed text-text-secondary">
              O Fábio organiza nos campos abaixo. Você confere antes de enviar.
            </span>
          </div>
          <span className="text-[11px] font-semibold uppercase tracking-[.5px] text-text-muted">
            ou escreve você mesmo · máx. {Math.floor(LIMITE_SEGUNDOS / 60)} min
          </span>
        </div>
      )}

      {rec.estado === 'pedindo_permissao' && (
        <p className="text-center text-[13px] text-text-secondary">
          <i className="fa-solid fa-microphone" aria-hidden="true" /> Pedindo acesso ao microfone…
        </p>
      )}

      {rec.estado === 'gravando' && (
        <div className="flex flex-col items-center gap-3">
          <div className="flex h-10 items-center gap-1" style={{ opacity: 0.55 + rec.nivel * 0.45 }} aria-hidden="true">
            {Array.from({ length: 14 }, (_, i) => (
              <i
                key={i}
                className="block h-3 w-[5px] animate-wave rounded-[3px] bg-brand"
                style={{ animationDelay: `${(i % 5) * 0.15}s` }}
              />
            ))}
          </div>
          <div className="font-mono text-[30px] font-semibold tracking-[1px]" role="timer">
            {fmt(rec.segundos)}
          </div>
          <p className="max-w-[290px] text-center text-[12.5px] leading-relaxed text-text-secondary">
            Como o aluno respondeu, o que contar pra família, por onde continuar — e o que você
            sentiu sobre a decisão deles. 🎙️
          </p>
          <button
            type="button"
            aria-label="Parar gravação"
            onClick={rec.stop}
            className="flex h-[60px] w-[60px] items-center justify-center rounded-full bg-danger text-xl text-[color:var(--on-danger)] shadow-fab transition-transform active:scale-[.93]"
          >
            <i className="fa-solid fa-stop" aria-hidden="true" />
          </button>
        </div>
      )}

      {fase.nome === 'gravar' && rec.estado === 'parado' && (
        <div className="flex flex-col items-center gap-3">
          <b className="text-[14.5px]">Gravado — {fmt(rec.segundos)}</b>
          {previewUrl && <AudioPlayer src={previewUrl} className="w-full max-w-[320px]" />}
          <div className="flex w-full max-w-[300px] flex-col gap-2">
            <Button block onClick={() => void enviar()}>
              <i className="fa-solid fa-paper-plane" aria-hidden="true" /> Enviar pro Fábio
            </Button>
            <Button block variant="ghost" onClick={rec.reset}>
              <i className="fa-solid fa-rotate-left" aria-hidden="true" /> Re-gravar
            </Button>
          </div>
        </div>
      )}

      {fase.nome === 'enviando' && (
        <p className="text-center text-[13px] text-text-secondary">
          <i className="fa-solid fa-cloud-arrow-up fa-bounce" aria-hidden="true" /> Subindo seu áudio…
        </p>
      )}

      {fase.nome === 'ouvindo' && (
        <div className="flex flex-col items-center gap-2 text-center">
          <i className="fa-solid fa-headphones fa-beat-fade text-2xl text-brand-text" aria-hidden="true" />
          <b className="text-[14.5px]">O Fábio está ouvindo…</b>
          <span className="max-w-[280px] text-[12.5px] leading-relaxed text-text-secondary">
            Leva menos de um minuto. Pode deixar a tela aberta — assim que ele terminar, os campos
            abaixo se preenchem.
          </span>
        </div>
      )}

      {fase.nome === 'falhou' && (
        <Aviso
          icone="fa-solid fa-triangle-exclamation"
          titulo="Não deu pelo áudio"
          texto={fase.motivo}
          acao={
            <div className="flex gap-2">
              {!fase.permanente && rec.blob && (
                <Button size="sm" onClick={() => void enviar()}>
                  <i className="fa-solid fa-rotate-right" aria-hidden="true" /> Tentar de novo
                </Button>
              )}
              <Button size="sm" variant="ghost" onClick={() => { rec.reset(); setFase({ nome: 'gravar' }) }}>
                Escrever eu mesmo
              </Button>
            </div>
          }
        />
      )}
    </section>
  )
}

function Aviso({
  icone, titulo, texto, acao,
}: { icone: string; titulo: string; texto: string; acao?: React.ReactNode }) {
  return (
    <div className="flex flex-col items-center gap-2 text-center">
      <i className={`${icone} text-xl text-warning-text`} aria-hidden="true" />
      <b className="text-[14px]">{titulo}</b>
      <span className="max-w-[290px] text-[12.5px] leading-relaxed text-text-secondary">{texto}</span>
      {acao}
    </div>
  )
}

function fmt(s: number): string {
  return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`
}
