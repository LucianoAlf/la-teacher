import React from 'react'
import ReactDOM from 'react-dom/client'
import { RouterProvider } from 'react-router-dom'
// tokens.css é importado UMA única vez, aqui, antes de tudo.
import './styles/tokens.css'
import './styles/tailwind.css'
import { router } from './routes'
import { AuthProvider } from './lib/auth'
import { ThemeProvider, aplicarTemaInicial } from './lib/theme'
import { AtualizacaoDisponivel } from './features/pwa/AtualizacaoDisponivel'
// Efeito de boot: captura o beforeinstallprompt cedo (antes de qualquer tela).
import './features/pwa/installState'
import { pedirArmazenamentoPersistente } from './features/pwa/persistStorage'

// aplica o tema salvo antes do primeiro render (sem flash, vale em toda rota)
aplicarTemaInicial()
// pede ao navegador pra não descartar nosso storage sob pressão (ver arquivo —
// bug do "pede login toda vez que reabre" no piloto).
pedirArmazenamentoPersistente()

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <ThemeProvider>
      <AuthProvider>
        <RouterProvider router={router} future={{ v7_startTransition: true }} />
        <AtualizacaoDisponivel />
      </AuthProvider>
    </ThemeProvider>
  </React.StrictMode>,
)
