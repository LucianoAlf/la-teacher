import { useCallback, useRef, useState } from 'react'
import { cx } from '../../lib/cx'

export interface ToastState {
  message: string
  visible: boolean
}

/** Controla um Toast transitório (2,4s, como no protótipo). */
export function useToast() {
  const [state, setState] = useState<ToastState>({ message: '', visible: false })
  const timer = useRef<number | undefined>(undefined)

  const show = useCallback((message: string) => {
    setState({ message, visible: true })
    window.clearTimeout(timer.current)
    timer.current = window.setTimeout(() => {
      setState((s) => ({ ...s, visible: false }))
    }, 2400)
  }, [])

  return { ...state, show }
}

export interface ToastProps {
  message: string
  visible: boolean
}

/** Feedback transitório (protótipo .toast) — superfície invertida nos 2 temas. */
export function Toast({ message, visible }: ToastProps) {
  return (
    <div
      role="status"
      aria-live="polite"
      className={cx(
        'pointer-events-none absolute bottom-24 left-1/2 z-[60] max-w-[88%] -translate-x-1/2 rounded-md border border-border-strong bg-[var(--toast-bg)] px-4 py-[11px] text-center text-[13px] font-semibold text-[color:var(--toast-text)] transition-all duration-300',
        visible ? 'translate-y-0 opacity-100' : 'translate-y-5 opacity-0',
      )}
    >
      {message}
    </div>
  )
}
