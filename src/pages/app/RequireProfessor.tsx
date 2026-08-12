import { useEffect, useState } from 'react'
import { Navigate } from 'react-router-dom'
import { Button, FabioAvatar } from '../../components/ui'
import { useAuth } from '../../lib/auth'
import { isSemVinculo, minhaAgendaSessao, professoresParaLiberar } from '../../lib/api'
import { introVisto } from '../../features/onboarding/introState'
import { OnboardingGate } from '../../features/onboarding/OnboardingGate'
import { iniciarSincronizacaoFila, pararSincronizacaoFila } from '../../features/registro/uploadAudio'
import { AppFrame } from './AppFrame'
import VinculoPendentePage from './VinculoPendente'

type Estado = 'checando' | 'ok' | 'sem_vinculo' | 'e_coordenacao' | 'erro'

/** Tela de carregamento (nunca branca) enquanto o guard decide. */
function Carregando() {
  return (
    <AppFrame>
      <div className="flex flex-1 flex-col items-center justify-center gap-4">
        <FabioAvatar className="h-[84px] w-[84px] animate-bob" alt="Fábio" />
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
      .then(async (res) => {
        if (!vivo) return
        if (!isSemVinculo(res)) {
          setEstado('ok')
          return
        }
        // Sem professor não quer dizer sem acesso: a coordenação também entra
        // aqui, e o app dela não é a agenda do professor. Antes de mostrar
        // "falta ativar" — que pra ela seria mentira — pergunta se é do time da
        // coordenação. A pergunta só acontece neste ramo raro; quem é professor
        // nunca paga esse round-trip.
        try {
          await professoresParaLiberar()
          if (vivo) setEstado('e_coordenacao')
        } catch {
          if (vivo) setEstado('sem_vinculo')
        }
      })
      .catch(() => vivo && setEstado('erro'))
    return () => {
      vivo = false
    }
  }, [loading, userId, tentativa])

  // Professor autenticado e vinculado → liga o reenvio automático da fila
  // offline (gravações feitas sem rede sobem sozinhas).
  useEffect(() => {
    if (estado !== 'ok' || !userId) {
      pararSincronizacaoFila()
      return
    }
    iniciarSincronizacaoFila()
    return pararSincronizacaoFila
  }, [estado, userId])

  if (loading) return <Carregando />
  // Sem sessão: primeira vez no dispositivo vê o intro; quem já viu vai pro login.
  if (!session) return <Navigate to={introVisto() ? '/app/login' : '/app/intro'} replace />
  if (estado === 'checando') return <Carregando />
  // Coordenação não tem agenda de professor — tem equipe. Mandar pro painel em
  // vez de mostrar "falta ativar seu acesso", que no caso dela é falso e manda
  // procurar a coordenação... que é ela mesma.
  if (estado === 'e_coordenacao') return <Navigate to="/app/equipe" replace />
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

  // Vínculo ok → o porteiro do onboarding decide: primeiro acesso ou app normal.
  return <OnboardingGate />
}
