import type { ReactNode } from 'react'
import { InstallPrompt } from '../../features/pwa/InstallPrompt'

/**
 * Moldura mobile-first das telas do professor (mesmo shell do protótipo .phone).
 * Altura ESTÁVEL da viewport (h-svh): a moldura sempre cabe na área visível — só
 * o miolo rola (overflow-y-auto) e a TabBar/Fab ficam fixas no rodapé. Usa svh (e
 * não dvh) porque o documento é travado em overflow:hidden (ver tailwind.css): a
 * altura pequena/estável garante que o rodapé nunca fique preso fora da tela.
 */
export function AppFrame({ children }: { children: ReactNode }) {
  return (
    <div className="flex h-svh justify-center overflow-hidden bg-bg-app">
      <div className="relative flex h-svh w-full max-w-[430px] flex-col overflow-hidden border-x border-border-subtle bg-bg-app">
        {children}
        <InstallPrompt />
      </div>
    </div>
  )
}
