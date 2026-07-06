import { createBrowserRouter, Navigate } from 'react-router-dom'
import DesignSystemPage from './pages/dev/DesignSystem'

// P2 (Sprint 2): guard por sessão + perfil (professor | coordenação).
// Por ora, só a vitrine do design system.
export const router = createBrowserRouter(
  [
    { path: '/', element: <Navigate to="/dev/ds" replace /> },
    { path: '/dev/ds', element: <DesignSystemPage /> },
  ],
  {
    // opt-in antecipado no comportamento do React Router v7 (console limpo)
    future: {
      v7_relativeSplatPath: true,
      v7_fetcherPersist: true,
      v7_normalizeFormMethod: true,
      v7_partialHydration: true,
      v7_skipActionErrorRevalidation: true,
    },
  },
)
