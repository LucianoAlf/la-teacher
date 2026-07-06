import { createBrowserRouter, Navigate } from 'react-router-dom'
import DesignSystemPage from './pages/dev/DesignSystem'
import LoginPage from './pages/app/Login'
import HomePage from './pages/app/Home'
import { RequireProfessor } from './pages/app/RequireProfessor'
import { useAuth } from './lib/auth'

/** Se já há sessão, o login redireciona pro app (o guard decide o resto). */
function LoginRoute() {
  const { session, loading } = useAuth()
  if (!loading && session) return <Navigate to="/app" replace />
  return <LoginPage />
}

export const router = createBrowserRouter(
  [
    { path: '/', element: <Navigate to="/app" replace /> },
    { path: '/app/login', element: <LoginRoute /> },
    {
      // Guard por sessão + vínculo de professor.
      element: <RequireProfessor />,
      children: [{ path: '/app', element: <HomePage /> }],
    },
    // Vitrine do design system — pública (sem guard), útil no dev.
    { path: '/dev/ds', element: <DesignSystemPage /> },
    { path: '*', element: <Navigate to="/app" replace /> },
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
