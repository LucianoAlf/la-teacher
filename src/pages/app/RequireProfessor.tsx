import { useEffect, useState } from 'react'
import { Navigate, Outlet } from 'react-router-dom'
import { Button } from '../../components/ui'
import { useAuth } from '../../lib/auth'
import { isSemVinculo, minhaAgendaSessao } from '../../lib/api'
import { iniciarSincronizacaoFila } from '../../features/registro/uploadAudio'
import { AppFrame } from './AppFrame'
import VinculoPendentePage from './VinculoPendente'

type Estado = 'checando' | 'ok' | 'sem_vinculo' | 'erro'

/** Tela de carregamento (nunca branca) enquanto o guard decide. */
function Carregando() {
  return (
    <AppFrame>
      <div className="flex flex-1 flex-col items-center justify-center gap-4">
        <div className="flex h-16 w-16 items-center justify-center rounded-full bg-brand-soft text-2xl text-brand-text">
          <i className="fa-solid fa-robot fa-bounce" aria-hidden="true" />
        </div>
        <p className="text-[13px] text-text-secondary">Preparando seu dia…</p>
      </div>
    </AppFrame>
  )
}

/**
 * Guard do app do professor:
 *  - sem sessão            → /app/login
 *  - sessão + sem vínculo  → VinculoPendente
 *  - sessão + vínculo ok   → conteúdo (<Outlet/>)
 * Erro de rede não vira tela branca: mostra retry.
 */
export function RequireProfessor() {
  const { session, loading } = useAuth()
  const [estado, setEstado] = useState<Estado>('checando')
  const [tentativa, setTentativa] = useState(0)

  // Chaveia a checagem no id do usuário (estável), NÃO no objeto session:
  // onAuthStateChange emite nova session a cada refresh de token / foco de aba,
  // e re-checar aqui remontaria o app inteiro (perdendo data selecionada, scroll…).
  const userId = session?.user.id

  useEffect(() => {
    if (loading || !userId) return
    let vivo = true
    setEstado('checando')
    minhaAgendaSessao()
      .then((res) => {
        if (!vivo) return
        setEstado(isSemVinculo(res) ? 'sem_vinculo' : 'ok')
      })
      .catch(() => vivo && setEstado('erro'))
    return () => {
      vivo = false
    }
  }, [loading, userId, tentativa])

  // Professor autenticado e vinculado → liga o reenvio automático da fila
  // offline (gravações feitas sem rede sobem sozinhas).
  useEffect(() => {
    if (estado === 'ok') iniciarSincronizacaoFila()
  }, [estado])

  if (loading) return <Carregando />
  if (!session) return <Navigate to="/app/login" replace />
  if (estado === 'checando') return <Carregando />
  if (estado === 'sem_vinculo') return <VinculoPendentePage />

  if (estado === 'erro') {
    return (
      <AppFrame>
        <div className="flex flex-1 flex-col items-center justify-center gap-4 px-6 text-center">
          <div className="flex h-16 w-16 items-center justify-center rounded-full bg-danger-soft text-2xl text-danger-text">
            <i className="fa-solid fa-triangle-exclamation" aria-hidden="true" />
          </div>
          <p className="text-[14px] text-text-secondary">
            Não consegui carregar sua agenda agora. Verifica a conexão e tenta de novo.
          </p>
          <Button onClick={() => setTentativa((t) => t + 1)}>
            <i className="fa-solid fa-rotate-right" aria-hidden="true" /> Tentar de novo
          </Button>
        </div>
      </AppFrame>
    )
  }

  return <Outlet />
}
