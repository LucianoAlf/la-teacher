import { createContext, useContext, useEffect, useState, type ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase } from './supabase'

interface AuthValue {
  session: Session | null
  /** true enquanto restaura a sessão do storage no boot. */
  loading: boolean
  signIn: (email: string, password: string) => Promise<{ error: string | null }>
  signOut: () => Promise<void>
}

const AuthContext = createContext<AuthValue | undefined>(undefined)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session)
      setLoading(false)
    })
    const { data: sub } = supabase.auth.onAuthStateChange((_event, s) => {
      setSession(s)
    })

    // Refresh proativo ao voltar pro primeiro plano (padrão do LA Organizer,
    // Sprint 27 — mesmo bug, já resolvido lá). Causa: o timer de
    // autoRefreshToken do supabase-js só roda com o app em foreground. Este
    // PWA fica horas fechado/em background, o token expira nesse meio tempo,
    // e ninguém dispara a renovação — o professor era forçado a logar de novo
    // (bug do Matheus no piloto). refreshSession() só renova de fato se
    // faltar pouco pro vencimento, então é barato chamar sempre.
    const aoFicarVisivel = () => {
      if (document.visibilityState === 'visible') {
        supabase.auth.refreshSession().catch(() => {
          /* falha silenciosa — o próximo request autenticado revalida */
        })
      }
    }
    document.addEventListener('visibilitychange', aoFicarVisivel)

    return () => {
      sub.subscription.unsubscribe()
      document.removeEventListener('visibilitychange', aoFicarVisivel)
    }
  }, [])

  async function signIn(email: string, password: string) {
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    return { error: error ? error.message : null }
  }

  async function signOut() {
    await supabase.auth.signOut()
  }

  return (
    <AuthContext.Provider value={{ session, loading, signIn, signOut }}>{children}</AuthContext.Provider>
  )
}

export function useAuth(): AuthValue {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth precisa estar dentro de <AuthProvider>')
  return ctx
}
