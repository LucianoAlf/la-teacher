import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react'

export type Theme = 'dark' | 'light'

const STORAGE_KEY = 'la-teacher:theme'
const DEFAULT_THEME: Theme = 'dark' // padrão do app do professor

function readStoredTheme(): Theme {
  try {
    const stored = localStorage.getItem(STORAGE_KEY)
    return stored === 'light' || stored === 'dark' ? stored : DEFAULT_THEME
  } catch {
    return DEFAULT_THEME
  }
}

/**
 * Aplica o tema salvo no <html> ANTES do React renderizar (chamado no main.tsx).
 * Evita o flash do tema errado num reload e garante que TODA rota nasce com o
 * tema certo — não depende de nenhum componente estar montado.
 */
export function aplicarTemaInicial() {
  document.documentElement.dataset.theme = readStoredTheme()
}

interface ThemeValue {
  theme: Theme
  setTheme: (t: Theme) => void
  toggle: () => void
}

const ThemeContext = createContext<ThemeValue | undefined>(undefined)

/**
 * Tema GLOBAL (contexto na raiz do app). O estado é único; qualquer toggle
 * reaplica em document.documentElement (data-theme) e persiste no localStorage.
 * Nenhum componente checa o tema: os tokens semânticos resolvem sozinhos.
 */
export function ThemeProvider({ children }: { children: ReactNode }) {
  const [theme, setTheme] = useState<Theme>(readStoredTheme)

  useEffect(() => {
    document.documentElement.dataset.theme = theme
    try {
      localStorage.setItem(STORAGE_KEY, theme)
    } catch {
      // storage indisponível (modo privado etc.) — segue só em memória
    }
  }, [theme])

  const toggle = useCallback(() => {
    setTheme((t) => (t === 'dark' ? 'light' : 'dark'))
  }, [])

  return <ThemeContext.Provider value={{ theme, setTheme, toggle }}>{children}</ThemeContext.Provider>
}

export function useTheme(): ThemeValue {
  const ctx = useContext(ThemeContext)
  if (!ctx) throw new Error('useTheme precisa estar dentro de <ThemeProvider>')
  return ctx
}
