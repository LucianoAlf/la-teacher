import { useCallback, useEffect, useRef, useState } from 'react'

export type EstadoGravacao = 'idle' | 'pedindo_permissao' | 'gravando' | 'parado' | 'erro'

/** Limite de segurança: 5 minutos (evita áudio gigante na fila). */
export const LIMITE_SEGUNDOS = 5 * 60

/**
 * Escolhe o mimeType suportado pela plataforma:
 * iOS/Safari não suporta webm → cai em 'audio/mp4';
 * Android/Chrome preferem 'audio/webm;codecs=opus'.
 */
export function escolherMime(): string {
  if (typeof MediaRecorder === 'undefined') return ''
  const candidatos = ['audio/webm;codecs=opus', 'audio/webm', 'audio/mp4']
  for (const m of candidatos) {
    if (MediaRecorder.isTypeSupported(m)) return m
  }
  return '' // deixa o browser decidir
}

/** Extensão de arquivo a partir do mime (audio/mp4 → m4a; webm → webm). */
export function extensaoDoMime(mime: string): string {
  if (mime.includes('mp4')) return 'm4a'
  if (mime.includes('webm')) return 'webm'
  return 'webm'
}

export interface Recorder {
  estado: EstadoGravacao
  /** Duração corrente (ou final) em segundos. */
  segundos: number
  /** Blob final — disponível quando estado === 'parado'. */
  blob: Blob | null
  /** MimeType efetivamente usado na gravação. */
  mime: string
  /** Mensagem amigável quando estado === 'erro'. */
  erro: string | null
  /** Nível de áudio 0..1 (para animação da onda). */
  nivel: number
  start: () => Promise<void>
  stop: () => void
  reset: () => void
}

/**
 * Gravação de áudio via MediaRecorder, com timer, nível (AnalyserNode) e
 * parada automática no LIMITE_SEGUNDOS. Permissão negada → estado 'erro'
 * amigável, nunca tela branca.
 */
export function useRecorder(): Recorder {
  const [estado, setEstado] = useState<EstadoGravacao>('idle')
  const [segundos, setSegundos] = useState(0)
  const [blob, setBlob] = useState<Blob | null>(null)
  const [erro, setErro] = useState<string | null>(null)
  const [nivel, setNivel] = useState(0)
  const [mime] = useState(escolherMime)

  const recorderRef = useRef<MediaRecorder | null>(null)
  const streamRef = useRef<MediaStream | null>(null)
  const chunksRef = useRef<BlobPart[]>([])
  const timerRef = useRef<number | undefined>(undefined)
  const nivelTimerRef = useRef<number | undefined>(undefined)
  const audioCtxRef = useRef<AudioContext | null>(null)

  const limparRecursos = useCallback(() => {
    window.clearInterval(timerRef.current)
    window.clearInterval(nivelTimerRef.current)
    streamRef.current?.getTracks().forEach((t) => t.stop())
    streamRef.current = null
    audioCtxRef.current?.close().catch(() => {})
    audioCtxRef.current = null
    setNivel(0)
  }, [])

  const stop = useCallback(() => {
    const rec = recorderRef.current
    if (rec && rec.state !== 'inactive') rec.stop()
  }, [])

  const start = useCallback(async () => {
    setErro(null)
    setBlob(null)
    setSegundos(0)
    chunksRef.current = []
    setEstado('pedindo_permissao')

    let stream: MediaStream
    try {
      stream = await navigator.mediaDevices.getUserMedia({ audio: true })
    } catch {
      setEstado('erro')
      setErro('Preciso do microfone pra gravar. Libera o acesso nas permissões do navegador e tenta de novo.')
      return
    }

    streamRef.current = stream
    const rec = new MediaRecorder(stream, mime ? { mimeType: mime } : undefined)
    recorderRef.current = rec

    rec.ondataavailable = (e) => {
      if (e.data.size > 0) chunksRef.current.push(e.data)
    }
    rec.onstop = () => {
      const final = new Blob(chunksRef.current, { type: rec.mimeType || mime || 'audio/webm' })
      setBlob(final)
      setEstado('parado')
      limparRecursos()
    }

    // nível de áudio pra onda (best-effort — se falhar, segue sem)
    try {
      const ctx = new AudioContext()
      audioCtxRef.current = ctx
      const analyser = ctx.createAnalyser()
      analyser.fftSize = 256
      ctx.createMediaStreamSource(stream).connect(analyser)
      const dados = new Uint8Array(analyser.frequencyBinCount)
      nivelTimerRef.current = window.setInterval(() => {
        analyser.getByteFrequencyData(dados)
        const media = dados.reduce((s, v) => s + v, 0) / dados.length
        setNivel(Math.min(1, media / 128))
      }, 150)
    } catch {
      // sem analisador — a onda anima em ritmo fixo
    }

    rec.start(15000) // chunks periódicos: gravação longa não vive só na memória do recorder
    setEstado('gravando')
    timerRef.current = window.setInterval(() => {
      setSegundos((s) => {
        if (s + 1 >= LIMITE_SEGUNDOS) stop() // trava de segurança
        return s + 1
      })
    }, 1000)
  }, [limparRecursos, mime, stop])

  const reset = useCallback(() => {
    stop()
    limparRecursos()
    setBlob(null)
    setSegundos(0)
    setErro(null)
    setEstado('idle')
  }, [limparRecursos, stop])

  // desmontou no meio da gravação → solta microfone e timers
  useEffect(() => () => limparRecursos(), [limparRecursos])

  return { estado, segundos, blob, mime, erro, nivel, start, stop, reset }
}
