import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { CoordenacaoFrame, AvatarDoUsuario } from './CoordenacaoFrame'
import { EmptyState, LinhaInfo, SeloVersao, Skeleton, TituloSecao } from '../../components/ui'
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
 *
 * Cartão, linhas, selo de versão e botão de voltar são os mesmos componentes do
 * Meu perfil do professor. A primeira versão desta tela tinha uma linha de
 * informação própria, um selo de build próprio (que omitia o número da versão)
 * e um link de texto no lugar do botão de voltar.
 */
export default function PerfilCoordenacaoPage() {
  const navigate = useNavigate()
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
    <CoordenacaoFrame
      titulo="Meu perfil"
      icone="fa-solid fa-user"
      aoVoltar={() => navigate('/app/coordenacao')}
    >
      <div className="mx-auto max-w-[560px] px-5 pb-5 pt-3">
        {erro ? (
          <EmptyState
            icon="fa-solid fa-triangle-exclamation"
            title="Não consegui abrir seu perfil"
            description="Recarrega a página e tenta de novo."
          />
        ) : !perfil ? (
          <div className="space-y-3">
            <Skeleton className="h-[92px] w-[92px] rounded-full" />
            <Skeleton className="h-5 w-48" />
            <Skeleton className="h-24 w-full rounded-lg" />
          </div>
        ) : (
          <>
            <div className="mb-5 flex items-center gap-4">
              <AvatarDoUsuario perfil={perfil} tamanho="lg" />
              <div className="min-w-0">
                <h2 className="truncate text-[17px] font-extrabold tracking-[-.3px] text-text-primary">
                  {perfil.nome}
                </h2>
                <p className="text-[12.5px] text-text-secondary">
                  {perfil.cargo || 'Coordenação'} · {perfil.alcance}
                </p>
              </div>
            </div>

            <div className="overflow-hidden rounded-lg border border-border-subtle bg-bg-surface shadow-card">
              <TituloSecao>Informações da conta</TituloSecao>
              <LinhaInfo rotulo="Apelido" valor={perfil.apelido} />
              <LinhaInfo rotulo="E-mail" valor={perfil.email} />
              <LinhaInfo rotulo="WhatsApp" valor={perfil.telefone} />
              <LinhaInfo rotulo="Cargo" valor={perfil.cargo} />
            </div>

            <p className="mt-3 text-[12px] leading-relaxed text-text-muted">
              Editar o perfil e trocar a foto ainda não têm porta no app. Por enquanto isso é
              alterado no LA Report.
            </p>

            <button
              onClick={() => void signOut()}
              className="mt-6 inline-flex items-center gap-3 text-sm text-danger-text"
            >
              <i
                className="fa-solid fa-arrow-right-from-bracket w-[18px] text-center text-[13px]"
                aria-hidden="true"
              />
              Sair
            </button>

            <SeloVersao />
          </>
        )}
      </div>
    </CoordenacaoFrame>
  )
}
