import type { ReactNode } from 'react'
import { InstallPrompt } from '../../features/pwa/InstallPrompt'

/**
 * Moldura mobile-first das telas do professor (mesmo shell do protótipo .phone).
 * Altura EXATA da viewport (h-dvh): o frame nunca cresce com o conteúdo —
 * só o miolo rola (overflow-y-auto) e a TabBar/Fab ficam fixas no rodapé.
 */
export function AppFrame({ children }: { children: ReactNode }) {
  return (
    <div className="flex h-dvh justify-center overflow-hidden bg-bg-app">
      <div className="relative flex h-dvh w-full max-w-[430px] flex-col overflow-hidden border-x border-border-subtle bg-bg-app">
        {children}
        <InstallPrompt />
      </div>
    </div>
  )
}
