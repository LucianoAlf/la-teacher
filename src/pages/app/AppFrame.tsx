import type { ReactNode } from 'react'
import { InstallPrompt } from '../../features/pwa/InstallPrompt'

/**
 * Moldura mobile-first das telas do professor (mesmo shell do protótipo .phone).
 * Altura = 100% do `#root` (que já é a viewport, ver tailwind.css): a moldura
 * cabe na área visível — só o miolo rola (overflow-y-auto) e a TabBar/Fab ficam
 * fixas no rodapé. Não usa mais h-svh: ao redimensionar a janela a unidade de
 * viewport podia ficar atrás do container e abrir tarja embaixo.
 */
export function AppFrame({ children }: { children: ReactNode }) {
  return (
    <div className="flex h-full min-h-0 w-full flex-1 justify-center overflow-hidden bg-bg-app">
      <div className="relative flex h-full min-h-0 w-full max-w-[430px] flex-col overflow-hidden border-x border-border-subtle bg-bg-app">
        {children}
        <InstallPrompt />
      </div>
    </div>
  )
}
