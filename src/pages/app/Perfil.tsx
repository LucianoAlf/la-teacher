import { useNavigate } from 'react-router-dom'
import { ScreenHeader } from '../../components/ui'
import { useAuth } from '../../lib/auth'
import { AppFrame } from './AppFrame'

/**
 * /app/perfil — "Meu perfil" (espelha o LA Organizer).
 *
 * SHELL: os dados de conta (nome, email) vêm da sessão — só leitura.
 * As partes editáveis (nome preferido, bio, foto) dependem de campos + RPC
 * que ainda NÃO existem no banco → reportado pro Claude Web. Assim que o
 * contrato (`app_meu_perfil` / `app_atualizar_perfil` + colunas) existir,
 * esta tela ganha os campos editáveis e o "Salvar perfil".
 */
export default function PerfilPage() {
  const navigate = useNavigate()
  const { session } = useAuth()

  const email = session?.user.email ?? '—'
  const nome = (session?.user.user_metadata?.name as string | undefined) ?? email.split('@')[0]
  const inicial = nome.charAt(0).toUpperCase()

  return (
    <AppFrame>
      <ScreenHeader
        title="Meu perfil"
        subtitle="O que o Fábio usa pra te conhecer melhor"
        onBack={() => navigate(-1)}
      />

      <div className="flex-1 overflow-y-auto px-4 pb-10 pt-1">
        {/* Foto */}
        <div className="mb-3 flex flex-col items-center gap-3 rounded-lg border border-border-subtle bg-bg-surface px-4 py-6">
          <div className="flex h-[92px] w-[92px] items-center justify-center rounded-full bg-[var(--avatar-grad)] text-3xl font-extrabold text-[color:var(--avatar-fg)]">
            {inicial}
          </div>
          <span className="text-[12.5px] text-text-secondary">Foto chega junto com o Fábio</span>
        </div>

        {/* Informações da conta — só leitura */}
        <div className="overflow-hidden rounded-lg border border-border-subtle bg-bg-surface">
          <div className="border-b border-border-subtle px-[14px] py-3">
            <span className="text-[11px] font-bold uppercase tracking-[.5px] text-text-secondary">Informações da conta</span>
          </div>
          <LinhaInfo rotulo="Nome" valor={nome} />
          <LinhaInfo rotulo="E-mail" valor={email} />
        </div>

        {/* Editável — pendente do banco */}
        <div className="mt-3 flex items-start gap-2 rounded-md border border-border-subtle bg-bg-inset px-3 py-[11px] text-[12.5px] leading-relaxed text-text-secondary">
          <i className="fa-solid fa-wand-magic-sparkles mt-[2px] text-brand-text" aria-hidden="true" />
          <span>
            Em breve você vai poder dizer <b>como quer ser chamado</b> e escrever uma <b>bio</b> (o que o Fábio deve
            saber sobre você — instrumento, preferências). Estou montando essa parte com o time do banco.
          </span>
        </div>
      </div>
    </AppFrame>
  )
}

function LinhaInfo({ rotulo, valor }: { rotulo: string; valor: string }) {
  return (
    <div className="flex items-center gap-3 border-b border-border-subtle px-[14px] py-3 last:border-b-0">
      <span className="w-[64px] flex-none text-[12.5px] font-bold text-text-secondary">{rotulo}</span>
      <span className="min-w-0 flex-1 truncate text-sm text-text-primary">{valor}</span>
    </div>
  )
}
