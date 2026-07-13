import { createBrowserRouter, Navigate } from 'react-router-dom'
import DesignSystemPage from './pages/dev/DesignSystem'
import LoginPage from './pages/app/Login'
import IntroPage from './pages/app/Intro'
import HomePage from './pages/app/Home'
import AgendaPage from './pages/app/Agenda'
import AlunosPage from './pages/app/Alunos'
import GravarAulaPage from './features/registro/GravarAula'
import ProcessandoPage from './features/registro/Processando'
import ConfirmarPage from './features/registro/Confirmar'
import ChamadaPage from './features/chamada/Chamada'
import PontoPage from './pages/app/Ponto'
import PerfilPage from './pages/app/Perfil'
import AlunoDetalhePage from './pages/app/AlunoDetalhe'
import { RequireProfessor } from './pages/app/RequireProfessor'
import { useAuth } from './lib/auth'

/** Se já há sessão, o login redireciona pro app (o guard decide o resto). */
function LoginRoute() {
  const { session, loading } = useAuth()
  if (!loading && session) return <Navigate to="/app" replace />
  return <LoginPage />
}

/** Intro é pré-login: quem já tem sessão não precisa ver — vai direto pro app. */
function IntroRoute() {
  const { session, loading } = useAuth()
  if (!loading && session) return <Navigate to="/app" replace />
  return <IntroPage />
}

export const router = createBrowserRouter(
  [
    { path: '/', element: <Navigate to="/app" replace /> },
    { path: '/app/intro', element: <IntroRoute /> },
    { path: '/app/login', element: <LoginRoute /> },
    {
      // Guard por sessão + vínculo de professor.
      element: <RequireProfessor />,
      children: [
        { path: '/app', element: <HomePage /> },
        { path: '/app/agenda', element: <AgendaPage /> },
        { path: '/app/alunos', element: <AlunosPage /> },
        { path: '/app/aluno/:alunoId', element: <AlunoDetalhePage /> },
        { path: '/app/chamada/:aulaId', element: <ChamadaPage /> },
        { path: '/app/ponto', element: <PontoPage /> },
        { path: '/app/perfil', element: <PerfilPage /> },
        { path: '/app/gravar', element: <GravarAulaPage /> },
        { path: '/app/gravar/:aulaId', element: <GravarAulaPage /> },
        { path: '/app/processando/:audioId', element: <ProcessandoPage /> },
        { path: '/app/confirmar/:registroId', element: <ConfirmarPage /> },
      ],
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
