import { createContext, useContext, useEffect, useState, type ReactNode } from 'react'
import type { AuthError, Session } from '@supabase/supabase-js'
import { supabase } from './supabase'

/**
 * Por que o login precisa distinguir tipo de falha (03/08/2026):
 *
 * O app dizia "E-mail ou senha incorretos" pra QUALQUER erro — inclusive pra
 * "não consegui falar com o servidor". No primeiro dia do piloto a internet do
 * Matheus oscilou, ele leu que a senha estava errada e passou meia hora
 * caçando senha. Eu também: fui atrás de senha salva no navegador. O problema
 * era rede, e ele resolveu reiniciando o note.
 *
 * Uma mensagem de erro que chuta a causa custa mais caro que uma que admite não
 * saber. Aqui a gente classifica antes de falar.
 */
export type FalhaLogin = 'credenciais' | 'conexao' | 'muitas_tentativas' | 'inesperado'

export function classificarFalhaAuth(error: AuthError): FalhaLogin {
  // Navegador já sabe que está sem rede: não precisa nem olhar o erro.
  if (typeof navigator !== 'undefined' && navigator.onLine === false) return 'conexao'
  // Sem rede o supabase-js nem chega no servidor — devolve AuthRetryableFetchError,
  // que vem sem status HTTP (ou com 0). Isso NÃO é senha errada.
  if (error.name === 'AuthRetryableFetchError' || !error.status) return 'conexao'
  if (error.status === 429) return 'muitas_tentativas'
  if (error.status === 400 || error.status === 401 || error.status === 422) return 'credenciais'
  return 'inesperado'
}

interface AuthValue {
  session: Session | null
  /** true enquanto restaura a sessão do storage no boot. */
  loading: boolean
  /**
   * true quando o professor chegou por um link de recuperação de senha.
   * Existe porque o link do Supabase NÃO cai necessariamente na rota que a
   * gente pediu: se o `redirectTo` não estiver na allowlist do projeto, ele
   * joga o professor na Site URL. Detectando aqui, o app leva ele pra tela de
   * senha nova venha o link de onde vier — e o fluxo não fica refém de uma
   * configuração de painel.
   */
  recuperacao: boolean
  /** Chamado quando a senha nova já foi salva: a viagem de recuperação acabou. */
  encerrarRecuperacao: () => void
  signIn: (email: string, password: string) => Promise<{ falha: FalhaLogin | null }>
  signOut: () => Promise<void>
}

const AuthContext = createContext<AuthValue | undefined>(undefined)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [loading, setLoading] = useState(true)
  // Lido de forma SÍNCRONA, no primeiro render: o supabase-js limpa o hash da
  // URL assim que processa o link, então quem só escutasse o evento poderia
  // chegar tarde. O evento abaixo cobre o outro lado (hash já consumido).
  const [recuperacao, setRecuperacao] = useState(
    () => typeof window !== 'undefined' && window.location.hash.includes('type=recovery'),
  )

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session)
      setLoading(false)
    })
    const { data: sub } = supabase.auth.onAuthStateChange((event, s) => {
      setSession(s)
      if (event === 'PASSWORD_RECOVERY') setRecuperacao(true)
    })

    // Ao voltar pro primeiro plano, revalida a sessão. O motivo original
    // continua valendo: o timer de autoRefreshToken do supabase-js só roda com
    // o app em foreground, e este PWA fica horas fechado — o token vence nesse
    // meio-tempo e ninguém renova.
    //
    // MAS AQUI ERA getSession(), NÃO refreshSession() (corrigido em 17/08/2026).
    // O comentário antigo afirmava que "refreshSession() só renova de fato se
    // faltar pouco pro vencimento". Fui no fonte do auth-js: é FALSO —
    // `_refreshSession` chama `_callRefreshToken` incondicionalmente e ROTACIONA
    // o token toda vez. Medido em auth.refresh_tokens: 420 tokens do Matheus num
    // dia só, mediana de 6s entre rotações. Cada rotação revoga a anterior, o
    // que abre corrida: quem ainda segurar o token velho leva 400 não-retryable,
    // e aí o auth-js DESTRÓI a sessão (`_removeSession`) se o access token já
    // tiver vencido — logout.
    //
    // getSession() faz o certo: só renova se estiver vencido, e preserva a
    // sessão quando a falha é de rede (o app volta ao ar sem exigir login).
    const aoFicarVisivel = () => {
      if (document.visibilityState === 'visible') {
        supabase.auth.getSession().catch(() => {
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
    return { falha: error ? classificarFalhaAuth(error) : null }
  }

  async function signOut() {
    await supabase.auth.signOut()
  }

  return (
    <AuthContext.Provider
      value={{
        session,
        loading,
        recuperacao,
        encerrarRecuperacao: () => setRecuperacao(false),
        signIn,
        signOut,
      }}
    >
      {children}
    </AuthContext.Provider>
  )
}

export function useAuth(): AuthValue {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth precisa estar dentro de <AuthProvider>')
  return ctx
}
