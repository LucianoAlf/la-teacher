import { useEffect, useRef, useState } from 'react'
import { useRecorder } from '../registro/useRecorder'
import { transcreverAudio } from '../../lib/api'

/**
 * Observação escrita ou falada.
 *
 * O texto transcrito cai no campo EDITÁVEL — o professor revisa antes de virar
 * dado (`aoConfirmar`, o mesmo caminho que o textarea puro chamava). Se a
 * transcrição falhar — ou o microfone nem abrir — o campo continua digitável:
 * o microfone é atalho, nunca a única porta.
 *
 * `useRecorder` não devolve o blob no `stop()` (ele é assíncrono por dentro:
 * o MediaRecorder fecha o chunk final e só então `onstop` grava `blob` e move
 * `estado` pra 'parado'). Por isso a transcrição é disparada por um efeito que
 * observa essa transição, não pelo clique em si.
 *
 * O TEXTO TAMBÉM SALVA SOZINHO. Era só `onBlur`, e blur é frágil pra valer
 * como promessa: fechar o card (o chevron desmonta este componente — React não
 * dispara blur no desmonte), trocar de aba ou largar o celular com o teclado
 * aberto deixavam o texto só na tela. Os três caminhos agora gravam: pausa de
 * ~900 ms na digitação, blur, e desmonte. `ultimoRef` guarda o que já foi
 * mandado pro card — sem ele, blur logo depois do debounce mandaria a mesma
 * observação duas vezes, e cada envio é uma chamada de rede.
 */
const ESPERA_MS = 900
export function CampoObservacao({
  valor,
  aoConfirmar,
}: {
  valor: string
  aoConfirmar: (texto: string) => void
}) {
  const [texto, setTexto] = useState(valor)
  const [transcrevendo, setTranscrevendo] = useState(false)
  const [aviso, setAviso] = useState<string | null>(null)
  const gravador = useRecorder()

  // Lido dentro do efeito sem precisar listar `texto` nas deps (senão o
  // efeito re-rodaria a cada tecla digitada).
  const textoRef = useRef(texto)
  textoRef.current = texto

  // O que já foi entregue ao card. Começa no que veio do banco.
  const ultimoRef = useRef(valor)
  const aoConfirmarRef = useRef(aoConfirmar)
  aoConfirmarRef.current = aoConfirmar
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  function confirmar(t: string) {
    if (timerRef.current) clearTimeout(timerRef.current)
    timerRef.current = null
    if (t === ultimoRef.current) return
    ultimoRef.current = t
    aoConfirmarRef.current(t)
  }

  function digitou(t: string) {
    setTexto(t)
    if (timerRef.current) clearTimeout(timerRef.current)
    timerRef.current = setTimeout(() => confirmar(textoRef.current), ESPERA_MS)
  }

  // Desmonte (o chevron fechando o card, a mesa recarregando): entrega o que
  // ainda estava no debounce. Deps vazias de propósito — só o desmonte.
  useEffect(() => {
    return () => {
      if (timerRef.current) clearTimeout(timerRef.current)
      if (textoRef.current !== ultimoRef.current) aoConfirmarRef.current(textoRef.current)
    }
  }, [])

  // Guarda de reentrância: com <React.StrictMode> (src/main.tsx) o React
  // dispara o efeito duas vezes em dev — sem isso, uma gravação virava DUAS
  // chamadas a transcreverAudio() (custo dobrado) e a segunda resolução lia
  // o texto que a primeira acabara de anexar, duplicando o texto no campo.
  // O ref lembra qual blob já está em processamento; um blob novo (próxima
  // gravação) sempre tem identidade nova, então nunca fica preso.
  const blobEmProcessoRef = useRef<Blob | null>(null)

  useEffect(() => {
    if (gravador.estado !== 'parado' || !gravador.blob) return
    if (blobEmProcessoRef.current === gravador.blob) return
    blobEmProcessoRef.current = gravador.blob
    const blob = gravador.blob

    setTranscrevendo(true)
    setAviso(null)
    transcreverAudio(blob)
      .then((t) => {
        const falado = t.trim()
        if (!falado) {
          setAviso('Não entendi nada no áudio. Tenta de novo ou escreve aí.')
          return
        }
        const novo = textoRef.current ? `${textoRef.current} ${falado}` : falado
        setTexto(novo)
        textoRef.current = novo
        confirmar(novo)
      })
      .catch(() => setAviso('Não consegui transcrever. Pode escrever aí.'))
      .finally(() => {
        setTranscrevendo(false)
        blobEmProcessoRef.current = null
        gravador.reset() // volta pra 'idle' — libera o botão pra uma nova gravação
      })
  }, [gravador.estado, gravador.blob, gravador.reset])

  const carregando = transcrevendo || gravador.estado === 'pedindo_permissao' || gravador.estado === 'parado'
  const mensagem = transcrevendo
    ? 'transcrevendo…'
    : (aviso ?? (gravador.estado === 'erro' ? gravador.erro : null))

  return (
    <div>
      <span className="mb-1 block text-[11px] font-bold uppercase tracking-[.5px] text-text-secondary">
        Observação
      </span>
      <div className="relative">
        <textarea
          rows={2}
          value={texto}
          onChange={(e) => digitou(e.target.value)}
          onBlur={() => confirmar(texto)}
          placeholder="Algo que vale a coordenação saber — um elogio, um ponto de melhoria, uma mudança que você notou."
          className="w-full resize-none rounded-lg border border-border-subtle bg-bg-inset px-3 py-2 pr-10 text-[13px] text-text-primary placeholder:text-text-muted"
        />
        <button
          type="button"
          aria-label={gravador.estado === 'gravando' ? 'Parar gravação' : 'Gravar observação'}
          onClick={() => {
            if (gravador.estado === 'gravando') {
              gravador.stop()
            } else {
              setAviso(null) // nova tentativa: some com o aviso da anterior
              void gravador.start()
            }
          }}
          disabled={carregando}
          className="absolute right-2 top-2 rounded-lg p-1.5 text-text-muted disabled:opacity-60"
        >
          <i
            className={
              carregando
                ? 'fa-solid fa-circle-notch fa-spin'
                : gravador.estado === 'gravando'
                  ? 'fa-solid fa-stop text-danger-text'
                  : 'fa-solid fa-microphone'
            }
            aria-hidden
          />
        </button>
      </div>
      {mensagem ? (
        <p className={`mt-1 text-[11.5px] ${transcrevendo ? 'text-text-muted' : 'text-warning-text'}`}>
          {mensagem}
        </p>
      ) : null}
    </div>
  )
}
