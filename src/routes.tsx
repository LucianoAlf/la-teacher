import { createBrowserRouter, Navigate, Outlet, useLocation } from 'react-router-dom'
import DesignSystemPage from './pages/dev/DesignSystem'
import ExperimentalFichaPage from './pages/app/ExperimentalFicha'
import ExperimentalRegistrarPage from './pages/app/ExperimentalRegistrar'
import ExperimentalConfirmarPage from './pages/app/ExperimentalConfirmar'
import ExperimentalFaltaPage from './pages/app/ExperimentalFalta'
import EquipePage from './pages/app/Equipe'
import CoordenacaoPage from './pages/app/Coordenacao'
import PerfilCoordenacaoPage from './pages/app/PerfilCoordenacao'
import CoordenacaoFeedbackPage from './pages/app/CoordenacaoFeedback'
import { RequireAdmin } from './pages/app/RequireAdmin'
import LoginPage from './pages/app/Login'
import NovaSenhaPage from './pages/app/NovaSenha'
import IntroPage from './pages/app/Intro'
import HomePage from './pages/app/Home'
import AgendaPage from './pages/app/Agenda'
import AlunosPage from './pages/app/Alunos'
import FeedbackPage from './pages/app/Feedback'
import GravarAulaPage from './features/registro/GravarAula'
import ProcessandoPage from './features/registro/Processando'
import ConfirmarPage from './features/registro/Confirmar'
import ChamadaPage from './features/chamada/Chamada'
import ChatFabioPage from './features/fabio/ChatFabio'
import DevolutivasPage from './pages/app/Devolutivas'
import PontoPage from './pages/app/Ponto'
import PerfilPage from './pages/app/Perfil'
import AlunoDetalhePage from './pages/app/AlunoDetalhe'
import TurmaHistoricoPage from './pages/app/TurmaHistorico'
import { RequireProfessor } from './pages/app/RequireProfessor'
import { useAuth } from './lib/auth'

/**
 * Chegou por link de recuperação de senha? Então a única tela que importa é a
 * de definir a senha nova — não interessa em que rota o link tenha caído.
 *
 * Isso existe porque o Supabase só honra o `redirectTo` se ele estiver na
 * allowlist do projeto; fora dela, ele manda o professor pra Site URL. Em vez
 * de deixar o fluxo depender de uma configuração de painel (que quebra calado
 * e ninguém percebe), o app detecta a recuperação e desvia sozinho.
 *
 * Espera o `loading` de propósito: o supabase-js ainda está lendo o token do
 * hash da URL nesse intervalo. Redirecionar antes disso descartaria o hash e
 * queimaria o link, que é de uso único.
 */
function GuardRecuperacao() {
  const { recuperacao, loading } = useAuth()
  const { pathname } = useLocation()
  if (!loading && recuperacao && pathname !== '/app/nova-senha') {
    return <Navigate to="/app/nova-senha" replace />
  }
  return <Outlet />
}

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
    {
      // Envolve TUDO: o link de recuperação pode cair em qualquer rota, então
      // o desvio tem que estar acima de todas elas.
      element: <GuardRecuperacao />,
      children: [
        { path: '/', element: <Navigate to="/app" replace /> },
        { path: '/app/intro', element: <IntroRoute /> },
        { path: '/app/login', element: <LoginRoute /> },
        // Fora do guard de professor de propósito: o link de recuperação chega
        // COM sessão, então tanto o RequireProfessor quanto o redirect do
        // LoginRoute jogariam o professor pro /app antes de ele digitar a senha
        // nova — e o link é de uso único, não daria pra tentar de novo.
        { path: '/app/nova-senha', element: <NovaSenhaPage /> },
        {
          // Guard por sessão + vínculo de professor.
          element: <RequireProfessor />,
          children: [
            { path: '/app', element: <HomePage /> },
            { path: '/app/agenda', element: <AgendaPage /> },
            { path: '/app/alunos', element: <AlunosPage /> },
            { path: '/app/feedback', element: <FeedbackPage /> },
            { path: '/app/aluno/:alunoId', element: <AlunoDetalhePage /> },
            { path: '/app/turma/:turmaNome', element: <TurmaHistoricoPage /> },
            { path: '/app/chamada/:aulaId', element: <ChamadaPage /> },
            { path: '/app/fabio', element: <ChatFabioPage /> },
            { path: '/app/devolutivas', element: <DevolutivasPage /> },
            { path: '/app/ponto', element: <PontoPage /> },
            { path: '/app/perfil', element: <PerfilPage /> },
            { path: '/app/gravar', element: <GravarAulaPage /> },
            { path: '/app/gravar/:aulaId', element: <GravarAulaPage /> },
            { path: '/app/processando/:audioId', element: <ProcessandoPage /> },
            { path: '/app/confirmar/:registroId', element: <ConfirmarPage /> },
          // Ciclo da aula experimental (migrations 034-047). A chave da rota é
          // o VÍNCULO lead↔aula, não a aula: é ele que amarra registro,
          // presença e aviso ao comercial.
          { path: '/app/experimental/:vinculoId', element: <ExperimentalFichaPage /> },
          { path: '/app/experimental/:vinculoId/registrar', element: <ExperimentalRegistrarPage /> },
          { path: '/app/experimental/:vinculoId/confirmar', element: <ExperimentalConfirmarPage /> },
          // Falta tem rota própria porque é caminho próprio: sem campos, e com
          // o que vai acontecer escrito antes do toque que manda WhatsApp.
          { path: '/app/experimental/:vinculoId/falta', element: <ExperimentalFaltaPage /> },
          ],
        },
        {
          // Guard PRÓPRIO, fora do RequireProfessor: o admin da escola não tem
          // professor vinculado, e o guard do professor manda quem não tem pra
          // "Vínculo pendente" — o dono do painel bateria na tela de quem não
          // tem acesso.
          element: <RequireAdmin />,
          children: [
            { path: '/app/coordenacao', element: <CoordenacaoPage /> },
            // Bloco 2 do painel: o semáforo do mês — e o único lugar onde a
            // observação escrita pelo professor tem leitor (077).
            { path: '/app/coordenacao/feedback', element: <CoordenacaoFeedbackPage /> },
            // Perfil PRÓPRIO da coordenação: o /app/perfil mora dentro do
            // RequireProfessor e lê a RPC do professor, que devolve vazio pra
            // quem não tem vínculo — era a dona do painel batendo na tela de
            // quem não tem acesso.
            { path: '/app/coordenacao/perfil', element: <PerfilCoordenacaoPage /> },
            { path: '/app/equipe', element: <EquipePage /> },
          ],
        },
        // Vitrine do design system — SÓ em desenvolvimento. Em produção a rota
        // nem existe (cai no catch-all → /app), pra nenhum professor tropeçar.
        ...(import.meta.env.DEV
          ? [{ path: '/dev/ds', element: <DesignSystemPage /> }]
          : []),
        { path: '*', element: <Navigate to="/app" replace /> },
      ],
    },
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
