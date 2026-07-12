import React from 'react'
import ReactDOM from 'react-dom/client'
import { RouterProvider } from 'react-router-dom'
// tokens.css é importado UMA única vez, aqui, antes de tudo.
import './styles/tokens.css'
import './styles/tailwind.css'
import { router } from './routes'
import { AuthProvider } from './lib/auth'
import { ThemeProvider, aplicarTemaInicial } from './lib/theme'
// Efeito de boot: captura o beforeinstallprompt cedo (antes de qualquer tela).
import './features/pwa/installState'

// aplica o tema salvo antes do primeiro render (sem flash, vale em toda rota)
aplicarTemaInicial()

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <ThemeProvider>
      <AuthProvider>
        <RouterProvider router={router} future={{ v7_startTransition: true }} />
      </AuthProvider>
    </ThemeProvider>
  </React.StrictMode>,
)
