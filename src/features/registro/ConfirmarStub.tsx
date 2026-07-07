import { useNavigate, useParams } from 'react-router-dom'
import { Button, EmptyState, ScreenHeader } from '../../components/ui'
import { AppFrame } from '../../pages/app/AppFrame'

/** /app/confirmar/:registroId — stub do P5; a tela real (tronco+fatias) é o P7. */
export default function ConfirmarStubPage() {
  const { registroId } = useParams()
  const navigate = useNavigate()

  return (
    <AppFrame>
      <ScreenHeader title="Confirmação" onBack={() => navigate('/app')} />
      <div className="flex flex-1 flex-col justify-center">
        <EmptyState
          icon="fa-solid fa-clipboard-check"
          title="Registro pronto! 🎉"
          description="O Fábio estruturou sua aula. A tela de Confirmação (tronco + fatias, edição e cutucadas) chega no próximo passo do Sprint 3."
          action={
            <Button variant="ghost" size="sm" onClick={() => navigate('/app')}>
              Voltar ao início
            </Button>
          }
        />
        {registroId && (
          <p className="pb-6 text-center font-mono text-[10.5px] tracking-[.3px] text-text-muted">
            registro {registroId}
          </p>
        )}
      </div>
    </AppFrame>
  )
}
