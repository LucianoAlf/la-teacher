import React from 'react'
import ReactDOM from 'react-dom/client'
import { RouterProvider } from 'react-router-dom'
// tokens.css é importado UMA única vez, aqui, antes de tudo.
import './styles/tokens.css'
import './styles/tailwind.css'
import { router } from './routes'
import { AuthProvider } from './lib/auth'

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <AuthProvider>
      <RouterProvider router={router} future={{ v7_startTransition: true }} />
    </AuthProvider>
  </React.StrictMode>,
)
