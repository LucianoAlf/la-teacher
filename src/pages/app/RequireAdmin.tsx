import { useEffect, useState } from 'react'
import { Navigate, Outlet } from 'react-router-dom'
import { EmptyState, FabioAvatar } from '../../components/ui'
import { useAuth } from '../../lib/auth'
import { professoresParaLiberar } from '../../lib/api'
import { AppFrame } from './AppFrame'

type Estado = 'checando' | 'ok' | 'nao_admin' | 'erro'

/**
 * Guard das telas de administração.
 *
 * SEPARADO do RequireProfessor de propósito, e isso não é organização: o
 * RequireProfessor manda pra "Vínculo pendente" quem não tem professor — e o
 * admin da escola NÃO tem professor. Pendurar o painel lá dentro faria o dono
 * do painel bater na tela de quem não tem acesso.
 *
 * Quem decide se é admin é o BANCO: a RPC levanta `apenas_admin` (057). Aqui só
 * se traduz a resposta — perfil guardado no cliente seria só sugestão.
 */
export function RequireAdmin() {
  const { session, loading } = useAuth()
  const [estado, setEstado] = useState<Estado>('checando')
  const userId = session?.user.id

  useEffect(() => {
    if (loading || !userId) return
    let vivo = true
    setEstado('checando')
    professoresParaLiberar()
      .then(() => vivo && setEstado('ok'))
      .catch((e: unknown) => {
        if (!vivo) return
        const msg = String((e as { message?: string })?.message ?? e)
        setEstado(msg.includes('apenas_admin') ? 'nao_admin' : 'erro')
      })
    return () => {
      vivo = false
    }
  }, [loading, userId])

  if (!loading && !session) return <Navigate to="/app/login" replace />

  if (estado === 'checando' || loading) {
    return (
      <AppFrame>
        <div className="flex flex-1 flex-col items-center justify-center gap-4">
          <FabioAvatar className="h-[84px] w-[84px] animate-bob" alt="Fábio" />
          <p className="text-[13px] text-text-secondary">Conferindo seu acesso…</p>
        </div>
      </AppFrame>
    )
  }

  if (estado === 'nao_admin') {
    return (
      <AppFrame>
        <EmptyState
          icon="fa-solid fa-lock"
          title="Essa área é da coordenação"
          description="Seu acesso é de professor. Se você precisa liberar alguém, fala com quem cuida da administração."
        />
      </AppFrame>
    )
  }

  if (estado === 'erro') {
    return (
      <AppFrame>
        <EmptyState
          icon="fa-solid fa-triangle-exclamation"
          title="Não consegui conferir agora"
          description="Deu um problema de conexão. Recarrega a página e tenta de novo."
        />
      </AppFrame>
    )
  }

  return <Outlet />
}
