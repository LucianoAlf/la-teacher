import { Button, EmptyState } from '../../components/ui'
import { useAuth } from '../../lib/auth'
import { AppFrame } from './AppFrame'

/**
 * Tela para usuário autenticado mas SEM professor vinculado
 * (app_minha_agenda devolveu {erro:'sem_professor_vinculado'}).
 * Nunca tela branca: dá direção e botão de sair.
 */
export default function VinculoPendentePage() {
  const { session, signOut } = useAuth()

  return (
    <AppFrame>
      <div className="flex flex-1 flex-col justify-center">
        <EmptyState
          icon="fa-solid fa-id-badge"
          title="Falta ativar seu acesso"
          description="Seu login funcionou, mas você ainda não está vinculado a um professor. Fala com a coordenação da sua unidade pra ativar — aí sua agenda aparece aqui."
          action={
            <Button variant="ghost" onClick={signOut}>
              <i className="fa-solid fa-arrow-right-from-bracket" aria-hidden="true" /> Sair
            </Button>
          }
        />
        {session?.user.email && (
          <p className="pb-8 text-center text-[12px] text-text-muted">
            Conectado como {session.user.email}
          </p>
        )}
      </div>
    </AppFrame>
  )
}
