import { useEffect, useRef, useState, type MouseEvent } from 'react'
import { cx } from '../../lib/cx'

export interface AudioPlayerProps {
  src: string
  className?: string
}

function fmt(s: number): string {
  if (!Number.isFinite(s) || s < 0) return '0:00'
  const m = Math.floor(s / 60)
  return `${m}:${String(Math.floor(s % 60)).padStart(2, '0')}`
}

// Alturas estáveis de uma pseudo-forma-de-onda (determinístico, sem random) —
// ecoa as barrinhas da tela de gravação. Vai de ~0.30 a 1.0 da altura.
const BARRAS = Array.from({ length: 32 }, (_, i) => {
  const n = Math.sin(i * 1.7) * 0.5 + Math.sin(i * 0.6) * 0.32 + Math.sin(i * 3.3) * 0.18
  return 0.3 + Math.abs(n) * 0.7
})

/**
 * Player de áudio do Fábio DS — substitui o `<audio controls>` nativo (que no
 * mobile vira uma pílula branca fora do tema). Botão teal + forma-de-onda
 * clicável (seek) + tempo mono. Só tokens semânticos; funciona nos dois temas.
 */
export function AudioPlayer({ src, className }: AudioPlayerProps) {
  const ref = useRef<HTMLAudioElement>(null)
  const [tocando, setTocando] = useState(false)
  const [tempo, setTempo] = useState(0)
  const [dur, setDur] = useState(0)

  useEffect(() => {
    const a = ref.current
    if (!a) return
    const onTime = () => setTempo(a.currentTime)
    const onDur = () => setDur(Number.isFinite(a.duration) ? a.duration : 0)
    const onFim = () => {
      setTocando(false)
      setTempo(0)
    }
    a.addEventListener('timeupdate', onTime)
    a.addEventListener('loadedmetadata', onDur)
    a.addEventListener('durationchange', onDur)
    a.addEventListener('play', () => setTocando(true))
    a.addEventListener('pause', () => setTocando(false))
    a.addEventListener('ended', onFim)
    return () => {
      a.removeEventListener('timeupdate', onTime)
      a.removeEventListener('loadedmetadata', onDur)
      a.removeEventListener('durationchange', onDur)
      a.removeEventListener('ended', onFim)
    }
  }, [src])

  const frac = dur > 0 ? Math.min(1, tempo / dur) : 0

  const alternar = () => {
    const a = ref.current
    if (!a) return
    if (a.paused) void a.play()
    else a.pause()
  }

  const buscar = (e: MouseEvent<HTMLDivElement>) => {
    const a = ref.current
    if (!a || !dur) return
    const r = e.currentTarget.getBoundingClientRect()
    const p = Math.min(1, Math.max(0, (e.clientX - r.left) / r.width))
    a.currentTime = p * dur
    setTempo(p * dur)
  }

  return (
    <div
      className={cx(
        'flex items-center gap-3 rounded-lg border border-border-subtle bg-bg-surface px-3 py-[10px]',
        className,
      )}
    >
      <audio ref={ref} src={src} preload="metadata" className="hidden" />

      <button
        type="button"
        aria-label={tocando ? 'Pausar' : 'Tocar'}
        onClick={alternar}
        className="flex h-11 w-11 flex-none items-center justify-center rounded-full bg-brand text-lg text-on-brand shadow-fab transition-transform duration-100 active:scale-90"
      >
        <i className={cx('fa-solid', tocando ? 'fa-pause' : 'fa-play ml-[2px]')} aria-hidden="true" />
      </button>

      <div
        className="flex h-9 flex-1 cursor-pointer items-center gap-[2px]"
        onClick={buscar}
        role="slider"
        aria-label="Posição do áudio"
        aria-valuemin={0}
        aria-valuemax={100}
        aria-valuenow={Math.round(frac * 100)}
      >
        {BARRAS.map((h, i) => (
          <span
            key={i}
            className={cx(
              'min-w-0 flex-1 rounded-full transition-colors duration-150',
              i / BARRAS.length < frac ? 'bg-brand' : 'bg-border-strong',
            )}
            style={{ height: `${Math.round(h * 100)}%` }}
          />
        ))}
      </div>

      <span className="flex-none font-mono text-xs tabular-nums text-text-secondary">
        {fmt(tempo)} / {fmt(dur)}
      </span>
    </div>
  )
}
