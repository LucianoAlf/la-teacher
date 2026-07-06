import type { ReactNode } from 'react'

/** Moldura mobile-first das telas do professor (mesmo shell do protótipo .phone). */
export function AppFrame({ children }: { children: ReactNode }) {
  return (
    <div className="flex min-h-dvh justify-center bg-bg-app">
      <div className="relative flex min-h-dvh w-full max-w-[430px] flex-col overflow-hidden border-x border-border-subtle bg-bg-app">
        {children}
      </div>
    </div>
  )
}
