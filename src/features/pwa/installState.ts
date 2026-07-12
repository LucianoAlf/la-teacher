/**
 * Estado global de instalação do PWA.
 *
 * O evento `beforeinstallprompt` (Chrome/Android) dispara UMA vez, cedo, antes de
 * qualquer tela montar. Capturamos aqui, no boot (import com efeito em main.tsx),
 * guardamos o evento e avisamos quem estiver ouvindo — assim o banner funciona
 * mesmo montando depois, e sobrevive à troca de rota.
 *
 * iOS não dispara esse evento (a Apple não permite convite de instalação); lá o
 * caminho é Compartilhar → Adicionar à Tela de Início, tratado no componente.
 */
export type PromptEvent = Event & {
  prompt: () => Promise<void>
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>
}

export const DISMISS_KEY = 'la_install_dismissed_v1'

let deferred: PromptEvent | null = null
const listeners = new Set<() => void>()

function emit() {
  for (const fn of listeners) fn()
}

if (typeof window !== 'undefined') {
  window.addEventListener('beforeinstallprompt', (e) => {
    e.preventDefault()
    deferred = e as PromptEvent
    emit()
  })
  window.addEventListener('appinstalled', () => {
    deferred = null
    try {
      localStorage.setItem(DISMISS_KEY, '1')
    } catch {
      /* modo privado pode barrar localStorage — sem problema */
    }
    emit()
  })
}

export function getInstallPrompt(): PromptEvent | null {
  return deferred
}

export function clearInstallPrompt() {
  deferred = null
  emit()
}

export function onInstallChange(fn: () => void): () => void {
  listeners.add(fn)
  return () => {
    listeners.delete(fn)
  }
}
