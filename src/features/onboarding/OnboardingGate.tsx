import { useEffect, useState } from 'react'
import { Outlet } from 'react-router-dom'
import { FabioAvatar } from '../../components/ui'
import { AppFrame } from '../../pages/app/AppFrame'
import { meuOnboarding, type MeuOnboarding } from '../../lib/api'
import { OnboardingFlow } from './OnboardingFlow'

type Estado = 'carregando' | 'onboarding' | 'pronto'

/**
 * Porteiro do primeiro acesso, DEPOIS do vínculo confirmado (dentro do guard).
 * Chama app_meu_onboarding() uma única vez:
 *  - concluido        → app normal (<Outlet/>)
 *  - não concluído    → fluxo de onboarding (WhatsApp + boas-vindas)
 * FAIL-OPEN: se a RPC falhar, o app abre normal. Onboarding é acolhida, não
 * pode travar o professor que abriu o app saindo da sala.
 */
export function OnboardingGate() {
  const [estado, setEstado] = useState<Estado>('carregando')
  const [dados, setDados] = useState<MeuOnboarding | null>(null)

  useEffect(() => {
    let vivo = true
    meuOnboarding()
      .then((d) => {
        if (!vivo) return
        setDados(d)
        setEstado(d.concluido ? 'pronto' : 'onboarding')
      })
      .catch(() => vivo && setEstado('pronto')) // fail-open
    return () => {
      vivo = false
    }
  }, [])

  if (estado === 'carregando') {
    return (
      <AppFrame>
        <div className="flex flex-1 flex-col items-center justify-center gap-4">
          <FabioAvatar className="h-[84px] w-[84px] animate-bob" alt="Fábio" />
          <p className="text-[13px] text-text-secondary">Preparando seu primeiro acesso…</p>
        </div>
      </AppFrame>
    )
  }

  if (estado === 'onboarding' && dados) {
    return <OnboardingFlow dados={dados} onConcluir={() => setEstado('pronto')} />
  }

  return <Outlet />
}
