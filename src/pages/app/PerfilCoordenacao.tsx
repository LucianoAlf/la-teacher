import { useEffect, useState } from 'react'
import { CoordenacaoFrame, AvatarDoUsuario } from './CoordenacaoFrame'
import { EmptyState, Skeleton } from '../../components/ui'
import { useAuth } from '../../lib/auth'
import { meuPerfilCoordenacao, type MeuPerfilCoordenacao } from '../../lib/api'

/**
 * Perfil de quem é da coordenação.
 *
 * Existe porque o `/app/perfil` é do PROFESSOR: ele mora dentro do
 * `RequireProfessor` e lê a `app_meu_perfil`, que filtra por
 * `fn_professor_do_usuario()`. A Juliana, o Quintela, o Hugo e o Alf não têm
 * vínculo de professor — o link levava a dona do painel pra tela de quem não
 * tem acesso. A fonte aqui é a `app_meu_perfil_coordenacao` (069), que lê de
 * `usuarios`.
 *
 * É read-only por enquanto, e a tela DIZ isso em vez de mostrar campos que não
 * salvam. Botão que não faz nada ensina a não confiar no resto.
 */
export default function PerfilCoordenacaoPage() {
  const { signOut } = useAuth()
  const [perfil, setPerfil] = useState<MeuPerfilCoordenacao | null>(null)
  const [erro, setErro] = useState(false)

  useEffect(() => {
    let vivo = true
    meuPerfilCoordenacao()
      .then((p) => vivo && setPerfil(p))
      .catch(() => vivo && setErro(true))
    return () => {
      vivo = false
    }
  }, [])

  return (
    <CoordenacaoFrame titulo="Meu perfil">
      <div className="mx-auto max-w-[560px] p-4">
        {erro ? (
          <EmptyState
            icon="fa-solid fa-triangle-exclamation"
            title="Não consegui abrir seu perfil"
            description="Recarrega a página e tenta de novo."
          />
        ) : !perfil ? (
          <div className="space-y-3">
            <Skeleton className="h-[84px] w-[84px] rounded-full" />
            <Skeleton className="h-5 w-48" />
            <Skeleton className="h-24 w-full" />
          </div>
        ) : (
          <>
            <div className="mb-5 flex items-center gap-4">
              <AvatarDoUsuario perfil={perfil} tamanho="lg" />
              <div className="min-w-0">
                <h2 className="truncate text-[19px] font-bold text-text-primary">{perfil.nome}</h2>
                <p className="text-[13px] text-text-secondary">
                  {perfil.cargo || 'Coordenação'} · {perfil.alcance}
                </p>
              </div>
            </div>

            <dl className="overflow-hidden rounded-md border border-border-subtle bg-bg-surface">
              <Campo rotulo="Como te chamam" valor={perfil.apelido} />
              <Campo rotulo="E-mail" valor={perfil.email} />
              <Campo rotulo="Telefone" valor={perfil.telefone} />
              <Campo rotulo="Cargo" valor={perfil.cargo} />
            </dl>

            <p className="mt-3 text-[12px] text-text-muted">
              Editar o perfil e trocar a foto ainda não têm porta no app. Por enquanto isso é
              alterado no LA Report.
            </p>

            <button
              onClick={() => void signOut()}
              className="mt-6 text-[13px] text-danger-text hover:underline"
            >
              Sair da conta
            </button>
          </>
        )}
      </div>
    </CoordenacaoFrame>
  )
}

/** Campo vazio aparece como "não informado" — não some. Sumir esconde o buraco. */
function Campo({ rotulo, valor }: { rotulo: string; valor: string | null }) {
  return (
    <div className="flex items-center justify-between gap-3 border-b border-border-subtle px-3.5 py-3 last:border-b-0">
      <dt className="shrink-0 text-[12.5px] text-text-secondary">{rotulo}</dt>
      <dd className={`truncate text-[13px] ${valor ? 'text-text-primary' : 'text-text-muted'}`}>
        {valor || 'não informado'}
      </dd>
    </div>
  )
}
