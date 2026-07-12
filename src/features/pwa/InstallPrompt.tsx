import { useEffect, useState } from 'react'
import { Download, Plus, X } from 'lucide-react'
import { Button } from '../../components/ui/Button'
import {
  DISMISS_KEY,
  clearInstallPrompt,
  getInstallPrompt,
  onInstallChange,
} from './installState'

function isStandalone(): boolean {
  return (
    window.matchMedia('(display-mode: standalone)').matches ||
    (navigator as unknown as { standalone?: boolean }).standalone === true
  )
}

function isIOS(): boolean {
  const ua = navigator.userAgent
  const iphone = /iphone|ipad|ipod/i.test(ua)
  // iPadOS 13+ se apresenta como Mac; detecta pelo toque.
  const ipadDesktop = /macintosh/i.test(ua) && navigator.maxTouchPoints > 1
  return iphone || ipadDesktop
}

/** Ícone de compartilhar do iOS (quadrado com seta pra cima) — igual ao do Safari. */
function IosShareGlyph() {
  return (
    <svg
      viewBox="0 0 24 24"
      width="16"
      height="16"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      className="inline-block shrink-0 align-[-3px]"
    >
      <path d="M12 15V3" />
      <path d="M8 7l4-4 4 4" />
      <path d="M5 12v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-7" />
    </svg>
  )
}

/**
 * Convite de instalação do app (só na área autenticada, montado no AppFrame).
 * Android: botão "Instalar" via beforeinstallprompt. iPhone: guia manual.
 * Aparece uma vez; "Agora não" grava dispensa no localStorage.
 */
export function InstallPrompt() {
  const [visible, setVisible] = useState(false)
  const [mode, setMode] = useState<'android' | 'ios'>('android')

  useEffect(() => {
    if (isStandalone()) return
    try {
      if (localStorage.getItem(DISMISS_KEY)) return
    } catch {
      /* localStorage bloqueado — segue mostrando */
    }

    if (isIOS()) {
      setMode('ios')
      const t = setTimeout(() => setVisible(true), 1400)
      return () => clearTimeout(t)
    }

    // Android/Chrome: espera o beforeinstallprompt (pode já ter chegado).
    const sync = () => {
      if (getInstallPrompt()) {
        setMode('android')
        setVisible(true)
      }
    }
    sync()
    return onInstallChange(sync)
  }, [])

  if (!visible) return null

  const dismiss = () => {
    setVisible(false)
    try {
      localStorage.setItem(DISMISS_KEY, '1')
    } catch {
      /* sem problema */
    }
  }

  const install = async () => {
    const evt = getInstallPrompt()
    if (!evt) return dismiss()
    try {
      await evt.prompt()
      await evt.userChoice
    } catch {
      /* usuário fechou o prompt nativo */
    }
    clearInstallPrompt()
    dismiss()
  }

  return (
    <div
      className="absolute inset-0 z-50 flex items-end"
      role="dialog"
      aria-modal="true"
      aria-label="Instalar o LA Teacher"
    >
      <button className="absolute inset-0 bg-black/50" aria-label="Fechar" onClick={dismiss} />
      <div className="relative w-full rounded-t-2xl border-t border-border-subtle bg-bg-surface p-5 pb-[calc(20px+env(safe-area-inset-bottom))]">
        <button
          onClick={dismiss}
          aria-label="Fechar"
          className="absolute right-3 top-3 p-1 text-text-muted"
        >
          <X size={20} />
        </button>

        <div className="mb-4 flex items-center gap-3">
          <img
            src="/icons/icon-192.png"
            alt=""
            className="h-14 w-14 rounded-[14px]"
            width={56}
            height={56}
          />
          <div className="min-w-0">
            <p className="font-bold text-text-primary">Instale o LA Teacher</p>
            <p className="text-[13px] leading-snug text-text-secondary">
              Abre em tela cheia, direto da sua tela de início — sem a barra do navegador.
            </p>
          </div>
        </div>

        {mode === 'android' ? (
          <Button block onClick={install}>
            <Download size={18} /> Instalar app
          </Button>
        ) : (
          <div className="rounded-md bg-bg-inset p-3 text-[13.5px] leading-relaxed text-text-secondary">
            <p className="mb-2 font-semibold text-text-primary">No iPhone, em 2 toques:</p>
            <p>
              1. Toque em <IosShareGlyph /> <span className="text-text-primary">(Compartilhar)</span> na
              barra do Safari
            </p>
            <p className="mt-1 flex items-center gap-1">
              2. Escolha <Plus size={15} className="text-brand-text" />
              <span className="font-semibold text-text-primary">Adicionar à Tela de Início</span>
            </p>
          </div>
        )}
      </div>
    </div>
  )
}
